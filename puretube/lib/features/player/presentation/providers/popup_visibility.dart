import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Visibility flag for the floating in-app popup player.
///
/// Kept in its own file (rather than `widgets/popup_player.dart`) so that
/// [PlayerController] can also read it — e.g. to hide the floating window
/// the moment native PiP takes over — without creating an import cycle
/// between the controller and the popup widget.
///
/// The popup shares the single media_kit `Player` owned by
/// `PureTubeAudioHandler` (via `mediaKitPlayerProvider`) — it never creates
/// its own player. All buttons drive `playerControllerProvider`.
final popupVisibleProvider = StateProvider<bool>((ref) => false);

/// True while at least one fullscreen [PlayerScreen] is on the
/// navigation stack. The root corner mini player hides itself while
/// this is true so it never floats over the fullscreen player.
///
/// Depth-counted, not a plain bool: moving from one video to another
/// can push/pushReplace a new PlayerScreen whose initState runs
/// BEFORE the replaced screen's dispose — the old screen's dispose
/// then wrote `false` over the new screen's `true`, and the corner
/// popup floated on top of the still-open player. The flag now turns
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
