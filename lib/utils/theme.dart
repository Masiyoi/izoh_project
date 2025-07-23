import 'package:flutter/material.dart';

class AppTheme {
  static final ThemeData darkTheme = ThemeData(
    scaffoldBackgroundColor: const Color(0xFF0A0E1A), // Home screen background
    primaryColor: Colors.blue,
    colorScheme: ColorScheme.dark(
      primary: Colors.blue,
      secondary: Colors.grey.shade600,
      surface: const Color(0xFF1A1F2E), // Modal and container background
      onPrimary: Colors.white,
      onSurface: Colors.white,
      error: Colors.red.shade600,
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
      titleLarge: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: TextStyle(color: Colors.grey, fontSize: 12),
      labelLarge: TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
    iconTheme: IconThemeData(color: Colors.grey.shade600),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.grey.shade600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFF0A0E1A).withOpacity(0.8),
      elevation: 0,
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    dividerColor: Colors.grey.shade900,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Colors.green.shade600,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade600),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade600),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.blue),
      ),
      hintStyle: TextStyle(color: Colors.grey.shade600),
      contentPadding: const EdgeInsets.all(12),
    ),
  );
}