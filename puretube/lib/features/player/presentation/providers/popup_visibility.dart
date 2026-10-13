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
