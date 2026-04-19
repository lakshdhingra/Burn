import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_config.dart';

/// Fetches sources and demand, applies matching rules, shows scored pairs.
class MatchesPage extends StatefulWidget {
  const MatchesPage({super.key});

  @override
  State<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends State<MatchesPage> {
  List<_ScoredMatch> _matches = [];

  bool _loading = true;
  String? _error;

  static const List<String> _dummyDistances = [
    '8.2 km',
    '14.0 km',
    '3.1 km',
    '21.6 km',
    '6.8 km',
  ];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (!supabaseInitialized) {
      setState(() {
        _loading = false;
        _error = 'Supabase is not initialized.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final rawSources = await client.from('heat_source_basics').select();
      final rawDemand = await client.from('heat_demand').select();

      final sources = _asRowList(rawSources);
      final demand = _asRowList(rawDemand);
      final scored = _buildAndSortMatches(sources, demand);

      if (!mounted) return;
      setState(() {
        _matches = scored;
        _loading = false;
        _error = null;
      });
    } catch (e, st) {
      debugPrint('MatchesPage fetch error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
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

  String _fmt(dynamic v) {
    if (v == null) return '—';
    return v.toString();
  }

  /// Temperature compatibility 0–1 (40% weight). Higher when headroom is healthy.
  double _temperatureCompatibility(double outletT, double reqT) {
    if (reqT <= 0) return 0.5;
    final excess = (outletT - reqT) / reqT;
    if (excess < 0) return 0;
    // Peak around ~12–25% headroom; penalize tiny margin and huge oversizing lightly.
    final ideal = 0.18;
    final dist = (excess - ideal).abs();
    return (1.0 - math.min(1.0, dist / 0.45)).clamp(0.0, 1.0);
  }

  /// Heat capacity match 0–1 (40% weight).
  double _capacityMatch(double peakKw, double reqVol) {
    if (reqVol <= 0) return 0.5;
    final excess = (peakKw - reqVol) / reqVol;
    if (excess < 0) return 0;
    final ideal = 0.22;
    final dist = (excess - ideal).abs();
    return (1.0 - math.min(1.0, dist / 0.55)).clamp(0.0, 1.0);
  }

  /// Operating profile similarity 0–1 (20% weight). Uses demand peak/base when present.
  double _operatingHoursSimilarity(
    Map<String, dynamic> src,
    Map<String, dynamic> snk,
  ) {
    final peak = _asDouble(snk['peak_load_kw']);
    final base = _asDouble(snk['base_load_kw']);
    if (peak == null || base == null || peak <= 0) {
      // Neutral when unknown — keeps fetch/schema tolerant.
      return 0.72;
    }
    final demandRatio = (base / peak).clamp(0.0, 1.0);
    final flow = _asDouble(src['flow_rate_kg_hr']);
    final steam = _asDouble(src['steam_pressure_bar']);
    // Rough proxy: steadier sources (higher flow/steam) align with higher duty cycles.
    final sourceStability = math.min(
      1.0,
      0.45 + 0.08 * math.min(flow ?? 0, 5000) / 5000 + 0.07 * math.min(steam ?? 0, 20) / 20,
    );
    final typical = 0.55 + 0.35 * (sourceStability - 0.45);
    final diff = (demandRatio - typical).abs();
    return (1.0 - math.min(1.0, diff / 0.4)).clamp(0.0, 1.0);
  }

  /// Weighted score 0–100: temp 40%, capacity 40%, operating profile 20%.
  double _compositeScorePercent({
    required double tempSub,
    required double capSub,
    required double hoursSub,
  }) {
    final raw = 0.4 * tempSub + 0.4 * capSub + 0.2 * hoursSub;
    return (100.0 * raw).clamp(0.0, 100.0);
  }

  List<String> _matchReasons(double tempSub, double capSub, double hoursSub) {
    final r = <String>[];
    if (tempSub >= 0.75) {
      r.add('High temperature compatibility');
    } else if (tempSub >= 0.55) {
      r.add('Solid temperature match');
    }
    if (capSub >= 0.75) {
      r.add('Strong capacity match');
    } else if (capSub >= 0.55) {
      r.add('Good capacity match');
    }
    if (hoursSub >= 0.72) {
      r.add('Similar operating profile');
    } else if (hoursSub >= 0.55) {
      r.add('Reasonable schedule fit');
    }
    if (r.isEmpty) {
      r.add('Meets feasibility thresholds');
    }
    return r;
  }

  List<_ScoredMatch> _buildAndSortMatches(
    List<Map<String, dynamic>> sources,
    List<Map<String, dynamic>> demand,
  ) {
    final out = <_ScoredMatch>[];
    var i = 0;

    for (final src in sources) {
      final outletT = _asDouble(src['outlet_temp_typical']);
      final peakKw = _asDouble(src['heat_output_peak_kw']);
      if (outletT == null || peakKw == null) continue;

      for (final snk in demand) {
        final reqT = _asDouble(snk['required_temperature']);
        final reqVol = _asDouble(snk['required_volume_kw']);
        if (reqT == null || reqVol == null) continue;

        if (outletT >= reqT && peakKw >= reqVol) {
          final tempSub = _temperatureCompatibility(outletT, reqT);
          final capSub = _capacityMatch(peakKw, reqVol);
          final hoursSub = _operatingHoursSimilarity(src, snk);
          final score = _compositeScorePercent(
            tempSub: tempSub,
            capSub: capSub,
            hoursSub: hoursSub,
          );
          final reasons = _matchReasons(tempSub, capSub, hoursSub);
          final dist = _dummyDistances[i % _dummyDistances.length];
          i++;
          out.add(
            _ScoredMatch(
              source: src,
              sink: snk,
              scorePercent: score,
              distanceLabel: dist,
              reasons: reasons,
            ),
          );
        }
      }
    }

    out.sort((a, b) => b.scorePercent.compareTo(a.scorePercent));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matches'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _fetchData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(theme)
              : RefreshIndicator(
                  onRefresh: _fetchData,
                  child: _matches.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(24),
                          children: [
                            Text(
                              'No matching pairs.',
                              style: theme.textTheme.titleMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Rules: outlet temp ≥ required temp and peak kW ≥ required volume.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _matches.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            return _matchCard(
                              theme,
                              _matches[index],
                              isBest: index == 0,
                            );
                          },
                        ),
                ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Could not load', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(
              _error!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _fetchData, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _matchCard(ThemeData theme, _ScoredMatch m, {required bool isBest}) {
    final cs = theme.colorScheme;
    final src = m.source;
    final snk = m.sink;
    final scoreRounded = m.scorePercent.round();

    return Card(
      elevation: isBest ? 2 : 0,
      color: isBest
          ? cs.primaryContainer.withValues(alpha: 0.28)
          : cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isBest ? cs.primary : cs.outlineVariant,
          width: isBest ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isBest)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(Icons.star_rounded, color: cs.primary, size: 22),
                    const SizedBox(width: 6),
                    Text(
                      'Best match',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Icon(Icons.link, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Source ↔ Demand',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Match score $scoreRounded%',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Why:',
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            ...m.reasons.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: cs.primary)),
                    Expanded(
                      child: Text(
                        line,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _metricBlock(
                    theme,
                    label: 'Source temp',
                    value: '${_fmt(src['outlet_temp_typical'])} °C',
                    sub: 'typical outlet',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _metricBlock(
                    theme,
                    label: 'Sink temp',
                    value: '${_fmt(snk['required_temperature'])} °C',
                    sub: 'required',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.place_outlined, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  'Distance: ${m.distanceLabel}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricBlock(
    ThemeData theme, {
    required String label,
    required String value,
    required String sub,
  }) {
    final cs = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              sub,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoredMatch {
  const _ScoredMatch({
    required this.source,
    required this.sink,
    required this.scorePercent,
    required this.distanceLabel,
    required this.reasons,
  });

  final Map<String, dynamic> source;
  final Map<String, dynamic> sink;
  final double scorePercent;
  final String distanceLabel;
  final List<String> reasons;
}
