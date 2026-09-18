#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ================================
// 全局配置（运行时可热改）
// ================================
static double gFactor = 0.10;
static NSTimeInterval gMinDurationMs = 0;
static BOOL gInstantMode = NO;

// ================================
// 黑名单 & 单App配置
// ================================
static NSMutableSet *gBlacklist = nil;
static NSMutableDictionary *gPerApp = nil;

// ================================
// 配置重载（每秒执行一次）
// ================================
static CFDateRef _lastRead = NULL;
static void _reloadConfigIfNeeded(void) {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (_lastRead && now - CFDateGetAbsoluteTime(_lastRead) < 1.0) return;
    if (_lastRead) CFRelease(_lastRead);
    _lastRead = CFDateCreate(kCFAllocatorDefault, now);

    NSString *path = @"/var/Managed Preferences/mobile/com.developlab.animationspeed.plist";
    NSDictionary *cfg = [NSDictionary dictionaryWithContentsOfFile:path];
    if (!cfg) return;

    id fv = cfg[@"UIAnimationDragCoefficient"];
    if (fv) gFactor = [fv doubleValue];

    id mv = cfg[@"MinDurationMs"];
    if (mv) gMinDurationMs = [mv doubleValue];

    id iv = cfg[@"InstantMode"];
    if (iv) gInstantMode = [iv boolValue];

    id bl = cfg[@"Blacklist"];
    if (bl && [bl isKindOfClass:[NSArray class]]) {
        [gBlacklist removeAllObjects];
        [gBlacklist addObjectsFromArray:bl];
    }

    id pa = cfg[@"PerAppFactor"];
    if (pa && [pa isKindOfClass:[NSDictionary class]]) {
        [gPerApp addEntriesFromDictionary:pa];
    }
}

// ================================
// 核心加速逻辑
// ================================
static double _effectiveFactor(void) {
    _reloadConfigIfNeeded();
    if (gInstantMode) return 0.0;
    NSString *bid = NSBundle.mainBundle.bundleIdentifier;
    if (bid && [gBlacklist containsObject:bid]) return 1.0;
    if (bid) {
        NSNumber *o = gPerApp[bid];
        if (o && o.doubleValue > 0 && o.doubleValue <= 2.0) return o.doubleValue;
    }
    return gFactor;
}

// duration 缩放：小于 minMs 不动，返回值保证 >= 0.016s 防止瞬间完成
static inline NSTimeInterval _scaleInterval(NSTimeInterval t, double f) {
    if (gInstantMode) return 0.0;
    if (t <= 0) return t;
    if (gMinDurationMs > 0 && t * 1000.0 < gMinDurationMs) return t;
    NSTimeInterval s = t * f;
    return (s < 0.016 && s > 0) ? 0.016 : s;
}

// ================================
// Swizzle 辅助
// ================================
static void _swizzleInstance(Class cls, SEL orig, SEL repl) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, orig);
    Method m2 = class_getInstanceMethod(cls, repl);
    if (m && m2) method_exchangeImplementations(m, m2);
}

static void _swizzleClass(Class cls, SEL orig, SEL repl) {
    if (!cls) return;
    Method m = class_getClassMethod(cls, orig);
    Method m2 = class_getClassMethod(cls, repl);
    if (m && m2) method_exchangeImplementations(m, m2);
}

// ================================
// AnimationSpeedTweak — 所有 swizzle 方法
// ================================
@implementation AnimationSpeedTweak

// MARK: UIView (Class Methods) — animateWithDuration 全家桶
+ (void)as_UIView_animate:(NSTimeInterval)d
               animations:(void (^)(void))a {
    double f = _effectiveFactor();
    [self as_UIView_animate:_scaleInterval(d, f) animations:a];
}

+ (void)as_UIView_animate:(NSTimeInterval)d
               animations:(void (^)(void))a
               completion:(void (^)(BOOL))c {
    double f = _effectiveFactor();
    [self as_UIView_animate:_scaleInterval(d, f) animations:a completion:c];
}

+ (void)as_UIView_animate:(NSTimeInterval)d
                     delay:(NSTimeInterval)dl
                   options:(UIViewAnimationOptions)o
                animations:(void (^)(void))a
                completion:(void (^)(BOOL))c {
    double f = _effectiveFactor();
    [self as_UIView_animate:_scaleInterval(d, f)
                       delay:dl * f
                     options:o
                  animations:a
                  completion:c];
}

+ (void)as_UIView_animate:(NSTimeInterval)d
                     delay:(NSTimeInterval)dl
      usingSpringWithDamping:(CGFloat)dr
       initialSpringVelocity:(CGFloat)v
                     options:(UIViewAnimationOptions)o
                  animations:(void (^)(void))a
                  completion:(void (^)(BOOL))c {
    double f = _effectiveFactor();
    [self as_UIView_animate:_scaleInterval(d, f)
                       delay:dl * f
        usingSpringWithDamping:dr
         initialSpringVelocity:v * f
                     options:o
                  animations:a
                  completion:c];
}

+ (void)as_UIView_transitionWithView:(UIView *)vw
                             duration:(NSTimeInterval)d
                              options:(UIViewAnimationOptions)o
                           animations:(void (^)(void))a
                           completion:(void (^)(BOOL))c {
    double f = _effectiveFactor();
    [self as_UIView_transitionWithView:vw duration:_scaleInterval(d, f) options:o animations:a completion:c];
}

