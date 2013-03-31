//
//  ViewController.mm
//  DoubleDots
//
//  Created by Marcelo Cantos on 1/03/13.
//  Copyright (c) 2013 Habeo Soft. All rights reserved.
//

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
    _renderer.game = _game = std::make_shared<GameState>(iPad);
}

-(void)viewDidLayoutSubviews {
    _renderer.view.frame = CGRectMake(0, 0, iPad ? 768 : std::ceil(320*8/7.0), iPad ? 768 : 320);
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _game->shapes().size();
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return (iPad ? 137 : 130) - (iPad ? 15 : 14)*(8 - _game->shapes()[indexPath.row].height);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 40;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 40)];
    headerView.backgroundColor = [UIColor clearColor];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 33)];
    label.text = @"Best shapes";
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

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"shape";
    ShapeCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell)
        cell = [[ShapeCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];

    const auto& shape = _game->shapes()[indexPath.row];
    cell.quantity.text          = shape.count;
    cell.quantity.hidden        = shape.matches.size() < 2;
    cell.shape.image            = [UIImage imageNamed:@"appicon57.png"];
    cell.shapeText.text         = shape.text;
    cell.scores.numberOfLines   = shape.matches.size();
    cell.scores.text            = shape.scores;

    return cell;
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
