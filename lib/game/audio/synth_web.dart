import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'synth.dart';

Synth createSynth() => _WebSynth();

@JS('AudioContext')
extension type _Ctx._(JSObject _) implements JSObject {
  external _Ctx();
  external double get currentTime;
  external double get sampleRate;
  external _Node get destination;
  external String get state;
  external _Osc createOscillator();
  external _Gain createGain();
  external _Filter createBiquadFilter();
  external _Source createBufferSource();
  external _Buffer createBuffer(int channels, int length, double rate);
  external JSPromise<JSAny?> resume();
}

extension type _Node._(JSObject _) implements JSObject {
  external void connect(_Node to);
}

extension type _Param._(JSObject _) implements JSObject {
  external set value(double v);
  external void setValueAtTime(double v, double t);
  external void linearRampToValueAtTime(double v, double t);
  external void exponentialRampToValueAtTime(double v, double t);
}

extension type _Osc._(JSObject _) implements _Node {
  external set type(String t);
  external _Param get frequency;
  external void start(double t);
  external void stop(double t);
}

extension type _Gain._(JSObject _) implements _Node {
  external _Param get gain;
}

extension type _Filter._(JSObject _) implements _Node {
  external set type(String t);
  external _Param get frequency;
}

extension type _Buffer._(JSObject _) implements JSObject {
  external JSFloat32Array getChannelData(int ch);
}

extension type _Source._(JSObject _) implements _Node {
  external set buffer(_Buffer b);
  external void start(double t);
  external void stop(double t);
}

class _WebSynth implements Synth {
  _Ctx? _ctx;
  _Gain? _master;
  _Buffer? _noise;
  double _vol = .6;

  _Ctx? get _c {
    if (_ctx != null) return _ctx;
    try {
      final c = _Ctx();
      final m = c.createGain();
      m.gain.value = _vol;
      m.connect(c.destination);
      _master = m;
      final n = c.createBuffer(1, (c.sampleRate * 1.5).round(), c.sampleRate);
      final Float32List data = n.getChannelData(0).toDart;
      final r = Random(7);
      for (var i = 0; i < data.length; i++) {
        data[i] = r.nextDouble() * 2 - 1;
      }
      _noise = n;
      return _ctx = c;
    } catch (_) {
      return null;
    }
  }

  @override
  bool get running => _ctx?.state == 'running';

  @override
  bool get supported => true;

  @override
  double get now => _ctx?.currentTime ?? 0;

  @override
  void unlock() {
    try {
      final c = _c;
      if (c != null && c.state != 'running') c.resume();
    } catch (_) {}
  }

  @override
  void setMasterVolume(double v) {
    _vol = v;
    _master?.gain.value = v;
  }

  @override
  void tone(double freq, double start, double dur, String wave, double vol, {double slide = 0}) {
    final c = _c;
    if (c == null || !running) return;
    final t = max(start, c.currentTime);
    final o = c.createOscillator();
    o.type = wave;
    o.frequency.setValueAtTime(freq, t);
    if (slide > 0) o.frequency.exponentialRampToValueAtTime(slide, t + dur);
    final g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(vol, t + min(.015, dur / 3));
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g);
    g.connect(_master!);
    o.start(t);
    o.stop(t + dur + .05);
  }

  @override
  void noise(double start, double dur, double vol, {double lowpass = 8000, double highpass = 0, double sweepTo = 0}) {
    final c = _c;
    if (c == null || !running) return;
    final t = max(start, c.currentTime);
    final s = c.createBufferSource();
    s.buffer = _noise!;
    final lp = c.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.setValueAtTime(lowpass, t);
    if (sweepTo > 0) lp.frequency.exponentialRampToValueAtTime(sweepTo, t + dur);
    final g = c.createGain();
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    s.connect(lp);
    var last = lp;
    if (highpass > 0) {
      final hp = c.createBiquadFilter();
      hp.type = 'highpass';
      hp.frequency.setValueAtTime(highpass, t);
      lp.connect(hp);
      last = hp;
    }
    last.connect(g);
    g.connect(_master!);
    s.start(t);
    s.stop(t + dur + .05);
  }
}
