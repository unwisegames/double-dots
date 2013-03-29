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

        Board rotL   () const { return map([=](const brac::BitBoard& b) { return b.rotL   (); }); }
        Board rotR   () const { return map([=](const brac::BitBoard& b) { return b.rotR   (); }); }
        Board reverse() const { return map([=](const brac::BitBoard& b) { return b.reverse(); }); }

        Board swCorner() const {
            brac::BitBoard all = mask();
            int s = all.marginS();
            int w = all.marginW();
            return map([=](const brac::BitBoard& b) { return b.shiftS(s).shiftW(w); });
        }

        Board canonical() const {
            return std::min(std::min(std::min(swCorner(), rotL().swCorner()), rotR().swCorner()), reverse().swCorner());
        }

        bool matches(const Board& b) const {
            return canonical() == b.canonical();
        }
    };

    template <size_t N>
    std::unordered_set<std::tuple<brac::BitBoard, brac::BitBoard>> findMatches(const Board<N>& b) {
        std::unordered_set<std::tuple<brac::BitBoard, brac::BitBoard>> matches;
        auto mask = b.mask();

        std::function<void(brac::BitBoard bb1, brac::BitBoard bb2, int level)> analysePair;

        analysePair = [&](brac::BitBoard bb1, brac::BitBoard bb2, int level) {
            if (!(bb1 & bb2) && (bb1.bits < bb2.bits) && !matches.count(std::make_tuple(bb1, bb2)) && (b & bb1).matches(b & bb2)) {
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

        return matches;
    }

}

#endif
