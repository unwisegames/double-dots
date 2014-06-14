//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#ifndef INCLUDED__DoubleDots__BoardRenderer_h
#define INCLUDED__DoubleDots__BoardRenderer_h

#include <bricabrac/Math/Color.h>
#include <bricabrac/Math/vec2.h>

#include <boost/signals2/signal.hpp>

#include <memory>

class GameView;
struct ShapeMatches;

class GameRenderer {
public:
    boost::signals2::signal<void(size_t)> onColorSetChanged;
    boost::signals2::signal<void()> toRefreshScene;

    static std::array<std::array<brac::vec2, 5>, 2> dots;

    GameRenderer(std::shared_ptr<GameView> const & game, size_t colorSet);

    void setGameView(std::shared_ptr<GameView> const & game);
    void setColorSet(size_t colorSet);
    void setBackgroundColor(brac::Color const & c);
    void setViewAspectRatio(float aspect);

    std::shared_ptr<GameView> const & gameView() const;
    size_t colorSet() const;

    void hint(std::shared_ptr<ShapeMatches> const & sm);

    brac::vec2 pick(brac::vec2 const & v) const;
    bool isOnBoard(brac::vec2 const & v) const;

    void setupGL();
    void update(float dt);
    void render();

private:
    struct Members;
    std::shared_ptr<Members> m;
};

#endif // INCLUDED__DoubleDots__BoardRenderer_h
