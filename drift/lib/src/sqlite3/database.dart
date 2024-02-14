@internal
import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:sqlite3/common.dart';

import '../../backends.dart';
import 'native_functions.dart';

/// Common database implementation based on the `sqlite3` database.
///
/// Depending on the actual platform (reflected by [DB]), the database is either
/// a native database accessed through `dart:ffi` or a WASM database accessed
/// through `package:js`.
abstract class Sqlite3Delegate<DB extends CommonDatabase>
    extends DatabaseDelegate {
  DB? _database;

  /// The underlying database instance from the `sqlite3` package.
  DB get database => _database!;

  bool _hasInitializedDatabase = false;
  bool _isOpen = false;

  final void Function(DB)? _setup;

  /// Whether prepared statements should be cached.
  final bool cachePreparedStatements;

  /// Whether migrations are enabled (they are by default).
  final bool enableMigrations;

  /// Whether the [database] should be closed when [close] is called on this
  /// instance.
  ///
  /// This defaults to `true`, but can be disabled to virtually open multiple
  /// connections to the same database.
  final bool closeUnderlyingWhenClosed;

  final PreparedStatementsCache _preparedStmtsCache = PreparedStatementsCache();

  /// A delegate that will call [openDatabase] to open the database.
  Sqlite3Delegate(
    this._setup, {
    this.enableMigrations = true,
    required this.cachePreparedStatements,
  }) : closeUnderlyingWhenClosed = true;

  /// A delegate using an underlying sqlite3 database object that has already
  /// been opened.
  Sqlite3Delegate.opened(
    this._database,
    this._setup,
    this.closeUnderlyingWhenClosed, {
    this.enableMigrations = true,
    required this.cachePreparedStatements,
  }) {
    _initializeDatabase();
  }

  /// This method is overridden by the platform-specific implementation to open
  /// the right sqlite3 database instance.
  DB openDatabase();

  @override
  TransactionDelegate get transactionDelegate => const NoTransactionDelegate();

  @override
  late DbVersionDelegate versionDelegate;

  @override
  Future<bool> get isOpen => Future.value(_isOpen);

  @override
  Future<void> open(QueryExecutorUser db) async {
    if (!_hasInitializedDatabase) {
      assert(_database == null);
      _database = openDatabase();

      try {
        _initializeDatabase();
      } catch (e) {
        // If the initialization fails, we effectively don't have a usable
        // database, so reset
        _database?.dispose();
        _database = null;

        // We can call clear instead of disposeAll because disposing the
        // database will also dispose all prepared statements on it.
        _preparedStmtsCache.clear();

        rethrow;
      }
    }

    _isOpen = true;
    return Future.value();
  }

  void _initializeDatabase() {
    assert(!_hasInitializedDatabase);

    database.useNativeFunctions();
    _setup?.call(database);
    versionDelegate = enableMigrations
        ? _SqliteVersionDelegate(database)
        : const NoVersionDelegate();
    _hasInitializedDatabase = true;
  }

  @override
  @mustCallSuper
  Future<void> close() async {
    _preparedStmtsCache.disposeAll();
  }

  /// Synchronously prepares and runs [statements] collected from a batch.
  @protected
  void runBatchSync(BatchedStatements statements) {
    final prepared = <CommonPreparedStatement>[];

    try {
      for (final stmt in statements.statements) {
        prepared.add(database.prepare(stmt, checkNoTail: true));
      }

      for (final application in statements.arguments) {
        final stmt = prepared[application.statementIndex];

        stmt.execute(application.arguments);
      }
    } finally {
      for (final stmt in prepared) {
        stmt.dispose();
      }
    }
  }

  /// Synchronously prepares and runs a single [statement], replacing variables
  /// with the given [args].
  @protected
  void runWithArgsSync(String statement, List<Object?> args) {
    if (args.isEmpty) {
      database.execute(statement);
    } else {
      final (stmt, cached) = _getPreparedStatement(statement);
      try {
        stmt.execute(args);
      } finally {
        _returnStatement(stmt, cached);
      }
    }
  }

  @override
  Future<QueryResult> runSelect(String statement, List<Object?> args) async {
    final (stmt, cached) = _getPreparedStatement(statement);

    try {
      final result = stmt.select(args);
      return QueryResult.fromRows(result.toList());
    } finally {
      _returnStatement(stmt, cached);
    }
  }

  /// Returns a prepared statement for [sql] and reports whether this statement
  /// was cached.
  (CommonPreparedStatement, bool) _getPreparedStatement(String sql) {
    if (cachePreparedStatements) {
      final cachedStmt = _preparedStmtsCache.use(sql);
      if (cachedStmt != null) {
        return (cachedStmt, true);
      }

      final stmt = database.prepare(sql, checkNoTail: true);
      if (!stmt.isExplain) {
        _preparedStmtsCache.addNew(sql, stmt);
      }

      return (stmt, !stmt.isExplain);
    } else {
      final stmt = database.prepare(sql, checkNoTail: true);
      return (stmt, false);
    }
  }

  void _returnStatement(CommonPreparedStatement stmt, bool cached) {
    // When using a statement cache, prepared statements are disposed as they
    // get evicted from the cache, so we don't need to do anything.
    if (!cached) {
      stmt.dispose();
    }
  }
}

class _SqliteVersionDelegate extends DynamicVersionDelegate {
  final CommonDatabase database;

  _SqliteVersionDelegate(this.database);

  @override
  Future<int> get schemaVersion => Future.value(database.userVersion);

  @override
  Future<void> setSchemaVersion(int version) {
    database.userVersion = version;
    return Future.value();
  }
}

/// A cache of prepared statements to avoid having to parse SQL statements
/// multiple time when they're used frequently.
@internal
class PreparedStatementsCache {
  /// The default amount of prepared statements to keep cached.
  ///
  /// This value is used in tests to verify that evicted statements get disposed.
  @visibleForTesting
  static const defaultSize = 64;

  /// The maximum amount of cached statements.
  final int maxSize;

  // The linked map returns entries in the order in which they have been
  // inserted (with the first insertion being reported first).
  // So, we treat it as a LRU cache with `entries.last` being the MRU and
  // `entries.first` being the LRU element.
  final LinkedHashMap<String, CommonPreparedStatement> _cachedStatements =
      LinkedHashMap();

  /// Create a cache of prepared statements with a capacity of [maxSize].
  PreparedStatementsCache({this.maxSize = defaultSize});

  /// Attempts to look up the cached [sql] statement, if it exists.
  ///
  /// If the statement exists, it is marked as most recently used as well.
  CommonPreparedStatement? use(String sql) {
    // Remove and add the statement if it was found to move it to the end,
    // which marks it as the MRU element.
    final foundStatement = _cachedStatements.remove(sql);

    if (foundStatement != null) {
      _cachedStatements[sql] = foundStatement;
    }

    return foundStatement;
  }

  /// Caches a statement that has not been cached yet for subsequent uses.
  void addNew(String sql, CommonPreparedStatement statement) {
    assert(!_cachedStatements.containsKey(sql));

    if (_cachedStatements.length == maxSize) {
      final lru = _cachedStatements.remove(_cachedStatements.keys.first)!;
      lru.dispose();
    }

    _cachedStatements[sql] = statement;
  }

  /// Removes all cached statements.
  void disposeAll() {
    for (final statement in _cachedStatements.values) {
      statement.dispose();
    }

    _cachedStatements.clear();
  }

  /// Forgets cached statements without explicitly disposing them.
  void clear() {
    _cachedStatements.clear();
  }
}
