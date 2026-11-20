import 'dart:async';
import '../models/records.dart';

/// Re-evaluate the last snapshot when its next active notice becomes due.
Stream<List<NotificationRecord>> watchNotificationSchedule(
  Stream<List<NotificationRecord>> source, {
  bool includeFuture = false,
  DateTime Function() now = DateTime.now,
}) {
  late final StreamController<List<NotificationRecord>> controller;
  StreamSubscription<List<NotificationRecord>>? subscription;
  Timer? timer;
  var snapshot = <NotificationRecord>[];

  void emit() {
    timer?.cancel();
    if (controller.isClosed || !controller.hasListener) return;
    final current = now();
    DateTime? next;
    final visible = <NotificationRecord>[];
    for (final notice in snapshot) {
      final due = notice.scheduledFor;
      final future = due != null && due.isAfter(current);
      if (includeFuture || (notice.active && !future)) visible.add(notice);
      if (notice.active && future && (next == null || due.isBefore(next))) {
        next = due;
      }
    }
    controller.add(visible);
    if (next != null) {
      final delay = next.difference(current);
      // Browser timers use a signed 32-bit millisecond interval.
      timer = Timer(
        delay > const Duration(days: 24) ? const Duration(days: 24) : delay,
        emit,
      );
    }
  }

  controller = StreamController<List<NotificationRecord>>(
    onListen: () {
      subscription = source.listen(
        (records) {
          snapshot = records;
          emit();
        },
        onError: controller.addError,
        onDone: () {
          timer?.cancel();
          controller.close();
        },
      );
    },
    onCancel: () async {
      timer?.cancel();
      await subscription?.cancel();
    },
  );
  return controller.stream;
}
