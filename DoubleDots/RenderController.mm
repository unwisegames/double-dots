//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import "RenderController.h"

#import "GameState.h"

#import "MathUtil.h"
#import "Texture2D.h"
#import "Physics.h"
#import "Color.h"

#include <array>
#include <mutex>
#include <vector>
#include <memory>
#include <algorithm>

using namespace brac;

#define BRICABRAC_SHADER_NAME Matte
#include "LoadShaders.h"
#define BRICABRAC_SHADER_NAME Border
#include "LoadShaders.h"

static bool iPad = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;

enum {
    sph_layers = 16,
    sph_segments = 32,
    sph_verts = sph_layers*sph_segments + 1,
    sph_elems = 6*sph_layers*sph_segments,
};

static constexpr float gBoardHeight = 41;
static constexpr float gScaleLimit = 2;
static float gLogScaleLimit = std::log(gScaleLimit);

class VertexBuffer {
public:
    VertexBuffer() : vbo_{0}, count_{0} { }
    VertexBuffer(GLuint vbo, GLsizei count) : vbo_{vbo}, count_{count} { }
    VertexBuffer(VertexBuffer&& b) : vbo_(b.vbo_), count_(b.count_) { b.vbo_ = 0; b.count_ = 0; }
    ~VertexBuffer() { reset(); }

    VertexBuffer& operator=(VertexBuffer&& b) {
        glDeleteBuffers(1, &vbo_);
        vbo_ = b.vbo_;
        count_ = b.count_;
        b.vbo_ = 0;
        b.count_ = 0;
        return *this;
    }

    void reset() {
        glDeleteBuffers(1, &vbo_);
        vbo_ = 0;
        count_ = 0;
    }

    explicit operator bool() const { return vbo_; }
    bool operator!() const { return !vbo_; }

    template <typename T>
    void render(const T& shaderContext, GLenum type, GLint first, GLsizei count) const {
        if (vbo_) {
            shaderContext.vs.enableVBO(vbo_);
            glDrawArrays(type, first, count);
        }
    }
    template <typename T>
    void render(const T& shaderContext, GLenum type) const {
        render(shaderContext, type, 0, count_);
    }

private:
    GLuint vbo_;
    GLsizei count_;

    VertexBuffer(const VertexBuffer&) = delete;
    VertexBuffer& operator=(const VertexBuffer&) = delete;
};

static Color ballColors[] = {
    Color::red  (),
    Color::green(),
    Color::blue (),
    Color::white(),
    {0.4, 0.4, 0.4, 1},
};

static std::array<Color, GameState::numBallColors> selectionColors = {{
    {1  , 0.7, 0.1},
    {0.6, 0.6, 1  },
    {0.9, 0.3, 0.6},
    {0.4, 0.8, 0.4},
    {0.6, 0.6, 0.2},
}};

static std::array<MatteVertex, sph_verts> gSphereVertices_;
static std::array<GLushort, sph_elems> gSphereElements_;

void prepareSphere() {
    static std::once_flag once;
    std::call_once(once, []{
        auto vi = gSphereVertices_.begin();
        for (GLushort l = 0; l < sph_layers; ++l) {
            auto z = sinf(M_PI*l/sph_layers);
            auto r = sqrtf(1 - z*z);
            for (GLushort s = 0; s < sph_segments; ++s, ++vi) {
                float a = 2*M_PI*s/sph_segments;
                vec3 p{r*cosf(a), r*sinf(a), z};
                *vi = {p, p};
            }
        }
        *vi = {{0, 0, 1}, {0, 0, 1}};

        auto ei = gSphereElements_.begin();
        for (GLushort l = 0; l < sph_layers - 1; ++l) {
            GLushort i = l*sph_segments;
            for (GLushort s = 0; s < sph_segments; ++s) {
                GLushort j = i + s;
                GLushort k = i + (s + 1)%sph_segments;
                int ii[] = { j, k, j + sph_segments, j + sph_segments, k, k + sph_segments };
                ei = std::copy(std::begin(ii), std::end(ii), ei);
            }
        }
        GLushort i = (sph_layers - 1)*sph_segments;
        for (GLushort s = 0; s < sph_segments; ++s) {
            GLushort j = i + s;
            GLushort k = i + (s + 1)%sph_segments;
            int ii[] = { j, k, sph_verts - 1 };
            ei = std::copy(std::begin(ii), std::end(ii), ei);
        }
    });
}

