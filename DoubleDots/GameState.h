//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#ifndef DoubleDots_GameState_h
#define DoubleDots_GameState_h

#import "BitBoard.h"
#import "Board.h"
#import "ShapeMatches.h"

#include "vec2.h"

#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <functional>

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
    };
    
    typedef std::vector<std::shared_ptr<ShapeMatches>>  ShapeMatcheses;
    typedef std::unordered_map<size_t, Selection>       Selections;
    
    enum { minimumSelection = 3 };

    GameState(size_t n, bool iPad);

    void match();

    size_t                  seed  () { return seed_     ; }
    Board           const & board () { return board_    ; }
    Selections      const & sels  () { return sels_     ; }

    template <typename F> void onSelectionChanged   (F f) { selectionChanged_   = f; }
    template <typename F> void onBoardChanged       (F f) { boardChanged_       = f; f(); }
    template <typename F> void onCancelTapGesture   (F f) { cancelTapGesture_   = f; }

    void touchesBegan    (std::vector<Touch> const & touches);
    void touchesMoved    (std::vector<Touch> const & touches);
    void touchesEnded    (std::vector<Touch> const & touches);
    void touchesCancelled(std::vector<Touch> const & touches);
    void tapped(brac::vec2 p);

    static std::function<brac::BitBoard(brac::BitBoard const &)> canonicaliser(brac::BitBoard const & bb);

    static ShapeMatcheses possibleMoves(Board const & board);
    void filterMatcheses(ShapeMatcheses & matcheses);

private:
    size_t                      seed_;
    Board                       board_;
    Selections                  sels_;
    std::unordered_set<size_t>  indices_;

    std::function<void()> selectionChanged_;
    std::function<void()> boardChanged_;
    std::function<void()> cancelTapGesture_;

    void handleTouch(brac::BitBoard is_touched, Selection& sel);

    Selections::iterator findSelection(Touch const & touch) {
        return std::find_if(begin(sels_), end(sels_), [&](Selections::value_type const & s){ return s.second.key == touch.key; });
    }
};

#endif
