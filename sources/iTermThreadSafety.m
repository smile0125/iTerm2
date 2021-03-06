//
//  iTermThreadSafety.m
//  iTerm2
//
//  Created by George Nachman on 3/14/20.
//

#import "iTermThreadSafety.h"

#import "NSObject+iTerm.h"

@interface iTermSynchronizedState()
@property (atomic) BOOL ready;
@end

@implementation iTermSynchronizedState {
    const char *_queueLabel;
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue {
    self = [super init];
    if (self) {
        _queueLabel = dispatch_queue_get_label(queue);
        assert(_queueLabel);
    }
    return self;
}

- (void)dealloc {
    [super dealloc];
}

static void Check(iTermSynchronizedState *self) {
    assert(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) == self->_queueLabel);
}

- (instancetype)retain {
    id result = [super retain];
    [self check];
    return result;
}

// Can't check on release because autorelease pools can be drained on a different thread.

- (instancetype)autorelease {
    [self check];
    return [super autorelease];
}

- (id)state {
    [self check];
    return self;
}

- (void)check {
    if (self.ready) {
        Check(self);
    }
}

@end

@implementation iTermMainThreadState
+ (instancetype)uncheckedSharedInstance {
    static iTermMainThreadState *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[iTermMainThreadState alloc] initWithQueue:dispatch_get_main_queue()];
    });
    return instance;
}

+ (instancetype)sharedInstance {
    iTermMainThreadState *instance = [self uncheckedSharedInstance];
    [instance check];
    return instance;
}
@end

@implementation iTermThread {
    iTermSynchronizedState *_state;
}

+ (instancetype)main {
    static iTermThread *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initWithQueue:dispatch_get_main_queue()
                              stateFactory:
                ^iTermSynchronizedState * _Nullable(dispatch_queue_t  _Nonnull queue) {
            return [iTermMainThreadState uncheckedSharedInstance];
        }];
    });
    return instance;
}

+ (instancetype)withLabel:(NSString *)label
             stateFactory:(iTermThreadStateFactoryBlockType)stateFactory {
    return [[self alloc] initWithLabel:label stateFactory:stateFactory];
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue
                 stateFactory:(iTermThreadStateFactoryBlockType)stateFactory {
    self = [super init];
    if (self) {
        _queue = queue;
        dispatch_retain(_queue);
        _state = [stateFactory(_queue) retain];
        _state.ready = YES;
    }
    return self;
}

- (instancetype)initWithLabel:(NSString *)label
                 stateFactory:(iTermThreadStateFactoryBlockType)stateFactory {
    return [self initWithQueue:dispatch_queue_create(label.UTF8String, DISPATCH_QUEUE_SERIAL)
                  stateFactory:stateFactory];
}

- (void)dealloc {
    dispatch_release(_queue);
    [_state release];
    [super dealloc];
}

- (void)dispatchAsync:(void (^)(id))block {
    [self retain];
    dispatch_async(_queue, ^{
        block(self->_state);
        [self release];
    });
}

- (void)dispatchSync:(void (^ NS_NOESCAPE)(id))block {
    [self retain];
    assert(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) != dispatch_queue_get_label(_queue));
    dispatch_sync(_queue, ^{
        block(self->_state);
        [self release];
    });
}

- (void)dispatchRecursiveSync:(void (^ NS_NOESCAPE)(id))block {
    if (dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) == dispatch_queue_get_label(_queue)) {
        block(self->_state);
    } else {
        [self dispatchSync:block];
    }
}

- (iTermCallback *)newCallbackWithBlock:(void (^)(id, id))callback {
    return [iTermCallback onThread:self block:callback];
}

- (iTermCallback *)newCallbackWithWeakTarget:(id)target selector:(SEL)selector userInfo:(id)userInfo {
    __weak id weakTarget = target;
    return [self newCallbackWithBlock:^(id  _Nonnull state, id  _Nullable value) {
        [weakTarget it_performNonObjectReturningSelector:selector
                                              withObject:state
                                                  object:value
                                                  object:userInfo];
    }];
}

- (void)check {
    [_state check];
}

@end

@implementation iTermCallback {
    void (^_block)(id, id);
    dispatch_group_t _group;
}

+ (instancetype)onThread:(iTermThread *)thread block:(void (^)(id, id))block {
    return [[self alloc] initWithThread:thread block:block];
}

- (instancetype)initWithThread:(iTermThread *)thread block:(void (^)(id, id))block {
    self = [super init];
    if (self) {
        _thread = [thread retain];
        _block = [block copy];
        _group = dispatch_group_create();
        dispatch_group_enter(_group);
    }
    return self;
}

- (void)dealloc {
    [_thread release];
    [_block release];
    dispatch_release(_group);
    [super dealloc];
}

- (void)invokeWithObject:(id)object {
    void (^block)(id, id) = [_block retain];
    [self retain];
    [_thread dispatchAsync:^(iTermSynchronizedState *state) {
        block(state, object);
        [block release];
        dispatch_group_leave(_group);
        [self release];
    }];
}

- (void)waitUntilInvoked {
    dispatch_group_wait(_group, DISPATCH_TIME_FOREVER);
}

@end

@implementation iTermThreadChecker {
    __weak iTermThread *_thread;
}

- (instancetype)initWithThread:(iTermThread *)thread {
    self = [super init];
    if (self) {
        _thread = thread;
    }
    return self;
}

- (void)check {
    [_thread check];
}

- (instancetype)retain {
    id result = [super retain];
    [self check];
    return result;
}

- (oneway void)release {
    [self check];
    [super release];
}

- (instancetype)autorelease {
    [self check];
    return [super autorelease];
}

@end
