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

using namespace squz;

GameState::GameState(bool iPad) {
    std::fill(begin(board_.colors), end(board_.colors), 0);
    for (int i = 0; i < (iPad ? 64 : 56); ++i)
        //_board.colors[rand()%numBallColors].bits |= 1ULL << i;
        board_.colors[arc4random_uniform(numBallColors)].bits |= 1ULL << i;
    updatePossibles();
}

void GameState::match() {
    std::array<brac::BitBoard, numBallColors> bbs;
    std::transform(begin(sels_), end(sels_), begin(bbs), [](const Selection& s) { return s.is_selected; });
    auto finish = std::remove(begin(bbs), end(bbs), brac::BitBoard{0});
    if (finish - begin(bbs) > 1 && bbs[0].count() > 2 && selectionsMatch(board_, begin(bbs), finish)) {
        for (auto& s : sels_) {
            board_ &= ~s.is_selected;
            s = Selection{};
        }
        updatePossibles();
    }
}

void GameState::touchesBegan(NSSet *touches) {
    for (UITouch *touch in touches)
        if (auto p = touchPosition_(touch)) {
            auto is_touched = brac::BitBoard{1, p->x, p->y};

            auto sel = std::find_if(begin(sels_), end(sels_), [&](const Selection& s){ return is_touched & s.is_selected; });
            if (sel == end(sels_)) {
                sel = std::find_if(begin(sels_), end(sels_), [](const Selection& s){ return !s.is_selected; });
                if (sel != end(sels_))
                    *sel = Selection{};
            }
            if (sel != end(sels_)) {
                sel->touch = touch;
                handleTouch(is_touched, *sel);
            }
        }
}

void GameState::touchesMoved(NSSet *touches) {
    for (UITouch *touch in touches)
        if (auto p = touchPosition_(touch)) {
            auto sel = std::find_if(begin(sels_), end(sels_), [&](const Selection& s){ return s.touch == touch; });
            if (sel != end(sels_)) {
                auto is_touched = brac::BitBoard{1, p->x, p->y};
                handleTouch(is_touched, *sel);
            }
        }
}

void GameState::touchesEnded(NSSet *touches) {
    for (UITouch *touch in touches) {
        auto sel = std::find_if(begin(sels_), end(sels_), [&](const Selection& s){ return s.touch == touch; });
        if (sel != end(sels_)) {
            if (sel->is_selected.count() < 3) {
                *sel = Selection{};
                selectionChanged_();
            } else {
                sel->touch = nil;
            }
        }
    }
}

void GameState::tapped(vec2 p) {
    brac::BitBoard is_touched{1, p.x, p.y};
    for (auto& sel : sels_)
        if ((sel.is_selected & is_touched) && sel.is_selected.count() > 1) {
            sel = Selection{};
            selectionChanged_();
            return;
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

    std::vector<std::pair<brac::BitBoard, brac::BitBoard>> biggest;
    int biggest_count = 0;

    std::map<int, int> histogram;
    for (const auto& p : pairs) {
        int count = p.first.count();
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
        int score = p.first.count();

        // Add the score of every smaller match that this pair clobbers but doesn't contain.
        for (const auto& m : matches) {
            brac::BitBoard bb = m.first | m.second;
            brac::BitBoard diff = bb & ~(p.first | p.second);
            if (diff && diff != bb)
                score += m.first.count();
        }

        matches.push_back({p.first, p.second, score});
    }

    typedef std::unordered_map<brac::BitBoard, std::vector<Match>> ShapeMap;
    typedef std::pair<brac::BitBoard, std::vector<Match>> ShapeMatches;
    ShapeMap shape_histogram;
    for (const auto& m : matches) {
        auto bb = m.first;
        int nm = bb.marginN(), sm = bb.marginS(), em = bb.marginE(), wm = bb.marginW();
        auto& h = shape_histogram[std::min(bb.shiftWS(wm, sm).bits,
                                           std::min(bb.rotL().shiftWS(nm, wm).bits,
                                                    std::min(bb.reverse().shiftWS(em, nm).bits,
                                                             bb.rotR().shiftWS(sm, em).bits)))];
        h.push_back(m);
    }
    std::vector<ShapeMatches> shapes(begin(shape_histogram), end(shape_histogram));
    std::sort(begin(shapes), end(shapes), [](const ShapeMatches& a, const ShapeMatches& b) {
        auto comp = [](const Match& a, const Match& b) { return a.score > b.score; };
        return (std::lexicographical_compare(begin(a.second), end(a.second), begin(b.second), end(a.second), comp) ||
                (!std::lexicographical_compare(begin(b.second), end(b.second), begin(a.second), end(a.second), comp) &&
                 a.first.bits > b.first.bits));
    });

    // Cull any shapes that are subsets of larger shapes.
    auto dst = begin(shapes);
    for (auto i = dst; i != end(shapes); ++i)
        if (std::find_if(begin(shapes), dst, [&](const ShapeMatches& sm) { return !(i->first & ~sm.first); }) == dst) {
            if (dst != i)
                *dst = *i;
            ++dst;
        }
    shapes.erase(dst, end(shapes));

    shapes_.clear();
    for (auto i = shapes.begin(); i != shapes.end(); ++i) {
        std::ostringstream shapeText;
        write(shapeText, habeo::Board<1>{{{0xffffffffffffffffULL}}}, {i->first}, " O", true);

        std::vector<int> scores; scores.reserve(i->second.size());
        std::ostringstream scoresText;
        for (const auto& m : i->second)
            (scoresText << (&m == &i->second[0] ? "" : "\n") << m.score);

        shapes_.emplace_back(
            i->second,
            [NSString stringWithFormat:@"%ld ×", i->second.size()],
            [NSString stringWithUTF8String:shapeText.str().c_str()],
            [NSString stringWithUTF8String:scoresText.str().c_str()],
            8 - i->first.marginN()
        );
    }
}
