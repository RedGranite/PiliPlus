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
