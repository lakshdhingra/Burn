import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_config.dart';
import 'factory/full_factory_form.dart';
import 'match_page.dart';

/// Home dashboard (heat summary, previews, quick actions).
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // Real top matches replacing dummy
  List<Map<String, dynamic>> _topMatches = [];
  
  // User role inference
  bool _isSourceProvider = false;
  bool _isSinkConsumer = false;

  /// Sum of [heat_source_basics.heat_output_peak_kw] (kW).
  double _totalSupplyKw = 0;

  /// Sum of [heat_demand.required_volume_kw] (kW).
  double _totalDemandKw = 0;

  bool _summaryLoading = true;
  String? _summaryError;

  @override
  void initState() {
    super.initState();
    _fetchHeatSummary();
  }

  Future<void> _fetchHeatSummary() async {
    if (!supabaseInitialized) {
      if (mounted) {
        setState(() {
          _summaryLoading = false;
          _summaryError = 'Supabase not initialized';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _summaryLoading = true;
        _summaryError = null;
      });
    }

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;

      final rawSources = await client.from('heat_source_basics').select();
      final rawDemand = await client.from('heat_demand').select();

      final sources = _asRowList(rawSources);
      final demand = _asRowList(rawDemand);

      final supply = _sumNumericColumn(sources, 'heat_output_peak_kw');
      final dem = _sumNumericColumn(demand, 'required_volume_kw');

      bool isSrc = false;
      bool isSnk = false;
      if (userId != null) {
        isSrc = sources.any((r) => r['user_id'] == userId);
        isSnk = demand.any((r) => r['user_id'] == userId);
      }

      // Compute simple matches for Dashboard preview based on Score formula
      final top = <Map<String, dynamic>>[];
      for (final src in sources) {
        final outletT = _asDouble(src['outlet_temp_typical']);
        final peakKw = _asDouble(src['heat_output_peak_kw']);
        if (outletT == null || peakKw == null) continue;

        for (final snk in demand) {
          final reqT = _asDouble(snk['required_temperature']);
          final reqVol = _asDouble(snk['required_volume_kw']);
          if (reqT == null || reqVol == null) continue;

          if (outletT >= reqT && peakKw >= reqVol) {
            // Rough 0-100 score temp/cap
            final tempScore = (1.0 - math.min(1.0, ((outletT - reqT) / reqT).abs() / 0.45));
            final capScore = (1.0 - math.min(1.0, ((peakKw - reqVol) / reqVol).abs() / 0.55));
            final composite = (tempScore * 0.5 + capScore * 0.5) * 100;
            top.add({
              'score': composite,
              'name': 'Match #${top.length + 1} (Source & Sink Pair)'
            });
          }
        }
      }
      top.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

      if (!mounted) return;
      setState(() {
        _totalSupplyKw = supply;
        _totalDemandKw = dem;
        _isSourceProvider = isSrc;
        _isSinkConsumer = isSnk;
        _topMatches = top.take(3).toList();
        _summaryLoading = false;
        _summaryError = null;
      });
    } catch (e, st) {
      debugPrint('Dashboard heat summary: $e\n$st');
      if (!mounted) return;
      setState(() {
        _summaryLoading = false;
        _summaryError = e.toString();
      });
    }
  }

  List<Map<String, dynamic>> _asRowList(dynamic response) {
    if (response == null) return [];
    final list = response as List<dynamic>;
    return list
        .map((row) => Map<String, dynamic>.from(row as Map<dynamic, dynamic>))
        .toList();
  }

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.'));
  }

  double _sumNumericColumn(List<Map<String, dynamic>> rows, String key) {
    var sum = 0.0;
    for (final r in rows) {
      final v = _asDouble(r[key]);
      if (v != null) sum += v;
    }
    return sum;
  }

  String _availableHeatLabel() {
    if (_summaryLoading) return '—';
    if (_summaryError != null) return '—';
    return _formatKw(_totalSupplyKw);
  }

  String _utilizationPercentLabel() {
    if (_summaryLoading) return '—';
    if (_summaryError != null) return '—';
    if (_totalSupplyKw <= 0 && _totalDemandKw <= 0) return '0%';
    if (_totalSupplyKw <= 0) return '—';
    final r = _totalDemandKw / _totalSupplyKw;
    return '${(r * 100).round()}%';
  }

  /// Progress bar 0–1; caps at 1 when demand ≥ supply.
  double _utilizationProgress() {
    if (_summaryLoading) return 0;
    if (_summaryError != null) return 0;
    if (_totalSupplyKw <= 0 && _totalDemandKw <= 0) return 0;
    if (_totalSupplyKw <= 0) return 1;
    final r = _totalDemandKw / _totalSupplyKw;
    if (r.isNaN) return 0;
    return r.clamp(0.0, 1.0);
  }

  String _formatKw(double v) {
    final n = v.round();
    final abs = n.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < abs.length; i++) {
      if (i > 0 && (abs.length - i) % 3 == 0) buf.write(',');
      buf.write(abs[i]);
    }
    final core = buf.toString();
    final sign = n < 0 ? '-' : '';
    return '$sign$core kW';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Heat App 🔥', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _buildHomeDashboard(context),
    );
  }

  Widget _buildHomeDashboard(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, val, child) {
              return Transform.translate(
                offset: Offset(0, 20 * (1 - val)),
                child: Opacity(
                  opacity: val,
                  child: child,
                ),
              );
            },
            child: _heatSummaryCard(theme, cs),
          ),
          const SizedBox(height: 24),
          if (_isSourceProvider || _isSinkConsumer) ...[
            TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, val, child) => Opacity(opacity: val, child: child),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _isSourceProvider ? Colors.orange.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _isSourceProvider ? Colors.orange : Colors.blue, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isSourceProvider ? Icons.local_fire_department : Icons.ac_unit,
                        color: _isSourceProvider ? Colors.orange : Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _isSourceProvider 
                            ? 'Role: Heat Source Provider\nYour facility is ready to supply heat to nearby sinks.'
                            : 'Role: Heat Consumer (Sink)\nYou are looking for heat supplies to offset your load.',
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
          ],
          Text(
            'Top matches',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _summaryLoading ? 'Loading top pairings...' : 'Preview of best compatibility pairs',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (!_summaryLoading && _topMatches.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: cs.surfaceContainerLowest,
              ),
              child: const Text('No matches available yet. Try adding more factories.'),
            )
          else
            ..._topMatches.asMap().entries.map(
              (e) => TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 500 + (e.key * 100)),
                curve: Curves.easeOut,
                builder: (context, val, child) => Transform.translate(
                  offset: Offset(20 * (1 - val), 0),
                  child: Opacity(opacity: val, child: child),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _matchPreviewCard(theme, cs, e.value['name'] as String, (e.value['score'] as double) / 100.0),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const MatchPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.search, size: 20),
                  label: const Text('Find Matches'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const FullFactoryFormPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  label: const Text('Add Factory Data'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heatSummaryCard(ThemeData theme, ColorScheme cs) {
    final pctLabel = _utilizationPercentLabel();
    final progress = _utilizationProgress();
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white.withValues(alpha: 0.05),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 15,
                offset: const Offset(0, 8),
              )
            ],
          ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, color: cs.primary, size: 26),
                const SizedBox(width: 10),
                Text(
                  'Heat summary',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_summaryLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              Text(
                'Available heat',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _availableHeatLabel(),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Utilization',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    pctLabel,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 10,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  ),
);
}

  Widget _matchPreviewCard(
    ThemeData theme,
    ColorScheme cs,
    String name,
    double scorePct,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: CircleAvatar(
          backgroundColor: cs.primary.withValues(alpha: 0.1),
          foregroundColor: cs.primary,
          child: const Icon(Icons.handshake_outlined, size: 20),
        ),
        title: Text(
          name,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: scorePct,
                    minHeight: 6,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(scorePct * 100).round()}%',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                ),
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
      ),
    );
  }
}
