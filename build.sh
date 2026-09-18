#!/bin/bash
# build.sh — 本地 Mac 一键编译（需要 Xcode Command Line Tools）
# 用法: bash build.sh [dylib|tipa|all]
set -e

THEOS="${THEOS:-/opt/theos}"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
ARCH="arm64"
DEPLOY="14.0"

CMD="${1:-all}"
BUILD_DIR="$(pwd)/build_output"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "=== SDK: $SDK ==="

# ── dylib ──────────────────────────────────────────────────────────────────
build_dylib() {
    echo ""
    echo ">>> Building dylib (pure clang, NO theos)..."
    cd Tweak
    clang -arch "$ARCH" -dynamiclib \
        -isysroot "$SDK" \
        -miphoneos-version-min="$DEPLOY" \
        -undefined dynamic_lookup -fobjc-arc \
        -framework Foundation -framework UIKit -framework QuartzCore \
        -o AnimationSpeedTweak.dylib Tweak.m
    echo "    dylib size: $(du -h AnimationSpeedTweak.dylib | cut -f1)"
    cp AnimationSpeedTweak.dylib "$BUILD_DIR/"
    cd ..
}

# ── .tipa (需要 theos) ─────────────────────────────────────────────────────
build_tipa() {
    if [ ! -d "$THEOS" ]; then
        echo "⚠️  theos not found at $THEOS，skipping .tipa build"
        echo "   Install theos: git clone https://github.com/theos/theos.git /opt/theos"
        return 0
    fi
    echo ""
    echo ">>> Building .tipa (theos + Xcode project)..."
    make package -j"$(sysctl -n hw.ncpu)" 2>&1
    # make 输出的 ipa 自动改名为 .tipa（Makefile 里 after-package 已处理）
    find . -name "*.tipa" -newer AnimationSpeed/Makefile -maxdepth 2 \
        -exec cp {} "$BUILD_DIR/" \;
}

# ── 主流程 ──────────────────────────────────────────────────────────────────
if [ "$CMD" = "dylib" ] || [ "$CMD" = "all" ]; then build_dylib; fi
if [ "$CMD" = "tipa"  ] || [ "$CMD" = "all" ]; then build_tipa;  fi

echo ""
echo "=== Output in ./build_output/ ==="
ls -lh "$BUILD_DIR/"
echo ""
echo "Done. Files:"
for f in "$BUILD_DIR"/*; do echo "  $f"; done
