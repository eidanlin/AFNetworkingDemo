//
//  AFDownloadSessionManager.m
//  AFNetworkingDemo
//
//  Created by eidan on 2017/7/6.
//  Copyright © 2017年 Amap. All rights reserved.
//

#import "AFDownloadSessionManager.h"
#import <AFNetworking/AFNetworking.h>
#import "AFDownloadBaseObj.h"
#import "NSURLSessionTask+AFDownloadBaseObj.h"
#import "AFDownloadBaseObj+Private.h"
#import "AppDelegate.h"

NSString * const AFDownloadSessionErrorDomain = @"AFDownloadSessionErrorDomain";
NSString * const AFDownloadSessionManagerResumeDatasDicLocalKey = @"AFDownloadSessionManagerResumeDatasDicLocalKey";
NSString * const AFDownloadSessionManagerDownloadingObjsDicLocalKey = @"AFDownloadSessionManagerDownloadingObjsDicLocalKey";
CGFloat const AFDownloadSessionManagerDelayTimeToNotifyDelegateWhenReLaunchApp = 1;

@interface AFDownloadSessionManager ()

@property (nonatomic, copy) NSString *managerIdentifier;

@property (nonatomic, strong) AFURLSessionManager *sessionManager;

@property (nonatomic, strong) NSMutableDictionary *downloadingObjsDic;  //这个只是用来内部维护，便于后台下载通知
@property (nonatomic, strong) dispatch_queue_t downloadingObjsQueue;

@property (nonatomic, strong) NSMutableDictionary *resumeDatasDic;
@property (nonatomic, strong) dispatch_queue_t resumeDataQueue;

@property (nonatomic, strong) NSUserDefaults *userDefaults;
@property (nonatomic, assign) BOOL isBackground; //是否是后台下载

@property (nonatomic, strong) NSDate *timeWhenInit; //init 时的时间戳

@end

@implementation AFDownloadSessionManager

#pragma mark - LifeCycle

+ (AFDownloadSessionManager *)backgrondManager {
    static AFDownloadSessionManager *_sharedInstance = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        _sharedInstance = [[AFDownloadSessionManager alloc] initWithIsNeedBackgroundDownload:YES];
    });
    return _sharedInstance;
}

+ (AFDownloadSessionManager *)standardManager {
    static AFDownloadSessionManager *_sharedInstance = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        _sharedInstance = [[AFDownloadSessionManager alloc] initWithIsNeedBackgroundDownload:NO];
    });
    return _sharedInstance;
}

- (instancetype)initWithIsNeedBackgroundDownload:(BOOL)isNeedBackground {
    
    self = [super init];
    
    if (self) {
        NSString * bundleId = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
        NSString *identifier = [NSString stringWithFormat:@"%@.AFDownloadSessionManager.%@",bundleId,isNeedBackground ? @"backgrond" : @"standard"];
        self.managerIdentifier = identifier;
        self.isBackground = isNeedBackground;
        [self setup];
    }
    
    return self;
    
}

#pragma mark - Init

