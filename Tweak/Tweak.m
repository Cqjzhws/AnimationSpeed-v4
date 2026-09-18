// AnimationSpeedTweak v3 (injectable) — pure Objective-C runtime swizzle, ZERO external deps.
//
// 专为 TrollFools 注入设计：不依赖 CydiaSubstrate / Logos，
// 用 method_exchangeImplementations 直接交换方法，注入任意 App 即可生效。
//
// 编译：clang -arch arm64 -dynamiclib -isysroot $SDK -undefined dynamic_lookup -fobjc-arc \
//        -framework Foundation -o AnimationSpeedTweak.dylib Tweak.m
//
// 注入：TrollFools 选目标 App（或 SpringBoard）→ 注入 AnimationSpeedTweak.dylib → 重开/注销
// 配置：/var/Managed Preferences/mobile/com.developlab.animationspeed.plist（App 端写，dylib 实时读）

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// MARK: - 全局状态

static double gFactor          = 0.10;
static double gMinDurationMs   = 150.0;
static BOOL   gInstantMode     = NO;
static BOOL   gReduceMotion    = NO;
static BOOL   gCatTransitions  = YES;
static BOOL   gCatSprings      = YES;
static BOOL   gCatScroll       = YES;
static BOOL   gCatKeyboard     = YES;
static BOOL   gCatLayers       = YES;

static NSMutableSet<NSString*> *gBlacklist;
static NSMutableDictionary<NSString*,NSNumber*> *gPerApp;
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
        NSNumber *min = d[@"MinDurationMs"];
        if ([min isKindOfClass:[NSNumber class]] && min.doubleValue >= 0) gMinDurationMs = min.doubleValue;
        NSNumber *inst = d[@"InstantMode"]; if ([inst isKindOfClass:[NSNumber class]]) gInstantMode = inst.boolValue;
        NSNumber *rm = d[@"ReduceMotion"]; if ([rm isKindOfClass:[NSNumber class]]) gReduceMotion = rm.boolValue;
        NSDictionary *cat = d[@"Categories"];
        if ([cat isKindOfClass:[NSDictionary class]]) {
            NSNumber *t=cat[@"Transitions"]; if (t) gCatTransitions=t.boolValue;
            NSNumber *s=cat[@"Springs"];     if (s) gCatSprings=s.boolValue;
            NSNumber *sc=cat[@"Scroll"];     if (sc) gCatScroll=sc.boolValue;
            NSNumber *k=cat[@"Keyboard"];    if (k) gCatKeyboard=k.boolValue;
            NSNumber *l=cat[@"Layers"];      if (l) gCatLayers=l.boolValue;
        }
        NSArray *bl = d[@"Blacklist"];
        if ([bl isKindOfClass:[NSArray class]]) {
            [gBlacklist removeAllObjects];
            for (id x in bl) if ([x isKindOfClass:[NSString class]]) [gBlacklist addObject:x];
        }
        NSDictionary *pa = d[@"PerApp"];
        if ([pa isKindOfClass:[NSDictionary class]]) {
            [gPerApp removeAllObjects];
            for (id k in pa) if ([k isKindOfClass:[NSString class]] && [pa[k] isKindOfClass:[NSNumber class]]) gPerApp[k]=pa[k];
        }
    }
}

static double _effectiveFactor(void) {
    _reloadConfigIfNeeded();
    if (gInstantMode) return 0.0;
    NSString *bid = NSBundle.mainBundle.bundleIdentifier;
    if (bid && [gBlacklist containsObject:bid]) return 1.0;
    if (bid) { NSNumber *o = gPerApp[bid]; if (o && o.doubleValue>0 && o.doubleValue<=2.0) return o.doubleValue; }
    return gFactor;
}

