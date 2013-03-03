//
//  Shader.fsh
//  DoubleDots
//
//  Created by Marcelo Cantos on 3/03/13.
//  Copyright (c) 2013 Marcelo Cantos. All rights reserved.
//

varying lowp vec4 colorVarying;

void main()
{
    gl_FragColor = colorVarying;
}
