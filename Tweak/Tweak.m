#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ================================
// 全局配置
// ================================
static double gFactor = 0.01;
static BOOL gInstantMode = NO;

// ================================
// 核心加速逻辑
// ================================
static double _effectiveFactor(void) {
    if (gInstantMode) return 0.0;
    return gFactor;
}

// 普通缩放：小值不动，超过 minMs 才缩
static inline NSTimeInterval _scaleInterval(NSTimeInterval t, double f) {
    if (gInstantMode) return 0.0;
    if (t <= 0) return t;
    NSTimeInterval s = t * f;
    return (s < 0.016 && s > 0) ? 0.016 : s;
}

// VC 级缩放：保底 minMs 毫秒，防止闪退
static inline NSTimeInterval _scaleVC(NSTimeInterval t, double f, double minMs) {
    if (gInstantMode) return 0.0;
    if (t <= 0) return t;
    NSTimeInterval scaled = t * f;
    double minSec = minMs / 1000.0;
    if (scaled < minSec) scaled = minSec;
    return scaled;
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
// AnimationSpeedTweak
// ================================
@implementation AnimationSpeedTweak

// MARK: UIView animateWithDuration 全家桶
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

// MARK: UIView transition
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

// MARK: UINavigationController — push/pop（保底 50ms）
- (void)as_Nav_pushViewController:(UIViewController *)vc animated:(BOOL)an {
    if (!an) { [self as_Nav_pushViewController:vc animated:an]; return; }
    double f = _effectiveFactor();
    [UIView animateWithDuration:_scaleVC(0.35, f, 50)
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{ [self as_Nav_pushViewController:vc animated:NO]; }
                     completion:nil];
}

- (UIViewController *)as_Nav_popViewControllerAnimated:(BOOL)an {
    if (!an) return [self as_Nav_popViewControllerAnimated:an];
    double f = _effectiveFactor();
    __block UIViewController *result = nil;
    [UIView animateWithDuration:_scaleVC(0.35, f, 50)
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{ result = [self as_Nav_popViewControllerAnimated:NO]; }
                     completion:nil];
    return result;
}

- (NSArray<UIViewController *> *)as_Nav_popToViewController:(UIViewController *)vc animated:(BOOL)an {
    if (!an) return [self as_Nav_popToViewController:vc animated:an];
    double f = _effectiveFactor();
    __block NSArray *result = nil;
    [UIView animateWithDuration:_scaleVC(0.35, f, 50)
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{ result = [self as_Nav_popToViewController:vc animated:NO]; }
                     completion:nil];
    return result;
}

- (NSArray<UIViewController *> *)as_Nav_popToRootViewControllerAnimated:(BOOL)an {
    if (!an) return [self as_Nav_popToRootViewControllerAnimated:an];
    double f = _effectiveFactor();
    __block NSArray *result = nil;
    [UIView animateWithDuration:_scaleVC(0.35, f, 50)
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{ result = [self as_Nav_popToRootViewControllerAnimated:NO]; }
                     completion:nil];
    return result;
}

// MARK: UITabBarController — tab 切换（保底 50ms）
- (void)as_Tab_setSelectedIndex:(NSUInteger)idx {
    double f = _effectiveFactor();
    [UIView animateWithDuration:_scaleVC(0.25, f, 50)
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{ [self as_Tab_setSelectedIndex:idx]; }
                     completion:nil];
}

// MARK: UIViewController — present/dismiss（保底 100ms，最敏感）
- (void)as_VC_presentViewController:(UIViewController *)vc
                           animated:(BOOL)an
                         completion:(void (^)(void))c {
    if (!an) { [self as_VC_presentViewController:vc animated:an completion:c]; return; }
    double f = _effectiveFactor();
    NSTimeInterval d = _scaleVC(0.30, f, 100);
    [self as_VC_presentViewController:vc animated:NO completion:c];
    if (c) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d * NSEC_PER_SEC)), dispatch_get_main_queue(), c);
    }
}

