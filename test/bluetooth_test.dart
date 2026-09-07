import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter_connect/flutter_connect.dart';
import 'connect_test.dart' show vectors;

class FakePeripheral implements PeripheralManager {
  int added = 0, removed = 0, advertised = 0, stopped = 0;
  @override
  BluetoothLowEnergyState get state => BluetoothLowEnergyState.poweredOn;
  @override
  Stream<GATTCharacteristicWriteRequestedEventArgs>
  get characteristicWriteRequested => const Stream.empty();
  @override
  Stream<GATTCharacteristicReadRequestedEventArgs>
  get characteristicReadRequested => const Stream.empty();
  @override
  Future<void> addService(GATTService service) async {
    added++;
    expect(service.characteristics.length, 2);
  }

  @override
  Future<void> removeService(GATTService service) async {
    removed++;
  }

  @override
  Future<void> startAdvertising(Advertisement advertisement) async {
    advertised++;
  }

  @override
  Future<void> stopAdvertising() async {
    stopped++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native peripheral owns and cleans up its service', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final challenge = Map<String, dynamic>.from(
      vectors().first['challenge'] as Map,
    );
    challenge['issuedAt'] = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceFirst(RegExp(r'\d{6}Z$'), '000Z');
    challenge['expiresAt'] = DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 2))
        .toIso8601String()
        .replaceFirst(RegExp(r'\d{6}Z$'), '000Z');
    final payload = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'type': 'connect:handoff:1',
              'challenge': challenge,
              'key': '01' * 32,
            }),
          ),
        )
        .replaceAll('=', '');
    final handoff = ConnectHandoff.parse(
      'connect://example.com/connect/v1/${challenge['requestId']}#$payload',
    );
    final manager = FakePeripheral();
    final errors = <Object>[];
    final peripheral = ConnectBluetoothPeripheral(
      handoff: handoff,
      manager: manager,
      onError: errors.add,
    );
    await peripheral.start();
    expect(manager.added, 1);
    expect(manager.advertised, 1);
    await expectLater(peripheral.start(), throwsA(isA<ConnectException>()));
    expect(() => peripheral.publish('{}'), throwsA(isA<ConnectException>()));
    await peripheral.stop();
    await peripheral.stop();
    expect(manager.removed, 1);
    expect(manager.stopped, 1);
    expect(errors, isEmpty);
  });
}
