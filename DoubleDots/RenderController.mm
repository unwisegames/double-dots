//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import "RenderController.h"
#import "ChipmunkDebugDrawDoubleDots.h"
#import "GameState.h"

#include "vec2.h"

#import <objc/runtime.h>

using namespace brac;

static bool iPad = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;

static char const g_TouchMovedKey = '\0';

@interface RenderController () {
    EAGLContext *_context;
    bool _updating;
    bool _needsRefresh;
}
@property (nonatomic, strong) IBOutlet UITapGestureRecognizer * tapGestureRecognizer;
@end

@implementation RenderController

@synthesize renderer = _renderer, tapGestureRecognizer = _tapGestureRecognizer;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self becomeFirstResponder];

    _renderer = std::make_shared<GameRenderer>(nullptr, 0);

    _renderer->onColorSetChanged([=](size_t colorSet) {
        auto ud = [NSUserDefaults standardUserDefaults];
        [ud setInteger:colorSet forKey:@"ColorBlind"];
        [ud synchronize];
        self.paused = NO;
    });

    _renderer->toRefreshScene([=]{
        if (_updating) {
            _needsRefresh = true;
        } else {
            self.paused = NO;
        }
    });

    _renderer->toCancelTapGesture([=]{
        _tapGestureRecognizer.enabled = NO;
        _tapGestureRecognizer.enabled = YES;
    });

    _renderer->setColorSet([[NSUserDefaults standardUserDefaults] integerForKey:@"ColorBlind"]);

    _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    if (!_context) {
        NSLog(@"Failed to create ES context");
    }

    GLKView *view = (GLKView *)self.view;
    view.context = _context;
    view.drawableMultisample = GLKViewDrawableMultisample4X;
    self.preferredFramesPerSecond = 60;

    Color bg;
    [self.view.backgroundColor getRed:&bg.r green:&bg.g blue:&bg.b alpha:&bg.a];
    _renderer->setBackgroundColor(bg);

    [EAGLContext setCurrentContext:_context];
    _renderer->setupGL();
}

#pragma mark - GLKView and GLKViewController delegate methods

- (void)update {
    if (_renderer) {
        _updating = true;
        CGSize size = self.view.bounds.size;
        _renderer->setViewAspectRatio(fabsf(size.width / size.height));
        _renderer->update(self.timeSinceLastUpdate);
        _updating = false;
    }
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    if (_renderer) _renderer->render();
    if (!_needsRefresh) {
        //self.paused = YES;
    } else {
        _needsRefresh = false;
    }
}

- (std::unique_ptr<vec2>)touchPosition:(CGPoint)loc {
    auto size = self.view.bounds.size;

    vec2 p = _renderer->pick({2 * loc.x/size.width - 1, 1 - 2 * loc.y/size.height});
    p = {std::floor(p.x), std::floor(p.y)};
    return std::unique_ptr<vec2>{_renderer->isOnBoard(p) ? new vec2{p} : nullptr};
}

- (std::vector<GameState::Touch>)touchPositions:(NSSet *)touches {
    std::vector<GameState::Touch> result; result.reserve(touches.count);
    for (UITouch * touch in touches)
        if (auto p = [self touchPosition:[touch locationInView:self.view]])
            result.push_back(GameState::Touch{(__bridge void const *)touch, *p, !!objc_getAssociatedObject(touch, &g_TouchMovedKey)});
    return result;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    _renderer->game()->touchesBegan([self touchPositions:touches]);
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    for (UITouch * touch in touches)
        objc_setAssociatedObject(touch, &g_TouchMovedKey, @"", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    _renderer->game()->touchesMoved([self touchPositions:touches]);
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    _renderer->game()->touchesEnded([self touchPositions:touches]);
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    _renderer->game()->touchesCancelled([self touchPositions:touches]);
}

#pragma mark - Actions

- (IBAction)tapGestured:(UITapGestureRecognizer *)sender {
    if (auto pos = [self touchPosition:[sender locationInView:self.view]])
        _renderer->game()->tapped(*pos);
}

- (IBAction)panGestured:(UIPanGestureRecognizer *)sender {
    //auto p = [sender locationInView:self.view] * (_viewHeight / self.view.bounds.size.height);
    //p.y = -p.y;

    switch (sender.state) {
        case UIGestureRecognizerStateBegan:
            break;
        case UIGestureRecognizerStateChanged:
        {
            break;
        }
        case UIGestureRecognizerStateEnded:
        {
            break;
        }
        default:
            break;
    }
}

- (IBAction)pinchGestured:(UIPinchGestureRecognizer *)sender {
    switch (sender.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
        {

            break;
        }
        case UIGestureRecognizerStateEnded:
        {

            break;
        }
        default:
            break;
    }
}

@end
