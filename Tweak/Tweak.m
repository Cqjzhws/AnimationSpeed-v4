// AnimationSpeedTweak v3.5 — bundle-aware single dylib
// Safe profile (WeChat/WeWork): v6_fix 19-hook + CALayer/C AAnimation 加速
// Broad profile (other apps): +UIDynamicAnimator, factor 0.01
//
// 修复：CAPropertyAnimation setDuration 是类方法→swizzleClass；
//       swizzle helper 用 class_addMethod 桥接（v6_fix 验证机制）；
//       safe profile 加回 CALayer actionForKey + CAAnimation setDuration
//       （v3.1极速感的主要来源，v6_fix 因稳定顾虑去掉了）。
//
// 编译：clang -arch arm64 -dynamiclib -isysroot $SDK -undefined dynamic_lookup -fobjc-arc \
//        -framework Foundation -framework UIKit -framework QuartzCore -o AnimationSpeedTweak.dylib Tweak.m

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// MARK: - 全局状态

static double gFactor          = 0.001;  // 非微信 App 广覆盖档
static double gWeChatFactor   = 0.001;  // 微信安全档（v6 实测稳定）
static BOOL   gSafeProfile     = NO;     // YES=微信：只装安全 hook 集（含 CALayer/C AAnim）
static BOOL   gInstantMode     = NO;
static double gMinPageAnimSec  = 0.050;  // 页面跳转最小 50ms（防状态机闪退）
static double gMinViewAnimSec  = 0.016;  // 视图动画最小 16ms（1 帧）
static double gMinCALayerSec   = 0.020;  // 内部 CA 动画最小 20ms

static NSString *const kConfigPath = @"/var/Managed Preferences/mobile/com.developlab.animationspeed.plist";
static NSTimeInterval gLastReload = 0;

// MARK: - 配置

static void _reloadConfigIfNeeded(void) {
    NSTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (now - gLastReload < 1.0) return;
    gLastReload = now;
    @autoreleasepool {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kConfigPath];
        if (![d isKindOfClass:[NSDictionary class]]) return;
        NSNumber *f = d[@"ViewAnimationFactor"];
        if ([f isKindOfClass:[NSNumber class]] && f.doubleValue > 0 && f.doubleValue <= 2.0) gFactor = f.doubleValue;
        NSNumber *inst = d[@"InstantMode"]; if ([inst isKindOfClass:[NSNumber class]]) gInstantMode = inst.boolValue;
    }
}

static double _effectiveFactor(void) {
    _reloadConfigIfNeeded();
    if (gInstantMode) return 0.0;
    return gFactor;
}

// 带下限的缩放（用于 CA 层级）
static inline NSTimeInterval _scaleVC(NSTimeInterval t, double f, double minMs) {
    if (gInstantMode) return 0.0;
    if (t <= 0) return t;
    NSTimeInterval s = t * f;
    return (s * 1000.0 < minMs) ? (minMs / 1000.0) : s;
}

// 视图动画缩放（带下限）
static inline NSTimeInterval _scaleInterval(NSTimeInterval t, double f) {
    if (gInstantMode) return 0.0;
    if (t <= 0) return t;
    NSTimeInterval s = t * f;
    return (s < gMinViewAnimSec) ? gMinViewAnimSec : s;
}

// MARK: - swizzle helpers（v6_fix 验证机制：NULL 检查 + class_addMethod 桥接）

static BOOL _swizzleInstance(Class cls, SEL orig, SEL repl) {
    if (!cls) { NSLog(@"[AST] skip nil cls for %@", NSStringFromSelector(orig)); return NO; }
    Method origMethod = class_getInstanceMethod(cls, orig);
    Method replMethod = class_getInstanceMethod(objc_getClass("AnimationSpeedTweak"), repl);
    if (!origMethod) { NSLog(@"[AST] MISS orig %@ on %@", NSStringFromSelector(orig), cls); return NO; }
    if (!replMethod) { NSLog(@"[AST] MISS repl %@ on AnimationSpeedTweak", NSStringFromSelector(repl)); return NO; }
    IMP replImp = method_getImplementation(replMethod);
    const char *types = method_getTypeEncoding(replMethod);
    if (!class_addMethod(cls, repl, replImp, types)) {
        Method existing = class_getInstanceMethod(cls, repl);
        if (existing) { method_exchangeImplementations(origMethod, existing); return YES; }
        NSLog(@"[AST] FAIL add %@ to %@", NSStringFromSelector(repl), cls); return NO;
    }
    Method replInCls = class_getInstanceMethod(cls, repl);
    method_exchangeImplementations(origMethod, replInCls);
    return YES;
}

