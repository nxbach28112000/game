import 'dart:js_interop';
import 'dart:js_interop_unsafe';

JSObject? get _ls {
  try {
    return globalContext['localStorage'] as JSObject?;
  } catch (_) {
    return null;
  }
}

Future<String?> storageRead(String key) async {
  try {
    final v = _ls?.callMethod('getItem'.toJS, key.toJS);
    return (v as JSString?)?.toDart;
  } catch (_) {
    return null;
  }
}

Future<void> storageWrite(String key, String value) async {
  try {
    _ls?.callMethod('setItem'.toJS, key.toJS, value.toJS);
  } catch (_) {}
}

Future<void> storageRemove(String key) async {
  try {
    _ls?.callMethod('removeItem'.toJS, key.toJS);
  } catch (_) {}
}
