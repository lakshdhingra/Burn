import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app_config.dart';
import '../dashboard_page.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();

  void _goToDashboard() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const DashboardPage(),
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> signup() async {
    if (!supabaseInitialized) {
      debugPrint('signup: supabase not initialized');
      _showSnack('Authentication is unavailable. Please try again later.');
      return;
    }

    final supabase = Supabase.instance.client;

    try {
      final response = await supabase.auth.signUp(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      debugPrint(
        'signup response: user=${response.user?.id}, '
        'session=${response.session != null}',
      );

      final user = response.user;
      if (user == null) {
        debugPrint('signup failure: response.user is null');
        _showSnack('Signup failed: response.user is null');
        return;
      }

      try {
        await supabase.from('signup').insert({
          'id': user.id,
          'fullname': nameController.text,
          'email': emailController.text,
          'phone': phoneController.text,
        });
        debugPrint('insert into signup table: success for id=${user.id}');
      } catch (e, st) {
        debugPrint('insert into signup table: failure: $e\n$st');
        _showSnack(e.toString());
        return;
      }

      _showSnack('Signup successful');
      _goToDashboard();
    } catch (e, st) {
      debugPrint('signup failure: $e\n$st');
      _showSnack(e.toString());
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signup')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: signup, child: const Text('Sign Up')),
          ],
        ),
      ),
    );
  }
}
