import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';
import 'app_shell.dart';
import 'pages/auth/login_page.dart';

class MainWrapper extends StatelessWidget {
  const MainWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    if (!supabaseInitialized) {
      return const LoginPage();
    }

    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      return const AppShell();
    }
    return const LoginPage();
  }
}
