//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#ifdef BRICABRAC_VERTEX_SHADER

BRICABRAC_ATTRIBUTE(vec2, position)
BRICABRAC_ATTRIBUTE(vec2, texcoord)

BRICABRAC_UNIFORM(mat4, pmvMat)

#ifndef BRICABRAC_HOSTED

varying vec2 v_texcoord;

void main() {
    v_texcoord = texcoord;

    gl_Position = pmvMat*vec4(position, 0.0, 1.0);
}

#endif // BRICABRAC_HOSTED
#endif // BRICABRAC_VERTEX_SHADER
//
//::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
//
#ifdef BRICABRAC_FRAGMENT_SHADER

BRICABRAC_UNIFORM(sampler2D, atlas)
BRICABRAC_UNIFORM(lowp vec4, color)

#ifndef BRICABRAC_HOSTED

varying mediump vec2 v_texcoord;

void main() {
    mediump vec4 v = texture2D(atlas, v_texcoord);
    gl_FragColor = color*v*v.a;
}

#endif // BRICABRAC_HOSTED
#endif // BRICABRAC_FRAGMENT_SHADER
