//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#include "GameRenderer.h"
#include "GameState.h"

#include "MathUtil.h"
#include "Texture2D.hpp"
#include "Color.h"

#include <OpenGLES/ES2/glext.h>

#include <array>
#include <mutex>
#include <vector>
#include <unordered_map>
#include <memory>
#include <algorithm>

#define BRICABRAC_SHADER_NAME Matte
#include "LoadShaders.h"
#define BRICABRAC_SHADER_NAME Border
#include "LoadShaders.h"
#define BRICABRAC_SHADER_NAME Dots
#include "LoadShaders.h"
#define BRICABRAC_SHADER_NAME Board
#include "LoadShaders.h"

using namespace brac;

static constexpr float gEdgeThickness   = 0.5;
static constexpr float gScaleLimit      = 2;
static           float gLogScaleLimit   = std::log(gScaleLimit);

static std::array<Color, 5> selectionColors = {{
    {1  , 0.7, 0.1},
    {0.5, 0.7, 1  },
    {0.9, 0.6, 1  },
    {0.5, 0.8, 0.3},
    {1  , 0.5, 0.5},
}};

static brac::vec2 blue   {0.25, 0.25};
static brac::vec2 red    {0.5 , 0.25};
static brac::vec2 purple {0.75, 0.25};
static brac::vec2 green  {0.5 , 0.5 };
static brac::vec2 dkblue {0.75, 0.5 };
static brac::vec2 white  {0.5 , 0.75};
static brac::vec2 yellow {0.75, 0.75};

typedef std::unordered_map<size_t, BorderVertexBuffer> Borders;

struct RgbaPixel {
    GLubyte r, g, b, a;
};

struct GameRenderer::Members {
    std::shared_ptr<GameState> game;
    size_t colorSet;

    std::function<void(size_t)> colorSetChanged;
    std::function<void()>       refreshScene;
    std::function<void()>       cancelTapGesture;

    std::unique_ptr<MatteProgram    > matte    ;
    std::unique_ptr<BorderProgram   > border   ;
    std::unique_ptr<DotsProgram     > dots     ;
    std::unique_ptr<BoardProgram    > board    ;

    int nBoardRows = 0, nBoardCols = 0;
    float viewHeight = 0, edgeThickness = 0, aspect = 1;

    mat4 pmvMatrix, pick;
    mat3 normalMatrix;
    Tex2D atlas, dotStates, surface, dimple, edging;
    RgbaPixel dotsData[16 * 16];
    DotsVertexBuffer vboDots;
    ElementBuffer<> eboDots;
    BoardVertexBuffer vboBoardInterior, vboBoardEdge, vboSeparator;

    Borders borders;

    std::weak_ptr<ShapeMatches> shapeMatchesToHint;
    int nextMatchToHint = 0;
    float hintIntensity = 0;
    std::array<BorderVertexBuffer, 2> vboHints;

    Members(std::shared_ptr<GameState> const & game, size_t colorSet) : game(game), colorSet(colorSet) { }

    std::vector<BorderVertex> prepareSelectionBorder(brac::BitBoard const & bb) {
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

        for (int y = 0; y < nBoardRows; ++y)
            for (int x = 0; x < nBoardCols; ++x) {
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
            std::cerr << "Huh?\n";
        }
        return border;
    }

    void updateDots() {
        if (game) {
            auto const & board = game->board();
            int nCells = nBoardRows * nBoardCols;
            std::vector<DotsVertex> dotsVertsData; dotsVertsData.reserve(4 * nCells);
            auto vi = back_inserter(dotsVertsData);
            for (size_t y = 0; y < nBoardRows; ++y)
                for (size_t x = 0; x < nBoardCols; ++x) {
                    vec2 position{ x            ,  y            };
                    vec2 dotcoord{(x + 0.5) / 16, (y + 0.5) / 16};
                    constexpr float s = 0.25;
                    int c = board.color(x, y);
                    vec2 tc = GameRenderer::dots[colorSet][c];
                    *vi++ = {position             , tc + vec2{0, s}, dotcoord};
                    *vi++ = {position + vec2{1, 0}, tc + vec2{s, s}, dotcoord};
                    *vi++ = {position + vec2{1, 1}, tc + vec2{s, 0}, dotcoord};
                    *vi++ = {position + vec2{0, 1}, tc             , dotcoord};
                }
            assert(dotsVertsData.size() == 4 * nCells);
            vboDots.data(dotsVertsData);

            std::vector<GLushort> dotsElemsData; dotsElemsData.reserve(6 * nCells);
            auto ei = back_inserter(dotsElemsData);
            for (size_t i = 0, y = 0; y < nBoardRows; ++y)
                for (size_t x = 0; x < nBoardCols; ++x, i += 4) {
                    size_t elems[] = { i, i + 1, i + 2, i, i + 2, i + 3 };
                    ei = std::copy(std::begin(elems), std::end(elems), ei);
                }
            assert(dotsElemsData.size() == 6 * nCells);
            eboDots.data(dotsElemsData);
        }
    }
};

