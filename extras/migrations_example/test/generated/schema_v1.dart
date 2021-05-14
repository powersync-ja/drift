// GENERATED CODE, DO NOT EDIT BY HAND.
//@dart=2.12
import 'package:moor/moor.dart';

class UsersData extends DataClass implements Insertable<UsersData> {
  final int id;
  UsersData({required this.id});
  factory UsersData.fromData(Map<String, dynamic> data, GeneratedDatabase db,
      {String? prefix}) {
    final effectivePrefix = prefix ?? '';
    return UsersData(
      id: const IntType()
          .mapFromDatabaseResponse(data['${effectivePrefix}id'])!,
    );
  }
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    return map;
  }

  UsersCompanion toCompanion(bool nullToAbsent) {
    return UsersCompanion(
      id: Value(id),
    );
  }

  factory UsersData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= moorRuntimeOptions.defaultSerializer;
    return UsersData(
      id: serializer.fromJson<int>(json['id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= moorRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
    };
  }

  UsersData copyWith({int? id}) => UsersData(
        id: id ?? this.id,
      );
  @override
  String toString() {
    return (StringBuffer('UsersData(')..write('id: $id')..write(')'))
        .toString();
  }

  @override
  int get hashCode => $mrjf(id.hashCode);
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is UsersData && other.id == this.id);
}

class UsersCompanion extends UpdateCompanion<UsersData> {
  final Value<int> id;
  const UsersCompanion({
    this.id = const Value.absent(),
  });
  UsersCompanion.insert({
    this.id = const Value.absent(),
  });
  static Insertable<UsersData> custom({
    Expression<int>? id,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
    });
  }

  UsersCompanion copyWith({Value<int>? id}) {
    return UsersCompanion(
      id: id ?? this.id,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsersCompanion(')..write('id: $id')..write(')'))
        .toString();
  }
}

class Users extends Table with TableInfo {
  final GeneratedDatabase _db;
  final String? _alias;
  Users(this._db, [this._alias]);
  late final GeneratedIntColumn id = _constructId();
  GeneratedIntColumn _constructId() {
    return GeneratedIntColumn('id', $tableName, false,
        hasAutoIncrement: true, declaredAsPrimaryKey: true);
  }

  @override
  List<GeneratedColumn> get $columns => [id];
  @override
  Users get asDslTable => this;
  @override
  String get $tableName => _alias ?? 'users';
  @override
  final String actualTableName = 'users';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UsersData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : null;
    return UsersData.fromData(data, _db, prefix: effectivePrefix);
  }

  @override
  Users createAlias(String alias) {
    return Users(_db, alias);
  }

  @override
  bool get dontWriteConstraints => false;
}

class DatabaseAtV1 extends GeneratedDatabase {
  DatabaseAtV1(QueryExecutor e) : super(SqlTypeSystem.defaultInstance, e);
  DatabaseAtV1.connect(DatabaseConnection c) : super.connect(c);
  late final Users users = Users(this);
  @override
  Iterable<TableInfo> get allTables => allSchemaEntities.whereType<TableInfo>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [users];
  @override
  int get schemaVersion => 1;
}
