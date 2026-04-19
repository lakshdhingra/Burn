import 'package:flutter/material.dart';

/// Dummy analytics dashboard (no backend).
class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  // Demo numbers — replace with real data later.
  static const double _totalAvailableGwh = 2.4;
  static const double _totalUsedGwh = 1.68;
  static const double _priceEurPerMwh = 45;

  double get _utilization =>
      _totalAvailableGwh > 0 ? _totalUsedGwh / _totalAvailableGwh : 0;

  /// Dummy: unused heat × flat €/MWh equivalent (illustrative only).
  double get _estimatedSavingsEur =>
      (_totalAvailableGwh - _totalUsedGwh) * 1000 * _priceEurPerMwh * 0.12;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Overview',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Sample figures for UI preview',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _metricCard(
            theme,
            icon: Icons.bolt_outlined,
            title: 'Total heat available',
            value: '${_totalAvailableGwh.toStringAsFixed(1)} GWh',
            subtitle: 'Aggregate supply-side capacity (demo)',
            accent: cs.primary,
          ),
          const SizedBox(height: 12),
          _metricCard(
            theme,
            icon: Icons.trending_flat_outlined,
            title: 'Total heat used',
            value: '${_totalUsedGwh.toStringAsFixed(2)} GWh',
            subtitle: 'Delivered / allocated (demo)',
            accent: cs.tertiary,
          ),
          const SizedBox(height: 12),
          _metricCard(
            theme,
            icon: Icons.savings_outlined,
            title: 'Estimated savings',
            value: '€${_estimatedSavingsEur.toStringAsFixed(0)}',
            subtitle: 'Unused capacity × demo €/MWh × 12% factor (not real billing)',
            accent: cs.secondary,
          ),
          const SizedBox(height: 24),
          _sectionCard(
            theme,
            title: 'Utilization',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Used vs available',
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      '${(_utilization * 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _utilization.clamp(0.0, 1.0),
                    minHeight: 14,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionCard(
            theme,
            title: 'Mix (demo breakdown)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _barRow(theme, 'Industrial', 0.55, cs.primary),
                const SizedBox(height: 10),
                _barRow(theme, 'District', 0.30, cs.tertiary),
                const SizedBox(height: 10),
                _barRow(theme, 'Other', 0.15, cs.outline),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color accent,
  }) {
    final cs = theme.colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: accent.withValues(alpha: 0.2),
              foregroundColor: accent,
              child: Icon(icon, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard(
    ThemeData theme, {
    required String title,
    required Widget child,
  }) {
    final cs = theme.colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _barRow(ThemeData theme, String label, double fraction, Color color) {
    final cs = theme.colorScheme;
    final f = fraction.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            Text(
              '${(f * 100).round()}%',
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: f,
            minHeight: 10,
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              color.withValues(alpha: 0.9),
            ),
          ),
        ),
      ],
    );
  }
}
