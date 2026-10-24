import 'dart:convert';

import 'storage/storage.dart';

/// Where each on-screen button sits in the 800x450 game view. The player can
/// rearrange them in Settings; the result is kept on the device.
class ButtonLayout {
  ButtonLayout(Map<String, (double, double)> pos) : pos = {...defaults, ...pos};

  static const _key = 'layout_v1';

  /// id -> (x, y) of the button centre.
  static const defaults = <String, (double, double)>{
    'attack': (745, 385),
    'skill1': (662, 405),
    'skill2': (692, 325),
    'run': (598, 424),
    'jump': (600, 360),
  };
  static const radius = <String, double>{'attack': 36, 'skill1': 28, 'skill2': 28, 'run': 22, 'jump': 22};
  static const labels = <String, String>{
    'attack': 'Đánh',
    'skill1': 'Kỹ năng 1',
    'skill2': 'Kỹ năng 2',
    'run': 'Chạy',
    'jump': 'Nhảy',
  };

  final Map<String, (double, double)> pos;

  (double, double) of(String id) => pos[id]!;

  ButtonLayout copy() => ButtonLayout(Map.of(pos));

  static Future<ButtonLayout> load() async {
    try {
      final s = await storageRead(_key);
      if (s != null) {
        final m = jsonDecode(s) as Map<String, dynamic>;
        final out = <String, (double, double)>{};
        for (final e in m.entries) {
          if (!defaults.containsKey(e.key)) continue;
          final v = e.value as List;
          out[e.key] = ((v[0] as num).toDouble(), (v[1] as num).toDouble());
        }
        return ButtonLayout(out);
      }
    } catch (_) {}
    return ButtonLayout({});
  }

  Future<void> save() =>
      storageWrite(_key, jsonEncode({for (final e in pos.entries) e.key: [e.value.$1, e.value.$2]}));

  Future<void> reset() async {
    pos
      ..clear()
      ..addAll(defaults);
    await storageRemove(_key);
  }
}
