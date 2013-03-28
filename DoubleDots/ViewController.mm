//
//  ViewController.mm
//  HabeoMath
//
//  Created by Marcelo Cantos on 1/03/13.
//  Copyright (c) 2013 Habeo Soft. All rights reserved.
//

#import "ViewController.h"
#import "ShapeCell.h"

#import "ShaderProgram.h"
#import "MathUtil.h"

#import <QuartzCore/QuartzCore.h>

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

using namespace squz;

namespace std {

    template <>
    struct hash<vec2> {
        size_t operator()(const vec2& p) const {
            return hash<float>()(p.x)*1129803267 + hash<float>()(p.y);
        }
    };

    template <>
    struct equal_to<vec2> {
        bool operator()(const vec2& p, const vec2& q) const {
            return p == q;
        }
    };

}

inline uint8_t reverseByte(uint8_t b) {
    return ((b * 0x80200802ULL) & 0x0884422110ULL) * 0x0101010101ULL >> 32;
}

inline uint64_t transposeByte(uint8_t b) {
    return ((b&0x7f) * 0x40810204081ULL & 0x0101010101010101ULL) + ((b & 0x80ULL) << 56);
}

struct BitBoard {
    uint64_t bits;

    bool operator!() const { return !bits; }
    explicit operator bool() const { return !!*this; }

    BitBoard& SQUZ_OPERATOR(&=)(const BitBoard& b) { bits &= b.bits; return *this; }
    BitBoard& SQUZ_OPERATOR(|=)(const BitBoard& b) { bits |= b.bits; return *this; }
    BitBoard& SQUZ_OPERATOR(^=)(const BitBoard& b) { bits ^= b.bits; return *this; }

    bool is_set(int x, int y) const {
        return bits & (1ULL << (x + 8*y));
    }
    void set(int x, int y) {
        bits |= (1ULL << (x + 8*y));
    }
    void clear(int x, int y) {
        bits &= ~(1ULL << (x + 8*y));
    }

    BitBoard reverse() const {
        uint64_t v = bits; // high word
        v = ((v >>  1) & 0x5555555555555555ULL) | ((v & 0x5555555555555555ULL) <<  1); // swap odd and even bits
        v = ((v >>  2) & 0x3333333333333333ULL) | ((v & 0x3333333333333333ULL) <<  2); // swap consecutive pairs
        v = ((v >>  4) & 0x0F0F0F0F0F0F0F0FULL) | ((v & 0x0F0F0F0F0F0F0F0FULL) <<  4); // swap nibbles ...
        v = ((v >>  8) & 0x00FF00FF00FF00FFULL) | ((v & 0x00FF00FF00FF00FFULL) <<  8); // swap bytes
        v = ((v >> 16) & 0x0000FFFF0000FFFFULL) | ((v & 0x0000FFFF0000FFFFULL) << 16); // swap 2-byte long pairs
        v = ( v >> 32                         ) | ( v                          << 32); // swap 4-byte long long pairs
        return {v};
    }
    BitBoard transpose() const {
        return {(transposeByte(bits      )      |
                 transposeByte(bits >>  8) << 1 |
                 transposeByte(bits >> 16) << 2 |
                 transposeByte(bits >> 24) << 3 |
                 transposeByte(bits >> 32) << 4 |
                 transposeByte(bits >> 40) << 5 |
                 transposeByte(bits >> 48) << 6 |
                 transposeByte(bits >> 56) << 7)};
    }

    BitBoard flipH() const {
        return{((uint64_t)reverseByte(bits      )       |
                (uint64_t)reverseByte(bits >>  8) <<  8 |
                (uint64_t)reverseByte(bits >> 16) << 16 |
                (uint64_t)reverseByte(bits >> 24) << 24 |
                (uint64_t)reverseByte(bits >> 32) << 32 |
                (uint64_t)reverseByte(bits >> 40) << 40 |
                (uint64_t)reverseByte(bits >> 48) << 48 |
                (uint64_t)reverseByte(bits >> 56) << 56)};
    }
    BitBoard flipV() const {
        return {((bits                        ) << 56 |
                 (bits & 0xff00ULL            ) << 40 |
                 (bits & 0xff0000ULL          ) << 24 |
                 (bits & 0xff000000ULL        ) <<  8 |
                 (bits & 0xff00000000ULL      ) >>  8 |
                 (bits & 0xff0000000000ULL    ) >> 24 |
                 (bits & 0xff000000000000ULL  ) >> 40 |
                 (bits                        ) >> 56)};
    }

