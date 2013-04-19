//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#include "ChipmunkDebugDrawDoubleDots.h"

#define BRICABRAC_SHADER_NAME Matte
#include "LoadShaders.h"

struct ChipmunkDebugDrawDoubleDots::Members {
    const MatteProgram::Context *context_;

    void setColor(const cpColor& color, float alpha = 1) {
        context_->vs.color = {color.r, color.g, color.b, color.a*alpha};
    }
};

ChipmunkDebugDrawDoubleDots::ChipmunkDebugDrawDoubleDots() : m_(new Members) { }
ChipmunkDebugDrawDoubleDots::~ChipmunkDebugDrawDoubleDots() { }

template <>
void ChipmunkDebugDrawDoubleDots::setShaderContext<MatteProgram::Context>(MatteProgram::Context const & context) {
    m_->context_ = &context;
}

void ChipmunkDebugDrawDoubleDots::circle(cpVect center, cpFloat angle, cpFloat radius, cpColor lineColor, cpColor fillColor) {
    cpVect vertices[32];
    for (int i = 0; i < 32; ++i)
        vertices[i] = cpvforangle(2*M_PI*i/32);
    m_->context_->vs.enableArray((MatteVertexShader::Vertex *)vertices);

    //setColor(fillColor, 0.5); glDrawArrays(GL_TRIANGLE_FAN, 0, 32);
    m_->setColor(lineColor);      glDrawArrays(GL_LINES, 0, 32);
}

void ChipmunkDebugDrawDoubleDots::segment(cpVect a, cpVect b, cpColor color) {
    m_->setColor(color);

    MatteVertexShader::Vertex vertices[] = { {{a.x, a.y, 0}, {0, 0, 1}}, {{b.x, b.y, 0}, {0, 0, 1}} };
    m_->context_->vs.enableArray(vertices);
    glLineWidth(3);
    glDrawArrays(GL_LINES, 0, 2);
}

void ChipmunkDebugDrawDoubleDots::fatSegment(cpVect a, cpVect b, cpFloat radius, cpColor lineColor, cpColor fillColor) {
    m_->setColor(lineColor, 0.5);

    MatteVertexShader::Vertex vertices[] = { {{a.x, a.y, 0}, {0, 0, 1}}, {{b.x, b.y, 0}, {0, 0, 1}} };
    m_->context_->vs.enableArray(vertices);
    // TODO
    glLineWidth(2*radius);
    glDrawArrays(GL_LINES, 0, 2);
}

void ChipmunkDebugDrawDoubleDots::polygon(int count, cpVect *verts, cpColor lineColor, cpColor fillColor) {
    m_->context_->vs.enableArray((MatteVertexShader::Vertex *)verts);

    //setColor(fillColor, 0.5); glDrawArrays(GL_TRIANGLE_FAN, 0, count);
    m_->setColor(lineColor);      glDrawArrays(GL_LINES, 0, count);
}

void ChipmunkDebugDrawDoubleDots::points(cpFloat size, int count, cpVect *verts, cpColor color) {
    m_->context_->vs.enableArray((MatteVertexShader::Vertex *)verts);

    m_->setColor(color); glDrawArrays(GL_POINTS, 0, count);
}

void ChipmunkDebugDrawDoubleDots::bb(cpBB bb, cpColor color) {
    MatteVertexShader::Vertex vertices[] = {
        {{bb.l, bb.t, 0}, {0, 0, 1}},
        {{bb.l, bb.b, 0}, {0, 0, 1}},
        {{bb.r, bb.b, 0}, {0, 0, 1}},
        {{bb.r, bb.t, 0}, {0, 0, 1}},
        {{bb.l, bb.t, 0}, {0, 0, 1}},
    };
    m_->context_->vs.enableArray(vertices);
    m_->setColor(color); glDrawArrays(GL_LINE_STRIP, 0, 5);
}
