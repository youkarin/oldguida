import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provides helpers for debug UI such as conditional snack bars.
class DebugUtils {
  DebugUtils._();

  /// Global [ScaffoldMessengerState] key used to show snack bars
  /// from anywhere in the app.
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// Shows a snack bar only when the debug switch is enabled in settings.
  static Future<void> showSnackBar(String message,
      {bool isError = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('debugMode') ?? false;
    if (!enabled) return;
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }
}
