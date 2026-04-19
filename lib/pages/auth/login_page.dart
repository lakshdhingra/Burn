import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app_config.dart';
import '../../app_shell.dart';
import 'signup_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  void _goToDashboard() {
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const AppShell()));
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ✅ EMAIL LOGIN
  Future<void> login() async {
    if (!supabaseInitialized) {
      debugPrint('login: supabase not initialized');
      _showSnack('Authentication is unavailable. Please try again later.');
      return;
    }
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      debugPrint('login success: email=${emailController.text.trim()}');
      _showSnack('Login Success ✅');
      _goToDashboard();
    } catch (e, st) {
      debugPrint('login failure: $e\n$st');
      _showSnack(e.toString());
    }
  }

  /// Placeholder until Google + Supabase is wired up.
  void signInWithGoogle() {
    debugPrint('Google Sign-In: placeholder tapped');
    _showSnack('Google Auth coming soon');
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),

            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),

            const SizedBox(height: 20),

            // 🔐 LOGIN BUTTON
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: login,
                child: const Text('Login'),
              ),
            ),

            const SizedBox(height: 10),

            // 🔵 GOOGLE BUTTON
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: signInWithGoogle,
                child: const Text('Google Sign In'),
              ),
            ),

            const SizedBox(height: 10),

            // 🔁 SIGNUP NAV
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SignupPage()),
                );
              },
              child: const Text('Go to Signup'),
            ),
          ],
        ),
      ),
    );
  }
}
