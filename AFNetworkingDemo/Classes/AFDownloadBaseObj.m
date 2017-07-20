//
//  AFDownloadBaseObj.m
//  AFNetworkingDemo
//
//  Created by eidan on 2017/7/6.
//  Copyright © 2017年 Amap. All rights reserved.
//

#import "AFDownloadBaseObj.h"
#import "AFDownloadBaseObj+Private.h"

@interface AFDownloadBaseObj ()


@end


@implementation AFDownloadBaseObj

#pragma mark - LifeCycle

- (instancetype)init {
    self = [super init];
    if (self) {
        self.identifierInternal = [[NSUUID UUID] UUIDString];
    }
    return self;
}

//序列化，可以存储到本地的。
- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:self.identifierInternal forKey:@"AFDownloadBaseObj_1000"];
    [aCoder encodeObject:self.downloadUrlInternal forKey:@"AFDownloadBaseObj_1001"];
    [aCoder encodeObject:self.relativeSandboxLocalPathInternal forKey:@"AFDownloadBaseObj_1002"];
    [aCoder encodeInteger:self.downloadTaskIdentifier forKey:@"AFDownloadBaseObj_1003"];
    [aCoder encodeInt64:self.totalBytesWrittenInternal forKey:@"AFDownloadBaseObj_1004"];
    [aCoder encodeInt64:self.totalBytesExpectedToWriteInternal forKey:@"AFDownloadBaseObj_1005"];
}


//反序列化
- (id)initWithCoder:(NSCoder *)aDecoder{
    self = [super init];
    if (self){
        self.identifierInternal = [aDecoder decodeObjectForKey:@"AFDownloadBaseObj_1000"];
        self.downloadUrlInternal = [aDecoder decodeObjectForKey:@"AFDownloadBaseObj_1001"];
        self.relativeSandboxLocalPathInternal = [aDecoder decodeObjectForKey:@"AFDownloadBaseObj_1002"];
        self.downloadTaskIdentifier = [aDecoder decodeIntegerForKey:@"AFDownloadBaseObj_1003"];
        self.totalBytesWrittenInternal = [aDecoder decodeInt64ForKey:@"AFDownloadBaseObj_1004"];
        self.totalBytesExpectedToWriteInternal = [aDecoder decodeInt64ForKey:@"AFDownloadBaseObj_1005"];
    }
    return self;
}

#pragma mark - Interface

- (NSString *)identifier {
    return self.identifierInternal;
}

- (NSString *)downloadUrl {
    return self.downloadUrlInternal;
}

- (NSString *)relativeSandboxLocalPath {
    return self.relativeSandboxLocalPathInternal;
}

- (NSURL *)absoluteSandboxLocalPath {
    if (self.relativeSandboxLocalPath) {
       return  [[NSURL fileURLWithPath:NSHomeDirectory()] URLByAppendingPathComponent:self.relativeSandboxLocalPath];
    }
    return nil;
}

- (int64_t)totalBytesWritten {
    return self.totalBytesWrittenInternal;
}

- (int64_t)totalBytesExpectedToWrite {
    return self.totalBytesExpectedToWriteInternal;
}

@end
