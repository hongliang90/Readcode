// AFImageDownloader.m
// Copyright (c) 2011–2016 Alamofire Software Foundation ( http://alamofire.org/ )
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <TargetConditionals.h>

#if TARGET_OS_IOS || TARGET_OS_TV

#import "AFImageDownloader.h"
#import "AFHTTPSessionManager.h"
//存放成功和失败的block
@interface AFImageDownloaderResponseHandler : NSObject
@property (nonatomic, strong) NSUUID *uuid;
@property (nonatomic, copy) void (^successBlock)(NSURLRequest*, NSHTTPURLResponse*, UIImage*);
@property (nonatomic, copy) void (^failureBlock)(NSURLRequest*, NSHTTPURLResponse*, NSError*);
@end

@implementation AFImageDownloaderResponseHandler
//当这个task完成的时候，会调用我们添加的回调。
//初始化回调对象
- (instancetype)initWithUUID:(NSUUID *)uuid
                     success:(nullable void (^)(NSURLRequest *request, NSHTTPURLResponse * _Nullable response, UIImage *responseObject))success
                     failure:(nullable void (^)(NSURLRequest *request, NSHTTPURLResponse * _Nullable response, NSError *error))failure {
    if (self = [self init]) {
        self.uuid = uuid;
        self.successBlock = success;
        self.failureBlock = failure;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat: @"<AFImageDownloaderResponseHandler>UUID: %@", [self.uuid UUIDString]];
}

@end

//3. 关于```AFImageDownloaderMergedTask```，我们在这里都用的是这种类型的task，其实这个task也很简单：
//就是当前下载任务的task
@interface AFImageDownloaderMergedTask : NSObject
@property (nonatomic, strong) NSString *URLIdentifier;
@property (nonatomic, strong) NSUUID *identifier;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, strong) NSMutableArray <AFImageDownloaderResponseHandler*> *responseHandlers;

@end

@implementation AFImageDownloaderMergedTask

- (instancetype)initWithURLIdentifier:(NSString *)URLIdentifier identifier:(NSUUID *)identifier task:(NSURLSessionDataTask *)task {
    if (self = [self init]) {
        self.URLIdentifier = URLIdentifier;
        self.task = task;
        self.identifier = identifier;
        self.responseHandlers = [[NSMutableArray alloc] init];
    }
    return self;
}
//添加任务完成回调
- (void)addResponseHandler:(AFImageDownloaderResponseHandler*)handler {
    [self.responseHandlers addObject:handler];
}
//移除任务完成回调
- (void)removeResponseHandler:(AFImageDownloaderResponseHandler*)handler {
    [self.responseHandlers removeObject:handler];
}
/*
 其实就是除了```NSURLSessionDataTask```，多加了几个参数，```URLIdentifier```和```identifier```都是用来标识这个task的，responseHandlers是用来存储task完成后的回调的，里面可以存一组，当任务完成时候，里面的回调都会被调用。
 4. 接着去根据缓存策略，去加载缓存，如果有缓存，从```self.imageCache```中返回缓存，否则继续往下走。
 5. 走到这说明没相同url的task，也没有cache，那么就开始一个新的task，调用的是```AFUrlSessionManager```里的请求方法生成了一个task（这里我们就不赘述了，可以看之前的楼主之前的文章）。然后做了请求完成的处理。注意，这里处理实在我们一开始初始化的并行queue:```self.responseQueue```中的，这里的响应处理是多线程并发进行的。
 1）完成，则调用如下方法把这个task从全局字典中移除
 
 */

@end

@implementation AFImageDownloadReceipt

- (instancetype)initWithReceiptID:(NSUUID *)receiptID task:(NSURLSessionDataTask *)task {
    if (self = [self init]) {
        self.receiptID = receiptID;
        self.task = task;
    }
    return self;
}

@end

@interface AFImageDownloader ()

@property (nonatomic, strong) dispatch_queue_t synchronizationQueue;
@property (nonatomic, strong) dispatch_queue_t responseQueue;

