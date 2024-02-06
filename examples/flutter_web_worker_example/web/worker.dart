// ignore: avoid_web_libraries_in_flutter
import 'dart:html';

import 'package:drift/drift.dart';
import 'package:drift/web.dart';
import 'package:drift/web/worker.dart';

void main() {
  WorkerGlobalScope.instance.importScripts('sql-wasm.js');

  driftWorkerMain(() {
    return DatabaseConnection(WebDatabase.withStorage(DriftWebStorage.indexedDb(
        'worker',
        migrateFromLocalStorage: false,
        inWebWorker: true)));
  });
}
