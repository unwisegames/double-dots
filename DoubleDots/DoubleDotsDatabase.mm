//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import "DoubleDotsDatabase.h"

#import "Database.h"

#import <Foundation/Foundation.h>

#include <mutex>

void prepareDoubleDotsDatabase() {
    std::once_flag once;
    std::call_once(once, []{
        constexpr int version = 0;
        
        brac::db::setupDB("DoubleDots",
                          version,
                          ^(int oldVersion,
                            void (^declareTable)(std::string const & name, std::string const & def),
                            void (^dropTable)(std::string const & name))
                          {
                          });
    });
}