static inline NSTimeInterval _scaleInterval(NSTimeInterval t, double f) {
    if (gInstantMode) return 0.0;
    if (t <= 0) return t;
    if (t*1000.0 < gMinDurationMs) return t;
    NSTimeInterval s = t*f; return s < 0.01 ? 0.01 : s;
}
static inline CFTimeInterval _scaleCF(CFTimeInterval t, double f) {
    if (gInstantMode) return 0.0;
    if (t <= 0) return t;
    if (t*1000.0 < gMinDurationMs) return t;
    CFTimeInterval s = t*f; return s < 0.01 ? 0.01 : s;
}

// MARK: - swizzle helpers

static void swizzleInstance(Class cls, SEL orig, SEL repl) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, orig);
    Method m2 = class_getInstanceMethod(cls, repl);
    if (m && m2) method_exchangeImplementations(m, m2);
}
static void swizzleClass(Class cls, SEL orig, SEL repl) {
    if (!cls) return;
    Method m = class_getClassMethod(cls, orig);
    Method m2 = class_getClassMethod(cls, repl);
    if (m && m2) method_exchangeImplementations(m, m2);
}

// MARK: - UIView (class methods)

@interface UIView (ASTweak)
@end
@implementation UIView (ASTweak)

+ (void)as_animateWithDuration:(NSTimeInterval)d animations:(void(^)(void))a {
    double f = _effectiveFactor();
    if (!gCatTransitions) { [self as_animateWithDuration:d animations:a]; return; }
    [self as_animateWithDuration:_scaleInterval(d,f) animations:a];
}
+ (void)as_animateWithDuration:(NSTimeInterval)d animations:(void(^)(void))a completion:(void(^)(BOOL))c {
    double f = _effectiveFactor();
    if (!gCatTransitions) { [self as_animateWithDuration:d animations:a completion:c]; return; }
    [self as_animateWithDuration:_scaleInterval(d,f) animations:a completion:c];
}
+ (void)as_animateWithDuration:(NSTimeInterval)d delay:(NSTimeInterval)dl options:(UIViewAnimationOptions)o animations:(void(^)(void))a completion:(void(^)(BOOL))c {
    double f = _effectiveFactor();
    if (!gCatTransitions) { [self as_animateWithDuration:d delay:dl options:o animations:a completion:c]; return; }
    [self as_animateWithDuration:_scaleInterval(d,f) delay:dl*f options:o animations:a completion:c];
}
+ (void)as_animateWithDuration:(NSTimeInterval)d delay:(NSTimeInterval)dl usingSpringWithDamping:(CGFloat)dr initialSpringVelocity:(CGFloat)v options:(UIViewAnimationOptions)o animations:(void(^)(void))a completion:(void(^)(BOOL))c {
    double f = _effectiveFactor();
    if (!gCatTransitions && !gCatSprings) { [self as_animateWithDuration:d delay:dl usingSpringWithDamping:dr initialSpringVelocity:v options:o animations:a completion:c]; return; }
    [self as_animateWithDuration:_scaleInterval(d,f) delay:dl*f usingSpringWithDamping:dr initialSpringVelocity:v options:o animations:a completion:c];
}
+ (void)as_transitionWithView:(UIView*)vw duration:(NSTimeInterval)d options:(UIViewAnimationOptions)o animations:(void(^)(void))a completion:(void(^)(BOOL))c {
    double f = _effectiveFactor();
    if (!gCatTransitions) { [self as_transitionWithView:vw duration:d options:o animations:a completion:c]; return; }
    [self as_transitionWithView:vw duration:_scaleInterval(d,f) options:o animations:a completion:c];
}
+ (void)as_transitionFromView:(UIView*)fv toView:(UIView*)tv duration:(NSTimeInterval)d options:(UIViewAnimationOptions)o completion:(void(^)(BOOL))c {
    double f = _effectiveFactor();
    if (!gCatTransitions) { [self as_transitionFromView:fv toView:tv duration:d options:o completion:c]; return; }
    [self as_transitionFromView:fv toView:tv duration:_scaleInterval(d,f) options:o completion:c];
}
@end

// MARK: - CATransaction

