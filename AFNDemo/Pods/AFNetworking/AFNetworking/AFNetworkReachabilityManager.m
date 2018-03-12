// AFNetworkReachabilityManager.m
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

#import "AFNetworkReachabilityManager.h"
#if !TARGET_OS_WATCH

#import <netinet/in.h>
#import <netinet6/in6.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>

NSString * const AFNetworkingReachabilityDidChangeNotification = @"com.alamofire.networking.reachability.change";
NSString * const AFNetworkingReachabilityNotificationStatusItem = @"AFNetworkingReachabilityNotificationStatusItem";

typedef void (^AFNetworkReachabilityStatusBlock)(AFNetworkReachabilityStatus status);

NSString * AFStringFromNetworkReachabilityStatus(AFNetworkReachabilityStatus status) {
    switch (status) {
        case AFNetworkReachabilityStatusNotReachable:
            return NSLocalizedStringFromTable(@"Not Reachable", @"AFNetworking", nil);
        case AFNetworkReachabilityStatusReachableViaWWAN:
            return NSLocalizedStringFromTable(@"Reachable via WWAN", @"AFNetworking", nil);
        case AFNetworkReachabilityStatusReachableViaWiFi:
            return NSLocalizedStringFromTable(@"Reachable via WiFi", @"AFNetworking", nil);
        case AFNetworkReachabilityStatusUnknown:
        default:
            return NSLocalizedStringFromTable(@"Unknown", @"AFNetworking", nil);
    }
}

static AFNetworkReachabilityStatus AFNetworkReachabilityStatusForFlags(SCNetworkReachabilityFlags flags) {
    BOOL isReachable = ((flags & kSCNetworkReachabilityFlagsReachable) != 0);
    BOOL needsConnection = ((flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0);
    BOOL canConnectionAutomatically = (((flags & kSCNetworkReachabilityFlagsConnectionOnDemand ) != 0) || ((flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0));
    BOOL canConnectWithoutUserInteraction = (canConnectionAutomatically && (flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0);
    BOOL isNetworkReachable = (isReachable && (!needsConnection || canConnectWithoutUserInteraction));

    AFNetworkReachabilityStatus status = AFNetworkReachabilityStatusUnknown;
    if (isNetworkReachable == NO) {
        status = AFNetworkReachabilityStatusNotReachable;
    }
#if	TARGET_OS_IPHONE
    else if ((flags & kSCNetworkReachabilityFlagsIsWWAN) != 0) {
        status = AFNetworkReachabilityStatusReachableViaWWAN;
    }
#endif
    else {
        status = AFNetworkReachabilityStatusReachableViaWiFi;
    }

    return status;
}

/**
 * Queue a status change notification for the main thread.
 *
 * This is done to ensure that the notifications are received in the same order
 * as they are sent. If notifications are sent directly, it is possible that
 * a queued notification (for an earlier status condition) is processed after
 * the later update, resulting in the listener being left in the wrong state.
 */
static void AFPostReachabilityStatusChange(SCNetworkReachabilityFlags flags, AFNetworkReachabilityStatusBlock block) {
    AFNetworkReachabilityStatus status = AFNetworkReachabilityStatusForFlags(flags);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (block) {
            block(status);
        }
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        NSDictionary *userInfo = @{ AFNetworkingReachabilityNotificationStatusItem: @(status) };
        [notificationCenter postNotificationName:AFNetworkingReachabilityDidChangeNotification object:nil userInfo:userInfo];
    });
}

static void AFNetworkReachabilityCallback(SCNetworkReachabilityRef __unused target, SCNetworkReachabilityFlags flags, void *info) {
    AFPostReachabilityStatusChange(flags, (__bridge AFNetworkReachabilityStatusBlock)info);
}


static const void * AFNetworkReachabilityRetainCallback(const void *info) {
    return Block_copy(info);
}

static void AFNetworkReachabilityReleaseCallback(const void *info) {
    if (info) {
        Block_release(info);
    }
}

@interface AFNetworkReachabilityManager ()
@property (readonly, nonatomic, assign) SCNetworkReachabilityRef networkReachability;
@property (readwrite, nonatomic, assign) AFNetworkReachabilityStatus networkReachabilityStatus;
@property (readwrite, nonatomic, copy) AFNetworkReachabilityStatusBlock networkReachabilityStatusBlock;
@end
//这个类的解析注释
//https://www.jianshu.com/p/727f08bb9878
@implementation AFNetworkReachabilityManager

+ (instancetype)sharedManager {
    static AFNetworkReachabilityManager *_sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedManager = [self manager];
    });

    return _sharedManager;
}