@property (nonatomic, assign) NSInteger maximumActiveDownloads;
@property (nonatomic, assign) NSInteger activeRequestCount;

@property (nonatomic, strong) NSMutableArray *queuedMergedTasks;
//所有的符合task
@property (nonatomic, strong) NSMutableDictionary *mergedTasks;

@end


@implementation AFImageDownloader
//设置一个系统缓存，内存缓存为20M，磁盘缓存为150M
+ (NSURLCache *)defaultURLCache {
    return [[NSURLCache alloc] initWithMemoryCapacity:20 * 1024 * 1024
                                         diskCapacity:150 * 1024 * 1024
                                             diskPath:@"com.alamofire.imagedownloader"];
}

+ (NSURLSessionConfiguration *)defaultURLSessionConfiguration {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];

    //TODO set the default HTTP headers

    configuration.HTTPShouldSetCookies = YES;
    configuration.HTTPShouldUsePipelining = NO;
     // http://nshipster.cn/nsurlcache/
     //https://www.jianshu.com/p/aa49bb3555f4
    configuration.requestCachePolicy = NSURLRequestUseProtocolCachePolicy;
    configuration.allowsCellularAccess = YES;
    configuration.timeoutIntervalForRequest = 60.0;
    configuration.URLCache = [AFImageDownloader defaultURLCache];

    return configuration;
}

- (instancetype)init {
    NSURLSessionConfiguration *defaultConfiguration = [self.class defaultURLSessionConfiguration];
    AFHTTPSessionManager *sessionManager = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:defaultConfiguration];
    sessionManager.responseSerializer = [AFImageResponseSerializer serializer];

    return [self initWithSessionManager:sessionManager
                 downloadPrioritization:AFImageDownloadPrioritizationFIFO
                 maximumActiveDownloads:4
                             imageCache:[[AFAutoPurgingImageCache alloc] init]];
}
/*
这边初始化了一些属性，这些属性跟着注释看应该很容易明白其作用。主要需要注意的就是，这里创建了两个queue：**一个串行的请求queue，和一个并行的响应queue。**
- 这个串行queue,是用来做内部生成task等等一系列业务逻辑的。它保证了我们在这些逻辑处理中的线程安全问题（迷惑的接着往下看）。
- 这个并行queue，被用来做网络请求完成的数据回调。
 */
- (instancetype)initWithSessionManager:(AFHTTPSessionManager *)sessionManager
                downloadPrioritization:(AFImageDownloadPrioritization)downloadPrioritization
                maximumActiveDownloads:(NSInteger)maximumActiveDownloads
                            imageCache:(id <AFImageRequestCache>)imageCache {
    if (self = [super init]) {
        self.sessionManager = sessionManager;

        self.downloadPrioritizaton = downloadPrioritization;
        self.maximumActiveDownloads = maximumActiveDownloads;
        //自动清理
        self.imageCache = imageCache;
        //队列合并任务
        self.queuedMergedTasks = [[NSMutableArray alloc] init];
        //合并task
        self.mergedTasks = [[NSMutableDictionary alloc] init];
        //活跃请求数
        self.activeRequestCount = 0;

        NSString *name = [NSString stringWithFormat:@"com.alamofire.imagedownloader.synchronizationqueue-%@", [[NSUUID UUID] UUIDString]];
        //同步队列
        self.synchronizationQueue = dispatch_queue_create([name cStringUsingEncoding:NSASCIIStringEncoding], DISPATCH_QUEUE_SERIAL);

        name = [NSString stringWithFormat:@"com.alamofire.imagedownloader.responsequeue-%@", [[NSUUID UUID] UUIDString]];
        //响应队列
        self.responseQueue = dispatch_queue_create([name cStringUsingEncoding:NSASCIIStringEncoding], DISPATCH_QUEUE_CONCURRENT);
    }

    return self;
}

