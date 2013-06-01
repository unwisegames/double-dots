//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import "ViewController.h"
#import "ShapeCell.h"
#import "Board.h"
#import "GameState.h"
#import "LruCache.h"
#import "UIAlertView+Blocks.h"
#import "SettingsController.h"
#import "IncompleteController.h"

#import <Crashlytics/Crashlytics.h>

#import <QuartzCore/QuartzCore.h>

static bool iPad = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;

static constexpr size_t gGrid = 16;
static constexpr size_t gBorder = 12;
static constexpr float gGearHz = 0.2;


typedef brac::LruCache<std::tuple<brac::BitBoard, uint8_t, size_t>, UIImage *> ShapeImageCache;

@interface ViewController () {
    int _level;
    std::shared_ptr<GameState> _game;
    std::shared_ptr<GameState::ShapeMatcheses> _matcheses;

    std::shared_ptr<ShapeImageCache> _shapeImages;
    std::array<std::array<UIImage *, 5>, 2> _dots;

    uint64_t _nUpdates;
}

@property (nonatomic, strong) IBOutlet RenderController * renderer;

- (void)restartGame:(size_t *)seed;

@end

@implementation ViewController

@synthesize tableView = _tableView, seed = _seed, gear = _gear, renderer = _renderer;

- (void)calculatePossibles {
    auto iUpdate = ++_nUpdates;
    auto board = _game->board();

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        auto matcheses = std::make_shared<GameState::ShapeMatcheses>(GameState::possibleMoves(board));

        dispatch_async(dispatch_get_main_queue(), ^{
            if (iUpdate == _nUpdates) {
                if (matcheses->empty()) {
                    [self restartGame:nullptr];
                } else {
                    _matcheses = matcheses;
                    [self.tableView reloadData];
                }
            }
        });
    });
}

- (UIImage *)makeImageShape:(brac::BitBoard)bb hint:(uint8_t)hint colorSet:(size_t)colorSet outline:(bool)outline {
    auto const & board = _game->board();

    auto canonicalised = GameState::canonicalise(bb);

    bb = canonicalised.bb;

    size_t w = 16 - bb.marginE(), h = 16 - bb.marginN();
    size_t W = 2 * gBorder + gGrid * w, H = 2 * gBorder + gGrid * h;

    float scale = outline ? 1 : 8;

    W *= scale;
    H *= scale;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(W, H), NO, 0);
    auto ctx = UIGraphicsGetCurrentContext();

#if 0
    [[UIColor colorWithHue:0.7 saturation:0.5 brightness:0.3 alpha:1] setFill];
    CGContextFillRect(ctx, CGRectMake(0, 0, W, H));
#endif

    if (outline) {
        float lineWidth = 1.5;
        // Shape
        [[[UIColor blackColor] colorWithAlphaComponent:0.15] setFill  ];
        for (size_t y = 0; y < h; ++y)
            for (size_t x = 0; x < w; ++x)
                if (bb.isSet(x, y)) {
                    auto cell = CGRectMake(gBorder + gGrid * x, H - (gBorder + gGrid * (y + 1)), gGrid, gGrid);
                    CGContextFillRect(ctx, cell);
                }
        [[UIColor blackColor] setStroke];
        CGContextSetLineCap(ctx, kCGLineCapRound);
        CGContextSetLineWidth(ctx, lineWidth);
        for (int y = 0; y <= h; ++y)
            for (int x = 0; x <= w; ++x) {
                auto p = CGPointMake(gBorder + gGrid * x, H - (gBorder + gGrid * y));
                uint32_t bits = bb.shiftWS(x - 1, y - 1).a;
                bool west   = bits & (1 << 16);
                bool center = bits & (2 << 16);
                bool south  = bits & 2;
                if (south ^ center) CGContextStrokeLineSegments(ctx, begin(std::initializer_list<CGPoint>{p, {p.x + gGrid, p.y        }}), 2);
                if (west  ^ center) CGContextStrokeLineSegments(ctx, begin(std::initializer_list<CGPoint>{p, {p.x        , p.y - gGrid}}), 2);
            }
        [[[UIColor blackColor] colorWithAlphaComponent:0.6] setStroke];
        CGContextSetLineWidth(ctx, 0.5 * lineWidth);
        for (int y = 0; y <= h; ++y)
            for (int x = 0; x <= w; ++x) {
                auto p = CGPointMake(gBorder + gGrid * x, H - (gBorder + gGrid * y));
                uint32_t bits = bb.shiftWS(x - 1, y - 1).a;
                bool west   = bits & (1 << 16);
                bool center = bits & (2 << 16);
                bool south  = bits & 2;
                if (south & center) CGContextStrokeLineSegments(ctx, begin(std::initializer_list<CGPoint>{
                    {p.x + 0.2f * gGrid, p.y                },
                    {p.x + 0.8f * gGrid, p.y                }
                }), 2);
                if (west  & center) CGContextStrokeLineSegments(ctx, begin(std::initializer_list<CGPoint>{
                    {p.x                , p.y - 0.2f * gGrid},
                    {p.x                , p.y - 0.8f * gGrid}
                }), 2);
            }
    }

    // Hint dots
    for (size_t c = 0; c < board.nColors(); ++c)
        if (hint & (1 << c)) {
            auto color = (canonicalised.sr * board.colors[c]) & bb;
            for (size_t y = 0; y < h; ++y)
                for (size_t x = 0; x < w; ++x)
                    if (color.isSet(x, y))
                        [_dots[colorSet][c] drawInRect:CGRectMake(scale * (gBorder + gGrid * x), H - scale * (gBorder + gGrid * (y + 1)), scale * gGrid, scale * gGrid)];
        }

    auto image = UIGraphicsGetImageFromCurrentImageContext();

    UIGraphicsEndImageContext();

    return image;
}

