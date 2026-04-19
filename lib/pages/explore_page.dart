import 'package:flutter/material.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  final TextEditingController _heatController = TextEditingController();
  final TextEditingController _hoursController = TextEditingController();

  double? _energyKwh;
  double? _costSavedRupees;
  double? _co2SavedKg;
  double? _roiPercent;

  @override
  void dispose() {
    _heatController.dispose();
    _hoursController.dispose();
    super.dispose();
  }

  void _calculate() {
    final heatKw = double.tryParse(_heatController.text);
    final hours = double.tryParse(_hoursController.text);

    if (heatKw == null || hours == null || heatKw <= 0 || hours <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid positive numbers.')),
      );
      return;
    }

    setState(() {
      _energyKwh = heatKw * hours * 365;
      final cost = _energyKwh! * 8.0;
      _costSavedRupees = cost;
      _co2SavedKg = _energyKwh! * 0.82;
      _roiPercent = cost / 500000.0;
    });
  }

  String _fmtNum(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore / Calculator'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Input Parameters',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _heatController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Heat (kW)',
                prefixIcon: const Icon(Icons.bolt_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hoursController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Hours per day',
                prefixIcon: const Icon(Icons.schedule_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _calculate,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Calculate'),
            ),
            if (_energyKwh != null) ...[
              const SizedBox(height: 48),
              Text(
                'Results',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                color: cs.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _resultRow(theme, Icons.bolt, 'Energy (kWh/yr)', '${_energyKwh!.toStringAsFixed(0)} kWh'),
                      const Divider(height: 24),
                      _resultRow(theme, Icons.currency_rupee, 'Cost Saved (₹/yr)', '₹${_fmtNum(_costSavedRupees!)}'),
                      const Divider(height: 24),
                      _resultRow(theme, Icons.co2, 'CO2 Saved (kg/yr)', '${_co2SavedKg!.toStringAsFixed(0)} kg'),
                      const Divider(height: 24),
                      _resultRow(theme, Icons.show_chart, 'ROI', '${(_roiPercent! * 100).toStringAsFixed(1)}%', isHighlight: true),
                    ],
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _resultRow(ThemeData theme, IconData icon, String label, String value, {bool isHighlight = false}) {
    final cs = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, color: isHighlight ? cs.primary : cs.onSurfaceVariant, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: isHighlight ? cs.primary : cs.onSurface,
              fontWeight: isHighlight ? FontWeight.bold : null,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: isHighlight ? cs.primary : null,
          ),
        ),
      ],
    );
  }
}
