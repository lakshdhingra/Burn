import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_config.dart';

/// Fetches heat sources and demand from Supabase; pairs rows by simple rules.
class MatchPage extends StatefulWidget {
  const MatchPage({super.key});

  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> {
  List<Map<String, dynamic>> _sources = [];
  List<Map<String, dynamic>> _demand = [];

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

      if (!mounted) return;
      setState(() {
        _sources = sources;
        _demand = demand;
        _loading = false;
        _error = null;
      });
    } catch (e, st) {
      debugPrint('MatchPage fetch error: $e\n$st');
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

  String _fmt(dynamic v) {
    if (v == null) return '—';
    return v.toString();
  }

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.'));
  }

  /// Match when source can meet sink temperature and capacity needs.
  List<_SourceSinkMatch> _computeMatches() {
    final out = <_SourceSinkMatch>[];
    for (final src in _sources) {
      final outletT = _asDouble(src['outlet_temp_typical']);
      final peakKw = _asDouble(src['heat_output_peak_kw']);
      if (outletT == null || peakKw == null) continue;

      for (final snk in _demand) {
        final reqT = _asDouble(snk['required_temperature']);
        final reqVol = _asDouble(snk['required_volume_kw']);
        if (reqT == null || reqVol == null) continue;

        if (outletT >= reqT && peakKw >= reqVol) {
          out.add(_SourceSinkMatch(source: src, sink: snk));
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Match'),
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
                  child: _buildListView(theme),
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
            Text(
              'Could not load data',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(
              _error!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _fetchData,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListView(ThemeData theme) {
    final matches = _computeMatches();

    if (_sources.isEmpty && _demand.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'No rows yet.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _sectionHeader(theme, 'Matched pairs', Icons.handshake_outlined),
        const SizedBox(height: 4),
        Text(
          'Rule: outlet temp ≥ required temp and peak kW ≥ required volume.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (matches.isEmpty)
          _emptyLine(theme, 'No matching source–demand pairs')
        else
          ...matches.asMap().entries.map(
                (e) => _matchCard(theme, e.key + 1, e.value),
              ),
        const SizedBox(height: 24),
        _sectionHeader(theme, 'Heat sources', Icons.local_fire_department_outlined),
        const SizedBox(height: 8),
        if (_sources.isEmpty)
          _emptyLine(theme, 'No heat sources')
        else
          ..._sources.map((row) => _sourceTile(theme, row)),
        const SizedBox(height: 24),
        _sectionHeader(theme, 'Heat demand', Icons.ac_unit_outlined),
        const SizedBox(height: 8),
        if (_demand.isEmpty)
          _emptyLine(theme, 'No demand entries')
        else
          ..._demand.map((row) => _demandTile(theme, row)),
      ],
    );
  }

  Widget _sectionHeader(ThemeData theme, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 22, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _emptyLine(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// Temperature: [outlet_temp_typical], output: [heat_output_peak_kw]
  Widget _sourceTile(ThemeData theme, Map<String, dynamic> row) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          'Temperature: ${_fmt(row['outlet_temp_typical'])} °C (typical)',
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Heat output (peak): ${_fmt(row['heat_output_peak_kw'])} kW',
          ),
        ),
      ),
    );
  }

  /// Temperature: [required_temperature], demand: [required_volume_kw]
  Widget _demandTile(ThemeData theme, Map<String, dynamic> row) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          'Temperature: ${_fmt(row['required_temperature'])} °C (required)',
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Demand (volume): ${_fmt(row['required_volume_kw'])}',
          ),
        ),
      ),
    );
  }

  Widget _matchCard(ThemeData theme, int n, _SourceSinkMatch m) {
    final src = m.source;
    final snk = m.sink;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.link, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Match $n',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _matchSide(
                    theme,
                    label: 'Source',
                    color: theme.colorScheme.tertiaryContainer,
                    lines: [
                      'Outlet temp: ${_fmt(src['outlet_temp_typical'])} °C',
                      'Peak output: ${_fmt(src['heat_output_peak_kw'])} kW',
                      if (src['project_id'] != null)
                        'project_id: ${_fmt(src['project_id'])}',
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.arrow_forward,
                    color: theme.colorScheme.outline,
                    size: 20,
                  ),
                ),
                Expanded(
                  child: _matchSide(
                    theme,
                    label: 'Demand',
                    color: theme.colorScheme.secondaryContainer,
                    lines: [
                      'Required temp: ${_fmt(snk['required_temperature'])} °C',
                      'Required vol: ${_fmt(snk['required_volume_kw'])}',
                      if (snk['project_id'] != null)
                        'project_id: ${_fmt(snk['project_id'])}',
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _matchSide(
    ThemeData theme, {
    required String label,
    required Color color,
    required List<String> lines,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(line, style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}

/// One feasible pairing from [_MatchPageState._computeMatches].
class _SourceSinkMatch {
  const _SourceSinkMatch({required this.source, required this.sink});

  final Map<String, dynamic> source;
  final Map<String, dynamic> sink;
}
