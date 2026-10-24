// Tiny synthesiser interface. The web build plays it through the Web Audio
// API; other platforms get a silent stub (no native audio plugin is used so
// the project builds without extra setup).
export 'synth_stub.dart' if (dart.library.js_interop) 'synth_web.dart';

abstract class Synth {
  /// False on platforms with no audio backend (a silent stub).
  bool get supported;

  /// Whether sound can play (browsers need a user gesture first).
  bool get running;

  /// Seconds on the audio clock.
  double get now;

  void unlock();

  /// A pitched note: wave is 'square', 'sawtooth', 'triangle' or 'sine'.
  /// [slide] is the end frequency for a pitch sweep (0 = none).
  void tone(double freq, double start, double dur, String wave, double vol, {double slide = 0});

  /// A burst of filtered noise (drums, swishes, explosions).
  void noise(double start, double dur, double vol, {double lowpass = 8000, double highpass = 0, double sweepTo = 0});

  void setMasterVolume(double v);
}
