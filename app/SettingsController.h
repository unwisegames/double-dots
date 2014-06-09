//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import <UIKit/UIKit.h>

#include <functional>

@interface SettingsController : UIViewController

@property (nonatomic, assign) bool colorBlind;

@property (nonatomic, strong) IBOutlet UIButton * colorBlindButton;

@property (nonatomic, assign) std::function<void(int w, int h, int colors, bool timed)>    newGame;
@property (nonatomic, assign) std::function<void()>             toggleColorBlind;
@property (nonatomic, assign) std::function<void()>             tutorial;
@property (nonatomic, assign) std::function<void()>             cancelled;

- (IBAction)tappedNewGame   :(UIButton *)sender;
- (IBAction)tappedColorBlind:(UIButton *)sender;
- (IBAction)tappedTutorial  :(UIButton *)sender;
- (IBAction)tappedCancel    :(UIButton *)sender;

@end
