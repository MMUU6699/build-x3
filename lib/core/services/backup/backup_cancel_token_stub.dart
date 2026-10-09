import 'dart:async';

final class BackupCancelledException implements Exception {
  const BackupCancelledException({this.isolateExited = true, this.isolateExit});

  final bool isolateExited;
  final Future<void>? isolateExit;

  @override
  String toString() => 'BackupCancelledException';
}

final class BackupCancelToken {
  BackupCancelToken();

  int _cellValue = 0;
  final Completer<void> _cancelled = Completer<void>();
  var _cancellable = true;
  var _disposeRequested = false;

  int get cellAddress => 0;

  bool get isCancelled => _cellValue != 0;

  bool get cancellable => _cancellable;

  bool get isCellAllocated => true;

  Future<void> get whenCancelled => _cancelled.future;

  void setCancellable(bool value) {
    _cancellable = value;
  }

  void retainWorker() {}

  void releaseWorker() {}

  void throwIfCancelled() {
    if (isCancelled) {
      throw const BackupCancelledException();
    }
  }

  void cancel() {
    if (_disposeRequested || !_cancellable) return;
    _cellValue = 1;
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }

  void dispose() {
    _disposeRequested = true;
  }
}

final class IsolateCancelFlag {
  IsolateCancelFlag.fromAddress(int address);

  IsolateCancelFlag.disabled();

  bool get isCancelled => false;

  void throwIfCancelled() {}
}
