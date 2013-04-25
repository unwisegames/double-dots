//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import "RenderController.h"
#import "ChipmunkDebugDrawDoubleDots.h"
#import "GameState.h"

#import "MathUtil.h"
#import "Texture2D.h"
#import "Color.h"

#include "chipmunk.h"

#include <array>
#include <mutex>
#include <vector>
#include <unordered_map>
#include <memory>
#include <algorithm>

using namespace brac;

#define BRICABRAC_SHADER_NAME Matte
#include "LoadShaders.h"
#define BRICABRAC_SHADER_NAME Border
#include "LoadShaders.h"
#define BRICABRAC_SHADER_NAME Dots
#include "LoadShaders.h"
#define BRICABRAC_SHADER_NAME Board
#include "LoadShaders.h"

static bool iPad = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;

static constexpr float gEdgeThickness   = 0.5;
static constexpr float gScaleLimit      = 2;
static           float gLogScaleLimit   = std::log(gScaleLimit);

static std::array<Color, 5> selectionColors = {{
    {1  , 0.7, 0.1},
    {0.5, 0.7, 1  },
    {0.8, 0.4, 1  },
    {0.5, 0.8, 0.3},
    {0.8, 0.3, 0.2},
}};

typedef std::unordered_map<size_t, BorderVertexBuffer> Borders;

struct RgbaPixel {
    GLubyte r, g, b, a;
};

@interface RenderController () {
    EAGLContext *_context;

    std::unique_ptr<MatteProgram    > _matte    ;
    std::unique_ptr<BorderProgram   > _border   ;
    std::unique_ptr<DotsProgram     > _dots     ;
    std::unique_ptr<BoardProgram    > _board    ;

    int _nBoardRows, _nBoardCols;
    float _viewHeight;

    mat4 _pmvMatrix, _pick;
    mat3 _normalMatrix;
    float _rotation;
    Texture2D * _atlas, * _dotStates, * _surface, * _dimple, * _edging;
    RgbaPixel _dotsData[16 * 16];
    std::vector<DotsVertex> _dotsVertsData;
    DotsVertexBuffer _vboDots;
    ElementBuffer<> _eboDots;
    BoardVertexBuffer _vboBoardInterior, _vboBoardEdge;
    size_t _colorSet;

    Borders _borders;

    std::weak_ptr<ShapeMatches> _shapeMatchesToHint;
    int _nextMatchToHint;
    float _hintIntensity;
    std::array<BorderVertexBuffer, 2> _vboHints;

    std::unique_ptr<ChipmunkDebugDrawDoubleDots> _debugDraw;

    // Zoom/pan
    cpSpace         * _space;
    cpBody          * _anchor, * _clamps[4], * _finger;
    cpConstraint    * _drag;
    cpVect _dragStart;
    std::vector<cpShape *> reportables;
}
@property (nonatomic, strong) IBOutlet UITapGestureRecognizer * tapGestureRecognizer;
@end

@implementation RenderController

@synthesize game = _game, colorSet = _colorSet, tapGestureRecognizer = _tapGestureRecognizer;

- (std::unique_ptr<vec2>)touchPosition:(CGPoint)loc {
    auto size = self.view.bounds.size;

    vec2 p = (_pick * vec3{2 * loc.x/size.width - 1, 1 - 2 * loc.y/size.height, 0}).xy();
    p = {std::floor(p.x), std::floor(p.y)};
    return std::unique_ptr<vec2>{0 <= p.x && p.x < _nBoardCols && 0 <= p.y && p.y < _nBoardRows ? new vec2{p} : nullptr};
}

- (std::vector<GameState::Touch>)touchPositions:(NSSet *)touches {
    std::vector<GameState::Touch> result; result.reserve(touches.count);
    for (UITouch * touch in touches)
        if (auto p = [self touchPosition:[touch locationInView:self.view]])
            result.push_back(GameState::Touch{(__bridge void const *)touch, *p});
    return result;
}

