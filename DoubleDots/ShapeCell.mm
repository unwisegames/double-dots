//
//  ShapeCell.m
//  DoubleDots
//
//  Created by Marcelo Cantos on 11/03/13.
//  Copyright (c) 2013 Marcelo Cantos. All rights reserved.
//

#import "ShapeCell.h"
#import "Board.h"

#include <sstream>

@interface ShapeCell () {
    std::shared_ptr<ShapeMatches> _sm;
    bool _scoresUpdated;
}
@property (nonatomic, strong) IBOutlet UILabel      *quantity;
@property (nonatomic, strong) IBOutlet UIImageView  *shape;
@property (strong, nonatomic) IBOutlet UILabel      *border;
@property (strong, nonatomic) IBOutlet UILabel      *scores;
@end

@implementation ShapeCell

@synthesize quantity = _quantity, shape = _shape, border = _border;

- (void)setShapeMatches:(const std::shared_ptr<ShapeMatches>&)sm {
    _sm = sm;

    std::ostringstream shapeText;
    write(shapeText, habeo::Board<1>{{{0xffffffffffffffffULL}}}, {sm->shape}, " O", true);

    _quantity.hidden        = sm->matches.size() < 2;
    if (!_quantity.hidden)
        _quantity.text      = [NSString stringWithFormat:@"%ld ×", sm->matches.size()];
    _shape.image            = [UIImage imageNamed:@"appicon57.png"];
    _border.text            = [NSString stringWithUTF8String:shapeText.str().c_str()];
    _border.numberOfLines   = 8 - sm->shape.marginN();
    _scores.numberOfLines   = sm->matches.size();

    [self updateScores];
}

- (void)updateScores {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentRight;

    NSMutableAttributedString *scoresText = [[NSMutableAttributedString alloc] init];
    for (auto i = begin(_sm->matches); i != end(_sm->matches); ++i) {
        const auto& m = *i;
        bool first = &m == &_sm->matches.front();
        bool last = &m == &_sm->matches.back();
        [scoresText appendAttributedString:[[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@%@", @(m.score), (last ? @"" : @"\n")]
                                                                                  attributes:(@{
                                                                                              NSForegroundColorAttributeName:first && _scoresUpdated ? [UIColor redColor] : [UIColor whiteColor],
                                                                                              NSBackgroundColorAttributeName:[UIColor clearColor],
                                                                                              NSParagraphStyleAttributeName :style,
                                                                                              })]];
    }

    _scores.attributedText = scoresText;
    _scoresUpdated = true;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization code
    }
    return self;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