static BOOL _swizzleClass(Class cls, SEL orig, SEL repl) {
    if (!cls) { NSLog(@"[AST] skip nil cls for %@", NSStringFromSelector(orig)); return NO; }
    Method origMethod = class_getClassMethod(cls, orig);
    Method replMethod = class_getClassMethod(objc_getClass("AnimationSpeedTweak"), repl);
    if (!origMethod) { NSLog(@"[AST] MISS orig %@ on %@", NSStringFromSelector(orig), cls); return NO; }
    if (!replMethod) { NSLog(@"[AST] MISS repl %@ on AnimationSpeedTweak", NSStringFromSelector(repl)); return NO; }
    IMP replImp = method_getImplementation(replMethod);
    const char *types = method_getTypeEncoding(replMethod);
    Class meta = object_getClass(cls);
    if (!class_addMethod(meta, repl, replImp, types)) {
        Method existing = class_getClassMethod(cls, repl);
        if (existing) { method_exchangeImplementations(origMethod, existing); return YES; }
        NSLog(@"[AST] FAIL add %@ to meta %@", NSStringFromSelector(repl), cls); return NO; }
    Method replInCls = class_getClassMethod(cls, repl);
    method_exchangeImplementations(origMethod, replInCls);
    return YES;
}

// MARK: - AnimationSpeedTweak 方法实现（全部是 class method，供 swizzle 桥接用）

@interface AnimationSpeedTweak : NSObject
@end

@implementation AnimationSpeedTweak

// UIView animateWithDuration:animations:
+ (void)as_UIView_animate:(NSTimeInterval)d animations:(void(^)(void))a {
    [self as_UIView_animate:_scaleInterval(d, _effectiveFactor()) animations:a];
}
// UIView animateWithDuration:animations:completion:
+ (void)as_UIView_animate:(NSTimeInterval)d animations:(void(^)(void))a completion:(void(^)(BOOL))c {
    [self as_UIView_animate:_scaleInterval(d, _effectiveFactor()) animations:a completion:c];
}
// UIView animateWithDuration:delay:options:animations:completion:
+ (void)as_UIView_animate:(NSTimeInterval)d delay:(NSTimeInterval)dl options:(UIViewAnimationOptions)o animations:(void(^)(void))a completion:(void(^)(BOOL))c {
    [self as_UIView_animate:_scaleInterval(d,_effectiveFactor()) delay:dl*_effectiveFactor() options:o animations:a completion:c];
}
// UIView animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:
+ (void)as_UIView_animate:(NSTimeInterval)d delay:(NSTimeInterval)dl usingSpringWithDamping:(CGFloat)dr initialSpringVelocity:(CGFloat)v options:(UIViewAnimationOptions)o animations:(void(^)(void))a completion:(void(^)(BOOL))c {
    [self as_UIView_animate:_scaleInterval(d,_effectiveFactor()) delay:dl*_effectiveFactor() usingSpringWithDamping:dr initialSpringVelocity:v*_effectiveFactor() options:o animations:a completion:c];
}
// UIView transitionWithView:duration:options:animations:completion:
+ (void)as_UIView_transitionWithView:(UIView*)vw duration:(NSTimeInterval)d options:(UIViewAnimationOptions)o animations:(void(^)(void))a completion:(void(^)(BOOL))c {
    [self as_UIView_transitionWithView:vw duration:_scaleInterval(d,_effectiveFactor()) options:o animations:a completion:c];
}
// UIView transitionFromView:toView:duration:options:completion:
+ (void)as_UIView_transitionFromView:(UIView*)fv toView:(UIView*)tv duration:(NSTimeInterval)d options:(UIViewAnimationOptions)o completion:(void(^)(BOOL))c {
    [self as_UIView_transitionFromView:fv toView:tv duration:_scaleInterval(d,_effectiveFactor()) options:o completion:c];
}