    BitBoard rotL() const { return flipV().transpose(); }
    BitBoard rotR() const { return transpose().flipV(); }

    BitBoard trimS(int n) const { return {bits & ~((1ULL<<(     8*n)) - 1)}; }
    BitBoard trimN(int n) const { return {bits &  ((1ULL<<(64 - 8*n)) - 1)}; }
    BitBoard trimW(int n) const { return {bits & ~((0x0101010101010101ULL<<     n ) - 0x0101010101010101)}; }
    BitBoard trimE(int n) const { return {bits &  ((0x0101010101010101ULL<<(8 - n)) - 0x0101010101010101)}; }

    BitBoard shiftN(int n) const { return n < 0 ? shiftS(-n) : n > 0 ? BitBoard{bits<<(8*n)}          : *this; }
    BitBoard shiftS(int n) const { return n < 0 ? shiftN(-n) : n > 0 ? BitBoard{bits>>(8*n)}          : *this; }
    BitBoard shiftE(int n) const { return n < 0 ? shiftW(-n) : n > 0 ? BitBoard{bits<<   n }.trimW(n) : *this; }
    BitBoard shiftW(int n) const { return n < 0 ? shiftE(-n) : n > 0 ? BitBoard{bits>>   n }.trimE(n) : *this; }

    int marginN() const { return margin<&BitBoard::trimS>(); }
    int marginS() const { return margin<&BitBoard::trimN>(); }
    int marginE() const { return margin<&BitBoard::trimW>(); }
    int marginW() const { return margin<&BitBoard::trimE>(); }

private:
    template <BitBoard (BitBoard::*trim)(int n) const>
    int margin() const {
        return ((this->*trim)(4) ? (this->*trim)(6) ? !(this->*trim)(7)     : !(this->*trim)(5) + 2 :
                /* otherwise */    (this->*trim)(2) ? !(this->*trim)(3) + 4 : !(this->*trim)(1) + 6);
    }
};

inline bool operator==(const BitBoard& a, const BitBoard& b) { return a.bits == b.bits; }
inline bool operator!=(const BitBoard& a, const BitBoard& b) { return !(a == b); }

inline BitBoard operator&(const BitBoard& a, const BitBoard& b) { return {a.bits & b.bits}; }
inline BitBoard operator|(const BitBoard& a, const BitBoard& b) { return {a.bits | b.bits}; }
inline BitBoard operator^(const BitBoard& a, const BitBoard& b) { return {a.bits ^ b.bits}; }
inline BitBoard operator~(const BitBoard& b) { return {~b.bits}; }

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

static vec4 ballColors[] = {
    {1  , 0  , 0  , 1},
    {0  , 1  , 0  , 1},
    {0  , 0  , 1  , 1},
    {1  , 1  , 1  , 1},
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

    BitBoard cells;
    std::vector<MatteVertex> border;
    size_t count;

    Selection() : cells{0}, count(0) { }
};

struct Shape {
    std::vector<BitBoard> possibles;
    UIImage *repr;
};

struct Board {
    std::array<BitBoard, numBallColors> colors;

    bool operator<(const Board& b) const {
        for (int i = 0; i < numBallColors; ++i)
            if (colors[i].bits != b.colors[i].bits)
                return (colors[i].bits < b.colors[i].bits);
        return false;
    }

    BitBoard mask() const {
        return std::accumulate(begin(colors), end(colors), BitBoard{0}, [](BitBoard b, BitBoard c) { return b | c; });
    }

    void clear(int x, int y) {
        for (auto& c : colors)
            c.clear(x, y);
    }

    template <typename F>
    Board map(F f) const {
        std::array<BitBoard, numBallColors> colors;
        for (int i = 0; i < numBallColors; ++i)
            colors[i] = f(colors[i]);
        return {colors};
    }

    Board rotL   () const { return map([=](const BitBoard& b) { return b.rotL   (); }); }
    Board rotR   () const { return map([=](const BitBoard& b) { return b.rotR   (); }); }
    Board reverse() const { return map([=](const BitBoard& b) { return b.reverse(); }); }

    Board swCorner() const {
        BitBoard all = mask();
        int s = all.marginS();
        int w = all.marginW();
        return map([=](const BitBoard& b) { return b.shiftS(s).shiftW(w); });
    }

    Board canonical() const {
        return std::min(std::min(std::min(swCorner(), rotL().swCorner()), rotR().swCorner()), reverse().swCorner());
    }
};

