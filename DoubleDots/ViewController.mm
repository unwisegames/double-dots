//
//  ViewController.mm
//  DoubleDots
//
//  Created by Marcelo Cantos on 1/03/13.
//  Copyright (c) 2013 Habeo Soft. All rights reserved.
//

#import "ViewController.h"
#import "ShapeCell.h"
#import "Board.h"

#import "ShaderProgram.h"
#import "MathUtil.h"

#import <QuartzCore/QuartzCore.h>

#include <mach/mach_time.h>

#include <array>
#include <vector>
#include <unordered_map>
#include <mutex>
#include <bitset>
#include <cmath>
#include <algorithm>
#include <functional>
#include <numeric>
#include <sstream>
#include <iostream>
#include <map>

using namespace squz;
using namespace habeo;

static bool iPad = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;

#define BRICABRAC_SHADER_NAME Matte
#include "LoadShaders.h"
typedef bricabrac::ShaderProgram<MatteVertexShader, MatteFragmentShader> MatteProgram;
typedef MatteVertexShader::Vertex MatteVertex;

enum {
    sph_layers = 16,
    sph_segments = 32,
    sph_verts = sph_layers*sph_segments + 1,
    sph_elems = 6*sph_layers*sph_segments,
};

static Color ballColors[] = {
    Color::red  (),
    Color::green(),
    Color::blue (),
    Color::white(),
    {0.4, 0.4, 0.4, 1},
};
enum { numBallColors = sizeof(ballColors)/sizeof(*ballColors) };

std::array<MatteVertex, sph_verts> gSphereVertices_;
std::array<GLushort, sph_elems> gSphereElements_;

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

struct Selection {
    enum { threshold = 3 };

    brac::BitBoard is_selected;
    std::vector<MatteVertex> border;

    Selection() : is_selected{0} { }
};

struct Match {
    brac::BitBoard a, b;
    int score;
};

struct Shape {
    std::vector<Match> matches;
    UIImage *repr;
    NSString *count, *text, *scores;
    int height;
};

@interface ViewController () {
    // Game state
    Board<numBallColors> _board;
    std::array<Selection, 2> _sels;
    Selection *_cursel;
    bool _moved;
    std::vector<Shape> _shapes;

    // OpenGL
    MatteProgram *_matte;
    mat4 _modelViewProjectionMatrix, _pick;
    mat3 _normalMatrix;
    float _rotation;
    GLuint _sphereVerts, _sphereElems;
}
@property (strong, nonatomic) EAGLContext *context;

- (void)setupGame;
- (void)setupGL;
- (void)tearDownGL;
@end

@implementation ViewController

@synthesize tableView = _tableView;

