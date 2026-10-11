import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../../core/theme/app_theme.dart';

/// Scrubbable seek bar with buffered indicator and glow knob.
class PlayerSeekBar extends StatelessWidget {
  final Player player;

  const PlayerSeekBar({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      builder: (_, posSnap) {
        return StreamBuilder<Duration>(
          stream: player.stream.duration,
          builder: (_, durSnap) {
            return StreamBuilder<Duration>(
              stream: player.stream.buffer,
              builder: (_, bufSnap) {
                final pos =
                    posSnap.data ?? Duration.zero;
                final dur = durSnap.data ??
                    Duration.zero;
                final buf = bufSnap.data ??
                    Duration.zero;
                final frac = dur.inMilliseconds >
                        0
                    ? pos.inMilliseconds /
                        dur.inMilliseconds
                    : 0.0;
                final bufFrac = dur.inMilliseconds >
                        0
                    ? buf.inMilliseconds /
                        dur.inMilliseconds
                    : 0.0;
                return GestureDetector(
                  onTapDown: (d) async {
                    try {
                      final w =
                          context.size?.width ?? 1;
                      final f =
                          ((d.localPosition.dx -
                                      12) /
                                  (w - 24))
                              .clamp(0.0, 1.0);
                      await player.seek(Duration(
                          milliseconds:
                              (f * dur.inMilliseconds)
                                  .round()));
                    } catch (_) {}
                  },
                  onHorizontalDragUpdate:
                      (d) async {
                    try {
                      final w =
                          context.size?.width ?? 1;
                      final delta =
                          d.delta.dx / w;
                      final target =
                          pos + dur * delta;
                      await player.seek(
                          target.isNegative
                              ? Duration.zero
                              : (target > dur
                                  ? dur
                                  : target));
                    } catch (_) {}
                  },
                  child: Container(
                    height: 28,
                    padding:
                        const EdgeInsets.symmetric(
                            horizontal: 12),
                    child: CustomPaint(
                      painter: _SeekPainter(
                        frac: frac.clamp(0.0, 1.0),
                        bufFrac:
                            bufFrac.clamp(0.0, 1.0),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _SeekPainter extends CustomPainter {
  final double frac;
  final double bufFrac;

  _SeekPainter(
      {required this.frac, required this.bufFrac});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final w = size.width;
    canvas.drawLine(
        Offset(0, y),
        Offset(w, y),
        Paint()
          ..color = Colors.white24
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 4);
    canvas.drawLine(
        Offset(0, y),
        Offset(w * bufFrac, y),
        Paint()
          ..color = Colors.white38
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 4);
    final played = Paint()
      ..color = AppTheme.primary
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    canvas.drawLine(
        Offset(0, y), Offset(w * frac, y), played);
    canvas.drawCircle(
        Offset(w * frac, y),
        8,
        Paint()
          ..color = AppTheme.primary
              .withOpacity(0.3));
    canvas.drawCircle(Offset(w * frac, y), 5.5,
        Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(
          covariant _SeekPainter old) =>
      old.frac != frac || old.bufFrac != bufFrac;
}
