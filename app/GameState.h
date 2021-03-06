//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#ifndef INCLUDED__GameState_h
#define INCLUDED__GameState_h

#import <bricabrac/Math/BitBoard.h>
#import "Board.h"
#import "ShapeMatches.h"
#import "Signal.h"

#include <bricabrac/Math/vec2.h>

#include <boost/signals2.hpp>

#include <vector>
#include <unordered_map>
#include <unordered_set>

class GameState {
public:
    class Selection {
    public:
        void const * key;
        brac::BitBoard is_selected{0, 0, 0, 0};
        bool has_moved = false;
        brac::BitBoard was_touched{0, 0, 0, 0};
        std::vector<brac::vec2> added;
        bool has_deleted = false;

        bool has_border() const { return has_moved && !has_deleted; }
    };

    struct Touch {
        void const * key;
        brac::vec2 p;
        bool hasMoved;
    };
    
    typedef std::vector<std::shared_ptr<ShapeMatches>>  ShapeMatcheses;
    typedef std::unordered_map<size_t, Selection>       Selections;
    
    enum { minimumSelection = 3 };

    boost::signals2::signal<void()> onSelectionChanged;
    boost::signals2::signal<void()> onBoardChanged;

    GameState(size_t nColors, size_t width, size_t height, size_t * seed = nullptr);

    bool match(bool & incomplete);

    size_t                  seed  () const { return seed_     ; }
    size_t                  width () const { return width_    ; }
    size_t                  height() const { return height_   ; }
    Board           const & board () const { return board_    ; }
    Selections      const & sels  () const { return sels_     ; }

    void touchesBegan    (std::vector<Touch> const & touches);
    void touchesMoved    (std::vector<Touch> const & touches);
    void touchesEnded    (std::vector<Touch> const & touches);
    void touchesCancelled(std::vector<Touch> const & touches);
    void tapped(brac::vec2 p);

    static brac::BitBoard::WithOrientation canonicalise(brac::BitBoard const & bb);

    static ShapeMatcheses possibleMoves(Board const & board);

private:
    size_t                      seed_;
    size_t                      width_, height_;
    Board                       board_;
    Selections                  sels_;
    std::unordered_set<size_t>  indices_;

    void handleTouch(brac::BitBoard is_touched, Selection& sel);

    Selections::iterator findSelection(Touch const & touch) {
        return std::find_if(begin(sels_), end(sels_), [&](Selections::value_type const & s){ return s.second.key == touch.key; });
    }
};

#endif // INCLUDED__GameState_h