std::array<std::array<brac::vec2, 5>, 2> GameRenderer::dots = {{
    {{red, green,   blue, purple, yellow}},
    {{red, green, dkblue, purple, white }},
}};

GameRenderer::GameRenderer(std::shared_ptr<GameState> const & game, size_t colorSet)
: m(std::make_shared<Members>(game, colorSet))
{

}

void GameRenderer::setGame(const std::shared_ptr<GameState> &game) {
    m->game = game;

    float scale = game->height() / 16.0;

    m->nBoardCols = game->width();
    m->nBoardRows = game->height();
    m->edgeThickness = gEdgeThickness * scale;
    m->viewHeight = m->nBoardRows + 2 * m->edgeThickness;

    m->game->onSelectionChanged([=]{
        auto const & sels = m->game->sels();

        // Remove deselected borders.
        for (auto i = begin(m->borders); i != end(m->borders);) {
            auto s = sels.find(i->first);
            if (s != end(sels) && s->second.has_border()) {
                ++i;
            } else {
                i = m->borders.erase(i);
            }
        }

        // Update modified borders and create new borders.
        for (auto const & sel : sels)
            if (sel.second.has_border()) {
                auto verts = m->prepareSelectionBorder(sel.second.is_selected);
                auto i = m->borders.find(sel.first);
                if (i == end(m->borders)) {
                    m->borders.emplace(sel.first, BorderVertexBuffer{verts});
                } else {
                    i->second.data(verts);
                }
            }
        m->refreshScene();
    });

    m->game->onBoardChanged([=]{
        auto mask = m->game->board().computeMask();
        for (size_t y = 0; y < 16; ++y)
            for (size_t x = 0; x < 16; ++x) {
                GLubyte v = mask.isSet(x, y) * 0xff;
                m->dotsData[16 * y + x] = {v, v, v, v};
            }

        m->dotStates.paste({m->dotsData, Tex2D::PixelFormat::Rgba8888, 16, 16, {16, 16}}, {0, 0});
        m->refreshScene();
    });

    m->game->onCancelTapGesture([=]{
        m->cancelTapGesture();
    });


    float s = 2.7 / m->nBoardCols;

    auto bvert = [=](vec2 p, vec2 l) {
        return BoardVertex{p, p * s, l};
    };

    m->vboBoardInterior = BoardVertexBuffer{
        bvert({0            , m->nBoardRows}, {0            , m->nBoardRows}),
        bvert({0            , 0            }, {0            , 0            }),
        bvert({m->nBoardCols, m->nBoardRows}, {m->nBoardCols, m->nBoardRows}),
        bvert({m->nBoardCols, 0            }, {m->nBoardCols, 0            }),
    };

    constexpr float ext = 5.7;
    float e = m->edgeThickness;

    auto edge = [&](int x, int y, int ox, int oy) {
        return bvert({(m->nBoardCols + ext) * x + e * ox, m->nBoardRows * y + e * oy}, {0.5 * (ox + 1), 0.5 * (oy + 1)});
    };

    auto e00 = edge(0, 0, -1, -1);
    auto e01 = edge(0, 0,  0, -1);
    auto e02 = edge(1, 0,  0, -1);
    auto e03 = edge(1, 0,  1, -1);
    auto e04 = edge(0, 0, -1,  0);
    auto e05 = edge(0, 0,  0,  0);
    auto e06 = edge(1, 0,  0,  0);
    auto e07 = edge(1, 0,  1,  0);
    auto e08 = edge(0, 1, -1,  0);
    auto e09 = edge(0, 1,  0,  0);
    auto e10 = edge(1, 1,  0,  0);
    auto e11 = edge(1, 1,  1,  0);
    auto e12 = edge(0, 1, -1,  1);
    auto e13 = edge(0, 1,  0,  1);
    auto e14 = edge(1, 1,  0,  1);
    auto e15 = edge(1, 1,  1,  1);

    auto i0 = bvert({m->nBoardCols      , 0            }, {0.5, 0.5});
    auto i1 = bvert({m->nBoardCols + ext, 0            }, {0.5, 0.5});
    auto i2 = bvert({m->nBoardCols      , m->nBoardRows}, {0.5, 0.5});
    auto i3 = bvert({m->nBoardCols + ext, m->nBoardRows}, {0.5, 0.5});

    m->vboBoardEdge = BoardVertexBuffer{
        i0 , i1 , i2 , i3 , i3 , e00,   // Sidebar
        e00, e01, e05, e02, e06, e03,   // Bottom edge
        e03, e07, e06, e11, e10, e15,   // Right edge
        e15, e14, e10, e13, e09, e12,   // Top edge
        e12, e08, e09, e04, e05, e00,   // Left edge
    };

    {
        float x0 = m->nBoardCols + 0.35 * scale;
        float y0 = m->nBoardRows;
        float y1 = 2.25 * scale;
        float x2 = x0 + 2.25 * scale;
        float y2 = 0;
        float gr = 0.2 * scale;
        float r1 = 0.5 * scale;
        float r2 = 1.25 * scale;
        size_t stitchSite = 0;

        std::vector<BoardVertex> verts; verts.reserve(100);
        auto joint = [&](vec2 p, float angle, float u) {
            float c = std::cos(angle), s = std::sin(angle);
            verts.push_back(bvert({p.x - gr * s, p.y + gr * c}, {0.5 * (1 - s + c * u), 0.5 * (1 + c + s * u)}));
            verts.push_back(bvert({p.x + gr * s, p.y - gr * c}, {0.5 * (1 + s + c * u), 0.5 * (1 - c + s * u)}));
        };
        auto arc = [&](vec2 center, float r, float a1, float a2) {
            size_t n = 24 / M_PI * std::fabs(a2 - a1);
            float delta = (a2 - a1) / n;
            for (size_t i = 0; i <= n; ++i, a1 += delta) {
                float c = std::cos(a1), s = std::sin(a1);
                joint(center + (r * vec2{s, -c}), a1, 0);
            }
        };
        auto stitch = [&](bool final) {
            if (stitchSite) {
                verts[stitchSite    ] = verts[stitchSite - 1];
                verts[stitchSite + 1] = verts[stitchSite + 2];
            }
            stitchSite = verts.size();
            if (!final)
                verts.resize(verts.size() + 2);
        };

#if 1
        joint({x2 - r2                 , y1     }, 0, 0);
        joint({m->nBoardCols + ext     , y1     }, 0, 0);
        joint({m->nBoardCols + ext + gr, y1     }, 0, 1);
        stitch(false);
        joint({x0     , y0 + gr},      -M_PI/2         , -1);
        joint({x0     , y0     },      -M_PI/2         ,  0);
        arc  ({x0 + r1, y1 + r1},  r1, -M_PI/2,  0         );
        arc  ({x2 - r2, y1 - r2}, -r2,  0     , -M_PI/2    );
        joint({x2     , y2     },               -M_PI/2,  0);
        joint({x2     , y2 - gr},               -M_PI/2,  1);
        stitch(true);
#else
        arc  ({x0 + r1, y1 + r1},  r1, -M_PI/2,  0         );
        arc  ({x2 - r2, y1 - r2}, -r2,  0     , -M_PI/2    );
#endif
        m->vboSeparator = verts;
    }

    m->updateDots();
}

