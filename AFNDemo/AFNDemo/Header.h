//
//  Header.h
//  AFNDemo
//
//  Created by changhongliang on 2018/2/23.
//  Copyright © 2018年 richinfo. All rights reserved.
//


/*
	NSProgress.h
	Copyright (c) 2011-2016, Apple Inc.
	All rights reserved.
 */

#import <Foundation/NSObject.h>
#import <Foundation/NSDictionary.h>

@class NSDictionary, NSMutableDictionary, NSMutableSet, NSURL, NSUUID, NSXPCConnection, NSLock;

typedef NSString * NSProgressKind NS_EXTENSIBLE_STRING_ENUM;
#if FOUNDATION_SWIFT_SDK_EPOCH_AT_LEAST(8)
typedef NSString * NSProgressUserInfoKey NS_EXTENSIBLE_STRING_ENUM;
#else
typedef NSString * NSProgressKey NS_EXTENSIBLE_STRING_ENUM;
#endif
typedef NSString * NSProgressFileOperationKind NS_EXTENSIBLE_STRING_ENUM;

NS_ASSUME_NONNULL_BEGIN

/*
 NSProgress is used to report the amount of work done, and provides a way to allow the user to cancel that work.
 
 Since work is often split up into several parts, progress objects can form a tree where children represent part of the overall total work. Each parent may have as many children as required, but each child only has one parent. The top level progress object in this tree is typically the one that you would display to a user. The leaf objects are updated as work completes, and the updates propagate up the tree.
 
 The work that an NSProgress does is tracked via a "unit count." There are two unit count values: total and completed. In its leaf form, an NSProgress is created with a total unit count and its completed unit count is updated with -setCompletedUnitCount: until it matches the total unit count. The progress is then considered finished.
 
 When progress objects form nodes in trees, they are still created with a total unit count. Portions of the total are then handed out to children as a "pending unit count." The total amount handed out to children should add up to the parent's totalUnitCount. When those children become finished, the pending unit count assigned to that child is added to the parent's completedUnitCount. Therefore, when all children are finished, the parent's completedUnitCount is equal to its totalUnitCount and it becomes finished itself.
 
 Children NSProgress objects can be added implicitly or by invoking the -addChild:withPendingUnitCount: method on the parent. Implicitly added children are attached to a parent progress between a call to -becomeCurrentWithPendingUnitCount: and a call to -resignCurrent. The implicit child is created with the +progressWithTotalUnitCount: method or by passing the result of +currentProgress to the -initWithParent:userInfo: method. Both kinds of children can be attached to the same parent progress object. If you have an idea in advance that some portions of the work will take more or less time than the others, you can use different values of pending unit count for each child.
 
 If you are designing an interface of an object that reports progress, then the recommended approach is to vend an NSProgress property and adopt the NSProgressReporting protocol. The progress should be created with the -discreteProgressWithTotalUnitCount: method. You can then either update the progress object directly or set it to have children of its own. Users of your object can compose your progress into their tree by using the -addChild:withPendingUnitCount: method.
 
 If you want to provide progress reporting for a single method, then the recommended approach is to implicitly attach to a current NSProgress by creating an NSProgress object at the very beginning of your method using +progressWithTotalUnitCount:. This progress object will consume the pending unit count, and then you can set up the progress object with children of its own.
 
 The localizedDescription and localizedAdditionalDescription properties are meant to be observed as well as set. So are the cancellable and pausable properties. totalUnitCount and completedUnitCount on the other hand are often not the best properties to observe when presenting progress to the user. For example, you should observe fractionCompleted instead of observing totalUnitCount and completedUnitCount and doing your own calculation. NSProgress' default implementation of fractionCompleted does fairly sophisticated things like taking child NSProgresses into account.
 */

NS_CLASS_AVAILABLE(10_9, 7_0)
@interface NSProgress : NSObject {
@private
    NSProgress *_parent;
    int64_t _reserved4;
    id _values;
    void (^ _resumingHandler)(void);
    void (^ _cancellationHandler)(void);
    void (^ _pausingHandler)(void);
    void (^ _prioritizationHandler)(void);
    uint64_t _flags;
    id _userInfoProxy;
    NSString *_publisherID;
    id _reserved5;
    NSInteger _reserved6;
    NSInteger _reserved7;
    NSInteger _reserved8;
    NSMutableDictionary *_acknowledgementHandlersByLowercaseBundleID;
    NSMutableDictionary *_lastNotificationTimesByKey;
    NSMutableDictionary *_userInfoLastNotificationTimesByKey;
    NSLock *_lock;
    NSMutableSet *_children;
}

