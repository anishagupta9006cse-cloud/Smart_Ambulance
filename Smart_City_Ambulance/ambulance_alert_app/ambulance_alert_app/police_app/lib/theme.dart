import 'package:flutter/material.dart';

/// Every kind of button has its own color, so each button is easy to tell apart.
class BtnColors {
  static const Color blue = Color(0xFF1565C0);
  static const Color brown = Color(0xFF6D4C41);
  static const Color green = Color(0xFF2E7D32);
  static const Color purple = Color(0xFF6A1B9A);
  static const Color red = Color(0xFFD32F2F);
  static const Color charcoal = Color(0xFF37474F);
  static const Color pink = Color(0xFFAD1457);
  static const Color orange = Color(0xFFEF6C00);
  static const Color teal = Color(0xFF00897B);
  static const Color indigo = Color(0xFF3949AB);
  static const Color olive = Color(0xFF6B7A0E);
  static const Color cyan = Color(0xFF00838F);
}

/// Solid colored button style (use with FilledButton / FilledButton.icon).
ButtonStyle solidButton(Color color, {EdgeInsetsGeometry? padding}) {
  return FilledButton.styleFrom(
    backgroundColor: color,
    foregroundColor: Colors.white,
    disabledBackgroundColor: color.withAlpha(110),
    disabledForegroundColor: Colors.white70,
    padding: padding ?? const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    textStyle: const TextStyle(fontWeight: FontWeight.bold),
  );
}

/// Colored text-only button style (use with TextButton).
ButtonStyle textColor(Color color) {
  return TextButton.styleFrom(
    foregroundColor: color,
    textStyle: const TextStyle(fontWeight: FontWeight.bold),
  );
}
