// Turns the AI sheet (baked checkerboard, 5x2 attack frames) into a clean
// transparent strip: assets/images/Hero/Attack.png (10 frames of 440x300).
import 'dart:io';
import 'dart:math';
import 'package:image/image.dart';

const fw = 440, fh = 300;
// Per frame: row, feet centre x, segment [left, right] to keep.
const frames = [
  (0, 197, 0, 296), (0, 425, 296, 530), (0, 648, 530, 842),
  (0, 925, 842, 1140), (0, 1197, 1140, 1408),
  (1, 190, 0, 316), (1, 428, 316, 511), (1, 655, 511, 768),
  (1, 878, 768, 1036), (1, 1157, 1036, 1408),
];

bool isBg(Pixel p) {
  final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
  final mx = max(r, max(g, b)), mn = min(r, min(g, b));
  return mx - mn < 16 && mx >= 70 && mx <= 160;
}

void main() {
  final im = decodePng(File('tool/attack_raw.png').readAsBytesSync())!;
  final w = im.width, h = im.height;
  final seen = List.filled(w * h, false);
  final stack = <int>[];
  void push(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final i = y * w + x;
    if (seen[i] || !isBg(im.getPixel(x, y))) return;
    seen[i] = true;
    stack.add(i);
  }
  for (var x = 0; x < w; x++) { push(x, 0); push(x, h - 1); }
  for (var y = 0; y < h; y++) { push(0, y); push(w - 1, y); }
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    final x = i % w, y = i ~/ w;
    push(x + 1, y); push(x - 1, y); push(x, y + 1); push(x, y - 1);
  }
  // Enclosed background pockets (between legs, arms...) inside the figure too.
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!seen[y * w + x] && isBg(im.getPixel(x, y))) {
        // only if neighbours are also bg-like in a 5px radius (avoid blade grey)
        var all = true;
        for (var dy = -3; dy <= 3 && all; dy += 3) {
          for (var dx = -3; dx <= 3; dx += 3) {
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            if (!isBg(im.getPixel(nx, ny))) { all = false; break; }
          }
        }
        if (all) seen[y * w + x] = true;
      }
    }
  }
  // Gemini watermark sparkle, and checker pixels blended into the glow frames.
  bool inFx(int x, int y) => y < 430 && x > 530 && x < 1408;
  final clean = Image(width: w, height: h, numChannels: 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (x > 1250 && x < 1335 && y > 600 && y < 690) continue;
      if (seen[y * w + x] || (inFx(x, y) && isBg(im.getPixel(x, y)) && im.getPixel(x, y).r > 108)) continue;
      clean.setPixel(x, y, im.getPixel(x, y));
    }
  }
  final strip = Image(width: fw * frames.length, height: fh, numChannels: 4);
  for (var n = 0; n < frames.length; n++) {
    final (row, cx, l, r) = frames[n];
    final y0 = row == 0 ? 130 : 430;
    for (var y = 0; y < fh; y++) {
      for (var x = 0; x < fw; x++) {
        final sx = cx - fw ~/ 2 + x, sy = y0 + y;
        if (sx < l || sx >= r || sx < 0 || sx >= w || sy >= h) continue;
        strip.setPixel(n * fw + x, y, clean.getPixel(sx, sy));
      }
    }
  }
  File('assets/images/Hero/Attack.png').writeAsBytesSync(encodePng(strip));
  // Preview on green to eyeball the cut-out.
  final prev = Image(width: strip.width, height: fh, numChannels: 4);
  fill(prev, color: ColorRgba8(40, 160, 60, 255));
  compositeImage(prev, strip);
  File('tool/preview_hero.png').writeAsBytesSync(encodePng(prev));
}
