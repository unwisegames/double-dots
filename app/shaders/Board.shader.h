//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#ifdef BRICABRAC_VERTEX_SHADER

BRICABRAC_ATTRIBUTE(vec2, position  )
BRICABRAC_ATTRIBUTE(vec2, texcoord  )
BRICABRAC_ATTRIBUTE(vec2, lightcoord)

BRICABRAC_UNIFORM(mat4, pmvMat)
BRICABRAC_UNIFORM(mat4, texMat)

#ifndef BRICABRAC_HOSTED

varying vec2 v_texcoord;
varying vec2 v_lightcoord;

void main() {
    v_texcoord   = (texMat * vec4(texcoord, 0, 1)).xy;
    v_lightcoord = lightcoord;

    gl_Position = pmvMat*vec4(position, 0.0, 1.0);
}

#endif // BRICABRAC_HOSTED
#endif // BRICABRAC_VERTEX_SHADER
//
//::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
//
#ifdef BRICABRAC_FRAGMENT_SHADER

BRICABRAC_UNIFORM(sampler2D, texture)
BRICABRAC_UNIFORM(sampler2D, light  )
BRICABRAC_UNIFORM(lowp vec4, color  )

#ifndef BRICABRAC_HOSTED

varying mediump vec2 v_texcoord;
varying mediump vec2 v_lightcoord;

void main() {
    mediump vec4 t = texture2D(texture, v_texcoord  );
    mediump vec4 l = texture2D(light  , v_lightcoord);

    gl_FragColor = t * l;
}

#endif // BRICABRAC_HOSTED
#endif // BRICABRAC_FRAGMENT_SHADER
