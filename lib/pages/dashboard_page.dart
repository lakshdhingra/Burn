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
  /// Dummy preview rows (no backend).
  static const List<({String factoryName, double matchScore})> _dummyMatches = [
    (factoryName: 'North Plant Thermal', matchScore: 0.94),
    (factoryName: 'Riverside Heat Hub', matchScore: 0.87),
    (factoryName: 'East District Boiler', matchScore: 0.81),
  ];

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
      final rawSources =
          await client.from('heat_source_basics').select('heat_output_peak_kw');
      final rawDemand =
          await client.from('heat_demand').select('required_volume_kw');

      final sources = _asRowList(rawSources);
      final demand = _asRowList(rawDemand);

      final supply = _sumNumericColumn(sources, 'heat_output_peak_kw');
      final dem = _sumNumericColumn(demand, 'required_volume_kw');

      if (!mounted) return;
      setState(() {
        _totalSupplyKw = supply;
        _totalDemandKw = dem;
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
      appBar: AppBar(
        title: const Text('Heat App 🔥'),
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
          _heatSummaryCard(theme, cs),
          const SizedBox(height: 20),
          Text(
            'Top matches',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Preview (sample data)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          ..._dummyMatches.map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _matchPreviewCard(theme, cs, m.factoryName, m.matchScore),
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
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
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
        ),
      ),
    );
  }

  Widget _matchPreviewCard(
    ThemeData theme,
    ColorScheme cs,
    String factoryName,
    double score,
  ) {
    final pct = (score * 100).round();
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: cs.primaryContainer,
              foregroundColor: cs.onPrimaryContainer,
              child: const Icon(Icons.factory_outlined, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    factoryName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Match score',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$pct%',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
