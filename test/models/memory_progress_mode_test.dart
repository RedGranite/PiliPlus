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
