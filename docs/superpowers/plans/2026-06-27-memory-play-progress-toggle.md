# 记忆播放进度开关（三态）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 PiliPlus 增加一个三态「记忆播放进度」设置（全局开 / 全局关 / 仅收藏夹关，默认仅收藏夹关），用于控制打开视频时是否自动跳转到上次观看位置。

**Architecture:** 把"是否续播"的决策抽成一个纯函数 `MemoryProgressMode.shouldResume(isFromFav:)`（可单测）。控制器在加载视频源时调用它来决定把 `defaultST`（播放器起播位置）设为历史进度还是 0。"从收藏夹打开"通过既有的 `sourceType == SourceType.fav` 加上收藏夹详情页单点击补充的 `args['fromFav']` 标记来判定。设置项复用既有 `PopupModel` 框架，偏好值以 `enum.index` 存入 Hive。

**Tech Stack:** Flutter / Dart、GetX、Hive（GStorage）、GitHub Actions（subosito/flutter-action）。

## Global Constraints

- 语言/框架：Flutter（Dart）；遵循仓库既有代码风格与 `analysis_options.yaml`（`flutter_lints`）。
- 默认值：`MemoryProgressMode.exceptFav`（枚举 index 必须为 2，因为 Pref 以 index 持久化，且默认回退依赖该顺序）。
- 枚举顺序固定为 `always(0), never(1), exceptFav(2)`，不得重排（重排会改变已持久化用户的设置语义）。
- 只拦截"自动续播"（`data.lastPlayTime` 与本地 `watchProgress` 读取）；**不得**改动本地进度写入（`watchProgress.put`）或服务端历史上报。
- 必须保留显式进度跳转：`args['progress']` 非空分支行为不变。
- "收藏夹"是唯一被 `exceptFav` 特殊处理的来源；`watchLater` / `playlist` / `archive` / `normal` / `file` 一律按"续播"处理。
- 本地无 Flutter/Dart 工具链：`flutter analyze` / `flutter test` 只能在 CI（你的 fork RedGranite/PiliPlus）运行；整包编译验证依赖既有 `build.yml` 的 `flutter build apk`。
- Git：远程 `origin` = `https://github.com/RedGranite/PiliPlus.git`（fork），`upstream` = `https://github.com/bggRGjQaUbCoE/PiliPlus.git`。工作分支 `feat/memory-play-progress-toggle`。

---

## File Structure

| 文件 | 责任 | 操作 |
|---|---|---|
| `lib/models/common/memory_progress_mode.dart` | 三态枚举 + 纯决策方法 `shouldResume` | 新建 |
| `test/models/memory_progress_mode_test.dart` | `shouldResume` 与默认契约的单测 | 新建 |
| `lib/utils/storage_key.dart` | Hive 设置项 key `memoryProgressMode` | 改 |
| `lib/utils/storage_pref.dart` | `Pref.memoryProgressMode` getter | 改 |
| `lib/pages/setting/models/play_settings.dart` | 「播放设置」里的三态选择项 UI | 改 |
| `lib/pages/fav_detail/controller.dart` | 收藏夹单点击补 `fromFav` 标记 | 改 |
| `lib/pages/video/controller.dart` | `_isFromFav` 判定 + gate 两处 `defaultST` | 改 |
| `.github/workflows/analyze_test.yml` | CI 跑 analyze + test（验证用） | 新建 |

---

## Task 1: 纯决策模型 `MemoryProgressMode` + 单测（TDD）

**Files:**
- Create: `lib/models/common/memory_progress_mode.dart`
- Test: `test/models/memory_progress_mode_test.dart`

**Interfaces:**
- Consumes: `package:PiliPlus/models/common/enum_with_label.dart`（既有 mixin `EnumWithLabel`，提供 `String get label`）。
- Produces:
  - `enum MemoryProgressMode with EnumWithLabel { always, never, exceptFav }`，每项带中文 `label`。
  - `bool MemoryProgressMode.shouldResume({required bool isFromFav})` —— Task 5（控制器）与 Task 3/2 会用到。

- [ ] **Step 1: 写失败测试** —— `test/models/memory_progress_mode_test.dart`

