import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_config.dart';

/// RFC 4122 version-4 UUID (no extra packages).
String _generateUuidV4() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}

/// Multi-step factory data entry; submits to Supabase on Finish.
class FullFactoryFormPage extends StatefulWidget {
  const FullFactoryFormPage({super.key});

  @override
  State<FullFactoryFormPage> createState() => _FullFactoryFormPageState();
}

class _FullFactoryFormPageState extends State<FullFactoryFormPage> {
  static const int _totalSteps = 3;

  int _step = 0;

  bool _submitting = false;

  /// `null` until user picks on step 1.
  String? _role; // 'source' | 'sink'

  /// Shared: maps to outlet_temp_typical (source) or required_temperature (sink).
  final TextEditingController _temperatureController = TextEditingController();

  /// Shared: heat_output_peak_kw (source) or required_volume_kw (sink).
  final TextEditingController _volumeController = TextEditingController();

  // heat_source_basics — extra
  final TextEditingController _outletTempMinController = TextEditingController();
  final TextEditingController _outletTempMaxController = TextEditingController();
  final TextEditingController _flowRateKgHrController = TextEditingController();
  final TextEditingController _steamPressureBarController =
      TextEditingController();

  // heat_demand — extra
  final TextEditingController _minAcceptableTempController =
      TextEditingController();
  final TextEditingController _maxAcceptableTempController =
      TextEditingController();
  final TextEditingController _peakLoadKwController = TextEditingController();
  final TextEditingController _baseLoadKwController = TextEditingController();

  /// UI-only (not sent to Supabase).
  String _heatType = 'Hot water';

  /// UI-only (not sent to Supabase).
  bool _continuousOperation = true;

  static const List<String> _heatTypeOptions = [
    'Steam',
    'Hot water',
    'Thermal oil',
    'Other',
  ];

  static const double _tempSliderMin = 0;
  static const double _tempSliderMax = 500;

  @override
  void initState() {
    super.initState();
    _seedDefaultsIfEmpty();
  }

  void _seedDefaultsIfEmpty() {
    if (_temperatureController.text.isEmpty) _temperatureController.text = '60.0';
    if (_outletTempMinController.text.isEmpty) _outletTempMinController.text = '50.0';
    if (_outletTempMaxController.text.isEmpty) _outletTempMaxController.text = '75.0';
    if (_minAcceptableTempController.text.isEmpty) {
      _minAcceptableTempController.text = '40.0';
    }
    if (_maxAcceptableTempController.text.isEmpty) {
      _maxAcceptableTempController.text = '55.0';
    }
  }

  @override
  void dispose() {
    _temperatureController.dispose();
    _volumeController.dispose();
    _outletTempMinController.dispose();
    _outletTempMaxController.dispose();
    _flowRateKgHrController.dispose();
    _steamPressureBarController.dispose();
    _minAcceptableTempController.dispose();
    _maxAcceptableTempController.dispose();
    _peakLoadKwController.dispose();
    _baseLoadKwController.dispose();
    super.dispose();
  }

  void _next() {
    if (_step >= _totalSteps - 1) return;
    setState(() => _step++);
  }

  void _back() {
    if (_step <= 0) return;
    setState(() => _step--);
  }

  bool get _step1FieldsComplete {
    bool nonEmpty(String s) => s.trim().isNotEmpty;
    if (_role == 'source') {
      return nonEmpty(_temperatureController.text) &&
          nonEmpty(_outletTempMinController.text) &&
          nonEmpty(_outletTempMaxController.text) &&
          nonEmpty(_volumeController.text) &&
          nonEmpty(_flowRateKgHrController.text) &&
          nonEmpty(_steamPressureBarController.text);
    }
    if (_role == 'sink') {
      return nonEmpty(_temperatureController.text) &&
          nonEmpty(_volumeController.text) &&
          nonEmpty(_minAcceptableTempController.text) &&
          nonEmpty(_maxAcceptableTempController.text) &&
          nonEmpty(_peakLoadKwController.text) &&
          nonEmpty(_baseLoadKwController.text);
    }
    return false;
  }

  bool get _canGoNext {
    switch (_step) {
      case 0:
        return _role != null;
      case 1:
        return _step1FieldsComplete;
      default:
        return true;
    }
  }

  double? _parseDouble(String raw) {
    final s = raw.trim().replaceAll(',', '.');
    return double.tryParse(s);
  }

