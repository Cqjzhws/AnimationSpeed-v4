# 独立可注入 dylib 构建（无 CydiaSubstrate 依赖）
# 用 clang 直接编译，TrollFools 注入任意 App 即可生效
#
# 用法（macOS + Xcode 命令行工具）：
#   make
# 产物：AnimationSpeedTweak.dylib

SDK ?= $(shell xcrun --sdk iphoneos --show-sdk-path)
MINVER ?= 14.0

AnimationSpeedTweak.dylib: Tweak.m
	clang -arch arm64 -dynamiclib \
	  -isysroot "$(SDK)" -miphoneos-version-min=$(MINVER) \
	  -undefined dynamic_lookup -fobjc-arc \
	  -framework Foundation \
	  -o AnimationSpeedTweak.dylib Tweak.m

clean:
	rm -f AnimationSpeedTweak.dylib

.PHONY: clean
