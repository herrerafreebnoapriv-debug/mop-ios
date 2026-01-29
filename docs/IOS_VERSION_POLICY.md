# iOS 版本兼容策略

## 一、适配范围

| 项目 | 要求 |
|------|------|
| **最低版本** | iOS 16.7 |
| **最高版本** | 当前最新（随 Xcode / SDK 更新，如 iOS 18.x） |
| **向下兼容** | 在 16.7～最新版之间，均需保证可安装、可运行 |

即：**仅支持 iOS 16.7+，且在该范围内向下兼容**。

## 二、真机测试与最低版本的关系

- **真机测试环境**：iOS 16.7.11 等 16.7+ 设备均可安装、运行。
- **正式支持范围**：iOS 16.7+

因此：
- **iOS 16.7.11 设备可以安装** 本 App，可直接用于最低版本验证与日常测试。
- 若需覆盖「最新系统」行为，建议额外保留一台当前最新 iOS 真机或模拟器。

## 三、配置位置（须一致）

以下三处需统一为 **16.7**：

1. **Podfile**（`ios/Podfile`）
   - `platform :ios, '16.7'`
   - 若为注释则取消注释并改为 `'16.7'`。

2. **Podfile `post_install`**
   - 为所有 Pod 设置 `IPHONEOS_DEPLOYMENT_TARGET = '16.7'`，避免个别依赖拉低最低版本。

3. **Xcode 工程**（`ios/Runner.xcodeproj/project.pbxproj`）
   - Runner 的 Debug / Release / Profile 中 `IPHONEOS_DEPLOYMENT_TARGET` 均为 `16.7`。

构建前若未统一，可能出现「部分依赖要求更高版本」或「真机最低版本与预期不符」等问题。

## 四、自动化脚本

在 **Mac** 上执行 iOS 构建前，可先运行：

```bash
# 在项目根目录
./scripts/ios_set_deployment_target_16_7.sh
```

或在 `mobile/` 下：

```bash
../scripts/ios_set_deployment_target_16_7.sh
```

脚本会：
- 检查 `ios/Podfile`、`ios/Runner.xcodeproj/project.pbxproj` 是否存在；
- 将 `platform :ios` 与 `IPHONEOS_DEPLOYMENT_TARGET` 统一为 **16.7**；
- 在 Podfile 中追加/复用 `post_install`，为所有 Pod 设置最低版本 16.7。

**注意**：  
- 首次 iOS 构建需先 `flutter pub get` 且生成 `ios/`（如通过 `flutter build ios` 或 `flutter run`），否则脚本会提示先完成 Flutter 构建流程再执行。

## 五、依赖最低版本（参考）

| 依赖 | 最低 iOS |
|------|----------|
| jitsi_meet_flutter_sdk | 15.1 |
| mobile_scanner | 13+ |
| Flutter 默认模板 | 多为 11.0 / 12.0 |

本项目取 **16.7** 作为统一最低版本，高于上述依赖，无冲突。

## 六、与「最新版本」的向下兼容

- 使用 **当前 Xcode 所带最新 iOS SDK** 构建，即可支持到「当前最新系统版本」。
- 若使用仅在新系统才有的 API，需加 `@available(iOS X, *)` 等条件，或通过运行时判断，避免在 iOS 16.7 上崩溃。
- 常规 Flutter / 插件用法在 16.7～最新版之间通常无额外适配，主要注意少用未标注兼容的 native 新 API。

## 七、简要检查清单

- [ ] Podfile 中 `platform :ios, '16.7'`
- [ ] Podfile `post_install` 中所有 Pod `IPHONEOS_DEPLOYMENT_TARGET = '16.7'`
- [ ] `project.pbxproj` 中 Runner 的 `IPHONEOS_DEPLOYMENT_TARGET = 16.7`
- [ ] 真机最低版本验证使用 **iOS 16.7+** 设备（如 16.7.11）

---

**文档更新**：按当前策略维护；构建流程或 Xcode 升级后若有变更再更新此文档。