+ (instancetype)managerForDomain:(NSString *)domain {
    //根据传入的域名创建网络连接引用
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, [domain UTF8String]);
    AFNetworkReachabilityManager *manager = [[self alloc] initWithReachability:reachability];
    //手动管理内存
    CFRelease(reachability);

    return manager;
}


+ (instancetype)managerForAddress:(const void *)address {
    //根据传入的地址创建网络连接引用
    //返回的网络连接引用必须在用完后释放。
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)address);
    AFNetworkReachabilityManager *manager = [[self alloc] initWithReachability:reachability];
    //手动管理内存
    CFRelease(reachability);
    
    return manager;
}

+ (instancetype)manager
{
//    使用这个类方法创建一个默认socket地址的AFNetworkReachabilityManager对象。
//    ipv6是iOS9和OSX10.11后推出的，因此这里要进行系统版本的判断。
    /*
     truct sockaddr_in {
     __uint8_t    sin_len;
     sa_family_t    sin_family; //协议族，在socket编程中只能是AF_INET
     in_port_t    sin_port;     //端口号（使用网络字节顺序）
     struct in_addr  sin_addr;  //按照网络字节顺序存储IP地址，使用in_addr这个数据结构
     char        sin_zero[8];   //让sockaddr与sockaddr_in两个数据结构保持大小相同而保留的空字节。
     //sockaddr_in和sockaddr是并列的结构，指向sockaddr_in的结构体的指针也可以指向sockaddr的结构体，并代替它。
     //也就是说，你可以使用sockaddr_in建立你所需要的信息,然后用进行类型转换就可以了
     };
     
     struct in_addr {
     in_addr_t s_addr;
     };
     结构体in_addr 用来表示一个32位的IPv4地址。in_addr_t 是一个32位的unsigned long，其中每8位代表一个IP地址位中的一个数值。
     　　例如192.168.3.144记为0xc0a80390
     */
#if (defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED >= 90000) || (defined(__MAC_OS_X_VERSION_MIN_REQUIRED) && __MAC_OS_X_VERSION_MIN_REQUIRED >= 101100)
    struct sockaddr_in6 address;
    bzero(&address, sizeof(address));
    address.sin6_len = sizeof(address);
    address.sin6_family = AF_INET6;
#else
    struct sockaddr_in address;
    bzero(&address, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
#endif
    return [self managerForAddress:&address];
}

- (instancetype)initWithReachability:(SCNetworkReachabilityRef)reachability {
    self = [super init];
    if (!self) {
        return nil;
    }
  /*
   让_networkReachability持有 SCNetworkReachabilityRef的引用，并设置一个默认的网络状态。
   为什么要retain这个SCNetworkReachabilityRef引用？个人理解：谁创建谁释放，这个参数reachability在+managerForDomain:和+managerForAddress:方法中创建也应由它们释放。为了防止-initWithReachability:方法还没执行完，这个引用就已经在+managerForDomain:或+managerForAddress:释放掉了，因此要在本方法中先把它retain一次。
   */
    _networkReachability = CFRetain(reachability);
    self.networkReachabilityStatus = AFNetworkReachabilityStatusUnknown;

    return self;
}

//这个方法被直接禁用了,主要是使用NS_UNAVAILABLE宏
- (instancetype)init NS_UNAVAILABLE
{
    return nil;
}

- (void)dealloc {
    [self stopMonitoring];
    
    if (_networkReachability != NULL) {
        CFRelease(_networkReachability);
    }
}

#pragma mark -

- (BOOL)isReachable {
    return [self isReachableViaWWAN] || [self isReachableViaWiFi];
}

- (BOOL)isReachableViaWWAN {
    return self.networkReachabilityStatus == AFNetworkReachabilityStatusReachableViaWWAN;
}

- (BOOL)isReachableViaWiFi {
    return self.networkReachabilityStatus == AFNetworkReachabilityStatusReachableViaWiFi;
}

#pragma mark -

- (void)startMonitoring {
    //先关闭监听
    [self stopMonitoring];
    //如果网络不可达，就返回
    if (!self.networkReachability) {
        return;
    }
//避免循环引用要用weakself，避免在block执行过程中，突然出现self被释放的情况，就用strongself
    __weak __typeof(self)weakSelf = self;
      //1.网络状态变化时回调的是这个block
    AFNetworkReachabilityStatusBlock callback = ^(AFNetworkReachabilityStatus status) {
        __strong __typeof(weakSelf)strongSelf = weakSelf;

        strongSelf.networkReachabilityStatus = status;
        //2.其中回调block中会执行_networkReachabilityStatusBlock，这个block才是核心，由-setReachabilityStatusChangeBlock:方法对这个block进行设置

        if (strongSelf.networkReachabilityStatusBlock) {
            strongSelf.networkReachabilityStatusBlock(status);
        }

    };
    ///*SCNetworkReachability 编程接口支持同步和异步两种模式。
    //关于 SCNetworkReachabilityContext结构体
    /*
     typedef struct {
     CFIndex        version;   作为参数传递到SCDynamicStore创建函数的结构类型的版本号，这个结构体对应的是version 0。
     void *        __nullable info; 表示网络状态处理的回调函数。指向用户指定的数据块的C指针，void* 相当于oc的id
     const void    * __nonnull (* __nullable retain)(const void *info); retain info
     void        (* __nullable release)(const void *info); 对应上一个元素 release
     CFStringRef    __nonnull (* __nullable copyDescription)(const void *info); 提供信息字段的描述
     } SCNetworkReachabilityContext;
     
     */
    /*
     CFIndex version：创建一个 SCNetworkReachabilityContext 结构体时，需要调用 SCDynamicStore的创建函数，SCNetworkReachabilityContext 对应的 version 是 0
     
     void *__nullable info：表示网络状态处理的回调函数。指向用户指定的数据块的C指针，void* 相当于oc的id。
     要携带的这个info就是下面这个block，是一个在每次网络状态改变时的回调。而且block和void*的转换不能直接转，要使用__bridge。
     */
    SCNetworkReachabilityContext context = {0, (__bridge void *)callback, AFNetworkReachabilityRetainCallback, AFNetworkReachabilityReleaseCallback, NULL};
    //设置回调。SCNetworkReachabilitySetCallback指定一个target(第一个参数)，当设备对于这个target链接状态发生改变时，就进行回调（第二个参数）。它第二个参数：SCNetworkReachabilityCallBack类型的值，是当网络可达性更改时调用的函数，如果为NULL，则目标的当前客户端将被删除。SCNetworkReachabilityCallBack中的info参数就是SCNetworkReachabilityContext中对应的那个info
    SCNetworkReachabilitySetCallback(self.networkReachability, AFNetworkReachabilityCallback, &context);
    //加入runloop
    SCNetworkReachabilityScheduleWithRunLoop(self.networkReachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    //异步线程发送一次当前网络状态（通知）
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        //SCNetworkReachabilityGetFlags获得可达性状态
        SCNetworkReachabilityFlags flags;
        if (SCNetworkReachabilityGetFlags(self.networkReachability, &flags)) {
            AFPostReachabilityStatusChange(flags, callback);
        }
    });
    /*SCNetworkReachability 编程接口支持同步和异步两种模式。
     在同步模式中，可以通过调用SCNetworkReachabilityGetFlag函数来获得可达性状态；
     在异步模式中，可以调度SCNetworkReachabilxity对象到客户端对象线程的运行循环上，客户端实现一个回调函数来接收通知，当远程主机改变可达性状态，回调则可响应。
     */
}

- (void)stopMonitoring {
    if (!self.networkReachability) {
        return;
    }

    SCNetworkReachabilityUnscheduleFromRunLoop(self.networkReachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);
}

#pragma mark -

- (NSString *)localizedNetworkReachabilityStatusString {
    return AFStringFromNetworkReachabilityStatus(self.networkReachabilityStatus);
}

#pragma mark -

- (void)setReachabilityStatusChangeBlock:(void (^)(AFNetworkReachabilityStatus status))block {
    self.networkReachabilityStatusBlock = block;
}

#pragma mark - NSKeyValueObserving

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key {
    if ([key isEqualToString:@"reachable"] || [key isEqualToString:@"reachableViaWWAN"] || [key isEqualToString:@"reachableViaWiFi"]) {
        return [NSSet setWithObject:@"networkReachabilityStatus"];
    }

    return [super keyPathsForValuesAffectingValueForKey:key];
}

@end
#endif