// UIViewPropertyAnimator
- (instancetype)as_UIPA_initDuration:(NSTimeInterval)d timingParameters:(id)p {
    return [self as_UIPA_initDuration:_scaleInterval(d,_effectiveFactor()) timingParameters:p];
}
- (instancetype)as_UIPA_initDuration:(NSTimeInterval)d dampingRatio:(CGFloat)r animations:(void(^)(void))a {
    return [self as_UIPA_initDuration:_scaleInterval(d,_effectiveFactor()) dampingRatio:r animations:a];
}
- (void)as_UIPA_setDuration:(NSTimeInterval)d {
    [self as_UIPA_setDuration:_scaleInterval(d,_effectiveFactor())];
}

// UIScrollView
- (void)as_UISV_setContentOffset:(CGPoint)o animated:(BOOL)an {
    if (!an) { [self as_UISV_setContentOffset:o animated:an]; return; }
    double f=_effectiveFactor();
    [UIView animateWithDuration:_scaleInterval(0.25,f) delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{ [self as_UISV_setContentOffset:o animated:NO]; } completion:nil];
}
- (void)as_UISV_scrollRectToVisible:(CGRect)r animated:(BOOL)an {
    if (!an) { [self as_UISV_scrollRectToVisible:r animated:an]; return; }
    double f=_effectiveFactor();
    [UIView animateWithDuration:_scaleInterval(0.25,f) delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{ [self as_UISV_scrollRectToVisible:r animated:NO]; } completion:nil];
}

// UINavigationController push/pop
- (void)as_Nav_pushViewController:(UIViewController*)vc animated:(BOOL)an {
    if (!an) { [self as_Nav_pushViewController:vc animated:an]; return; }
    double f=_effectiveFactor();
    [UIView animateWithDuration:_scaleVC(0.35,f,50) delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{ [self as_Nav_pushViewController:vc animated:NO]; } completion:nil];
}
- (UIViewController*)as_Nav_popViewControllerAnimated:(BOOL)an {
    if (!an) return [self as_Nav_popViewControllerAnimated:an];
    double f=_effectiveFactor(); __block UIViewController *result=nil;
    [UIView animateWithDuration:_scaleVC(0.35,f,50) delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{ result=[self as_Nav_popViewControllerAnimated:NO]; } completion:nil];
    return result;
}
- (NSArray<UIViewController*>*)as_Nav_popToViewController:(UIViewController*)vc animated:(BOOL)an {
    if (!an) return [self as_Nav_popToViewController:vc animated:an];
    double f=_effectiveFactor(); __block NSArray *result=nil;
    [UIView animateWithDuration:_scaleVC(0.35,f,50) delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{ result=[self as_Nav_popToViewController:vc animated:NO]; } completion:nil];
    return result;
}
- (NSArray<UIViewController*>*)as_Nav_popToRootViewControllerAnimated:(BOOL)an {
    if (!an) return [self as_Nav_popToRootViewControllerAnimated:an];
    double f=_effectiveFactor(); __block NSArray *result=nil;
    [UIView animateWithDuration:_scaleVC(0.35,f,50) delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{ result=[self as_Nav_popToRootViewControllerAnimated:NO]; } completion:nil];
    return result;
}

// UITabBarController
- (void)as_Tab_setSelectedIndex:(NSUInteger)i {
    double f=_effectiveFactor();
    [UIView animateWithDuration:_scaleVC(0.25,f,50) delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{ [self as_Tab_setSelectedIndex:i]; } completion:nil];
}

// UIViewController present/dismiss
- (void)as_VC_presentViewController:(UIViewController*)vc animated:(BOOL)an completion:(void(^)(void))c {
    if (!an) { [self as_VC_presentViewController:vc animated:an completion:c]; return; }
    double f=_effectiveFactor();
    [UIView animateWithDuration:_scaleVC(0.35,f,50) delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{ [self as_VC_presentViewController:vc animated:NO completion:c]; } completion:nil];
}
- (void)as_VC_dismissViewControllerAnimated:(BOOL)an completion:(void(^)(void))c {
    if (!an) { [self as_VC_dismissViewControllerAnimated:an completion:c]; return; }
    double f=_effectiveFactor();
    [UIView animateWithDuration:_scaleVC(0.35,f,50) delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{ [self as_VC_dismissViewControllerAnimated:NO completion:c]; } completion:nil];
}

// CATransaction setAnimationDuration（类方法）
+ (void)as_CATrans_setDuration:(CFTimeInterval)d {
    [self as_CATrans_setDuration:_scaleVC(d,_effectiveFactor(),16)];
}