/* The instance of NSProgress associated with the current thread by a previous invocation of -becomeCurrentWithPendingUnitCount:, if any. The purpose of this per-thread value is to allow code that does work to usefully report progress even when it is widely separated from the code that actually presents progress to the user, without requiring layers of intervening code to pass the instance of NSProgress through. Using the result of invoking this directly will often not be the right thing to do, because the invoking code will often not even know what units of work the current progress object deals in. Invoking +progressWithTotalUnitCount: to create a child NSProgress object and then using that to report progress makes more sense in that situation.
 */
+ (nullable NSProgress *)currentProgress;

/* Return an instance of NSProgress that has been initialized with -initWithParent:userInfo:. The initializer is passed the current progress object, if there is one, and the value of the totalUnitCount property is set. In many cases you can simply precede code that does a substantial amount of work with an invocation of this method, with repeated invocations of -setCompletedUnitCount: and -isCancelled in the loop that does the work.
 
 You can invoke this method on one thread and then message the returned NSProgress on another thread. For example, you can let the result of invoking this method get captured by a block passed to dispatch_async(). In that block you can invoke methods like -becomeCurrentWithPendingUnitCount: and -resignCurrent, or -setCompletedUnitCount: and -isCancelled.
 */
+ (NSProgress *)progressWithTotalUnitCount:(int64_t)unitCount;

/* Return an instance of NSProgress that has been initialized with -initWithParent:userInfo:. The initializer is passed nil for the parent, resulting in a progress object that is not part of an existing progress tree. The value of the totalUnitCount property is also set.
 */
+ (NSProgress *)discreteProgressWithTotalUnitCount:(int64_t)unitCount NS_AVAILABLE(10_11, 9_0);

/* Return an instance of NSProgress that has been attached to a parent progress with the given pending unit count.
 */
+ (NSProgress *)progressWithTotalUnitCount:(int64_t)unitCount parent:(NSProgress *)parent pendingUnitCount:(int64_t)portionOfParentTotalUnitCount NS_AVAILABLE(10_11, 9_0);

/* The designated initializer. If a parent NSProgress object is passed then progress reporting and cancellation checking done by the receiver will notify or consult the parent. The only valid arguments to the first argument of this method are nil (indicating no parent) or [NSProgress currentProgress]. Any other value will throw an exception.
 */
- (instancetype)initWithParent:(nullable NSProgress *)parentProgressOrNil userInfo:(nullable NSDictionary *)userInfoOrNil NS_DESIGNATED_INITIALIZER;

/* Make the receiver the current thread's current progress object, returned by +currentProgress. At the same time, record how large a portion of the work represented by the receiver will be represented by the next progress object initialized by invoking -initWithParent:userInfo: in the current thread with the receiver as the parent. This will be used when that child is sent -setCompletedUnitCount: and the receiver is notified of that.
 
 With this mechanism, code that doesn't know anything about its callers can report progress accurately by using +progressWithTotalUnitCount: and -setCompletedUnitCount:. The calling code will account for the fact that the work done is only a portion of the work to be done as part of a larger operation. The unit of work in a call to -becomeCurrentWithPendingUnitCount: has to be the same unit of work as that used for the value of the totalUnitCount property, but the unit of work used by the child can be a completely different one, and often will be. You must always balance invocations of this method with invocations of -resignCurrent.
 */
- (void)becomeCurrentWithPendingUnitCount:(int64_t)unitCount;

/* Balance the most recent previous invocation of -becomeCurrentWithPendingUnitCount: on the same thread by restoring the current progress object to what it was before -becomeCurrentWithPendingUnitCount: was invoked.
 */
- (void)resignCurrent;

/* Directly add a child progress to the receiver, assigning it a portion of the receiver's total unit count.
 */
- (void)addChild:(NSProgress *)child withPendingUnitCount:(int64_t)inUnitCount NS_AVAILABLE(10_11, 9_0);

#pragma mark *** Reporting Progress ***