- (void)restartGame:(size_t *)seed {
    _renderer.renderer->setGame(_game = (_level == 1 ? std::make_shared<GameState>(4, 10, 10, seed) :
                                         /* else */    std::make_shared<GameState>(5, 16, 16, seed) ));

    // Report game seed.
    NSString * seedStr = [NSString stringWithFormat:@"%04lx:%04lx", _game->seed() >> 16, _game->seed() % (1 << 16)];
    for (auto state : std::initializer_list<UIControlState>{UIControlStateNormal, UIControlStateHighlighted})
        [_seed setTitle:seedStr forState:state];

    [Crashlytics setObjectValue:seedStr forKey:@"game-seed"];

    _matcheses->clear();

    _shapeImages = std::make_shared<ShapeImageCache>([self](std::tuple<brac::BitBoard, uint8_t, size_t> const & params) {
        return [self makeImageShape:std::get<0>(params)
                               hint:std::get<1>(params)
                           colorSet:std::get<2>(params)
                            outline:true];
    }, 1000);

    [self.tableView reloadData];
    [self calculatePossibles];

    _renderer.paused = NO;
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self becomeFirstResponder];

#ifndef DEBUG
    _seed.hidden = YES;
#endif

    _renderer = [self.storyboard instantiateViewControllerWithIdentifier:@"glkView"];

    _matcheses = std::make_shared<GameState::ShapeMatcheses>();

    {
        UIImage * atlas = [UIImage imageNamed:@"atlas.png"];
        for (size_t i = 0; i < _dots.size(); ++i)
            for (size_t c = 0; c < _dots[i].size(); ++c) {
                brac::vec2 dot = GameRenderer::dots[i][c];
                UIGraphicsBeginImageContextWithOptions(CGSizeMake(64, 64), NO, 0);
                [atlas drawInRect:CGRectMake(-256 * dot.x, -256 * dot.y, 256, 256)];
                _dots[i][c] = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
            }
    }

    [self addChildViewController:_renderer];
    [self.view addSubview:_renderer.view];
    [self.view sendSubviewToBack:_renderer.view];
    [_renderer didMoveToParentViewController:self];

    _level = [[NSUserDefaults standardUserDefaults] integerForKey:@"GameLevel"];
    if (!_level) _level = 2;
    [self restartGame:nullptr];
}

-(void)viewDidLayoutSubviews {
    _renderer.view.frame = CGRectMake(0, 0, iPad ? 1024 : std::ceil(480), iPad ? 768 : 320);
    _renderer.paused = NO;
}

- (void)viewDidAppear:(BOOL)animated {
    _renderer.paused = NO;
}

- (void)stopGear {
    [_gear.layer removeAllAnimations];

    float currentAngle = ((NSNumber *)[_gear.layer.presentationLayer valueForKeyPath:@"transform.rotation.z"]).floatValue;
    float finishAngle = std::round(1 / (0.5 * M_PI) * currentAngle) * (0.5 * M_PI);

    CABasicAnimation * rotateGear = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rotateGear.fromValue = @(currentAngle);
    rotateGear.toValue = @(finishAngle);
    rotateGear.duration = 0.5 / (2 * M_PI * gGearHz) * (finishAngle - currentAngle);
    rotateGear.repeatCount = 1;
    [_gear.layer addAnimation:rotateGear forKey:@"rotateGear"];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _matcheses->size();
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    auto const & sm = *(*_matcheses)[indexPath.row];
    auto bb = GameState::canonicalise(sm.shape).bb;

    size_t h = 16 - bb.marginN();
    size_t H = 2 * gBorder + gGrid * h;

    return H;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString * CellIdentifier = @"shape";
    ShapeCell * cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell)
        cell = [[ShapeCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];

    auto const & sm = *(*_matcheses)[indexPath.row];
    [cell setShapeMatches:sm image:(*_shapeImages)(std::make_tuple(sm.matches[0].shape1, sm.hinted, _renderer.renderer->colorSet()))];

    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    auto & sm = *(*_matcheses)[indexPath.row];
    auto & board = _game->board();
    size_t colors = 0;
    for (size_t i = 0; i < board.nColors(); ++i)
        if (board.colors[i] & sm.matches[0].shape1)
            colors |= (1 << i);
    if (sm.hinted < colors) {
        for (;;) {
            uint8_t h = 1 << (arc4random() % board.nColors());
            if ((colors & h) && !(sm.hinted & h)) {
                sm.hinted |= h;
                break;
            }
        }
        ((ShapeCell *)[tableView cellForRowAtIndexPath:indexPath]).shape.image = (*_shapeImages)(std::make_tuple(sm.matches[0].shape1, sm.hinted, _renderer.renderer->colorSet()));
    } else {
        _renderer.renderer->hint((*_matcheses)[indexPath.row]);
    }
}

