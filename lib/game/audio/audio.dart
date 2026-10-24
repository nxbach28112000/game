import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../storage/storage.dart';
import 'synth.dart';

class _Track {
  const _Track(this.bpm, this.roots, this.minor, {this.drums = 0, this.lead = 0, this.sawBass = false});

  final int bpm;
  final List<int> roots; // MIDI root of each bar
  final List<bool> minor;
  final int drums; // 0 none, 1 light, 2 driving, 3 four on the floor
  final int lead; // 0 none, 1 sparse, 2 busy
  final bool sawBass;
}

const _tracks = <String, _Track>{
  'menu': _Track(70, [45, 41, 48, 43], [true, false, false, false], lead: 1),
  'w1': _Track(100, [45, 41, 48, 43], [true, false, false, false], drums: 1, lead: 1),
  'w2': _Track(108, [50, 46, 53, 48], [true, false, false, false], drums: 2, lead: 1),
  'w3': _Track(116, [52, 48, 50, 47], [true, false, false, true], drums: 2, lead: 2),
  'w4': _Track(124, [41, 37, 44, 39], [true, false, false, false], drums: 2, lead: 2),
  'boss': _Track(150, [45, 45, 41, 40], [true, true, false, false], drums: 3, lead: 2, sawBass: true),
};

double _hz(num midi) => 440 * pow(2, (midi - 69) / 12).toDouble();

/// Procedural music and sound effects (no audio files needed). Sounds play on
/// the web build; other platforms are silent.
class GameAudio {
  static final Synth _s = createSynth();
  static String? _track;
  static int _step = 0;
  static double _next = 0;
  static Timer? _timer;
  static bool _muted = false;
  static final _last = <String, double>{};

  static final mutedNotifier = ValueNotifier<bool>(false);

  static bool get muted => _muted;

  static Future<void> init() async {
    _muted = (await storageRead('muted')) == '1';
    mutedNotifier.value = _muted;
    _s.setMasterVolume(_muted ? 0 : .6);
    if (_s.supported) _timer ??= Timer.periodic(const Duration(milliseconds: 30), (_) => _tick());
  }

  static void setMuted(bool m) {
    _muted = m;
    mutedNotifier.value = m;
    _s.setMasterVolume(m ? 0 : .6);
    storageWrite('muted', m ? '1' : '0');
  }

  /// Call from a user gesture (browsers keep audio locked until then).
  static void unlock() {
    _s.unlock();
    if (_s.supported) _timer ??= Timer.periodic(const Duration(milliseconds: 30), (_) => _tick());
  }

  static void music(String? name) {
    if (name == _track) return;
    _track = name;
    _step = 0;
    _next = _s.now + .08;
  }

  static void _tick() {
    final t = _tracks[_track];
    if (t == null || !_s.running) return;
    final dur = 60 / t.bpm / 4;
    if (_next < _s.now) _next = _s.now + .05;
    while (_next < _s.now + .2) {
      _play(t, _step, _next, dur);
      _step++;
      _next += dur;
    }
  }

  static void _play(_Track t, int step, double at, double dur) {
    final bar = (step ~/ 16) % t.roots.length;
    final s = step % 16;
    final root = t.roots[bar];
    final chord = t.minor[bar] ? const [0, 3, 7] : const [0, 4, 7];
    // Bass
    if (s % 4 == 0 || (t.drums >= 2 && s % 4 == 2)) {
      final oct = s % 8 >= 4 && t.drums >= 2 ? 12 : 0;
      _s.tone(_hz(root + oct), at, dur * 3.2, t.sawBass ? 'sawtooth' : 'triangle', t.sawBass ? .16 : .26);
    }
    // Pad: one long chord per bar
    if (s == 0) {
      for (final c in chord) {
        _s.tone(_hz(root + 24 + c), at, dur * 16, 'triangle', .035);
      }
    }
    // Arpeggio
    final fast = t.drums >= 2;
    if (fast || s % 2 == 0) {
      final idx = (s ~/ (fast ? 1 : 2)) % 4;
      final note = root + 24 + chord[const [0, 1, 2, 1][idx]] + (s >= 8 ? 12 : 0);
      _s.tone(_hz(note), at, dur * 1.4, 'square', .03);
    }
    // Lead: a deterministic motif per bar so the loop is stable
    if (t.lead > 0) {
      final hits = t.lead == 2 ? const [0, 3, 6, 8, 10, 12, 14] : const [0, 6, 10];
      final k = hits.indexOf(s);
      if (k >= 0) {
        final r = Random(bar * 31 + t.bpm + k * 7);
        const pent = [0, 3, 5, 7, 10, 12];
        final n = root + 36 + (t.minor[bar] ? pent[r.nextInt(6)] : chord[r.nextInt(3)] + (r.nextBool() ? 12 : 0));
        _s.tone(_hz(n), at, dur * (t.lead == 2 ? 2.2 : 4), t.lead == 2 ? 'square' : 'triangle', t.lead == 2 ? .045 : .07);
      }
    }
    // Drums
    if (t.drums > 0) {
      final kick = t.drums == 3 ? s % 4 == 0 : (s == 0 || s == 8 || (t.drums == 2 && s == 10));
      if (kick) _s.tone(120, at, .14, 'sine', .5, slide: 40);
      if (s == 4 || s == 12) {
        _s.noise(at, .13, .22, highpass: 1500);
        _s.tone(190, at, .08, 'triangle', .12);
      }
      if (s % 2 == 0 || t.drums == 3) _s.noise(at, .03, t.drums == 1 ? .05 : .08, highpass: 7000);
    }
  }

