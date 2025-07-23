import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
// ignore: unused_import
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:unic_connect/providers/theme_provider.dart';
import 'package:unic_connect/utils/supabase_client.dart';
import 'package:unic_connect/utils/theme.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'services/auth_service.dart';
import 'services/user_service.dart';
import 'services/post_service.dart';
import 'services/comment_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseClientUtil.initialize(); // Single Supabase initialization

  try {
    // Initialize Firebase (if still needed)
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          Provider(create: (_) => UserService()),
          Provider(create: (_) => PostService()),
          Provider(create: (_) => CommentService()),
        ],
        child: const UnicConnectApp(),
      ),
    );
  } catch (e) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'App Initialization Error: ${e.toString()}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontSize: 18),
          ),
        ),
      ),
    ));
  }
}

class UnicConnectApp extends StatelessWidget {
  const UnicConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Unic Connect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: Colors.white,
        brightness: Brightness.light,
      ),
      darkTheme: AppTheme.darkTheme, // Use AppTheme.darkTheme from theme.dart
      themeMode: themeProvider.themeMode, // Controlled by ThemeProvider
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