// CAPropertyAnimation setDuration（类方法，供 swizzle 替换类方法）
+ (void)as_CAProp_setDuration:(CFTimeInterval)d {
    [self as_CAProp_setDuration:_scaleVC(d,_effectiveFactor(),16)];
}

// CAAnimation setDuration 实例方法（供 CALayer hook 调用）
- (void)as_CAAnim_setDuration:(CFTimeInterval)d {
    [self as_CAAnim_setDuration:_scaleVC(d,_effectiveFactor(),20)];
}

@end

// MARK: - 激进 hook 方法（仅非 safe profile 安装）

@interface CAAnimation (ASTweak)
- (void)as_CAAnim_setDuration:(CFTimeInterval)d;
@end

@interface CALayer (ASTweak_Risky)
@end
@implementation CALayer (ASTweak_Risky)
- (id)as_CALayer_actionForKey:(NSString*)key {
    id action = [self as_CALayer_actionForKey:key];
    if ([action isKindOfClass:[CAAnimation class]]) {
        [(CAAnimation*)action as_CAAnim_setDuration:_scaleVC([(CAAnimation*)action duration], _effectiveFactor(), 20)];
    }
    return action;
}
@end

@interface UIDynamicAnimator (ASTweak_Risky)
@end
@implementation UIDynamicAnimator (ASTweak_Risky)
- (void)as_UIDy_addBehavior:(UIDynamicBehavior*)b {
    if (gInstantMode) return;
    [self as_UIDy_addBehavior:b];
}
@end

// MARK: - _install（bundle-aware）

