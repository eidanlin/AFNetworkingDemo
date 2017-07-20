//
//  AFDownloadSessionManager.h
//  AFNetworkingDemo
//
//  Created by eidan on 2017/7/6.
//  Copyright © 2017年 Amap. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AFDownloadBaseObj.h"

extern NSString * const AFDownloadSessionErrorDomain;

typedef NS_ENUM(NSInteger, AFDownloadSessionErrorCode) {
    AFDownloadSessionErrorCannotFindTask = 1,                       //找不到指定的下载任务
    ADDownloadSessionErrorNSURLError = 2                            //NSURL的相关错误
};


@protocol AFDownloadSessionManagerDelegate;

@interface AFDownloadSessionManager : NSObject

///代理必须设置
@property (nonatomic, weak) id <AFDownloadSessionManagerDelegate>delegate;


///支持后台下载的单例
+ (AFDownloadSessionManager *)backgrondManager;


///不支持后台下载的单例，即前台下载
+ (AFDownloadSessionManager *)standardManager;


/**
 * @brief 开始下载
 * @param downloadUrl 下载的地址
 * @param relativeSandboxLocalPath 文件下载完成后，存储在沙盒根目录的“相对路径”。如 “/Library/Preferences/download/1.zip”
 * @return 返回 AFDownloadBaseObj
 */
- (AFDownloadBaseObj *)startDownloadTaskWithDownloadUrl:(NSString *)downloadUrl relativeSandboxLocalPath:(NSString *)relativeSandboxLocalPath;


/**
 * @brief 暂停下载
 * @param identifier 请传入合法的AFDownloadBaseObj的identifier
 */
- (void)pauseDownloadTaskWithIdentifier:(NSString *)identifier;


/**
 * @brief 继续下载
 * @param identifier 请传入合法的AFDownloadBaseObj的identifier
 */
- (BOOL)resumeDownloadTaskWithIdentifier:(NSString *)identifier;


/**
 * @brief 取消下载
 * @param identifier 请传入合法的AFDownloadBaseObj的identifier
 */
- (void)cancelDownloadTaskWithIdentifier:(NSString *)identifier;

/**
 * @brief 判断某个任务是否正在下载，开发者如果想判断某个任务是否已下载完成，可以再返回NO的前提下，判断“下载完成后的本地存储地址”是否有文件存在
 * @param identifier 请传入合法的AFDownloadBaseObj的identifier
 * @return 已经下载完成的，返回NO; 正在下载的，返回YES
 */
- (BOOL)taskWithIdentifierIsDownloading:(NSString *)identifier;


@end



@protocol AFDownloadSessionManagerDelegate <NSObject>

@optional


/**
 * @brief 下载完成，即成功和失败都会调用此函数
 * @param sessionManager 下载管理类
 * @param obj 下载任务的obj，参考 AFDownloadBaseObj
 * @param error 为nil代表下载成功; 不为nil代表下载失败，参考 AFDownloadSessionErrorCode
 */
- (void)sessionManager:(AFDownloadSessionManager *)sessionManager taskDidDownloadComplete:(AFDownloadBaseObj *)obj error:(NSError *)error;


/**
 * @brief 暂停完成，即成功和失败都会调用此函数
 * @param sessionManager 下载管理类
 * @param identifier 任务的唯一标示
 * @param error 为nil代表暂停成功; 不为nil代表暂停失败，参考 AFDownloadSessionErrorCode
 */
- (void)sessionManager:(AFDownloadSessionManager *)sessionManager taskDidPauseComplete:(NSString *)identifier error:(NSError *)error;


/**
 * @brief 取消完成，即成功和失败都会调用此函数
 * @param sessionManager 下载管理类
 * @param identifier 任务的唯一标示
 * @param error 为nil代表取消成功; 不为nil代表取消失败，参考 AFDownloadSessionErrorCode
 */
- (void)sessionManager:(AFDownloadSessionManager *)sessionManager taskDidCancelComplete:(NSString *)identifier error:(NSError *)error;


/**
 * @brief 文件已被下载的长度(百分比)更新会调用此回调
 * @param sessionManager 下载管理类
 * @param obj 下载任务的obj，参考 AFDownloadBaseObj
 */
- (void)sessionManager:(AFDownloadSessionManager *)sessionManager taskDidWriteData:(AFDownloadBaseObj *)obj;


@end

/*
  已知bug：
  1. 如果用户同时添加多个任务，虽然任务都已经添加进入队列，但还没来得及本地化就Crash了，那么如果是前台下载，就会丢失没有本地化的任务，如果是后台下载，虽然会继续下载，但二次启动后，不应该通知给谁，也是任务丢失。
  2. 下载的过程中，AFDownloadSessionManager 通过delegate给开发者发通知，开发者在这些回调函数中处理的时候Crash了，内部还没来得及将数据归位和本地化，下次启动后，可能会出现已经成功的任务，重新开始下载。
  总之，开发者在使用的过程中，不能Crash。
 */


/*
 * !!!!! 不能点击Xcode的停止按钮来测试，因为用户不可能这样做，用户最多只是主动划掉App。如果点击“停止”会出现很多不可预料的bug,所以我们做测试要模仿用户操作。
 */