+ (void)as_UIView_transitionFromView:(UIView *)fv
                               toView:(UIView *)tv
                             duration:(NSTimeInterval)d
                              options:(UIViewAnimationOptions)o
                           completion:(void (^)(BOOL))c {
    double f = _effectiveFactor();
    [self as_UIView_transitionFromView:fv toView:tv duration:_scaleInterval(d, f) options:o completion:c];
}

// MARK: UIViewPropertyAnimator
- (instancetype)as_UIPA_initDuration:(NSTimeInterval)d
                    timingParameters:(id<UITimingCurveProvider>)tp {
    double f = _effectiveFactor();
    return [self as_UIPA_initDuration:_scaleInterval(d, f) timingParameters:tp];
}

- (instancetype)as_UIPA_initDuration:(NSTimeInterval)d
                        dampingRatio:(CGFloat)r
                          animations:(void (^)(void))a {
    double f = _effectiveFactor();
    return [self as_UIPA_initDuration:_scaleInterval(d, f) dampingRatio:r animations:a];
}

- (void)as_UIPA_setDuration:(NSTimeInterval)d {
    double f = _effectiveFactor();
    [self as_UIPA_setDuration:_scaleInterval(d, f)];
}

// MARK: UIScrollView
- (void)as_UISV_setContentOffset:(CGPoint)o animated:(BOOL)an {
    if (!an) { [self as_UISV_setContentOffset:o animated:an]; return; }
    double f = _effectiveFactor();
    [UIView animateWithDuration:_scaleInterval(0.25, f)
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{ [self as_UISV_setContentOffset:o animated:NO]; }
                     completion:nil];
}

- (void)as_UISV_scrollRectToVisible:(CGRect)r animated:(BOOL)an {
    if (!an) { [self as_UISV_scrollRectToVisible:r animated:an]; return; }
    double f = _effectiveFactor();
    [UIView animateWithDuration:_scaleInterval(0.25, f)
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{ [self as_UISV_scrollRectToVisible:r animated:NO]; }
                     completion:nil];
}

// MARK: CATransaction
+ (void)as_CATrans_setDuration:(CFTimeInterval)d {
    double f = _effectiveFactor();
    [self as_CATrans_setDuration:_scaleInterval(d, f)];
}

// MARK: CAPropertyAnimation
+ (void)as_CAProp_setDuration:(CFTimeInterval)d {
    double f = _effectiveFactor();
    [self as_CAProp_setDuration:_scaleInterval(d, f)];
}

@end

// ================================
// 安装全部 Hook
// ================================
__attribute__((constructor))
static void _astweak_install(void) {
    @autoreleasepool {
        gBlacklist = [NSMutableSet set];
        gPerApp    = [NSMutableDictionary dictionary];
        _reloadConfigIfNeeded();

        double f = _effectiveFactor();
        NSLog(@"[AnimationSpeedTweak] factor=%.3f minMs=%.0f instant=%d",
              f, gMinDurationMs, gInstantMode);

        // UIView 动画类方法
        Class UIView_cls = [UIView class];
        _swizzleClass(UIView_cls, @selector(animateWithDuration:animations:),
                      @selector(as_UIView_animate:animations:));
        _swizzleClass(UIView_cls, @selector(animateWithDuration:animations:completion:),
                      @selector(as_UIView_animate:animations:completion:));
        _swizzleClass(UIView_cls, @selector(animateWithDuration:delay:options:animations:completion:),
                      @selector(as_UIView_animate:delay:options:animations:completion:));
        _swizzleClass(UIView_cls, @selector(animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:),
                      @selector(as_UIView_animate:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:));
        _swizzleClass(UIView_cls, @selector(transitionWithView:duration:options:animations:completion:),
                      @selector(as_UIView_transitionWithView:duration:options:animations:completion:));
        _swizzleClass(UIView_cls, @selector(transitionFromView:toView:duration:options:completion:),
                      @selector(as_UIView_transitionFromView:toView:duration:options:completion:));

        // UIViewPropertyAnimator
        Class UIPA_cls = [UIViewPropertyAnimator class];
        _swizzleInstance(UIPA_cls, @selector(initWithDuration:timingParameters:),
                         @selector(as_UIPA_initDuration:timingParameters:));
        _swizzleInstance(UIPA_cls, @selector(initWithDuration:dampingRatio:animations:),
                         @selector(as_UIPA_initDuration:dampingRatio:animations:));
        _swizzleInstance(UIPA_cls, @selector(setDuration:),
                         @selector(as_UIPA_setDuration:));

        // UIScrollView
        Class UISV_cls = [UIScrollView class];
        _swizzleInstance(UISV_cls, @selector(setContentOffset:animated:),
                         @selector(as_UISV_setContentOffset:animated:));
        _swizzleInstance(UISV_cls, @selector(scrollRectToVisible:animated:),
                         @selector(as_UISV_scrollRectToVisible:animated:));

        // CATransaction
        Class CATrans_cls = [CATransaction class];
        _swizzleClass(CATrans_cls, @selector(setAnimationDuration:),
                      @selector(as_CATrans_setDuration:));

        // CAPropertyAnimation
        Class CAProp_cls = [CAPropertyAnimation class];
        _swizzleClass(CAProp_cls, @selector(setDuration:),
                      @selector(as_CAProp_setDuration:));

        NSLog(@"[AnimationSpeedTweak] all hooks installed OK");
    }
}
