import 'synth.dart';

Synth createSynth() => _SilentSynth();

class _SilentSynth implements Synth {
  @override
  bool get running => false;

  @override
  bool get supported => false;

  @override
  double get now => 0;

  @override
  void unlock() {}

  @override
  void tone(double freq, double start, double dur, String wave, double vol, {double slide = 0}) {}

  @override
  void noise(double start, double dur, double vol, {double lowpass = 8000, double highpass = 0, double sweepTo = 0}) {}

  @override
  void setMasterVolume(double v) {}
}