std::array<MatteVertex, sph_verts> sphereVertices() {
    prepareSphere();
    return gSphereVertices_;
}

std::array<GLushort, sph_elems> sphereElements() {
    prepareSphere();
    return gSphereElements_;
}

@interface RenderController () {
    EAGLContext *_context;

    std::unique_ptr<MatteProgram> _matte;
    std::unique_ptr<BorderProgram> _border;
    mat4 _mvpMatrix, _pick;
    mat3 _normalMatrix;
    float _rotation;
    GLuint _sphereVerts, _sphereElems;
    Texture2D *_atlas;
    vec2 _offset;
    float _scale;

    std::array<VertexBuffer, GameState::maxTouches> _sels;

    std::weak_ptr<ShapeMatches> _shapeMatchesToHint;
    int _nextMatchToHint;
    float _hintIntensity;
    std::array<VertexBuffer, 2> _hints;

    vec2 _pan, _panLimit;
    float _pinchScale;
    std::shared_ptr<brac::kinematics::MechanicalSystem> _xReturn, _yReturn, _scaleReturn;
}
@end

@implementation RenderController

@synthesize game = _game;

- (std::unique_ptr<vec2>)touchPosition:(CGPoint)loc {
    auto size = self.view.bounds.size;

    vec2 p = ((_pick*vec3{2*loc.x/size.width - 1, 1 - 2*loc.y/size.height, 0})*(1/2.5)).xy();
    p = {std::round(p.x), std::round(p.y)};
    return std::unique_ptr<vec2>{0 <= p.x && p.x < 16 && 0 <= p.y && p.y < 16 ? new vec2{p} : nullptr};
}

- (VertexBuffer)prepareBorderForSelection:(brac::BitBoard const &)bb {
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

    for (int i = 0; i < 16; ++i) {
        float y = 2.5*i;
        for (int j = 0; j < 16; ++j) {
            float x = 2.5*j;
            vec2 c{x, y};
            uint64_t hood = bb.shiftWS(j - 1, i - 1).a;
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

                triangle(c, c + vec2{-1.25,  0   }, c + vec2{-1.25, -1.25}, We, SWc);
                triangle(c, c + vec2{-1.25,  0   }, c + vec2{-1.25,  1.25}, We, NWc);
                triangle(c, c + vec2{ 0   , -1.25}, c + vec2{ 1.25, -1.25}, Se, SEc);
                triangle(c, c + vec2{ 0   , -1.25}, c + vec2{-1.25, -1.25}, Se, SWc);
                triangle(c, c + vec2{ 1.25,  0   }, c + vec2{ 1.25, -1.25}, Ee, SEc);
                triangle(c, c + vec2{ 1.25,  0   }, c + vec2{ 1.25,  1.25}, Ee, NEc);
                triangle(c, c + vec2{ 0   ,  1.25}, c + vec2{ 1.25,  1.25}, Ne, NEc);
                triangle(c, c + vec2{ 0   ,  1.25}, c + vec2{-1.25,  1.25}, Ne, NWc);
            }
        }
    }
    return {border.size() ? BorderVertex::makeBuffer(border.data(), border.size()) : 0, border.size()};
}

- (void)updateBorders {
    for (int i = 0; i < GameState::maxTouches; ++i)
        _sels[i] = [self prepareBorderForSelection:_game->sels()[0].is_selected.count() > 1 ? _game->sels()[i].is_selected : brac::BitBoard::empty()];
}

