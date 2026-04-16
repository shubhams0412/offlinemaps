import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:vector_tile/raw/raw_vector_tile.dart' as raw;
import 'package:vector_tile/vector_tile_value.dart';

const String _styleProfileMetadataKey = 'offlinemaps_style_profile';
const String _styleProfileRichSingleLayer = 'rich_single_layer';
const String _repairedAtMetadataKey = 'offlinemaps_android_repaired_at';

void main(List<String> args) {
  final config = _parseArgs(args);
  if (config == null) {
    _printUsage();
    exitCode = 64;
    return;
  }

  final inputFile = File(config.inputPath);
  if (!inputFile.existsSync()) {
    stderr.writeln('Input file not found: ${config.inputPath}');
    exitCode = 66;
    return;
  }

  final targetPath = config.inPlace
      ? config.inputPath
      : (config.outputPath ?? _defaultOutputPath(config.inputPath));

  if (!config.dryRun && !config.inPlace) {
    final outputFile = File(targetPath);
    outputFile.parent.createSync(recursive: true);
    inputFile.copySync(targetPath);
  }

  stdout.writeln(config.dryRun
      ? 'Inspecting ${config.inputPath} (dry run)...'
      : 'Repairing ${config.inputPath} -> $targetPath');

  final db = sqlite3.open(config.dryRun ? config.inputPath : targetPath);
  try {
    final format = _readMetadataValue(db, 'format') ?? 'unknown';
    if (format != 'pbf' && format != 'mvt') {
      stderr.writeln('This tool only supports vector MBTiles. Found format: $format');
      exitCode = 65;
      return;
    }

    final storage = _detectStorage(db);
    final tileCount = _readTileCount(db, storage);
    final totalToProcess = config.limit == null
        ? tileCount
        : (config.limit! < tileCount ? config.limit! : tileCount);
    stdout.writeln('Tiles to process: $totalToProcess');

    final selectSql = StringBuffer(storage.selectSql);
    if (config.limit != null) {
      selectSql.write(' LIMIT ${config.limit}');
    }

    final rows = db.select(selectSql.toString());
    final updateStatement = config.dryRun
        ? null
        : db.prepare(storage.updateSql);

    if (!config.dryRun) {
      db.execute('BEGIN');
    }

    var processed = 0;
    var changedTiles = 0;
    var droppedTagPairs = 0;
    var droppedInvalidValues = 0;

    for (final row in rows) {
      processed++;
      final tileData = row['tile_data'] as Uint8List;
      final result = _repairTile(tileData);

      if (result.changed) {
        changedTiles++;
      }
      droppedTagPairs += result.droppedTagPairs;
      droppedInvalidValues += result.droppedInvalidValues;

      if (!config.dryRun && result.changed) {
        updateStatement!.execute(storage.updateArgs(row, result.bytes));
      }

      if (processed % 500 == 0 || processed == totalToProcess) {
        stdout.writeln(
          'Processed $processed/$totalToProcess tiles'
          ' | changed: $changedTiles'
          ' | dropped tag pairs: $droppedTagPairs'
          ' | dropped invalid values: $droppedInvalidValues',
        );
      }
    }

    updateStatement?.dispose();

    if (!config.dryRun) {
      db.execute(
        'INSERT OR REPLACE INTO metadata(name, value) VALUES(?, ?)',
        [_styleProfileMetadataKey, _styleProfileRichSingleLayer],
      );
      db.execute(
        'INSERT OR REPLACE INTO metadata(name, value) VALUES(?, ?)',
        [_repairedAtMetadataKey, DateTime.now().toUtc().toIso8601String()],
      );
      db.execute('COMMIT');
    }

    stdout.writeln('');
    stdout.writeln('Done.');
    stdout.writeln('Changed tiles: $changedTiles');
    stdout.writeln('Dropped invalid tag pairs: $droppedTagPairs');
    stdout.writeln('Dropped invalid values: $droppedInvalidValues');
    if (!config.dryRun) {
      stdout.writeln('Updated metadata: $_styleProfileMetadataKey=$_styleProfileRichSingleLayer');
    }
  } catch (error) {
    if (!config.dryRun) {
      try {
        db.execute('ROLLBACK');
      } catch (_) {}
    }
    stderr.writeln('Repair failed: $error');
    exitCode = 1;
  } finally {
    db.dispose();
  }
}