+ (instancetype)defaultInstance {
    static AFImageDownloader *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (nullable AFImageDownloadReceipt *)downloadImageForURLRequest:(NSURLRequest *)request
                                                        success:(void (^)(NSURLRequest * _Nonnull, NSHTTPURLResponse * _Nullable, UIImage * _Nonnull))success
                                                        failure:(void (^)(NSURLRequest * _Nonnull, NSHTTPURLResponse * _Nullable, NSError * _Nonnull))failure {
    return [self downloadImageForURLRequest:request withReceiptID:[NSUUID UUID] success:success failure:failure];
}

//真正的下载方法
//就这么一个非常非常长的方法，这个方法执行的内容都是在我们之前创建的串行queue中，同步的执行的，这是因为这个方法绝大多数的操作都是需要线程安全的。可以对着源码和注释来看，我们在这讲下它做了什么：
//1. 首先做了一个url的判断，如果为空则返回失败Block。
//2. 判断这个需要请求的url，是不是已经被生成的task中，如果是的话，则多添加一个回调处理就可以。回调处理对象为```AFImageDownloaderResponseHandler```。这个类非常简单，总共就如下3个属性：

- (nullable AFImageDownloadReceipt *)downloadImageForURLRequest:(NSURLRequest *)request
                                                  withReceiptID:(nonnull NSUUID *)receiptID
                                                        success:(nullable void (^)(NSURLRequest *request, NSHTTPURLResponse  * _Nullable response, UIImage *responseObject))success
                                                        failure:(nullable void (^)(NSURLRequest *request, NSHTTPURLResponse * _Nullable response, NSError *error))failure {
    //还是类似之前的，同步串行去做下载的事 生成一个task,这些事情都是在当前线程中串行同步做的，所以不用担心线程安全问题。
    __block NSURLSessionDataTask *task = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        //请求的URL
        NSString *URLIdentifier = request.URL.absoluteString;
        if (URLIdentifier == nil) {
            if (failure) {
                //错误返回，没Url
                NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(request, nil, error);
                });
            }
            return;
        }
        //如果这个任务已经存在，则添加成功失败Block,然后直接返回，即一个url用一个request,可以响应好几个block
        //从自己task字典中根据Url去取AFImageDownloaderMergedTask，里面有task id url等等信息
        // 1) Append the success and failure blocks to a pre-existing request if it already exists
        AFImageDownloaderMergedTask *existingMergedTask = self.mergedTasks[URLIdentifier];
        if (existingMergedTask != nil) {
            //里面包含成功和失败Block和UUid
            AFImageDownloaderResponseHandler *handler = [[AFImageDownloaderResponseHandler alloc] initWithUUID:receiptID success:success failure:failure];
             //添加handler
            [existingMergedTask addResponseHandler:handler];
            //给task赋值
            task = existingMergedTask.task;
            return;
        }

        // 2) Attempt to load the image from the image cache if the cache policy allows it
        //根据request的缓存策略，加载缓存
        switch (request.cachePolicy) {
            //这3种情况都会去加载缓存
            case NSURLRequestUseProtocolCachePolicy:
            case NSURLRequestReturnCacheDataElseLoad:
            case NSURLRequestReturnCacheDataDontLoad: {
                //从cache中根据request拿数据
                UIImage *cachedImage = [self.imageCache imageforRequest:request withAdditionalIdentifier:nil];
                if (cachedImage != nil) {
                    if (success) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            success(request, nil, cachedImage);
                        });
                    }
                    return;
                }
                break;
            }
            default:
                break;
        }

        // 3) Create the request and set up authentication, validation and response serialization
        //走到这说明即没有请求中的request,也没有cache,开始请求
        NSUUID *mergedTaskIdentifier = [NSUUID UUID];
         //task
        NSURLSessionDataTask *createdTask;
        __weak __typeof__(self) weakSelf = self;
        //用sessionManager的去请求，注意，只是创建task,还是挂起状态
        createdTask = [self.sessionManager
                       dataTaskWithRequest:request
                       completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
                           //在responseQueue中回调数据,初始化为并行queue
                           dispatch_async(self.responseQueue, ^{
                               __strong __typeof__(weakSelf) strongSelf = weakSelf;
                               //拿到当前的task
                               AFImageDownloaderMergedTask *mergedTask = self.mergedTasks[URLIdentifier];
                               //如果之前的task数组中，有这个请求的任务task，则从数组中移除
                               if ([mergedTask.identifier isEqual:mergedTaskIdentifier]) {
                                   //安全的移除，并返回当前被移除的AF task
                                   mergedTask = [strongSelf safelyRemoveMergedTaskWithURLIdentifier:URLIdentifier];
                                     //请求错误
                                   if (error) {
                                       //去遍历task所有响应的处理
                                       for (AFImageDownloaderResponseHandler *handler in mergedTask.responseHandlers) {
                                           if (handler.failureBlock) {
                                               //主线程，调用失败的Block
                                               dispatch_async(dispatch_get_main_queue(), ^{
                                                   handler.failureBlock(request, (NSHTTPURLResponse*)response, error);
                                               });
                                           }
                                       }
                                   } else {
                                       //成功根据request,往cache里添加
                                       [strongSelf.imageCache addImage:responseObject forRequest:request withAdditionalIdentifier:nil];
                                       //调用成功Block
                                       for (AFImageDownloaderResponseHandler *handler in mergedTask.responseHandlers) {
                                           if (handler.successBlock) {
                                               dispatch_async(dispatch_get_main_queue(), ^{
                                                   handler.successBlock(request, (NSHTTPURLResponse*)response, responseObject);
                                               });
                                           }
                                       }
                                       
                                   }
                               }
                                //减少活跃的任务数
                               [strongSelf safelyDecrementActiveTaskCount];
                               [strongSelf safelyStartNextTaskIfNecessary];
                           });
                       }];

        // 4) Store the response handler for use when the request completes
         //创建handler
        AFImageDownloaderResponseHandler *handler = [[AFImageDownloaderResponseHandler alloc] initWithUUID:receiptID
                                                                                                   success:success
                                                                                                   failure:failure];
        //创建task
        AFImageDownloaderMergedTask *mergedTask = [[AFImageDownloaderMergedTask alloc]
                                                   initWithURLIdentifier:URLIdentifier
                                                   identifier:mergedTaskIdentifier
                                                   task:createdTask];
        //添加handler
        [mergedTask addResponseHandler:handler];
        //往当前任务字典里添加任务
        self.mergedTasks[URLIdentifier] = mergedTask;

        // 5) Either start the request or enqueue it depending on the current active request count
        //如果小于，则开始任务下载resume
        if ([self isActiveRequestCountBelowMaximumLimit]) {
            [self startMergedTask:mergedTask];
        } else {
            [self enqueueMergedTask:mergedTask];
        }
         //拿到最终生成的task
        task = mergedTask.task;
    });
    if (task) {
        //创建一个AFImageDownloadReceipt并返回，里面就多一个receiptID
        return [[AFImageDownloadReceipt alloc] initWithReceiptID:receiptID task:task];
    } else {
        return nil;
    }
}