- (void)setGame:(std::shared_ptr<GameState>)game {
    _game = game;
    _game->onTouchPosition([=](UITouch *touch){
        return [self touchPosition:[touch locationInView:self.view]];
    });
    _game->onSelectionChanged([=]{
        [self updateBorders];
    });
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

    _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    if (!_context) {
        NSLog(@"Failed to create ES context");
    }

    GLKView *view = (GLKView *)self.view;
    view.context = _context;
    view.drawableMultisample = GLKViewDrawableMultisample4X;
    self.preferredFramesPerSecond = 60;

    _scale = _pinchScale = 1;

    _xReturn = std::make_shared<brac::kinematics::MechanicalSystem>(brac::kinematics::harmonicOscillator(5000));
    _yReturn = std::make_shared<brac::kinematics::MechanicalSystem>(brac::kinematics::harmonicOscillator(5000));
    _scaleReturn = std::make_shared<brac::kinematics::MechanicalSystem>(brac::kinematics::harmonicOscillator(5000));

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
    if (auto hinted = _shapeMatchesToHint.lock())
        if (hinted != sm) {
            _shapeMatchesToHint = sm;
            _nextMatchToHint = 0;
        }
    const auto& match = sm->matches[_nextMatchToHint++%sm->matches.size()];
    _hints[0] = [self prepareBorderForSelection:match.shape1];
    _hints[1] = [self prepareBorderForSelection:match.shape2];
    _hintIntensity = 1;
}

- (void)setupGL {
    [EAGLContext setCurrentContext:_context];

    _matte.reset(new MatteProgram);
    _border.reset(new BorderProgram);

    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

    _sphereVerts = MatteVertex::makeBuffer(sphereVertices().data(), sphereVertices().size());
    glGenBuffers(1, &_sphereElems);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _sphereElems);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(GLushort)*sphereElements().size(), sphereElements().data(), GL_STATIC_DRAW);

    _atlas = [[Texture2D alloc] initWithImage:[UIImage imageNamed:@"atlas.png"]];
}

- (void)tearDownGL {
    [EAGLContext setCurrentContext:_context];

    glDeleteBuffers(1, &_sphereVerts);
    glDeleteBuffers(1, &_sphereElems);

    _matte.reset();
    _border.reset();
}

#pragma mark - GLKView and GLKViewController delegate methods

