import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/services/ble_ecg_service.dart';

class EcgScreen extends StatefulWidget {
  const EcgScreen({
    super.key,
    required this.name,
    required this.sex,
    required this.age,
  });

  final String name;
  final String sex;
  final String age;

  @override
  State<EcgScreen> createState() => _EcgScreenState();
}

class _EcgScreenState extends State<EcgScreen> {
  // ── Paleta ───────────────────────────────────────────────────────
  static const Color _primary = Color(0xFFF78B94);
  static const Color _soft    = Color(0xFFF8ABBB);
  static const Color _pale    = Color(0xFFFADEDF);
  static const Color _white   = Colors.white;

  // ── ECG config ───────────────────────────────────────────────────
  static const int _sampleRateHz      = 250;
  static const int _visibleSeconds    = 5;
  static const int _maxVisibleSamples = _sampleRateHz * _visibleSeconds;
  static const double _adcMin         = 0;
  static const double _adcMax         = 4095;

  // ── BLE ──────────────────────────────────────────────────────────
  late final BleEcgService _bleService;
  StreamSubscription<int>? _ecgSub;

  // ── Estado ───────────────────────────────────────────────────────
  final List<FlSpot> _spots = [];
  int _x = 0;

  String _status       = 'Desconectado';
  bool _isConnecting   = false;
  bool _isConnected    = false;

  // ── Alertas ──────────────────────────────────────────────────────
  bool _alertsEnabled  = true;

  @override
  void initState() {
    super.initState();
    _bleService = BleEcgService(deviceName: 'ECG_Device');
  }

  @override
  void dispose() {
    _ecgSub?.cancel();
    _bleService.dispose();
    super.dispose();
  }

  // ── Permisos ─────────────────────────────────────────────────────
  Future<void> _requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  // ── Helpers de nombre ─────────────────────────────────────────────
  String _deviceName(ScanResult r) {
    if (r.device.platformName.isNotEmpty) return r.device.platformName;
    if (r.advertisementData.advName.isNotEmpty) return r.advertisementData.advName;
    return 'Sin nombre';
  }

  bool _hasName(ScanResult r) =>
      r.device.platformName.isNotEmpty || r.advertisementData.advName.isNotEmpty;

  bool _isTarget(ScanResult r) =>
      r.device.platformName == _bleService.deviceName ||
      r.advertisementData.advName == _bleService.deviceName;

  List<ScanResult> _sorted(List<ScanResult> raw) {
    final byId = <String, ScanResult>{};
    for (final r in raw) {
      byId[r.device.remoteId.toString()] = r;
    }
    return byId.values.toList()
      ..sort((a, b) {
        final t = (_isTarget(b) ? 1 : 0).compareTo(_isTarget(a) ? 1 : 0);
        if (t != 0) return t;
        final n = (_hasName(b) ? 1 : 0).compareTo(_hasName(a) ? 1 : 0);
        if (n != 0) return n;
        return b.rssi.compareTo(a.rssi);
      });
  }

