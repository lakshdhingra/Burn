import 'dart:math' as math;
import 'dart:ui';
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
  final List<_ScoredMatch> _savedMatches = [];

  bool _loading = true;
  String? _error;

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

  double calculateDistance(double? lat1, double? lng1, double? lat2, double? lng2) {
    if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) {
      return 0.0;
    }
    return math.sqrt(math.pow((lat1 - lat2), 2) + math.pow((lng1 - lng2), 2)) * 111.0;
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
          
          final effectiveHeatKw = math.min(peakKw, reqVol);
          final hoursPerDay = _asDouble(src['operating_hours_per_day']) ?? 8.0;
          final energyKwh = effectiveHeatKw * hoursPerDay * 365.0;
          final costSavedRupees = energyKwh * 8.0;
          final co2SavedKg = energyKwh * 0.82;
          final roiPercent = costSavedRupees / 500000.0;

          final srcLat = _asDouble(src['latitude']) ?? _asDouble(src['lat']);
          final srcLng = _asDouble(src['longitude']) ?? _asDouble(src['lng']);
          final snkLat = _asDouble(snk['latitude']) ?? _asDouble(snk['lat']);
          final snkLng = _asDouble(snk['longitude']) ?? _asDouble(snk['lng']);

          final distVal = calculateDistance(srcLat, srcLng, snkLat, snkLng);
          final dist = distVal > 0 ? '${distVal.toStringAsFixed(1)} km' : 'Unknown';

          out.add(
            _ScoredMatch(
              source: src,
              sink: snk,
              scorePercent: score,
              distanceLabel: dist,
              reasons: reasons,
              energyKwh: energyKwh,
              costSavedRupees: costSavedRupees,
              co2SavedKg: co2SavedKg,
              roiPercent: roiPercent,
            ),
          );
        }
      }
    }

    // Sort by Score then ROI (Score primary, ROI secondary)
    out.sort((a, b) {
      final s = b.scorePercent.compareTo(a.scorePercent);
      if (s != 0) return s;
      return b.roiPercent.compareTo(a.roiPercent);
    });
    return out;
  }

  void _showUseMatchDialog(_ScoredMatch match) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Match Actions',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                _bottomSheetAction(
                  icon: Icons.analytics_outlined,
                  label: 'View Detailed Analysis',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showDetailedAnalysis(match);
                  },
                ),
                _bottomSheetAction(
                  icon: Icons.message_outlined,
                  label: 'Contact Factory',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showContactDialog();
                  },
                ),
                _bottomSheetAction(
                  icon: Icons.description_outlined,
                  label: 'Generate Proposal',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showProposal(match);
                  },
                ),
                _bottomSheetAction(
                  icon: Icons.bookmark_border,
                  label: 'Save Match',
                  onTap: () async {
                    Navigator.pop(ctx);

                    final user = Supabase.instance.client.auth.currentUser;
                    if (user == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Error: You must be logged in to save matches.')),
                      );
                      return;
                    }

                    try {
                      await Supabase.instance.client.from('matches').insert({
                        'source_id': match.source['id'] ?? match.source['project_id'],
                        'sink_id': match.sink['id'] ?? match.sink['project_id'],
                        'user_id': user.id,
                        'match_score': match.scorePercent,
                        'roi': match.roiPercent,
                        'cost_savings': match.costSavedRupees,
                        'co2_savings': match.co2SavedKg,
                      });

                      setState(() {
                        if (!_savedMatches.contains(match)) {
                          _savedMatches.add(match);
                        }
                      });

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Match saved successfully ✅')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error saving match: $e')),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bottomSheetAction({required IconData icon, required String label, required VoidCallback onTap}) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
        foregroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(icon),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  void _showDetailedAnalysis(_ScoredMatch m) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final paybackYears = m.costSavedRupees > 0 ? 500000.0 / m.costSavedRupees : 0.0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.query_stats, color: cs.primary),
            const SizedBox(width: 8),
            const Text('Detailed Analysis'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _analysisRow(Icons.bolt, 'Energy Saved', '${_fmtNum(m.energyKwh)} kWh/yr', Colors.orange),
            const Divider(),
            _analysisRow(Icons.currency_rupee, 'Cost Saved', '₹${_fmtNum(m.costSavedRupees)}/yr', Colors.green),
            const Divider(),
            _analysisRow(Icons.co2, 'CO2 Saved', '${_fmtNum(m.co2SavedKg)} kg/yr', Colors.teal),
            const Divider(),
            _analysisRow(Icons.show_chart, 'ROI', '${(m.roiPercent * 100).toStringAsFixed(1)}%', cs.primary),
            const Divider(),
            _analysisRow(Icons.timelapse, 'Payback Period', '${paybackYears.toStringAsFixed(1)} Years', cs.secondary),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))
        ],
      ),
    );
  }

  Widget _analysisRow(IconData icon, String label, String val, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
          Text(val, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  void _showContactDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Contact Factory'),
        content: const Text('How would you like to proceed with contacting the operational manager?'),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request details sent successfully!')));
            },
            child: const Text('Request Details'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connection request sent successfully!')));
            },
            child: const Text('Send Request'),
          ),
        ],
      ),
    );
  }

  void _showProposal(_ScoredMatch m) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sourceName = m.source['factory_name'] ?? 'Source Factory';
    final sinkName = m.sink['factory_name'] ?? 'Sink Factory';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified, color: Colors.green, size: 18),
                  SizedBox(width: 6),
                  Text('Status: Recommended', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Partnership Proposal', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(child: Text(sourceName.toString(), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.arrow_forward_rounded, color: Colors.grey)),
                Expanded(child: Text(sinkName.toString(), textAlign: TextAlign.left, style: const TextStyle(fontWeight: FontWeight.w600))),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  Text('Projected Annual Savings', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Text('₹${_fmtNum(m.costSavedRupees)}', style: theme.textTheme.headlineSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(children: [
                  const Icon(Icons.co2, color: Colors.teal),
                  Text('${_fmtNum(m.co2SavedKg)} kg', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Text('CO2 Cut', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
                Column(children: [
                  const Icon(Icons.show_chart, color: Colors.purple),
                  Text('${(m.roiPercent * 100).toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Text('ROI', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ])
              ],
            ),
          ],
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))
        ],
      ),
    );
  }

  void _showCalculatorDialog(BuildContext context) {
    final heatController = TextEditingController();
    final hoursController = TextEditingController();
    final costController = TextEditingController();

    double? energyKwh;
    double? costSaved;
    double? co2Saved;
    double? roiPercent;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            void calculate() {
              final heat = double.tryParse(heatController.text);
              final hours = double.tryParse(hoursController.text);
              final customCost = double.tryParse(costController.text) ?? 8.0;

              if (heat != null && hours != null && heat > 0 && hours > 0) {
                setState(() {
                  energyKwh = heat * hours * 365;
                  costSaved = energyKwh! * customCost;
                  co2Saved = energyKwh! * 0.82;
                  roiPercent = (costSaved! / 500000.0) * 100;
                });
              }
            }

            return AlertDialog(
              title: const Text('Advanced ROI Calculator'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: heatController,
                      decoration: const InputDecoration(labelText: 'Heat (kW)', prefixIcon: Icon(Icons.bolt)),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: hoursController,
                      decoration: const InputDecoration(labelText: 'Hours per day', prefixIcon: Icon(Icons.schedule)),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: costController,
                      decoration: const InputDecoration(labelText: 'Cost/kWh (Optional, default = 8)', prefixIcon: Icon(Icons.currency_rupee)),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: calculate,
                      child: const Text('Calculate'),
                    ),
                    if (energyKwh != null) ...[
                      const SizedBox(height: 24),
                      Text('Energy: ${energyKwh!.toStringAsFixed(0)} kWh/yr', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Cost Saved: ₹${costSaved!.toStringAsFixed(0)}/yr', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('CO2 Saved: ${co2Saved!.toStringAsFixed(0)} kg/yr', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('ROI: ${roiPercent!.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                    ]
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Matches', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calculate_outlined),
            tooltip: 'ROI Calculator',
            onPressed: () => _showCalculatorDialog(context),
          ),
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
                            return TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: Duration(milliseconds: 400 + (index * 100)),
                              curve: Curves.easeOutCubic,
                              builder: (context, val, child) => Transform.translate(
                                offset: Offset(0, 30 * (1 - val)),
                                child: Opacity(opacity: val, child: child),
                              ),
                              child: _matchCard(
                                theme,
                                _matches[index],
                                isBest: index == 0,
                              ),
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

    final isSaved = _savedMatches.contains(m);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: isBest
                ? cs.primaryContainer.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.05),
            boxShadow: [
              if (isBest || isSaved)
                BoxShadow(
                  color: isSaved ? Colors.green.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.25),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                )
            ],
            border: Border.all(
              color: isSaved ? Colors.green : (isBest ? cs.primary.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.1)),
              width: isBest || isSaved ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isSaved) 
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    const Icon(Icons.bookmark, color: Colors.green, size: 20),
                    const SizedBox(width: 6),
                    Text(
                      'Saved Match',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            else if (isBest)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(Icons.emoji_events, color: cs.primary, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Match of the Day',
                      style: theme.textTheme.titleSmall?.copyWith(
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
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _calcMetric(
                  theme: theme,
                  icon: Icons.bolt,
                  label: 'Energy Saved',
                  value: '${_fmtNum(m.energyKwh)} kWh/yr',
                ),
                _calcMetric(
                  theme: theme,
                  icon: Icons.currency_rupee,
                  label: 'Cost Saved',
                  value: '₹${_fmtNum(m.costSavedRupees)}/yr',
                ),
                _calcMetric(
                  theme: theme,
                  icon: Icons.co2,
                  label: 'CO2 Saved',
                  value: '${_fmtNum(m.co2SavedKg)} kg/yr',
                ),
                _calcMetric(
                  theme: theme,
                  icon: Icons.show_chart,
                  label: 'ROI',
                  value: '${(m.roiPercent * 100).toStringAsFixed(1)}%',
                  isHighlight: true,
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _showUseMatchDialog(m),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Use This Match'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);
}

  String _fmtNum(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  Widget _calcMetric(
      {required ThemeData theme,
      required IconData icon,
      required String label,
      required String value,
      bool isHighlight = false}) {
    final cs = theme.colorScheme;
    return Column(
      children: [
        Icon(icon, size: 20, color: isHighlight ? cs.primary : cs.onSurfaceVariant),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: isHighlight ? cs.primary : null,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
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
    required this.energyKwh,
    required this.costSavedRupees,
    required this.co2SavedKg,
    required this.roiPercent,
  });

  final Map<String, dynamic> source;
  final Map<String, dynamic> sink;
  final double scorePercent;
  final String distanceLabel;
  final List<String> reasons;
  final double energyKwh;
  final double costSavedRupees;
  final double co2SavedKg;
  final double roiPercent;
}
