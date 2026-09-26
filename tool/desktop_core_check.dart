// Smoke del core compartido en desktop (Linux = misma vía FFI que Windows):
// 1) sqlite3 FFI  2) drift AppDatabase real (migraciones + consultas)
import 'package:drift/native.dart';
import 'package:hermes_pocket/data/database/app_database.dart';

void main() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.customSelect('SELECT 1 AS one').getSingle();
  print('drift AppDatabase OK en desktop: ${db.allTables.length} tablas');
  await db.close();
}
