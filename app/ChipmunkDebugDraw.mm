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

#include "chipmunk_private.h"

#include "ChipmunkDebugDraw.h"

#include <mutex>

#include <limits.h>
#include <string.h>

/*
 IMPORTANT - READ ME!

 This file sets up a simple interface that the individual demos can use to get
 a Chipmunk space running and draw what's in it. In order to keep the Chipmunk
 examples clean and simple, they contain no graphics code. All drawing is done
 by accessing the Chipmunk structures at a very low level. It is NOT
 recommended to write a game or application this way as it does not scale
 beyond simple shape drawing and is very dependent on implementation details
 about Chipmunk which may change with little to no warning.
 */

const cpColor LINE_COLOR = {1, 0, 1, 1};
const cpColor CONSTRAINT_COLOR = {0, 0.75, 0, 1};
const float SHAPE_ALPHA = 1;

static cpColor
ColorFromHash(cpHashValue hash, float alpha) {
	unsigned long val = (unsigned long)hash;

	// scramble the bits up using Robert Jenkins' 32 bit integer hash function
	val = (val+0x7ed55d16) + (val<<12);
	val = (val^0xc761c23c) ^ (val>>19);
	val = (val+0x165667b1) + (val<< 5);
	val = (val+0xd3a2646c) ^ (val<< 9);
	val = (val+0xfd7046c5) + (val<< 3);
	val = (val^0xb55a4f09) ^ (val>>16);

	float r = (val>> 0) & 0xFF;
	float g = (val>> 8) & 0xFF;
	float b = (val>>16) & 0xFF;

	float max = cpfmax(cpfmax(r, g), b);
	float min = cpfmin(cpfmin(r, g), b);
	float intensity = 0.75;

	// Saturate and scale the color
	if (min == max) {
		return cpRgbaColor(intensity, 0, 0, alpha);
	} else {
		float coef = alpha*intensity/(max - min);
		return cpRgbaColor((r - min)*coef, (g - min)*coef, (b - min)*coef, alpha);
	}
}

static cpColor ColorForShape(cpShape *shape)
{
	if (cpShapeGetSensor(shape)) {
		return cpLaColor(1, 0);
	} else {
		cpBody *body = shape->body;

		if (cpBodyIsSleeping(body)) {
			return cpLaColor(0.2, 1);
		} else if (body->node.idleTime > shape->space->sleepTimeThreshold) {
			return cpLaColor(0.66, 1);
		} else {
			return ColorFromHash(shape->hashid, SHAPE_ALPHA);
		}
	}
}

static void drawShape(cpShape *shape, void *context_) {
    auto context = (cpDebugDrawContext *)context_;
	cpBody *body = shape->body;
	cpColor color = ColorForShape(shape);

	switch(shape->klass->type){
		case CP_CIRCLE_SHAPE: {
			cpCircleShape *circle = (cpCircleShape *)shape;
			context->draw->circle(context->data, circle->tc, body->a, circle->r, LINE_COLOR, color);
			break;
		}
		case CP_SEGMENT_SHAPE: {
			cpSegmentShape *seg = (cpSegmentShape *)shape;
			context->draw->fatSegment(context->data, seg->ta, seg->tb, seg->r, LINE_COLOR, color);
			break;
		}
		case CP_POLY_SHAPE: {
			cpPolyShape *poly = (cpPolyShape *)shape;
			context->draw->polygon(context->data, poly->numVerts, poly->tVerts, LINE_COLOR, color);
			break;
		}
		default: break;
	}
}

void ChipmunkDebugDrawShape(cpShape *shape, void *context) {
	drawShape(shape, context);
}

void ChipmunkDebugDrawShapes(cpSpace *space, cpDebugDrawContext *context) {
	cpSpaceEachShape(space, &drawShape, (void *)context);
}

static const float springVAR[] = {
	0.00,  0,
	0.20,  0,
	0.25,  3,
	0.30, -6,
	0.35,  6,
	0.40, -6,
	0.45,  6,
	0.50, -6,
	0.55,  6,
	0.60, -6,
	0.65,  6,
	0.70, -3,
	0.75,  6,
	0.80,  0,
	1.00,  0,
};
static const int springVAR_count = sizeof(springVAR)/sizeof(float)/2;

static void drawSpring(cpDampedSpring *spring, cpBody *body_a, cpBody *body_b, cpDebugDrawContext *context) {
	cpVect a = cpvadd(body_a->p, cpvrotate(spring->anchr1, body_a->rot));
	cpVect b = cpvadd(body_b->p, cpvrotate(spring->anchr2, body_b->rot));

	cpVect points[] = {a, b};
	context->draw->points(context->data, 5, 2, points, CONSTRAINT_COLOR);

    // TODO
    /*
	cpVect delta = cpvsub(b, a);

	glVertexPointer(2, GL_FLOAT, 0, springVAR);
	glPushMatrix(); {
		float x = a.x;
		float y = a.y;
		float cos = delta.x;
		float sin = delta.y;
		float s = 1.0f/cpvlength(delta);

		const float matrix[] = {
            cos,    sin, 0.0f, 0.0f,
			-sin*s,  cos*s, 0.0f, 0.0f,
            0.0f,   0.0f, 1.0f, 0.0f,
            x,      y, 0.0f, 1.0f,
		};

		glMultMatrixf(matrix);
		glDrawArrays(GL_LINE_STRIP, 0, springVAR_count);
	} glPopMatrix();
     */
}