@interface CATransaction (ASTweak)
@end
@implementation CATransaction (ASTweak)
+ (void)as_setAnimationDuration:(CFTimeInterval)d { [self as_setAnimationDuration:_scaleCF(d,_effectiveFactor())]; }
@end

// MARK: - UIViewPropertyAnimator

@interface UIViewPropertyAnimator (ASTweak)
@end
@implementation UIViewPropertyAnimator (ASTweak)
- (instancetype)as_initWithDuration:(NSTimeInterval)d timingParameters:(id)p {
    double f=_effectiveFactor();
    if (!gCatSprings) return [self as_initWithDuration:d timingParameters:p];
    return [self as_initWithDuration:_scaleInterval(d,f) timingParameters:p];
}
- (instancetype)as_initWithDuration:(NSTimeInterval)d dampingRatio:(CGFloat)r animations:(void(^)(void))a {
    double f=_effectiveFactor();
    if (!gCatSprings) return [self as_initWithDuration:d dampingRatio:r animations:a];
    return [self as_initWithDuration:_scaleInterval(d,f) dampingRatio:r animations:a];
}
- (void)as_setDuration:(NSTimeInterval)d {
    double f=_effectiveFactor();
    if (!gCatSprings) { [self as_setDuration:d]; return; }
    [self as_setDuration:_scaleInterval(d,f)];
}
+ (void)as_runningPropertyAnimatorWithDuration:(NSTimeInterval)d delay:(NSTimeInterval)dl options:(UIViewAnimationOptions)o animations:(void(^)(void))a completion:(void(^)(UIViewAnimatingPosition))c {
    double f=_effectiveFactor();
    if (!gCatSprings) { [self as_runningPropertyAnimatorWithDuration:d delay:dl options:o animations:a completion:c]; return; }
    [self as_runningPropertyAnimatorWithDuration:_scaleInterval(d,f) delay:dl*f options:o animations:a completion:c];
}
@end

// MARK: - UIScrollView

@interface UIScrollView (ASTweak)
@end
@implementation UIScrollView (ASTweak)
- (void)as_setContentOffset:(CGPoint)o animated:(BOOL)an {
    if (!an || !gCatScroll) { [self as_setContentOffset:o animated:an]; return; }
    double f=_effectiveFactor();
    [CATransaction begin]; [CATransaction setAnimationDuration:f<=0?0:f];
    [self as_setContentOffset:o animated:YES];
    [CATransaction commit];
}
- (void)as_scrollRectToVisible:(CGRect)r animated:(BOOL)an {
    if (!an || !gCatScroll) { [self as_scrollRectToVisible:r animated:an]; return; }
    double f=_effectiveFactor();
    [CATransaction begin]; [CATransaction setAnimationDuration:f<=0?0:f];
    [self as_scrollRectToVisible:r animated:YES];
    [CATransaction commit];
}
@end

// MARK: - UINavigationController

@interface UINavigationController (ASTweak)
@end
@implementation UINavigationController (ASTweak)
- (void)as_pushViewController:(UIViewController*)vc animated:(BOOL)an {
    if (!an || !gCatTransitions) { [self as_pushViewController:vc animated:an]; return; }
    double f=_effectiveFactor();
    [CATransaction begin]; [CATransaction setAnimationDuration:f<=0?0:f];
    [self as_pushViewController:vc animated:YES];
    [CATransaction commit];
}
- (UIViewController*)as_popViewControllerAnimated:(BOOL)an {
    if (!an || !gCatTransitions) return [self as_popViewControllerAnimated:an];
    double f=_effectiveFactor();
    __block UIViewController *ret;
    [CATransaction begin]; [CATransaction setAnimationDuration:f<=0?0:f];
    ret = [self as_popViewControllerAnimated:YES];
    [CATransaction commit];
    return ret;
}
- (void)as_setViewControllers:(NSArray<UIViewController*>*)vcs animated:(BOOL)an {
    if (!an || !gCatTransitions) { [self as_setViewControllers:vcs animated:an]; return; }
    double f=_effectiveFactor();
    [CATransaction begin]; [CATransaction setAnimationDuration:f<=0?0:f];
    [self as_setViewControllers:vcs animated:YES];
    [CATransaction commit];
}
@end

