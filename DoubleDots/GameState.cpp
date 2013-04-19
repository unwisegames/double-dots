//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#include "GameState.h"

#include "vec2.h"

#include <unordered_map>
#include <sstream>

#include <mach/mach_time.h>

using namespace brac;

GameState::GameState(size_t n, bool iPad) : board_(n), indices_({0, 1, 2, 3, 4}) {
    std::fill(begin(board_.colors), end(board_.colors), brac::BitBoard::empty());
    int h = iPad ? 16 : 7, w = iPad ? 16 : 8;
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x)
            if (x < 16 && y < 16)
                //board_.colors[rand() % board_.nColors()].set(x, y);
                board_.colors[arc4random_uniform(board_.nColors())].set(x, y);
    //    board_.colors[0] = { 1     + 16};
    //    board_.colors[1] = { 2     + 32};
    //    board_.colors[2] = {(2<< 8)+(32<< 8)};
    //    board_.colors[3] = {(4<< 8)+(64<< 8)};
    //    board_.colors[4] = {(4<<16)+(64<<16)};
    updatePossibles();
}

void GameState::match() {
    std::vector<brac::BitBoard> bbs; bbs.reserve(sels_.size());
    std::transform(begin(sels_), end(sels_), back_inserter(bbs), [](Selections::value_type const & s) { return s.second.is_selected; });
    auto finish = std::remove(begin(bbs), end(bbs), brac::BitBoard::empty());
    if (finish - begin(bbs) > 1 && bbs[0].count() > 2 && board_.selectionsMatch(begin(bbs), finish)) {
        for (auto& s : sels_) {
            board_ &= ~s.second.is_selected;
        }
        for (auto const & sel : sels_) indices_.insert(sel.first);
        sels_.clear();
        boardChanged_();
        selectionChanged_();
        updatePossibles();
    }
}

void GameState::touchesBegan(std::vector<Touch> const & touches) {
    for (auto const & t : touches) {
        auto is_touched = brac::BitBoard::single(t.p);

        auto sel = std::find_if(begin(sels_), end(sels_), [&](Selections::value_type const & s) { return is_touched & s.second.is_selected; });
        if (sel == end(sels_) && !indices_.empty()) {
            auto i = std::min_element(begin(indices_), end(indices_));
            sel = sels_.emplace(*i, Selection{}).first;
            indices_.erase(i);
            selectionChanged_();
        }
        if (sel != end(sels_)) {
            sel->second.key = t.key;
            sel->second.was_touched = is_touched;
            sel->second.added.clear();
        }
    }
}

void GameState::touchesMoved(std::vector<Touch> const & touches) {
    for (auto const & t : touches) {
        auto i = findSelection(t);
        if (i != end(sels_)) {
            auto & sel = i->second;
            sel.has_moved = true;
            auto is_touched = brac::BitBoard::single(t.p);

            auto adjoins_touch = is_touched.shiftN(1) | is_touched.shiftS(1) | is_touched.shiftE(1) | is_touched.shiftW(1);
            auto is_occupied = board_.computeMask();

            auto container = std::find_if(begin(sels_), end(sels_), [&](Selections::value_type const & s) { return !!(s.second.is_selected & is_touched); });
            if (container == end(sels_) && !sel.has_deleted && (is_touched & is_occupied) && (!sel.is_selected || (sel.is_selected & adjoins_touch))) {
                sel.is_selected |= is_touched;

                sel.added.push_back(t.p);

                if (sel.is_selected.count() > 1)
                    cancelTapGesture_();
                selectionChanged_();
            } else if ((sel.added.empty() || (sel.added.size() >= 2 && t.p == sel.added.end()[-2])) &&
                       is_touched != sel.was_touched &&
                       (is_touched & is_occupied & sel.is_selected) &&
                       (sel.was_touched & is_occupied & sel.is_selected))
            {
                // Moved from one touched cell to another within the current selection. Erase?
                brac::BitBoard erased = sel.is_selected & ~sel.was_touched;
                if (floodFill(is_touched, erased) == erased)
                    sel.is_selected = erased;

                cancelTapGesture_();

                if (!sel.added.empty())
                    sel.added.pop_back();
                selectionChanged_();
            } else if (container != end(sels_) && container != i && sel.is_selected.count() <= 1) {
                auto & csel = container->second;

                // Moved from an unextended selection into another selection. Erase?
                brac::BitBoard erased = csel.is_selected & ~is_touched;
                if (floodFill(erased.clearAllButLowestSetBit(), erased) == erased)
                    csel.is_selected = erased;

                sel.is_selected = is_touched;
                sel.has_deleted = true;

                cancelTapGesture_();

                if (!csel.is_selected) {
                    indices_.insert(container->first);
                    sels_.erase(container);
                }

                selectionChanged_();
            }
            sel.was_touched = is_touched;
        }
    }
}