```dart
import 'package:PiliPlus/models/common/memory_progress_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MemoryProgressMode.shouldResume', () {
    test('always: 任何来源都续播', () {
      expect(MemoryProgressMode.always.shouldResume(isFromFav: false), isTrue);
      expect(MemoryProgressMode.always.shouldResume(isFromFav: true), isTrue);
    });

    test('never: 任何来源都不续播', () {
      expect(MemoryProgressMode.never.shouldResume(isFromFav: false), isFalse);
      expect(MemoryProgressMode.never.shouldResume(isFromFav: true), isFalse);
    });

    test('exceptFav: 仅非收藏夹来源续播', () {
      expect(
        MemoryProgressMode.exceptFav.shouldResume(isFromFav: false),
        isTrue,
      );
      expect(
        MemoryProgressMode.exceptFav.shouldResume(isFromFav: true),
        isFalse,
      );
    });

    test('持久化契约: 顺序与默认项 index 固定', () {
      // Pref 以 enum.index 存储并默认回退到 index 2，顺序不可变。
      expect(MemoryProgressMode.values.length, 3);
      expect(MemoryProgressMode.always.index, 0);
      expect(MemoryProgressMode.never.index, 1);
      expect(MemoryProgressMode.exceptFav.index, 2);
    });

    test('每项有非空 label', () {
      for (final mode in MemoryProgressMode.values) {
        expect(mode.label, isNotEmpty);
      }
    });
  });
}
```

- [ ] **Step 2: （CI）确认测试失败**

本地无 Flutter 工具链，无法运行。此步在 Task 7 推送后由 `analyze_test.yml` 执行；预期首个 commit 编译失败（`memory_progress_mode.dart` 不存在）。在本地，跳过运行，直接进入 Step 3。

- [ ] **Step 3: 写最小实现** —— `lib/models/common/memory_progress_mode.dart`

```dart
import 'package:PiliPlus/models/common/enum_with_label.dart';

/// 记忆视频播放进度（自动续播）的三种模式。
///
/// 注意：枚举顺序即持久化值（`Pref.memoryProgressMode` 以 `index` 存储），
/// 不得重排。
enum MemoryProgressMode with EnumWithLabel {
  always('全局开启'),
  never('全局关闭'),
  exceptFav('仅收藏夹关闭');

  const MemoryProgressMode(this.label);

  @override
  final String label;

  /// 给定视频的打开来源，是否应自动续播到上次位置。
  bool shouldResume({required bool isFromFav}) => switch (this) {
    MemoryProgressMode.always => true,
    MemoryProgressMode.never => false,
    MemoryProgressMode.exceptFav => !isFromFav,
  };
}
```

- [ ] **Step 4: （CI）确认测试通过** —— 见 Task 6/7；预期 `flutter test` 全绿。

- [ ] **Step 5: Commit**

```bash
git add lib/models/common/memory_progress_mode.dart test/models/memory_progress_mode_test.dart
git commit -m "feat: add MemoryProgressMode tri-state model with shouldResume + tests"
```

---

## Task 2: 设置项 key 与 `Pref` getter

**Files:**
- Modify: `lib/utils/storage_key.dart`（`static const String` 组，`pgcSkipType` 之后）
- Modify: `lib/utils/storage_pref.dart`（import 区 + `pgcSkipType` getter 附近）

**Interfaces:**
- Consumes: `MemoryProgressMode`（Task 1）。
- Produces:
  - `SettingBoxKey.memoryProgressMode` → `'memoryProgressMode'`（String）。
  - `Pref.memoryProgressMode` → `MemoryProgressMode`（默认 `exceptFav`）。

- [ ] **Step 1: 加 key** —— `lib/utils/storage_key.dart`，把

```dart
      pgcSkipType = 'pgcSkipType',
      audioPlayMode = 'audioPlayMode',
```

改成

```dart
      pgcSkipType = 'pgcSkipType',
      memoryProgressMode = 'memoryProgressMode',
      audioPlayMode = 'audioPlayMode',
```

- [ ] **Step 2: 加 import** —— `lib/utils/storage_pref.dart`，在

```dart
import 'package:PiliPlus/models/common/follow_order_type.dart';
```