  InputDecoration _inputDecoration(ThemeData theme) {
    return InputDecoration(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
    );
  }

  List<TextInputFormatter> get _unsignedDecimalFormatters => [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ];

  Widget _sectionCard({
    required ThemeData theme,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    final cs = theme.colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
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
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _temperatureSlider(
    ThemeData theme,
    String label,
    TextEditingController c,
  ) {
    final raw = _parseDouble(c.text);
    final v = (raw ?? (_tempSliderMin + _tempSliderMax) / 2)
        .clamp(_tempSliderMin, _tempSliderMax);
    final divisions =
        ((_tempSliderMax - _tempSliderMin) * 2).round().clamp(1, 320);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleSmall,
              ),
            ),
            Text(
              '${v.round()} °C',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: v,
          min: _tempSliderMin,
          max: _tempSliderMax,
          divisions: divisions,
          label: '${v.round()} °C',
          onChanged: (nv) {
            setState(() {
              c.text = nv.round().toString();
            });
          },
        ),
      ],
    );
  }

  Widget _heatProfileCard(ThemeData theme) {
    final deco = _inputDecoration(theme);
    return _sectionCard(
      theme: theme,
      title: 'Heat profile',
      subtitle: 'Type and operation (preview only — not saved)',
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InputDecorator(
            decoration: deco.copyWith(
              labelText: 'Heat type',
              prefixIcon: const Icon(Icons.category_outlined),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _heatType,
                isExpanded: true,
                borderRadius: BorderRadius.circular(12),
                items: _heatTypeOptions
                    .map(
                      (e) =>
                          DropdownMenuItem<String>(value: e, child: Text(e)),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _heatType = v);
                },
              ),
            ),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            value: _continuousOperation,
            onChanged: (v) => setState(() => _continuousOperation = v),
            title: const Text('Continuous operation'),
            subtitle: const Text('Fewer long shutdowns'),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;

    if (!supabaseInitialized) {
      debugPrint('submit: supabase not initialized');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Authentication is unavailable.')),
      );
      return;
    }

    final role = _role;
    if (role == null) {
      debugPrint('submit: role is null');
      return;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('submit: no authenticated user');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in to save.')),
      );
      return;
    }

    late final Map<String, dynamic> row;
    if (role == 'source') {
      final outletTempTypical = _parseDouble(_temperatureController.text);
      final outletTempMin = _parseDouble(_outletTempMinController.text);
      final outletTempMax = _parseDouble(_outletTempMaxController.text);
      final heatOutputPeakKw = _parseDouble(_volumeController.text);
      final flowRate = _parseDouble(_flowRateKgHrController.text);
      final steamBar = _parseDouble(_steamPressureBarController.text);

      if (outletTempTypical == null ||
          outletTempMin == null ||
          outletTempMax == null ||
          heatOutputPeakKw == null ||
          flowRate == null ||
          steamBar == null) {
        debugPrint('submit: invalid source numeric fields');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter valid numbers for all heat source fields.'),
          ),
        );
        return;
      }

      row = {
        'outlet_temp_typical': outletTempTypical,
        'outlet_temp_min': outletTempMin,
        'outlet_temp_max': outletTempMax,
        'heat_output_peak_kw': heatOutputPeakKw,
        'flow_rate_kg_hr': flowRate,
        'steam_pressure_bar': steamBar,
      };
    } else {
      final reqTemp = _parseDouble(_temperatureController.text);
      final reqVol = _parseDouble(_volumeController.text);
      final minAcc = _parseDouble(_minAcceptableTempController.text);
      final maxAcc = _parseDouble(_maxAcceptableTempController.text);
      final peakLoad = _parseDouble(_peakLoadKwController.text);
      final baseLoad = _parseDouble(_baseLoadKwController.text);

      if (reqTemp == null ||
          reqVol == null ||
          minAcc == null ||
          maxAcc == null ||
          peakLoad == null ||
          baseLoad == null) {
        debugPrint('submit: invalid demand numeric fields');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter valid numbers for all heat demand fields.'),
          ),
        );
        return;
      }

      row = {
        'required_temperature': reqTemp,
        'required_volume_kw': reqVol,
        'min_acceptable_temperature': minAcc,
        'max_acceptable_temperature': maxAcc,
        'peak_load_kw': peakLoad,
        'base_load_kw': baseLoad,
      };
    }

    final projectId = _generateUuidV4();
    debugPrint('submit: project_id=$projectId user_id=$userId');

    setState(() => _submitting = true);

    try {
      final client = Supabase.instance.client;

      if (role == 'source') {
        debugPrint('submit: inserting heat_source_basics project_id=$projectId');
        await client.from('heat_source_basics').insert({
          'project_id': projectId,
          'user_id': userId,
          ...row,
        });
        debugPrint('submit: heat_source_basics insert success');
      } else {
        debugPrint('submit: inserting heat_demand project_id=$projectId');
        await client.from('heat_demand').insert({
          'project_id': projectId,
          'user_id': userId,
          ...row,
        });
        debugPrint('submit: heat_demand insert success');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved successfully')),
      );
    } catch (e, st) {
      debugPrint('submit error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stepLabel = 'Step ${_step + 1} / $_totalSteps';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Factory setup'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    stepLabel,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (_step + 1) / _totalSteps,
                        minHeight: 6,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: KeyedSubtree(
                  key: ValueKey<int>(_step),
                  child: _buildStepContent(theme),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _step > 0 ? _back : null,
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: (!_canGoNext || _submitting)
                          ? null
                          : (_step < _totalSteps - 1 ? _next : _submit),
                      child: Text(
                        _step < _totalSteps - 1 ? 'Next' : 'Finish',
                      ),
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

  Widget _buildStepContent(ThemeData theme) {
    switch (_step) {
      case 0:
        return _buildRoleStep(theme);
      case 1:
        return _buildBasicFieldsStep(theme);
      default:
        return _buildReviewStep(theme);
    }
  }

  Widget _buildRoleStep(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Select role',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Is this facility a heat source or a heat sink?',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          _roleCard(
            theme,
            title: 'Heat Source',
            subtitle: 'Supplies thermal energy',
            value: 'source',
            icon: Icons.local_fire_department_outlined,
          ),
          const SizedBox(height: 12),
          _roleCard(
            theme,
            title: 'Heat Sink',
            subtitle: 'Absorbs or requires heat removal',
            value: 'sink',
            icon: Icons.ac_unit_outlined,
          ),
        ],
      ),
    );
  }

  Widget _roleCard(
    ThemeData theme, {
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
  }) {
    final selected = _role == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _role = value),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
            color: selected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                : theme.colorScheme.surfaceContainerLow,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 36,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBasicFieldsStep(ThemeData theme) {
    final deco = _inputDecoration(theme);

    if (_role == 'source') {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Heat source parameters',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Outlet conditions, capacity, and steam data.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _heatProfileCard(theme),
            const SizedBox(height: 12),
            _sectionCard(
              theme: theme,
              title: 'Outlet temperatures',
              subtitle: 'Adjust with sliders (°C)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _temperatureSlider(
                    theme,
                    'Outlet temp (typical)',
                    _temperatureController,
                  ),
                  const SizedBox(height: 8),
                  _temperatureSlider(
                    theme,
                    'Outlet temp (min)',
                    _outletTempMinController,
                  ),
                  const SizedBox(height: 8),
                  _temperatureSlider(
                    theme,
                    'Outlet temp (max)',
                    _outletTempMaxController,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _sectionCard(
              theme: theme,
              title: 'Capacity & steam',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                      controller: _volumeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: _unsignedDecimalFormatters,
                      onChanged: (_) => setState(() {}),
                      decoration: deco.copyWith(
                        labelText: 'Heat Output (kW)',
                        hintText: 'kW',
                        suffixText: 'kW',
                        prefixIcon: const Icon(Icons.bolt_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _flowRateKgHrController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: _unsignedDecimalFormatters,
                      onChanged: (_) => setState(() {}),
                      decoration: deco.copyWith(
                        labelText: 'Flow Rate (m³/hour)',
                        hintText: 'kg/hr',
                        suffixText: 'm³/hr',
                        prefixIcon: const Icon(Icons.water_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _steamPressureBarController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: _unsignedDecimalFormatters,
                      onChanged: (_) => setState(() {}),
                      decoration: deco.copyWith(
                        labelText: 'Steam Pressure (bar)',
                        hintText: 'bar',
                        suffixText: 'bar',
                        prefixIcon: const Icon(Icons.speed_outlined),
                      ),
                    ),
                  ],
                ),
            ),
          ],
        ),
      );
    }

    if (_role == 'sink') {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Heat demand parameters',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Required conditions, acceptable range, and loads.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _heatProfileCard(theme),
            const SizedBox(height: 12),
            _sectionCard(
              theme: theme,
              title: 'Temperature',
              subtitle: 'Adjust with sliders (°C)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _temperatureSlider(
                    theme,
                    'Required temperature',
                    _temperatureController,
                  ),
                  const SizedBox(height: 8),
                  _temperatureSlider(
                    theme,
                    'Min acceptable temperature',
                    _minAcceptableTempController,
                  ),
                  const SizedBox(height: 8),
                  _temperatureSlider(
                    theme,
                    'Max acceptable temperature',
                    _maxAcceptableTempController,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _sectionCard(
              theme: theme,
              title: 'Volume & load',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                      controller: _volumeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: _unsignedDecimalFormatters,
                      onChanged: (_) => setState(() {}),
                      decoration: deco.copyWith(
                        labelText: 'Required Volume (kW)',
                        hintText: 'kW',
                        suffixText: 'kW',
                        prefixIcon: const Icon(Icons.inventory_2_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _peakLoadKwController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: _unsignedDecimalFormatters,
                      onChanged: (_) => setState(() {}),
                      decoration: deco.copyWith(
                        labelText: 'Peak Load (kW)',
                        hintText: 'kW',
                        suffixText: 'kW',
                        prefixIcon: const Icon(Icons.trending_up_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _baseLoadKwController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: _unsignedDecimalFormatters,
                      onChanged: (_) => setState(() {}),
                      decoration: deco.copyWith(
                        labelText: 'Base Load (kW)',
                        hintText: 'kW',
                        suffixText: 'kW',
                        prefixIcon: const Icon(Icons.trending_flat_outlined),
                      ),
                    ),
                  ],
                ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Select a role first.',
          style: theme.textTheme.bodyLarge,
        ),
      ),
    );
  }

  Widget _buildReviewStep(ThemeData theme) {
    final roleLabel = _role == 'sink' ? 'Heat Sink' : 'Heat Source';
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Review',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Confirm the details below before finishing.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _reviewRow(theme, 'Role', roleLabel),
                  const Divider(height: 24),
                  _reviewRow(theme, 'Heat type', _heatType),
                  const Divider(height: 24),
                  _reviewRow(
                    theme,
                    'Continuous operation',
                    _continuousOperation ? 'Yes' : 'No',
                  ),
                  const Divider(height: 24),
                  if (_role == 'source') ...[
                    _reviewRow(
                      theme,
                      'Outlet temp (typical)',
                      _temperatureController.text,
                    ),
                    const Divider(height: 24),
                    _reviewRow(
                      theme,
                      'Outlet temp (min)',
                      _outletTempMinController.text,
                    ),
                    const Divider(height: 24),
                    _reviewRow(
                      theme,
                      'Outlet temp (max)',
                      _outletTempMaxController.text,
                    ),
                    const Divider(height: 24),
                    _reviewRow(
                      theme,
                      'Heat output (peak kW)',
                      _volumeController.text,
                    ),
                    const Divider(height: 24),
                    _reviewRow(
                      theme,
                      'Flow rate (kg/hr)',
                      _flowRateKgHrController.text,
                    ),
                    const Divider(height: 24),
                    _reviewRow(
                      theme,
                      'Steam pressure (bar)',
                      _steamPressureBarController.text,
                    ),
                  ] else if (_role == 'sink') ...[
                    _reviewRow(
                      theme,
                      'Required temperature',
                      _temperatureController.text,
                    ),
                    const Divider(height: 24),
                    _reviewRow(
                      theme,
                      'Required volume',
                      _volumeController.text,
                    ),
                    const Divider(height: 24),
                    _reviewRow(
                      theme,
                      'Min acceptable temp',
                      _minAcceptableTempController.text,
                    ),
                    const Divider(height: 24),
                    _reviewRow(
                      theme,
                      'Max acceptable temp',
                      _maxAcceptableTempController.text,
                    ),
                    const Divider(height: 24),
                    _reviewRow(theme, 'Peak load (kW)', _peakLoadKwController.text),
                    const Divider(height: 24),
                    _reviewRow(theme, 'Base load (kW)', _baseLoadKwController.text),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewRow(ThemeData theme, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value.isEmpty ? '—' : value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
