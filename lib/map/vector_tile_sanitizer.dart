import 'dart:io';
import 'dart:typed_data';

import 'package:vector_tile/raw/raw_vector_tile.dart' as raw;
import 'package:vector_tile/vector_tile_value.dart';

typedef SanitizedVectorTileResult =
    ({Uint8List bytes, bool changed, int droppedTagPairs, int droppedInvalidValues});

class VectorTileSanitizer {
  static SanitizedVectorTileResult sanitize(Uint8List tileData) {
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

  static ({raw.VectorTile_Layer layer, bool changed, int droppedTagPairs, int droppedInvalidValues})
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

        final valueSignature = '${normalizedValue.type.name}:${normalizedValue.value}';
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
}