- (void)setup {
    
    self.resumeDataQueue =  dispatch_queue_create([NSString stringWithFormat:@"%@.resumeDataQueue",self.managerIdentifier].UTF8String, DISPATCH_QUEUE_CONCURRENT);  //并行
    self.downloadingObjsQueue = dispatch_queue_create([NSString stringWithFormat:@"%@.downloadingObjsQueue",self.managerIdentifier].UTF8String, DISPATCH_QUEUE_CONCURRENT); //并行
    self.userDefaults = [[NSUserDefaults alloc] initWithSuiteName:[NSString stringWithFormat:@"%@.userDefaults",self.managerIdentifier]];  //本地持久化
    
    self.resumeDatasDic = [NSMutableDictionary dictionaryWithDictionary:[self readObj:AFDownloadSessionManagerResumeDatasDicLocalKey]];
    self.downloadingObjsDic = [NSMutableDictionary dictionaryWithDictionary:[self readObj:AFDownloadSessionManagerDownloadingObjsDicLocalKey]];
    
    if (self.isBackground) {
        NSURLSessionConfiguration *backgroundSessionConfiguration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:self.managerIdentifier];
        self.sessionManager = [[AFURLSessionManager alloc] initWithSessionConfiguration:backgroundSessionConfiguration];
        [self createBackgroundDownloadTmpFileFolder];
    } else {
        self.sessionManager = [[AFURLSessionManager alloc] init];
    }
    
    self.timeWhenInit = [NSDate date];
    
    __weak typeof(self) weakSelf = self;
    
    //百分比。
    [self.sessionManager setDownloadTaskDidWriteDataBlock:^(NSURLSession * _Nonnull session, NSURLSessionDownloadTask * _Nonnull downloadTask, int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite) {
        
        if (!downloadTask.downloadObj) {  //后台下载
            [weakSelf resetObjToTaskWhenAppReLauncheWithTask:downloadTask];
        }
        
        if (downloadTask.downloadObj) {
            downloadTask.downloadObj.totalBytesExpectedToWriteInternal = totalBytesExpectedToWrite;
            downloadTask.downloadObj.totalBytesWrittenInternal = totalBytesWritten;
            [weakSelf notifyDelegateWhenWriteData:downloadTask.downloadObj];
        }
        
    }];
    
    
    //这边需要提供一个下载文件的存储地址，manager里面会自动把tmp文件移动到这个地址，如果这里的回调调用了，代表已经下载成功了，正准备开始移动，移动成功后才去调用DidCompleteBlock。
    [self.sessionManager setDownloadTaskDidFinishDownloadingBlock:^NSURL * _Nullable(NSURLSession * _Nonnull session, NSURLSessionDownloadTask * _Nonnull downloadTask, NSURL * _Nonnull location) {
        
        if (!downloadTask.downloadObj) {  //后台下载成功后，APP第二次启动的处理。
            [weakSelf resetObjToTaskWhenAppReLauncheWithTask:downloadTask];
        }
        
        if (downloadTask.downloadObj) {
            
            NSRange range = [downloadTask.downloadObj.relativeSandboxLocalPath rangeOfString:@"/" options:NSBackwardsSearch];
            
            //找到了，代表相对沙盒根目录后有文件夹，那么就要看这个文件夹是否存在，不存在，就需要创建
            if (range.location != NSNotFound) {
                NSString *relativeFolderPath = [downloadTask.downloadObj.relativeSandboxLocalPath substringToIndex:range.location];  //去掉了文件的文件名和后缀名剩下的文件夹路径
                NSString *absoluteFolderPath = [NSHomeDirectory() stringByAppendingPathComponent:relativeFolderPath];
                if (![[NSFileManager defaultManager] fileExistsAtPath:absoluteFolderPath]) {
                    [[NSFileManager defaultManager] createDirectoryAtPath:absoluteFolderPath withIntermediateDirectories:YES attributes:nil error:nil];
                }
            }
            
            //如果同一路径，文件已经存在，需要先删除，否则也会移动失败..如果外界传入Documents，也会把Documents成功删除掉
            if ([[NSFileManager defaultManager] fileExistsAtPath:downloadTask.downloadObj.absoluteSandboxLocalPath.path]) {
                [[NSFileManager defaultManager] removeItemAtPath:downloadTask.downloadObj.absoluteSandboxLocalPath.path error:nil];
            }
            
            //处理一下location，因为后台下载后的二次汇报location的沙盒地址是不对的
            NSURL *newTmpLocation = [weakSelf updateTempFileURLAppReLauncheWithOriginURL:location];
            
//            NSLog(@"location: %@, isExist: %d",location,[[NSFileManager defaultManager] fileExistsAtPath:location.path]);
//            NSLog(@"newTmpLocation: %@, isExist %d",newTmpLocation,[[NSFileManager defaultManager] fileExistsAtPath:newTmpLocation.path]);
            
            //移动文件
            NSError *error = nil;
            [[NSFileManager defaultManager] moveItemAtURL:newTmpLocation toURL:downloadTask.downloadObj.absoluteSandboxLocalPath error:&error];
            
//            if (error) {
//                NSLog(@"移动文件发生错误 %lu,%@",(unsigned long)downloadTask.taskIdentifier,error);
//            }
            
        } else {
            //如果调用到这里，就是 self.downloadingObjsDic 里面没有这个任务，也就是上次 self.downloadingObjsDic 的本地化出现了问题
            //比如还没来得及存到本地，App就被划掉或者Crash了。
        }
        return nil;  //全部返回nil，也就是不让sessionManager帮我们移动文件，不管前后台下载都是我们自己移动
    }];
    
    
    
    //下载完成，暂停，失败都会调用
    [self.sessionManager setTaskDidCompleteBlock:^(NSURLSession * _Nonnull session, NSURLSessionTask * _Nonnull task, NSError * _Nullable error) {
        
        /*
         * 如果用户主动暂停或者取消，task.downloadObj 一定是有值的，所以 task.downloadObj 为nil的话，一定是第二次启动App，系统的主动通知
         * 如果后台下载文件成功，第二次启动时，系统会主动调用移动文件的回调，那里就已经让task有obj了，如果这里task还没有obj，证明应该是有error，没有执行移动文件的回调。
         * 如果是后台下载，用户在下载个过程，主动划掉App来杀死App，后台下载不会继续，等到第二次启动时，系统会主动通知，且error.code = -999
         * 根据以上规则，我们做了如下处理，就是只要是用户主动划掉App，我们再下次启动时，把这些任务又主动添加到下载队列中，继续下载，不通知用户“下载失败”，这样一切就无缝的切换，用户第二次启动后又继续下载了
         */
        if (!task.downloadObj) {  //后台下载成功后，APP第二次启动的处理。
            
            [weakSelf resetObjToTaskWhenAppReLauncheWithTask:task];
            
            if (task.downloadObj && error.code == -999) {
                
                if ([error.userInfo objectForKey:@"NSURLSessionDownloadTaskResumeData"]) {  //系统已经自动帮我们保存好ResumeData的，我们继续下载
                    
                    //存一下resumeData
                    [weakSelf.resumeDatasDic setObject:[error.userInfo objectForKey:@"NSURLSessionDownloadTaskResumeData"] forKey:task.downloadObj.identifierInternal];
                    
                    //继续下载
                    [weakSelf resumeDownloadTaskWithIdentifier:task.downloadObj.identifierInternal];
                    
                    dispatch_async(weakSelf.resumeDataQueue, ^{
                        [weakSelf updateObj:weakSelf.resumeDatasDic forKey:AFDownloadSessionManagerResumeDatasDicLocalKey];
                    });
                    
                } else {  //如果没有resumeData，证明在之前的下载，他还没有被开始，我们继续把他加入队列
                    [weakSelf resumeDownloadTaskWithIdentifier:task.downloadObj.identifierInternal];
                }
                
                return;   //如果是这样情况，重新加入下载队列，就返回了，不进行通知
            }

        }
        
        if (task.downloadObj) {
            [weakSelf handleWhenCompleteWithSession:session task:task error:error];
        }
    }];
    
    
    /* 
     * 后台下载全部完成后的回调
     * application 在收到如下回调后
     * -application:handleEventsForBackgroundURLSession:completionHandler:
     * 会调用 session的 setDidFinishEventsForBackgroundURLSessionBlock ，说明了之前在这个session里的任务已经全部完成了
     * 这个时候就可以处理程序内部的本地数据库和界面更新，在最后一定要调用一下之前在AppDelegate中存储的 completion handler
     */
    [self.sessionManager setDidFinishEventsForBackgroundURLSessionBlock:^(NSURLSession * _Nonnull session) {
        dispatch_async(dispatch_get_main_queue(), ^{
            AppDelegate *XAppDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
            if (XAppDelegate.backgroundURLSessionCompletionHandler) {
                void (^handler)() = XAppDelegate.backgroundURLSessionCompletionHandler;
                XAppDelegate.backgroundURLSessionCompletionHandler = nil;
                handler();
            }
        });
    }];
    
}