static void drawConstraint(cpConstraint *constraint, void *context_)
{
    auto context = (cpDebugDrawContext *)context_;
	cpBody *body_a = constraint->a;
	cpBody *body_b = constraint->b;

	const cpConstraintClass *klass = constraint->klass;
	if(klass == cpPinJointGetClass()){
		cpPinJoint *joint = (cpPinJoint *)constraint;

		cpVect a = cpvadd(body_a->p, cpvrotate(joint->anchr1, body_a->rot));
		cpVect b = cpvadd(body_b->p, cpvrotate(joint->anchr2, body_b->rot));

		cpVect points[] = {a, b};
		context->draw->points(context->data, 5, 2, points, CONSTRAINT_COLOR);
		context->draw->segment(context->data, a, b, CONSTRAINT_COLOR);
	} else if(klass == cpSlideJointGetClass()){
		cpSlideJoint *joint = (cpSlideJoint *)constraint;

		cpVect a = cpvadd(body_a->p, cpvrotate(joint->anchr1, body_a->rot));
		cpVect b = cpvadd(body_b->p, cpvrotate(joint->anchr2, body_b->rot));

		cpVect points[] = {a, b};
		context->draw->points(context->data, 5, 2, points, CONSTRAINT_COLOR);
		context->draw->segment(context->data, a, b, CONSTRAINT_COLOR);
	} else if(klass == cpPivotJointGetClass()){
		cpPivotJoint *joint = (cpPivotJoint *)constraint;

		cpVect a = cpvadd(body_a->p, cpvrotate(joint->anchr1, body_a->rot));
		cpVect b = cpvadd(body_b->p, cpvrotate(joint->anchr2, body_b->rot));

		cpVect points[] = {a, b};
		context->draw->points(context->data, 10, 2, points, CONSTRAINT_COLOR);
	} else if(klass == cpGrooveJointGetClass()){
		cpGrooveJoint *joint = (cpGrooveJoint *)constraint;

		cpVect a = cpvadd(body_a->p, cpvrotate(joint->grv_a, body_a->rot));
		cpVect b = cpvadd(body_a->p, cpvrotate(joint->grv_b, body_a->rot));
		cpVect c = cpvadd(body_b->p, cpvrotate(joint->anchr2, body_b->rot));

		context->draw->points(context->data, 5, 1, &c, CONSTRAINT_COLOR);
		context->draw->segment(context->data, a, b, CONSTRAINT_COLOR);
	} else if(klass == cpDampedSpringGetClass()){
		drawSpring((cpDampedSpring *)constraint, body_a, body_b, context);
	}
}

void ChipmunkDebugDrawConstraint(cpConstraint *constraint, void *context) {
	drawConstraint(constraint, context);
}

void ChipmunkDebugDrawConstraints(cpSpace *space, cpDebugDrawContext *context) {
	cpSpaceEachConstraint(space, drawConstraint, context);
}

void ChipmunkDebugDrawCollisionPoints(cpSpace *space, cpDebugDrawContext *context) {
	cpArray *arbiters = space->arbiters;

    for(int i=0; i<arbiters->num; i++){
        cpArbiter *arb = (cpArbiter*)arbiters->arr[i];

        cpColor color = {1, 1, 1, 1};
        for(int j=0; j<arb->numContacts; j++){
            context->draw->points(context->data, 4, 1, &arb->contacts[j].p, color);
        }
    }
}

void ChipmunkDebugDrawSpace(cpSpace *space, cpDebugDrawContext *context) {
    ChipmunkDebugDrawShapes(space, context);
    ChipmunkDebugDrawConstraints(space, context);
    ChipmunkDebugDrawCollisionPoints(space, context);
}

namespace chipmunk {

    void cpDebugDraw::space(cpSpace *space) {
        static cpDebugDrawCallbacks callbacks;
        static std::once_flag call_once_flag;
        std::call_once(call_once_flag, []{
            callbacks.circle     = cpDebugDraw::circle;
            callbacks.segment    = cpDebugDraw::segment;
            callbacks.fatSegment = cpDebugDraw::fatSegment;
            callbacks.polygon    = cpDebugDraw::polygon;
            callbacks.points     = cpDebugDraw::points;
            callbacks.bb         = cpDebugDraw::bb;
        });

        cpDebugDrawContext context = {&callbacks, this};
        ChipmunkDebugDrawSpace(space, &context);
    }

}