#pragma mark - Actions

- (IBAction)tappedMatch {
    bool incomplete;
    if (_game->match(incomplete)) {
        [self calculatePossibles];
        _renderer.renderer->hint(nullptr);
        if (_matcheses->empty()) {
            [self restartGame:nullptr];
        } else {
            [self.tableView reloadData];
        }
    } else if (incomplete) {
        [self performSegueWithIdentifier:@"incomplete" sender:self];
    }
}

- (IBAction)tappedSeed {
    UIAlertView * av = [UIAlertView alertViewWithTitle:@"Seed"
                                               message:@"Enter a 32-bit seed in hex."
                                     cancelButtonTitle:@"Cancel"
                                   cancelButtonPressed:nil
                                          otherButtons:nil];

    av.alertViewStyle = UIAlertViewStylePlainTextInput;

    UIAlertView * __weak weakAv = av;
    [av addButtonWithTitle:@"Start" whenDidDismiss:^{
        size_t seed;
        sscanf([weakAv textFieldAtIndex:0].text.UTF8String, "%lx", &seed);
        [self restartGame:&seed];
    }];

    [av show];
}

#pragma mark - Segues

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.destinationViewController isMemberOfClass:[SettingsController class]]) {
        __weak SettingsController * settings = segue.destinationViewController;
        __weak UIPopoverController * popover = nil;

        if ([segue respondsToSelector:@selector(popoverController)]) {
            popover = [(UIStoryboardPopoverSegue *)segue popoverController];

            popover.delegate = self;

            CABasicAnimation * rotateGear = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
            rotateGear.toValue = @(2*M_PI);
            rotateGear.duration = 1 / gGearHz;
            rotateGear.cumulative = NO;
            rotateGear.repeatCount = 1e20;

            [_gear.layer addAnimation:rotateGear forKey:@"rotateGear"];
        }

        settings.colorBlind = _renderer.renderer->colorSet();
        settings.toggleColorBlind = [=]() {
            size_t colorSet = 1 - _renderer.renderer->colorSet();
            _renderer.renderer->setColorSet(colorSet);
            [self.tableView reloadData];
            settings.colorBlind = colorSet;
            _renderer.paused = NO;
        };

        settings.newGame = [=](int level) {
            _level = level;

            auto ud = [NSUserDefaults standardUserDefaults];
            [ud setInteger:_level forKey:@"GameLevel"];
            [ud synchronize];

            [self restartGame:nullptr];
            if (popover) {
                [popover dismissPopoverAnimated:YES];
            } else {
                [self dismissModalViewControllerAnimated:YES];
            }
            [self stopGear];
        };

        settings.tutorial = [=]{
            [[UIAlertView alertViewWithTitle:@"Not implemented"
                                     message:@"Tutorial mode coming soon..."
                           cancelButtonTitle:@"Close"
                         cancelButtonPressed:^{
                             [popover dismissPopoverAnimated:YES];
                             [self stopGear];
                         }
                                otherButtons:nil] show];
        };

        settings.cancelled = [=]{
            [self dismissModalViewControllerAnimated:YES];
        };
    } else if ([segue.destinationViewController isMemberOfClass:[IncompleteController class]]) {
        IncompleteController * incomplete = segue.destinationViewController;

        incomplete.shapeImage = [self makeImageShape:_game->sels().begin()->second.is_selected hint:-1 colorSet:_renderer.renderer->colorSet() outline:false];

        if ([segue respondsToSelector:@selector(popoverController)]) {
            UIPopoverController * popover = [(UIStoryboardPopoverSegue *)segue popoverController];
            popover.contentViewController.view.superview.superview.superview.alpha = 0.5;
        }
    }
}

#pragma mark - UIPopoverControllerDelegate

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController {
    if ([popoverController.contentViewController isMemberOfClass:[SettingsController class]]) {
        [self stopGear];
    } else if ([popoverController.contentViewController.restorationIdentifier isEqualToString:@"incomplete"]) {
    }
}

- (void)viewDidUnload {
    [super viewDidUnload];
}
@end
