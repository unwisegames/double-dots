//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#ifndef __DoubleDots__ChipmunkDebugDrawDoubleDots__
#define __DoubleDots__ChipmunkDebugDrawDoubleDots__

#include "ChipmunkDebugDraw.h"

#include <memory>

class ChipmunkDebugDrawDoubleDots : public chipmunk::cpDebugDraw {
public:
    ChipmunkDebugDrawDoubleDots();
    ~ChipmunkDebugDrawDoubleDots();

    template <typename C>
    void setShaderContext(C const & context);

    virtual void circle(cpVect center, cpFloat angle, cpFloat radius, cpColor lineColor, cpColor fillColor) override;
    virtual void segment(cpVect a, cpVect b, cpColor color) override;
    virtual void fatSegment(cpVect a, cpVect b, cpFloat radius, cpColor lineColor, cpColor fillColor) override;
    virtual void polygon(int count, cpVect *verts, cpColor lineColor, cpColor fillColor) override;
    virtual void points(cpFloat size, int count, cpVect *verts, cpColor color) override;
    virtual void bb(cpBB bb, cpColor color) override;

private:
    struct Members;
    std::unique_ptr<Members> m_;

    ChipmunkDebugDrawDoubleDots(ChipmunkDebugDrawDoubleDots const &) = delete;
    ChipmunkDebugDrawDoubleDots& operator=(ChipmunkDebugDrawDoubleDots const &) = delete;
    ChipmunkDebugDrawDoubleDots& operator=(ChipmunkDebugDrawDoubleDots &&) = delete;
};

#endif /* defined(__DoubleDots__ChipmunkDebugDrawDoubleDots__) */
