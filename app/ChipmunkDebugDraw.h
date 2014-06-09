/* Copyright (c) 2007 Scott Lembcke
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#ifndef INCLUDED__ChipmunkDebugDraw_h
#define INCLUDED__ChipmunkDebugDraw_h

#include "chipmunk.h"

#ifdef __cplusplus
extern "C" {
#endif

    typedef struct cpColor {
        float r, g, b, a;
    } cpColor;

    static inline cpColor cpRgbaColor(float r, float g, float b, float a){
        cpColor color = {r, g, b, a};
        return color;
    }

    static inline cpColor cpLaColor(float l, float a){
        cpColor color = {l, l, l, a};
        return color;
    }

    typedef void (*ChipmunkDebugDrawCircle    )(void *data, cpVect center, cpFloat angle, cpFloat radius, cpColor lineColor, cpColor fillColor);
    typedef void (*ChipmunkDebugDrawSegment   )(void *data, cpVect a, cpVect b, cpColor color);
    typedef void (*ChipmunkDebugDrawFatSegment)(void *data, cpVect a, cpVect b, cpFloat radius, cpColor lineColor, cpColor fillColor);
    typedef void (*ChipmunkDebugDrawPolygon   )(void *data, int count, cpVect *verts, cpColor lineColor, cpColor fillColor);
    typedef void (*ChipmunkDebugDrawPoints    )(void *data, cpFloat size, int count, cpVect *verts, cpColor color);
    typedef void (*ChipmunkDebugDrawBB        )(void *data, cpBB bb, cpColor color);

    typedef struct cpDebugDrawCallbacks {
        ChipmunkDebugDrawCircle     circle;
        ChipmunkDebugDrawSegment    segment;
        ChipmunkDebugDrawFatSegment fatSegment;
        ChipmunkDebugDrawPolygon    polygon;
        ChipmunkDebugDrawPoints     points;
        ChipmunkDebugDrawBB         bb;
    } cpDebugDrawCallbacks;

    typedef struct cpDebugDrawContext {
        cpDebugDrawCallbacks *draw;
        void *data;
    } cpDebugDrawContext;
    
    void ChipmunkDebugDrawSpace(cpSpace *space, cpDebugDrawContext *callbacks);
    
#ifdef __cplusplus
}

namespace chipmunk {

    class cpDebugDraw {
    public:
        void space(cpSpace *space);

    private:
        virtual void circle    (cpVect center, cpFloat angle, cpFloat radius, cpColor lineColor, cpColor fillColor) = 0;
        virtual void segment   (cpVect a, cpVect b, cpColor color) = 0;
        virtual void fatSegment(cpVect a, cpVect b, cpFloat radius, cpColor lineColor, cpColor fillColor) = 0;
        virtual void polygon   (int count, cpVect *verts, cpColor lineColor, cpColor fillColor) = 0;
        virtual void points    (cpFloat size, int count, cpVect *verts, cpColor color) = 0;
        virtual void bb        (cpBB bb, cpColor color) = 0;

        static void circle    (void *data, cpVect center, cpFloat angle, cpFloat radius, cpColor lineColor, cpColor fillColor) {
            ((cpDebugDraw *)data)->circle(center, angle, radius, lineColor, fillColor);
        }
        static void segment   (void *data, cpVect a, cpVect b, cpColor color) {
            ((cpDebugDraw *)data)->segment(a, b, color);
        }
        static void fatSegment(void *data, cpVect a, cpVect b, cpFloat radius, cpColor lineColor, cpColor fillColor) {
            ((cpDebugDraw *)data)->fatSegment(a, b, radius, lineColor, fillColor);
        }
        static void polygon   (void *data, int count, cpVect *verts, cpColor lineColor, cpColor fillColor) {
            ((cpDebugDraw *)data)->polygon(count, verts, lineColor, fillColor);
        }
        static void points    (void *data, cpFloat size, int count, cpVect *verts, cpColor color) {
            ((cpDebugDraw *)data)->points(size, count, verts, color);
        }
        static void bb        (void *data, cpBB bb, cpColor color) {
            ((cpDebugDraw *)data)->bb(bb, color);
        }
    };

}

#endif

#endif // INCLUDED__ChipmunkDebugDraw_h