//取消图片下载的收据
- (void)cancelTaskForImageDownloadReceipt:(AFImageDownloadReceipt *)imageDownloadReceipt {
    dispatch_sync(self.synchronizationQueue, ^{
        NSString *URLIdentifier = imageDownloadReceipt.task.originalRequest.URL.absoluteString;
        AFImageDownloaderMergedTask *mergedTask = self.mergedTasks[URLIdentifier];
        //合并的task
        //Returns the index of the first object in the array that passes a test in a given block
        //返回第一个handler.uuid == imageDownloadReceipt.receiptID相等的
        NSUInteger index = [mergedTask.responseHandlers indexOfObjectPassingTest:^BOOL(AFImageDownloaderResponseHandler * _Nonnull handler, __unused NSUInteger idx, __unused BOOL * _Nonnull stop) {
            return handler.uuid == imageDownloadReceipt.receiptID;
        }];

        if (index != NSNotFound) {
            AFImageDownloaderResponseHandler *handler = mergedTask.responseHandlers[index];
            [mergedTask removeResponseHandler:handler];
            NSString *failureReason = [NSString stringWithFormat:@"ImageDownloader cancelled URL request: %@",imageDownloadReceipt.task.originalRequest.URL.absoluteString];
            NSDictionary *userInfo = @{NSLocalizedFailureReasonErrorKey:failureReason};
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:userInfo];
            if (handler.failureBlock) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    handler.failureBlock(imageDownloadReceipt.task.originalRequest, nil, error);
                });
            }
        }
        //如何如果当前task没有返回响应的handler,且当前的状态是挂起的
        if (mergedTask.responseHandlers.count == 0 && mergedTask.task.state == NSURLSessionTaskStateSuspended) {
            [mergedTask.task cancel];
            //移除task
            [self removeMergedTaskWithURLIdentifier:URLIdentifier];
        }
    });
}

