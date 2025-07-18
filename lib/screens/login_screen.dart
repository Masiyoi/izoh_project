import 'package:flutter/material.dart';
import 'package:unic_connect/utils/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic));

    _animationController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loginUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await _authService.signInWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image
          Image.asset(
            'images/login_bg.jpg',
            fit: BoxFit.cover,
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.08),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // App Logo
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.deepPurpleAccent,
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.deepPurpleAccent.withValues(alpha: 0.5),
                                  blurRadius: 15,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.school_rounded,
                              size: 60,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 30),
                          const Text(
                            'UNIC CONNECT',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 2.0,
                              shadows: [
                                Shadow(
                                  color: Colors.black38,
                                  offset: Offset(0, 2),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Welcome Back!',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Sign in to continue your journey',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white.withValues(alpha: 0.8),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 40),
                          // Login Form
                          Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(maxWidth: 400),
                            padding: const EdgeInsets.all(30),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.deepPurpleAccent.withValues(alpha: 0.7),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.deepPurpleAccent.withValues(alpha: 0.3),
                                  blurRadius: 30,
                                  offset: const Offset(0, 15),
                                ),
                              ],
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                children: [
                                  _buildInputField(
                                    controller: _emailController,
                                    label: 'Email Address',
                                    hint: 'you@example.com',
                                    icon: Icons.email_outlined,
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) return 'Enter email';
                                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                                        return 'Enter valid email';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 20),
                                  _buildInputField(
                                    controller: _passwordController,
                                    label: 'Password',
                                    hint: 'Your password',
                                    icon: Icons.lock_outline,
                                    obscureText: _obscurePassword,
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        color: Colors.grey.shade300,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
                                    validator: (value) =>
                                        value!.isEmpty ? 'Enter your password' : null,
                                  ),
                                  const SizedBox(height: 16),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: _isLoading
                                          ? null
                                          : () {
                                              Navigator.pushNamed(context, '/forgot_password');
                                            },
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text('Forgot Password?'),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  ElevatedButton(
                                    onPressed: _isLoading ? null : _loginUser,
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(50),
                                      backgroundColor: Colors.deepPurpleAccent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: _isLoading
                                        ? const CircularProgressIndicator(color: Colors.white)
                                        : const Text(
                                            'Sign In',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Don't have an account? ",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 16,
                                ),
                              ),
                              TextButton(
                                onPressed: _isLoading
                                    ? null
                                    : () => Navigator.pushNamed(context, '/register'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text(
                                  'Sign Up',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.deepPurpleAccent.withValues(alpha: 0.6),
              width: 1.2,
            ),
          ),
          child: TextFormField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.7)),
              suffixIcon: suffixIcon,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            ),
            validator: validator,
          ),
        ),
      ],
    );
  }
}