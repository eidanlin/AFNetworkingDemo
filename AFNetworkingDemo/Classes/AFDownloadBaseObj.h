//
//  AFDownloadBaseObj.h
//  AFNetworkingDemo
//
//  Created by eidan on 2017/7/6.
//  Copyright © 2017年 Amap. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AFDownloadBaseObj : NSObject <NSCoding>

@property (nonatomic, copy, readonly) NSString *identifier;                     //唯一标识符，如果需要判断两个AFDownloadBaseObj是否相等，必须判断其identifier是否相等，不能直接判断obj之间是否相等
@property (nonatomic, copy, readonly) NSString *downloadUrl;                    //下载要请求的地址
@property (nonatomic, copy, readonly) NSString *relativeSandboxLocalPath;       //文件下载完成后，存储的相对沙盒根目录的“相对路径”。如 “/Library/Preferences/download/1.zip”
@property (nonatomic, copy, readonly) NSURL *absoluteSandboxLocalPath;          //文件下载完成后的绝对路径
@property (nonatomic, assign, readonly) int64_t totalBytesExpectedToWrite;      //文件的总长度
@property (nonatomic, assign, readonly) int64_t totalBytesWritten;              //目前已经被下载的长度

@end
