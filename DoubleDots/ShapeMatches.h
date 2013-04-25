//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

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
    uint8_t hinted;
};

#endif /* defined(__DoubleDots__ShapeMatches__) */
