// FPSHud - Bảng FPS + ngày giờ thực nổi trên mọi ứng dụng
// © 2026 quangbao07. Bảo lưu mọi quyền.
// Chèn file FPSHud.dylib vào IPA của bất kỳ app nào (Sideloadly: Inject dylibs).
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <mach/mach.h>

#pragma mark - Tiện ích

static UIColor *FHHex(uint32_t h) {
    return [UIColor colorWithRed:((h >> 16) & 0xFF) / 255.0 green:((h >> 8) & 0xFF) / 255.0 blue:(h & 0xFF) / 255.0 alpha:1];
}
static NSArray<UIColor *> *FHColors(void) {
    return @[FHHex(0xFF3B30), FHHex(0xFF9500), FHHex(0xFFCC00), FHHex(0x34C759),
             FHHex(0x0A84FF), FHHex(0x5E5CE6), FHHex(0xBF5AF2)];
}
static NSAttributedString *FHRainbow(NSString *t, UIFont *font) {
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:t];
    NSArray *cols = FHColors();
    for (NSUInteger i = 0; i < t.length; i++)
        [as addAttribute:NSForegroundColorAttributeName value:cols[i % cols.count] range:NSMakeRange(i, 1)];
    [as addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, t.length)];
    return as;
}
static double FHMemMB(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t c = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &c) == KERN_SUCCESS)
        return info.phys_footprint / 1048576.0;
    return 0;
}

// Viền 7 màu xoay liên tục
static CALayer *FHBorder(CGSize size, CGFloat radius, CGFloat width) {
    CALayer *host = [CALayer layer];
    host.frame = CGRectMake(0, 0, size.width, size.height);
    CGFloat d = hypot(size.width, size.height);
    NSMutableArray *cg = [NSMutableArray array];
    for (UIColor *c in FHColors()) [cg addObject:(id)c.CGColor];
    [cg addObject:(id)FHHex(0xFF3B30).CGColor];
    CAGradientLayer *g = [CAGradientLayer layer];
    g.type = kCAGradientLayerConic;
    g.colors = cg;
    g.startPoint = CGPointMake(0.5, 0.5);
    g.endPoint = CGPointMake(0.5, 0);
    g.bounds = CGRectMake(0, 0, d, d);
    g.position = CGPointMake(size.width / 2, size.height / 2);
    [host addSublayer:g];
    CAShapeLayer *m = [CAShapeLayer layer];
    m.frame = host.bounds;
    CGRect r = CGRectMake(width / 2, width / 2, size.width - width, size.height - width);
    m.path = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:MAX(0, radius - width / 2)].CGPath;
    m.fillColor = NULL;
    m.strokeColor = UIColor.blackColor.CGColor;
    m.lineWidth = width;
    host.mask = m;
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    a.fromValue = @0; a.toValue = @(M_PI * 2); a.duration = 4; a.repeatCount = HUGE_VALF;
    [g addAnimation:a forKey:@"spin"];
    return host;
}

#pragma mark - Bảng HUD

@interface FHHud : UIView
- (void)start;
- (void)stop;
- (void)placeInView:(UIView *)root;
@end
static FHHud *gHud;

@implementation FHHud {
    UILabel *_info, *_credit;
    CADisplayLink *_link;
    CFTimeInterval _last;
    NSUInteger _frames;
    int _fps;
    NSDateFormatter *_df;
    CALayer *_border;
    CGSize _borderSize;
    BOOL _placed;
}
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(10, 50, 150, 70)];
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.66];
    self.layer.cornerRadius = 12;
    _info = [UILabel new]; _info.numberOfLines = 0;
    _credit = [UILabel new];
    _credit.attributedText = FHRainbow(@"by quangbao07", [UIFont systemFontOfSize:10 weight:UIFontWeightHeavy]);
    [self addSubview:_info];
    [self addSubview:_credit];
    _df = [NSDateFormatter new];
    _df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    _df.dateFormat = @"dd/MM/yyyy HH:mm:ss";
    [self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]];
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap)]];
    [self refresh];
    return self;
}
- (void)start {
    if (_link) return;
    _last = 0; _frames = 0;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}
