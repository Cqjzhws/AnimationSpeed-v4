# Animation Speed v4 — 增强版

> **上游**：[DevelopCubeLab/AnimationSpeed](https://github.com/DevelopCubeLab/AnimationSpeed)（Apache-2.0）  
> **包 ID**：`com.developlab.animationspeed` | **iOS ≥ 14.0**（dylib）/ ≥ 12.2（App）

---

## 改动总览（v1.0.1 → v4）

| 维度 | 原版 | v4 |
|------|------|-----|
| 加速范围 | 仅 UIAnimationDragCoefficient（拖动相关） | 15+ hook 点：UIView / CATransaction / UIViewPropertyAnimator / UIScrollView / UINavigationController / UITabBarController / UIViewController / UIPresentationController / UIPageViewController / CALayer 隐式动画等 |
| 档位 | 1 个滑块（精度低） | 4 档预设（最快/快/正常/慢）+ 精确滑块 |
| 智能缩放 | 无 | MinDurationMs 保护，短动画（<150ms）原样保留 |
| 分类开关 | 无 | 独立控制：转场 / 弹簧 / 滚动 / 键盘 / 图层 |
| 黑名单 | 无 | 按 bundleID 单独 App 排除 |
| 每 App 系数 | 无 | 每个 App 设专属系数 |
| 一键关闭动画 | 无 | InstantMode 瞬间模式（近 0ms） |
| 减少动态 | 无 | 强制启用减少动态效果 |
| 注入方式 | 需 CydiaSubstrate（不可用） | **纯 ObjC runtime，零外部依赖**，TrollFools 直接注入 |

---

## 文件结构

```
AnimationSpeed-v4-enhanced/
├── AnimationSpeed/          # 原版 App 源码（Swift+ObjC，theos 工程）
│   ├── AnimationHelper.swift   # 4 档预设 + SmartScale + plist 读写
│   ├── MainViewController.swift
│   ├── AppDelegate.swift
│   ├── DeviceController.h/.m
│   └── Assets.xcassets/
├── AnimationSpeed.xcodeproj/
├── Makefile                 # theos 打包 .tipa
├── RebootRootHelper         # TrollStore 重启注入工具
├── control / entitlements.plist
├── Tweak/                   # dylib 源码（独立工程，零依赖）
│   ├── Tweak.m              # 全 hook（纯 ObjC swizzle）
│   ├── Makefile             # clang 一行编译
│   └── control
├── .github/workflows/build.yml   # GitHub Actions 自动编译
├── build.sh                 # 本地 Mac 一键脚本
└── README.md
```

---

## 获取编译产物

### 方式 A：GitHub Actions（一键，推荐）

> **无需 Mac，全程浏览器操作，3 分钟出 .dylib**

1. **Fork** 本仓库到你的 GitHub 账号
2. 进仓库 → **Actions** → 左侧 "Build AnimationSpeedTweak dylib" → **Run workflow**
3. 等 1–3 分钟，绿色 ✅ → 点击 **Artifacts** → 下载 `AnimationSpeedTweak-dylib`
4. 文件传到 iPhone → **TrollFools** → 选目标 App → 注入 `AnimationSpeedTweak.dylib`
5. 重开 App 生效

### 方式 B：本地 Mac（需 Xcode Command Line Tools）

```bash
# 1. 克隆
git clone https://github.com/<your-fork>/AnimationSpeed.git
cd AnimationSpeed

# 2. 仅编译 dylib（无需 theos）
bash build.sh dylib
# 输出: build_output/AnimationSpeedTweak.dylib

# 3. 仅编译 App .tipa（需安装 theos）
bash build.sh tipa
# 或两者都编：
bash build.sh all
```

### 方式 C：TrollStore App 端操作

1. 用 GitHub Actions 或 build.sh 拿到 `AnimationSpeedTweak.dylib`
2. 传到 iPhone 备用
3. 打开 **TrollFools**（TrollStore 内置）
4. 选目标 App（建议先试 SpringBoard）→ 点 **Inject** → 选 `AnimationSpeedTweak.dylib`
5. 重启 / Respring 目标 App

---

## 配置说明

App 端设置好参数后，dylib 实时读取（每秒自动刷新）：

```
/var/Managed Preferences/mobile/com.developlab.animationspeed.plist
```

| 键 | 类型 | 说明 | 默认 |
|----|------|------|------|
| `ViewAnimationFactor` | Double | 全局加速系数（0.001~2.0） | 0.10（10%） |
| `MinDurationMs` | Double | 仅压缩超过此毫秒的动画 | 150 |
| `InstantMode` | Bool | true = 所有动画近 0ms（抢单慎用） | false |
| `ReduceMotion` | Bool | 强制减少动态效果 | false |
| `Categories` | Dict | 各分类开关（true=生效） | 全部 true |
| `Blacklist` | Array | 不加速的 App bundleID 列表 | [] |
| `PerApp` | Dict | bundleID → 系数覆盖 | {} |

---

## 支持的 hook 一览

| 类 | 方法 | 触发场景 |
|----|------|----------|
| UIView（类方法） | `animateWithDuration:*` ×4 | 所有 block 动画 |
| UIView（类方法） | `transitionWithView:` / `transitionFromView:` | 转场动画 |
| CATransaction | `setAnimationDuration:` | Core Animation 底层 |
| UIViewPropertyAnimator | `initWithDuration:*` / `setDuration:` | 属性动画器 |
| UIScrollView | `setContentOffset:animated:` | 滚动动画 |
| UIPresentationController | `presentWithAnimated:` | 全屏自定义转场 |
| UIWindow | `setAnimationDuration:` | 窗口层级动画 |
| UIPageViewController | `setViewControllers:direction:*` | 分页转场 |
| UIDocumentBrowserViewController | `presentDocumentAtURL:*` | 文件浏览器 |
| UINavigationController | `push/pop/setViewControllers:` | 导航推入弹出 |
| UITabBarController | `setSelectedIndex/ViewController:` | Tab 切换 |
| UIViewController | `present/dismiss:*` | 模态弹出 |
| CAAnimation | `setDuration:` | 所有 CA 动画 |
| CALayer | `actionForKey:` | 隐式层动画 |
| UIDynamicAnimator | `addBehavior:` | 物理仿真 |
| UIAccessibility | `isReduceMotionEnabled` | 减少动态开关 |

---

## 安全声明

- 仅缩短合法系统 UI 动画时长，不做任何抢单、定位欺骗、SSL Pinning 绕过或反检测操作
- 所有 hook 均作用于 UIKit/CoreAnimation，不修改网络请求或数据
- InstantMode 仅关闭视觉动画，不改变任何业务逻辑
