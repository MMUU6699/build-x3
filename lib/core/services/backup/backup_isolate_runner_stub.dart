import 'dart:async';
import 'package:flutter/foundation.dart';

import 'backup_cancel_token.dart';
import 'backup_task_progress.dart';

export '../../database/sqlite_interrupt.dart'
    show debugOnInterruptSqliteHandle, interruptSqliteHandle;

@visibleForTesting
bool debugSkipBackupIsolateKill = false;

void debugNativeSleepIgnoringKill(int seconds) {}

final class BackupIsolateTimeoutException extends TimeoutException {
  BackupIsolateTimeoutException({
    required this.isolateExited,
    this.isolateExit,
    Duration? duration,
  }) : super('backup_isolate_timeout', duration);

  final bool isolateExited;
  final Future<void>? isolateExit;
}

bool backupIsolateStillAlive(Object error) => false;

Future<void>? backupIsolateExitFuture(Object error) => null;

final class BackupIsolateContext {
  BackupIsolateContext({
    required this.cancelFlag,
    required this._reportProgress,
    this._registerSqliteInterruptHandle,
    this._waitForSqliteCloseAck,
  });

  final IsolateCancelFlag cancelFlag;
  final void Function(BackupProgress progress) _reportProgress;
  final void Function(int handleAddress)? _registerSqliteInterruptHandle;
  final Future<void> Function()? _waitForSqliteCloseAck;

  void throwIfCancelled() => cancelFlag.throwIfCancelled();

  void reportProgress(BackupProgress progress) => _reportProgress(progress);

  void registerSqliteInterruptHandle(int address) {
    _registerSqliteInterruptHandle?.call(address);
  }

  Future<void> waitForSqliteCloseAck() async {
    await _waitForSqliteCloseAck?.call();
  }
}

Future<R> runBackupIsolate<R, P>({
  required FutureOr<R> Function(BackupIsolateContext context, P payload) body,
  required P payload,
  BackupCancelToken? cancelToken,
  BackupProgressSink? onProgress,
  Duration killGrace = const Duration(seconds: 3),
  Duration isolateExitDeadline = const Duration(seconds: 2),
  Duration? timeout,
}) async {
  final context = BackupIsolateContext(
    cancelFlag: IsolateCancelFlag.disabled(),
    reportProgress: (progress) => onProgress?.call(progress),
  );
  return await body(context, payload);
}
