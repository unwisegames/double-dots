#ifndef INCLUDED__ShapeMatches_h
#define INCLUDED__ShapeMatches_h

#include <bricabrac/Math/BitBoard.h>

#include <vector>

struct Match {
    brac::BitBoard shape1, shape2;
    int score;

    Match(brac::BitBoard const & a, brac::BitBoard const & b, int score) : shape1(a), shape2(b), score(score) { }
};

struct ShapeMatches {
    brac::BitBoard shape;
    std::vector<Match> matches;
    uint8_t hinted;
};

#endif // INCLUDED__ShapeMatches_h