void GameRenderer::setColorSet(size_t colorSet) {
    m->colorSet = colorSet;
    m->updateDots();
    m->colorSetChanged(colorSet);
}

void GameRenderer::setBackgroundColor(Color const & bg) {
    glClearColor(bg.r, bg.g, bg.b, bg.a);
}

void GameRenderer::setViewAspectRatio(float aspect) {
    m->aspect = aspect;
}

std::shared_ptr<GameState> const &  GameRenderer::game      () const { return m->game               ; }
size_t                              GameRenderer::colorSet  () const { return m->colorSet           ; }

void GameRenderer::onColorSetChanged(std::function<void(size_t)> const & f) {
    m->colorSetChanged = f;
}

void GameRenderer::toRefreshScene(std::function<void()> const & f) {
    m->refreshScene = f;
}

void GameRenderer::toCancelTapGesture(std::function<void()> const & f) {
    m->cancelTapGesture = f;
}

void GameRenderer::hint(std::shared_ptr<ShapeMatches> const & sm) {
    if (auto hinted = m->shapeMatchesToHint.lock()) {
        if (hinted != sm) {
            m->shapeMatchesToHint = sm;
            m->nextMatchToHint = 0;
        }
    } else {
        m->shapeMatchesToHint = sm;
        m->nextMatchToHint = 0;
    }

    if (sm) {
        const auto& match = sm->matches[m->nextMatchToHint++ % sm->matches.size()];
        m->vboHints[0].data(m->prepareSelectionBorder(match.shape1));
        m->vboHints[1].data(m->prepareSelectionBorder(match.shape2));
        m->hintIntensity = 1;
    }

    m->refreshScene();
}

