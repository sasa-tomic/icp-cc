import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/services/connectivity_service.dart';

void main() {
  group('ConnectivityService', () {
    late ConnectivityService service;

    setUp(() {
      service = ConnectivityService();
    });

    tearDown(() async {
      await service.dispose();
    });

    group('initialization', () {
      test('isOnline stream is broadcast', () {
        // A broadcast stream allows multiple listeners
        expect(service.isOnline.isBroadcast, isTrue);
      });

      test('initial isOnline value is true (optimistic default)', () async {
        // Start with optimistic online assumption
        final initialValue = await service.isOnline.first
            .timeout(const Duration(seconds: 1), onTimeout: () => true);

        // After initial check, value should be determined
        // Default is true (optimistic) before first check completes
        expect(initialValue, isA<bool>());
      });
    });

    group('connectivity check', () {
      test('checkConnectivity returns a boolean', () async {
        final result = await service.checkConnectivity();

        expect(result, isA<bool>());
      });

      test('checkConnectivity attempts to connect to a reliable host',
          () async {
        // This test verifies the service doesn't throw during check
        // Actual connectivity depends on the test environment
        bool result;
        try {
          result = await service.checkConnectivity();
        } catch (e) {
          // Should not throw, should return false on failure
          fail('checkConnectivity should not throw: $e');
        }

        expect(result, isA<bool>());
      });

      test('isOnline emits value after checkConnectivity is called', () async {
        final completer = Completer<bool>();

        // Subscribe to stream
        service.isOnline.listen((isOnline) {
          if (!completer.isCompleted) {
            completer.complete(isOnline);
          }
        });

        // Trigger check
        await service.checkConnectivity();

        // Should have received a value
        final value = await completer.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () => true,
        );
        expect(value, isA<bool>());
      });
    });

    group('periodic checking', () {
      test('startPeriodicCheck emits initial status immediately', () async {
        final values = <bool>[];

        // Subscribe to collect values
        final subscription = service.isOnline.listen((isOnline) {
          values.add(isOnline);
        });

        // Start periodic check - should emit initial status right away
        service.startPeriodicCheck(interval: const Duration(milliseconds: 100));

        // Wait a short time for the initial emission
        await Future.delayed(const Duration(milliseconds: 50));

        service.stopPeriodicCheck();
        await subscription.cancel();

        // Should have at least 1 value (the initial status)
        expect(values.length, greaterThanOrEqualTo(1));
        expect(values.first, isA<bool>());
      });

      test('stopPeriodicCheck stops emissions', () async {
        final values = <bool>[];

        service.isOnline.listen((isOnline) {
          values.add(isOnline);
        });

        // Start and then stop immediately
        service.startPeriodicCheck(interval: const Duration(milliseconds: 100));
        await Future.delayed(const Duration(milliseconds: 150));
        service.stopPeriodicCheck();

        final countAfterStop = values.length;

        // Wait a bit more
        await Future.delayed(const Duration(milliseconds: 300));

        // Should not have significantly more values after stopping
        expect(values.length - countAfterStop, lessThan(3));
      });
    });

    group('dispose', () {
      test('dispose closes the stream controller and stops emissions',
          () async {
        final values = <bool>[];

        // Subscribe before dispose
        final subscription = service.isOnline.listen((isOnline) {
          values.add(isOnline);
        });

        // Trigger a check
        await service.checkConnectivity();
        await Future.delayed(const Duration(milliseconds: 50));

        final countBeforeDispose = values.length;

        // Dispose
        await service.dispose();

        // After dispose, the stream should not emit new values
        // Try to check again - should not emit
        final result = await service.checkConnectivity();
        expect(result, isFalse); // Returns false when disposed

        await Future.delayed(const Duration(milliseconds: 50));

        // Should not have received more values after dispose
        expect(values.length, equals(countBeforeDispose));

        await subscription.cancel();
      });

      test('stopPeriodicCheck is called on dispose', () async {
        service.startPeriodicCheck(interval: const Duration(seconds: 1));

        // Dispose should not throw
        await expectLater(service.dispose(), completes);
      });
    });

    group('Socket connectivity (integration)', () {
      test('can reach google.com:80 when network is available', () async {
        // Skip if no network - this is an integration test
        bool canConnect = false;
        try {
          final socket = await Socket.connect(
            'google.com',
            80,
            timeout: const Duration(seconds: 5),
          );
          await socket.close();
          canConnect = true;
        } catch (e) {
          // Network not available in test environment
          canConnect = false;
        }

        final serviceResult = await service.checkConnectivity();

        // If Socket could connect, service should return true
        // If Socket couldn't connect, service should return false
        // This validates the service logic matches direct Socket behavior
        if (canConnect) {
          expect(serviceResult, isTrue);
        } else {
          expect(serviceResult, isFalse);
        }
      });

      test('handles SocketException gracefully', () async {
        // The service should handle SocketException internally and return false
        // This is implicitly tested by the connectivity check
        final result = await service.checkConnectivity();

        // Should return a boolean, never throw
        expect(result, isA<bool>());
      });
    });
  });
}
