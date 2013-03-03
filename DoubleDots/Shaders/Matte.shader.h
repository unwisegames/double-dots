//
//  Sprite.shader.h
//  TiltBuggy
//
//  Created by Marcelo Cantos on 28/01/13.
//  Copyright (c) 2013 Marcelo Cantos. All rights reserved.
//

#ifdef BRICABRAC_VERTEX_SHADER

BRICABRAC_ATTRIBUTE(vec3, position)
BRICABRAC_ATTRIBUTE(vec3, normal)

BRICABRAC_UNIFORM(mat4, mvpMat)
BRICABRAC_UNIFORM(mat3, normalMat)
BRICABRAC_UNIFORM(vec4, color)

#ifndef BRICABRAC_HOSTED

varying vec4 v_color;

void main()
{
    vec3 eyeNormal = normalize(normalMat*normal);
    vec3 lightPosition = normalize(vec3(-1.0, 1.0, 3.0));

    float nDotVP = max(0.0, dot(eyeNormal, normalize(lightPosition)));

    v_color = color*nDotVP;

    gl_Position = mvpMat*vec4(position, 1.0);
}

#endif // BRICABRAC_HOSTED
#endif // BRICABRAC_VERTEX_SHADER
//
//::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
//
#ifdef BRICABRAC_FRAGMENT_SHADER

#ifndef BRICABRAC_HOSTED

varying lowp vec4 v_color;

void main() {
    gl_FragColor = v_color;
}

#endif // BRICABRAC_HOSTED
#endif // BRICABRAC_FRAGMENT_SHADER