之后插入

```dart
import 'package:PiliPlus/models/common/memory_progress_mode.dart';
```

- [ ] **Step 3: 加 getter** —— `lib/utils/storage_pref.dart`，在

```dart
  static SkipType get pgcSkipType =>
      SkipType.values[_setting.get(SettingBoxKey.pgcSkipType) ??
          SkipType.skipOnce.index];
```

之后插入

```dart

  static MemoryProgressMode get memoryProgressMode =>
      MemoryProgressMode.values[_setting.get(SettingBoxKey.memoryProgressMode) ??
          MemoryProgressMode.exceptFav.index];
```

- [ ] **Step 4: Commit**

```bash
git add lib/utils/storage_key.dart lib/utils/storage_pref.dart
git commit -m "feat: add memoryProgressMode storage key and Pref getter"
```

> 验证：编译正确性由 Task 7 的 `flutter build apk` 整包编译确认。

---

## Task 3: 「播放设置」三态选择项 UI

**Files:**
- Modify: `lib/pages/setting/models/play_settings.dart`（import 区 + `playSettings` 列表首项）

**Interfaces:**
- Consumes: `MemoryProgressMode`（Task 1）、`Pref.memoryProgressMode`（Task 2）、`SettingBoxKey.memoryProgressMode`（Task 2）、既有 `PopupModel<T>`、`GStorage`。

- [ ] **Step 1: 加 import** —— `lib/pages/setting/models/play_settings.dart`，在

```dart
import 'package:PiliPlus/common/widgets/custom_icon.dart';
```

之后插入

```dart
import 'package:PiliPlus/models/common/memory_progress_mode.dart';
```

- [ ] **Step 2: 插入选择项** —— 把

```dart
List<SettingsModel> get playSettings => [
  const SwitchModel(
    title: '弹幕开关',
```

改成

```dart
List<SettingsModel> get playSettings => [
  PopupModel<MemoryProgressMode>(
    title: '记忆播放进度',
    leading: const Icon(Icons.history),
    value: () => Pref.memoryProgressMode,
    items: MemoryProgressMode.values,
    onSelected: (value, setState) => GStorage.setting
        .put(SettingBoxKey.memoryProgressMode, value.index)
        .whenComplete(setState),
  ),
  const SwitchModel(
    title: '弹幕开关',
```

- [ ] **Step 3: Commit**

```bash
git add lib/pages/setting/models/play_settings.dart
git commit -m "feat: add 记忆播放进度 selector to play settings"
```

> 验证：该 `PopupModel<SkipType>` 写法已在 `extra_settings.dart` 中验证可用；整包编译由 Task 7 确认。

---

## Task 4: 收藏夹单点击补 `fromFav` 标记

**Files:**
- Modify: `lib/pages/fav_detail/controller.dart`（`onViewFav`，约 219–236 行）

**Interfaces:**
- Produces: 从收藏夹详情页打开视频时，路由 `arguments` 始终包含 `'fromFav': true`（连播模式仍附带原有 `sourceType`/`mediaId` 等 keys）。Task 5 的 `_isFromFav` 依赖它。

> `fav_search/controller.dart` 已始终传 `SourceType.fav`，无需改动。

- [ ] **Step 1: 改 `extraArguments`** —— 把

```dart
    PageUtils.toVideoPage(
      bvid: item.bvid,
      cid: item.ugc!.firstCid!,
      cover: item.cover,
      title: item.title,
      extraArguments: isPlayAll.value
          ? {
              'sourceType': SourceType.fav,
              'mediaId': folder.id,
              'oid': item.id,
              'favTitle': folder.title,
              'count': folder.mediaCount,
              'desc': true,
              if (index != null) 'isContinuePlaying': index != 0,
              'isOwner': isOwner,
            }
          : null,
    );
```

改成

```dart
    PageUtils.toVideoPage(
      bvid: item.bvid,
      cid: item.ugc!.firstCid!,
      cover: item.cover,
      title: item.title,
      extraArguments: {
        'fromFav': true,
        if (isPlayAll.value) ...{
          'sourceType': SourceType.fav,
          'mediaId': folder.id,
          'oid': item.id,
          'favTitle': folder.title,
          'count': folder.mediaCount,
          'desc': true,
          if (index != null) 'isContinuePlaying': index != 0,
          'isOwner': isOwner,
        },
      },
    );
```

