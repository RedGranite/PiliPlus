# 记忆播放进度开关（三态）设计文档

- 日期：2026-06-27
- 目标仓库：PiliPlus（Flutter / Dart），fork 自 `bggRGjQaUbCoE/PiliPlus`
- 交付方式：推送到用户 fork，使用仓库自带 GitHub Actions（`build.yml`）手动触发构建 Android APK

## 1. 背景与问题

PiliPlus 提供"记忆视频播放进度"功能：打开视频时自动跳转到上次观看位置。但**没有提供关闭开关**。用户希望增加一个开关，并且需要三种状态而非简单的开/关。

### 现有实现（已定位）

播放进度（"续播"）来自两个来源，均在 [`lib/pages/video/controller.dart`](../../../lib/pages/video/controller.dart)：

- **在线视频**（约 867–874 行）：`defaultST = Duration(milliseconds: data.lastPlayTime)`，其中 `data.lastPlayTime` 是 playurl API 返回的服务端历史进度。
- **本地/缓存（下载）视频**（约 364–372 行，`initFileSource`）：从本地 `GStorage.watchProgress` 读取毫秒数。

`defaultST` 是播放器加载时 seek 到的位置。控制器另有显式进度入口：`args['progress']`（约 868 行），用于历史卡片、评论时间戳等"用户主动指定位置"的场景。

控制器在 `onInit`（约 400 行）已经解析出导航来源：
```dart
sourceType = args['sourceType'] ?? SourceType.normal;
```

## 2. 需求：三态开关

新增枚举 `MemoryProgressMode`，默认 `exceptFav`：

| 枚举值 | 中文标签 | 行为 |
|---|---|---|
| `always` | 全局开启 | 所有视频都续播（等同现状） |
| `never` | 全局关闭 | 所有视频都从头播放 |
| `exceptFav`（默认） | 仅收藏夹关闭 | 从收藏夹打开的视频从头播放；其他途径打开的视频续播 |

## 3. 设计决策

1. **只拦截"跳转到上次位置"的动作，不停止记录。** 关闭时把 `defaultST` 置 0，但本地 `watchProgress.put(...)` 与服务端历史上报保持不变。好处：完全可逆（切回开启进度仍在），且不影响跨设备观看历史。
2. **保留显式进度跳转。** `args['progress']` 非空时（用户主动点的时间戳/继续观看卡片）始终生效，不受开关影响。开关只作用于"自动续播"分支（`data.lastPlayTime` 与本地 `watchProgress` 读取）。
3. **"收藏夹"是唯一的特殊途径。** 稍后看（`watchLater`）、播放列表（`playlist`）、UP 主投稿（`archive`）、普通（`normal`）等在 `exceptFav` 模式下都照常续播。
4. **默认 `exceptFav`** —— 这是用户本人想要的默认行为。

### "从收藏夹打开"如何判定

控制器内统一判定：
```dart
bool get _isFromFav =>
    sourceType == SourceType.fav || args['fromFav'] == true;
```

覆盖情况：

| 入口 | 当前是否带 `SourceType.fav` | 处理 |
|---|---|---|
| 收藏夹内搜索 [`fav_search/controller.dart:61`](../../../lib/pages/fav_search/controller.dart) | 是（始终） | 无需改动 |
| 收藏夹详情 - 连播模式 [`fav_detail/controller.dart:219`](../../../lib/pages/fav_detail/controller.dart) | 是（`isPlayAll == true` 时） | 无需改动 |
| 收藏夹详情 - 单个点击 | 否（`extraArguments` 为 `null`） | **补 `'fromFav': true` 标记** |

> 不直接给单点击场景设 `sourceType = SourceType.fav`，因为那会让 `isPlayAll` 变为 true（[controller.dart:402](../../../lib/pages/video/controller.dart)），改变连播行为。用独立的轻量 `fromFav` 标记避免副作用。

## 4. 代码改动清单（6 处，均在既有框架内）

### 4.1 新增枚举 `lib/models/common/memory_progress_mode.dart`
```dart
import 'package:PiliPlus/models/common/enum_with_label.dart';

enum MemoryProgressMode with EnumWithLabel {
  always('全局开启'),
  never('全局关闭'),
  exceptFav('仅收藏夹关闭');

  @override
  final String label;

  const MemoryProgressMode(this.label);
}
```

### 4.2 `lib/utils/storage_key.dart`
新增 key（与现有 `pgcSkipType` 等同列表）：
```dart
memoryProgressMode = 'memoryProgressMode',
```