//移除task相关，用同步串行的形式，防止移除中出现重复移除一系列问题
- (AFImageDownloaderMergedTask*)safelyRemoveMergedTaskWithURLIdentifier:(NSString *)URLIdentifier {
    __block AFImageDownloaderMergedTask *mergedTask = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        mergedTask = [self removeMergedTaskWithURLIdentifier:URLIdentifier];
    });
    return mergedTask;
}

//This method should only be called from safely within the synchronizationQueue
- (AFImageDownloaderMergedTask *)removeMergedTaskWithURLIdentifier:(NSString *)URLIdentifier {
    AFImageDownloaderMergedTask *mergedTask = self.mergedTasks[URLIdentifier];
    [self.mergedTasks removeObjectForKey:URLIdentifier];
    return mergedTask;
}
//减少活跃的任务数
- (void)safelyDecrementActiveTaskCount {
    //回到串行queue去-
    dispatch_sync(self.synchronizationQueue, ^{
        if (self.activeRequestCount > 0) {
            self.activeRequestCount -= 1;
        }
    });
}

//如果可以，则开启下一个任务
- (void)safelyStartNextTaskIfNecessary {
    //回到串行queue
    dispatch_sync(self.synchronizationQueue, ^{
        //先判断并行数限制
        if ([self isActiveRequestCountBelowMaximumLimit]) {
            while (self.queuedMergedTasks.count > 0) {
                //获取数组中第一个task
                AFImageDownloaderMergedTask *mergedTask = [self dequeueMergedTask];
                //如果状态是挂起状态
                if (mergedTask.task.state == NSURLSessionTaskStateSuspended) {
                    [self startMergedTask:mergedTask];
                    break;
                }
            }
        }
    });
}

- (void)startMergedTask:(AFImageDownloaderMergedTask *)mergedTask {
    [mergedTask.task resume];
    ++self.activeRequestCount;
}

- (void)enqueueMergedTask:(AFImageDownloaderMergedTask *)mergedTask {
    switch (self.downloadPrioritizaton) {
        case AFImageDownloadPrioritizationFIFO:
            [self.queuedMergedTasks addObject:mergedTask];
            break;
        case AFImageDownloadPrioritizationLIFO:
            [self.queuedMergedTasks insertObject:mergedTask atIndex:0];
            break;
    }
}

- (AFImageDownloaderMergedTask *)dequeueMergedTask {
    AFImageDownloaderMergedTask *mergedTask = nil;
    mergedTask = [self.queuedMergedTasks firstObject];
    [self.queuedMergedTasks removeObject:mergedTask];
    return mergedTask;
}

- (BOOL)isActiveRequestCountBelowMaximumLimit {
    return self.activeRequestCount < self.maximumActiveDownloads;
}

@end

#endif