  // ---- sound effects ----
  static void sfx(String name) {
    if (_muted || !_s.running) return;
    final t = _s.now;
    final prev = _last[name] ?? -1;
    if (t - prev < (name == 'hit' ? .05 : .03)) return;
    _last[name] = t;
    switch (name) {
      case 'swing':
        _s.noise(t, .13, .22, lowpass: 7000, highpass: 700, sweepTo: 1600);
      case 'cast':
        _s.tone(520, t, .2, 'sine', .22, slide: 1100);
        _s.tone(780, t + .03, .16, 'triangle', .1, slide: 1500);
      case 'hit':
        _s.noise(t, .07, .28, lowpass: 5000);
        _s.tone(240, t, .1, 'square', .18, slide: 90);
      case 'kill':
        _s.tone(360, t, .2, 'sawtooth', .2, slide: 90);
        _s.noise(t, .16, .2, lowpass: 3000, sweepTo: 300);
      case 'hurt':
        _s.tone(170, t, .24, 'sawtooth', .28, slide: 60);
        _s.noise(t, .1, .2, lowpass: 2500);
      case 'block':
        _s.tone(620, t, .09, 'square', .14);
        _s.noise(t, .05, .15, highpass: 2000);
      case 'jump':
        _s.tone(280, t, .14, 'triangle', .2, slide: 620);
      case 'shield':
        _s.tone(440, t, .3, 'sine', .2, slide: 900);
        _s.tone(660, t + .04, .26, 'sine', .12, slide: 1300);
      case 'boom':
        _s.noise(t, .22, .3, lowpass: 3200, sweepTo: 350);
        _s.tone(130, t, .2, 'sine', .3, slide: 50);
      case 'slam':
        _s.noise(t, .55, .6, lowpass: 1600, sweepTo: 70);
        _s.tone(80, t, .5, 'sine', .6, slide: 32);
      case 'warn':
        for (var i = 0; i < 3; i++) {
          _s.tone(220, t + i * .22, .16, 'square', .14);
        }
      case 'pickup':
        _s.tone(880, t, .09, 'square', .14);
        _s.tone(1320, t + .07, .14, 'square', .14);
      case 'coin':
        _s.tone(990, t, .07, 'square', .14);
        _s.tone(1480, t + .06, .16, 'square', .14);
      case 'levelup':
        for (var i = 0; i < 4; i++) {
          _s.tone(_hz(72 + const [0, 4, 7, 12][i]), t + i * .09, .22, 'square', .17);
        }
      case 'portal':
        _s.tone(330, t, .55, 'sine', .22, slide: 700);
        _s.tone(495, t + .05, .5, 'sine', .14, slide: 1000);
      case 'stage':
        for (var i = 0; i < 3; i++) {
          _s.tone(_hz(67 + const [0, 4, 9][i]), t + i * .12, .3, 'triangle', .22);
        }
      case 'click':
        _s.tone(700, t, .05, 'square', .1);
      case 'heal':
        _s.tone(520, t, .3, 'sine', .22, slide: 800);
      case 'dead':
        _s.tone(420, t, .9, 'sawtooth', .28, slide: 55);
      case 'roar':
        _s.tone(95, t, .9, 'sawtooth', .35, slide: 40);
        _s.noise(t, .7, .3, lowpass: 900, sweepTo: 120);
      case 'victory':
        for (var i = 0; i < 6; i++) {
          _s.tone(_hz(72 + const [0, 4, 7, 12, 7, 12][i]), t + i * .16, i == 5 ? .8 : .24, 'square', .2);
        }
      case 'gameover':
        for (var i = 0; i < 4; i++) {
          _s.tone(_hz(57 - i * 2), t + i * .32, .5, 'triangle', .26);
        }
    }
  }
}
