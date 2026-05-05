import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/services/ble_ecg_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final BleEcgService _bleService;

  StreamSubscription<int>? _ecgSub;

  final List<FlSpot> _spots = [];
  int _x = 0;
  double _currentValue = 0;

  String _status = 'Desconectado';
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();

    _bleService = BleEcgService(
      deviceName: 'ECG_Device', // 👈 debe coincidir con ESP32
    );
  }

  // 🔐 Permisos BLE
  Future<void> requestBlePermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  // 🔌 Conectar al ESP32
  Future<void> _connect() async {
    debugPrint("Botón conectar presionado");

    setState(() {
      _isConnecting = true;
      _status = 'Pidiendo permisos...';
    });

    try {
      await requestBlePermissions();

      setState(() {
        _status = 'Buscando dispositivo...';
      });

      final device = await _bleService.scanAndConnect(
        timeout: const Duration(seconds: 10),
      );

      if (device == null) {
        setState(() {
          _status = 'No se encontró ECG_Device';
          _isConnecting = false;
        });
        return;
      }

      await _ecgSub?.cancel();
      _ecgSub = _bleService.ecgStream.listen((sample) {
        setState(() {
          _currentValue = sample.toDouble();

          _spots.add(FlSpot(_x.toDouble(), _currentValue));
          _x++;

          // mantener buffer de ~250 muestras
          if (_spots.length > 250) {
            _spots.removeAt(0);
          }
        });
      });

      setState(() {
        _status = 'Conectado a ${device.platformName}';
        _isConnecting = false;
      });
    } catch (e) {
      debugPrint('ERROR BLE: $e');

      setState(() {
        _status = 'Error: $e';
        _isConnecting = false;
      });
    }
  }

  // 🔌 Desconectar
  Future<void> _disconnect() async {
    await _ecgSub?.cancel();
    await _bleService.disconnect();

    setState(() {
      _status = 'Desconectado';
      _spots.clear();
      _x = 0;
      _currentValue = 0;
    });
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
    final maxX = _spots.isEmpty ? 100.0 : _spots.last.x;

    final minY = _spots.isEmpty
        ? 0.0
        : _spots.map((e) => e.y).reduce((a, b) => a < b ? a : b) - 50;

    final maxY = _spots.isEmpty
        ? 4095.0
        : _spots.map((e) => e.y).reduce((a, b) => a > b ? a : b) + 50;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ECG Monitor'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 🔹 Estado y valor actual
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Estado: $_status'),
                Text('ECG: ${_currentValue.toStringAsFixed(0)}'),
              ],
            ),

            const SizedBox(height: 12),

            // 🔹 Botones
            Row(
              children: [
                ElevatedButton(
                  onPressed: _isConnecting ? null : _connect,
                  child: const Text('Conectar'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _disconnect,
                  child: const Text('Desconectar'),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 🔹 Gráfica ECG
            Expanded(
              child: Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: LineChart(
                    LineChartData(
                      minX: minX,
                      maxX: maxX,
                      minY: minY,
                      maxY: maxY,
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