#pragma mark - Interface

- (void)setDelegate:(id<AFDownloadSessionManagerDelegate>)delegate {
    
    _delegate = delegate;
    
    if (delegate && !self.isBackground) {  //非后台下载才需要根据resumeData去矫正百分比，后台下载的resumeData本身就不准，没有意义了。
        [self handleDownloadingObjsPercentToRightAccordingResumeData];
    }
    
    if (self.isBackground) {  //后台下载，延迟一下，让二次启动的下载汇报，先汇报完，self.downloadingObjsDic的数据为正确状态
        [self performSelector:@selector(startDownloadAllTasksThatInDownloadingObjsDicButNoInSession) withObject:nil afterDelay:2];
    } else {
        [self startDownloadAllTasksThatInDownloadingObjsDicButNoInSession];
    }
    
    //这里调用可有，可无，只是为了保险
    [self checkResumeDatasDicAccordingDownloadingObjsDic];
}

- (AFDownloadBaseObj *)startDownloadTaskWithDownloadUrl:(NSString *)downloadUrl relativeSandboxLocalPath:(NSString *)relativeSandboxLocalPath {
    return [self startDownloadTaskWithDownloadUrl:downloadUrl relativeSandboxLocalPath:relativeSandboxLocalPath identifier:nil];
}

