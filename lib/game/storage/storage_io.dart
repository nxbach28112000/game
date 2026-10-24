import 'dart:convert';
import 'dart:io';

File get _file {
  final env = Platform.environment;
  final dir = env['APPDATA'] ?? env['HOME'] ?? Directory.systemTemp.path;
  return File('$dir${Platform.pathSeparator}slime_slayer_save.json');
}

Map<String, dynamic> _readAll() {
  try {
    final f = _file;
    if (f.existsSync()) return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  } catch (_) {}
  return {};
}

void _writeAll(Map<String, dynamic> m) {
  try {
    _file.writeAsStringSync(jsonEncode(m));
  } catch (_) {}
}

Future<String?> storageRead(String key) async => _readAll()[key] as String?;

Future<void> storageWrite(String key, String value) async =>
    _writeAll(_readAll()..[key] = value);

Future<void> storageRemove(String key) async =>
    _writeAll(_readAll()..remove(key));