void GameState::touchesEnded(std::vector<Touch> const & touches) {
    for (auto const & t : touches) {
        auto sel = findSelection(t);
        if (sel != end(sels_)) {
            if (sel->second.is_selected.count() < 3) {
                indices_.insert(sel->first);
                sels_.erase(sel);
                selectionChanged_();
            } else {
                sel->second.key = nullptr;
                cancelTapGesture_();
            }
        }
    }
}

void GameState::touchesCancelled(std::vector<Touch> const & touches) {
    for (auto const & t : touches) {
        auto sel = findSelection(t);
        if (sel != end(sels_)) {
            sel->second.key = nullptr;
            cancelTapGesture_();
            selectionChanged_();
        }
    }
}

void GameState::tapped(vec2 p) {
    auto is_touched = brac::BitBoard::single(p.x, p.y);
    for (auto i = begin(sels_); i != end(sels_); ++i) {
        if (i->second.is_selected & is_touched) {
            indices_.insert(i->first);
            i = sels_.erase(i);
            selectionChanged_();
            return;
        }
    }
    for (auto const & sel : sels_) indices_.insert(sel.first);
    sels_.clear();
    selectionChanged_();
}

void GameState::updatePossibles() {
    auto pairs = board_.findMatchingPairs();

#if 0
    static mach_timebase_info_data_t tbi;
    static std::once_flag once;
    std::call_once(once, []{
        mach_timebase_info(&tbi);
    });

    auto at = []{ return mach_absolute_time()*tbi.numer/tbi.denom/1000000; };
    auto t1 = at();
    constexpr int numtests = 1;
    for (int i = 0; i < numtests; ++i)
        auto pairs2 = findMatchingPairs(_board);
    auto t2 = at();

    if (numtests)
        (std::cerr << pairs.size() << " matches found in " << (t2 - t1)/numtests << "ms\n");

    std::vector<std::array<brac::BitBoard, 2>> biggest;
    int biggest_count = 0;

    std::map<int, int> histogram;
    for (const auto& p : pairs) {
        int count = p[0].count();
        ++histogram[count];
        if (biggest_count <= count) {
            if (biggest_count < count) {
                biggest_count = count;
                biggest.clear();
            }
            biggest.push_back(p);
        }
    }

    for (const auto& h : histogram)
        (std::cerr << h.first << ": " << h.second << "\n");

    for (const auto& p : biggest) {
        write(std::cerr, _board, {p.first, p.second}, "-RGBWK");
    }
#endif

    std::vector<Match> matches;
    for (const auto& p : pairs) {
        int score = p[0].count();

        // Add the score of every smaller match that this pair clobbers but doesn't contain.
        for (const auto& m : matches) {
            brac::BitBoard bb = m.shape1 | m.shape2;
            brac::BitBoard diff = bb & ~(p[0] | p[1]);
            if (diff && diff != bb)
                score += m.shape1.count();
        }

        matches.push_back({p[0], p[1], score});
    }

    typedef std::unordered_map<brac::BitBoard, std::vector<Match>> ShapeMap;
    ShapeMap shape_histogram;
    for (const auto& m : matches) {
        auto bb = m.shape1;
        int nm = bb.marginN(), sm = bb.marginS(), em = bb.marginE(), wm = bb.marginW();
        auto& h = shape_histogram[std::min(bb.shiftWS(wm, sm),
                                           std::min(bb.rotL().shiftWS(nm, wm),
                                                    std::min(bb.reverse().shiftWS(em, nm),
                                                             bb.rotR().shiftWS(sm, em))))];
        h.push_back(m);
    }
    shapeMatcheses_.clear(); shapeMatcheses_.reserve(shape_histogram.size());
    std::transform(begin(shape_histogram), end(shape_histogram), back_inserter(shapeMatcheses_),
                   [](ShapeMap::value_type const & sm) { return std::make_shared<ShapeMatches>(ShapeMatches{sm.first, sm.second}); });

    for (auto& sm : shapeMatcheses_) {
        // Sort matches by score.
        std::sort(begin(sm->matches), end(sm->matches), [](Match const & a, Match const & b) { return a.score > b.score; });
    }

    // Sort by lexicograpically comparing score lists, secondarily on bit-value.
    std::sort(begin(shapeMatcheses_), end(shapeMatcheses_), [](const std::shared_ptr<ShapeMatches>& a, const std::shared_ptr<ShapeMatches>& b) {
        auto comp = [](Match const & a, Match const & b) { return a.score > b.score; };

        return (std::lexicographical_compare(begin(a->matches), end(a->matches), begin(b->matches), end(a->matches), comp) ||
                (!std::lexicographical_compare(begin(b->matches), end(b->matches), begin(a->matches), end(a->matches), comp) &&
                 a->shape > b->shape));
    });
    
    if (shapeMatcheses_.empty() && gameOver_)
        gameOver_();
}