- (std::vector<BorderVertex>)prepareSelectionBorder:(brac::BitBoard const &)bb {
    std::vector<BorderVertex> border;

    vec2 Ci{0, 0}, I{0.25, 0.25}, Cs{0.25, 0}, S{0.5, 0.25}, Co{0.5, 0}, O{0.75, 0.25};
    vec2 texcoords[] = {Cs, O, S, I, I};

    enum CornerType { none, outer, straight, inner, own_inner };
    auto cornerType = [](bool cw, bool diag, bool ccw) {
        switch (cw + 2*diag + 4*ccw) {
            case 0 : return outer;
            case 1 : return straight;
            case 2 : return outer;
            case 3 : return inner;
            case 4 : return straight;
            case 5 : return own_inner;
            case 6 : return inner;
            default: return none;
        }
    };

    auto triangle = [&](vec2 a, vec2 b, vec2 c, CornerType edge, CornerType corner) {
        BorderVertex vs[] = {
            {a, corner == own_inner && edge == none ? Ci : Co},
            {b, texcoords[edge]},
            {c, texcoords[corner]},
        };
        if (cross(b, c) < 0)
            std::swap(vs[1], vs[2]);
        border.insert(end(border), std::begin(vs), std::end(vs));
    };

    for (int y = 0; y < _nBoardRows; ++y)
        for (int x = 0; x < _nBoardCols; ++x) {
            vec2 c{0.5 + x, 0.5 + y};
            uint64_t hood = bb.shiftWS(x - 1, y - 1).a;
            if (hood & (2ULL<<16)) {
                bool SW = hood &  1ULL;
                bool S  = hood &  2ULL;
                bool SE = hood &  4ULL;
                bool W  = hood & (1ULL<<16);
                bool E  = hood & (4ULL<<16);
                bool NW = hood & (1ULL<<32);
                bool N  = hood & (2ULL<<32);
                bool NE = hood & (4ULL<<32);
                CornerType SWc = cornerType(W, SW, S);
                CornerType SEc = cornerType(S, SE, E);
                CornerType NEc = cornerType(E, NE, N);
                CornerType NWc = cornerType(N, NW, W);

                // Edge types
                CornerType Ne = N ? none : straight;
                CornerType Se = S ? none : straight;
                CornerType Ee = E ? none : straight;
                CornerType We = W ? none : straight;

                triangle(c, c + vec2{-0.5,  0   }, c + vec2{-0.5, -0.5}, We, SWc);
                triangle(c, c + vec2{-0.5,  0   }, c + vec2{-0.5,  0.5}, We, NWc);
                triangle(c, c + vec2{ 0   , -0.5}, c + vec2{ 0.5, -0.5}, Se, SEc);
                triangle(c, c + vec2{ 0   , -0.5}, c + vec2{-0.5, -0.5}, Se, SWc);
                triangle(c, c + vec2{ 0.5,  0   }, c + vec2{ 0.5, -0.5}, Ee, SEc);
                triangle(c, c + vec2{ 0.5,  0   }, c + vec2{ 0.5,  0.5}, Ee, NEc);
                triangle(c, c + vec2{ 0   ,  0.5}, c + vec2{ 0.5,  0.5}, Ne, NEc);
                triangle(c, c + vec2{ 0   ,  0.5}, c + vec2{-0.5,  0.5}, Ne, NWc);
            }
        }
    if (border.empty()) {
        NSLog(@"Huh?");
    }
    return border;
}

- (void)updateBoardColors:(bool)swap {
    _colorSet ^= swap;

    auto vi = begin(_dotsVertsData);
    auto const & board = _game->board();
    for (size_t y = 0; y < _nBoardRows; ++y)
        for (size_t x = 0; x < _nBoardCols; ++x) {
            int c = board.color(x, y);
            float s = 0.25;
            if (c == -1) { c = 0; s = 0; }
            vec2 tc = DotTexCoords::dots[_colorSet][c];
            vi++->texcoord = tc + vec2{0, s};
            vi++->texcoord = tc + vec2{s, s};
            vi++->texcoord = tc + vec2{s, 0};
            vi++->texcoord = tc;
        }
    assert(vi == std::end(_dotsVertsData));
    _vboDots.subData(_dotsVertsData);
    self.paused = NO;
}

