import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleEcgService {
  BleEcgService({required this.deviceName});

  static final Guid ecgServiceUuid = Guid(
    '12345678-1234-1234-1234-123456789abc',
  );
  static final Guid ecgCharacteristicUuid = Guid(
    'abcd1234-5678-1234-5678-123456789abc',
  );

  final String deviceName;

  final StreamController<int> _ecgController = StreamController<int>.broadcast();
  Stream<int> get ecgStream => _ecgController.stream;
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _valueSub;

  Future<void> ensureBluetoothReady() async {
    final supported = await FlutterBluePlus.isSupported;
    if (!supported) {
      throw Exception('Este telefono no soporta BLE.');
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

    await _scanSub?.cancel();
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
          await FlutterBluePlus.stopScan();
          _device = result.device;

          try {
            await _device!.connect(timeout: const Duration(seconds: 15));
          } catch (e) {
            debugPrint('Conexion inicial fallo o ya estaba conectado: $e');
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

  Future<List<ScanResult>> scanForDevices({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    await ensureBluetoothReady();

    debugPrint('Iniciando scan manual BLE...');

    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();

    final devicesById = <String, ScanResult>{};

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final advName = result.advertisementData.advName;
        final platformName = result.device.platformName;

        debugPrint(
          'Detectado: platformName=$platformName | advName=$advName | id=${result.device.remoteId}',
        );

        devicesById[result.device.remoteId.toString()] = result;
      }
    });

    await FlutterBluePlus.startScan(
      timeout: timeout,
      continuousUpdates: true,
      androidScanMode: AndroidScanMode.lowLatency,
      androidUsesFineLocation: true,
    );
    await Future.delayed(timeout);
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;

    final results = devicesById.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    return results;
  }

  Future<void> startDeviceScan({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await ensureBluetoothReady();

    debugPrint('Iniciando scan BLE en vivo...');

    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;

    await FlutterBluePlus.startScan(
      timeout: timeout,
      continuousUpdates: true,
      continuousDivisor: 1,
      androidScanMode: AndroidScanMode.lowLatency,
      androidUsesFineLocation: true,
      androidCheckLocationServices: true,
    );
  }

  Future<void> stopDeviceScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
  }

  Future<BluetoothDevice> connectToDevice(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();

    _device = device;

    try {
      debugPrint('Conectando a ${device.remoteId}...');
      await _device!.connect(timeout: const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Conexion inicial fallo o ya estaba conectado: $e');
    }

    await _discoverAndSubscribe();

    return _device!;
  }

  Future<void> _discoverAndSubscribe() async {
    if (_device == null) {
      throw Exception('No hay dispositivo conectado.');
    }

    debugPrint('Descubriendo servicios...');
    final services = await _device!.discoverServices();

    for (final service in services) {
      debugPrint('Servicio: ${service.uuid}');

      if (service.uuid != ecgServiceUuid) {
        continue;
      }

      for (final characteristic in service.characteristics) {
        debugPrint(
          'Caracteristica: ${characteristic.uuid} '
          '| notify=${characteristic.properties.notify} '
          '| indicate=${characteristic.properties.indicate}',
        );

        final isEcgCharacteristic = characteristic.uuid == ecgCharacteristicUuid;
        final canNotify = characteristic.properties.notify ||
            characteristic.properties.indicate;

        if (isEcgCharacteristic && canNotify) {
          _characteristic = characteristic;

          await _valueSub?.cancel();
          _valueSub = characteristic.onValueReceived.listen((value) {
            debugPrint('Bytes recibidos: $value');

            final sample = _decodeSample(value);
            _ecgController.add(sample);
          });

          await characteristic.setNotifyValue(true);

          debugPrint('Notificaciones activadas en ${characteristic.uuid}');

          return;
        }
      }
    }

    throw Exception('No se encontro la caracteristica ECG esperada.');
  }

  int _decodeSample(List<int> value) {
    if (value.isEmpty) return 0;

    if (value.length >= 4) {
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
