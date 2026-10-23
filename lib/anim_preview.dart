// Run: flutter run -d chrome -t lib/anim_preview.dart
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MaterialApp(
    debugShowCheckedModeBanner: false, home: Scaffold(body: Preview())));

class Preview extends StatefulWidget {
  const Preview({super.key});

  @override
  State<Preview> createState() => _PreviewState();
}

class _PreviewState extends State<Preview> {
  static const frames = 10;
  ui.Image? _img;
  int _frame = 0;
  double _fps = 10;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    rootBundle.load('assets/images/Hero/Attack.png').then((d) async {
      final codec = await ui.instantiateImageCodec(d.buffer.asUint8List());
      final img = (await codec.getNextFrame()).image;
      if (mounted) setState(() => _img = img);
      _restart();
    });
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: (1000 / _fps).round()),
        (_) => setState(() => _frame = (_frame + 1) % frames));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _img;
    if (img == null) return const Center(child: CircularProgressIndicator());
    return Container(
      color: const Color(0xFF263238),
      child: Column(children: [
        Expanded(
          child: Center(
            child: CustomPaint(
                size: const Size(440, 300), painter: _FramePainter(img, _frame)),
          ),
        ),
        Text('Frame ${_frame + 1}/$frames   •   $_fps fps',
            style: const TextStyle(color: Colors.white)),
        Slider(
            min: 4,
            max: 24,
            divisions: 20,
            value: _fps,
            onChanged: (v) {
              _fps = v;
              _restart();
            }),
        SizedBox(
          height: 70,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var i = 0; i < frames; i++)
              GestureDetector(
                onTap: () {
                  _timer?.cancel();
                  setState(() => _frame = i);
                },
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                      border: Border.all(
                          color: i == _frame ? Colors.amber : Colors.white24)),
                  child: CustomPaint(
                      size: const Size(88, 60), painter: _FramePainter(img, i)),
                ),
              ),
            TextButton(onPressed: _restart, child: const Text('Play')),
          ]),
        ),
      ]),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.img, this.frame);

  final ui.Image img;
  final int frame;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
        img,
        Rect.fromLTWH(frame * 440.0, 0, 440, 300),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.frame != frame || old.img != img;
}
