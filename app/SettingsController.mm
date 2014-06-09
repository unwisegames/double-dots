//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import "SettingsController.h"

@interface SettingsController ()

@end

@implementation SettingsController

@synthesize colorBlind = _colorBlind, colorBlindButton = _colorBlindButton, newGame = _newGame, toggleColorBlind = _toggleColorBlind, tutorial = _tutorial, cancelled = _cancelled;

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
    int tag = sender.tag;
    int colors  = tag %  10; tag /=  10;
    int y       = tag % 100; tag /= 100;
    int x       = tag % 100; tag /= 100;
    int timed   = tag %  10; tag /=  10;
    assert(!tag);
    _newGame(x, y, colors, timed);
}

- (IBAction)tappedColorBlind:(UIButton *)sender {
    _colorBlindButton.selected ^= 1;
    _toggleColorBlind();
}

- (IBAction)tappedTutorial:(UIButton *)sender {
    _tutorial();
}

- (IBAction)tappedCancel:(UIButton *)sender {
    _cancelled();
}

@end
