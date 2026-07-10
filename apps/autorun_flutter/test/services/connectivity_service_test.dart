import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/services/connectivity_service.dart';

/// Deterministic unit tests for [ConnectivityService].
///
/// These replace the old tautological suite (TQ-4): no `isA<bool>()`
/// placeholders, no `onTimeout: () => true` escape hatches, no dependence on the
/// host network. The reachability probe is injected via the constructor seam
/// (`ConnectivityProbe`), so every outcome is asserted exactly. Periodic
/// behaviour is driven by `package:fake_async` instead of real wall-clock waits.
void main() {
  group('ConnectivityService', () {
    late ConnectivityService service;

    tearDown(() async => service.dispose());

    group('isOnline stream', () {
      test('is a broadcast stream allowing multiple listeners', () {
        service = ConnectivityService(probe: () async => true);
        expect(service.isOnline.isBroadcast, isTrue);
      });
    });

    group('checkConnectivity (probe seam)', () {
      test('probe reports online → isOnline true, no offline transition', () async {
        service = ConnectivityService(probe: () async => true);

        final events = <bool>[];
        final sub = service.isOnline.listen(events.add);

        final result = await service.checkConnectivity();

        expect(result, isTrue);
        expect(service.currentStatus, isTrue);

        // Optimistic default is already true; a true probe means no transition.
        await _pump();
        expect(events, isEmpty);
        await sub.cancel();
      });

      test('probe reports refused/offline → isOnline false + one transition',
          () async {
        service = ConnectivityService(probe: () async => false);

        final events = <bool>[];
        final sub = service.isOnline.listen(events.add);

        final result = await service.checkConnectivity();

        expect(result, isFalse);
        expect(service.currentStatus, isFalse);

        await _pump();
        // The optimistic-true → false transition must be emitted exactly once.
        expect(events, [false]);
        await sub.cancel();
      });

      test('transition emitted only on status change, not on every probe',
          () async {
        var online = false;
        service = ConnectivityService(probe: () async => online);

        final events = <bool>[];
        final sub = service.isOnline.listen(events.add);

        await service.checkConnectivity(); // true → false
        await service.checkConnectivity(); // still false: no event
        online = true;
        await service.checkConnectivity(); // false → true
        await service.checkConnectivity(); // still true: no event

        await _pump();
        expect(events, [false, true]);
        await sub.cancel();
      });
    });

    group('dispose', () {
      test('after dispose, checkConnectivity reports false and emits nothing',
          () async {
        service = ConnectivityService(probe: () async => true);

        final events = <bool>[];
        final sub = service.isOnline.listen(events.add);
        await service.checkConnectivity();
        await _pump();
        events.clear();

        await service.dispose();

        expect(await service.checkConnectivity(), isFalse);

        await _pump();
        expect(events, isEmpty);
        await sub.cancel();
      });
    });

    group('periodic checking (fake_async)', () {
      test('periodic timer re-probes and emits transitions without real I/O', () {
        FakeAsync().run((fake) {
          var online = true;
          final svc = ConnectivityService(probe: () async => online);
          final events = <bool>[];
          final sub = svc.isOnline.listen(events.add);

          svc.startPeriodicCheck(interval: const Duration(seconds: 30));

          // startPeriodicCheck emits the optimistic current status (true) then
          // kicks the immediate probe (still true) → no transition.
          fake.flushMicrotasks();
          expect(events, [true]);

          // Go offline; advance one interval → periodic probe → transition.
          online = false;
          fake.elapse(const Duration(seconds: 30));
          fake.flushMicrotasks();
          expect(events, [true, false]);

          // Another interval, still offline → no new event.
          fake.elapse(const Duration(seconds: 30));
          fake.flushMicrotasks();
          expect(events, [true, false]);

          // Back online → transition.
          online = true;
          fake.elapse(const Duration(seconds: 30));
          fake.flushMicrotasks();
          expect(events, [true, false, true]);

          svc.stopPeriodicCheck();
          sub.cancel();
          svc.dispose();
          fake.flushMicrotasks();
        });
      });

      test('stopPeriodicCheck cancels the periodic timer', () {
        FakeAsync().run((fake) {
          var online = true;
          final svc = ConnectivityService(probe: () async => online);
          final events = <bool>[];
          final sub = svc.isOnline.listen(events.add);

          svc.startPeriodicCheck(interval: const Duration(seconds: 30));
          fake.flushMicrotasks();
          expect(events, [true]);

          svc.stopPeriodicCheck();

          // Flip + advance well past the interval: with the timer cancelled,
          // no probe runs and no event is emitted.
          online = false;
          fake.elapse(const Duration(seconds: 90));
          fake.flushMicrotasks();
          expect(events, [true]);

          sub.cancel();
          svc.dispose();
          fake.flushMicrotasks();
        });
      });

      test('onChange signal triggers an immediate re-probe ahead of the timer',
          () {
        FakeAsync().run((fake) {
          var online = true;
          final changeController = StreamController<void>.broadcast();
          final svc = ConnectivityService(
            probe: () async => online,
            onChange: changeController.stream,
          );
          final events = <bool>[];
          final sub = svc.isOnline.listen(events.add);

          svc.startPeriodicCheck(interval: const Duration(seconds: 30));
          fake.flushMicrotasks();
          expect(events, [true]);

          // A browser online/offline event fires well before the 30s interval.
          online = false;
          changeController.add(null);
          fake.flushMicrotasks();
          expect(events, [true, false]);

          // Still no interval elapsed, but another event arrives:
          online = true;
          changeController.add(null);
          fake.flushMicrotasks();
          expect(events, [true, false, true]);

          svc.stopPeriodicCheck();
          changeController.close();
          sub.cancel();
          svc.dispose();
          fake.flushMicrotasks();
        });
      });
    });
  });
}

/// Flushes any pending microtasks so stream emissions become observable.
Future<void> _pump() => Future<void>.delayed(Duration.zero);
