import 'dart:ffi';

import 'package:flutter/foundation.dart';

@Native<Void Function(Pointer<Void>)>(
  assetId: 'package:sqlite3/src/ffi/libsqlite3.g.dart',
  symbol: 'sqlite3_interrupt',
)
external void _sqlite3Interrupt(Pointer<Void> db);

@visibleForTesting
void Function(int handleAddress)? debugOnInterruptSqliteHandle;

void interruptSqliteHandle(int address) {
  final debugHook = debugOnInterruptSqliteHandle;
  if (debugHook != null) {
    debugHook(address);
    return;
  }
  if (address == 0) return;
  try {
    _sqlite3Interrupt(Pointer<Void>.fromAddress(address));
  } catch (_) {
    // Native asset may have stripped sqlite3_interrupt. Kill still follows.
  }
}
