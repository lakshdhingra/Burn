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
  double _sourceKwUser = 0;
  double _sinkKwUser = 0;

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
      double sourceHeatKw = 0;
      double sinkDemandKw = 0;

      try {
        final rawSources = await client.from('heat_source_basics').select().eq('user_id', user.id);
        final rawDemand = await client.from('heat_demand').select().eq('user_id', user.id);
        
        final s = rawSources as List<dynamic>;
        final d = rawDemand as List<dynamic>;
        factories = s.length + d.length;

        for (var row in s) {
          final kw = double.tryParse(row['heat_output_peak_kw']?.toString() ?? '');
          if (kw != null) sourceHeatKw += kw;
        }

        for (var row in d) {
          final kw = double.tryParse(row['required_volume_kw']?.toString() ?? '');
          if (kw != null) sinkDemandKw += kw;
        }

      } catch (e, st) {
        debugPrint('ProfilePage factory count: $e\n$st');
      }

      if (!mounted) return;
      setState(() {
        _authUser = user;
        _signupRow = row;
        _factoryCount = factories;
        _sourceKwUser = sourceHeatKw;
        _sinkKwUser = sinkDemandKw;
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
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
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
                      leading: CircleAvatar(
                        backgroundColor: cs.primary.withValues(alpha: 0.1),
                        foregroundColor: cs.primary,
                        child: const Icon(Icons.factory_outlined),
                      ),
                      title: const Text('Factories Added', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        '$_factoryCount total facilities active in network.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  if (_sourceKwUser > 0) ...[
                    const SizedBox(height: 12),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (context, val, child) => Transform.scale(
                        scale: 0.95 + (0.05 * val),
                        child: Opacity(opacity: val, child: child),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(colors: [Colors.orange.shade50, Colors.deepOrange.shade50]),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.local_fire_department, color: Colors.orange),
                          title: const Text('Source Profile', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                          subtitle: Text('Supplying ${_sourceKwUser.toStringAsFixed(0)} kW of heat energy.'),
                        ),
                      ),
                    ),
                  ],
                  if (_sinkKwUser > 0) ...[
                    const SizedBox(height: 12),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (context, val, child) => Transform.scale(
                        scale: 0.95 + (0.05 * val),
                        child: Opacity(opacity: val, child: child),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(colors: [Colors.blue.shade50, Colors.lightBlue.shade50]),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.ac_unit, color: Colors.blue),
                          title: const Text('Sink Profile', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                          subtitle: Text('Demanding ${_sinkKwUser.toStringAsFixed(0)} kW of heat energy.'),
                        ),
                      ),
                    ),
                  ],
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
