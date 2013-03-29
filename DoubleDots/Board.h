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
#include <unordered_set>
#include <iostream>

namespace std {

    template <>
    struct hash<std::tuple<brac::BitBoard, brac::BitBoard>> {
        size_t operator()(const std::tuple<brac::BitBoard, brac::BitBoard>& bb) const {
            return hash<brac::BitBoard>()(std::get<0>(bb))*1129803267 + hash<brac::BitBoard>()(std::get<1>(bb));
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
            return map([=](const brac::BitBoard& b) { return b.shiftSW(s, w); });
        }
    };

    template <size_t N>
    bool match(const Board<N>& b, const brac::BitBoard& bb1, const brac::BitBoard& bb2, bool report = false) {
        int sm1 = bb1.marginS(), wm1 = bb1.marginW();
        int nm = bb2.marginN(), sm = bb2.marginS(), em = bb2.marginE(), wm = bb2.marginW();

        if (report) {
            for (int i = 0; i < N; ++i) {
                auto c1 = (b.colors[i] & bb1).shiftSW(sm1, wm1);
                auto c2 = b.colors[i] & bb2;
                write(std::cerr << "identity " << (c1 == c2.shiftSW(sm, wm)) << "\n", b, {c1, c2, c2, c2.shiftSW(sm, wm)}, "-RGBWK");
            }
            for (int i = 0; i < N; ++i) {
                auto c1 = (b.colors[i] & bb1).shiftSW(sm1, wm1);
                auto c2 = b.colors[i] & bb2;
                write(std::cerr << "rotL " << (c1 == c2.rotL().shiftSW(wm, nm)) << "\n", b, {c1, c2, c2.rotL(), c2.rotL().shiftSW(wm, nm)}, "-RGBWK");
            }
            for (int i = 0; i < N; ++i) {
                auto c1 = (b.colors[i] & bb1).shiftSW(sm1, wm1);
                auto c2 = b.colors[i] & bb2;
                write(std::cerr << "reverse " << (c1 == c2.reverse().shiftSW(nm, em)) << "\n", b, {c1, c2, c2.reverse(), c2.reverse().shiftSW(nm, em)}, "-RGBWK");
            }
            for (int i = 0; i < N; ++i) {
                auto c1 = (b.colors[i] & bb1).shiftSW(sm1, wm1);
                auto c2 = b.colors[i] & bb2;
                write(std::cerr << "rotR " << (c1 == c2.rotR().shiftSW(em, sm)) << "\n", b, {c1, c2, c2.rotR(), c2.rotR().shiftSW(em, sm)}, "-RGBWK");
            }
            std::cerr << "nm = " << nm << "; sm = " << sm << "; em = " << em << "; wm = " << wm << "\n";
        }

        brac::BitBoard c1[N], c2[N];
        for (int i = 0; i < N; ++i) {
            c1[i] = (b.colors[i] & bb1).shiftSW(sm1, wm1);
            c2[i] =  b.colors[i] & bb2;
        }

        for (int i = 0; i < N; ++i)
            if (c1[i] != c2[i].shiftSW(sm, wm))
                goto rotl;
        return true;
    rotl:
        for (int i = 0; i < N; ++i)
            if (c1[i] != c2[i].rotL().shiftSW(wm, nm))
                goto reverse;
        return true;
    reverse:
        for (int i = 0; i < N; ++i)
            if (c1[i] != c2[i].reverse().shiftSW(nm, em))
                goto rotr;
        return true;
    rotr:
        for (int i = 0; i < N; ++i)
            if (c1[i] != c2[i].rotR().shiftSW(em, sm))
                goto gulp;
        return true;
    gulp:
        return false;
    }

    template <size_t N>
    std::unordered_set<std::tuple<brac::BitBoard, brac::BitBoard>> findMatches(const Board<N>& b) {
        std::unordered_set<std::tuple<brac::BitBoard, brac::BitBoard>> matches;
        auto mask = b.mask();
        int analyses = 0, tests = 0, passes = 0, overlaps = 0;

        std::function<void(brac::BitBoard bb1, brac::BitBoard bb2, int level)> analysePair;

        analysePair = [&](brac::BitBoard bb1, brac::BitBoard bb2, int level) {
            ++analyses;
            if (!(bb1 & bb2) && (bb1.bits < bb2.bits)) {
                if (!matches.count(std::make_tuple(bb1, bb2))) {
                    ++tests;
                    if (match(b, bb1, bb2)) {
                        ++passes;
                        matches.emplace(bb1, bb2);

                        //std::cerr << "Analyse[" << level << "] " << bb1.bits << " <-> " << bb2.bits << "\n";
                        //std::cerr << level;

                        auto neighborhood = [&](brac::BitBoard bb) { return (bb.shiftN(1) | bb.shiftS(1) | bb.shiftE(1) | bb.shiftW(1)) & ~bb & mask; };

                        auto hood2init = neighborhood(bb2);

                        for (auto hood1 = neighborhood(bb1); hood1;) {
                            brac::BitBoard newHood1 = {hood1.bits & (hood1.bits - 1)};
                            brac::BitBoard test1 = bb1 | (hood1 ^ newHood1);
                            hood1 = newHood1;

                            for (auto hood2 = hood2init; hood2;) {
                                brac::BitBoard newHood2 = {hood2.bits & (hood2.bits - 1)};
                                brac::BitBoard test2 = bb2 | (hood2 ^ newHood2);
                                hood2 = newHood2;

                                analysePair(test1, test2, level + 1);
                            }
                        }
                    }
                } else {
                    ++overlaps;
                }
            }
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
                            analysePair(bbs, bbt, 3);
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

#if 0
        std::cerr << analyses << " analyses; " << tests << " tests; " << passes << " passes; " << overlaps << " overlaps\n";
#endif

        return matches;
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
