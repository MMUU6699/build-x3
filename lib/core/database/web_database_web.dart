import 'package:drift/drift.dart';
import 'package:drift/web.dart';

QueryExecutor createWebDatabase() {
  return WebDatabase('buildx_db');
}
