import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_config.dart';
import 'auth/login_page.dart';

/// Shows signed-in user info from [signup] plus optional factory counts.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  User? _authUser;
  Map<String, dynamic>? _signupRow;
  int _factoryCount = 0;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (!supabaseInitialized) {
      if (mounted) {
        setState(() => _loading = false);
        _showSnack('Supabase is not initialized.');
      }
      return;
    }

    setState(() => _loading = true);

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;

      if (user == null) {
        if (!mounted) return;
        setState(() => _loading = false);
        _showSnack('Not signed in.');
        _goToLogin();
        return;
      }

      final signupRes =
          await client.from('signup').select().eq('id', user.id).maybeSingle();

      Map<String, dynamic>? row;
      if (signupRes != null) {
        row = Map<String, dynamic>.from(signupRes as Map<dynamic, dynamic>);
      }

      var factories = 0;
      try {
        final rawSources = await client
            .from('heat_source_basics')
            .select('project_id')
            .eq('user_id', user.id);
        final rawDemand = await client
            .from('heat_demand')
            .select('project_id')
            .eq('user_id', user.id);
        final s = rawSources as List<dynamic>;
        final d = rawDemand as List<dynamic>;
        factories = s.length + d.length;
      } catch (e, st) {
        debugPrint('ProfilePage factory count: $e\n$st');
      }

      if (!mounted) return;
      setState(() {
        _authUser = user;
        _signupRow = row;
        _factoryCount = factories;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('ProfilePage load error: $e\n$st');
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack(e.toString());
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _goToLogin() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _logout() async {
    if (!supabaseInitialized) {
      _showSnack('Authentication is unavailable.');
      return;
    }

    try {
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      _goToLogin();
    } catch (e, st) {
      debugPrint('ProfilePage signOut: $e\n$st');
      if (mounted) _showSnack(e.toString());
    }
  }

  String _displayName() {
    final v = _signupRow?['fullname'];
    if (v != null && v.toString().trim().isNotEmpty) {
      return v.toString();
    }
    return '—';
  }

  String _displayEmail() {
    final v = _signupRow?['email'];
    if (v != null && v.toString().trim().isNotEmpty) {
      return v.toString();
    }
    return _authUser?.email ?? '—';
  }

  String _displayPhone() {
    final v = _signupRow?['phone'];
    if (v != null && v.toString().trim().isNotEmpty) {
      return v.toString();
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadProfile,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadProfile,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Text(
                    'Profile Details',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    color: cs.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: cs.outlineVariant),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(Icons.badge_outlined, color: cs.primary),
                          title: const Text('Full name'),
                          subtitle: Text(
                            _displayName(),
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.email_outlined, color: cs.primary),
                          title: const Text('Email'),
                          subtitle: Text(
                            _displayEmail(),
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.phone_outlined, color: cs.primary),
                          title: const Text('Phone number'),
                          subtitle: Text(
                            _displayPhone(),
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Activity',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    color: cs.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: cs.outlineVariant),
                    ),
                    child: ListTile(
                      leading: Icon(Icons.factory_outlined, color: cs.primary),
                      title: const Text('Factories added'),
                      subtitle: Text(
                        '$_factoryCount (source + demand entries)',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout),
                    label: const Text('Log out'),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.error,
                      foregroundColor: cs.onError,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
