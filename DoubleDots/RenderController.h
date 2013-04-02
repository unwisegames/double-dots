//
//  RenderController.h
//  DoubleDots
//
//  Created by Marcelo Cantos on 31/03/13.
//  Copyright (c) 2013 Marcelo Cantos. All rights reserved.
//

#import "GameState.h"

#import <GLKit/GLKit.h>

#include <memory>

@interface RenderController : GLKViewController

@property (nonatomic, assign) std::shared_ptr<GameState> game;

- (void)hint:(const std::shared_ptr<ShapeMatches>&)sm;

- (IBAction)tapGestured:(UITapGestureRecognizer *)sender;

@end
