import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:unic_connect/providers/theme_provider.dart';

import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/forgot_password_screen.dart';

import 'services/auth_service.dart';
import 'services/user_service.dart';
import 'services/post_service.dart';
import 'services/comment_service.dart';
// ✅ Theme Provider import

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // ✅ Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // ✅ Initialize Supabase
    await Supabase.initialize(
      url: 'https://oegfcsyndbycisohwbvg.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9lZ2Zjc3luZGJ5Y2lzb2h3YnZnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA5NTA4NTksImV4cCI6MjA2NjUyNjg1OX0.5pGM2Pfne23eqXuoWVRLMVH1PHeU4a4FzGHHZhPpTe8',
    );
    

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()), // ✅ Add theme provider
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
            'App Initialization Error: \${e.toString()}',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.red, fontSize: 18),
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
      themeMode: themeProvider.themeMode,
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: Colors.white,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: Colors.grey[900],
      ),
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