- [ ] **Step 2: Commit**

```bash
git add lib/pages/fav_detail/controller.dart
git commit -m "feat: tag favorites-opened videos with fromFav flag"
```

---

## Task 5: 在视频控制器中按模式 gate 续播

**Files:**
- Modify: `lib/pages/video/controller.dart`（import 区 + `sourceType` 声明后加 getter + `initFileSource` 约 364 行 + `_setVideoSource` 约 871 行）

**Interfaces:**
- Consumes: `MemoryProgressMode`、`Pref.memoryProgressMode`（Task 2）、`MemoryProgressMode.shouldResume`（Task 1）、既有 `SourceType`、`args`、`sourceType`、`watchProgress`、`data.lastPlayTime`。

- [ ] **Step 1: 加 import** —— 在

```dart
import 'package:PiliPlus/models/common/video/source_type.dart';
```

之后插入

```dart
import 'package:PiliPlus/models/common/memory_progress_mode.dart';
```

- [ ] **Step 2: 加判定 getter** —— 在

```dart
  late SourceType sourceType;
```

之后插入

```dart

  bool get _isFromFav =>
      sourceType == SourceType.fav || args['fromFav'] == true;

  bool get _shouldMemoryProgress =>
      Pref.memoryProgressMode.shouldResume(isFromFav: _isFromFav);
```

- [ ] **Step 3: gate 本地/缓存来源** —— 在 `initFileSource` 里，把

```dart
    if (watchProgress.get(cid.value.toString()) case final int progress?) {
      if (progress >= entry.totalTimeMilli - 400) {
        defaultST = Duration.zero;
      } else {
        defaultST = Duration(milliseconds: progress);
      }
    } else {
      defaultST = Duration.zero;
    }
```

改成

```dart
    final int? localProgress = _shouldMemoryProgress
        ? watchProgress.get(cid.value.toString())
        : null;
    if (localProgress != null && localProgress < entry.totalTimeMilli - 400) {
      defaultST = Duration(milliseconds: localProgress);
    } else {
      defaultST = Duration.zero;
    }
```

- [ ] **Step 4: gate 在线来源** —— 在 `_setVideoSource` 里，把

```dart
      if (!fromReset) {
        final progress = args.remove('progress');
        if (progress != null) {
          defaultST = Duration(milliseconds: progress);
        } else {
          defaultST = Duration(milliseconds: data.lastPlayTime);
        }
      }
```

改成

```dart
      if (!fromReset) {
        final progress = args.remove('progress');
        if (progress != null) {
          defaultST = Duration(milliseconds: progress);
        } else {
          defaultST = Duration(
            milliseconds: _shouldMemoryProgress ? data.lastPlayTime : 0,
          );
        }
      }
```

- [ ] **Step 5: Commit**

```bash
git add lib/pages/video/controller.dart
git commit -m "feat: gate auto-resume by MemoryProgressMode in video controller"
```

> 验证：整包编译由 Task 7 的 `flutter build apk` 确认；行为验证见 Task 7 矩阵。

---

## Task 6: CI 验证 workflow（analyze + test）

**Files:**
- Create: `.github/workflows/analyze_test.yml`

**Interfaces:** 无代码接口；在 push / 手动触发时于 fork 上运行 `flutter analyze` 与 `flutter test`，作为本地无工具链时的真实验证信号。

- [ ] **Step 1: 新建 workflow**

```yaml
name: Analyze & Test

on:
  push:
    paths-ignore:
      - "**.md"
  workflow_dispatch:

jobs:
  analyze-test:
    name: Analyze & Test
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v7

      - name: Setup flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version-file: pubspec.yaml
          cache: true

      - name: Pub get
        run: flutter pub get

      - name: Analyze
        run: flutter analyze

      - name: Test
        run: flutter test
```