@interface ViewController () {
    // Game state
    Board _board;
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

- (void)setupGL;
- (void)tearDownGL;
@end

@implementation ViewController

@synthesize tableView = _tableView;

- (void)setupGame {
    for (auto& b : _board.colors)
        b.bits = 0;
    for (int i = 0; i < 64; ++i)
        _board.colors[rand()%numBallColors].bits |= 1ULL << i;
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
            const BitBoard& bb = _board.colors[c];
            matte.vs.color = ballColors[c];

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
        BitBoard mask = _board.mask();
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
                if (cells.shiftN(5 - i).shiftE(5 - j).is_set(4, 4) != cells.shiftN(5 - i).shiftE(4 - j).is_set(4, 4)) {
                    vec2 a{x + 2.5, y + 2.5}, b{x + 2.5, y};
                    sel.border.push_back({{a, 0}, {0, 0, 1}});
                    sel.border.push_back({{b, 0}, {0, 0, 1}});
                }
                if (cells.shiftN(5 - i).shiftE(5 - j).is_set(4, 4) != cells.shiftN(4 - i).shiftE(5 - j).is_set(4, 4)) {
                    vec2 a{x, y + 2.5}, b{x + 2.5, y + 2.5};
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
        typedef std::array<std::vector<vec2>, numBallColors> Paths;

#if 0
        auto pathStr = [](const std::vector<vec2>& path) {
            std::ostringstream oss;
            for (auto v : path)
                oss << " [" << v.x << "," << v.y << "]";
            return oss.str();
        };

        auto reportPaths = [&](const Paths& paths) {
            auto path = begin(paths);
            for (const auto& c : ballColors) {
                if (&c == &ballColors[0])
                    NSLog(@"Paths:");
                NSLog(@"  {%g, %g, %g, %g}:%s", c.x, c.y, c.z, c.w, pathStr(*path).c_str());
                ++path;
            }
        };
#else
        auto reportPaths = [](const Paths&) { };
#endif

        auto sortPath = [](std::vector<vec2>& path) {
            std::sort(begin(path), end(path), [](const vec2& a, const vec2& b) { return a.x < b.x || (a.x == b.x && a.y < b.y); });
        };

        auto pathsForSelection = [&](const Selection& sel) {
            Paths paths;
            int n = 0;
            vec2 bl{8, 8}, tr{0, 0};
            auto path = begin(paths);
            for (int c = 0; c < numBallColors; ++c) {
                auto mask = sel.cells & _board.colors[c];
                for (int i = 0; i < 8; ++i)
                    for (int j = 0; j < 8; ++j)
                        if (mask.is_set(j, i)) {
                            vec2 v{j, i};
                            path->push_back(v);
                            bl = {std::min(bl.x, v.x), std::min(bl.y, v.y)};
                            tr = {std::max(tr.x, v.x), std::max(tr.y, v.y)};
                            ++n;
                        }
                sortPath(*path);
                ++path;
            }

            auto mid = 0.5*(bl + tr);
            for (auto& path : paths)
                for (auto& v : path)
                    v -= mid;

            reportPaths(paths);
            return paths;
        };

        auto p0 = pathsForSelection(_sels[0]);
        auto p1 = pathsForSelection(_sels[1]);
        auto rot = mat4::rotate(0.5*M_PI, {0, 0, 1});

        // Stabilise rot
        for (float *f = &rot.a.x; f != &rot.a.x + 16; ++f)
            *f = std::round(*f);

        for (int i = 0; i < 4; ++i) {
            if (std::equal(begin(p0), end(p0), begin(p1), [&](const std::vector<vec2>& a, const std::vector<vec2>& b) {
                return a.size() == b.size() && std::equal(begin(a), end(a), begin(b));
            })) {
                auto mask = _sels[0].cells | _sels[1].cells;
                for (int i = 0; i < 8; ++i)
                    for (int j = 0; j < 8; ++j)
                        if (mask.is_set(j, i))
                            _board.clear(j, i);
                break;
            }

            for (auto& path : p1) {
                for (auto& v : path)
                    v = (rot*vec4(v, {0, 1})).xy();
                sortPath(path);
            }
            reportPaths(p1);
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

- (void)updatePossibles {

}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
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
    
    cell.quantity.text = [NSString stringWithFormat:@"%d ×", 42];
    cell.shape.image = [UIImage imageNamed:@"appicon57.png"];
    
    return cell;
}

@end
