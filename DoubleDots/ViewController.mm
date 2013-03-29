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

    brac::BitBoard cells;
    std::vector<MatteVertex> border;
    size_t count;

    Selection() : cells{0}, count(0) { }
};

struct Shape {
    std::vector<brac::BitBoard> possibles;
    UIImage *repr;
    NSString *text;
    int height;
};

@interface ViewController () {
    // Game state
    Board<numBallColors> _board;
    std::array<Selection, 2> _sels;
    int _cursel;
    bool _moved;
    std::vector<std::unique_ptr<Shape>> _shapes;

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
    auto matches = findMatches(_board);

#if 0
    auto at = []{ return mach_absolute_time()*tbi.numer/tbi.denom/1000000; };
    auto t1 = at();
    constexpr int numtests = 0;
    for (int i = 0; i < numtests; ++i)
        auto matches2 = findMatches(_board);
    auto t2 = at();

    if (numtests)
        std::cerr << matches.size() << " matches found in " << (t2 - t1)/numtests << "ms\n";

    std::vector<std::tuple<brac::BitBoard, brac::BitBoard>> biggest;
    int biggest_count = 0;

    std::map<int, int> histogram;
    for (const auto& m : matches) {
        int count = std::get<0>(m).count();
        ++histogram[count];
        if (biggest_count <= count) {
            if (biggest_count < count) {
                biggest_count = count;
                biggest.clear();
            }
            biggest.push_back(m);
        }
    }

    for (const auto& h : histogram)
        std::cerr << h.first << ": " << h.second << "\n";

    for (const auto& m : biggest) {
        brac::BitBoard a, b;
        std::tie(a, b) = m;
        write(std::cerr, _board, {a, b}, "-RGBWK");
    }
#endif

    std::unordered_map<brac::BitBoard, int> shape_histogram;
    for (const auto& m : matches) {
        auto bb = std::get<0>(m);
        int nm = bb.marginN(), sm = bb.marginS(), em = bb.marginE(), wm = bb.marginW();
        ++shape_histogram[std::min(bb.shiftSW(sm, wm).bits,
                                   std::min(bb.rotL().shiftSW(wm, nm).bits,
                                            std::min(bb.reverse().shiftSW(nm, em).bits,
                                                     bb.rotR().shiftSW(em, sm).bits)))];
    }
    std::vector<std::pair<brac::BitBoard, int>> shapes(begin(shape_histogram), end(shape_histogram));
    std::sort(begin(shapes), end(shapes), [](const std::pair<brac::BitBoard, int>& a, const std::pair<brac::BitBoard, int>& b) { return a.first.bits > b.first.bits; });

    // Cull shapes that are subsets of larger shapes.
    auto dst = begin(shapes);
    for (auto i = dst; i != end(shapes); ++i)
        if (std::find_if(begin(shapes), dst, [&](const std::pair<brac::BitBoard, int>& bb) { return !(i->first & ~bb.first); }) == dst) {
            if (dst != i)
                *dst = *i;
            ++dst;
        }
    shapes.erase(dst, end(shapes));

    _shapes.clear();
    for (auto i = shapes.begin(); i != shapes.end(); ++i) {
        std::ostringstream oss;
        write(oss, Board<1>{{{0xffffffffffffffffULL}}}, {i->first}, " O", true);
        _shapes.emplace_back(new Shape({
            std::vector<brac::BitBoard>{i->second},
            nil,
            [NSString stringWithFormat:@"%s", oss.str().c_str()],
            8 - i->first.marginN()
        }));
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

    auto proj = mat4::ortho(-10.5, 21*aspect - 10.5, -10.5, 10.5, -5, 5);
    auto mv = mat4::identity();

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
                matte.vs.color  = vec4(borderColors[&sel - &_sels[0]]*(sel.count < Selection::threshold ? 0.5 : 1), 1);

                matte.vs.enableArray(sel.border.data());

                glLineWidth(3);

                glDrawArrays(GL_LINES, 0, sel.border.size());
            }

        matte.vs.enableVBO(_sphereVerts);
        matte.vs.enableElementVBO(_sphereElems);

        for (int c = 0; c < numBallColors; ++c) {
            const brac::BitBoard& bb = _board.colors[c];
            matte.vs.color = (vec4)ballColors[c];

            for (int i = 0; i < 8; ++i)
                for (int j = 0; j < 8; ++j)
                    if (bb.is_set(j, i)) {
                        matte.vs.mvpMat = _modelViewProjectionMatrix*mat4::translate({2.5*j - 8.75, 2.5*i - 8.75, 0});
                        glDrawElements(GL_TRIANGLES, sph_elems, GL_UNSIGNED_SHORT, 0);
                    }
        }
    }
}

