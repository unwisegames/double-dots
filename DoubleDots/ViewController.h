//
//  ViewController.h
//  DoubleDots
//
//  Created by Marcelo Cantos on 3/03/13.
//  Copyright (c) 2013 Marcelo Cantos. All rights reserved.
//

#import "RenderController.h"

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController<UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) IBOutlet UITableView *tableView;
@property (nonatomic, strong) IBOutlet RenderController *renderer;

- (IBAction)tappedMatch;
@end
