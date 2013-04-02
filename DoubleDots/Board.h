//
//  Board.h
//  DoubleDots
//
//  Created by Marcelo Cantos on 28/03/13.
//  Copyright (c) 2013 Marcelo Cantos. All rights reserved.
//

#ifndef DoubleDots_Board_h
#define DoubleDots_Board_h

#import "BitBoard.h"

#include <utility>
#include <algorithm>
#include <numeric>
#include <vector>
#include <array>
#include <unordered_set>
#include <iostream>

namespace std {

    template <>
    struct hash<std::array<brac::BitBoard, 2>> {
        size_t operator()(const std::array<brac::BitBoard, 2>& bb) const {
            return hash<brac::BitBoard>()(bb[0])*1129803267 + hash<brac::BitBoard>()(bb[1]);
        }
    };

}

namespace habeo {

    template <size_t N>
    struct Board {
        std::array<brac::BitBoard, N> colors;

        bool SQUZ_OPERATOR(<)(const Board& b) const {
            for (int i = 0; i < N; ++i)
                if (colors[i].bits != b.colors[i].bits)
                    return (colors[i].bits < b.colors[i].bits); // Parens needed due to brain-damaged Xcode formatter.
            return false;
        }

        template <typename F>
        Board map(F f) const {
            Board b;
            std::transform(begin(colors), end(colors), begin(b.colors), f);
            return b;
        }

        template <typename T, typename F>
        T reduce(const T& t, F f) const {
            return std::accumulate(begin(colors), end(colors), t, f);
        }

        bool SQUZ_OPERATOR(==)(const Board& b) const {
            return std::equal(begin(colors), end(colors), begin(b.colors));
        }

        brac::BitBoard mask() const {
            return reduce(brac::BitBoard{0}, [](brac::BitBoard b, brac::BitBoard c) { return b | c; });
        }

        Board SQUZ_OPERATOR(&)(brac::BitBoard b) const {
            return map([=](brac::BitBoard color){ return color & b; });
        }
        Board& SQUZ_OPERATOR(&=)(brac::BitBoard b) { return *this = *this & b; }

        void clear(int x, int y) {
            for (auto& c : colors)
                c.clear(x, y);
        }

        int color(int x, int y) const {
            for (const auto& c : colors)
                if (c.is_set(x, y))
                    return &c - &*begin(colors);
            return -1;
        }

        Board rotL   () const { return map([=](const brac::BitBoard& b) { return b.rotL   (); }); }
        Board rotR   () const { return map([=](const brac::BitBoard& b) { return b.rotR   (); }); }
        Board reverse() const { return map([=](const brac::BitBoard& b) { return b.reverse(); }); }

        Board shiftSW(int s, int w) const {
            return map([=](const brac::BitBoard& b) { return b.shiftWS(w, s); });
        }
    };

    template <size_t N, typename I>
    bool selectionsMatch(const Board<N>& b, I startBBs, I finishBBs, bool report = false) {
        if (std::distance(startBBs, finishBBs) < 2)
            return true;

        const auto& bb1 = *startBBs;
        int sm1 = bb1.marginS(), wm1 = bb1.marginW();

        typedef std::array<brac::BitBoard, 2> Colors;
        Colors colors[N];
        for (int i = 0; i < N; ++i)
            colors[i][0] = (b.colors[i] & bb1).shiftWS(wm1, sm1);

        for (auto i = startBBs + 1; i != finishBBs; ++i) {
            const auto& bb2 = *i;
            int nm = bb2.marginN(), sm = bb2.marginS(), em = bb2.marginE(), wm = bb2.marginW();

            if (report) {
                for (int i = 0; i < N; ++i) {
                    auto c1 = (b.colors[i] & bb1).shiftWS(wm1, sm1);
                    auto c2 = b.colors[i] & bb2;
                    write(std::cerr << "identity " << (c1 == c2.shiftWS(wm, sm)) << "\n", b, {c1, c2, c2, c2.shiftWS(wm, sm)}, "-RGBWK");
                }
                for (int i = 0; i < N; ++i) {
                    auto c1 = (b.colors[i] & bb1).shiftWS(wm1, sm1);
                    auto c2 = b.colors[i] & bb2;
                    write(std::cerr << "rotL " << (c1 == c2.rotL().shiftWS(nm, wm)) << "\n", b, {c1, c2, c2.rotL(), c2.rotL().shiftWS(nm, wm)}, "-RGBWK");
                }
                for (int i = 0; i < N; ++i) {
                    auto c1 = (b.colors[i] & bb1).shiftWS(wm1, sm1);
                    auto c2 = b.colors[i] & bb2;
                    write(std::cerr << "reverse " << (c1 == c2.reverse().shiftWS(em, nm)) << "\n", b, {c1, c2, c2.reverse(), c2.reverse().shiftWS(em, nm)}, "-RGBWK");
                }
                for (int i = 0; i < N; ++i) {
                    auto c1 = (b.colors[i] & bb1).shiftWS(wm1, sm1);
                    auto c2 = b.colors[i] & bb2;
                    write(std::cerr << "rotR " << (c1 == c2.rotR().shiftWS(sm, em)) << "\n", b, {c1, c2, c2.rotR(), c2.rotR().shiftWS(sm, em)}, "-RGBWK");
                }
                std::cerr << "nm = " << nm << "; sm = " << sm << "; em = " << em << "; wm = " << wm << "\n";
            }

            for (int i = 0; i < N; ++i)
                colors[i][1] =  b.colors[i] & bb2;

            if (std::any_of(begin(colors), end(colors), [&](Colors c) { return c[0] != c[1]          .shiftWS(wm, sm); }) &&
                std::any_of(begin(colors), end(colors), [&](Colors c) { return c[0] != c[1].rotL()   .shiftWS(nm, wm); }) &&
                std::any_of(begin(colors), end(colors), [&](Colors c) { return c[0] != c[1].reverse().shiftWS(em, nm); }) &&
                std::any_of(begin(colors), end(colors), [&](Colors c) { return c[0] != c[1].rotR()   .shiftWS(sm, em); }))
            {
                return false;
            }
        }
        return true;
    }

