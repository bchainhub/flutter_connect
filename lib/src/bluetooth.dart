import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'handoff.dart';
import 'protocol.dart';

/// Native wallet peripheral. The portal is the Web Bluetooth central.
/// Call start only after displaying/confirming the scanned request's origin.
class ConnectBluetoothPeripheral {
  final ConnectHandoff handoff;
  final PeripheralManager _manager;
  final void Function(Object) onError;
  final ConnectBleResponseBuffer _buffer = ConnectBleResponseBuffer();
  final Map<UUID, int> _offsets = {};
  final List<StreamSubscription<Object?>> _subscriptions = [];
  GATTService? _service;
  Timer? _timer;
  bool _active = false;
  bool _starting = false;
  ConnectBluetoothPeripheral({
    required this.handoff,
    required this.onError,
    PeripheralManager? manager,
  }) : _manager = manager ?? PeripheralManager();
  static bool get isSupportedPlatform =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ].contains(defaultTargetPlatform);
  Future<void> start() async {
    if (_active || _starting) fail('invalidState');
    if (!isSupportedPlatform) fail('bluetoothUnavailable');
    handoff.challenge.validateTime(DateTime.now());
    _active = true;
    _starting = true;
    try {
      if (defaultTargetPlatform == TargetPlatform.android &&
          !await _manager.authorize()) {
        fail('bluetoothPermissionDenied');
      }
      if (_manager.state == BluetoothLowEnergyState.unknown) {
        await _manager.stateChanged
            .firstWhere(
              (event) => event.state != BluetoothLowEnergyState.unknown,
            )
            .timeout(const Duration(seconds: 15));
      }
      if (_manager.state != BluetoothLowEnergyState.poweredOn) {
        fail('bluetoothUnavailable');
      }
      if (!_active) fail('cancelled');
      final control = GATTCharacteristic.mutable(
        uuid: UUID.fromString(connectBleControlUuid),
        properties: [GATTCharacteristicProperty.write],
        permissions: [GATTCharacteristicPermission.write],
        descriptors: [],
      );
      final response = GATTCharacteristic.mutable(
        uuid: UUID.fromString(connectBleResponseUuid),
        properties: [GATTCharacteristicProperty.read],
        permissions: [GATTCharacteristicPermission.read],
        descriptors: [],
      );
      final service = GATTService(
        uuid: UUID.fromString(handoff.serviceUuid),
        isPrimary: true,
        includedServices: [],
        characteristics: [control, response],
      );
      _subscriptions.add(
        _manager.characteristicWriteRequested.listen((event) {
          if (event.characteristic.uuid != control.uuid) return;
          unawaited(_write(event).catchError(onError));
        }, onError: onError),
      );
      _subscriptions.add(
        _manager.characteristicReadRequested.listen((event) {
          if (event.characteristic.uuid != response.uuid) return;
          unawaited(_read(event).catchError(onError));
        }, onError: onError),
      );
      await _manager.addService(service);
      _service = service;
      if (!_active) {
        fail('cancelled');
      }
      handoff.challenge.validateTime(DateTime.now());
      await _manager.startAdvertising(
        Advertisement(serviceUUIDs: [service.uuid]),
      );
      if (!_active) {
        await _manager.stopAdvertising();
        fail('cancelled');
      }
      _timer = Timer(
        DateTime.parse(handoff.challenge.expiresAt).difference(DateTime.now()),
        () => unawaited(stop().catchError(onError)),
      );
    } catch (_) {
      await stop();
      rethrow;
    } finally {
      _starting = false;
    }
  }

  /// Publish only the encrypted response returned by ConnectRequest.response.
  void publish(String response) {
    if (!_active) fail('invalidState');
    handoff.challenge.validateTime(DateTime.now());
    final data = object(jsonDecode(response), [
      'type',
      'requestId',
      'iv',
      'ciphertext',
    ]);
    if (data['type'] != 'connect:response:1' ||
        data['requestId'] != handoff.challenge.requestId) {
      fail('invalidHandoff');
    }
    _buffer.publish(response);
  }

  Future<void> _write(GATTCharacteristicWriteRequestedEventArgs event) async {
    try {
      handoff.challenge.validateTime(DateTime.now());
      final bytes = event.request.value;
      if (!_active ||
          event.request.offset != 0 ||
          bytes.length != 4 ||
          (!_offsets.containsKey(event.central.uuid) &&
              _offsets.length >= 16)) {
        fail('invalidBluetoothFrame');
      }
      final offset = ByteData.sublistView(bytes).getUint32(0, Endian.little);
      if (offset > 32768) fail('invalidBluetoothFrame');
      _offsets[event.central.uuid] = offset;
    } catch (_) {
      await _manager.respondWriteRequestWithError(
        event.request,
        error: GATTError.invalidPDU,
      );
      return;
    }
    await _manager.respondWriteRequest(event.request);
  }

  Future<void> _read(GATTCharacteristicReadRequestedEventArgs event) async {
    Uint8List value;
    try {
      handoff.challenge.validateTime(DateTime.now());
      if (!_active || event.request.offset != 0) fail('invalidBluetoothFrame');
      value = _buffer.frame(_offsets[event.central.uuid] ?? 0);
    } catch (_) {
      await _manager.respondReadRequestWithError(
        event.request,
        error: GATTError.invalidOffset,
      );
      return;
    }
    await _manager.respondReadRequestWithValue(event.request, value: value);
  }

  Future<void> stop() async {
    if (!_active && _service == null) return;
    _active = false;
    _timer?.cancel();
    _timer = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _offsets.clear();
    _buffer.clear();
    final service = _service;
    _service = null;
    if (service != null) {
      try {
        await _manager.stopAdvertising();
      } finally {
        await _manager.removeService(service);
      }
    }
  }
}
