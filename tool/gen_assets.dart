// Generates placeholder pixel-art PNGs into assets/images.
// Run: dart run tool/gen_assets.dart
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

typedef Img = img.Image;

img.Color c(int argb) => img.ColorRgba8(
    (argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF, (argb >> 24) & 0xFF);

Img blank(int w, int h) => Img(width: w, height: h, numChannels: 4);

void r(Img im, int x, int y, int w, int h, int col) {
  if (w <= 0 || h <= 0) return;
  img.fillRect(im,
      x1: x, y1: y, x2: x + w - 1, y2: y + h - 1, color: c(col));
}

void px(Img im, int x, int y, int col) => r(im, x, y, 1, 1, col);

void ellipse(Img im, double cx, double cy, double rx, double ry, int col) {
  for (var y = (cy - ry).floor(); y <= (cy + ry).ceil(); y++) {
    for (var x = (cx - rx).floor(); x <= (cx + rx).ceil(); x++) {
      final dx = (x + .5 - cx) / rx, dy = (y + .5 - cy) / ry;
      if (dx * dx + dy * dy <= 1 &&
          x >= 0 &&
          y >= 0 &&
          x < im.width &&
          y < im.height) {
        px(im, x, y, col);
      }
    }
  }
}

void line(Img im, int x0, int y0, int x1, int y1, int col) {
  final n = max((x1 - x0).abs(), (y1 - y0).abs());
  for (var i = 0; i <= n; i++) {
    final t = n == 0 ? 0 : i / n;
    px(im, (x0 + (x1 - x0) * t).round(), (y0 + (y1 - y0) * t).round(), col);
  }
}

void save(String name, Img im) {
  File('assets/images/$name.png').writeAsBytesSync(img.encodePng(im));
}

const skin = 0xFFFFCC99, black = 0xFF202020, outline = 0xFF1B1B2F;

/// 24x24 character frame. [attack] extends the sword; [leg] 0 idle, 1/2 walk.
Img person(
    {required int hair,
    required int cloth,
    required int accent,
    int leg = 0,
    bool attack = false,
    bool beard = false}) {
  final im = blank(24, 24);
  // legs
  final l = leg == 1 ? 1 : 0, rr = leg == 2 ? 1 : 0;
  r(im, 8, 17, 3, 6 - l, 0xFF2B2B3B);
  r(im, 13, 17, 3, 6 - rr, 0xFF2B2B3B);
  r(im, 8, 23 - l - 1, 3, 1, 0xFF111111);
  r(im, 13, 23 - rr - 1, 3, 1, 0xFF111111);
  // body
  r(im, 7, 10, 10, 8, cloth);
  r(im, 7, 15, 10, 1, accent);
  r(im, 5, 10, 2, 6, cloth);
  r(im, 5, 15, 2, 1, skin);
  if (attack) {
    r(im, 17, 11, 4, 2, skin);
  } else {
    r(im, 17, 10, 2, 6, cloth);
    r(im, 17, 15, 2, 1, skin);
  }
  // head
  r(im, 8, 3, 8, 7, skin);
  r(im, 7, 1, 10, 4, hair);
  r(im, 7, 4, 2, 4, hair);
  r(im, 8, 4, 8, 1, accent);
  px(im, 12, 6, black);
  px(im, 14, 6, black);
  if (beard) r(im, 9, 9, 6, 3, 0xFFEEEEEE);
  if (attack) {
    r(im, 20, 9, 1, 5, 0xFF6D4C41);
    r(im, 20, 8, 4, 2, 0xFFE0E0E0);
    r(im, 21, 6, 3, 2, 0xFFFFFFFF);
    r(im, 22, 4, 2, 2, 0xFFFFFFFF);
  }
  return im;
}

Img slime(int frame) {
  final im = blank(16, 16);
  final h = frame == 0 ? 6.0 : 5.0;
  final w = frame == 0 ? 7.0 : 7.5;
  ellipse(im, 8, 15 - h, w, h + 0.5, outline);
  ellipse(im, 8, 15 - h, w - 1, h - 0.5, 0xFFFB8C00);
  ellipse(im, 6, 15 - h - 2, 2, 1.5, 0xFFFFB74D);
  final ey = 15 - h.round();
  r(im, 5, ey, 2, 2, black);
  r(im, 10, ey, 2, 2, black);
  px(im, 5, ey, 0xFFFFFFFF);
  px(im, 10, ey, 0xFFFFFFFF);
  return im;
}

Img speckled(int base, List<int> dots, int seed) {
  final im = blank(16, 16);
  r(im, 0, 0, 16, 16, base);
  var s = seed;
  for (var i = 0; i < 18; i++) {
    s = (s * 1103515245 + 12345) & 0x7FFFFFFF;
    px(im, s % 16, (s ~/ 16) % 16, dots[i % dots.length]);
  }
  return im;
}

Img house() {
  final im = blank(48, 40);
  r(im, 3, 16, 42, 24, 0xFF8D6E63);
  for (var y = 18; y < 40; y += 4) {
    r(im, 3, y, 42, 1, 0xFF6D4C41);
  }
  for (var y = 0; y < 15; y++) {
    final half = (3 + y * 1.5).round();
    r(im, 24 - half, y, half * 2, 1, y.isEven ? 0xFFB71C1C : 0xFF9A1515);
  }
  r(im, 0, 14, 48, 3, 0xFF7F1010);
  r(im, 19, 24, 10, 16, 0xFF4E342E);
  px(im, 26, 32, 0xFFFFD54F);
  r(im, 7, 22, 8, 7, 0xFFFFF59D);
  r(im, 7, 25, 8, 1, 0xFF6D4C41);
  r(im, 10, 22, 1, 7, 0xFF6D4C41);
  r(im, 33, 22, 8, 7, 0xFFFFF59D);
  r(im, 33, 25, 8, 1, 0xFF6D4C41);
  r(im, 36, 22, 1, 7, 0xFF6D4C41);
  return im;
}

Img tree() {
  final im = blank(24, 32);
  r(im, 10, 18, 4, 14, 0xFF5D4037);
  ellipse(im, 12, 11, 11, 10, 0xFF2E7D32);
  ellipse(im, 9, 8, 6, 5, 0xFF43A047);
  ellipse(im, 16, 13, 5, 4, 0xFF1B5E20);
  return im;
}

Img mountain() {
  final im = blank(96, 48);
  for (var y = 0; y < 48; y++) {
    final half = (y * 1.0).round();
    r(im, 48 - half, y, half * 2, 1,
        y < 10 ? 0xFFF5F5F5 : (y < 28 ? 0xFF6F8F86 : 0xFF5E7D74));
  }
  return im;
}

Img potion() {
  final im = blank(16, 16);
  r(im, 6, 1, 4, 3, 0xFF8D6E63);
  r(im, 5, 4, 6, 1, 0xFFB0BEC5);
  ellipse(im, 8, 10, 5, 5, 0xFFB71C1C);
  ellipse(im, 8, 10, 4, 4, 0xFFEF5350);
  px(im, 6, 8, 0xFFFFCDD2);
  px(im, 6, 9, 0xFFFFCDD2);
  return im;
}

Img sword(int blade, int guard) {
  final im = blank(16, 16);
  line(im, 3, 12, 12, 3, blade);
  line(im, 4, 12, 13, 3, blade);
  line(im, 3, 11, 12, 2, 0xFFFFFFFF);
  line(im, 2, 9, 6, 13, guard);
  line(im, 3, 9, 7, 13, guard);
  line(im, 1, 14, 3, 12, 0xFF5D4037);
  line(im, 2, 14, 4, 12, 0xFF5D4037);
  return im;
}

Img armor(int main, int trim) {
  final im = blank(16, 16);
  r(im, 4, 3, 8, 11, main);
  r(im, 1, 3, 4, 5, main);
  r(im, 11, 3, 4, 5, main);
  r(im, 6, 3, 4, 2, 0xFF222222);
  r(im, 4, 10, 8, 1, trim);
  r(im, 7, 5, 2, 9, trim);
  return im;
}

Img stone() {
  final im = blank(16, 16);
  for (var y = 0; y < 14; y++) {
    final half = y < 7 ? y + 1 : 14 - y;
    r(im, 8 - half, y + 1, half * 2, 1,
        y < 7 ? 0xFF4FC3F7 : 0xFF0288D1);
  }
  r(im, 6, 5, 2, 2, 0xFFE1F5FE);
  return im;
}

Img gel() {
  final im = blank(16, 16);
  ellipse(im, 8, 10, 6, 5, 0xFF2E7D32);
  ellipse(im, 8, 10, 5, 4, 0xFF66BB6A);
  r(im, 5, 8, 2, 2, 0xFFC8E6C9);
  return im;
}

void main() {
  Directory('assets/images').createSync(recursive: true);
  const hair = 0xFF212121;
  final frames = [
    person(hair: hair, cloth: 0xFF1E3A8A, accent: 0xFFE53935),
    person(hair: hair, cloth: 0xFF1E3A8A, accent: 0xFFE53935, leg: 1),
    person(hair: hair, cloth: 0xFF1E3A8A, accent: 0xFFE53935, leg: 2),
    person(
        hair: hair,
        cloth: 0xFF1E3A8A,
        accent: 0xFFE53935,
        attack: true),
  ];
  final sheet = blank(24 * frames.length, 24);
  for (var i = 0; i < frames.length; i++) {
    img.compositeImage(sheet, frames[i], dstX: i * 24);
  }
  save('player', sheet);

  final ms = blank(32, 16);
  img.compositeImage(ms, slime(0));
  img.compositeImage(ms, slime(1), dstX: 16);
  save('monster', ms);

  save(
      'npc',
      person(
          hair: 0xFFEEEEEE,
          cloth: 0xFF2E7D32,
          accent: 0xFFFFD54F,
          beard: true));
  save('grass', speckled(0xFF7CB342, [0xFF689F38, 0xFF8BC34A], 7));
  save('dirt', speckled(0xFFC8A96A, [0xFFB89A5C, 0xFFD7BC84], 3));
  save('house', house());
  save('tree', tree());
  save('mountain', mountain());

  save('item_potion', potion());
  save('item_sword_wood', sword(0xFFBCAAA4, 0xFF8D6E63));
  save('item_sword_iron', sword(0xFFCFD8DC, 0xFFFFC107));
  save('item_armor_cloth', armor(0xFF8D6E63, 0xFF6D4C41));
  save('item_armor_ninja', armor(0xFF263238, 0xFFE53935));
  save('item_stone', stone());
  save('item_gel', gel());
  stdout.writeln('Assets generated.');
}
