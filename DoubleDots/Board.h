//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#ifndef INCLUDED__DoubleDots__Board_h
#define INCLUDED__DoubleDots__Board_h

#import "common.h"
#import "BitBoard.h"
#import "bert.hpp"

#include <utility>
#include <algorithm>
#include <numeric>
#include <vector>
#include <unordered_set>
#include <iostream>
#include <initializer_list>
#include <cassert>

namespace std {

    template <>
    struct hash<std::array<brac::BitBoard, 2>> {
        size_t operator()(const std::array<brac::BitBoard, 2>& bb) const {
            return hash<brac::BitBoard>()(bb[0])*1129803267 + hash<brac::BitBoard>()(bb[1]);
        }
    };

}

struct Board {
    std::vector<brac::BitBoard> colors;

    Board(size_t n) : colors(n) { }

    size_t nColors() const { return colors.size(); }

    explicit operator bool() const { return std::all_of(begin(colors), end(colors), [](brac::BitBoard const & color) { return (bool)color; }); }
    bool operator!() const { return !!*this; }

    bool BRAC_OPERATOR(<)(Board const & b) const {
        return std::lexicographical_compare(begin(colors), end(colors), begin(b.colors), end(b.colors));
    }

    template <typename F>
    Board map(F f) const {
        Board b(nColors());
        std::transform(begin(colors), end(colors), begin(b.colors), f);
        return b;
    }

    template <typename T, typename F>
    T reduce(T const & t, F f) const {
        return std::accumulate(begin(colors), end(colors), t, f);
    }

    template <typename F> void foreach(F f)       { for (auto       & color : colors) f(color); }
    template <typename F> void foreach(F f) const { for (auto const & color : colors) f(color); }

    bool BRAC_OPERATOR(==)(Board const & b) const {
        return std::equal(begin(colors), end(colors), begin(b.colors));
    }

    bool BRAC_OPERATOR(!=)(Board const & b) { return !(*this == b); }

    brac::BitBoard computeMask() const {
        return reduce(brac::BitBoard::empty(), [](brac::BitBoard const & b, brac::BitBoard const & c) { return b | c; });
    }

    Board BRAC_OPERATOR(&)(brac::BitBoard const & b) const { return map([&](brac::BitBoard const & color){ return color & b; }); }
    Board BRAC_OPERATOR(|)(brac::BitBoard const & b) const { return map([&](brac::BitBoard const & color){ return color | b; }); }
    Board BRAC_OPERATOR(^)(brac::BitBoard const & b) const { return map([&](brac::BitBoard const & color){ return color ^ b; }); }

    Board BRAC_OPERATOR(~)() const { return map([&](brac::BitBoard const & color){ return ~color; }); }

    Board& BRAC_OPERATOR(&=)(brac::BitBoard const & b) { return *this = *this & b; }
    Board& BRAC_OPERATOR(|=)(brac::BitBoard const & b) { return *this = *this ^ b; }
    Board& BRAC_OPERATOR(^=)(brac::BitBoard const & b) { return *this = *this | b; }

    void clear(int x, int y) {
        for (auto& c : colors)
            c.clear(x, y);
    }

    int color(int x, int y) const {
        for (const auto& c : colors)
            if (c.isSet(x, y))
                return &c - &*begin(colors);
        return -1;
    }

    Board rotL   () const { return map([=](brac::BitBoard const & b) { return b.rotL   (); }); }
    Board rotR   () const { return map([=](brac::BitBoard const & b) { return b.rotR   (); }); }
    Board reverse() const { return map([=](brac::BitBoard const & b) { return b.reverse(); }); }

    Board shiftWS(int w, int s) const {
        return map([=](brac::BitBoard const & b) { return b.shiftWS(w, s); });
    }

    Board shiftEN(int e, int n) const {
        return map([=](brac::BitBoard const & b) { return b.shiftEN(e, n); });
    }

    template <typename I>
    bool selectionsMatch(I startBBs, I finishBBs, bool report = false) const;

    template <typename I>
    static bool selectionsMatch(std::initializer_list<Board const &> rots, I startBBs, I finishBBs, bool report = false);

    std::unordered_set<std::array<brac::BitBoard, 2>> findMatchingPairs() const;
};

template <typename I>
bool Board::selectionsMatch(I startBBs, I finishBBs, bool report) const {
    if (std::distance(startBBs, finishBBs) < 2)
        return true;

    const auto& bb1 = *startBBs;
    int sm1 = bb1.marginS(), wm1 = bb1.marginW();

    Board first = (*this & bb1).shiftWS(wm1, sm1);
    std::vector<size_t> ii(nColors());
    std::iota(begin(ii), end(ii), 0);
    return std::all_of(++startBBs, finishBBs, [&](brac::BitBoard const & bb) {
        int nm = bb.marginN(), sm = bb.marginS(), em = bb.marginE(), wm = bb.marginW();
        std::vector<brac::BitBoard> cc(nColors());
        return (std::all_of(begin(ii), end(ii), [&](size_t i) { return first.colors[i] == (cc[i] = (colors[i] & bb))          .shiftWS(wm, sm); }) ||
                std::all_of(begin(ii), end(ii), [&](size_t i) { return first.colors[i] == (cc[i]                   ).rotL   ().shiftWS(nm, wm); }) ||
                std::all_of(begin(ii), end(ii), [&](size_t i) { return first.colors[i] == (cc[i]                   ).reverse().shiftWS(em, nm); }) ||
                std::all_of(begin(ii), end(ii), [&](size_t i) { return first.colors[i] == (cc[i]                   ).rotR   ().shiftWS(sm, em); }) );
    });
}

std::ostream& write(std::ostream& os, Board const & b, std::initializer_list<brac::BitBoard> bbs, const char* colors, bool trimNorth = false);

#endif // INCLUDED__DoubleDots__Board_h
