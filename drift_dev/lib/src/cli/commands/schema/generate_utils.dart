import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as p;

import '../../../analysis/results/file_results.dart';
import '../../../analysis/results/results.dart';
import '../../../analysis/options.dart';
import '../../../services/schema/schema_files.dart';
import '../../../writer/database_writer.dart';
import '../../../writer/import_manager.dart';
import '../../../writer/writer.dart';
import '../../cli.dart';
import '../schema.dart';

class GenerateUtilsCommand extends Command {
  final DriftDevCli cli;

  GenerateUtilsCommand(this.cli) {
    argParser.addFlag(
      'data-classes',
      defaultsTo: false,
      help: 'Whether to generate data classes for each schema version.',
    );
    argParser.addFlag(
      'companions',
      defaultsTo: false,
      help: 'Whether to generate companions for each schema version.',
    );
  }

  @override
  String get description {
    return 'Generate Dart code to help verify schema migrations.';
  }

  @override
  String get name => 'generate';

  @override
  String get invocation {
    return '${runner!.executableName} schema generate <input> <output>';
  }

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length != 2) {
      usageException('Expected input and output directories');
    }

    final inputDir = Directory(rest[0]);
    final outputDir = Directory(rest[1]);

    if (!await inputDir.exists()) {
      cli.exit('The provided input directory does not exist.');
    }

    if (!await outputDir.exists()) {
      await outputDir.create();
    }

    final schema = await parseSchema(inputDir);
    for (final versionAndEntities in schema.entries) {
      final version = versionAndEntities.key;
      final entities = versionAndEntities.value;

      await _writeSchemaFile(
        outputDir,
        version,
        entities,
        argResults?['data-classes'] as bool,
        argResults?['companions'] as bool,
      );
    }

    final versions = schema.keys.toList()..sort();
    await _writeLibraryFile(outputDir, versions);
    print(
        'Wrote ${schema.length + 1} files into ${p.relative(outputDir.path)}');
  }

  Future<void> _writeSchemaFile(
    Directory output,
    int version,
    ExportedSchema schema,
    bool dataClasses,
    bool companions,
  ) {
    // let serialized options take precedence, otherwise use current options
    // from project.
    final options = DriftOptions.fromJson({
      ...cli.project.moorOptions.toJson(),
      ...schema.options,
    });

    final writer = Writer(
      options,
      generationOptions: GenerationOptions(
        forSchema: version,
        writeCompanions: companions,
        writeDataClasses: dataClasses,
        imports: NullImportManager(),
      ),
    );
    final file = File(p.join(output.path, _filenameForVersion(version)));

    writer.leaf()
      ..writeln(_prefix)
      ..writeln('//@dart=2.12')
      ..writeln("import 'package:drift/drift.dart';");

    final database = DriftDatabase(
      id: DriftElementId(SchemaReader.elementUri, 'database'),
      declaration: DriftDeclaration(SchemaReader.elementUri, 0, 'database'),
      declaredIncludes: const [],
      declaredQueries: const [],
      declaredTables: const [],
      declaredViews: const [],
    );
    final resolved =
        ResolvedDatabaseAccessor(const {}, const [], schema.schema);
    final input = DatabaseGenerationInput(database, resolved, const {}, null);

    DatabaseWriter(input, writer.child()).write();

    return file.writeAsString(_dartfmt.format(writer.writeGenerated()));
  }

  Future<void> _writeLibraryFile(Directory output, Iterable<int> versions) {
    final buffer = StringBuffer()
      ..writeln(_prefix)
      ..writeln('//@dart=2.12')
      ..writeln("import 'package:drift/drift.dart';")
      ..writeln("import 'package:drift/internal/migrations.dart';");

    for (final version in versions) {
      buffer.writeln("import '${_filenameForVersion(version)}' as v$version;");
    }

    buffer
      ..writeln('class GeneratedHelper implements SchemaInstantiationHelper {')
      ..writeln('@override')
      ..writeln('GeneratedDatabase databaseForVersion(QueryExecutor db, '
          'int version) {')
      ..writeln('switch (version) {');

    for (final version in versions) {
      buffer
        ..writeln('case $version:')
        ..writeln('return v$version.DatabaseAtV$version(db);');
    }

    final missingAsSet = '{${versions.join(', ')}}';
    buffer
      ..writeln('default:')
      ..writeln('throw MissingSchemaException(version, const $missingAsSet);')
      ..writeln('}}}');

    final file = File(p.join(output.path, 'schema.dart'));
    return file.writeAsString(_dartfmt.format(buffer.toString()));
  }

  String _filenameForVersion(int version) => 'schema_v$version.dart';

  static final _dartfmt = DartFormatter();
  static const _prefix = '// GENERATED CODE, DO NOT EDIT BY HAND.\n'
      '// ignore_for_file: type=lint';
}