// MARK: - UITabBarController

@interface UITabBarController (ASTweak)
@end
@implementation UITabBarController (ASTweak)
- (void)as_setSelectedIndex:(NSUInteger)i {
    if (!gCatTransitions) { [self as_setSelectedIndex:i]; return; }
    double f=_effectiveFactor();
    [CATransaction begin]; [CATransaction setAnimationDuration:f<=0?0:f];
    [self as_setSelectedIndex:i];
    [CATransaction commit];
}
- (void)as_setSelectedViewController:(UIViewController*)vc {
    if (!gCatTransitions) { [self as_setSelectedViewController:vc]; return; }
    double f=_effectiveFactor();
    [CATransaction begin]; [CATransaction setAnimationDuration:f<=0?0:f];
    [self as_setSelectedViewController:vc];
    [CATransaction commit];
}
@end

// MARK: - UIViewController

@interface UIViewController (ASTweak)
@end
@implementation UIViewController (ASTweak)
- (void)as_presentViewController:(UIViewController*)vc animated:(BOOL)an completion:(void(^)(void))c {
    if (!an || !gCatTransitions) { [self as_presentViewController:vc animated:an completion:c]; return; }
    double f=_effectiveFactor();
    [CATransaction begin]; [CATransaction setAnimationDuration:f<=0?0:f];
    [self as_presentViewController:vc animated:YES completion:c];
    [CATransaction commit];
}
- (void)as_dismissViewControllerAnimated:(BOOL)an completion:(void(^)(void))c {
    if (!an || !gCatTransitions) { [self as_dismissViewControllerAnimated:an completion:c]; return; }
    double f=_effectiveFactor();
    [CATransaction begin]; [CATransaction setAnimationDuration:f<=0?0:f];
    [self as_dismissViewControllerAnimated:YES completion:c];
    [CATransaction commit];
}
@end

// MARK: - CAAnimation

@interface CAAnimation (ASTweak)
@end
@implementation CAAnimation (ASTweak)
- (void)as_setDuration:(CFTimeInterval)d {
    double f=_effectiveFactor();
    BOOL spring = [self isKindOfClass:[CASpringAnimation class]];
    if (spring && !gCatSprings) { [self as_setDuration:d]; return; }
    if (!gCatLayers && !spring) { [self as_setDuration:d]; return; }
    [self as_setDuration:_scaleCF(d,f)];
}
@end

// MARK: - CALayer (隐式动画)

@interface CALayer (ASTweak)
@end
@implementation CALayer (ASTweak)
- (id)as_actionForKey:(NSString*)key {
    id action = [self as_actionForKey:key];
    if (!gCatLayers) return action;
    if ([action isKindOfClass:[CAAnimation class]]) {
        double f=_effectiveFactor();
        [(CAAnimation*)action as_setDuration:_scaleCF([(CAAnimation*)action duration], f)];
    }
    return action;
}
@end

// MARK: - UIDynamicAnimator

@interface UIDynamicAnimator (ASTweak)
@end
@implementation UIDynamicAnimator (ASTweak)
- (void)as_addBehavior:(UIDynamicBehavior*)b {
    if (gInstantMode) return;
    [self as_addBehavior:b];
}
@end


// MARK: - UIPresentationController (自定义全屏转场)

@interface UIPresentationController (ASTweak)
@end
@implementation UIPresentationController (ASTweak)
- (void)as_presentWithAnimated:(BOOL)an completion:(void(^)(void))c {
    if (!an || !gCatTransitions) { [self as_presentWithAnimated:an completion:c]; return; }
    double f=_effectiveFactor();
    [CATransaction begin]; [CATransaction setAnimationDuration:f<=0?0:f];
    [self as_presentWithAnimated:YES completion:c];
    [CATransaction commit];
}
@end