> 若 `flutter analyze` 因与本改动无关的既有告警而失败（看日志确认非本次改动文件），把 Analyze 步骤临时缩小到改动文件：
> `flutter analyze lib/models/common/memory_progress_mode.dart lib/pages/video/controller.dart lib/pages/fav_detail/controller.dart lib/utils/storage_pref.dart lib/pages/setting/models/play_settings.dart test/models/memory_progress_mode_test.dart`

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/analyze_test.yml
git commit -m "ci: add analyze + test workflow"
```

---

## Task 7: 推送、CI 构建与验证

**Files:** 无（操作性任务）。

**前置：** fork `RedGranite/PiliPlus` 的 **Settings → Actions** 已启用（fork 默认禁用 Actions，需点一次"I understand my workflows, go ahead and enable them"）。推送需要对 fork 的写权限（`gh auth login` 或已配置的凭据）。

- [ ] **Step 1: 推送分支到 fork**

```bash
git push -u origin feat/memory-play-progress-toggle
```

- [ ] **Step 2: 看 analyze+test 结果**

在 `https://github.com/RedGranite/PiliPlus/actions` 找到 **Analyze & Test** run。
预期：`flutter test` 全绿（含 Task 1 的 5 个用例），`flutter analyze` 无错误。

- [ ] **Step 3: 触发 Android 构建**

fork 的 **Actions → Build → Run workflow**（分支选 `feat/memory-play-progress-toggle`，`build_android` = true）。
或 CLI：

```bash
gh workflow run build.yml --repo RedGranite/PiliPlus --ref feat/memory-play-progress-toggle -f build_android=true
```

预期：job `Release Android` 成功，产出 artifacts `Android_arm64-v8a` 等（证明整包 `flutter build apk` 编译通过）。

- [ ] **Step 4: 下载并安装**

从该 run 的 Artifacts 下载对应架构 APK（一般手机选 `arm64-v8a`）。
> ⚠️ debug 签名，无法覆盖安装官方版：需先卸载官方版（丢该 App 本地数据），或在 fork 配置签名 secret 实现无缝升级。

- [ ] **Step 5: 行为验证矩阵（手动，在设备上）**

| 模式 | 收藏夹打开（单点击/连播/夹内搜索） | 首页/搜索/稍后看/UP主页打开 | 显式时间戳/继续观看卡片 |
|---|---|---|---|
| 全局开启 | 续播 | 续播 | 跳到指定位置 |
| 全局关闭 | 从 0 | 从 0 | 跳到指定位置 |
| 仅收藏夹关闭（默认） | 从 0 | 续播 | 跳到指定位置 |

操作：看一个视频到中途 → 退出 → 按上表从不同入口重新打开，核对起播位置。切换设置项（设置 → 播放设置 → 记忆播放进度）后复测。

---

## Self-Review

**1. Spec coverage（逐条对照 spec）**
- 三态枚举 + 默认 exceptFav → Task 1、2 ✓
- 收藏夹判定（含单点击补标记） → Task 4、Task 5 Step 2 ✓
- gate 在线 + 本地两处 → Task 5 Step 3/4 ✓
- 保留显式 `args['progress']` → Task 5 Step 4 未动该分支 ✓
- 设置项 UI 位于播放设置 → Task 3 ✓
- 不停止记录/历史上报 → 计划未触碰 `watchProgress.put` 与上报逻辑 ✓
- CI 构建 + 签名注意点 → Task 7 ✓
- 验证（analyze/test/build/行为矩阵） → Task 6、7 ✓

**2. Placeholder scan:** 无 TBD/TODO；每个代码步骤均给出完整代码与前后对照。本地无工具链导致的"运行测试"步骤已明确改由 CI 执行，非占位。

**3. Type consistency:**
- `MemoryProgressMode.shouldResume({required bool isFromFav}) -> bool`：Task 1 定义，Task 5 `_shouldMemoryProgress` 调用，签名一致 ✓
- `Pref.memoryProgressMode -> MemoryProgressMode`：Task 2 定义，Task 3/5 使用 ✓
- `SettingBoxKey.memoryProgressMode -> String`：Task 2 定义，Task 3 使用 ✓
- 枚举顺序/默认 index：Task 1 测试钉死、Task 2 默认回退一致（exceptFav.index = 2）✓
