//
//  GameState.cpp
//  DoubleDots
//
//  Created by Marcelo Cantos on 31/03/13.
//  Copyright (c) 2013 Marcelo Cantos. All rights reserved.
//

#include "GameState.h"

#include "vec2.h"

#include <unordered_map>
#include <sstream>

#include <mach/mach_time.h>

using namespace brac;

GameState::GameState(bool iPad) {
    std::fill(begin(board_.colors), end(board_.colors), brac::BitBoard::empty());
    int h = iPad ? 16 : 7, w = iPad ? 16 : 8;
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x)
            board_.colors[rand()%numBallColors].set(x, y);
        //board_.colors[arc4random_uniform(numBallColors)].bits |= 1ULL << i;
//    board_.colors[0] = { 1     + 16};
//    board_.colors[1] = { 2     + 32};
//    board_.colors[2] = {(2<< 8)+(32<< 8)};
//    board_.colors[3] = {(4<< 8)+(64<< 8)};
//    board_.colors[4] = {(4<<16)+(64<<16)};
    updatePossibles();
}

void GameState::match() {
    std::array<brac::BitBoard, numBallColors> bbs;
    std::transform(begin(sels_), end(sels_), begin(bbs), [](const Selection& s) { return s.is_selected; });
    auto finish = std::remove(begin(bbs), end(bbs), brac::BitBoard::empty());
    if (finish - begin(bbs) > 1 && bbs[0].count() > 2 && selectionsMatch(board_, begin(bbs), finish)) {
        for (auto& s : sels_) {
            board_ &= ~s.is_selected;
            s = Selection{};
            selectionChanged_();
        }
        updatePossibles();
    }
}

void GameState::touchesBegan(NSSet *touches) {
    for (UITouch *touch in touches)
        if (auto p = touchPosition_(touch)) {
            auto is_touched = brac::BitBoard::single(p->x, p->y);

            auto sel = std::find_if(begin(sels_), end(sels_), [&](const Selection& s){ return is_touched & s.is_selected; });
            if (sel == end(sels_))
                sel = std::find_if(begin(sels_), end(sels_), [](const Selection& s){ return !s.touch && !s.is_selected; });
            if (sel != end(sels_)) {
                sel->touch = touch;
                sel->was_selected_prior_to_touch = sel->is_selected;
                //handleTouch(is_touched, *sel);
            }
        }
}

void GameState::touchesMoved(NSSet *touches) {
    for (UITouch *touch in touches)
        if (auto p = touchPosition_(touch)) {
            auto sel = std::find_if(begin(sels_), end(sels_), [&](const Selection& s){ return s.touch == touch; });
            if (sel != end(sels_)) {
                sel->moved = true;
                auto is_touched = brac::BitBoard::single(p->x, p->y);
                handleTouch(is_touched, *sel);
            }
        }
}

void GameState::touchesEnded(NSSet *touches) {
    for (UITouch *touch in touches) {
        auto sel = std::find_if(begin(sels_), end(sels_), [&](const Selection& s){ return s.touch == touch; });
        if (sel != end(sels_)) {
            if (sel->is_selected.count() < 2) {
                *sel = Selection{};
                selectionChanged_();
            } else {
                sel->touch = nil;
            }
            sel->suppressTap = false;
        }
    }
}

void GameState::touchesCancelled(NSSet *touches) {
    for (UITouch *touch in touches) {
        auto sel = std::find_if(begin(sels_), end(sels_), [&](const Selection& s){ return s.touch == touch; });
        if (sel != end(sels_)) {
            sel->is_selected = sel->was_selected_prior_to_touch;
            sel->touch = nil;
            selectionChanged_();
        }
    }
}

void GameState::tapped(vec2 p) {
    auto is_touched = brac::BitBoard::single(p.x, p.y);
    for (auto& sel : sels_)
        if ((sel.is_selected & is_touched)) {
            if (sel.is_selected.count() > 1) {
                if (!sel.suppressTap) {
                    sel = Selection{};
                    selectionChanged_();
                }
                return;
            }
            break;
        }
    for (auto& s : sels_)
        s = Selection{};
    selectionChanged_();
}

void GameState::handleTouch(brac::BitBoard is_touched, Selection& sel) {
    auto adjoins_touch = is_touched.shiftN(1) | is_touched.shiftS(1) | is_touched.shiftE(1) | is_touched.shiftW(1);
    auto is_occupied = board_.mask();

    if ((is_touched & is_occupied & ~isSelected()) && (!sel.is_selected || (sel.is_selected & adjoins_touch))) {
        sel.is_selected |= is_touched;
        if (sel.is_selected.count() > 1)
            sel.suppressTap = true;
        selectionChanged_();
    }
}

void GameState::updatePossibles() {
    auto pairs = findMatchingPairs(board_);

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
                   [](const std::pair<brac::BitBoard, std::vector<Match>>& sm) { return std::make_shared<ShapeMatches>(ShapeMatches{sm.first, sm.second}); });
    NSLog(@"%ld shapes", shapeMatcheses_.size());

    // Sort scores.
    for (auto& sm : shapeMatcheses_)
        std::sort(begin(sm->matches), end(sm->matches), [](const Match& a, const Match& b) { return a.score > b.score; });

    // Sort by lexicograpically comparing score lists, secondarily on bit-value.
    std::sort(begin(shapeMatcheses_), end(shapeMatcheses_), [](const std::shared_ptr<ShapeMatches>& a, const std::shared_ptr<ShapeMatches>& b) {
        auto comp = [](const Match& a, const Match& b) { return a.score > b.score; };

        return (std::lexicographical_compare(begin(a->matches), end(a->matches), begin(b->matches), end(a->matches), comp) ||
                (!std::lexicographical_compare(begin(b->matches), end(b->matches), begin(a->matches), end(a->matches), comp) &&
                 a->shape > b->shape));
    });

    if (shapeMatcheses_.empty() && gameOver_)
        gameOver_();
}