String _defaultOutputPath(String inputPath) {
  final inputFile = File(inputPath);
  final basename = inputFile.uri.pathSegments.last;
  final outputName = basename.replaceFirst('.mbtiles', '.android-fixed.mbtiles');
  return inputFile.parent.uri.resolve(outputName).toFilePath();
}

String? _readMetadataValue(Database db, String name) {
  final rows = db.select(
    'SELECT value FROM metadata WHERE name = ? LIMIT 1',
    [name],
  );
  if (rows.isEmpty) return null;
  return rows.first['value'] as String?;
}

int _readTileCount(Database db, _TileStorage storage) {
  final rows = db.select(storage.countSql);
  return rows.first['count'] as int;
}

({Uint8List bytes, bool changed, int droppedTagPairs, int droppedInvalidValues})
    _repairTile(Uint8List tileData) {
  final isGzipped =
      tileData.length >= 2 && tileData[0] == 0x1f && tileData[1] == 0x8b;
  final decodedBytes = isGzipped
      ? Uint8List.fromList(gzip.decode(tileData))
      : tileData;

  final tile = raw.VectorTile.fromBuffer(decodedBytes);
  final repairedLayers = <raw.VectorTile_Layer>[];
  var changed = false;
  var droppedTagPairs = 0;
  var droppedInvalidValues = 0;

  for (final layer in tile.layers) {
    final repaired = _repairLayer(layer);
    repairedLayers.add(repaired.layer);
    changed = changed || repaired.changed;
    droppedTagPairs += repaired.droppedTagPairs;
    droppedInvalidValues += repaired.droppedInvalidValues;
  }

  if (!changed) {
    return (
      bytes: tileData,
      changed: false,
      droppedTagPairs: droppedTagPairs,
      droppedInvalidValues: droppedInvalidValues,
    );
  }

  final repairedTile = raw.VectorTile(layers: repairedLayers);
  final repairedBytes = Uint8List.fromList(repairedTile.writeToBuffer());
  final outputBytes = isGzipped
      ? Uint8List.fromList(gzip.encode(repairedBytes))
      : repairedBytes;

  return (
    bytes: outputBytes,
    changed: true,
    droppedTagPairs: droppedTagPairs,
    droppedInvalidValues: droppedInvalidValues,
  );
}

({raw.VectorTile_Layer layer, bool changed, int droppedTagPairs, int droppedInvalidValues})
    _repairLayer(raw.VectorTile_Layer layer) {
  final keys = <String>[];
  final keyIndexes = <String, int>{};
  final values = <raw.VectorTile_Value>[];
  final valueIndexes = <String, int>{};
  final features = <raw.VectorTile_Feature>[];

  var changed = false;
  var droppedTagPairs = 0;
  var droppedInvalidValues = 0;

  for (final feature in layer.features) {
    final repairedTags = <int>[];

    if (feature.tags.length.isOdd) {
      changed = true;
    }

    for (var i = 0; i + 1 < feature.tags.length; i += 2) {
      final keyIndex = feature.tags[i];
      final valueIndex = feature.tags[i + 1];

      if (keyIndex < 0 ||
          keyIndex >= layer.keys.length ||
          valueIndex < 0 ||
          valueIndex >= layer.values.length) {
        changed = true;
        droppedTagPairs++;
        continue;
      }

      final key = layer.keys[keyIndex];
      final rawValue = layer.values[valueIndex];

      late final VectorTileValue normalizedValue;
      try {
        normalizedValue = VectorTileValue.fromRaw(rawValue);
      } catch (_) {
        changed = true;
        droppedInvalidValues++;
        continue;
      }

      final repairedKeyIndex = keyIndexes.putIfAbsent(key, () {
        final index = keys.length;
        keys.add(key);
        return index;
      });

      final valueSignature = _valueSignature(normalizedValue);
      final repairedValueIndex = valueIndexes.putIfAbsent(valueSignature, () {
        final index = values.length;
        values.add(normalizedValue.toRaw());
        return index;
      });

      if (repairedKeyIndex != keyIndex || repairedValueIndex != valueIndex) {
        changed = true;
      }

      repairedTags
        ..add(repairedKeyIndex)
        ..add(repairedValueIndex);
    }

    if (repairedTags.length != feature.tags.length) {
      changed = true;
    }

    features.add(
      raw.VectorTile_Feature(
        id: feature.hasId() ? feature.id : null,
        tags: repairedTags,
        type: feature.type,
        geometry: feature.geometry,
      ),
    );
  }

  if (keys.length != layer.keys.length || values.length != layer.values.length) {
    changed = true;
  }

  return (
    layer: raw.VectorTile_Layer(
      name: layer.name,
      features: features,
      keys: keys,
      values: values,
      extent: layer.extent,
      version: layer.version,
    ),
    changed: changed,
    droppedTagPairs: droppedTagPairs,
    droppedInvalidValues: droppedInvalidValues,
  );
}