  // ── Diálogo de selección BLE ─────────────────────────────────────
  Future<ScanResult?> _pickDevice() async {
    await _bleService.startDeviceScan(timeout: const Duration(seconds: 15));
    if (!mounted) {
      await _bleService.stopDeviceScan();
      return null;
    }

    final selected = await showDialog<ScanResult>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _white,
        title: const Text(
          'Dispositivos BLE',
          style: TextStyle(
            fontFamily: 'serif',
            color: Color(0xFF444444),
            fontWeight: FontWeight.w700,
          ),
        ),
        content: StreamBuilder<List<ScanResult>>(
          stream: _bleService.scanResults,
          builder: (ctx, snap) {
            final results = _sorted(snap.data ?? []);

            if (results.isEmpty) {
              return const SizedBox(
                width: double.maxFinite,
                height: 140,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFFF78B94)),
                      SizedBox(height: 16),
                      Text('Escaneando dispositivos...'),
                    ],
                  ),
                ),
              );
            }

            return SizedBox(
              width: double.maxFinite,
              height: 320,
              child: ListView.separated(
                itemCount: results.length,
                separatorBuilder: (_, _a) =>
                    const Divider(height: 1, color: Color(0xFFFADEDF)),
                itemBuilder: (ctx, i) {
                  final r = results[i];
                  return ListTile(
                    leading: Icon(
                      Icons.bluetooth,
                      color: _isTarget(r) ? _primary : _soft,
                    ),
                    title: Text(
                      _deviceName(r),
                      style: const TextStyle(fontFamily: 'serif'),
                    ),
                    subtitle: Text(
                      '${r.device.remoteId} · RSSI: ${r.rssi}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () => Navigator.of(ctx).pop(r),
                  );
                },
              ),
            );
          },
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _primary),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    await _bleService.stopDeviceScan();
    return selected;
  }

  // ── Conectar ─────────────────────────────────────────────────────
  Future<void> _connect() async {
    setState(() {
      _isConnecting = true;
      _status = 'Pidiendo permisos...';
    });

    try {
      await _requestPermissions();
      setState(() => _status = 'Escaneando...');

      final selected = await _pickDevice();
      if (selected == null) {
        setState(() {
          _status = 'Sin dispositivo seleccionado';
          _isConnecting = false;
        });
        return;
      }

      setState(() => _status = 'Conectando a ${_deviceName(selected)}...');

      final device = await _bleService.connectToDevice(selected.device);

      await _ecgSub?.cancel();
      _ecgSub = _bleService.ecgStream.listen((sample) {
        setState(() {
          _spots.add(FlSpot(_x.toDouble(), sample.toDouble()));
          _x++;
          if (_spots.length > _maxVisibleSamples) _spots.removeAt(0);
        });
      });

      setState(() {
        _status      = 'Conectado a ${device.platformName}';
        _isConnected = true;
        _isConnecting = false;
      });
    } catch (e) {
      setState(() {
        _status      = 'Error: $e';
        _isConnected = false;
        _isConnecting = false;
      });
    }
  }

  // ── Desconectar ──────────────────────────────────────────────────
  Future<void> _disconnect() async {
    setState(() {
      _isConnecting = true;
      _status = 'Desconectando...';
    });

    try {
      await _ecgSub?.cancel();
      _ecgSub = null;
      await _bleService.disconnect();
    } catch (e) {
      debugPrint('Error al desconectar: $e');
    }

    if (!mounted) return;
    setState(() {
      _status       = 'Desconectado';
      _isConnected  = false;
      _isConnecting = false;
      _spots.clear();
      _x = 0;
    });
  }

  // ── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _white,
      endDrawer: _buildAlertDrawer(),
      appBar: AppBar(
        backgroundColor: _primary,
        elevation: 2,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Heartbeat',
          style: TextStyle(
            fontFamily: 'serif',
            color: _white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.notifications_outlined, color: _white),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Título sección ─────────────────────────────────────
            Container(
              width: double.infinity,
              height: 50,
              color: _white,
              alignment: Alignment.center,
              child: const Text(
                'Electrocardiograma',
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 16,
                  color: _soft,
                  letterSpacing: 0.5,
                ),
              ),
            ),

            // ── Zona de gráfica / botones ──────────────────────────
            Container(
              width: double.infinity,
              height: 230,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _pale, width: 1.5),
              ),
              child: _isConnected ? _buildChart() : _buildConnectPanel(),
            ),

            const Divider(thickness: 2, color: _pale, height: 24),

            // ── Frecuencia cardiaca ────────────────────────────────
            _InfoTile(
              label: 'Frecuencia cardiaca:',
              value: '— lpm',
              color: _pale,
            ),

            const Divider(thickness: 2, color: _pale, height: 1),

            // ── Zona ──────────────────────────────────────────────
            _InfoTile(
              label: 'Zona de frecuencia cardiaca:',
              value: '—',
              color: _pale,
            ),

            const Divider(thickness: 2, color: _pale, height: 1),

            // ── Estado BLE ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    color: _isConnected ? _primary : Colors.grey,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _status,
                      style: TextStyle(
                        fontFamily: 'serif',
                        fontSize: 13,
                        color: Colors.grey.shade600,
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

  // ── Panel con botones (cuando está desconectado) ──────────────────
  Widget _buildConnectPanel() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.monitor_heart_outlined,
            size: 48,
            color: _soft,
          ),
          const SizedBox(height: 16),
          const Text(
            'Sin señal ECG',
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 15,
              color: Color(0xFF888888),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Botón Conectar
              ElevatedButton.icon(
                onPressed: (_isConnecting || _isConnected) ? null : _connect,
                icon: const Icon(Icons.bluetooth_searching, size: 18),
                label: const Text('Conectar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: _white,
                  disabledBackgroundColor: _soft,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'serif',
                    fontSize: 15,
                  ),
                  elevation: 0,
                ),
              ),
              const SizedBox(width: 12),
              // Botón Desconectar
              OutlinedButton.icon(
                onPressed: (_isConnecting || !_isConnected) ? null : _disconnect,
                icon: const Icon(Icons.bluetooth_disabled, size: 18),
                label: const Text('Desconectar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primary,
                  side: const BorderSide(color: _primary),
                  disabledForegroundColor: _soft,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'serif',
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          if (_isConnecting) ...[
            const SizedBox(height: 16),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Gráfica ECG en vivo ───────────────────────────────────────────
  Widget _buildChart() {
    final minX = _spots.isEmpty ? 0.0 : _spots.first.x;
    final maxX = _spots.isEmpty
        ? _maxVisibleSamples.toDouble()
        : (_spots.first.x + _maxVisibleSamples);

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: LineChart(
            LineChartData(
              minX: minX,
              maxX: maxX,
              minY: _adcMin,
              maxY: _adcMax,
              clipData: const FlClipData.all(),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: 1024,
                verticalInterval: 250,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: _pale,
                  strokeWidth: 1,
                ),
                getDrawingVerticalLine: (_) => FlLine(
                  color: _pale,
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: _pale, width: 1),
              ),
              titlesData: const FlTitlesData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: _spots,
                  isCurved: false,
                  color: _primary,
                  barWidth: 1.8,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: _pale.withValues(alpha: 0.25),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Botón desconectar superpuesto (esquina superior derecha)
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            onTap: _isConnecting ? null : _disconnect,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _pale,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.bluetooth_connected, size: 13, color: _primary),
                  SizedBox(width: 4),
                  Text(
                    'Desconectar',
                    style: TextStyle(
                      fontSize: 11,
                      color: _primary,
                      fontFamily: 'serif',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Drawer de alertas ─────────────────────────────────────────────
  Widget _buildAlertDrawer() {
    return Opacity(
      opacity: 0.95,
      child: SizedBox(
        width: 300,
        child: Drawer(
          backgroundColor: _white,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              const SizedBox(height: 80),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: const Text(
                  'ALERTA\nFrecuencia cardiaca elevada',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF444444),
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Activar alertas',
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 15,
                      color: Color(0xFF666666),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Switch.adaptive(
                    value: _alertsEnabled,
                    activeThumbColor: _soft,
                    activeTrackColor: _soft,
                    onChanged: (v) => setState(() => _alertsEnabled = v),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Tile de info (FC / Zona) ──────────────────────────────────────────────────
class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 60,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'serif',
              fontSize: 15,
              color: Color(0xFF555555),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'serif',
              fontSize: 15,
              color: Color(0xFF888888),
            ),
          ),
        ],
      ),
    );
  }
}