- (void)pauseDownloadTaskWithIdentifier:(NSString *)identifier {
    [self cancelDownloadTaskWithIdentifier:identifier needSaveResumeData:YES];
}

- (void)cancelDownloadTaskWithIdentifier:(NSString *)identifier {
    [self cancelDownloadTaskWithIdentifier:identifier needSaveResumeData:NO];
}

- (BOOL)resumeDownloadTaskWithIdentifier:(NSString *)identifier {
    
    if (!identifier) {
        return NO;
    }
    
    NSData *resumeData = [self.resumeDatasDic objectForKey:identifier];
    AFDownloadBaseObj *obj = [self.downloadingObjsDic objectForKey:identifier];
    
    if (obj) {
        
        if (resumeData) {
            //iOS10.3亲测：如果下载的.tmp文件不见了（被删除了），然后断点续传，系统会发出这样一个通知：__NSCFLocalDownloadFile: error 2 opening resume file:XXX。
            //系统会全自动从头开始下载，不用我们做任何处理。
            //但其他的系统型号可能会报错，然后走错误回调，也一样告诉了开发者，让其自行处理.
            NSURLSessionDownloadTask *downloadTask = [self.sessionManager downloadTaskWithResumeData:resumeData progress:nil destination:nil completionHandler:nil];
            downloadTask.downloadObj = obj;
            obj.downloadTaskIdentifier = downloadTask.taskIdentifier;
            [downloadTask resume];
            
             //更新一下 obj.downloadTaskIdentifier 到本地
            [self updateObj:self.downloadingObjsDic forKey:AFDownloadSessionManagerDownloadingObjsDicLocalKey];
            
        } else {
            //如果下载到一半，没有暂停，直接划掉App，就会出现有obj，没有resumeData
            //但用户和我们都有这个identifier，我们就要从新开始，就要把用户这个identifier替换掉我们刚刚自生成的，这样回调出去后，用户才能唯一确定是哪个identifier正在下载
            [self startDownloadTaskWithDownloadUrl:obj.downloadUrlInternal relativeSandboxLocalPath:obj.relativeSandboxLocalPathInternal identifier:identifier];
        }
        
        return YES;
    }
    
    return NO;
    
}

- (BOOL)taskWithIdentifierIsDownloading:(NSString *)identifier {
    
    AFDownloadBaseObj *obj = [self.downloadingObjsDic objectForKey:identifier];
    
    if (obj) {
        
        NSInteger isRunning = [self objIsRunning:identifier];
        
        if (isRunning == 0) {  //有obj，但不在队列的才加，正常情况应该是不会出现为0的情况，加一层判断，防止漏网之鱼
            [self resumeDownloadTaskWithIdentifier:identifier];
        }
        
        return YES;
    }
    
    return NO;
}

#pragma mark - Uility

//让本地已经有但还没有添加到下载队列中的obj，添加到下载的队列中
- (void)startDownloadAllTasksThatInDownloadingObjsDicButNoInSession {
    
    for (NSString *identifierInternal in self.downloadingObjsDic.allKeys) {
        NSInteger isRunning = [self objIsRunning:identifierInternal];
        if (isRunning == 0) {  //不在队列的才加，未知的都不能加，未知会在任务通报后，自动处理的。
            [self resumeDownloadTaskWithIdentifier:identifierInternal];
        }
    }
}

/*
 * 目前是否正在下载的队列里
 * -1: 未知，只有后台下载，在第二次刚init时，“任务汇报”还没来得及结束，就先调用此函数，task没有对应的downloadObj，就是未知。
 * 0 : 没有在队列里
 * 1 : 已经在队列里
 */
- (NSInteger)objIsRunning:(NSString *)identifier {
    
    BOOL taskDoesNotObj = NO;
    
    for (NSURLSessionDataTask *task in self.sessionManager.downloadTasks) {
        
        if (task.downloadObj == nil) {  //没有obj
            taskDoesNotObj = YES;
            continue;
        }
        
        if ([task.downloadObj.identifierInternal isEqualToString:identifier]) {  //有obj，且相等，证明在队列里
            return 1;
        }
    }
    
    if (taskDoesNotObj) {
        return -1;
    }
    
    return 0;  //不在队列里
}