- (void)updatePossibles {
    static mach_timebase_info_data_t tbi;
    static std::once_flag once;
    std::call_once(once, []{
        mach_timebase_info(&tbi);
    });
    auto pairs = findMatchingPairs(_board);

#if 0
    auto at = []{ return mach_absolute_time()*tbi.numer/tbi.denom/1000000; };
    auto t1 = at();
    constexpr int numtests = 1;
    for (int i = 0; i < numtests; ++i)
        auto pairs2 = findMatchingPairs(_board);
    auto t2 = at();

    if (numtests)
        std::cerr << pairs.size() << " matches found in " << (t2 - t1)/numtests << "ms\n";

    std::vector<std::pair<brac::BitBoard, brac::BitBoard>> biggest;
    int biggest_count = 0;

    std::map<int, int> histogram;
    for (const auto& p : pairs) {
        int count = p.first.count();
        ++histogram[count];
        if (biggest_count <= count) {
            if (biggest_count < count) {
                biggest_count = count;
                biggest.clear();
            }
            biggest.push_back(p);
        }
    }

    for (const auto& h : histogram)
        std::cerr << h.first << ": " << h.second << "\n";

    for (const auto& p : biggest) {
        write(std::cerr, _board, {p.first, p.second}, "-RGBWK");
    }
#endif

    std::vector<Match> matches;
    for (const auto& p : pairs) {
        int score = p.first.count();

        // Add the score of every smaller match that this pair clobbers but doesn't contain.
        for (const auto& m : matches) {
            brac::BitBoard bb = m.a | m.b;
            brac::BitBoard diff = bb & ~(p.first | p.second);
            if (diff && diff != bb)
                score += m.a.count();
        }

        matches.push_back({p.first, p.second, score});
    }

    typedef std::unordered_map<brac::BitBoard, std::vector<Match>> ShapeMap;
    typedef std::pair<brac::BitBoard, std::vector<Match>> ShapeMatches;
    ShapeMap shape_histogram;
    for (const auto& m : matches) {
        auto bb = m.a;
        int nm = bb.marginN(), sm = bb.marginS(), em = bb.marginE(), wm = bb.marginW();
        auto& h = shape_histogram[std::min(bb.shiftWS(wm, sm).bits,
                                           std::min(bb.rotL().shiftWS(nm, wm).bits,
                                                    std::min(bb.reverse().shiftWS(em, nm).bits,
                                                             bb.rotR().shiftWS(sm, em).bits)))];
        h.push_back(m);
    }
    std::vector<ShapeMatches> shapes(begin(shape_histogram), end(shape_histogram));
    std::sort(begin(shapes), end(shapes), [](const ShapeMatches& a, const ShapeMatches& b) {
        auto comp = [](const Match& a, const Match& b) { return a.score > b.score; };
        return (std::lexicographical_compare(begin(a.second), end(a.second), begin(b.second), end(a.second), comp) ||
                (!std::lexicographical_compare(begin(b.second), end(b.second), begin(a.second), end(a.second), comp) &&
                 a.first.bits > b.first.bits));
    });

    // Cull any shapes that are subsets of larger shapes.
    auto dst = begin(shapes);
    for (auto i = dst; i != end(shapes); ++i)
        if (std::find_if(begin(shapes), dst, [&](const ShapeMatches& sm) { return !(i->first & ~sm.first); }) == dst) {
            if (dst != i)
                *dst = *i;
            ++dst;
        }
    shapes.erase(dst, end(shapes));

    _shapes.clear();
    for (auto i = shapes.begin(); i != shapes.end(); ++i) {
        std::ostringstream shapeText;
        write(shapeText, Board<1>{{{0xffffffffffffffffULL}}}, {i->first}, " O", true);

        std::vector<int> scores; scores.reserve(i->second.size());
        std::ostringstream scoresText;
        for (const auto& m : i->second)
            scoresText << (&m == &i->second[0] ? "" : "\n") << m.score;

        _shapes.push_back({
            i->second,
            nil,
            [NSString stringWithFormat:@"%ld ×", i->second.size()],
            [NSString stringWithUTF8String:shapeText.str().c_str()],
            [NSString stringWithUTF8String:scoresText.str().c_str()],
            8 - i->first.marginN()
        });
    }
    [_tableView reloadData];

    if (matches.empty())
        [self setupGame];
}

- (void)setupGame {
    std::fill(begin(_board.colors), end(_board.colors), 0);
    for (int i = 0; i < 64; ++i)
        //_board.colors[rand()%numBallColors].bits |= 1ULL << i;
        _board.colors[arc4random_uniform(numBallColors)].bits |= 1ULL << i;
    [self updatePossibles];
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self becomeFirstResponder];

    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    if (!self.context) {
        NSLog(@"Failed to create ES context");
    }

    GLKView *view = (GLKView *)self.view;
    view.context = self.context;
    view.drawableMultisample = GLKViewDrawableMultisample4X;
    self.preferredFramesPerSecond = 60;

    _tableView.layer.borderColor = [UIColor grayColor].CGColor;
    _tableView.layer.borderWidth = 1;

    [self setupGL];
    [self setupGame];
}

- (void)dealloc {
    [self tearDownGL];

    if ([EAGLContext currentContext] == self.context) {
        [EAGLContext setCurrentContext:nil];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];

    if ([self isViewLoaded] && ([[self view] window] == nil)) {
        self.view = nil;

        [self tearDownGL];

        if ([EAGLContext currentContext] == self.context) {
            [EAGLContext setCurrentContext:nil];
        }
        self.context = nil;
    }

    // Dispose of any resources that can be recreated.
}

