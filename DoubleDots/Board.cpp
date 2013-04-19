//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#include "Board.h"

#include <unordered_map>
#include <cassert>

using namespace brac;

std::unordered_set<std::array<BitBoard, 2>> Board::findMatchingPairs() const {
    std::unordered_set<std::array<BitBoard, 2>> result, discarded;
    auto mask = computeMask();
    int analyses = 0, tests = 0, matches = 0, overlaps = 0;

    std::function<bool(const std::array<BitBoard, 2>& bbs, int level)> analysePair;

    // Build an array of colors in each orientation.
    Board rots_[3] = { rotL(), rotR(), reverse() };
    Board const * rots[4] = { this, &rots_[0], &rots_[1], &rots_[2] };
    char cc[4][16][16];
    for (size_t r = 0; r < 4; ++r)
        for (size_t y = 0; y < 16; ++y)
            for (size_t x = 0; x < 16; ++x)
                cc[r][y][x] = rots[r]->color(x, y);

    // Return true iff a match was found directly or recursively (even if it was already in the result or discarded).
    analysePair = [&](const std::array<BitBoard, 2>& bbs, int level) -> bool {
        ++analyses;
        if (!(bbs[0] & bbs[1]) && bbs[0] < bbs[1]) {
            if (discarded.count(bbs) || result.count(bbs)) {
                ++overlaps;
                return true;
            } else {
                ++tests;
                if (selectionsMatch(begin(bbs), end(bbs))) {
                    ++matches;

                    //fprintf(stderr, "Analyse[%3d] %016llx:%016llx:%016llx:%016llx <-> %016llx:%016llx:%016llx:%016llx\n",
                    //        level, bbs[0].a, bbs[0].b, bbs[0].c, bbs[0].d, bbs[1].a, bbs[1].b, bbs[1].c, bbs[1].d);

                    auto neighborhood = [&](BitBoard const & bb) { return (bb.shiftN(1) | bb.shiftS(1) | bb.shiftE(1) | bb.shiftW(1)) & ~bb & mask; };

                    auto hood2init = neighborhood(bbs[1]);

                    bool foundBigger = false;
                    for (auto hood1 = neighborhood(bbs[0]); hood1;) {
                        auto lo1 = hood1.clearAllButLowestSetBit();
                        BitBoard test1 = bbs[0] | lo1;
                        hood1 &= ~lo1;

                        for (auto hood2 = hood2init; hood2;) {
                            auto lo2 = hood2.clearAllButLowestSetBit();
                            auto test2 = bbs[1] | lo2;
                            hood2 &= ~lo2;

                            foundBigger |= analysePair({test1, test2}, level + 1);
                        }
                    }
                    if (!foundBigger) {
                        result.insert(bbs);
                    } else {
                        discarded.insert(bbs);
                    }
                    return true;
                }
            }
        }
        return false;
    };

    typedef std::unordered_multimap<size_t, BitBoard> TripleMap;

    auto enumerateTriples = [&](TripleMap const & m) {
        for (auto i = begin(m); i != end(m);) {
            auto j = m.equal_range(i->first).second;
            for (auto bb0 = i; bb0 != j; ++bb0)
                for (auto bb1 = i; bb1 != j; ++bb1) {
                    analysePair({bb0->second, bb1->second}, 3);
                    if (bb0 != bb1)
                        analysePair({bb1->second, bb0->second}, 3);
                }
            i = j;
        }
    };

    auto bitboardForPattern = [](uint64_t pat, size_t r, size_t x, size_t y) {
        auto result = BitBoard{pat, 0, 0, 0}.shiftEN(x, y);
        switch (r) {
            case 1 : result = result.rotR   (); break;
            case 2 : result = result.rotL   (); break;
            case 3 : result = result.reverse(); break;
            default:                            break;
        }
        return result;
    };

    // Straight triples
    TripleMap s_triples(2 * 4 * 16 * 16);
    for (size_t r = 0; r < 4; ++r)
        for (size_t y = 0; y < 16; ++y)
            for (size_t x = 0; x < 14; ++x) {
                char *c = cc[r][y] + x;
                char c0 = c[0], c1 = c[1], c2 = c[2];

                if (c0 >= 0 && c1 >= 0 && c2 >= 0 &&    // no holes and ...
                    (c0 < c2 ||                         //   first of asymetric pair, or...
                     (c0 == c2 && r < 2)))              //   symmetric and not in rotR() or reverse()
                {
                    s_triples.emplace(c0 + 5 * c1 + 25 * c2, bitboardForPattern(7, r, x, y));
                }
            }
    enumerateTriples(s_triples);

    // L-triples
    TripleMap l_triples(2 * 4 * 16 * 16);
    for (size_t r = 0; r < 4; ++r)
        for (size_t y = 0; y < 15; ++y)
            for (size_t x = 0; x < 14; ++x) {
                char (*c)[16] = cc[r];
                char c0 = c[y + 1][x], c1 = c[y][x], c2 = c[y][x + 1];
                if (c0 >= 0 && c1 >= 0 && c2 >= 0)
                    l_triples.emplace(c0 + 5 * c1 + 25 * c2, bitboardForPattern(3 + (1 << 16), r, x, y));
            }
    enumerateTriples(l_triples);

#if 1
    std::cerr << analyses << " analyses; " << tests << " tests; " << matches << " matches; " << overlaps << " overlaps; " << result.size() << " returned; " << discarded.size() << " discarded\n";
#endif
    
    return result;
}

std::ostream& write(std::ostream& os, Board const & b, std::initializer_list<BitBoard> bbs, const char* colors, bool trimNorth) {
    int mn = 16;
    for (auto const & bb : bbs)
        mn = std::min(mn, bb.marginN());

    for (int y = 16 - trimNorth*mn; y--;) {
        for (const auto& bb : bbs) {
            if (&bb != &*begin(bbs))
                os << " |";
            for (int x = 0; x < 16; ++x) {
                auto c = b.color(x, y);
                (os << " " << (c < 0 ? ' ' : (bb.isSet(x, y)) ? colors[1 + c] : colors[0]));
            }
        }
        (os << "\n");
    }
    return os;
}
