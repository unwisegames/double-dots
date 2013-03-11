//
//  ViewController.mm
//  HabeoMath
//
//  Created by Marcelo Cantos on 1/03/13.
//  Copyright (c) 2013 Habeo Soft. All rights reserved.
//

#import "ViewController.h"
#import "ShaderProgram.h"
#import "MathUtil.h"

#include <array>
#include <vector>
#include <mutex>
#include <bitset>
#include <cmath>
#include <algorithm>
#include <numeric>
#include <sstream>

using namespace squz;

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
    {1, 0, 0, 1},
    {0, 1, 0, 1},
    {0, 0, 1, 1},
    {1, 1, 1, 1},
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

    std::array<std::bitset<10>, 10> cells;
    std::vector<MatteVertex> border;
    size_t count;

    Selection() : count(0) { }
};

@interface ViewController () {
    std::array<std::array<vec4, 10>, 10> _balls;

    MatteProgram *_matte;

    mat4 _modelViewProjectionMatrix, _pick;
    mat3 _normalMatrix;
    float _rotation;

    std::array<Selection, 2> _sels;
    int _cursel;
    bool _moved;

    GLuint _sphereVerts, _sphereElems;
}
@property (strong, nonatomic) EAGLContext *context;

- (void)setupGL;
- (void)tearDownGL;
@end

@implementation ViewController

- (void)setupGame {
    for (auto& row : _balls)
        for (auto& b : row)
            b = ballColors[rand()%numBallColors];
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

    auto proj = mat4::ortho(-10.5*aspect, 10.5*aspect, -10.5, 10.5, -5, 5);
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
            if (!sel.border.empty() && !(!_moved && &sel == &_sels[_cursel])) {
                matte.vs.mvpMat = _modelViewProjectionMatrix;
                matte.vs.color  = vec4(borderColors[&sel - &_sels[0]]*(sel.count < Selection::threshold ? 0.5 : 1), 1);

                matte.vs.enableArray(sel.border.data());

                glLineWidth(3);

                glDrawArrays(GL_LINES, 0, sel.border.size());
            }

        matte.vs.enableVBO(_sphereVerts);
        matte.vs.enableElementVBO(_sphereElems);

        for (int i = 0; i < 8; ++i) {
            for (int j = 0; j < 8; ++j) {
                auto mvp = _modelViewProjectionMatrix*mat4::translate({2.5*j - 8.75, 2.5*i - 8.75, 0});

                matte.vs.mvpMat = mvp;
                matte.vs.color  = _balls[i + 1][j + 1];

                glDrawElements(GL_TRIANGLES, sph_elems, GL_UNSIGNED_SHORT, 0);
            }
        }
    }
}

- (void)handleTouch:(UITouch *)touch began:(bool)began {
    auto loc = [touch locationInView:self.view];
    auto size = self.view.bounds.size;

    vec2 pos = (((_pick*vec3{2*loc.x/size.width - 1, 1 - 2*loc.y/size.height, 0}) + vec3{8.75, 8.75, 0})*(1/2.5)).xy();
    float x = (int)(pos.x + 0.5 + 1);
    float y = (int)(pos.y + 0.5 + 1);

    if (1 <= x && x <= 8 && 1 <= y && y <= 8) {
        x = clamp(x, 1, 8);
        y = clamp(y, 1, 8);
        auto& sel = _sels[_cursel];
        auto& cells = sel.cells;
        if (!cells[y][x] && _balls[y][x].w && (began || cells[y][x - 1] || cells[y][x + 1] || cells[y - 1][x] || cells[y + 1][x])) {
            cells[y].set(x);
            ++sel.count;
        }

        // Redo border.
        sel.border.clear();
        for (int i = 0; i < 9; ++i) {
            float y = -8.75+2.5*(i - 1.5);
            for (int j = 0; j < 9; ++j) {
                float x = -8.75+2.5*(j - 1.5);
                if (cells[i][j] != cells[i][j + 1]) {
                    sel.border.push_back({{x + 2.5, y      , 0}, {0, 0, 1}});
                    sel.border.push_back({{x + 2.5, y + 2.5, 0}, {0, 0, 1}});
                }
                if (cells[i][j] != cells[i + 1][j]) {
                    sel.border.push_back({{x      , y + 2.5, 0}, {0, 0, 1}});
                    sel.border.push_back({{x + 2.5, y + 2.5, 0}, {0, 0, 1}});
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
            std::sort(begin(path), end(path), [](vec2 a, vec2 b) { return a.y < b.y || (a.y == b.y && a.x < b.x); });
        };

        auto pathsForSelection = [&](const Selection& sel) {
            Paths paths;
            int n = 0;
            vec2 bl{8, 8}, tr{0, 0};
            auto path = begin(paths);
            for (const auto& c : ballColors) {
                for (int i = 1; i <= 8; ++i)
                    for (int j = 1; j <= 8; ++j)
                        if (sel.cells[i][j] && _balls[i][j] == c) {
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
                for (int i = 1; i <= 8; ++i)
                    for (int j = 1; j <= 8; ++j)
                        if (_sels[0].cells[i][j] || _sels[1].cells[i][j])
                            _balls[i][j] = {0, 0, 0, 0};
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

@end
