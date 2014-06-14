//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#include "Board.h"

#include <unordered_map>
#include <cassert>

using namespace brac;

bool Board::selectionsMatch(Board const (&prerotated)[4], BitBoard const & a, BitBoard const & b)
{
    size_t nColors = prerotated[0].nColors();

    assert(std::all_of(std::begin(prerotated) + 1, std::end(prerotated),
                       [&](Board const & b) { return b.nColors() == nColors; }));

    int sm1 = a.marginS(), wm1 = a.marginW();

    BitBoard * cc = new (alloca(nColors * sizeof(BitBoard))) BitBoard[nColors];
    uint32_t cc_set = 0;

    auto lazyColorA = [&](size_t i) -> BitBoard const & {
        uint32_t m = 1 << i;
        if (!(cc_set & m)) {
            cc[i] = (prerotated[0].colors[i] & a).shiftWS(wm1, sm1);
            cc_set |= m;
        }
        return cc[i];
    };

    int nm = b.marginN(), sm = b.marginS(), em = b.marginE(), wm = b.marginW();

    for (size_t i = 0; i < nColors; ++i)
        if (lazyColorA(i) != (prerotated[0].colors[i] & b).shiftWS(wm, sm))
            goto b1;
    return true;

b1:
    auto b1 = b.rotL();
    for (size_t i = 0; i < nColors; ++i)
        if (lazyColorA(i) != (prerotated[1].colors[i] & b1).shiftWS(nm, wm))
            goto b2;
    return true;

b2:
    auto b2 = b.reverse();
    for (size_t i = 0; i < nColors; ++i)
        if (lazyColorA(i) != (prerotated[2].colors[i] & b2).shiftWS(em, nm))
            goto b3;
    return true;

b3:
    auto b3 = b.rotR();
    for (size_t i = 0; i < nColors; ++i)
        if (lazyColorA(i) != (prerotated[3].colors[i] & b3).shiftWS(sm, em))
            goto b4;
    return true;

b4:
    return false;
}