- (void)setGame:(std::shared_ptr<GameState>)game {
    _game = game;

    _game->onSelectionChanged([=]{
        auto const & sels = _game->sels();

        // Remove deselected borders.
        for (auto i = begin(_borders); i != end(_borders);) {
            auto s = sels.find(i->first);
            if (s != end(sels) && s->second.has_border()) {
                ++i;
            } else {
                i = _borders.erase(i);
            }
        }

        // Update modified borders and create new borders.
        for (auto const & sel : sels)
            if (sel.second.has_border()) {
                auto verts = [self prepareSelectionBorder:sel.second.is_selected];
                auto i = _borders.find(sel.first);
                if (i == end(_borders)) {
                    _borders.emplace(sel.first, BorderVertexBuffer{verts});
                } else {
                    i->second.data(verts);
                }
            }
        self.paused = NO;
    });

    _game->onBoardChanged([=]{
        auto mask = _game->board().computeMask();
        for (size_t y = 0; y < 16; ++y)
            for (size_t x = 0; x < 16; ++x) {
                GLubyte v = mask.isSet(x, y) * 0xff;
                _dotsData[16 * y + x] = {v, v, v, v};
            }

        Texture2DData data{_dotsData, kTexture2DPixelFormat_RGBA8888, 16, 16, {16, 16}};
        [Texture2D pasteIntoTexture:_dotStates.name data:data atXOffset:0 atYOffset:0];
        self.paused = NO;
    });

    _game->onCancelTapGesture([=]{
        _tapGestureRecognizer.enabled = NO;
        _tapGestureRecognizer.enabled = YES;
    });

    [self updateBoardColors:false];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self becomeFirstResponder];

    _nBoardRows = iPad ? 16 : 7;
    _nBoardCols = iPad ? 16 : 8;
    _viewHeight = _nBoardRows + 2 * gEdgeThickness;

    _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    if (!_context) {
        NSLog(@"Failed to create ES context");
    }

    GLKView *view = (GLKView *)self.view;
    view.context = _context;
    view.drawableMultisample = GLKViewDrawableMultisample4X;
    self.preferredFramesPerSecond = 60;

    // Prepare zoom/pan clamps.

    auto cpRectShapeNew = [](cpBody *body, float halfW, float halfH, cpVect offset) {
        cpVect verts[4] = { {-halfW, -halfH}, {-halfW, halfH}, {halfW, halfH}, {halfW, -halfH} };
        return cpPolyShapeNew(body, 4, verts, offset);
    };

    cpInitChipmunk();

    _debugDraw.reset(new ChipmunkDebugDrawDoubleDots);

    _space = cpSpaceNew();
    auto world = cpSpaceGetStaticBody(_space);

    _anchor = cpBodyNew(0.1, 1);
    cpSpaceAddBody(_space, _anchor);

    _finger = cpBodyNewStatic();

//    auto clamp = [&](cpVect const & pos) {
//        auto body = cpBodyNew(1, 1);
//        cpBodySetPos(body, pos);
//        auto disk = cpCircleShapeNew(body, 1, {0, 0});
//        cpSpaceAddBody (_space, body);
//        cpSpaceAddShape(_space, disk);
//        cpSpaceAddConstraint(_space, cpDampedSpringNew(_anchor, body, {0, 0}, {0, 0}, cpvlength(pos), 1, 1));
//        cpSpaceAddConstraint(_space, cpGrooveJointNew(_anchor, body, {0, 0}, pos * 3, {0, 0}));
//        return body;
//    };
//
//    _clamps[0] = clamp({ 21,   0});
//    _clamps[1] = clamp({-21,   0});
//    _clamps[2] = clamp({  0,  21});
//    _clamps[3] = clamp({  0, -21});

    cpSpaceAddShape(_space, cpRectShapeNew(_anchor, 20, 20, {0, 0}));

    cpSpaceAddConstraint(_space, cpRotaryLimitJointNew(world, _anchor, 0, 0));
    //cpSpaceAddConstraint(_space, cpSlideJointNew(world, _anchor, {0, 0}, {0, 0}, 0, 30));

    auto brake = [&](float halfW, float halfH, cpVect offset) {
        auto brake = cpBodyNew(0.01, 1);
        cpBodySetPos(brake, offset);
        cpSpaceAddBody(_space, brake);

        auto brakePad = cpRectShapeNew(brake, halfW, halfH, {0, 0});
        cpShapeSetGroup(brakePad, 1);
        cpShapeSetFriction(brakePad, 1000);
        cpSpaceAddShape(_space, brakePad);

        cpSpaceAddConstraint(_space, cpRotaryLimitJointNew(world, brake, 0, 0));
        cpSpaceAddConstraint(_space, cpGrooveJointNew(world, brake, offset * -10, offset * 10, {0, 0}));

        return brake;
    };
    assert(&brake);

