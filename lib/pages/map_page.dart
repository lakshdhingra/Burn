import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_config.dart';

/// OpenStreetMap with heat sources (red) and demand sinks (blue).
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static final LatLng _initialCenter = LatLng(52.52, 13.405);

  /// Berlin-area fallbacks when rows have no coordinates.
  static const List<LatLng> _dummyPoints = [
    LatLng(52.5359, 13.3892),
    LatLng(52.5080, 13.4313),
    LatLng(52.4934, 13.4694),
  ];

  List<Map<String, dynamic>> _sources = [];
  List<Map<String, dynamic>> _sinks = [];

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchFactories();
  }

  Future<void> _fetchFactories() async {
    if (!supabaseInitialized) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Supabase is not initialized.';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final client = Supabase.instance.client;
      final rawSources = await client.from('heat_source_basics').select();
      final rawDemand = await client.from('heat_demand').select();

      if (!mounted) return;
      setState(() {
        _sources = _asRowList(rawSources);
        _sinks = _asRowList(rawDemand);
        _loading = false;
        _error = null;
      });
    } catch (e, st) {
      debugPrint('MapPage fetch error: $e\n$st');
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

  LatLng? _readLatLng(Map<String, dynamic> row) {
    final lat = _asDouble(row['latitude']) ?? _asDouble(row['lat']);
    final lng = _asDouble(row['longitude']) ?? _asDouble(row['lng']);
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return LatLng(lat, lng);
  }

  /// Deterministic dummy position so stacked rows don't sit on identical pixels.
  LatLng _dummyCoordinate(int index) {
    final base = _dummyPoints[index % _dummyPoints.length];
    final ring = index ~/ _dummyPoints.length;
    return LatLng(
      base.latitude + ring * 0.004,
      base.longitude + ring * 0.003,
    );
  }

  void _showPinDialog(
    BuildContext context, {
    required bool isSource,
    required Map<String, dynamic> row,
    required bool usedFallback,
  }) {
    final theme = Theme.of(context);
    final lines = isSource
        ? <String>[
            'Outlet (typical): ${_fmt(row['outlet_temp_typical'])} °C',
            'Heat output (peak): ${_fmt(row['heat_output_peak_kw'])} kW',
            'Flow: ${_fmt(row['flow_rate_kg_hr'])} kg/h',
            'Steam pressure: ${_fmt(row['steam_pressure_bar'])} bar',
          ]
        : <String>[
            'Required temp: ${_fmt(row['required_temperature'])} °C',
            'Required volume: ${_fmt(row['required_volume_kw'])} kW',
            'Peak load: ${_fmt(row['peak_load_kw'])} kW',
            'Base load: ${_fmt(row['base_load_kw'])} kW',
          ];

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isSource ? Icons.local_fire_department : Icons.ac_unit,
              color: isSource ? Colors.red : Colors.blue,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isSource ? 'Heat source' : 'Heat demand',
                style: theme.textTheme.titleLarge,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (row['project_id'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Project: ${_fmt(row['project_id'])}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(line, style: theme.textTheme.bodyMedium),
                ),
              if (usedFallback)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Location on map is illustrative (no coordinates saved).',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _fmt(dynamic v) {
    if (v == null) return '—';
    return v.toString();
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    var fallbackIndex = 0;

    for (final row in _sources) {
      final parsed = _readLatLng(row);
      final usedFallback = parsed == null;
      final point = parsed ?? _dummyCoordinate(fallbackIndex++);
      markers.add(
        Marker(
          point: point,
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: _FactoryMarker(
            label: 'Heat source',
            color: Colors.red,
            onTap: () => _showPinDialog(
              context,
              isSource: true,
              row: row,
              usedFallback: usedFallback,
            ),
          ),
        ),
      );
    }

    for (final row in _sinks) {
      final parsed = _readLatLng(row);
      final usedFallback = parsed == null;
      final point = parsed ?? _dummyCoordinate(fallbackIndex++);
      markers.add(
        Marker(
          point: point,
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: _FactoryMarker(
            label: 'Heat demand',
            color: Colors.blue,
            onTap: () => _showPinDialog(
              context,
              isSource: false,
              row: row,
              usedFallback: usedFallback,
            ),
          ),
        ),
      );
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _loading ? null : _fetchFactories,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: 12,
              minZoom: 3,
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'heat_app',
              ),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),
          if (_loading)
            Positioned(
              top: 12,
              right: 12,
              child: Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
          if (_error != null && !_loading)
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(12),
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: theme.colorScheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FactoryMarker extends StatelessWidget {
  const _FactoryMarker({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: label,
          child: Icon(
            Icons.factory_outlined,
            size: 40,
            color: color,
            shadows: const [
              Shadow(
                blurRadius: 4,
                color: Colors.black54,
                offset: Offset(1, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
