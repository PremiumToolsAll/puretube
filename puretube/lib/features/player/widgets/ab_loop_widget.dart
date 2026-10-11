import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';

/// A-B loop: repeat a segment of the video.
class AbLoopController extends ChangeNotifier {
  final Player player;
  Duration? pointA;
  Duration? pointB;
  Timer? _timer;

  AbLoopController(this.player);

  bool get isActive =>
      pointA != null && pointB != null;

  void setA() {
    pointA = player.state.position;
    pointB = null;
    notifyListeners();
  }

  void setB() {
    if (pointA == null) return;
    final pos = player.state.position;
    if (pos <= pointA!) return;
    pointB = pos;
    _startLoop();
    notifyListeners();
  }

  void clear() {
    pointA = null;
    pointB = null;
    _timer?.cancel();
    notifyListeners();
  }

  void _startLoop() {
    _timer?.cancel();
    if (!isActive) return;
    _timer = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) {
      final pos = player.state.position;
      if (pos >= pointB!) {
        player.seek(pointA!);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// A-B loop buttons row.
class AbLoopWidget extends StatefulWidget {
  final Player player;

  const AbLoopWidget(
      {super.key, required this.player});

  @override
  State<AbLoopWidget> createState() =>
      _AbLoopWidgetState();
}

class _AbLoopWidgetState
    extends State<AbLoopWidget> {
  late final AbLoopController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AbLoopController(widget.player);
    _ctrl.addListener(
        () => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
              horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius:
            BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
              Icons.repeat_outlined,
              size: 16,
              color: AppTheme.primary),
          const SizedBox(width: 8),
          _btn('A', _ctrl.pointA == null,
              _ctrl.setA),
          const SizedBox(width: 4),
          _btn('B', _ctrl.pointB == null,
              _ctrl.setB),
          if (_ctrl.isActive) ...[
            const SizedBox(width: 8),
            Text(
                '${formatDuration(_ctrl.pointA)} → ${formatDuration(_ctrl.pointB)}',
                style:
                    AppTheme.caption.copyWith(
                        color:
                            AppTheme.primary)),
            const SizedBox(width: 4),
            InkWell(
              onTap: _ctrl.clear,
              child: const Icon(
                  Icons.close,
                  size: 16,
                  color:
                      AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _btn(String label, bool enabled,
      VoidCallback onTap) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius:
          BorderRadius.circular(12),
      child: Container(
        padding:
            const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6),
        decoration: BoxDecoration(
          color: enabled
              ? AppTheme.primary
                  .withOpacity(0.2)
              : Colors.white10,
          borderRadius:
              BorderRadius.circular(12),
          border: Border.all(
              color: enabled
                  ? AppTheme.primary
                  : Colors.transparent),
        ),
        child: Text(label,
            style: AppTheme.body.copyWith(
                color: enabled
                    ? AppTheme.primary
                    : AppTheme.textSecondary,
                fontWeight:
                    FontWeight.bold,
                fontSize: 13)),
      ),
    );
  }
}