//    auto brakeN = brake(40,   4, {  0,  25}); assert(brakeN);
//    auto brakeS = brake(40,   4, {  0, -25}); assert(brakeS);
//    auto brakeE = brake(  4, 40, { 25,   0}); assert(brakeE);
//    auto brakeW = brake(  4, 40, {-25,   0}); assert(brakeW);
//
//    cpSpaceAddConstraint(_space, cpDampedSpringNew(brakeN, brakeS, {0, 0}, {0, 0}, 0, 1, 0));
//    cpSpaceAddConstraint(_space, cpDampedSpringNew(brakeE, brakeW, {0, 0}, {0, 0}, 0, 100, 0));

    [self setupGL];
}

- (void)dealloc {
    [self tearDownGL];

    if ([EAGLContext currentContext] == _context) {
        [EAGLContext setCurrentContext:nil];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];

    if ([self isViewLoaded] && ([[self view] window] == nil)) {
        self.view = nil;

        [self tearDownGL];

        if ([EAGLContext currentContext] == _context) {
            [EAGLContext setCurrentContext:nil];
        }
        _context = nil;
    }

    // Dispose of any resources that can be recreated.
}

- (void)hint:(const std::shared_ptr<ShapeMatches>&)sm {
    if (auto hinted = _shapeMatchesToHint.lock()) {
        if (hinted != sm) {
            _shapeMatchesToHint = sm;
            _nextMatchToHint = 0;
        }
    } else {
        _shapeMatchesToHint = sm;
        _nextMatchToHint = 0;
    }

    if (sm) {
        const auto& match = sm->matches[_nextMatchToHint++ % sm->matches.size()];
        _vboHints[0].data([self prepareSelectionBorder:match.shape1]);
        _vboHints[1].data([self prepareSelectionBorder:match.shape2]);
        _hintIntensity = 1;
    }

    self.paused = NO;
}