    template <size_t N>
    std::unordered_set<std::array<brac::BitBoard, 2>> findMatchingPairs(const Board<N>& b) {
        std::unordered_set<std::array<brac::BitBoard, 2>> result, discarded;
        auto mask = b.mask();
        int analyses = 0, tests = 0, matches = 0, overlaps = 0;

        std::function<bool(const std::array<brac::BitBoard, 2>& bbs, int level)> analysePair;

        // Return true iff a match was found directly or recursively (even if it was already in the result or discarded).
        analysePair = [&](const std::array<brac::BitBoard, 2>& bbs, int level) -> bool {
            ++analyses;
            if (!(bbs[0] & bbs[1]) && (bbs[0].bits < bbs[1].bits)) {
                if (discarded.count(bbs) || result.count(bbs)) {
                    ++overlaps;
                    return true;
                } else {
                    ++tests;
                    if (selectionsMatch(b, begin(bbs), end(bbs))) {
                        ++matches;

                        //std::cerr << "Analyse[" << level << "] " << bbs[0].bits << " <-> " << bbs[1].bits << "\n";
                        //std::cerr << level;

                        auto neighborhood = [&](brac::BitBoard bb) { return (bb.shiftN(1) | bb.shiftS(1) | bb.shiftE(1) | bb.shiftW(1)) & ~bb & mask; };

                        auto hood2init = neighborhood(bbs[1]);

                        bool foundBigger = false;
                        for (auto hood1 = neighborhood(bbs[0]); hood1;) {
                            brac::BitBoard test1 = {bbs[0].bits | (hood1.bits & -hood1.bits)};
                            hood1 = {hood1.bits & (hood1.bits - 1)};

                            for (auto hood2 = hood2init; hood2;) {
                                brac::BitBoard test2 = {bbs[1].bits | (hood2.bits & -hood2.bits)};
                                hood2 = {hood2.bits & (hood2.bits - 1)};

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

        auto enumeratePairs = [&](brac::BitBoard bb1, brac::BitBoard bb2) {
            assert(!bb1.marginW());
            assert(!bb1.marginS());
            assert(!bb2.marginW());
            assert(!bb2.marginS());
            auto bbs1 = brac::BitBoardShifts(8 - bb1.marginE(), 8 - bb1.marginN());
            auto bbs2 = brac::BitBoardShifts(8 - bb2.marginE(), 8 - bb2.marginN());
            for (auto s = std::begin(bbs1); s != std::end(bbs1); ++s) {
                brac::BitBoard bbs = bb1 << *s;
                if ((bbs & mask) == bbs)
                    for (auto t = std::begin(bbs2); t != std::end(bbs2); ++t) {
                        brac::BitBoard bbt = bb2 << *t;
                        if ((bbt & mask) == bbt)
                            analysePair({bbs, bbt}, 3);
                    }
            }
        };

        auto ep = [&](std::initializer_list<brac::BitBoard> bb) {
            for (auto bb1 : bb)
                for (auto bb2 : bb) {
                    enumeratePairs(bb1, bb2);
                    if (bb1 != bb2)
                        enumeratePairs(bb2, bb1);
                }
        };

        uint64_t A = 1<<8, B = 2<<8, C = 1<<16;
        ep({{1+2+4}, {1+A+C}});
        ep({{A+1+2}, {1+2+B}, {2+B+A}, {B+A+1}});

#if 1
        std::cerr << analyses << " analyses; " << tests << " tests; " << matches << " matches; " << overlaps << " overlaps; " << result.size() << " returned; " << discarded.size() << " discarded\n";
#endif

        return result;
    }

    template <size_t N>
    std::ostream& write(std::ostream& os, const Board<N>& b, std::initializer_list<brac::BitBoard> bbs, const char* colors, bool trimNorth = false) {
        int mn = 8;
        for (const auto& bb : bbs)
            mn = std::min(mn, bb.marginN());

        for (int y = 8 - trimNorth*mn; y--;) {
            for (const auto& bb : bbs) {
                if (&bb != &*begin(bbs))
                    os << " |";
                for (int x = 0; x < 8; ++x) {
                    auto c = b.color(x, y);
                    (os << " " << (c < 0 ? ' ' : bb.is_set(x, y) ? colors[1 + c] : colors[0]));
                }
            }
            (os << "\n");
        }
        return os;
    }
    
}

#endif