String _valueSignature(VectorTileValue value) {
  return '${value.type.name}:${value.value}';
}

_RepairConfig? _parseArgs(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    return null;
  }

  String? inputPath;
  String? outputPath;
  int? limit;
  var inPlace = false;
  var dryRun = false;

  for (final arg in args) {
    if (arg.startsWith('--input=')) {
      inputPath = arg.substring('--input='.length);
    } else if (arg.startsWith('--output=')) {
      outputPath = arg.substring('--output='.length);
    } else if (arg.startsWith('--limit=')) {
      limit = int.tryParse(arg.substring('--limit='.length));
      if (limit == null || limit <= 0) {
        return null;
      }
    } else if (arg == '--in-place') {
      inPlace = true;
    } else if (arg == '--dry-run') {
      dryRun = true;
    } else if (arg.trim().isNotEmpty) {
      return null;
    }
  }

  if (inputPath == null || inputPath.isEmpty) {
    return null;
  }

  if (inPlace && outputPath != null) {
    return null;
  }

  return _RepairConfig(
    inputPath: inputPath,
    outputPath: outputPath,
    limit: limit,
    inPlace: inPlace,
    dryRun: dryRun,
  );
}

void _printUsage() {
  stdout.writeln('Usage: dart run tool/repair_single_layer_mbtiles.dart --input=<path> [options]');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --output=<path>   Write repaired MBTiles to a new file.');
  stdout.writeln('  --in-place        Repair the input MBTiles file directly.');
  stdout.writeln('  --limit=<count>   Only process the first N tiles.');
  stdout.writeln('  --dry-run         Decode and validate tiles without writing changes.');
  stdout.writeln('  --help            Show this help.');
}

class _RepairConfig {
  const _RepairConfig({
    required this.inputPath,
    required this.outputPath,
    required this.limit,
    required this.inPlace,
    required this.dryRun,
  });

  final String inputPath;
  final String? outputPath;
  final int? limit;
  final bool inPlace;
  final bool dryRun;
}

class _TileStorage {
  const _TileStorage({
    required this.countSql,
    required this.selectSql,
    required this.updateSql,
    required this.updateArgs,
  });

  final String countSql;
  final String selectSql;
  final String updateSql;
  final List<Object?> Function(Row row, Uint8List repairedBytes) updateArgs;
}

_TileStorage _detectStorage(Database db) {
  final tilesObjectType = db.select(
    "SELECT type FROM sqlite_master WHERE name = 'tiles' LIMIT 1",
  );
  final hasImagesTable = db.select(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'images' LIMIT 1",
  ).isNotEmpty;
  final hasMapTable = db.select(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'map' LIMIT 1",
  ).isNotEmpty;

  if (tilesObjectType.isNotEmpty &&
      tilesObjectType.first['type'] == 'view' &&
      hasImagesTable &&
      hasMapTable) {
    return _TileStorage(
      countSql: 'SELECT COUNT(*) AS count FROM images',
      selectSql:
          'SELECT zoom_level, tile_id, tile_data FROM images ORDER BY zoom_level, tile_id',
      updateSql: 'UPDATE images SET tile_data = ? WHERE zoom_level = ? AND tile_id = ?',
      updateArgs: (row, repairedBytes) => [
        repairedBytes,
        row['zoom_level'],
        row['tile_id'],
      ],
    );
  }

  return _TileStorage(
    countSql: 'SELECT COUNT(*) AS count FROM tiles',
    selectSql:
        'SELECT zoom_level, tile_column, tile_row, tile_data FROM tiles ORDER BY zoom_level, tile_column, tile_row',
    updateSql:
        'UPDATE tiles SET tile_data = ? WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
    updateArgs: (row, repairedBytes) => [
      repairedBytes,
      row['zoom_level'],
      row['tile_column'],
      row['tile_row'],
    ],
  );
}
