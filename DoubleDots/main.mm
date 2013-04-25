//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import <UIKit/UIKit.h>

#import "AppDelegate.h"

#include "BitBoard.h"

int main(int argc, char *argv[])
{
    brac::test_BitBoard();

    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
