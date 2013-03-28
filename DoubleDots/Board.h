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

        Board SQUZ_OPERATOR(&)(brac::BitBoard b) {
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

}

#endif
