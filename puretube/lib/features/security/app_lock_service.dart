import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App lock: biometric + PIN fallback.
class AppLockService {
  AppLockService._();
  static final AppLockService instance =
      AppLockService._();

  final _auth = LocalAuthentication();

  Future<bool> get isEnabled async {
    try {
      final p = await SharedPreferences
          .getInstance();
      return p.getBool('app_lock_enabled') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled(bool v) async {
    try {
      final p = await SharedPreferences
          .getInstance();
      await p.setBool(
          'app_lock_enabled', v);
    } catch (_) {}
  }

  Future<bool> get hasPin async {
    try {
      final p = await SharedPreferences
          .getInstance();
      final pin =
          p.getString('app_lock_pin');
      return pin != null &&
          pin.length == 4;
    } catch (_) {
      return false;
    }
  }

  Future<void> setPin(String pin) async {
    try {
      final p = await SharedPreferences
          .getInstance();
      await p.setString(
          'app_lock_pin', pin);
    } catch (_) {}
  }

  Future<bool> verifyPin(String pin) async {
    try {
      final p = await SharedPreferences
          .getInstance();
      return p.getString(
              'app_lock_pin') ==
          pin;
    } catch (_) {
      return false;
    }
  }

  Future<bool> get canBiometric async {
    try {
      return await _auth.canCheckBiometrics &&
          await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Try biometric first, fall back to PIN (caller shows PIN UI).
  Future<bool> authenticate(
      {String reason =
          'Unlock PureTube'}) async {
    try {
      if (await canBiometric) {
        return await _auth.authenticate(
          localizedReason: reason,
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false,
          ),
        );
      }
    } on PlatformException catch (_) {
      // Fall through to PIN.
    } catch (_) {}
    return false;
  }
}