static void _install(void) {
    int ok=0, total=0;
    double f = _effectiveFactor();
    NSLog(@"[AnimationSpeedTweak v3.5] bid=%@ safe=%d factor=%.4f", NSBundle.mainBundle.bundleIdentifier, gSafeProfile, f);

    // ─── 通用安全 hook ──────────────────────────────────────────────────
    Class UIView_cls = [UIView class];
    total += 6;
    ok += _swizzleClass(UIView_cls, @selector(animateWithDuration:animations:),
                        @selector(as_UIView_animate:animations:));
    ok += _swizzleClass(UIView_cls, @selector(animateWithDuration:animations:completion:),
                        @selector(as_UIView_animate:animations:completion:));
    ok += _swizzleClass(UIView_cls, @selector(animateWithDuration:delay:options:animations:completion:),
                        @selector(as_UIView_animate:delay:options:animations:completion:));
    ok += _swizzleClass(UIView_cls, @selector(animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:),
                        @selector(as_UIView_animate:delay:options:animations:completion:));
    ok += _swizzleClass(UIView_cls, @selector(transitionWithView:duration:options:animations:completion:),
                        @selector(as_UIView_transitionWithView:duration:options:animations:completion:));
    ok += _swizzleClass(UIView_cls, @selector(transitionFromView:toView:duration:options:completion:),
                        @selector(as_UIView_transitionFromView:toView:duration:options:completion:));

    Class UIPA_cls = [UIViewPropertyAnimator class];
    total += 3;
    ok += _swizzleInstance(UIPA_cls, @selector(initWithDuration:timingParameters:),
                           @selector(as_UIPA_initDuration:timingParameters:));
    ok += _swizzleInstance(UIPA_cls, @selector(initWithDuration:dampingRatio:animations:),
                           @selector(as_UIPA_initDuration:dampingRatio:animations:));
    ok += _swizzleInstance(UIPA_cls, @selector(setDuration:),
                           @selector(as_UIPA_setDuration:));

    Class UISV_cls = [UIScrollView class];
    total += 2;
    ok += _swizzleInstance(UISV_cls, @selector(setContentOffset:animated:),
                           @selector(as_UISV_setContentOffset:animated:));
    ok += _swizzleInstance(UISV_cls, @selector(scrollRectToVisible:animated:),
                           @selector(as_UISV_scrollRectToVisible:animated:));

    Class Nav_cls = [UINavigationController class];
    total += 4;
    ok += _swizzleInstance(Nav_cls, @selector(pushViewController:animated:),
                           @selector(as_Nav_pushViewController:animated:));
    ok += _swizzleInstance(Nav_cls, @selector(popViewControllerAnimated:),
                           @selector(as_Nav_popViewControllerAnimated:));
    ok += _swizzleInstance(Nav_cls, @selector(popToViewController:animated:),
                           @selector(as_Nav_popToViewController:animated:));
    ok += _swizzleInstance(Nav_cls, @selector(popToRootViewControllerAnimated:),
                           @selector(as_Nav_popToRootViewControllerAnimated:));

    Class Tab_cls = [UITabBarController class];
    total += 1;
    ok += _swizzleInstance(Tab_cls, @selector(setSelectedIndex:),
                           @selector(as_Tab_setSelectedIndex:));

    Class VC_cls = [UIViewController class];
    total += 2;
    ok += _swizzleInstance(VC_cls, @selector(presentViewController:animated:completion:),
                           @selector(as_VC_presentViewController:animated:completion:));
    ok += _swizzleInstance(VC_cls, @selector(dismissViewControllerAnimated:completion:),
                           @selector(as_VC_dismissViewControllerAnimated:completion:));

    total += 2;
    ok += _swizzleClass([CATransaction class], @selector(setAnimationDuration:),
                        @selector(as_CATrans_setDuration:));
    ok += _swizzleClass([CAPropertyAnimation class], @selector(setDuration:),
                        @selector(as_CAProp_setDuration:));

    // ─── Safe profile 也装 CALayer/C AAnimation（极速感的主要来源）─────
    //    CAPropertyAnimation/CATransaction 已上；这里加 CALayer + CAAnimation instance
    Class CALR_cls = [CALayer class];
    total += 1;
    ok += _swizzleInstance(CALR_cls, @selector(actionForKey:),
                           @selector(as_CALayer_actionForKey:));
    // swizzle CAAnimation setDuration: instance method so CALayer hook can call it
    total += 1;
    ok += _swizzleInstance([CAAnimation class], @selector(setDuration:),
                           @selector(as_CAAnim_setDuration:));

    NSLog(@"[AnimationSpeedTweak v3.5] installed hooks %d/%d", ok, total);

    // ─── 激进 hook（仅非 safe profile：UIDynamicAnimator）──────────────
    if (!gSafeProfile) {
        int ok2=0, total2=0;
        Class UIDy_cls = [UIDynamicAnimator class];
        total2++;
        ok2 += _swizzleInstance(UIDy_cls, @selector(addBehavior:),
                                @selector(as_UIDy_addBehavior:));
        NSLog(@"[AnimationSpeedTweak v3.5] installed extra risky hooks %d/%d", ok2, total2);
    }

    // HUD 横幅（延迟 1s 显示，确认注入成功）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *win = UIApplication.sharedApplication.windows.firstObject;
        if (!win) return;
        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, win.bounds.size.width, 24)];
        bar.backgroundColor = [UIColor colorWithRed:0 green:0.5 blue:1 alpha:0.85];
        bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        UILabel *lbl = [[UILabel alloc] initWithFrame:bar.bounds];
        lbl.text = [NSString stringWithFormat:@"AST v3.5 %@ factor=%.4f",
                    gSafeProfile ? @"SAFE" : @"BROAD", _effectiveFactor()];
        lbl.textColor = [UIColor whiteColor]; lbl.font = [UIFont systemFontOfSize:12];
        lbl.textAlignment = NSTextAlignmentCenter;
        [bar addSubview:lbl]; [win addSubview:bar];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [bar removeFromSuperview]; });
    });
}

// MARK: - 构造器

__attribute__((constructor))
static void _astweak_init(void) {
    @autoreleasepool {
        NSString *bid = NSBundle.mainBundle.bundleIdentifier ?: @"";
        if ([bid isEqualToString:@"com.tencent.xin"] ||
            [bid hasPrefix:@"com.tencent.xin"] ||
            [bid isEqualToString:@"com.tencent.wework"] ||
            [bid hasPrefix:@"com.tencent.wework"]) {
            gSafeProfile    = YES;
            gFactor         = gWeChatFactor;  // 0.001
            gMinPageAnimSec = 0.050;
            gMinViewAnimSec = 0.016;
            gMinCALayerSec  = 0.020;
        }
        _install();
        NSLog(@"[AnimationSpeedTweak v3.5] ready bid=%@ safe=%d factor=%.4f minPage=%.0fms",
              bid, gSafeProfile, gFactor, gMinPageAnimSec*1000);
    }
}
