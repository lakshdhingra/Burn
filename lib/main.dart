import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';
import 'main_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: 'https://fzyyutcaurmlcrzkjfke.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ6eXl1dGNhdXJtbGNyemtqZmtlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY1MDMxNjAsImV4cCI6MjA5MjA3OTE2MH0.EQeBNei6bEQHnmBeMb5op-tW15RmczJfOZsoD7Azc_Y',
      // PKCE + deep-link session detection (default); pair with [kSupabaseMobileRedirectUrl]
      // in Dashboard and native URL handlers.
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        detectSessionInUri: true,
      ),
    );
    supabaseInitialized = true;
  } catch (e, st) {
    supabaseInitialized = false;
    debugPrint('Supabase.initialize failed: $e\n$st');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: Colors.teal,
          primary: Colors.tealAccent,
          secondary: Colors.cyanAccent,
          surface: const Color(0xFF0F172A), // Tailwind Slate-900 equivalent
          background: const Color(0xFF0F172A),
        ),
        fontFamily: 'Inter', // Often available automatically structurally or defaults nicely
      ),
      home: const MainWrapper(),
    );
  }
}