// MARK: - UIWindow (根视图控制器转场覆盖)

@interface UIWindow (ASTweak)
@end
@implementation UIWindow (ASTweak)
+ (void)as_setAnimationDuration:(CFTimeInterval)d {
    double f=_effectiveFactor();
    [self as_setAnimationDuration:_scaleCF(d,f)];
}
@end

// MARK: - UIPageViewController

@interface UIPageViewController (ASTweak)
@end
@implementation UIPageViewController (ASTweak)
- (void)as_setViewControllers:(NSArray*)vcs direction:(UIPageViewControllerNavigationDirection)dir animated:(BOOL)an completion:(void(^)(BOOL))c {
    if (!an || !gCatTransitions) { [self as_setViewControllers:vcs direction:dir animated:an completion:c]; return; }
    double f=_effectiveFactor();
    [CATransaction begin]; [CATransaction setAnimationDuration:f<=0?0:f];
    [self as_setViewControllers:vcs direction:dir animated:YES completion:c];
    [CATransaction commit];
}
@end

// MARK: - UIDocumentBrowserViewController

@interface UIDocumentBrowserViewController (ASTweak)
@end
@implementation UIDocumentBrowserViewController (ASTweak)
- (void)as_presentDocumentAtURL:(NSURL*)url options:(NSDictionary*)opts animated:(BOOL)an completion:(void(^)(UIViewController * _Nullable, NSError * _Nullable, UIViewController * _Nullable))c {
    if (!an || !gCatTransitions) { [self as_presentDocumentAtURL:url options:opts animated:an completion:c]; return; }
    double f=_effectiveFactor();
    [CATransaction begin]; [CATransaction setAnimationDuration:f<=0?0:f];
    [self as_presentDocumentAtURL:url options:opts animated:YES completion:c];
    [CATransaction commit];
}
@end

// MARK: - Reduce Motion

@interface UIApplication (ASRM)
@end
@implementation UIApplication (ASRM)
- (BOOL)as_isReduceMotionEnabled { return gReduceMotion ? YES : [self as_isReduceMotionEnabled]; }
@end
@interface UIAccessibility (ASRM)
@end
@implementation UIAccessibility (ASRM)
+ (BOOL)as_isReduceMotionEnabled { return gReduceMotion ? YES : [self as_isReduceMotionEnabled]; }
@end

// MARK: - 全部 swizzle

