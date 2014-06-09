//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import "GameRenderer.h"

#import <GLKit/GLKit.h>

#include <memory>

@interface RenderController : GLKViewController<GLKViewDelegate>

@property (assign, nonatomic) std::shared_ptr<GameRenderer> renderer;
@property (assign, nonatomic) std::function<void()> sceneChanged;

@end
