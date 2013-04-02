//
//  ShapeMatches.h
//  DoubleDots
//
//  Created by Marcelo Cantos on 1/04/13.
//  Copyright (c) 2013 Marcelo Cantos. All rights reserved.
//

#ifndef __DoubleDots__ShapeMatches__
#define __DoubleDots__ShapeMatches__

#include "BitBoard.h"

#include <vector>

struct Match {
    brac::BitBoard shape1, shape2;
    int score;
};

struct ShapeMatches {
    brac::BitBoard shape;
    std::vector<Match> matches;
};

#endif /* defined(__DoubleDots__ShapeMatches__) */
