// Tiny key/value store: browser localStorage on web, a JSON file elsewhere.
// Failures are swallowed so the game still runs without saving.
export 'storage_io.dart' if (dart.library.js_interop) 'storage_web.dart';
