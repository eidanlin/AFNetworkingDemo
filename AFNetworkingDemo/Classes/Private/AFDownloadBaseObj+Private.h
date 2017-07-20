//
//  AFDownloadBaseObj+Private.h
//  AFNetworkingDemo
//
//  Created by eidan on 2017/7/7.
//  Copyright © 2017年 Amap. All rights reserved.
//

// 内部使用

#import "AFDownloadBaseObj.h"

@interface AFDownloadBaseObj ()

@property (nonatomic, copy) NSString *identifierInternal;                   //唯一标识符
@property (nonatomic, copy) NSString *downloadUrlInternal;                  //下载要请求的地址
@property (nonatomic, copy) NSString *relativeSandboxLocalPathInternal;     //文件下载完成后，存储的相对沙盒根目录的“相对路径”。如 “/Library/Preferences/download/1.zip”
@property (nonatomic, assign) int64_t totalBytesExpectedToWriteInternal;    //文件的总长度
@property (nonatomic, assign) int64_t totalBytesWrittenInternal;            //目前已经被下载的长度
@property (nonatomic, assign) NSInteger downloadTaskIdentifier;             //对应的sessionTask的Identifier

@end
