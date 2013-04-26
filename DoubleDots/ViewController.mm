//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import "ViewController.h"
#import "ShapeCell.h"
#import "Board.h"
#import "GameState.h"
#import "LruCache.h"

#import <QuartzCore/QuartzCore.h>

static bool iPad = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;

static constexpr size_t gGrid = 16, gBorder = gGrid / 2;


typedef brac::LruCache<std::tuple<brac::BitBoard, uint8_t, size_t>, UIImage *> ShapeImageCache;

@interface ViewController () {
    std::shared_ptr<GameState> _game;
    std::shared_ptr<GameState::ShapeMatcheses> _matcheses;

    std::shared_ptr<ShapeImageCache> _shapeImages;
    std::array<std::array<UIImage *, 5>, 2> _dots;

    uint64_t _nUpdates;
}

@property (nonatomic, strong) IBOutlet UITableView      * tableView;
@property (nonatomic, strong) IBOutlet UILabel          * seed;
@property (nonatomic, strong) IBOutlet RenderController * renderer;

- (void)resetGame;

@end

@implementation ViewController

@synthesize tableView = _tableView, seed = _seed, renderer = _renderer;

- (void)calculatePossibles {
    auto iUpdate = ++_nUpdates;
    auto board = _game->board();

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        auto matcheses = std::make_shared<GameState::ShapeMatcheses>(GameState::possibleMoves(board));

        dispatch_async(dispatch_get_main_queue(), ^{
            if (iUpdate == _nUpdates) {
                if (matcheses->empty()) {
                    [self resetGame];
                } else {
                    _matcheses = matcheses;
                    [self.tableView reloadData];
                }
            }
        });
    });
}

- (void)resetGame {
    _renderer.game = _game = std::make_shared<GameState>(5, iPad);
    _seed.text = [NSString stringWithFormat:@"%04lx:%04lx", _game->seed() >> 16, _game->seed() % (1 << 16)];
    _matcheses->clear();

    _shapeImages = std::make_shared<ShapeImageCache>([self](std::tuple<brac::BitBoard, uint8_t, size_t> const & bbcols) {
        auto const & board = _game->board();
        auto bb         = std::get<0>(bbcols);
        auto hint       = std::get<1>(bbcols);
        auto colorSet   = std::get<2>(bbcols);

        auto canonicalise = GameState::canonicaliser(bb);

        bb = canonicalise(bb);

        size_t w = 16 - bb.marginE(), h = 16 - bb.marginN();
        size_t W = 2 * gBorder + gGrid * w, H = 2 * gBorder + gGrid * h;

        UIGraphicsBeginImageContextWithOptions(CGSizeMake(W, H), NO, 0);
        auto ctx = UIGraphicsGetCurrentContext();

#if 0
        [[UIColor colorWithHue:0.7 saturation:0.5 brightness:0.3 alpha:1] setFill];
        CGContextFillRect(ctx, CGRectMake(0, 0, W, H));
#endif

        auto uncolored = bb;

        auto drawDots = [&](brac::BitBoard const & col, std::function<void(size_t, size_t)> drawDot) {
            auto color = col & uncolored;
            uncolored &= ~color;

            for (size_t y = 0; y < h; ++y)
                for (size_t x = 0; x < w; ++x)
                    if (color.isSet(x, y)) {
                        drawDot(x, y);
                    }
        };

        for (size_t c = 0; c <= board.nColors(); ++c) {
            if (hint & (1 << c)) {
                drawDots(canonicalise(board.colors[c]) & bb, [&](size_t x, size_t y) {
                    [_dots[colorSet][c] drawInRect:CGRectMake(gBorder + gGrid * x, H - (gBorder + gGrid * (y + 1)), gGrid, gGrid)];
                });
            }
        }

        [[[UIColor blackColor] colorWithAlphaComponent:0.3] setFill  ];
        [[UIColor blackColor] setStroke];
        CGContextSetLineWidth(ctx, 1);

        drawDots(uncolored, [&](size_t x, size_t y) {
            auto cell = CGRectMake(gBorder + gGrid * x, H - (gBorder + gGrid * (y + 1)), gGrid, gGrid);
            auto dot = CGRectInset(cell, gGrid / 8, gGrid / 8);
            CGContextFillEllipseInRect(ctx, dot);
            CGContextStrokeEllipseInRect(ctx, dot);
        });

        auto image = UIGraphicsGetImageFromCurrentImageContext();

        UIGraphicsEndImageContext();
        
        return image;
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

    _renderer = [self.storyboard instantiateViewControllerWithIdentifier:@"glkView"];

    _matcheses = std::make_shared<GameState::ShapeMatcheses>();

    {
        UIImage * atlas = [UIImage imageNamed:@"atlas.png"];
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(16, 16), NO, 0);
        for (size_t i = 0; i < _dots.size(); ++i)
            for (size_t c = 0; c < _dots[i].size(); ++c) {
                brac::vec2 dot = DotTexCoords::dots[i][c];
                [atlas drawInRect:CGRectMake(-64 * dot.x, -64 * dot.y, 64, 64)];
                _dots[i][c] = UIGraphicsGetImageFromCurrentImageContext();
            }
        UIGraphicsEndImageContext();
    }

    [self addChildViewController:_renderer];
    [self.view addSubview:_renderer.view];
    [self.view sendSubviewToBack:_renderer.view];
    [_renderer didMoveToParentViewController:self];
    [self resetGame];
}

-(void)viewDidLayoutSubviews {
    _renderer.view.frame = CGRectMake(0, 0, iPad ? 1024 : std::ceil(480), iPad ? 768 : 320);
    _renderer.paused = NO;
}

- (void)viewDidAppear:(BOOL)animated {
    _renderer.paused = NO;
}

- (void)motionBegan:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (motion == UIEventSubtypeMotionShake) {
        [self resetGame];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return std::max<size_t>(_matcheses->size(), 1);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_matcheses->empty())
        return 70;

    auto const & sm = *(*_matcheses)[indexPath.row];
    auto bb = GameState::canonicaliser(sm.shape)(sm.shape);

    size_t h = 16 - bb.marginN();
    size_t H = 2 * gBorder + gGrid * h;

    return H;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return [[UIView alloc] init];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_matcheses->empty()) {
        static NSString * CellIdentifier = @"analysis_in_progress";

        UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
        if (!cell)
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];

        return cell;
    } else {
        static NSString * CellIdentifier = @"shape";
        ShapeCell * cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
        if (!cell)
            cell = [[ShapeCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];

        auto const & sm = *(*_matcheses)[indexPath.row];
        [cell setShapeMatches:sm image:(*_shapeImages)(std::make_tuple(sm.matches[0].shape1, sm.hinted, _renderer.colorSet))];

        return cell;
    }
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
        ((ShapeCell *)[tableView cellForRowAtIndexPath:indexPath]).shape.image = (*_shapeImages)(std::make_tuple(sm.matches[0].shape1, sm.hinted, _renderer.colorSet));
    } else {
        [_renderer hint:(*_matcheses)[indexPath.row]];
    }
}

#pragma mark - Actions

- (IBAction)tappedMatch {
    _game->match();
    _game->filterMatcheses(*_matcheses);
    [_renderer hint:nullptr];
    if (_matcheses->empty()) {
        [self resetGame];
    } else {
        [self.tableView reloadData];
    }
}

- (IBAction)tappedColorBlind {
    [_renderer updateBoardColors:true];
    [self.tableView reloadData];
    _renderer.paused = NO;
}

@end
