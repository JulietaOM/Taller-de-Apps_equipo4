import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleEcgService {
  BleEcgService({required this.deviceName});

  final String deviceName;

  final StreamController<int> _ecgController = StreamController<int>.broadcast();
  Stream<int> get ecgStream => _ecgController.stream;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _valueSub;

  Future<void> ensureBluetoothReady() async {
    final supported = await FlutterBluePlus.isSupported;
    if (!supported) {
      throw Exception('Este teléfono no soporta BLE.');
    }

    await FlutterBluePlus.adapterState
        .where((state) => state == BluetoothAdapterState.on)
        .first;
  }

  Future<BluetoothDevice?> scanAndConnect({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await ensureBluetoothReady();

    final completer = Completer<BluetoothDevice?>();

    debugPrint('Iniciando scan BLE...');

    await FlutterBluePlus.stopScan();

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((results) async {
      for (final result in results) {
        final advName = result.advertisementData.advName;
        final platformName = result.device.platformName;

        debugPrint(
          'Detectado: platformName=$platformName | advName=$advName | id=${result.device.remoteId}',
        );

        final matchesName =
            platformName == deviceName || advName == deviceName;

        if (matchesName) {
          debugPrint('✅ Dispositivo encontrado: $deviceName');

          await FlutterBluePlus.stopScan();
          _device = result.device;

          try {
            debugPrint('Conectando...');
            await _device!.connect(timeout: const Duration(seconds: 15));
          } catch (e) {
            debugPrint('Conexión inicial falló o ya estaba conectado: $e');
          }

          await _discoverAndSubscribe();

          if (!completer.isCompleted) {
            completer.complete(_device);
          }
          return;
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: timeout);

    Future.delayed(timeout + const Duration(seconds: 1), () {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    return completer.future;
  }

  Future<void> _discoverAndSubscribe() async {
    if (_device == null) {
      throw Exception('No hay dispositivo conectado.');
    }

    debugPrint('Descubriendo servicios...');
    final services = await _device!.discoverServices();

    for (final service in services) {
      debugPrint('Servicio: ${service.uuid}');

      for (final characteristic in service.characteristics) {
        debugPrint(
          'Característica: ${characteristic.uuid} '
          '| notify=${characteristic.properties.notify} '
          '| read=${characteristic.properties.read}',
        );

        if (characteristic.properties.notify ||
            characteristic.properties.indicate) {
          _characteristic = characteristic;

          await characteristic.setNotifyValue(true);

          debugPrint('✅ Notificaciones activadas en ${characteristic.uuid}');

          await _valueSub?.cancel();
          _valueSub = characteristic.onValueReceived.listen((value) {
            debugPrint('Bytes recibidos: $value');

            final sample = _decodeSample(value);
            _ecgController.add(sample);
          });

          return;
        }
      }
    }

    throw Exception('No se encontró ninguna característica con notify/indicate.');
  }

  int _decodeSample(List<int> value) {
    if (value.isEmpty) return 0;

    if (value.length >= 4) {
      // intenta leer int32 little-endian
      final bytes = Uint8List.fromList(value);
      return ByteData.sublistView(bytes).getInt32(0, Endian.little);
    }

    final text = utf8.decode(value, allowMalformed: true).trim();
    return int.tryParse(text) ?? 0;
  }

  Future<void> disconnect() async {
    await _valueSub?.cancel();
    await _scanSub?.cancel();

    _characteristic = null;

    if (_device != null) {
      try {
        await _device!.disconnect();
      } catch (_) {}
      _device = null;
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _ecgController.close();
  }
}