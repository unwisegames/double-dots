//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import "GameState.h"
#import "vec2.h"

#import <GLKit/GLKit.h>

#include <memory>

namespace DotTexCoords {
    static brac::vec2 blue   {0.25, 0.25};
    static brac::vec2 red    {0.5 , 0.25};
    static brac::vec2 purple {0.75, 0.25};
    static brac::vec2 green  {0.5 , 0.5 };
    static brac::vec2 dkblue {0.75, 0.5 };
    static brac::vec2 white  {0.5 , 0.75};
    static brac::vec2 yellow {0.75, 0.75};

    static brac::vec2 dots[2][5] = {
        {red, green,   blue, purple, yellow},
        {red, green, dkblue, purple, white },
    };
}

@interface RenderController : GLKViewController

@property (nonatomic, assign) std::shared_ptr<GameState>    game;
@property (nonatomic, assign) size_t                        colorSet;

- (void)hint:(const std::shared_ptr<ShapeMatches>&)sm;

- (void)updateBoardColors;

@end
