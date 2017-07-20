//
//  AppDelegate.h
//  AFNetworkingDemo
//
//  Created by eidan on 2017/7/6.
//  Copyright © 2017年 Amap. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) void(^backgroundURLSessionCompletionHandler)(void);


@end

