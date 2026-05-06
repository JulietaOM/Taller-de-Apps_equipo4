import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/services/ble_ecg_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _sampleRateHz = 250;
  static const int _visibleSeconds = 5;
  static const int _maxVisibleSamples = _sampleRateHz * _visibleSeconds;
  static const double _adcMin = 0;
  static const double _adcMax = 4095;

  late final BleEcgService _bleService;

  StreamSubscription<int>? _ecgSub;

  final List<FlSpot> _spots = [];
  int _x = 0;
  double _currentValue = 0;

  String _status = 'Desconectado';
  bool _isConnecting = false;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();

    _bleService = BleEcgService(
      deviceName: 'ECG_Device',
    );
  }

  Future<void> requestBlePermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  String _deviceName(ScanResult result) {
    final platformName = result.device.platformName;
    final advName = result.advertisementData.advName;

    if (platformName.isNotEmpty) return platformName;
    if (advName.isNotEmpty) return advName;

    return 'Dispositivo sin nombre';
  }

  bool _hasDeviceName(ScanResult result) {
    return result.device.platformName.isNotEmpty ||
        result.advertisementData.advName.isNotEmpty;
  }

  bool _isTargetDevice(ScanResult result) {
    return result.device.platformName == _bleService.deviceName ||
        result.advertisementData.advName == _bleService.deviceName;
  }

  Future<ScanResult?> _pickBleDevice() async {
    await _bleService.startDeviceScan(
      timeout: const Duration(seconds: 15),
    );

    if (!mounted) {
      await _bleService.stopDeviceScan();
      return null;
    }

    final selected = await showDialog<ScanResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dispositivos BLE'),
        content: StreamBuilder<List<ScanResult>>(
          stream: _bleService.scanResults,
          builder: (context, snapshot) {
            final results = _sortedUniqueResults(snapshot.data ?? []);

            if (results.isEmpty) {
              return const SizedBox(
                width: double.maxFinite,
                height: 140,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Escaneando dispositivos cercanos...'),
                    ],
                  ),
                ),
              );
            }

            return SizedBox(
              width: double.maxFinite,
              height: 360,
              child: ListView.separated(
                itemCount: results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final result = results[index];
                  final name = _deviceName(result);

                  return ListTile(
                    title: Text(name),
                    subtitle: Text(
                      '${result.device.remoteId} | RSSI: ${result.rssi}',
                    ),
                    onTap: () => Navigator.of(context).pop(result),
                  );
                },
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    await _bleService.stopDeviceScan();

    return selected;
  }

  List<ScanResult> _sortedUniqueResults(List<ScanResult> results) {
    final byId = <String, ScanResult>{};

    for (final result in results) {
      byId[result.device.remoteId.toString()] = result;
    }

    return byId.values.toList()
      ..sort((a, b) {
        final targetComparison =
            (_isTargetDevice(b) ? 1 : 0).compareTo(_isTargetDevice(a) ? 1 : 0);

        if (targetComparison != 0) {
          return targetComparison;
        }

        final namedComparison =
            (_hasDeviceName(b) ? 1 : 0).compareTo(_hasDeviceName(a) ? 1 : 0);

        if (namedComparison != 0) {
          return namedComparison;
        }

        return b.rssi.compareTo(a.rssi);
      });
  }

  Future<void> _connect() async {
    setState(() {
      _isConnecting = true;
      _status = 'Pidiendo permisos...';
    });

    try {
      await requestBlePermissions();

      setState(() {
        _status = 'Escaneando dispositivos BLE...';
      });

      final selected = await _pickBleDevice();

      if (selected == null) {
        setState(() {
          _status = 'No se selecciono dispositivo';
          _isConnecting = false;
        });
        return;
      }

      final selectedName = _deviceName(selected);

      setState(() {
        _status = 'Conectando a $selectedName...';
      });

      final device = await _bleService.connectToDevice(selected.device);

      await _ecgSub?.cancel();
      _ecgSub = _bleService.ecgStream.listen((sample) {
        setState(() {
          _currentValue = sample.toDouble();

          _spots.add(FlSpot(_x.toDouble(), _currentValue));
          _x++;

          if (_spots.length > _maxVisibleSamples) {
            _spots.removeAt(0);
          }
        });
      });

      setState(() {
        _status = 'Conectado a ${device.platformName}';
        _isConnected = true;
        _isConnecting = false;
      });
    } catch (e) {
      debugPrint('ERROR BLE: $e');

      setState(() {
        _status = 'Error: $e';
        _isConnected = false;
        _isConnecting = false;
      });
    }
  }

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
      debugPrint('ERROR al desconectar BLE: $e');
    } finally {
      if (!mounted) return;

      setState(() {
        _status = 'Desconectado';
        _isConnected = false;
        _isConnecting = false;
        _spots.clear();
        _x = 0;
        _currentValue = 0;
      });
    }
  }

  @override
  void dispose() {
    _ecgSub?.cancel();
    _bleService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minX = _spots.isEmpty ? 0.0 : _spots.first.x;
    final maxX = _spots.isEmpty ? _maxVisibleSamples.toDouble() : _spots.last.x;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ECG Monitor'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Estado: $_status'),
                Text('ECG: ${_currentValue.toStringAsFixed(0)}'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: (_isConnecting || _isConnected) ? null : _connect,
                  child: const Text('Conectar'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed:
                      (_isConnecting || !_isConnected) ? null : _disconnect,
                  child: const Text('Desconectar'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: LineChart(
                    LineChartData(
                      minX: minX,
                      maxX: maxX,
                      minY: _adcMin,
                      maxY: _adcMax,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: true),
                      titlesData: const FlTitlesData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _spots,
                          isCurved: false,
                          barWidth: 2,
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