/* The size of the job whose progress is being reported, and how much of it has been completed so far, respectively. For an NSProgress with a kind of NSProgressKindFile, the unit of these properties is bytes while the NSProgressFileTotalCountKey and NSProgressFileCompletedCountKey keys in the userInfo dictionary are used for the overall count of files. For any other kind of NSProgress, the unit of measurement you use does not matter as long as you are consistent. The values may be reported to the user in the localizedDescription and localizedAdditionalDescription.
 
 If the receiver NSProgress object is a "leaf progress" (no children), then the fractionCompleted is generally completedUnitCount / totalUnitCount. If the receiver NSProgress has children, the fractionCompleted will reflect progress made in child objects in addition to its own completedUnitCount. As children finish, the completedUnitCount of the parent will be updated.
 */
@property int64_t totalUnitCount;
@property int64_t completedUnitCount;

/* A description of what progress is being made, fit to present to the user. NSProgress is by default KVO-compliant for this property, with the notifications always being sent on thread which updates the property. The default implementation of the getter for this property does not always return the most recently set value of the property. If the most recently set value of this property is nil then NSProgress uses the value of the kind property to determine how to use the values of other properties, as well as values in the user info dictionary, to return a computed string. If it fails to do that then it returns an empty string.
 
 For example, depending on the kind of progress, the completed and total unit counts, and other parameters, these kinds of strings may be generated:
 Copying 10 files…
 30% completed
 Copying “TextEdit”…
 */
@property (null_resettable, copy) NSString *localizedDescription;

/* A more specific description of what progress is being made, fit to present to the user. NSProgress is by default KVO-compliant for this property, with the notifications always being sent on thread which updates the property. The default implementation of the getter for this property does not always return the most recently set value of the property. If the most recently set value of this property is nil then NSProgress uses the value of the kind property to determine how to use the values of other properties, as well as values in the user info dictionary, to return a computed string. If it fails to do that then it returns an empty string. The difference between this and localizedDescription is that this text is meant to be more specific about what work is being done at any particular moment.
 
 For example, depending on the kind of progress, the completed and total unit counts, and other parameters, these kinds of strings may be generated:
 3 of 10 files
 123 KB of 789.1 MB
 3.3 MB of 103.92 GB — 2 minutes remaining
 1.61 GB of 3.22 GB (2 KB/sec) — 2 minutes remaining
 1 minute remaining (1 KB/sec)
 
 */
@property (null_resettable, copy) NSString *localizedAdditionalDescription;

/* Whether the work being done can be cancelled or paused, respectively. By default NSProgresses are cancellable but not pausable. NSProgress is by default KVO-compliant for these properties, with the notifications always being sent on the thread which updates the property. These properties are for communicating whether controls for cancelling and pausing should appear in a progress reporting user interface. NSProgress itself does not do anything with these properties other than help pass their values from progress reporters to progress observers. It is valid for the values of these properties to change in virtually any way during the lifetime of an NSProgress. Of course, if an NSProgress is cancellable you should actually implement cancellability by setting a cancellation handler or by making your code poll the result of invoking -isCancelled. Likewise for pausability.
 */
//任务可能
@property (getter=isCancellable) BOOL cancellable;
@property (getter=isPausable) BOOL pausable;

/* Whether the work being done has been cancelled or paused, respectively. NSProgress is by default KVO-compliant for these properties, with the notifications always being sent on the thread which updates the property. Instances of NSProgress that have parents are at least as cancelled or paused as their parents.
 */
@property (readonly, getter=isCancelled) BOOL cancelled;
@property (readonly, getter=isPaused) BOOL paused;

/* A block to be invoked when cancel is invoked. The block will be invoked even when the method is invoked on an ancestor of the receiver, or an instance of NSProgress in another process that resulted from publishing the receiver or an ancestor of the receiver. Your block won't be invoked on any particular queue. If it must do work on a specific queue then it should schedule that work on that queue.
 */
@property (nullable, copy) void (^cancellationHandler)(void);

/* A block to be invoked when pause is invoked. The block will be invoked even when the method is invoked on an ancestor of the receiver, or an instance of NSProgress in another process that resulted from publishing the receiver or an ancestor of the receiver. Your block won't be invoked on any particular queue. If it must do work on a specific queue then it should schedule that work on that queue.
 */
@property (nullable, copy) void (^pausingHandler)(void);

/* A block to be invoked when resume is invoked. The block will be invoked even when the method is invoked on an ancestor of the receiver, or an instance of NSProgress in another process that resulted from publishing the receiver or an ancestor of the receiver. Your block won't be invoked on any particular queue. If it must do work on a specific queue then it should schedule that work on that queue.
 */
@property (nullable, copy) void (^resumingHandler)(void) NS_AVAILABLE(10_11, 9_0);