- (void)setupGL {
    [EAGLContext setCurrentContext:_context];

    _matte  .reset(new  MatteProgram);
    _border .reset(new BorderProgram);
    _dots   .reset(new   DotsProgram);
    _board  .reset(new  BoardProgram);

    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

    {
        float r, g, b, a;
        [self.view.backgroundColor getRed:&r green:&g blue:&b alpha:&a];
        glClearColor(r, g, b, a);
    }

    auto loadImage = [](NSString *filename, bool repeat) {
        Texture2D * image = [[Texture2D alloc] initWithImage:[UIImage imageNamed:filename]];
        glGenerateMipmapOES(GL_TEXTURE_2D);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR_MIPMAP_NEAREST);
        if (repeat) {
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
        }
        return image;
    };

    _atlas   = loadImage(@"atlas.png"  , false);
    _surface = loadImage(@"surface.png", true ); // http://seamless-pixels.blogspot.com.au/2012/09/seamless-floor-concrete-stone-pavement.html
    _dimple  = loadImage(@"dimple.png" , true );
    _edging  = loadImage(@"edging.png" , false);

    _dotStates = [[Texture2D alloc] initWithTexData:Texture2DData{_dotsData, kTexture2DPixelFormat_RGBA8888, 16, 16, {16, 16}}];

    int nCells = _nBoardRows * _nBoardCols;
    _dotsVertsData.reserve(4 * nCells);
    auto vi = back_inserter(_dotsVertsData);
    for (size_t y = 0; y < _nBoardRows; ++y)
        for (size_t x = 0; x < _nBoardCols; ++x) {
            vec2 position{ x            ,  y            };
            vec2 dotcoord{(x + 0.5) / 16, (y + 0.5) / 16};
            *vi++ = {position             , {0, 0}, dotcoord};
            *vi++ = {position + vec2{1, 0}, {0, 0}, dotcoord};
            *vi++ = {position + vec2{1, 1}, {0, 0}, dotcoord};
            *vi++ = {position + vec2{0, 1}, {0, 0}, dotcoord};
        }
    assert(_dotsVertsData.size() == 4 * nCells);
    _vboDots = DotsVertexBuffer{_dotsVertsData};

    std::vector<GLushort> dotsElemsData; dotsElemsData.reserve(6 * nCells);
    auto ei = back_inserter(dotsElemsData);
    for (size_t i = 0, y = 0; y < _nBoardRows; ++y)
        for (size_t x = 0; x < _nBoardCols; ++x, i += 4) {
            size_t elems[] = { i, i + 1, i + 2, i, i + 2, i + 3 };
            ei = std::copy(std::begin(elems), std::end(elems), ei);
        }
    assert(dotsElemsData.size() == 6 * nCells);
    _eboDots = ElementBuffer<>{dotsElemsData};

    float s = 4.7 / 16;
    float sx = s * _nBoardCols, sy = s * _nBoardRows;
    _vboBoardInterior = BoardVertexBuffer{
        { {0          , 0          }, {0 , 0 }, {0          , 0          } },
        { {_nBoardCols, 0          }, {sx, 0 }, {_nBoardCols, 0          } },
        { {_nBoardCols, _nBoardRows}, {sx, sy}, {_nBoardCols, _nBoardRows} },
        { {0          , _nBoardRows}, {0 , sy}, {0          , _nBoardRows} },
    };

    constexpr float e = gEdgeThickness;
    float E = e * s;
    auto edge = [&](int x, int y, int ox, int oy) {
        return BoardVertex{ {_nBoardCols * x + e * ox, _nBoardRows * y + e * oy}, {sx * x + E * ox, sy * y + E * oy}, {0.5 * (ox + 1), 0.5 * (oy + 1)} };
    };
    auto a00 = edge(0, 0, -1, -1);
    auto a01 = edge(0, 0,  0, -1);
    auto a02 = edge(1, 0,  0, -1);
    auto a03 = edge(1, 0,  1, -1);
    auto a04 = edge(0, 0, -1,  0);
    auto a05 = edge(0, 0,  0,  0);
    auto a06 = edge(1, 0,  0,  0);
    auto a07 = edge(1, 0,  1,  0);
    auto a08 = edge(0, 1, -1,  0);
    auto a09 = edge(0, 1,  0,  0);
    auto a10 = edge(1, 1,  0,  0);
    auto a11 = edge(1, 1,  1,  0);
    auto a12 = edge(0, 1, -1,  1);
    auto a13 = edge(0, 1,  0,  1);
    auto a14 = edge(1, 1,  0,  1);
    auto a15 = edge(1, 1,  1,  1);

    _vboBoardEdge = BoardVertexBuffer{
        a00, a01, a05, a02, a06, a03, // Bottom edge
        a03, a07, a06, a11, a10, a15, // Right edge
        a15, a14, a10, a13, a09, a12, // Top edge
        a12, a08, a09, a04, a05, a00, // Left edge
    };

    _vboHints[0] = BorderVertexBuffer::empty();
    _vboHints[1] = BorderVertexBuffer::empty();

    if (auto border = (*_border)()) {
        border.fs.atlas = 0;
    }

    if (auto dots = (*_dots)()) {
        dots.fs.atlas = 0;
        dots.fs.dots  = 1;
    }

    if (auto board = (*_board)()) {
        board.fs.texture = 0;
        board.fs.light   = 1;
    }

    self.paused = NO;
}

- (void)tearDownGL {
    [EAGLContext setCurrentContext:_context];

    _matte.reset();
    _border.reset();
}

#pragma mark - GLKView and GLKViewController delegate methods

