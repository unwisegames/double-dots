//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import "ViewController.h"
#import "ShapeCell.h"
#import "Board.h"
#import "GameState.h"

#import <QuartzCore/QuartzCore.h>

using namespace habeo;

static bool iPad = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;

@interface ViewController () {
    std::shared_ptr<GameState> _game;
}
@end

@implementation ViewController

@synthesize tableView = _tableView, renderer = _renderer;

- (void)resetGame {
    _renderer.game = _game = std::make_shared<GameState>(iPad);
    _game->onGameOver([=]{ dispatch_async(dispatch_get_main_queue(), ^{ [self resetGame]; }); });
    [self.tableView reloadData];
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self becomeFirstResponder];

    _tableView.layer.borderColor = [UIColor grayColor].CGColor;
    _tableView.layer.borderWidth = 1;

    _renderer = [self.storyboard instantiateViewControllerWithIdentifier:@"glkView"];

    [self addChildViewController:_renderer];
    [self.view addSubview:_renderer.view];
    [_renderer didMoveToParentViewController:self];
    [self resetGame];
}

-(void)viewDidLayoutSubviews {
    _renderer.view.frame = CGRectMake(0, 0, iPad ? 768 : std::ceil(320*8/7.0), iPad ? 768 : 320);
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
    return _game->shapes().size();
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    const auto& sm = _game->shapes()[indexPath.row];

    size_t boardHeight = 8 - sm->shape.marginN();
    return std::max(iPad ? 15*boardHeight        + 17 : 14*boardHeight        + 18,
                    iPad ? 21*sm->matches.size() +  5 : 21*sm->matches.size() +  4);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 33;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 33)];
    headerView.backgroundColor = [UIColor clearColor];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 33)];
    label.text = @"Can you find…?";
    label.textColor = [UIColor whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.7];
    label.layer.borderColor = [UIColor redColor].CGColor;
    [headerView addSubview:label];

    CALayer *line = [CALayer layer];
    line.frame = CGRectMake(0, 33, tableView.bounds.size.width, 1);
    line.backgroundColor = [UIColor grayColor].CGColor;
    [headerView.layer addSublayer:line];

    return headerView;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return [[UIView alloc] init];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"shape";
    ShapeCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell)
        cell = [[ShapeCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];

    cell.shapeMatches = _game->shapes()[indexPath.row];

    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    cell.backgroundColor = [UIColor colorWithRed:0.115 green:0.115 blue:0.115 alpha:1];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [_renderer hint:_game->shapes()[indexPath.row]];
}

#pragma mark - Actions

- (IBAction)tappedMatch {
    _game->match();
    [self.tableView reloadData];
}

@end
