// Splits tool/ronin_raw.jpg (white background sprite sheet, 8 rows) into
// assets/images/Ronin/<Anim>.png strips of 128x128 frames (feet on the bottom,
// centred), the same layout as the Fighter/Samurai/Shinobi sheets.
import 'dart:io';
import 'dart:math';
import 'package:image/image.dart';

bool isBg(Pixel p) => min(p.r.toInt(), min(p.g.toInt(), p.b.toInt())) > 228;

List<(int, int)> runs(List<bool> mask, int minGap, int minLen) {
  final out = <(int, int)>[];
  int? start;
  var gap = 0;
  for (var i = 0; i <= mask.length; i++) {
    final on = i < mask.length && mask[i];
    if (on) {
      start ??= i;
      gap = 0;
    } else if (start != null) {
      gap++;
      if (gap >= minGap || i == mask.length) {
        final end = i - gap + 1;
        if (end - start >= minLen) out.add((start, end));
        start = null;
        gap = 0;
      }
    }
  }
  return out;
}

void main() {
  final im = decodeJpg(File('tool/ronin_raw.jpg').readAsBytesSync())!;
  final w = im.width, h = im.height;
  // Foreground mask: flood fill the white from the borders, then trim 1px of
  // light fringe so no white halo is left around the sprites.
  final bg = List.filled(w * h, false);
  final st = <int>[];
  void push(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final i = y * w + x;
    if (bg[i] || !isBg(im.getPixel(x, y))) return;
    bg[i] = true;
    st.add(i);
  }
  for (var x = 0; x < w; x++) { push(x, 0); push(x, h - 1); }
  for (var y = 0; y < h; y++) { push(0, y); push(w - 1, y); }
  while (st.isNotEmpty) {
    final i = st.removeLast();
    final x = i % w, y = i ~/ w;
    push(x + 1, y); push(x - 1, y); push(x, y + 1); push(x, y - 1);
  }
  final fg = List.filled(w * h, false);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (bg[y * w + x]) continue;
      var edge = false;
      for (var dy = -1; dy <= 1 && !edge; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx >= 0 && ny >= 0 && nx < w && ny < h && bg[ny * w + nx]) {
            edge = true;
            break;
          }
        }
      }
      final p = im.getPixel(x, y);
      final lum = min(p.r.toInt(), min(p.g.toInt(), p.b.toInt()));
      fg[y * w + x] = !(edge && lum > 185);
    }
  }
  // Row bands from the horizontal projection.
  final rowMask = [
    for (var y = 0; y < h; y++)
      () {
        var c = 0;
        for (var x = 0; x < w; x++) { if (fg[y * w + x]) c++; }
        return c > 2;
      }()
  ];
  final bands = runs(rowMask, 2, 25);
  stdout.writeln('row bands: ${bands.length} $bands');
  // frames[row] = list of (left, top, right, bottom) boxes
  final all = <List<(int, int, int, int)>>[];
  for (final (y0, y1) in bands) {
    final col = [
      for (var x = 0; x < w; x++)
        () {
          for (var y = y0; y < y1; y++) { if (fg[y * w + x]) return true; }
          return false;
        }()
    ];
    var segs = runs(col, 4, 18);
    const expected = [6, 6, 5, 5, 6, 5, 5, 6];
    final want = expected[all.length];
    if (segs.length == 1 && want > 1) {
      // Touching swords: cut the span at the sparsest columns near an even split.
      final (a, b) = segs.first;
      final cnt = [
        for (var x = 0; x < w; x++)
          () {
            var c = 0;
            for (var y = y0; y < y1; y++) { if (fg[y * w + x]) c++; }
            return c;
          }()
      ];
      final cuts = <int>[a];
      for (var k = 1; k < want; k++) {
        final guess = a + ((b - a) * k / want).round();
        var best = guess;
        for (var x = guess - 25; x <= guess + 25; x++) {
          if (cnt[x] < cnt[best]) best = x;
        }
        cuts.add(best);
      }
      cuts.add(b);
      segs = [for (var k = 0; k < want; k++) (cuts[k], cuts[k + 1])];
    }
    final boxes = <(int, int, int, int)>[];
    for (final (x0, x1) in segs) {
      var top = y1, bot = y0;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          if (fg[y * w + x]) { top = min(top, y); bot = max(bot, y); break; }
        }
      }
      boxes.add((x0, top, x1, bot + 1));
    }
    all.add(boxes);
  }
  stdout.writeln('frames per row: ${all.map((r) => r.length).toList()}');
  if (all.length != 8) { stderr.writeln('expected 8 rows'); exit(1); }

  // Scale: standing height 92 in the sheet -> 80px like Samurai (47..127).
  final standH = all[0].map((b) => b.$4 - b.$2).reduce(max);
  var scale = 80 / standH;
  for (final row in all) {
    for (final b in row) {
      final fl = (b.$3 - b.$1) * scale;
      if (fl > 124) scale = scale * 124 / fl;
    }
  }
  stdout.writeln('scale $scale');

  Image cell(int r, int i) {
    final (l, t, rr, bt) = all[r][i];
    final c = Image(width: 128, height: 128, numChannels: 4);
    // Anchor on the feet: x centre of the lowest 10px of the box.
    var fl = rr, fr = l;
    for (var y = max(t, bt - 10); y < bt; y++) {
      for (var x = l; x < rr; x++) {
        if (fg[y * w + x]) { fl = min(fl, x); fr = max(fr, x); }
      }
    }
    final feet = (fl + fr) / 2;
    for (var dy = 0; dy < 128; dy++) {
      for (var dx = 0; dx < 128; dx++) {
        final sx = (feet + (dx - 64) / scale).round();
        final sy = (bt - 1 + (dy - 127) / scale).round();
        if (sx < l || sx >= rr || sy < t || sy >= bt) continue;
        if (!fg[sy * w + sx]) continue;
        c.setPixel(dx, dy, im.getPixel(sx, sy));
      }
    }
    return c;
  }

  void save(String name, List<Image> frames) {
    final s = Image(width: 128 * frames.length, height: 128, numChannels: 4);
    for (var i = 0; i < frames.length; i++) {
      compositeImage(s, frames[i], dstX: i * 128);
    }
    File('assets/images/Ronin/$name.png').writeAsBytesSync(encodePng(s));
  }

  Directory('assets/images/Ronin').createSync(recursive: true);
  List<Image> row(int r) => [for (var i = 0; i < all[r].length; i++) cell(r, i)];
  final idle = row(0), run = row(1), shield = row(6);
  save('Idle', idle);
  save('Run', run);
  save('Walk', run);
  save('Attack_1', row(2));
  save('Attack_2', row(5));
  save('Attack_3', row(4));
  save('Shield', shield);
  save('Dead', row(7));
  save('Hurt', [shield[0], shield[0]]);
  save('Jump', [run[4], run[5]]);
}