- (AFDownloadBaseObj *)startDownloadTaskWithDownloadUrl:(NSString *)downloadUrl relativeSandboxLocalPath:(NSString *)relativeSandboxLocalPath identifier:(NSString *)identifier{
    
    if (!(downloadUrl.length && relativeSandboxLocalPath.length)) {
        return nil;
    }
    
    AFDownloadBaseObj *obj = [[AFDownloadBaseObj alloc] init];
    obj.downloadUrlInternal = downloadUrl;
    obj.relativeSandboxLocalPathInternal = relativeSandboxLocalPath;
    if (identifier.length) {
        obj.identifierInternal = identifier;
    }
    
    NSURL *URL = [NSURL URLWithString:obj.downloadUrlInternal];
    NSURLRequest *request = [NSURLRequest requestWithURL:URL];
    
    NSURLSessionDownloadTask *downloadTask = [self.sessionManager downloadTaskWithRequest:request progress:nil destination:nil completionHandler:nil];
    obj.downloadTaskIdentifier = downloadTask.taskIdentifier;
    downloadTask.downloadObj = obj;
    [downloadTask resume];
    
    [self.downloadingObjsDic setObject:obj forKey:obj.identifierInternal];
    [self updateObj:self.downloadingObjsDic forKey:AFDownloadSessionManagerDownloadingObjsDicLocalKey];  //这个地方的存储不放在子线程，因为iPhone4s，500个存储所花的时间也才不到0.1s。
    
    return obj;
}

- (void)cancelDownloadTaskWithIdentifier:(NSString *)identifier needSaveResumeData:(BOOL)isNeed {
    
    AFDownloadBaseObj *obj = [self.downloadingObjsDic objectForKey:identifier];  // identifier为nil也可以
    
    if (!obj) {
        NSError *error = [self errorWithErrorCode:AFDownloadSessionErrorCannotFindTask info:@"下载队列中找不到指定的任务"];
        if (isNeed) {  //代表暂停,找不到要暂停的文件
            [self notifyDelegateWhenPauseComplete:identifier error:error];
        } else {  //代表取消,找不到要取消的文件
            [self notifyDelegateWhenCancelComplete:identifier error:error];
        }
        return;
    }
    
    for (NSURLSessionDownloadTask *task in self.sessionManager.downloadTasks) {
        
        if (task.taskIdentifier == obj.downloadTaskIdentifier) {
            if (isNeed) {
                [task cancelByProducingResumeData:^(NSData * _Nullable resumeData) {
                    
                }];
            } else {
                [task cancel];
            }
        }
    }
    
}

//后台下载中，第二次启动App，进行已完成的后台任务的汇报需要找到obj
- (void)resetObjToTaskWhenAppReLauncheWithTask:(NSURLSessionTask *)task {
    for (AFDownloadBaseObj *obj in self.downloadingObjsDic.allValues) {
        if (obj.downloadTaskIdentifier == task.taskIdentifier) {
            task.downloadObj = obj;
            break;
        }
    }
}