- (void)update {
    float dt = self.timeSinceLastUpdate;

    for (int i = 0; i < 4; ++i)
        cpSpaceStep(_space, (1 / 4.0) * dt);

    CGSize size = self.view.bounds.size;
    float aspect = fabsf(size.width / size.height);

    auto proj = mat4::ortho(0, _viewHeight*aspect, 0, _viewHeight, -5, 5);
    //proj *= mat4::scale(0.2) * mat4::translate({40, 40, 0});

    auto offset = cpBodyGetPos(_anchor);
    auto mv = mat4::translate({gEdgeThickness + offset.x, gEdgeThickness + offset.y, 0});

    _pmvMatrix = proj*mv;
    _normalMatrix = mv.ToMat3().inverse().transpose();
    _pick = _pmvMatrix.inverse();

    if (_hintIntensity && (_hintIntensity -= dt) < 0)
        _hintIntensity = 0;
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    if (auto board = (*_board)()) {
        [_surface activateAndBind:GL_TEXTURE0];
        [_dimple  activateAndBind:GL_TEXTURE1];

        board.vs.pmvMat = _pmvMatrix;
        board.fs.color = {1, 1, 1, 1};

        _vboBoardInterior.render(board, GL_TRIANGLE_FAN);

        [_edging activateAndBind:GL_TEXTURE1];

        _vboBoardEdge.render(board, GL_TRIANGLE_STRIP);
    }
    
    [_atlas activateAndBind:GL_TEXTURE0];
    [_dotStates activateAndBind:GL_TEXTURE1];

    if (auto border = (*_border)()) {
        border.vs.pmvMat = _pmvMatrix;

        for (auto const & sel : _game->sels()) {
            auto b = _borders.find(sel.first);
            if (b != _borders.end() && b->second) {
                border.fs.color = vec4{(vec3)selectionColors[sel.first % selectionColors.size()] * (1 - 0.5 * (sel.second.is_selected.count() < GameState::minimumSelection)), 1};

                b->second.render(border, GL_TRIANGLES);
            }
        }

        if (_hintIntensity) {
            border.fs.color = vec4{1, 1, 1, 1} * _hintIntensity;
            for (const auto& hint : _vboHints)
                hint.render(border, GL_TRIANGLES);
        }
    }

    if (auto dots = (*_dots)()) {
        dots.vs.pmvMat = _pmvMatrix;

        _eboDots.render(dots, _vboDots, GL_TRIANGLES);
    }

    if (_drag)
        if (auto matte = (*_matte)()) {
            matte.vs.pmvMat  = _pmvMatrix;
            matte.vs.normalMat = _normalMatrix;

            auto p = cpBodyGetPos(_finger) - cpBodyGetPos(_anchor);
            matte.vs.color = {1, 1, 0, 1};
            matte.vs.pmvMat = _pmvMatrix*mat4::translate({p.x, p.y, 0});//*mat4::scale(3);
            // TODO
            //glDrawElements(GL_TRIANGLES, sph_elems, GL_UNSIGNED_SHORT, 0);
        }

    if(0)if (auto matte = (*_matte)()) {
        matte.vs.pmvMat  = _pmvMatrix;
        matte.vs.normalMat = _normalMatrix;

        _debugDraw->setShaderContext(matte);
        glLineWidth(3);
        _debugDraw->space(_space);
    }

    [Texture2D activateAndUnbind:GL_TEXTURE0];
    [Texture2D activateAndUnbind:GL_TEXTURE1];

    self.paused = !_hintIntensity;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    _game->touchesBegan([self touchPositions:touches]);
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    _game->touchesMoved([self touchPositions:touches]);
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    _game->touchesEnded([self touchPositions:touches]);
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    _game->touchesCancelled([self touchPositions:touches]);
}

#pragma mark - Actions

- (IBAction)tapGestured:(UITapGestureRecognizer *)sender {
    if (auto pos = [self touchPosition:[sender locationInView:self.view]])
        _game->tapped(*pos);
}

- (IBAction)panGestured:(UIPanGestureRecognizer *)sender {
    auto p = [sender locationInView:self.view] * (_viewHeight / self.view.bounds.size.height);
    p.y = -p.y;

    switch (sender.state) {
        case UIGestureRecognizerStateBegan:
            cpBodySetPos(_finger, p);
            cpBodySetVel(_anchor, {0, 0});
            _drag = cpPivotJointNew(_anchor, _finger, p);
            //cpConstraintSetMaxForce(_drag, 100);
            cpConstraintSetErrorBias(_drag, powf(0.7, 60));
            cpSpaceAddConstraint(_space, _drag);
            break;
        case UIGestureRecognizerStateChanged:
        {
            if (sender.numberOfTouches == 2)
                cpBodySetPos(_finger, p);
            //cpBodySetVel(_finger, {0, 0});
            break;
        }
        case UIGestureRecognizerStateEnded:
        {
            auto v = [sender velocityInView:self.view] * (_viewHeight / self.view.bounds.size.height);
            v.y *= -1;
            cpBodySetVel(_anchor, v);
            cpSpaceRemoveConstraint(_space, _drag);
            cpConstraintFree(_drag);
            _drag = nullptr;
            break;
        }
        default:
            break;
    }
}

- (IBAction)pinchGestured:(UIPinchGestureRecognizer *)sender {
    switch (sender.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
        {

            break;
        }
        case UIGestureRecognizerStateEnded:
        {

            break;
        }
        default:
            break;
    }
}

@end
