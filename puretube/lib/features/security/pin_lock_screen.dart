import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import 'app_lock_service.dart';

/// PIN entry screen (app lock fallback + secure folder).
class PinLockScreen extends StatefulWidget {
  final String title;
  final bool isSetup;
  final VoidCallback onUnlocked;

  const PinLockScreen({
    super.key,
    this.title = 'Enter PIN',
    this.isSetup = false,
    required this.onUnlocked,
  });

  @override
  State<PinLockScreen> createState() =>
      _PinLockScreenState();
}

class _PinLockScreenState
    extends State<PinLockScreen> {
  String _pin = '';
  String? _firstEntry;
  String? _error;

  Future<void> _onDigit(String d) async {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == 4) {
      await Future.delayed(
          const Duration(milliseconds: 200));
      await _submit();
    }
  }

  Future<void> _submit() async {
    if (widget.isSetup) {
      if (_firstEntry == null) {
        setState(() {
          _firstEntry = _pin;
          _pin = '';
        });
      } else {
        if (_pin == _firstEntry) {
          await AppLockService.instance
              .setPin(_pin);
          widget.onUnlocked();
        } else {
          setState(() {
            _error =
                'PINs do not match. Try again.';
            _pin = '';
            _firstEntry = null;
          });
        }
      }
    } else {
      final ok = await AppLockService
          .instance
          .verifyPin(_pin);
      if (ok) {
        widget.onUnlocked();
      } else {
        setState(() {
          _error = 'Wrong PIN.';
          _pin = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            const Icon(
                Icons.lock_outline,
                size: 64,
                color: AppTheme.primary),
            const SizedBox(height: 24),
            Text(
                widget.isSetup &&
                        _firstEntry != null
                    ? 'Confirm PIN'
                    : widget.title,
                style: AppTheme.title),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: List.generate(
                  4,
                  (i) => Container(
                        width: 20,
                        height: 20,
                        margin:
                            const EdgeInsets
                                .symmetric(
                                horizontal: 8),
                        decoration:
                            BoxDecoration(
                          shape:
                              BoxShape.circle,
                          color: i <
                                  _pin.length
                              ? AppTheme.primary
                              : Colors.white24,
                        ),
                      )),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: AppTheme.caption
                      .copyWith(
                          color:
                              AppTheme.error)),
            ],
            const SizedBox(height: 32),
            _keypad(),
          ],
        ),
      ),
    );
  }

  Widget _keypad() {
    return Column(
      children: [
        for (var row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', 'back'],
        ])
          Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: row.map((k) {
              if (k.isEmpty) {
                return const SizedBox(
                    width: 80, height: 80);
              }
              return Padding(
                padding:
                    const EdgeInsets.all(8),
                child: InkWell(
                  onTap: () {
                    if (k == 'back') {
                      if (_pin.isNotEmpty) {
                        setState(() => _pin =
                            _pin.substring(
                                0,
                                _pin.length -
                                    1));
                      }
                    } else {
                      _onDigit(k);
                    }
                  },
                  borderRadius:
                      BorderRadius.circular(
                          40),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration:
                        BoxDecoration(
                      shape:
                          BoxShape.circle,
                      color: AppTheme.card,
                    ),
                    child: Center(
                      child: k == 'back'
                          ? const Icon(
                              Icons
                                  .backspace_outlined,
                              color: Colors
                                  .white70)
                          : Text(k,
                              style: AppTheme
                                  .title
                                  .copyWith(
                                      color: Colors
                                          .white)),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

/// Biometric gate shown on app launch when app lock is enabled.
class AppLockGate extends ConsumerStatefulWidget {
  final Widget child;

  const AppLockGate(
      {super.key, required this.child});

  @override
  ConsumerState<AppLockGate> createState() =>
      _AppLockGateState();
}

class _AppLockGateState
    extends ConsumerState<AppLockGate> {
  bool _unlocked = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final enabled = await AppLockService
        .instance.isEnabled;
    if (!enabled) {
      if (mounted) {
        setState(() {
          _unlocked = true;
          _checking = false;
        });
      }
      return;
    }
    final ok = await AppLockService.instance
        .authenticate();
    if (mounted) {
      setState(() {
        _unlocked = ok;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
            child: CircularProgressIndicator()),
      );
    }
    if (_unlocked) return widget.child;
    return PinLockScreen(
      title: 'Enter PIN to unlock',
      onUnlocked: () =>
          setState(() => _unlocked = true),
    );
  }
}
