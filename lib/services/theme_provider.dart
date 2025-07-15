import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:unic_connect/providers/theme_provider.dart';
import 'package:unic_connect/screens/forgot_password_screen.dart';
import 'package:unic_connect/screens/home_screen.dart';
import 'package:unic_connect/screens/login_screen.dart';
import 'package:unic_connect/screens/register_screen.dart';

class UnicConnectApp extends StatelessWidget {
  const UnicConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Unic Connect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => const HomeScreen(),
        '/forgot_password': (context) => const ForgotPasswordScreen(),
      },
    );
  }
}