//后台下载的缓存文件夹，理论上系统会帮我们创建好，但不知为什么有时候会被删除掉，所以需要手动创建,保证之后的下载任务能够顺利进行
- (void)createBackgroundDownloadTmpFileFolder {
    NSString *bundleId = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
    NSString *relativePath = [NSString stringWithFormat:@"%@%@",@"Library/Caches/com.apple.nsurlsessiond/Downloads/",bundleId];
    NSString *absolutePath = [NSHomeDirectory() stringByAppendingPathComponent:relativePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:absolutePath]) {
        [[NSFileManager defaultManager ] createDirectoryAtPath:absolutePath withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

//前台下载的.tmp文件是放在沙盒 tmp文件夹下
//后台下载的.tmp文件是放在沙盒 Library/Caches/com.apple.nsurlsessiond/Downloads/"BundleId" 的文件夹下
//后台下载中，第二次启动App，根据.tmp文件之前的沙盒地址，重新拼装一个能够真正能取到.tmp文件的地址
//原来的：/private/var/mobile/Containers/Data/Application/F0B147AC-6C8B-4B0B-922B-84E2E6CCE5EC/Library/Caches/com.apple.nsurlsessiond/Downloads/com.haomee.Laiba/CFNetworkDownload_SHifNR.tmp
//新拼的：/privat/var/mobile/Containers/Data/Application/548E06DB-927C-4B8A-A5F8-9228FB2C078A/Library/Caches/com.apple.nsurlsessiond/Downloads/com.haomee.Laiba/CFNetworkDownload_SHifNR.tmp
- (NSURL *)updateTempFileURLAppReLauncheWithOriginURL:(NSURL *)originURL{
    
    NSURL *newURL = originURL;
    
    NSString *bundleId = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
    NSString *relativePath = [NSString stringWithFormat:@"%@%@",@"Library/Caches/com.apple.nsurlsessiond/Downloads/",bundleId];
    
    NSInteger locationInLocationPath = [originURL.path rangeOfString:relativePath].location;
    
    if (locationInLocationPath != NSNotFound ) {
        NSString *fileName = [originURL.path substringFromIndex:locationInLocationPath + relativePath.length ];  //获取文件名如 CFNetworkDownload_SHifNR.tmp
        NSString *newRelativePath = [NSString stringWithFormat:@"%@%@",relativePath,fileName];
        newURL = [[NSURL fileURLWithPath:NSHomeDirectory()] URLByAppendingPathComponent:newRelativePath];
    }
    
    return newURL;
}

//下载完成的处理，点击暂停也会调用。
- (void)handleWhenCompleteWithSession:(NSURLSession *)session task:(NSURLSessionTask *)task error:(NSError *)error {
    
    if (error) {  //下载出错
        
        if (error.code == -999) {   ///主动取消，不用发错误回调
            
            if ([error.userInfo objectForKey:@"NSURLSessionDownloadTaskResumeData"]) {  //需要断点续传
                
                //存一下resumeData
                [self.resumeDatasDic setObject:[error.userInfo objectForKey:@"NSURLSessionDownloadTaskResumeData"] forKey:task.downloadObj.identifierInternal];
                dispatch_async(self.resumeDataQueue, ^{
                    [self updateObj:self.resumeDatasDic forKey:AFDownloadSessionManagerResumeDatasDicLocalKey];
                });
                
                //存一下百分比，百分比只需这里存，因为只有正确的resumeData，百分比才有意义，所以两者都在子线程
                //比如下载到50%，应用划掉，resumeData没有成功保存，下次还是要从头开始下载，你在别的地方保存了50%，也是一个错误的值，所以只有在这里存储百分比
                dispatch_async(self.downloadingObjsQueue, ^{
                    [self updateObj:self.downloadingObjsDic forKey:AFDownloadSessionManagerDownloadingObjsDicLocalKey];
                });
                
                //放这里，让内部数据先归位，再发送delegate，暂停成功
                [self notifyDelegateWhenPauseComplete:task.downloadObj.identifierInternal error:nil];
                
            } else {  //如果没有resumeData，证明是直接取消，不需要断点续传。
                
                task.downloadObj.totalBytesWrittenInternal = 0;
                [self handleDownloadingObjsDicWhenDownloadCompleteWithObj:task.downloadObj];
                [self handleResumeDatasDicWhenDownloadCompleteWithObj:task.downloadObj];
                
                //百分比
                [self notifyDelegateWhenWriteData:task.downloadObj];
                
                //取消成功
                [self notifyDelegateWhenCancelComplete:task.downloadObj.identifierInternal error:nil];
                
            }
            
        } else {
            
            task.downloadObj.totalBytesWrittenInternal = 0;
            NSError *aError = [NSError errorWithDomain:AFDownloadSessionErrorDomain code:ADDownloadSessionErrorNSURLError userInfo:@{@"NSURLErrorDomain":[NSString stringWithFormat:@"%@",error.domain],@"NSURLErrorCode":@(error.code),@"NSURLErrorInfo":error.userInfo}];
            
            [self handleDownloadingObjsDicWhenDownloadCompleteWithObj:task.downloadObj];
            [self handleResumeDatasDicWhenDownloadCompleteWithObj:task.downloadObj];
            
            [self notifyDelegateWhenDownloadCompleteWithTask:task error:aError];

        }
        
    } else {  //下载没有出错
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:[task.downloadObj.absoluteSandboxLocalPath path]]) {  //也在指定位置找到文件，我们才能说真正下载成功。
            
            task.downloadObj.totalBytesWrittenInternal = task.downloadObj.totalBytesExpectedToWriteInternal = [self getContentLengthWithHeaderInfo:task.response];  //如果是后台下载中间没有经历过百分比，totalBytesExpectedToWriteInternal也是为0的，所以还是从response取才靠谱
            
            [self handleDownloadingObjsDicWhenDownloadCompleteWithObj:task.downloadObj];
            [self handleResumeDatasDicWhenDownloadCompleteWithObj:task.downloadObj];
            
            [self notifyDelegateWhenDownloadCompleteWithTask:task error:nil];

        } else {  //找不到文件，下载本身没有出错，也已经调用了移动文件，就是移动文件出错，导致没有找到下载完后的文件
            //移动文件一般不可能出错，出错的最大原因为.tmp文件不存在，.tmp文件一些情况下会被系统删除掉（系统的bug），常常出现在多次Crash之后，所以只能重新下载
            task.downloadObj.totalBytesWrittenInternal = 0;
            [self resumeDownloadTaskWithIdentifier:task.downloadObj.identifierInternal];
            [self notifyDelegateWhenWriteData:task.downloadObj];
        }

    }
    
}