/*
 * 如果选择了前台下载，但是添加了很多任务，然后进入后台，下载会立即被系统自动停掉
 * 如果在1到2分钟，立刻又回到了前台，那么下载会自动继续，接着上次的百分比往下走
 * 如果时间一长，App切换到挂起状态了，下载就会失败，等到回到前台，会一并全部通知失败（一般会报 The request timed out）
 * 所以，如果选择前台下载，进入后台时，建议暂停掉所有正在下载的任务
 *
 */


/*
 * 如果选择了后台下载，并进行50个任务的后台下载：
 *
 * === 情况1：下载过程中，App只是进入了后台（挂起、非挂起不影响），没有被用户主动划掉杀死，50个任务全部下载完后。（或者点击XCode的停止按钮来杀死App也会是如下情况） ===
 * 1. 会先调用1次：-application:handleEventsForBackgroundURLSession:completionHandler:
 * 2. App没有主动被用户杀死的，直接走3，4。如果是“点击XCode的停止按钮来杀死App”的情况，init session后才会走3，4
 * 3. 调用50次 session 的 setDownloadTaskDidFinishDownloadingBlock 和 setTaskDidCompleteBlock
 * 4. 调用1次 session 的 setDidFinishEventsForBackgroundURLSessionBlock
 * 注意：如果本来要通知50次的setDownloadTaskDidFinishDownloadingBlock，但在第4次，不管是由于 AFDownloadSessionManager自身或者外界的delegate没处理好，导致Crash，都不会调用步骤4
 *      而且.tmp文件不会被移动到指定位置，剩余46次的通知也不会被调用，数据和文件都烂在硬盘和内存里，用户也无从得知这些任务的情况，总之是一个非常糟糕的情况，本来已经全部完成的任务，却要全部重新来。
 *      所以，，不能有Crash，,所以我们在AFDownloadSessionManager内部对第二次启动时的任务汇报后的调用delegate做了延迟，让任务汇报先全部汇报完，文件也移动到指定位置，数组中的数据也都归位，再调用delegate
 *      所以，只要AFDownloadSessionManager本身不Crash，外界Crash了，AFDownloadSessionManager也能保证数据的完整性。
 *
 * === 情况2：下载过程中，App Crash了（不是被用户划掉杀死）===
 * 1. 系统会帮我们继续下载，等我们二次启动后，会根据实际的下载完成情况，进行汇报
 * 2. 下载完成几个就调用几次，setDownloadTaskDidFinishDownloadingBlock 和 setTaskDidCompleteBlock，剩余的继续下载
 * 3. 即使全部下载完成，也不会调用 -application:handleEventsForBackgroundURLSession:completionHandler:
 *
 * === 情况3：下载过程中，App被用户主动划掉杀死 ===
 * 1. 还未完成的下载任务会全部被暂停掉，不会继续下载。重新启动 init session后，会收到对应的通知：
 * 2. 已完成的，会调用 setDownloadTaskDidFinishDownloadingBlock 和 setTaskDidCompleteBlock
 * 3. 未完成的，只会调用 setTaskDidCompleteBlock，并且返回 error.code = -999（取消）
 * 4. AFDownloadSessionManager 根据以上规则，会让重新启动后，继续下载，该断点续传的会续传，无缝衔接。
 * 注意：基于情况3，开发者应该建议用户，如果有下载任务，就不要把App划掉杀死，App即使是挂起也会继续下载的
 *
 * === 情况4：50个任务没有全部下载完成，只完成了20个（期间App没有被划掉，而是直接从后台进入前台） ===
 * 1. 一进入前台，直接调用20次 session 的 setDownloadTaskDidFinishDownloadingBlock 和 setTaskDidCompleteBlock，不会调用百分比
 * 2. 继续剩余的下载
 *
 *
 * 总之：一个 session 被添加了后台任务：
 * 1. 如果该 session 一直没有被释放，可以正常的继续添加下载任务，task.taskIdentifier会自增，且唯一。那么收到的回调就可以一一确认是哪些下载任务，所以是单例。
 * 2. 如果该 session 已经被有效释放掉（App被杀死），但有正在进行下载的后台任务
 *    那么App重启 session init 后，之前的task.taskIdentifier会被保留，并进行通知，所以能唯一确认任务
 *    并且接下去新增的任务的taskIdentifier也还是会接着上次App的往下自增，不会从头开始
 *    只有所有下载的任务都完成了，App重启后 task.taskIdentifier 才会从头开始。
 *
 */


/*
 
 如果你的应用程序没有在运行，iOS在后台自动重启你的应用程序然后在应用程序的UIApplicationDelegate对象上调用application:handleEventsForBackgroundURLSession:completionHandler:方法。
 这个方法提供了导致你应用程序重启的会话的identifier。你的应用程序应该存储完成处理句柄，使用这个相同的identifier创建一个后台配置对象，然后使用这个后台配置对象创建一个会话。新的会话会自动与后台活动的关联。
 之后，当会话完成了最后一个后台下载任务，它会给会话的代理发送一个URLSessionDidFinishEventsForBackgroundURLSession:消息。你的会话代理应该在主线程调用之前存储的完成句柄，以便让系统知道可以再次安全的挂起你的应用
 
 */
