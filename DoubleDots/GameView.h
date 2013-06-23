//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#ifndef INCLUDED__GameView_h
#define INCLUDED__GameView_h

#include "GameState.h"

class GameView {
public:
    GameView(std::shared_ptr<GameState> const & game) : game_(game) { }

    std::shared_ptr<GameState>       & game()       { return game_; }
    std::shared_ptr<GameState> const & game() const { return game_; }

private:
    std::shared_ptr<GameState> game_;
};

#endif // INCLUDED__GameView_h