- (void)update {
    float dt = self.timeSinceLastUpdate;

    CGSize size = self.view.bounds.size;
    float aspect = fabsf(size.width / size.height);

    float s = gBoardHeight / size.height;

    float scale = std::exp(softclamp(std::log(_scale * _pinchScale) + _scaleReturn->x(), 0, gLogScaleLimit, 0.3));
    float inv_scale = 1 / scale;

    _panLimit = vec2(1, 1) * (std::max(gBoardHeight * (scale - 1), 0.0f) / s);

    vec2 off = (_offset + _pan + vec2{_xReturn->x(), _yReturn->x()});
    off.x = softclamp(off.x, 0, _panLimit.x, 0.25 * _panLimit.x) * s;
    off.y = softclamp(off.y, 0, _panLimit.y, 0.25 * _panLimit.y) * s;

    for (int i = 0; i < 4; ++i) {
        (*_xReturn)(0.25 * dt);
        (*_yReturn)(0.25 * dt);
        (*_scaleReturn)(0.25 * dt);
    }

    auto proj = mat4::ortho(inv_scale * off.x, inv_scale * (off.x + gBoardHeight*aspect), inv_scale * off.y, inv_scale * (off.y + gBoardHeight), -5, 5);
    if (!iPad) proj *= mat4::scale(16/7.0);

    auto mv = mat4::identity()*mat4::translate({1.75, 1.75, 0});

    _mvpMatrix = proj*mv;
    _normalMatrix = mv.ToMat3().inverse().transpose();
    _pick = _mvpMatrix.inverse();

    if (_hintIntensity && (_hintIntensity -= dt) < 0) {
        _hintIntensity = 0;
        for (int i = 0; i < 2; ++i)
            _hints[i].reset();
    }
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    {
        float r, g, b, a;
        [self.view.backgroundColor getRed:&r green:&g blue:&b alpha:&a];
        glClearColor(r, g, b, a);
    }
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    if (auto border = (*_border)()) {
        border.vs.pmvMat = _mvpMatrix;

        border.fs.atlas = 0;
        [_atlas activateAndBind:GL_TEXTURE0];

        for (int i = 0; i != _game->sels().size(); ++i) {
            const auto& sel = _game->sels()[i];
            if (_sels[i]) {
                border.fs.color = vec4{(vec3)selectionColors[i]*(1 - 0.5*(sel.is_selected.count() < GameState::minimumSelection)), 1};

                _sels[i].render(border, GL_TRIANGLES);
            }
        }

        if (_hintIntensity)
            border.fs.color = vec4{1, 1, 1, 1}*_hintIntensity;
        for (const auto& hint : _hints)
            hint.render(border, GL_TRIANGLES);
    }

    if (auto matte = (*_matte)()) {
        matte.vs.normalMat = _normalMatrix;
        matte.vs.enableVBO(_sphereVerts);
        matte.vs.enableElementVBO(_sphereElems);

        // Dots
        for (int c = 0; c < GameState::numBallColors; ++c)
            if (brac::BitBoard const & bb = _game->board().colors[c]) {
                matte.vs.color = (vec4)ballColors[c];

                for (int y = 0; y < 16; ++y)
                    for (int x = 0; x < 16; ++x)
                        if (bb.isSet(x, y)) {
                            matte.vs.mvpMat = _mvpMatrix*mat4::translate({2.5*x, 2.5*y, 0});
                            glDrawElements(GL_TRIANGLES, sph_elems, GL_UNSIGNED_SHORT, 0);
                        }
            }
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    _game->touchesBegan(touches);
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    _game->touchesMoved(touches);
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    _game->touchesEnded(touches);
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    _game->touchesCancelled(touches);
}

#pragma mark - Actions

- (IBAction)tapGestured:(UITapGestureRecognizer *)sender {
    if (auto pos = [self touchPosition:[sender locationInView:self.view]])
        _game->tapped(*pos);
}

- (IBAction)panGestured:(UIPanGestureRecognizer *)sender {
    switch (sender.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
        {
            CGPoint pan = [sender translationInView:self.view];
            _pan = vec2{-pan.x, pan.y};
            break;
        }
        case UIGestureRecognizerStateEnded:
            _offset += _pan;
            if (_offset.x < 0) {
                _xReturn->setX(_offset.x);
                _offset.x = 0;
            } else if (_offset.x > _panLimit.x) {
                _xReturn->setX(_offset.x - _panLimit.x);
                _offset.x = _panLimit.x;
            }
            if (_offset.y < 0) {
                _yReturn->setX(_offset.y);
                _offset.y = 0;
            } else if (_offset.y > _panLimit.y) {
                _yReturn->setX(_offset.y - _panLimit.y);
                _offset.y = _panLimit.y;
            }
            _pan = {0, 0};
            break;
        default:
            break;
    }
}

- (IBAction)pinchGestured:(UIPinchGestureRecognizer *)sender {
    switch (sender.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            _pinchScale = sender.scale;
            break;
        case UIGestureRecognizerStateEnded:
            _scale *= _pinchScale;
            if (_scale < 1) {
                _scaleReturn->setX(std::log(_scale));
                _scale = 1;
            } else if (_scale > gScaleLimit) {
                _scaleReturn->setX(std::log(_scale) - gLogScaleLimit);
                _scale = gScaleLimit;
            }
            _pinchScale = 1;
            break;
        default:
            break;
    }
}

@end
