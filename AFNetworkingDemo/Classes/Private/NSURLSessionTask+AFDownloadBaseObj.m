//
//  NSURLSessionTask+AFDownloadBaseObj.m
//  AFNetworkingDemo
//
//  Created by eidan on 2017/7/6.
//  Copyright © 2017年 Amap. All rights reserved.
//

#import "NSURLSessionTask+AFDownloadBaseObj.h"
#import <objc/runtime.h>

@implementation NSURLSessionTask (AFDownloadBaseObj)

- (AFDownloadBaseObj *)downloadObj {
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setDownloadObj:(AFDownloadBaseObj *)otherDownloadObj {
    objc_setAssociatedObject(self, @selector(downloadObj), otherDownloadObj, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
