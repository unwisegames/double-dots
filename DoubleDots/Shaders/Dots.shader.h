//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#ifdef BRICABRAC_VERTEX_SHADER

BRICABRAC_ATTRIBUTE(vec2, position)
BRICABRAC_ATTRIBUTE(vec2, texcoord)
BRICABRAC_ATTRIBUTE(vec2, dotcoord)

BRICABRAC_UNIFORM(mat4, pmvMat)

#ifndef BRICABRAC_HOSTED

varying vec2 v_texcoord;
varying vec2 v_dotcoord;

void main() {
    v_texcoord = texcoord;
    v_dotcoord = dotcoord;

    gl_Position = pmvMat*vec4(position, 0.0, 1.0);
}

#endif // BRICABRAC_HOSTED
#endif // BRICABRAC_VERTEX_SHADER
//
//::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
//
#ifdef BRICABRAC_FRAGMENT_SHADER

BRICABRAC_UNIFORM(sampler2D, atlas)
BRICABRAC_UNIFORM(sampler2D, dots)
BRICABRAC_UNIFORM(lowp vec4, color)

#ifndef BRICABRAC_HOSTED

varying mediump vec2 v_texcoord;
varying mediump vec2 v_dotcoord;

void main() {
    mediump vec4 color = texture2D(atlas, v_texcoord);
    mediump vec4 alpha = texture2D(dots , v_dotcoord);
    //color.a *= alpha.a;
    //color.rgb *= color.a;
    gl_FragColor = color * alpha;
}

#endif // BRICABRAC_HOSTED
#endif // BRICABRAC_FRAGMENT_SHADER
