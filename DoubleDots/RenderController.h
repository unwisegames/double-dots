//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import "GameRenderer.h"

#import <GLKit/GLKit.h>

#include <memory>

@interface RenderController : GLKViewController<GLKViewDelegate>

@property (nonatomic, assign) std::shared_ptr<GameRenderer> renderer;

@end
