import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show LazyDatabase, QueryExecutor;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../clients/hermes/connection_manager.dart';
import '../data/database/app_database.dart';
import '../data/secure/secure_store.dart';

/// Agregador de servicios de la app: DB, gestor de conexiones y secretos.
///
/// Un único punto de cableado compartido por todas las features. Los
/// singletons son lazy (se crean al primer acceso) y el InheritedWidget
/// expone el mismo conjunto al árbol si Main lo monta sobre MaterialApp.
class AppServices {
  AppServices._();

  static AppDatabase? _db;
  static ConnectionManager? _connections;
  static SecureStore? _secrets;

  /// Instancia lazy de la base de datos drift (SQLite en disco).
  static AppDatabase get db => _db ??= AppDatabase(_openExecutor());

  /// Gestor de conexiones multi-gateway (runtimes vivos por perfil).
  static ConnectionManager get connections =>
      _connections ??= ConnectionManager();

  /// Almacén de secretos (tokens, contraseñas recordadas).
  static SecureStore get secrets => _secrets ??= SecureStore();

  /// Respaldo para pruebas y smoke tests.
  @visibleForTesting
  static void overrideForTests({
    AppDatabase? db,
    ConnectionManager? connections,
    SecureStore? secrets,
  }) {
    _db = db ?? _db;
    _connections = connections ?? _connections;
    _secrets = secrets ?? _secrets;
  }

  static QueryExecutor _openExecutor() {
    return LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      await Directory(dir.path).create(recursive: true);
      final file = File(p.join(dir.path, 'hermes_pocket.db'));
      return NativeDatabase.createInBackground(file);
    });
  }

  /// Directorio de datos de la app (para settings.json y export/import).
  static Future<Directory> supportDir() async {
    final dir = await getApplicationSupportDirectory();
    await Directory(dir.path).create(recursive: true);
    return dir;
  }

  /// Directorio de documentos visible por el usuario (export files).
  static Future<Directory> documentsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    await Directory(dir.path).create(recursive: true);
    return dir;
  }
}

/// Exposición al árbol de widgets (opcional: los singletons estáticos ya
/// cubren el caso general). Main debe montarla sobre MaterialApp para que
/// las rutas pushed también la vean.
class AppServicesScope extends StatelessWidget {
  final Widget child;

  const AppServicesScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}

/// Accesos de conveniencia al árbol. `of` se suscribe (aquí no hay cambios
/// reactivos de servicios, así que delega a peek).
AppServicesAccess of(BuildContext context, {bool listen = true}) =>
    const AppServicesAccess();

/// Contenedor de acceso: `AppServices.of(context).db`, etc.
class AppServicesAccess {
  const AppServicesAccess();

  AppDatabase get db => AppServices.db;
  ConnectionManager get connections => AppServices.connections;
  SecureStore get secrets => AppServices.secrets;
}

/// Excepción de integridad re-lanzada con mensaje legible (índice único).
AppException asAppException(Object e) => AppException(_describe(e));

class AppException implements Exception {
  final String message;
  final Object? cause;

  const AppException(this.message, {this.cause});

  @override
  String toString() => message;
}

String _describe(Object e) {
  // 2067 = SQLITE_CONSTRAINT_UNIQUE: colisión de clave/índice único.
  if (e is Exception && e.runtimeType.toString() == 'SqliteException') {
    final code = (e as dynamic).resultCode as int?;
    if (code == 2067) {
      return 'Ya existe un elemento con esa identidad';
    }
  }
  return 'Error inesperado: $e';
}

/// Utilidad de tarea con timeout corto para probes de red en UI.
Future<T> withTimeout<T>(
  Future<T> future,
  Duration duration,
  Future<T> Function() onTimeout,
) =>
    future.timeout(duration, onTimeout: onTimeout);

/// Stream vacío tipado, útil como fallback antes de inicializar.
Stream<T> emptyStream<T>() => const Stream.empty();
