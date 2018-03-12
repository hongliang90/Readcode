//
//  ViewController.m
//  AFNDemo
//
//  Created by changhongliang on 2018/2/23.
//  Copyright © 2018年 richinfo. All rights reserved.
//

#import "ViewController.h"
#import <AFNetworking.h>
#import "AFNetworkActivityIndicatorManager.h"
#import <UIKit+AFNetworking.h>
#import <objc/runtime.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <AFNetworkReachabilityManager.h>
//#import <CoreServices/CoreServices.h>


@interface ViewController ()
@property (nonatomic, strong, nullable) dispatch_queue_t completionQueue;
@property (nonatomic,weak) UIImageView *imageview;
@end

@implementation ViewController

//AFN源码阅读文章: http://www.cnblogs.com/machao/p/5768253.html
//AFN源码阅读: https://www.jianshu.com/p/856f0e26279d

//FOUNDATION_EXPORT NSArray * AFQueryDic;

- (void)viewDidLoad {
    [super viewDidLoad];
    UIImageView *imageview = [[UIImageView alloc]initWithFrame:CGRectMake(100, 100, 200, 200)];
    self.imageview = imageview;
    imageview.backgroundColor = [UIColor grayColor];
    [self.view addSubview:imageview];
    /*NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcT2RMujRpUbfX4bT74w9Ns4M8cu8J6BeEHqkoCylCjjvbFvDAH9LQ"]];
    [imageview setImageWithURLRequest: request placeholderImage:nil success:nil failure:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, NSError * _Nonnull error) {
        if (error) {
            NSLog(@"error:%@",error);
        }
    }];*/
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(netStateChange:) name:AFNetworkingReachabilityDidChangeNotification object:nil];
    [[AFNetworkReachabilityManager sharedManager]startMonitoring];


}

- (void)netStateChange:(id)notification{
    NSLog(@"%@",notification);
}

- (void)dealloc{
    [[NSNotificationCenter defaultCenter]removeObserver:self name:AFNetworkingReachabilityDidChangeNotification object:nil];
}

-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
//    NSString *URLString = @"http://httpstat.us/200";
    
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
//    AFURLSessionManager *manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];
//    NSURL *URL = [NSURL URLWithString:@"http://httpbin.org/get"];
//    NSURLRequest *request = [NSURLRequest requestWithURL:URL];
//    NSURLSessionDataTask *dataTask = [manager dataTaskWithRequest:request completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
//        if (error) {
//            NSLog(@"Error: %@", error);
//        } else {
//            NSLog(@"%@ %@", response, responseObject);
//        }
//    }];
//    [dataTask resume];
//    [dataTask suspend];
//    [dataTask resume];
//    [[AFHTTPRequestSerializer serializer] requestWithMethod:@"GET" URLString:URLString parameters:nil error:nil];
    
    //runtime 源码
    //https://www.jianshu.com/p/2e198f56352e
    AFHTTPSessionManager *manager = [[AFHTTPSessionManager alloc]init];
    AFHTTPRequestSerializer *requestSerializer = [AFHTTPRequestSerializer serializer];
//    requestSerializer.HTTPRequestHeaders
//    requestSerializer
    requestSerializer.timeoutInterval = 2;
    manager.requestSerializer = requestSerializer;
    AFSecurityPolicy *policy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeCertificate];
    manager.securityPolicy = policy;
//    policy.SSLPinningMode = AFSSLPinningModePublicKey;
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSDictionary *dic = @{
                          @"name" : @"bang",
                          @"phone": @{@"mobile": @"xx", @"home": @"xx"},
                          @"families": @[@"father", @"mother"],
                          @"nums": [NSSet setWithObjects:@"1", @"2", nil]
                          };
    //https://www.baidu.com
    //http://httpbin.org/get
    [[AFNetworkActivityIndicatorManager sharedManager] setEnabled:YES];
    [manager GET:@"https://www.baidu.com" parameters:dic progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSLog(@"%@",responseObject);
        
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        
    }];
    
    
}
 
 
/*- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcT2RMujRpUbfX4bT74w9Ns4M8cu8J6BeEHqkoCylCjjvbFvDAH9LQ"]];
    [self.imageview setImageWithURLRequest: request placeholderImage:nil success:nil failure:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, NSError * _Nonnull error) {
        if (error) {
            NSLog(@"error:%@",error);
        }
    }];
        NSLog(@"path:%@",[NSBundle mainBundle].bundlePath);NSLog(@"This objcet is %p", objc_getClass((__bridge void *)[NSString class]));
    Class class = objc_getClass("NSString");
}*/


/*-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    NSURL *url = [NSURL URLWithString:@"https://baidu.com/fg"];
    //如果正常,url却不是用这个以"/"结尾的,那么我们应该在
    if ([[url path] length] > 0 && ![[url absoluteString] hasSuffix:@"/"]) {
        url = [url URLByAppendingPathComponent:@""];
    }
    NSLog(@"url:%@",url);
}*/

/*-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
  NSString *userAgent = [NSString stringWithFormat:@"%@/%@ (%@; iOS %@; Scale/%0.2f)", [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleExecutableKey] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleIdentifierKey], [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleVersionKey], [[UIDevice currentDevice] model], [[UIDevice currentDevice] systemVersion], [[UIScreen mainScreen] scale]];
    NSLog(@"useragent:%@",userAgent);
}
 */



@end

@interface dog : NSObject

@end



@implementation dog
//
//-(void)Test{
//    AFQueryDic = [NSMutableArray array];
//}

@end