### 4.3 `lib/utils/storage_pref.dart`
新增 getter（镜像 `pgcSkipType` 的写法，存 `enum.index`）：
```dart
static MemoryProgressMode get memoryProgressMode =>
    MemoryProgressMode.values[_setting.get(SettingBoxKey.memoryProgressMode) ??
        MemoryProgressMode.exceptFav.index];
```
需要 `import` 新枚举。

### 4.4 `lib/pages/setting/models/play_settings.dart`
在播放设置列表新增（镜像现有 `PopupModel<SkipType>`）：
```dart
PopupModel<MemoryProgressMode>(
  title: '记忆播放进度',
  leading: const Icon(Icons.history),
  value: () => Pref.memoryProgressMode,
  items: MemoryProgressMode.values,
  onSelected: (value, setState) => GStorage.setting
      .put(SettingBoxKey.memoryProgressMode, value.index)
      .whenComplete(setState),
),
```
需要 `import` 新枚举。

### 4.5 `lib/pages/fav_detail/controller.dart`（`onViewFav`，约 219 行）
让单个点击也带上 `fromFav` 标记（连播分支可保留原有 keys）：
```dart
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
```

### 4.6 `lib/pages/video/controller.dart`
新增 helper：
```dart
bool get _shouldMemoryProgress => switch (Pref.memoryProgressMode) {
      MemoryProgressMode.always => true,
      MemoryProgressMode.never => false,
      MemoryProgressMode.exceptFav => !_isFromFav,
    };

bool get _isFromFav =>
    sourceType == SourceType.fav || args['fromFav'] == true;
```
gate 两处自动续播：
- **在线视频**（约 872 行）：
  ```dart
  defaultST = Duration(
    milliseconds: _shouldMemoryProgress ? data.lastPlayTime : 0,
  );
  ```
- **本地/缓存视频**（`initFileSource`，约 364–372 行）：`_shouldMemoryProgress == false` 时直接 `defaultST = Duration.zero`，不读取 `watchProgress`。

> 显式 `args['progress']` 分支（约 869 行）保持不变。
> 需要 `import` 新枚举。

## 5. 交付与构建（GitHub Actions）

CI 现状（[`.github/workflows/build.yml`](../../../.github/workflows/build.yml)）：
- Android job 在 `workflow_dispatch` 且 `build_android == 'true'` 时构建 —— **fork 上手动触发可用**（PR 触发条件限定了原仓库名，不影响手动构建）。
- 构建步骤会运行 `lib/scripts/build.ps1 android` 自动生成 `pili_release.json`（该文件被 gitignore，由脚本在构建时产生），**无需任何 secret**。
- 未配置签名 secret 时，`android/app/build.gradle.kts` 的 release 构建回退到 debug 签名（`signingConfig = config ?: signingConfigs["debug"]`）。

操作步骤：
1. 在 GitHub fork `bggRGjQaUbCoE/PiliPlus`（若尚未 fork）。
2. 把本地改动推送到 fork。
3. fork 的 **Actions → Build → Run workflow**，`build_android` 保持 true，触发。
4. 构建完成后从 workflow run 的 Artifacts 下载分架构 APK（`arm64-v8a` / `armeabi-v7a` / `x86_64`）。

### 已知注意点（签名）
- 默认 debug 签名的 APK 与官方发布版签名不同，**无法覆盖安装**：需先卸载官方版（会丢失该 App 本地数据），或在 fork 配置自己的 keystore secret（`SIGN_KEYSTORE_BASE64` / `KEYSTORE_PASSWORD` / `KEY_ALIAS` / `KEY_PASSWORD`）实现无缝升级。

## 6. 验证

- `flutter analyze` 无新增告警/错误。
- CI 构建成功并产出 APK 产物。
- 行为验证（三态）：
  - `always`：收藏夹打开 + 首页/搜索打开，均续播。
  - `never`：两种途径均从头播放。
  - `exceptFav`（默认）：收藏夹（单点击、连播、收藏夹内搜索）打开 → 从头；首页/搜索/稍后看/UP 主页打开 → 续播。
  - 显式时间戳/继续观看卡片：任意模式下仍跳转到指定位置。

## 7. 不做（YAGNI）

- 不停止本地进度记录与服务端历史上报。
- 不为"稍后看 / 播放列表"等其他途径单独加状态（需求仅区分收藏夹）。
- 不做 APK 二进制 patch / Xposed 外挂（Flutter AOT 产物不可行，已在方案讨论中排除）。