- (void)stop { [_link invalidate]; _link = nil; }
- (void)tick:(CADisplayLink *)l {
    if (_last == 0) { _last = l.timestamp; return; }
    _frames++;
    CFTimeInterval dt = l.timestamp - _last;
    if (dt >= 0.5) {
        _fps = (int)round(_frames / dt);
        _frames = 0; _last = l.timestamp;
        [self refresh];
    }
}
- (BOOL)compact { return [[NSUserDefaults standardUserDefaults] boolForKey:@"FH_compact"]; }
- (void)tap {
    [[NSUserDefaults standardUserDefaults] setBool:![self compact] forKey:@"FH_compact"];
    [self refresh];
    [self clamp];
}
- (void)refresh {
    UIFont *f = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightSemibold];
    NSMutableAttributedString *out = [NSMutableAttributedString new];
    void (^add)(NSString *, UIColor *) = ^(NSString *line, UIColor *c) {
        if (out.length) [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:line
            attributes:@{NSFontAttributeName: f, NSForegroundColorAttributeName: c}]];
    };
    UIColor *fc = _fps >= 55 ? FHHex(0x34C759) : (_fps >= 40 ? FHHex(0xFFCC00) : FHHex(0xFF3B30));
    add([NSString stringWithFormat:@"FPS  %d", _fps], fc);
    if (![self compact]) {
        add([_df stringFromDate:[NSDate date]], UIColor.whiteColor);
        add([NSString stringWithFormat:@"RAM  %.0f MB", FHMemMB()], UIColor.whiteColor);
    }
    _info.attributedText = out;
    CGSize s1 = [_info sizeThatFits:CGSizeMake(300, CGFLOAT_MAX)];
    CGSize s2 = [_credit sizeThatFits:CGSizeMake(300, CGFLOAT_MAX)];
    CGFloat w = MAX(s1.width, s2.width) + 16;
    CGFloat h = 6 + s1.height + 2 + s2.height + 6;
    _info.frame = CGRectMake(8, 6, w - 16, s1.height);
    _credit.frame = CGRectMake(8, 6 + s1.height + 2, w - 16, s2.height);
    CGPoint c = self.center;
    self.bounds = CGRectMake(0, 0, w, h);
    self.center = c;
    if (_borderSize.width != w || _borderSize.height != h) {
        _borderSize = CGSizeMake(w, h);
        [_border removeFromSuperlayer];
        _border = FHBorder(_borderSize, 12, 2);
        [self.layer addSublayer:_border];
    }
}
- (void)clamp {
    UIView *sv = self.superview; if (!sv) return;
    UIEdgeInsets in = sv.safeAreaInsets;
    CGFloat hw = self.bounds.size.width / 2, hh = self.bounds.size.height / 2;
    CGPoint c = self.center;
    c.x = MIN(MAX(c.x, hw + 4), sv.bounds.size.width - hw - 4);
    c.y = MIN(MAX(c.y, in.top + hh), sv.bounds.size.height - in.bottom - hh);
    self.center = c;
}
- (void)placeInView:(UIView *)root {
    if (self.superview != root) [root addSubview:self];
    if (!_placed && root.bounds.size.width > 0) {
        _placed = YES;
        NSArray *p = [[NSUserDefaults standardUserDefaults] arrayForKey:@"FH_pos"];
        if (p.count == 2) {
            self.center = CGPointMake([p[0] doubleValue] * root.bounds.size.width,
                                      [p[1] doubleValue] * root.bounds.size.height);
        } else {
            self.center = CGPointMake(self.bounds.size.width / 2 + 10, root.safeAreaInsets.top + self.bounds.size.height / 2 + 6);
        }
    }
    [self clamp];
}
- (void)pan:(UIPanGestureRecognizer *)g {
    UIView *sv = self.superview; if (!sv) return;
    CGPoint t = [g translationInView:sv];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [g setTranslation:CGPointZero inView:sv];
    [self clamp];
    if (g.state == UIGestureRecognizerStateEnded && sv.bounds.size.width > 0 && sv.bounds.size.height > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:@[@(self.center.x / sv.bounds.size.width),
                                                           @(self.center.y / sv.bounds.size.height)] forKey:@"FH_pos"];
    }
}
- (void)dealloc { [_link invalidate]; }
@end

#pragma mark - Cửa sổ nổi (cho phép chạm xuyên qua)

@interface FHWindow : UIWindow
@end
@implementation FHWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
@end

@interface FHRootVC : UIViewController
@end
@implementation FHRootVC
- (void)loadView {
    UIView *v = [UIView new];
    v.backgroundColor = UIColor.clearColor;
    self.view = v;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [gHud placeInView:self.view];
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end

static FHWindow *gWin;

static UIWindowScene *FHActiveScene(void) {
    UIWindowScene *any = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        if (s.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)s;
        if (!any) any = (UIWindowScene *)s;
    }
    return any;
}

static void FHEnsure(void) {
    UIWindowScene *sc = FHActiveScene();
    if (gWin && sc && gWin.windowScene != sc) {
        [gHud stop]; gWin.hidden = YES; gWin = nil; gHud = nil;
    }
    if (!gWin) {
        gWin = sc ? [[FHWindow alloc] initWithWindowScene:sc]
                  : [[FHWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        gWin.windowLevel = UIWindowLevelAlert + 100;
        gWin.backgroundColor = UIColor.clearColor;
        gHud = [FHHud new];
        gWin.rootViewController = [FHRootVC new];
    }
    gWin.hidden = NO;
    [gHud placeInView:gWin.rootViewController.view];
    [gHud start];
}

#pragma mark - Khởi tạo

__attribute__((constructor)) static void FHInit(void) {
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                     queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { FHEnsure(); }];
    [nc addObserverForName:UIApplicationWillResignActiveNotification object:nil
                     queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { [gHud stop]; }];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) FHEnsure();
    });
}
