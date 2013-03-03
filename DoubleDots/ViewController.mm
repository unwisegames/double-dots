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

using namespace squz;

#define BRICABRAC_SHADER_NAME Matte
#include "LoadShaders.h"
typedef bricabrac::ShaderProgram<MatteVertexShader, MatteFragmentShader> MatteProgram;
typedef MatteVertexShader::Vertex MatteVertex;

vec4 rgb_to_hsv(vec4 c) {
    float min = std::min(c.x, std::min(c.y, c.z));
    float max = std::max(c.x, std::max(c.y, c.z));
    float delta = max - min;

    float v = max;
    float s = max ? delta/max : 0;
    float h = (delta    ? (1/6.0)*(max == c.x ?     (c.y - c.z)/delta :    // between yellow & magenta
                                   max == c.y ? 2 + (c.z - c.x)/delta :    // between cyan & yellow
                                   /* else */   4 + (c.x - c.y)/delta ) :  // between magenta & cyan
               /*else*/   0);

    if (h < 0) h += 1;

    return {h, s, v, c.w};
}

vec4 hsv_to_rgb(vec4 c) {
    float hh = 6*c.x;
    int i = hh;
    float ff = hh - i;
    float p = c.z * (1 - c.y);
    float q = c.z * (1 - c.y*ff);
    float t = c.z * (1 - c.y*(1 - ff));

    switch (i) {
        case 0 : return {c.z, t, p, c.w};
        case 1 : return {q, c.z, p, c.w};
        case 2 : return {p, c.z, t, c.w};
        case 3 : return {p, q, c.z, c.w};
        case 4 : return {t, p, c.z, c.w};
        default: return {c.z, p, q, c.w};
    }
}

vec4 blendColors(vec4 p, vec4 q) {
    p = rgb_to_hsv(p);
    q = rgb_to_hsv(q);
    vec4 r = 0.5*(p + q);

    // Find the closest mean hue (could be one of two, because hue is modular).
    auto meanHue = [](const vec4& u, const vec4& v) {
        float h1 = u.x, h2 = v.x;
        float s1 = u.y, s2 = v.y; // Weight hues by saturation.
        float h3 = h1 + 1;
        float S = s1 + s2;
        return fmodf(((h2 - h1 < h3 - h2 ? h1 : h3)*s1 + h2*s2)*(S ? 1/S : 0), 1);
    };
    r.x = p.x < q.x ? meanHue(p, q) : meanHue(q, p);

    return hsv_to_rgb(r);
}

enum {
    sph_layers = 16,
    sph_segments = 32,
    sph_verts = sph_layers*sph_segments + 1,
    sph_elems = 6*sph_layers*sph_segments,
};

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
    std::array<std::bitset<11>, 11> cells;
    std::vector<MatteVertex> border;

    void clear() {
        for (auto& row : cells)
            row.reset();
        border.clear();
    }
};

@interface ViewController () {
    std::array<std::array<vec4, 11>, 11> _balls;

    MatteProgram *_matte;

    mat4 _modelViewProjectionMatrix, _pick;
    mat3 _normalMatrix;
    float _rotation;

    std::array<Selection, 2> _sels;
    int _cursel;

    GLuint _sphereVerts, _sphereElems;
}
@property (strong, nonatomic) EAGLContext *context;

- (void)setupGL;
- (void)tearDownGL;
@end

@implementation ViewController

- (void)setupGame {
    vec4 colors[] = {
        {1, 0, 0, 1},
        {0, 1, 0, 1},
        {0, 0, 1, 1},
        {1, 1, 1, 1},
        {0, 0, 0, 1},
    };

    for (auto& row : _balls)
        for (auto& b : row)
            b = colors[rand()%(std::end(colors) - std::begin(colors))];
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

    auto proj = mat4::ortho(-14*aspect, 14*aspect, -14, 14, -5, 5);
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

        vec4 borderColors[2] = {{1, 1, 0, 1}, {0.5, 0.5, 1, 1}};
        for (auto& sel : _sels)
            if (!sel.border.empty()) {
                matte.vs.mvpMat = _modelViewProjectionMatrix;
                matte.vs.color  = borderColors[&sel - &_sels[0]];

                matte.vs.enableArray(sel.border.data());

                glLineWidth(3);

                glDrawArrays(GL_LINES, 0, sel.border.size());
            }

        matte.vs.enableVBO(_sphereVerts);
        matte.vs.enableElementVBO(_sphereElems);

        for (int i = 0; i < 10; ++i) {
            for (int j = 0; j < 10; ++j) {
                auto mvp = _modelViewProjectionMatrix*mat4::translate({-11.25+2.5*j, -11.25+2.5*i, 0});

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

    vec2 pos = (((_pick*vec3{2*loc.x/size.width - 1, 1 - 2*loc.y/size.height, 0}) + vec3{11.25, 11.25, 0})*(1/2.5)).xy();
    float x = (int)(pos.x + 0.5 + 1);
    float y = (int)(pos.y + 0.5 + 1);

    if (1 <= x && x <= 10 && 1 <= y && y <= 10) {
        x = clamp(x, 1, 10);
        y = clamp(y, 1, 10);
        auto& sel = _sels[_cursel];
        auto& cells = sel.cells;
        if (began || (!cells[y][x] && (cells[y][x - 1] || cells[y][x + 1] || cells[y - 1][x] || cells[y + 1][x]))) {
            cells[y].set(x);
        }

        // Redo border.
        sel.border.clear();
        for (int i = 0; i < 11; ++i) {
            float y = -11.25+2.5*(i - 1.5);
            for (int j = 0; j < 11; ++j) {
                float x = -11.25+2.5*(j - 1.5);
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
    _sels[_cursel].clear();
    [self handleTouch:[touches anyObject] began:true];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    [self handleTouch:[touches anyObject] began:false];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!(_cursel = (_cursel + 1)%2)) {

    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    _sels[_cursel].clear();
}

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (motion == UIEventSubtypeMotionShake)
        [self setupGame];
}

@end
