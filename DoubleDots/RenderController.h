//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import "GameState.h"

#import <GLKit/GLKit.h>

#include <memory>

@interface RenderController : GLKViewController

@property (nonatomic, assign) std::shared_ptr<GameState> game;

- (void)hint:(const std::shared_ptr<ShapeMatches>&)sm;

@end
