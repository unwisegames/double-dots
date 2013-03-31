//
//  GameState.h
//  DoubleDots
//
//  Created by Marcelo Cantos on 31/03/13.
//  Copyright (c) 2013 Marcelo Cantos. All rights reserved.
//

#ifndef DoubleDots_GameState_h
#define DoubleDots_GameState_h

#import "BitBoard.h"
#import "Board.h"

#include "vec2.h"

#include <vector>
#include <functional>

class Selection {
public:
    UITouch *touch = nil;
    brac::BitBoard is_selected = 0;
};

struct Match {
    brac::BitBoard first, second;
    int score;
};

struct Shape {
    std::vector<Match> matches;
    NSString *count, *text, *scores;
    int height;

    Shape(const std::vector<Match>& matches, NSString *count, NSString *text, NSString *scores, int height)
    : matches(matches), count(count), text(text), scores(scores), height(height) { }

    const Match& nextMatch() const {
        return matches[nextToHighlight_ = (nextToHighlight_ + 1)%matches.size()];
    }

private:
    mutable int nextToHighlight_;
};

struct GameState {
    enum { numBallColors = 5, minimumSelection = 3, maxTouches = 5 };

    GameState(bool iPad);

    void match();

    const habeo::Board<numBallColors>       & board () { return board_ ; }
    const std::vector<Shape>                & shapes() { return shapes_; }
    const std::array<Selection, maxTouches> & sels  () { return sels_  ; }

    brac::BitBoard isSelected() const {
        return std::accumulate(begin(sels_), end(sels_), brac::BitBoard{0},
                               [](brac::BitBoard acc, const Selection& sel) { return acc | sel.is_selected; });
    }

    template <typename F> void setTouchPosition(F f) { touchPosition_ = f; }
    template <typename F> void setSelectionChanged(F f) { selectionChanged_ = f; }

    void touchesBegan(NSSet *touches);
    void touchesMoved(NSSet *touches);
    void touchesEnded(NSSet *touches);
    void tapped(squz::vec2 p);

private:
    habeo::Board<numBallColors> board_;
    std::vector<Shape> shapes_;
    std::array<Selection, maxTouches> sels_;
    std::function<std::shared_ptr<squz::vec2>(UITouch *touch)> touchPosition_;
    std::function<void()> selectionChanged_;

    void handleTouch(brac::BitBoard is_touched, Selection& sel);
    void updatePossibles();
};

#endif
