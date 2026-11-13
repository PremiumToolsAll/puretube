import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while at least one fullscreen [PlayerScreen] is on the
/// navigation stack. Used by the controller to arm/disarm auto-PiP.
///
/// Depth-counted, not a plain bool: moving from one video to another
/// can push/pushReplace a new PlayerScreen whose initState runs
/// BEFORE the replaced screen's dispose — the old screen's dispose
/// then wrote `false` over the new screen's `true`. The flag now turns
/// false only when the LAST player screen closes.
class FullPlayerOpenNotifier extends StateNotifier<bool> {
  FullPlayerOpenNotifier() : super(false);

  int _depth = 0;

  void push() {
    _depth++;
    if (!state) state = true;
  }

  void pop() {
    _depth--;
    if (_depth <= 0) {
      _depth = 0;
      if (state) state = false;
    }
  }
}

final fullPlayerOpenProvider =
    StateNotifierProvider<FullPlayerOpenNotifier, bool>(
        (ref) => FullPlayerOpenNotifier());