- (void)as_VC_dismissViewControllerAnimated:(BOOL)an completion:(void (^)(void))c {
    if (!an) { [self as_VC_dismissViewControllerAnimated:an completion:c]; return; }
    double f = _effectiveFactor();
    NSTimeInterval d = _scaleVC(0.30, f, 100);
    [self as_VC_dismissViewControllerAnimated:NO completion:c];
    if (c) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d * NSEC_PER_SEC)), dispatch_get_main_queue(), c);
    }
}

// MARK: CATransaction（保底 16ms）
+ (void)as_CATrans_setDuration:(CFTimeInterval)d {
    double f = _effectiveFactor();
    [self as_CATrans_setDuration:_scaleVC(d, f, 16)];
}

// MARK: CAPropertyAnimation（保底 16ms）
+ (void)as_CAProp_setDuration:(CFTimeInterval)d {
    double f = _effectiveFactor();
    [self as_CAProp_setDuration:_scaleVC(d, f, 16)];
}

@end

// ================================
// 安装全部 Hook + 启动确认横幅
// ================================
__attribute__((constructor))
static void _astweak_install(void) {
    @autoreleasepool {
        double f = _effectiveFactor();
        NSLog(@"[AnimationSpeedTweak] factor=%.3f instant=%d", f, gInstantMode);

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

        // UINavigationController
        Class Nav_cls = [UINavigationController class];
        _swizzleInstance(Nav_cls, @selector(pushViewController:animated:),
                         @selector(as_Nav_pushViewController:animated:));
        _swizzleInstance(Nav_cls, @selector(popViewControllerAnimated:),
                         @selector(as_Nav_popViewControllerAnimated:));
        _swizzleInstance(Nav_cls, @selector(popToViewController:animated:),
                         @selector(as_Nav_popToViewController:animated:));
        _swizzleInstance(Nav_cls, @selector(popToRootViewControllerAnimated:),
                         @selector(as_Nav_popToRootViewControllerAnimated:));

        // UITabBarController
        Class Tab_cls = [UITabBarController class];
        _swizzleInstance(Tab_cls, @selector(setSelectedIndex:),
                         @selector(as_Tab_setSelectedIndex:));

        // UIViewController present/dismiss
        Class VC_cls = [UIViewController class];
        _swizzleInstance(VC_cls, @selector(presentViewController:animated:completion:),
                         @selector(as_VC_presentViewController:animated:completion:));
        _swizzleInstance(VC_cls, @selector(dismissViewControllerAnimated:completion:),
                         @selector(as_VC_dismissViewControllerAnimated:completion:));

        // CATransaction / CAPropertyAnimation
        _swizzleClass([CATransaction class], @selector(setAnimationDuration:),
                      @selector(as_CATrans_setDuration:));
        _swizzleClass([CAPropertyAnimation class], @selector(setDuration:),
                      @selector(as_CAProp_setDuration:));

        NSLog(@"[AnimationSpeedTweak] all hooks installed OK (19 total)");

        // 启动确认横幅：注入成功会出现 2.5 秒
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *win = UIApplication.sharedApplication.keyWindow;
            if (!win) win = UIApplication.sharedApplication.windows.firstObject;
            if (!win) return;
            UILabel *hud = [[UILabel alloc] initWithFrame:CGRectZero];
            hud.text = [NSString stringWithFormat:@"⚡ AnimationSpeed v5  f=%.3f", gFactor];
            hud.textAlignment = NSTextAlignmentCenter;
            hud.textColor = [UIColor whiteColor];
            hud.font = [UIFont boldSystemFontOfSize:13];
            hud.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.78];
            hud.layer.cornerRadius = 8;
            hud.clipsToBounds = YES;
            hud.userInteractionEnabled = NO;
            [hud sizeToFit];
            CGRect hf = hud.frame;
            hf.size.width += 24; hf.size.height += 12;
            hud.frame = CGRectMake((win.bounds.size.width - hf.size.width) / 2.0,
                                   win.bounds.size.height - 90,
                                   hf.size.width, hf.size.height);
            [win addSubview:hud];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [hud removeFromSuperview];
            });
        });
    }
}
