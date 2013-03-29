//
//  ShapeCell.h
//  DoubleDots
//
//  Created by Marcelo Cantos on 11/03/13.
//  Copyright (c) 2013 Marcelo Cantos. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ShapeCell : UITableViewCell

@property (nonatomic, strong) IBOutlet UILabel     *quantity;
@property (nonatomic, strong) IBOutlet UIImageView *shape;
@property (strong, nonatomic) IBOutlet UITextView  *shapeText;

@end