static void _install(void) {
    Class UIView_cls  = objc_getClass("UIView");
    Class CATx_cls    = objc_getClass("CATransaction");
    Class UIPA_cls    = objc_getClass("UIViewPropertyAnimator");
    Class UISV_cls    = objc_getClass("UIScrollView");
    Class UINC_cls    = objc_getClass("UINavigationController");
    Class UITB_cls    = objc_getClass("UITabBarController");
    Class UIVC_cls    = objc_getClass("UIViewController");
    Class CAAN_cls    = objc_getClass("CAAnimation");
    Class CALR_cls    = objc_getClass("CALayer");
    Class UIDy_cls    = objc_getClass("UIDynamicAnimator");
    Class UIApp_cls   = objc_getClass("UIApplication");
    Class UIAc_cls    = objc_getClass("UIAccessibility");

    swizzleClass(UIView_cls, @selector(animateWithDuration:animations:), @selector(as_animateWithDuration:animations:));
    swizzleClass(UIView_cls, @selector(animateWithDuration:animations:completion:), @selector(as_animateWithDuration:animations:completion:));
    swizzleClass(UIView_cls, @selector(animateWithDuration:delay:options:animations:completion:), @selector(as_animateWithDuration:delay:options:animations:completion:));
    swizzleClass(UIView_cls, @selector(animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:), @selector(as_animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:));
    swizzleClass(UIView_cls, @selector(transitionWithView:duration:options:animations:completion:), @selector(as_transitionWithView:duration:options:animations:completion:));
    swizzleClass(UIView_cls, @selector(transitionFromView:toView:duration:options:completion:), @selector(as_transitionFromView:toView:duration:options:completion:));

    swizzleClass(CATx_cls, @selector(setAnimationDuration:), @selector(as_setAnimationDuration:));

    swizzleInstance(UIPA_cls, @selector(initWithDuration:timingParameters:), @selector(as_initWithDuration:timingParameters:));
    swizzleInstance(UIPA_cls, @selector(initWithDuration:dampingRatio:animations:), @selector(as_initWithDuration:dampingRatio:animations:));
    swizzleInstance(UIPA_cls, @selector(setDuration:), @selector(as_setDuration:));
    swizzleClass(UIPA_cls, @selector(runningPropertyAnimatorWithDuration:delay:options:animations:completion:), @selector(as_runningPropertyAnimatorWithDuration:delay:options:animations:completion:));

    swizzleInstance(UISV_cls, @selector(setContentOffset:animated:), @selector(as_setContentOffset:animated:));
    swizzleInstance(UISV_cls, @selector(scrollRectToVisible:animated:), @selector(as_scrollRectToVisible:animated:));

    swizzleInstance(UINC_cls, @selector(pushViewController:animated:), @selector(as_pushViewController:animated:));
    swizzleInstance(UINC_cls, @selector(popViewControllerAnimated:), @selector(as_popViewControllerAnimated:));
    swizzleInstance(UINC_cls, @selector(setViewControllers:animated:), @selector(as_setViewControllers:animated:));

    swizzleInstance(UITB_cls, @selector(setSelectedIndex:), @selector(as_setSelectedIndex:));
    swizzleInstance(UITB_cls, @selector(setSelectedViewController:), @selector(as_setSelectedViewController:));

    swizzleInstance(UIVC_cls, @selector(presentViewController:animated:completion:), @selector(as_presentViewController:animated:completion:));
    swizzleInstance(UIVC_cls, @selector(dismissViewControllerAnimated:completion:), @selector(as_dismissViewControllerAnimated:completion:));

    swizzleInstance(CAAN_cls, @selector(setDuration:), @selector(as_setDuration:));
    swizzleInstance(CALR_cls, @selector(actionForKey:), @selector(as_actionForKey:));
    swizzleInstance(UIDy_cls, @selector(addBehavior:), @selector(as_addBehavior:));

    swizzleInstance(UIApp_cls, @selector(isReduceMotionEnabled), @selector(as_isReduceMotionEnabled));
    swizzleClass(UIAc_cls, @selector(isReduceMotionEnabled), @selector(as_isReduceMotionEnabled));
    // UIPresentationController / UIWindow / UIPageViewController / UIDocumentBrowserVC
    Class UIPrc_cls = objc_getClass("UIPresentationController");
    Class UIWin_cls = objc_getClass("UIWindow");
    Class UIPG_cls  = objc_getClass("UIPageViewController");
    Class UIDoc_cls = objc_getClass("UIDocumentBrowserViewController");
    swizzleInstance(UIPrc_cls, @selector(presentWithAnimated:completion:), @selector(as_presentWithAnimated:completion:));
    swizzleClass(UIWin_cls, @selector(setAnimationDuration:), @selector(as_setAnimationDuration:));
    swizzleInstance(UIPG_cls, @selector(setViewControllers:direction:animated:completion:), @selector(as_setViewControllers:direction:animated:completion:));
    swizzleInstance(UIDoc_cls, @selector(presentDocumentAtURL:options:animated:completion:), @selector(as_presentDocumentAtURL:options:animated:completion:));

}


// MARK: - 构造器

__attribute__((constructor))
static void _astweak_init(void) {
    @autoreleasepool {
        gBlacklist = [NSMutableSet set];
        gPerApp = [NSMutableDictionary dictionary];
        _reloadConfigIfNeeded();
        _install();
        NSLog(@"[AnimationSpeedTweak] injected factor=%.3f minMs=%.0f instant=%d rm=%d",
              gFactor, gMinDurationMs, gInstantMode, gReduceMotion);
    }
}
