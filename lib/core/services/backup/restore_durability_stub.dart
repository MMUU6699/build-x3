import 'dart:io';

abstract interface class RestoreDurability {
  Future<void> restrictFile(File file);
  Future<void> restrictDirectory(Directory directory);
  Future<void> syncFile(File file, {bool fullBarrier = false});
  Future<void> syncDirectory(Directory directory, {bool fullBarrier = false});
  Future<void> renameAndSync({
    required FileSystemEntity source,
    required String targetPath,
  });
}

final class RestorePlatformDurability implements RestoreDurability {
  RestorePlatformDurability();

  @override
  Future<void> restrictFile(File file) async {}

  @override
  Future<void> restrictDirectory(Directory directory) async {}

  @override
  Future<void> syncFile(File file, {bool fullBarrier = false}) async {}

  @override
  Future<void> syncDirectory(Directory directory, {bool fullBarrier = false}) async {}

  @override
  Future<void> renameAndSync({
    required FileSystemEntity source,
    required String targetPath,
  }) async {
    await source.rename(targetPath);
  }
}
