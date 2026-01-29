#!/usr/bin/env bash
# 将 iOS 最低版本统一设为 16.7，供 MOP 构建使用（适配范围 16.7+～最新）。
# 用法：在项目根目录执行 ./scripts/ios_set_deployment_target_16_7.sh
#       或在 mobile/ 下执行 ../scripts/ios_set_deployment_target_16_7.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# 支持从项目根或 mobile 下运行
if [[ -d "$ROOT_DIR/mobile/ios" ]]; then
  IOS_DIR="$ROOT_DIR/mobile/ios"
elif [[ -d "$ROOT_DIR/ios" ]]; then
  IOS_DIR="$ROOT_DIR/ios"
else
  echo "❌ 未找到 ios 目录（请在本仓库根目录或 mobile/ 下执行）"
  exit 1
fi

PODFILE="$IOS_DIR/Podfile"
PBXPROJ="$IOS_DIR/Runner.xcodeproj/project.pbxproj"
TARGET_VERSION="16.7"

echo "=========================================="
echo "iOS 最低版本配置 -> $TARGET_VERSION"
echo "=========================================="
echo "ios 目录: $IOS_DIR"
echo ""

if [[ ! -f "$PODFILE" ]]; then
  echo "⚠️ 未找到 $PODFILE"
  echo "   请先在 Mac 上执行: flutter pub get && flutter build ios --no-codesign"
  echo "   生成 ios 产物后再运行本脚本。"
  exit 1
fi

if [[ ! -f "$PBXPROJ" ]]; then
  echo "⚠️ 未找到 $PBXPROJ"
  echo "   请先完成 Flutter iOS 构建流程以生成 Xcode 工程。"
  exit 1
fi

# 1. Podfile: platform :ios, '17.0'
# sed -i: macOS 用 sed -i '' 或 sed -i.bak；GNU 用 sed -i 或 sed -i.bak。用 .bak 后删除可兼容
if grep -qE "^# *platform :ios" "$PODFILE"; then
  sed -i.bak -E "s|^# *platform :ios, *'[^']*'|platform :ios, '$TARGET_VERSION'|" "$PODFILE" 2>/dev/null || \
  sed -i '' -E "s|^# *platform :ios, *'[^']*'|platform :ios, '$TARGET_VERSION'|" "$PODFILE"
  echo "✅ Podfile: 已取消注释并设置 platform :ios, '$TARGET_VERSION'"
elif grep -qE "^platform :ios" "$PODFILE"; then
  sed -i.bak -E "s|^platform :ios, *'[^']*'|platform :ios, '$TARGET_VERSION'|" "$PODFILE" 2>/dev/null || \
  sed -i '' -E "s|^platform :ios, *'[^']*'|platform :ios, '$TARGET_VERSION'|" "$PODFILE"
  echo "✅ Podfile: 已设置 platform :ios, '$TARGET_VERSION'"
else
  echo "⚠️ Podfile 中未找到 platform :ios，请手动添加: platform :ios, '$TARGET_VERSION'"
fi
rm -f "${PODFILE}.bak" 2>/dev/null || true

# 2. Podfile: post_install 统一 Pod 的 IPHONEOS_DEPLOYMENT_TARGET
MARKER="MOP: enforce iOS 16.7+ for all pods"
if grep -q "$MARKER" "$PODFILE"; then
  echo "✅ Podfile: post_install 已存在，跳过"
else
  cat >> "$PODFILE" << 'POSTINSTALL'

# MOP: enforce iOS 16.7+ for all pods
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.7'
    end
  end
end
POSTINSTALL
  echo "✅ Podfile: 已追加 post_install，统一 Pod 最低版本为 16.7"
fi

# 3. project.pbxproj: Runner 的 IPHONEOS_DEPLOYMENT_TARGET
if grep -q "IPHONEOS_DEPLOYMENT_TARGET" "$PBXPROJ"; then
  sed -i.bak -E "s|IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;|IPHONEOS_DEPLOYMENT_TARGET = $TARGET_VERSION;|g" "$PBXPROJ" 2>/dev/null || \
  sed -i '' -E "s|IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;|IPHONEOS_DEPLOYMENT_TARGET = $TARGET_VERSION;|g" "$PBXPROJ"
  echo "✅ project.pbxproj: 已统一 IPHONEOS_DEPLOYMENT_TARGET = $TARGET_VERSION"
  rm -f "${PBXPROJ}.bak" 2>/dev/null || true
else
  echo "⚠️ project.pbxproj 中未找到 IPHONEOS_DEPLOYMENT_TARGET，请检查 Xcode 工程"
fi

echo ""
echo "=========================================="
echo "✅ iOS 16.7 最低版本配置完成"
echo "=========================================="
