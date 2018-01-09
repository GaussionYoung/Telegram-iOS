#import "RaiseToListenActivator.h"

#import <SSignalKit/SSignalKit.h>

#import "DeviceProximityManager.h"

static NSString *TGEncodeText(NSString *string, int key)
{
    NSMutableString *result = [[NSMutableString alloc] init];
    
    for (int i = 0; i < (int)[string length]; i++)
    {
        unichar c = [string characterAtIndex:i];
        c += key;
        [result appendString:[NSString stringWithCharacters:&c length:1]];
    }
    
    return result;
}

static void TGDispatchOnMainThread(dispatch_block_t block)
{
    if ([NSThread isMainThread])
        block();
    else
        dispatch_async(dispatch_get_main_queue(), block);
}

@protocol RaiseManager <NSObject>

- (id)initWithPriority:(int)priority;
- (void)setGestureHandler:(void (^)(int, int))handler;

@end

@interface RaiseToListenActivator () {
    NSInteger _proximityStateIndex;
    
    bool (^_shouldActivate)(void);
    void (^_activate)(void);
    void (^_deactivate)(void);
    
    bool _proximityState;
    STimer *_timer;
    
    id _manager;
}

@end

@implementation RaiseToListenActivator

- (instancetype)initWithShouldActivate:(bool (^)(void))shouldActivate activate:(void (^)(void))activate deactivate:(void (^)(void))deactivate {
    self = [super init];
    if (self != nil) {
        _shouldActivate = [shouldActivate copy];
        _activate = [activate copy];
        _deactivate = [deactivate copy];
        
        _enabled = false;
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
    _timer = nil;
    
    [self setEnabled:false];
}

- (void)setEnabled:(bool)enabled {
    if (_enabled != enabled) {
        _enabled = enabled;
        
        if (enabled) {
            Class c = NSClassFromString(TGEncodeText(@"DNHftuvsfNbobhfs", -1));
            if (c != nil) {
                _manager = [(id<RaiseManager>)[c alloc] initWithPriority:0x2];
                __weak RaiseToListenActivator *weakSelf = self;
                [_manager setGestureHandler:^(int arg0, int arg1) {
                    __strong RaiseToListenActivator *strongSelf = weakSelf;
                    if (strongSelf != nil) {
                        if (arg0 == 0) {
                            [strongSelf startCheckingProximity];
                        }
                    }
                }];
            }
        } else {
            [_manager setGestureHandler:nil];
            _manager = nil;
            [self stopCheckingProximity];
            if (_activated) {
                _activated = false;
                if (_deactivate) {
                    _deactivate();
                }
            }
        }
    }
}

- (void)stopCheckingProximity {
    if (_proximityStateIndex != -1) {
        [[DeviceProximityManager shared] remove:_proximityStateIndex];
        _proximityStateIndex = -1;
    }
}

- (bool)shouldActivate {
    /*if ([TGMusicPlayer isHeadsetPluggedIn]) {
        return false;
    }*/
    
    if (_shouldActivate) {
        return _shouldActivate();
    }
    
    return true;
}

- (void)startCheckingProximity {
    if (_enabled && [self shouldActivate]) {
        NSInteger previousIndex = _proximityStateIndex;
        __weak RaiseToListenActivator *weakSelf = self;
        _proximityStateIndex = [[DeviceProximityManager shared] add:^(bool value) {
            __strong RaiseToListenActivator *strongSelf = weakSelf;
            if (strongSelf != nil) {
                [strongSelf proximityChanged:value];
            }
        }];
        if (previousIndex != -1) {
            [[DeviceProximityManager shared] remove:previousIndex];
        }
        
        if (_proximityState) {
            _activated = true;
            if (_activate) {
                _activate();
            }
            
            [_timer invalidate];
            _timer = nil;
        } else if (_timer == nil) {
            __weak RaiseToListenActivator *weakSelf = self;
            _timer = [[STimer alloc] initWithTimeout:1.0 repeat:false completion:^{
                __strong RaiseToListenActivator *strongSelf = weakSelf;
                if (strongSelf != nil) {
                    strongSelf->_timer = nil;
                    [strongSelf stopCheckingProximity];
                }
            } queue:[SQueue mainQueue]];
            [_timer start];
        }
    }
}

- (void)proximityChanged:(bool)proximityState {
    TGDispatchOnMainThread(^{
        if (_proximityState != proximityState) {
            _proximityState = proximityState;
            
            if (proximityState && _timer != nil) {
                [_timer invalidate];
                _timer = nil;
                _activated = true;
                
                if (_activate) {
                    _activate();
                }
            } else if (!proximityState) {
                [_timer invalidate];
                _timer = nil;
                [self stopCheckingProximity];
                
                _activated = false;
                if (_deactivate) {
                    _deactivate();
                }
            }
        }
    });
}

@end