//根据ResumeData将obj的百分比设置成正确的值,因为有可能下载一半被划掉，下载了10%，百分比和resumeData都被存了，然后下了20%，百分比被存了，resumeData没有被存，那么百分比就要回到10%，并告诉外界
- (void)handleDownloadingObjsPercentToRightAccordingResumeData {
    
    for (NSString *identifierInternal in self.downloadingObjsDic.allKeys) {
        
        AFDownloadBaseObj *obj = [self.downloadingObjsDic objectForKey:identifierInternal];
        
        NSData *resumeData = [self.resumeDatasDic objectForKey:identifierInternal];
        
        if (resumeData) {  //有resumeData，从resumeData里面取出最新的
            NSString *dataString = [[NSString alloc] initWithData:resumeData encoding:NSUTF8StringEncoding];
            NSRange range = [dataString rangeOfString:@"<key>NSURLSessionResumeBytesReceived</key>"];
            if (range.location != NSNotFound) {
                dataString = [dataString substringFromIndex:range.location + range.length];
                NSRange startRange = [dataString rangeOfString:@"<integer>"];
                NSRange endRange = [dataString rangeOfString:@"</integer>"];
                if (endRange.location != NSNotFound && startRange.location != NSNotFound) {
                    NSString *totalBytesWritten = [dataString substringWithRange:NSMakeRange(startRange.location + 9, endRange.location - startRange.location - 9)];
                    if (obj.totalBytesWrittenInternal != [totalBytesWritten longLongValue]) {
                        obj.totalBytesWrittenInternal = [totalBytesWritten longLongValue];
                        [self notifyDelegateWhenWriteData:obj];
                    }
                }
            }
            
        } else {  //没有resumeData，百分比为0
            if (obj.totalBytesWrittenInternal != 0) {
                obj.totalBytesWrittenInternal = 0;
                [self notifyDelegateWhenWriteData:obj];
            }
        }
    }
    
    dispatch_async(self.downloadingObjsQueue, ^{
        [self updateObj:self.downloadingObjsDic forKey:AFDownloadSessionManagerDownloadingObjsDicLocalKey];
    });
    
}

- (void)handleResumeDatasDicWhenDownloadCompleteWithObj:(AFDownloadBaseObj *)obj {
    if ([self.resumeDatasDic objectForKey:obj.identifierInternal]) {
        [self.resumeDatasDic removeObjectForKey:obj.identifierInternal];
        dispatch_async(self.resumeDataQueue, ^{ //不卡线程
            [self updateObj:self.resumeDatasDic forKey:AFDownloadSessionManagerResumeDatasDicLocalKey];
        });
    }
}

- (void)handleDownloadingObjsDicWhenDownloadCompleteWithObj:(AFDownloadBaseObj *)obj {
    if ([self.downloadingObjsDic objectForKey:obj.identifierInternal]) {
        [self.downloadingObjsDic removeObjectForKey:obj.identifierInternal];
        [self updateObj:self.downloadingObjsDic forKey:AFDownloadSessionManagerDownloadingObjsDicLocalKey];  //卡住，防止数据错误
    }
    
    [self checkResumeDatasDicAccordingDownloadingObjsDic];
}

//如果一个identifier在downloadingObjsDic里没有，但在resumeDatasDic有，应该移除，这种情况可能很少。
- (void)checkResumeDatasDicAccordingDownloadingObjsDic {
    dispatch_async(self.resumeDataQueue, ^{ //不卡线程
        
        NSMutableArray *needRemoveKeys = [NSMutableArray array];
        
        for (NSString *key in self.resumeDatasDic.allKeys) {
            if ([self.downloadingObjsDic objectForKey:key] == nil) {
                [needRemoveKeys addObject:key];
            }
        }
        
        if (needRemoveKeys.count) {
            [self.resumeDatasDic removeObjectsForKeys:needRemoveKeys];
            [self updateObj:self.resumeDatasDic forKey:AFDownloadSessionManagerResumeDatasDicLocalKey];
        }
        
    });
}

