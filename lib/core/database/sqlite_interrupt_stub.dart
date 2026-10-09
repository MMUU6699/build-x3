import 'package:flutter/foundation.dart';

@visibleForTesting
void Function(int handleAddress)? debugOnInterruptSqliteHandle;

void interruptSqliteHandle(int address) {
  final debugHook = debugOnInterruptSqliteHandle;
  if (debugHook != null) {
    debugHook(address);
    return;
  }
}
