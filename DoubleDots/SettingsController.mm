//
//  SettingsController.m
//  DoubleDots
//
//  Created by Marcelo Cantos on 26/04/13.
//  Copyright (c) 2013 Marcelo Cantos. All rights reserved.
//

#import "SettingsController.h"

@interface SettingsController ()

@end

@implementation SettingsController

@synthesize colorBlind = _colorBlind, colorBlindButton = _colorBlindButton, newGame = _newGame, toggleColorBlind = _toggleColorBlind, tutorial = _tutorial;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _colorBlindButton.selected = _colorBlind;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)tappedNewGame:(UIButton *)sender {
    _newGame(sender.tag);
}

- (IBAction)tappedColorBlind:(UIButton *)sender {
    _toggleColorBlind();
}

- (IBAction)tappedTutorial:(UIButton *)sender {
    _tutorial();
}

@end
