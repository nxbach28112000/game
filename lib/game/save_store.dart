import 'dart:convert';

import 'storage/storage.dart';

/// Persistent data: the run checkpoint (taken at the start of each stage) and
/// lifetime records shown on the main menu.
class SaveStore {
  static const _runKey = 'run_v1', _recKey = 'records_v1';

  static Future<Map<String, dynamic>?> loadRun() => _load(_runKey);

  static Future<void> saveRun(Map<String, dynamic> run) =>
      storageWrite(_runKey, jsonEncode(run));

  static Future<void> clearRun() => storageRemove(_runKey);

  static Future<Map<String, dynamic>> loadRecords() async =>
      await _load(_recKey) ?? {'bestStage': 0, 'kills': 0, 'wins': 0};

  static Future<void> addRecords({int stage = 0, int kills = 0, bool win = false}) async {
    final r = await loadRecords();
    r['bestStage'] = (r['bestStage'] as int) > stage ? r['bestStage'] : stage;
    r['kills'] = (r['kills'] as int) + kills;
    if (win) r['wins'] = (r['wins'] as int) + 1;
    await storageWrite(_recKey, jsonEncode(r));
  }

  static Future<Map<String, dynamic>?> _load(String key) async {
    try {
      final s = await storageRead(key);
      if (s == null) return null;
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
