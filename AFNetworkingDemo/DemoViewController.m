//
//  DemoViewController.m
//  AFNetworkingDemo
//
//  Created by eidan on 2017/7/6.
//  Copyright © 2017年 Amap. All rights reserved.
//

#import "DemoViewController.h"
#import "AFDownloadSessionManager.h"

@interface DemoViewController () <AFDownloadSessionManagerDelegate>

@property (nonatomic, strong) AFDownloadSessionManager *downloadManager;

@property (nonatomic, strong) AFDownloadBaseObj *myObj;
@property (nonatomic, assign) int index;

@property (nonatomic, assign) int successIndex;


@end

@implementation DemoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"DEMO";
    
    // Do any additional setup after loading the view from its nib.
}
- (IBAction)doInit:(id)sender {
    self.downloadManager = [AFDownloadSessionManager backgrondManager];
    self.downloadManager.delegate = self;
}


- (void)startDownload {
    self.index++;

    NSString *downloadUrl = @"http://cdn.haomee.cn/manhua/emotion/zip/3.zip";
    NSString *relativeSandboxLocalPath = [NSString stringWithFormat:@"Documents/%d.zip",self.index];
    self.myObj = [self.downloadManager startDownloadTaskWithDownloadUrl:downloadUrl relativeSandboxLocalPath:relativeSandboxLocalPath];
//    NSLog(@"start %d",self.index);
    
    if (self.index < 20) {
        [self performSelector:@selector(startDownload) withObject:nil afterDelay:0.01];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (IBAction)startDownload:(id)sender {
    [self startDownload];
}

- (IBAction)cancelDownload:(id)sender {
    
////    if (self.successIndex >= 10) {  //下载完成3个，手动造成Crash
//        NSArray *array = @[];
//        NSString *strring = [array objectAtIndex:3];
//        NSLog(@"%@",strring);
////    }

    
    [self.downloadManager pauseDownloadTaskWithIdentifier:self.myObj.identifier];
}

- (IBAction)resumeDownload:(id)sender {
    [self.downloadManager resumeDownloadTaskWithIdentifier:self.myObj.identifier];
}

#pragma mark - AFDownloadSessionManagerDelegate

- (void)sessionManager:(AFDownloadSessionManager *)sessionManager taskDidDownloadComplete:(AFDownloadBaseObj *)obj error:(NSError *)error {
    if (error) {
        NSLog(@"!!! download failed %@,%@",obj.identifier,error);
    } else {
        NSLog(@"!!! download success %@,%@",obj.identifier,obj.absoluteSandboxLocalPath.path);
        self.successIndex++;
        if (self.successIndex >= 2) {  //下载完成3个，手动造成Crash
            NSArray *array = @[];
            NSString *strring = [array objectAtIndex:3];
            NSLog(@"%@",strring);
        }
    }
}

- (void)sessionManager:(AFDownloadSessionManager *)sessionManager taskDidPauseComplete:(NSString *)identifier error:(NSError *)error {
    if (error) {
        NSLog(@"!!! Pause failed %@,%@",identifier,error);  //如果外界有，AFDownloadSessionManager没有，应该是AFDownloadSessionManager没来得及把obj存本地，app就被杀死了，这是个bug。
    } else {
        NSLog(@"!!! Pause success %@",identifier);
    }
}

- (void)sessionManager:(AFDownloadSessionManager *)sessionManager taskDidCancelComplete:(NSString *)identifier error:(NSError *)error {
    if (error) {
        NSLog(@"!!! Cancel failed %@,%@",identifier,error);  //同上
    } else {
        NSLog(@"!!! Cancel success %@",identifier);
    }
}

- (void)sessionManager:(AFDownloadSessionManager *)sessionManager taskDidWriteData:(AFDownloadBaseObj *)obj {
    CGFloat percent = (CGFloat)obj.totalBytesWritten / obj.totalBytesExpectedToWrite;
//    NSLog(@"??? percent %@  , %f",obj.identifier, percent);
}


@end