- (void)setupGL {
    [EAGLContext setCurrentContext:self.context];

    _matte = new MatteProgram;

    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

    _sphereVerts = MatteVertex::makeBuffer(sphereVertices().data(), sphereVertices().size());
    glGenBuffers(1, &_sphereElems);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _sphereElems);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(GLushort)*sphereElements().size(), sphereElements().data(), GL_STATIC_DRAW);
}

- (void)tearDownGL {
    [EAGLContext setCurrentContext:self.context];

    glDeleteBuffers(1, &_sphereVerts);
    glDeleteBuffers(1, &_sphereElems);

    delete _matte; _matte = nullptr;
}

#pragma mark - GLKView and GLKViewController delegate methods

- (void)update {
    float aspect = fabsf(self.view.bounds.size.width / self.view.bounds.size.height);

    auto proj = mat4::ortho(0, 21*aspect, 0, 21, -2, 2);//*mat4::scale(8/7.0);
    auto mv = mat4::identity()*mat4::translate({10.5, 10.5, 0});

    _modelViewProjectionMatrix = proj*mv;
    _normalMatrix = mv.ToMat3().inverse().transpose();
    _pick = _modelViewProjectionMatrix.inverse();
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    glClearColor(0.15, 0.15, 0.15, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    if (auto matte = (*_matte)()) {
        matte.vs.normalMat = _normalMatrix;

        vec3 borderColors[2] = {{1, 0.7, 0.1}, {0.6, 0.6, 1}};
        for (auto& sel : _sels)
            if (!sel.border.empty()) {
                matte.vs.mvpMat = _modelViewProjectionMatrix;
                matte.vs.color  = vec4(borderColors[&sel - &_sels[0]]*(sel.is_selected.count() < Selection::threshold ? 0.5 : 1), 1);

                matte.vs.enableArray(sel.border.data());

                glLineWidth(3);

                glDrawArrays(GL_LINES, 0, sel.border.size());
            }

        matte.vs.enableVBO(_sphereVerts);
        matte.vs.enableElementVBO(_sphereElems);

        for (int c = 0; c < numBallColors; ++c) {
            const brac::BitBoard& bb = _board.colors[c];
            matte.vs.color = (vec4)ballColors[c];

            for (int y = 0; y < 8; ++y)
                for (int x = 0; x < 8; ++x)
                    if (bb.is_set(x, y)) {
                        matte.vs.mvpMat = _modelViewProjectionMatrix*mat4::translate({2.5*x - 8.75, 2.5*y - 8.75, 0});
                        glDrawElements(GL_TRIANGLES, sph_elems, GL_UNSIGNED_SHORT, 0);
                    }
        }
    }
}

- (std::unique_ptr<vec2>)touchPosition:(UITouch *)touch {
    auto loc = [touch locationInView:self.view];
    auto size = self.view.bounds.size;

    vec2 p = (((_pick*vec3{2*loc.x/size.width - 1, 1 - 2*loc.y/size.height, 0}) + vec3{8.75, 8.75, 0})*(1/2.5)).xy();
    p = {std::round(p.x), std::round(p.y)};
    return std::unique_ptr<vec2>{0 <= p.x && p.x < 8 && 0 <= p.y && p.y < 8 ? new vec2{p} : nullptr};
}

- (void)handleTouch:(brac::BitBoard)is_touched began:(bool)began {
    auto adjoins_touch = is_touched.shiftN(1) | is_touched.shiftS(1) | is_touched.shiftE(1) | is_touched.shiftW(1);
    auto is_occupied = _board.mask();
    if ((is_touched & is_occupied & ~(_sels[0].is_selected | _sels[1].is_selected)) && (!_cursel->is_selected || (_cursel->is_selected & adjoins_touch)))
        _cursel->is_selected |= is_touched;

    // Redo border.
    auto& sel = *_cursel;
    const auto& is_selected = sel.is_selected;
    sel.border.clear();
    for (int i = 0; i < 9; ++i) {
        float y = -8.75+2.5*(i - 1.5);
        for (int j = 0; j < 9; ++j) {
            float x = -8.75+2.5*(j - 1.5);
            bool C  = is_selected.shiftEN(5 - j, 5 - i).is_set(4, 4);
            bool E  = is_selected.shiftEN(4 - j, 5 - i).is_set(4, 4);
            bool N  = is_selected.shiftEN(5 - j, 4 - i).is_set(4, 4);
            bool NE = is_selected.shiftEN(4 - j, 4 - i).is_set(4, 4);
            if (C != E) {
                bool S  = is_selected.shiftN(6 - i).shiftE(5 - j).is_set(4, 4);
                bool SE = is_selected.shiftN(6 - i).shiftE(4 - j).is_set(4, 4);
                float X = x + 2.45 + 0.1*(C < E);
                vec2 a{X, y + 2.45 + 0.1*((C || NE) && (E || N))}, b{X, y + 0.05 - 0.1*((C || SE) && (E || S))};
                sel.border.push_back({{a, 0}, {0, 0, 1}});
                sel.border.push_back({{b, 0}, {0, 0, 1}});
            }
            if (C != N) {
                bool W  = is_selected.shiftN(5 - i).shiftE(6 - j).is_set(4, 4);
                bool NW = is_selected.shiftN(4 - i).shiftE(6 - j).is_set(4, 4);
                float Y = y + 2.45 + 0.1*(C < N);
                vec2 a{x + 0.05 - 0.1*((C || NW) && (W || N)), Y}, b{x + 2.45 + 0.1*((C || NE) && (E || N)), Y};
                sel.border.push_back({{a, 0}, {0, 0, 1}});
                sel.border.push_back({{b, 0}, {0, 0, 1}});
            }
        }
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if (auto p = [self touchPosition:[touches anyObject]]) {
        if (!_cursel) {
            auto is_touched = brac::BitBoard{1, p->x, p->y};

            for (int i = 0; i < 2; ++i)
                if (is_touched & _sels[i].is_selected)
                    _cursel = &_sels[i];

            if (!_cursel)
                for (int i = 0; i < 2; ++i)
                    if (!_sels[i].is_selected)
                        _cursel = &_sels[i];

            if (_cursel)
                [self handleTouch:is_touched began:true];
        }
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if (auto p = [self touchPosition:[touches anyObject]]) {
        if (_cursel) {
            auto is_touched = brac::BitBoard{1, p->x, p->y};

            [self handleTouch:is_touched began:false];
        }
        _moved = true;
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!_moved) {
        _sels[0] = _sels[1] = Selection();
    } else if (_sels[0].is_selected.count() >= Selection::threshold) {
        if (selectionsMatch(_board, _sels[0].is_selected, _sels[1].is_selected)) {
            _board &= ~(_sels[0].is_selected | _sels[1].is_selected);
            [self updatePossibles];
            _sels[0] = _sels[1] = Selection();
        }
    }
    _cursel = nullptr;
    _moved = false;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    if (_cursel)
        *_cursel = Selection();
}

- (void)motionBegan:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (motion == UIEventSubtypeMotionShake)
        [self setupGame];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _shapes.size();
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return (iPad ? 137 : 130) - (iPad ? 15 : 14)*(8 - _shapes[indexPath.row].height);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 40;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 40)];
    headerView.backgroundColor = [UIColor clearColor];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 33)];
    label.text = @"Best shapes";
    label.textColor = [UIColor whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.7];
    label.layer.borderColor = [UIColor redColor].CGColor;
    [headerView addSubview:label];

    CALayer *line = [CALayer layer];
    line.frame = CGRectMake(0, 33, tableView.bounds.size.width, 1);
    line.backgroundColor = [UIColor grayColor].CGColor;
    [headerView.layer addSublayer:line];

    return headerView;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"shape";
    ShapeCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell) {
        cell = [[ShapeCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }

    const auto& shape = _shapes[indexPath.row];
    cell.quantity.text = shape.count;
    cell.quantity.hidden = shape.matches.size() < 2;
    cell.shape.image = [UIImage imageNamed:@"appicon57.png"];
    cell.shapeText.text = shape.text;
    cell.scores.numberOfLines = shape.matches.size();
    cell.scores.text = shape.scores;

    return cell;
}

@end
