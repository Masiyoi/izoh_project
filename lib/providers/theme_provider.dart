import 'package:flutter/material.dart';

class ThemeProvider with ChangeNotifier {
  bool isDarkMode = false;

  void toggleTheme() {
    isDarkMode = !isDarkMode;
    notifyListeners();
  }
  ThemeMode get themeMode => isDarkMode ? ThemeMode.dark : ThemeMode.light;
  ThemeMode get currentTheme => isDarkMode ? ThemeMode.dark : ThemeMode.light;
}