- (void)handleTouch:(UITouch *)touch began:(bool)began {
    auto loc = [touch locationInView:self.view];
    auto size = self.view.bounds.size;

    vec2 pos = (((_pick*vec3{2*loc.x/size.width - 1, 1 - 2*loc.y/size.height, 0}) + vec3{8.75, 8.75, 0})*(1/2.5)).xy();
    float x = (int)(pos.x + 0.5);
    float y = (int)(pos.y + 0.5);

    if (0 <= x && x < 8 && 0 <= y && y < 8) {
        auto& sel = _sels[_cursel];
        auto& cells = sel.cells;
        brac::BitBoard mask = _board.mask();
        if (!cells.is_set(x, y) &&
            !_sels[!_cursel].cells.is_set(x, y) &&
            mask.is_set(x, y) &&
            (began ||
             cells.shiftN(1).is_set(x, y) ||
             cells.shiftS(1).is_set(x, y) ||
             cells.shiftE(1).is_set(x, y) ||
             cells.shiftW(1).is_set(x, y)))
        {
            cells.set(x, y);
            ++sel.count;
        }

        // Redo border.
        sel.border.clear();
        for (int i = 0; i < 9; ++i) {
            y = -8.75+2.5*(i - 1.5);
            for (int j = 0; j < 9; ++j) {
                x = -8.75+2.5*(j - 1.5);
                bool C  = cells.shiftN(5 - i).shiftE(5 - j).is_set(4, 4);
                bool E  = cells.shiftN(5 - i).shiftE(4 - j).is_set(4, 4);
                bool N  = cells.shiftN(4 - i).shiftE(5 - j).is_set(4, 4);
                bool NE = cells.shiftN(4 - i).shiftE(4 - j).is_set(4, 4);
                if (C != E) {
                    bool S  = cells.shiftN(6 - i).shiftE(5 - j).is_set(4, 4);
                    bool SE = cells.shiftN(6 - i).shiftE(4 - j).is_set(4, 4);
                    float X = x + 2.45 + 0.1*(C < E);
                    vec2 a{X, y + 2.45 + 0.1*((C || NE) && (E || N))}, b{X, y + 0.05 - 0.1*((C || SE) && (E || S))};
                    sel.border.push_back({{a, 0}, {0, 0, 1}});
                    sel.border.push_back({{b, 0}, {0, 0, 1}});
                }
                if (C != N) {
                    bool W  = cells.shiftN(5 - i).shiftE(6 - j).is_set(4, 4);
                    bool NW = cells.shiftN(4 - i).shiftE(6 - j).is_set(4, 4);
                    float Y = y + 2.45 + 0.1*(C < N);
                    vec2 a{x + 0.05 - 0.1*((C || NW) && (W || N)), Y}, b{x + 2.45 + 0.1*((C || NE) && (E || N)), Y};
                    sel.border.push_back({{a, 0}, {0, 0, 1}});
                    sel.border.push_back({{b, 0}, {0, 0, 1}});
                }
            }
        }
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    _sels[_cursel] = Selection();
    [self handleTouch:[touches anyObject] began:true];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    [self handleTouch:[touches anyObject] began:false];
    _moved = true;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!_moved) {
        _sels[1] = Selection();
        _cursel = 0;
    } else if (_sels[_cursel].count >= Selection::threshold && !(_cursel = (_cursel + 1)%2)) {
        if (match(_board, _sels[0].cells, _sels[1].cells)) {
            _board &= ~(_sels[0].cells | _sels[1].cells);
            [self updatePossibles];
        }
        _sels[1] = Selection();
    }
    _sels[_cursel] = Selection();
    _moved = false;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    _sels[_cursel] = Selection();
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
    return (iPad ? 137 : 130) - (iPad ? 15 : 14)*(8 - _shapes[indexPath.row]->height);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 40;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 40)];
    headerView.backgroundColor = [UIColor clearColor];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 33)];
    label.text = @"Possible matches";
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

    const auto& shape = *_shapes[indexPath.row];
    cell.quantity.text = [NSString stringWithFormat:@"%ld ×", shape.possibles.size()];
    cell.shape.image = [UIImage imageNamed:@"appicon57.png"];
    cell.shapeText.text = shape.text;
    
    return cell;
}

@end