/* Set a value in the dictionary returned by invocations of -userInfo, with appropriate KVO notification for properties whose values can depend on values in the user info dictionary, like localizedDescription. If a nil value is passed then the dictionary entry is removed.
 */
#if FOUNDATION_SWIFT_SDK_EPOCH_AT_LEAST(8)
- (void)setUserInfoObject:(nullable id)objectOrNil forKey:(NSProgressUserInfoKey)key;
#else
- (void)setUserInfoObject:(nullable id)objectOrNil forKey:(NSString *)key;
#endif

#pragma mark *** Observing and Controlling Progress ***

/* Whether the progress being made is indeterminate. -isIndeterminate returns YES when the value of the totalUnitCount or completedUnitCount property is less than zero. Zero values for both of those properties indicates that there turned out to not be any work to do after all; -isIndeterminate returns NO and -fractionCompleted returns 1.0 in that case. NSProgress is by default KVO-compliant for these properties, with the notifications always being sent on the thread which updates the property.
 */
@property (readonly, getter=isIndeterminate) BOOL indeterminate;

/* The fraction of the overall work completed by this progress object, including work done by any children it may have.
 */
@property (readonly) double fractionCompleted;

/* Invoke the block registered with the cancellationHandler property, if there is one, and set the cancelled property to YES. Do this for the receiver, any descendants of the receiver, the instance of NSProgress that was published in another process to make the receiver if that's the case, and any descendants of such a published instance of NSProgress.
 */
- (void)cancel;

/* Invoke the block registered with the pausingHandler property, if there is one, and set the paused property to YES. Do this for the receiver, any descendants of the receiver, the instance of NSProgress that was published in another process to make the receiver if that's the case, and any descendants of such a published instance of NSProgress.
 */
- (void)pause;

/* Invoke the block registered with the resumingHandler property, if there is one, and set the paused property to NO. Do this for the receiver, any descendants of the receiver, the instance of NSProgress that was published in another process to make the receiver if that's the case, and any descendants of such a published instance of NSProgress.
 */
- (void)resume NS_AVAILABLE(10_11, 9_0);

/* Arbitrary values associated with the receiver. Returns a KVO-compliant dictionary that changes as -setUserInfoObject:forKey: is sent to the receiver. The dictionary will send all of its KVO notifications on the thread which updates the property. The result will never be nil, but may be an empty dictionary. Some entries have meanings that are recognized by the NSProgress class itself. See the NSProgress...Key string constants listed below.
 */
#if FOUNDATION_SWIFT_SDK_EPOCH_AT_LEAST(8)
@property (readonly, copy) NSDictionary<NSProgressUserInfoKey, id> *userInfo;
#else
@property (readonly, copy) NSDictionary *userInfo;
#endif

/* Either a string identifying what kind of progress is being made, like NSProgressKindFile, or nil. If the value of the localizedDescription property has not been set to a non-nil value then the default implementation of -localizedDescription uses the progress kind to determine how to use the values of other properties, as well as values in the user info dictionary, to create a string that is presentable to the user. This is most useful when -localizedDescription is actually being invoked in another process, whose localization language may be different, as a result of using the publish and subscribe mechanism described here.
 */
@property (nullable, copy) NSProgressKind kind;

#pragma mark *** Reporting Progress to Other Processes (OS X Only) ***

/* Make the NSProgress observable by other processes. Whether or not another process can discover the NSProgress to observe it, and how it would do that, depends on entries in the user info dictionary. For example, an NSProgressFileURLKey entry makes an NSProgress discoverable by corresponding invokers of +addSubscriberForFileURL:withPublishingHandler:.
 
 When you make an NSProgress observable by other processes you must ensure that at least -localizedDescription, -isIndeterminate, and -fractionCompleted always work when sent to proxies of your NSProgress in other processes. You make -isIndeterminate and -fractionCompleted always work by accurately setting the total and completed unit counts of the progress. You make -localizedDescription always work by setting the value of the kind property to something valid, like NSProgressKindFile, and then fulfilling the requirements for that specific kind of progress. (You can instead set the value of localizedDescription directly but that is not perfectly reliable because other processes might be using different localization languages than yours.)
 
 You can publish an instance of NSProgress at most once.
 */
- (void)publish NS_AVAILABLE(10_9, NA);

/* Make the NSProgress no longer observable by other processes.
 */
- (void)unpublish NS_AVAILABLE(10_9, NA);



