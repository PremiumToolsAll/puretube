import 'package:flutter/material.dart';

/// Wraps any child with a 200ms ease-in-out press-scale effect:
/// shrinks to [pressedScale] while the pointer is down, springs back
/// on release/cancel.
///
/// This widget handles the tap itself — do NOT nest another tappable
/// ([IconButton], [GestureDetector] with onTap, [InkWell]) inside it,
/// or the two gesture recognizers will fight in the arena.
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final Duration duration;

  const PressScale({
    super.key,
    required this.child,
    required this.onTap,
    this.pressedScale = 0.88,
    this.duration = const Duration(milliseconds: 200),
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _setPressed(true) : null,
      onTapUp: enabled ? (_) => _setPressed(false) : null,
      onTapCancel: _setPressedFalse,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: widget.duration,
        curve: Curves.easeInOut,
        child: widget.child,
      ),
    );
  }

  void _setPressedFalse() => _setPressed(false);
}

/// Drop-in replacement for [IconButton] with a 200ms ease-in-out
/// press-scale effect instead of the Material ripple.
///
/// Mirrors the [IconButton] call sites used across the player UI:
/// [icon], [onPressed], [tooltip], [iconSize]. The [icon] widget keeps
/// any explicit size/color set on it; [iconSize] applies via [IconTheme]
/// when the icon doesn't set its own size.
class PressIconButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double? iconSize;
  final EdgeInsetsGeometry padding;
  final double pressedScale;

  const PressIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.iconSize,
    this.padding = const EdgeInsets.all(8.0),
    this.pressedScale = 0.88,
  });

  @override
  Widget build(BuildContext context) {
    Widget button = PressScale(
      onTap: onPressed,
      pressedScale: pressedScale,
      child: Padding(
        padding: padding,
        child: IconTheme(
          data: IconThemeData(size: iconSize),
          child: Opacity(
            opacity: onPressed == null ? 0.38 : 1.0,
            child: icon,
          ),
        ),
      ),
    );
    final tip = tooltip;
    if (tip != null && tip.isNotEmpty) {
      button = Tooltip(message: tip, child: button);
    }
    return button;
  }
}