std::unordered_set<std::array<BitBoard, 2>> Board::findMatchingPairs() const {
    std::unordered_set<std::array<BitBoard, 2>> result, discarded;
    std::vector<std::array<BitBoard, 2>> result_masks; result_masks.reserve(1 << 16);
    auto mask = computeMask();
    int analyses = 0, tests = 0, matches = 0, overlaps = 0;

    // Build an array of colors in each orientation.
    Board const rots[4] = { *this, rotL(), reverse(), rotR() };
    int rotcolors[4][16][16];
    for (int8_t r = 0; r < 4; ++r)
        for (size_t y = 0; y < 16; ++y)
            for (size_t x = 0; x < 16; ++x)
                rotcolors[r][y][x] = rots[r].color(x, y);

    // Return true iff a match was found directly or recursively (even if it was already in the result or discarded).
    std::function<bool(const std::array<BitBoard, 2>& bbs, BitBoard::ShiftRotate sr, int level)> analysePair;
    analysePair = [&](const std::array<BitBoard, 2>& bbs, BitBoard::ShiftRotate sr, int level) -> bool {
        ++analyses;
        if (!(bbs[0] & bbs[1]) && bbs[0] < bbs[1]) {
            if (discarded.count(bbs) || result.count(bbs)) {
                ++overlaps;
                return true;
            } else {
                ++tests;
                if (selectionsMatch(rots, bbs[0], bbs[1])) {
                    ++matches;

                    //fprintf(stderr, "Analyse[%3d] %016llx:%016llx:%016llx:%016llx <-> %016llx:%016llx:%016llx:%016llx\n",
                    //        level, bbs[0].a, bbs[0].b, bbs[0].c, bbs[0].d, bbs[1].a, bbs[1].b, bbs[1].c, bbs[1].d);

                    auto neighborhood = [&](BitBoard const & bb) { return bb.nhood4() & ~bb & mask; };

                    bool foundBigger = false;
                    for (auto hood1 = neighborhood(bbs[0]); hood1;) {
                        auto lo1 = hood1.ls1b();
                        BitBoard test1 = bbs[0] | lo1;
                        hood1 &= ~lo1;

                        if (auto lo2 = sr * lo1) {
                            BitBoard test2 = bbs[1] | lo2;
                            foundBigger |= analysePair({test1, test2}, sr, level + 1);
                        }
                    }
                    if (!foundBigger) {
                        result.insert(bbs);
                        result_masks.push_back({~bbs[0], ~bbs[1]});
                    } else {
                        discarded.insert(bbs);
                    }
                    return true;
                }
            }
        }
        return false;
    };

    typedef std::vector<BitBoard::WithOrientation> TripleSet;
    typedef std::unordered_map<size_t, TripleSet> TripleMap;

    auto enumerateTriples = [&](TripleMap const & m) {
        for (auto const & i : m)
            for (auto bb0 = std::begin(i.second); bb0 != end(i.second); ++bb0)
                for (auto bb1 = bb0; ++bb1 != end(i.second);)
                    analysePair({bb0->bb, bb1->bb}, bb1->sr * bb0->sr.inverse(), 3);
    };

    // Straight triples
    TripleMap s_triples(2 * 4 * 16 * 16);
    BitBoard s3{7, 0, 0, 0};
    for (int8_t r = 0; r < 4; ++r)
        for (int8_t y = 0; y < 16; ++y)
            for (int8_t x = 0; x < 14; ++x) {
                int *c = rotcolors[r][y] + x;
                char c0 = c[0], c1 = c[1], c2 = c[2];

                if (~c0 && ~c1 && ~c2 &&    // no missing dots and ...
                    c0 <= c2)               //   not greater of asymmetric pair
                {
                    s_triples[c0 + 5 * c1 + 25 * c2].push_back(BitBoard::ShiftRotate{{x, y}, static_cast<int8_t>(-r)}(s3));
                }
            }
    enumerateTriples(s_triples);

    // L-triples
    TripleMap l_triples(2 * 4 * 16 * 16);
    BitBoard l3{3 + (1 << 16), 0, 0, 0};
    for (int8_t r = 0; r < 4; ++r)
        for (int8_t y = 0; y < 15; ++y)
            for (int8_t x = 0; x < 14; ++x) {
                int (&c)[16][16] = rotcolors[r];
                char c0 = c[y + 1][x], c1 = c[y][x], c2 = c[y][x + 1];
                if (~c0 && ~c1 && ~c2)
                    l_triples[c0 + 5 * c1 + 25 * c2].push_back(BitBoard::ShiftRotate{{x, y}, static_cast<int8_t>(-r)}(l3));
            }
    enumerateTriples(l_triples);

    auto smaller = [](TripleMap::value_type const & a, TripleMap::value_type const & b) { return a.second.size() < b.second.size(); };
    auto const & largest = std::max(*std::max_element(begin(s_triples), end(s_triples), smaller),
                                    *std::max_element(begin(l_triples), end(l_triples), smaller),
                                    smaller);
    std::cerr << "Largest triple set " << "RGBPY"[largest.first % 5] << "RGBPY"[(largest.first / 5) % 5] << "RGBPY"[largest.first / 25] << " has " << largest.second.size() << " elements\n";
#if 0
    std::cerr << analyses << " analyses; " << tests << " tests; " << matches << " matches; " << overlaps << " overlaps; " << result.size() << " returned; " << discarded.size() << " discarded\n";
#endif
    
    return result;
}

std::vector<BitBoard> Board::findOtherMatches(std::vector<BitBoard> const & matches) const {
    std::vector<BitBoard> result;

    auto shape = matches[0].canonical();
    auto pattern = (shape.sr * *this) & shape.bb;

    auto mask = computeMask();
    for (auto const & bb : matches)
        mask &= ~bb;

    size_t w = shape.bb.marginE(), h = shape.bb.marginN();
    for (size_t r = 0; r < 4; ++r)
        for (size_t y = 0; y < h; ++y)
            for (size_t x = 0; x < w; ++x) {
                BitBoard::ShiftRotate sr{{static_cast<signed char>(x), static_cast<signed char>(y)}, static_cast<int8_t>(r)};
                auto candidate = sr * shape.bb;
                if ((mask & candidate) == candidate && sr.inverse() * (*this & candidate) == pattern)
                    result.push_back(candidate);
            }

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
                (os << (c < 0 ? ' ' : (bb.isSet(x, y)) ? colors[1 + c] : colors[0]));
            }
        }
        (os << "\n");
    }
    return os;
}