brac::vec2 GameRenderer::pick(brac::vec2 const & v) const {
    return (m->pick * vec3{v, 0}).xy();
}

bool GameRenderer::isOnBoard(brac::vec2 const & v) const {
    return 0 <= v.x && v.x < m->nBoardCols && 0 <= v.y && v.y < m->nBoardRows;
}

void GameRenderer::setupGL() {
    m->matte  .reset(new  MatteProgram);
    m->border .reset(new BorderProgram);
    m->dots   .reset(new   DotsProgram);
    m->board  .reset(new  BoardProgram);

    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

    auto loadImageTexture = [](const char *name, bool repeat) {
        Tex2D tex{std::make_shared<Image>(name)};
        glGenerateMipmap(GL_TEXTURE_2D);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR_MIPMAP_NEAREST);
        if (repeat) {
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
        }
        return tex;
    };

    m->atlas   = loadImageTexture("atlas.png"  , false);
    m->surface = loadImageTexture("surface.png", true ); // http://seamless-pixels.blogspot.com.au/2012/09/seamless-floor-concrete-stone-pavement.html
    m->dimple  = loadImageTexture("dimple.png" , true );
    m->edging  = loadImageTexture("edging.png" , false);

    m->dotStates = {{m->dotsData, Tex2D::PixelFormat::Rgba8888, 16, 16, {16, 16}}};

    m->vboDots        = m->vboDots      .empty();
    m->eboDots        = m->eboDots      .empty();
    m->vboBoardEdge   = m->vboBoardEdge .empty();

    for (size_t i = 0; i < 2; ++i)
        m->vboHints[i] = m->vboHints[i].empty();

    if (auto border = (*m->border)()) {
        border.fs.atlas = 0;
    }

    if (auto dots = (*m->dots)()) {
        dots.fs.atlas = 0;
        dots.fs.dots  = 1;
    }

    if (auto board = (*m->board)()) {
        board.fs.texture = 0;
        board.fs.light   = 1;
    }
}

void GameRenderer::update(float dt) {
    if (!m->game) return;

    auto proj = mat4::ortho(0, m->viewHeight * m->aspect, 0, m->viewHeight, -5, 5);
    //proj *= mat4::scale(0.2) * mat4::translate({40, 40, 0});

    auto mv = mat4::translate({m->edgeThickness, m->edgeThickness, 0});

    m->pmvMatrix = proj * mv;
    m->normalMatrix = mv.ToMat3().inverse().transpose();
    m->pick = m->pmvMatrix.inverse();

    if (m->hintIntensity) {
        if ((m->hintIntensity -= dt) < 0)
            m->hintIntensity = 0;
        m->refreshScene();
    }
}

void GameRenderer::render() {
    if (!m->game) return;

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    if (auto board = (*m->board)()) {
        board.vs.pmvMat = m->pmvMatrix;
        board.vs.texMat = mat4::rotate(0.5, {0, 0, 1});
        board.fs.color = {1, 1, 1, 1};

        m->surface.activateAndBind();

        m->edging.activateAndBind(GL_TEXTURE1);
        m->vboBoardEdge.render(board, GL_TRIANGLE_STRIP);

        m->dimple.activateAndBind(GL_TEXTURE1);
        m->vboBoardInterior.render(board, GL_TRIANGLE_STRIP);
        m->vboSeparator.render(board, GL_TRIANGLE_STRIP);
    }

    m->atlas.activateAndBind(GL_TEXTURE0);
    m->dotStates.activateAndBind(GL_TEXTURE1);

    if (auto border = (*m->border)()) {
        border.vs.pmvMat = m->pmvMatrix;

        for (auto const & sel : m->game->sels()) {
            auto b = m->borders.find(sel.first);
            if (b != m->borders.end() && b->second) {
                border.fs.color = vec4{(vec3)selectionColors[sel.first % selectionColors.size()] * (1 - 0.5 * (sel.second.is_selected.count() < GameState::minimumSelection)), 1};

                b->second.render(border, GL_TRIANGLES);
            }
        }

        if (m->hintIntensity) {
            border.fs.color = vec4{1, 1, 1, 1} * m->hintIntensity;
            for (const auto& hint : m->vboHints)
                hint.render(border, GL_TRIANGLES);
        }
    }

    if (auto dots = (*m->dots)()) {
        dots.vs.pmvMat = m->pmvMatrix;

        m->eboDots.render(dots, m->vboDots, GL_TRIANGLES);
    }

    Tex2D::activateAndUnbind(GL_TEXTURE0);
    Tex2D::activateAndUnbind(GL_TEXTURE1);
}
