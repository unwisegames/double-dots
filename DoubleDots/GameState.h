//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#ifndef DoubleDots_GameState_h
#define DoubleDots_GameState_h

#import "BitBoard.h"
#import "Board.h"
#import "ShapeMatches.h"

#include "vec2.h"

#include <vector>
#include <functional>

class Selection {
public:
    UITouch *touch = nil;
    brac::BitBoard is_selected{0, 0, 0, 0};
    brac::BitBoard was_selected_prior_to_touch{0, 0, 0, 0};
    bool moved = false;
    bool suppressTap = false;
};

struct GameState {
    enum { numBallColors = 5, minimumSelection = 3, maxTouches = 5 };

    GameState(bool iPad);

    void match();

    const habeo::Board<numBallColors>               & board () { return board_         ; }
    const std::vector<std::shared_ptr<ShapeMatches>>& shapes() { return shapeMatcheses_; }
    const std::array<Selection, maxTouches>         & sels  () { return sels_          ; }

    brac::BitBoard isSelected() const {
        return std::accumulate(begin(sels_), end(sels_), brac::BitBoard{0, 0, 0, 0},
                               [](brac::BitBoard acc, const Selection& sel) { return acc | sel.is_selected; });
    }

    template <typename F> void onTouchPosition   (F f) { touchPosition_    = f; }
    template <typename F> void onSelectionChanged(F f) { selectionChanged_ = f; }
    template <typename F> void onGameOver        (F f) { gameOver_         = f; }

    void touchesBegan    (NSSet *touches);
    void touchesMoved    (NSSet *touches);
    void touchesEnded    (NSSet *touches);
    void touchesCancelled(NSSet *touches);
    void tapped(brac::vec2 p);

private:
    habeo::Board<numBallColors> board_;
    std::vector<std::shared_ptr<ShapeMatches>> shapeMatcheses_;
    std::array<Selection, maxTouches> sels_;
    std::function<std::shared_ptr<brac::vec2>(UITouch *touch)> touchPosition_;
    std::function<void()> selectionChanged_;
    std::function<void()> gameOver_;

    void handleTouch(brac::BitBoard is_touched, Selection& sel);
    void updatePossibles();
};

#endif