//获得完成文件的大小
- (int64_t)getContentLengthWithHeaderInfo:(NSURLResponse *)response {
    
    if (!response) {
        return 0;
    }
    
    NSDictionary *header = ((NSHTTPURLResponse *)response).allHeaderFields;
    
    int64_t contentLength = 0;
    
    if ([header objectForKey:@"Content-Range"]) {
        
        NSString *contentRange = [header objectForKey:@"Content-Range"];
        NSRange range =  [contentRange rangeOfString:@"/" options:NSBackwardsSearch];
        if (range.location != NSNotFound) {
            NSString *length = [contentRange substringFromIndex:range.location + 1];
            contentLength = [length longLongValue];
        }else{
            contentLength = [[header objectForKey:@"Content-Length"] longLongValue];
        }
        
    }else{
        contentLength = [[header objectForKey:@"Content-Length"] longLongValue];
    }
    return contentLength;
    
}

#pragma mark - Notify Delegate

- (void)notifyDelegateWhenDownloadCompleteWithTask:(NSURLSessionTask *)task error:(NSError *)aError{
    
    NSTimeInterval current = [[NSDate date] timeIntervalSinceDate:self.timeWhenInit];
    
    //如果下载成功或者失败的时间 与 init 的时间差小于1s，我们就认为此场景就是：后台下载第二次启动的任务汇报，这时我们延迟，就是为了让任务汇报都汇报完
    //可能有bad case，比如init时，立马有一个任务下载添加进来立刻失败了。我们也延迟通知，我觉得可以接受，况且这种情况非常少。
    if (current < AFDownloadSessionManagerDelayTimeToNotifyDelegateWhenReLaunchApp) {
        dispatch_time_t time = dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC);
        dispatch_after(time, dispatch_get_main_queue(), ^{
            [self notifyDelegateWhenWriteData:task.downloadObj];
            [self notifyDelegateWhenDownloadComplete:task.downloadObj error:aError];
        });
    } else {
        [self notifyDelegateWhenWriteData:task.downloadObj];
        [self notifyDelegateWhenDownloadComplete:task.downloadObj error:aError];
    }
    
}

- (void)notifyDelegateWhenDownloadComplete:(AFDownloadBaseObj *)obj error:(NSError *)error{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.delegate && [self.delegate respondsToSelector:@selector(sessionManager:taskDidDownloadComplete:error:)]) {
            [self.delegate sessionManager:self taskDidDownloadComplete:obj error:error];
        }
    });
}

- (void)notifyDelegateWhenPauseComplete:(NSString *)identifer error:(NSError *)error{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.delegate && [self.delegate respondsToSelector:@selector(sessionManager:taskDidPauseComplete:error:)]) {
            [self.delegate sessionManager:self taskDidPauseComplete:identifer error:error];
        }
    });
}

- (void)notifyDelegateWhenCancelComplete:(NSString *)identifer error:(NSError *)error{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.delegate && [self.delegate respondsToSelector:@selector(sessionManager:taskDidCancelComplete:error:)]) {
            [self.delegate sessionManager:self taskDidCancelComplete:identifer error:error];
        }
    });
}

- (void)notifyDelegateWhenWriteData:(AFDownloadBaseObj *)obj{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.delegate && [self.delegate respondsToSelector:@selector(sessionManager:taskDidWriteData:)]) {
            [self.delegate sessionManager:self taskDidWriteData:obj];
        }
    });
}

#pragma mark - Error

- (NSError *)errorWithErrorCode:(AFDownloadSessionErrorCode)code info:(NSString *)info {
    
    NSString *description = [NSString stringWithFormat:@"%@", info];
    
    NSError *error = [NSError errorWithDomain:AFDownloadSessionErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: description}];
    
    return error;
}

#pragma mark - CustomUserDefault

- (id)readObj:(NSString *)key {
    
    NSData *infoData = [self.userDefaults objectForKey:key];
    
    if (!infoData) {
        return nil;
    }
    
    id obj = [NSKeyedUnarchiver unarchiveObjectWithData:infoData];
    
    return obj;
}

- (void)updateObj:(id)obj forKey:(NSString *)key {
    
    if (obj == nil) {
        return;
    }
    
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:obj];
    [self.userDefaults setObject:data forKey:key];
    
    //ios7 需调用synchronize才能将数据文件写入到本地，否则存储不了
    if( [[[UIDevice currentDevice] systemVersion] intValue] == 7) {
        [self.userDefaults synchronize];
    }
    
}

@end
