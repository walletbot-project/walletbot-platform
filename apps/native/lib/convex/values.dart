import 'dart:convert';
import 'dart:typed_data';

/// Convex value encoding (docs/dart-convex-client.md §A.7).
///
/// Dart → wire:
///   null / bool / String        → as-is
///   int (|v| ≤ 2^53) / double   → JSON number (Convex float64); -0.0, NaN and
///                                 ±Infinity use the `$float` envelope
///   BigInt                      → `$integer` envelope (Convex int64)
///   Uint8List                   → `$bytes` envelope
///   List / `Map<String, ...>`   → recursively, map keys sorted
///
/// Wire → Dart is the inverse; `$integer` becomes BigInt, `$bytes` becomes
/// Uint8List, `$float` becomes double.

final BigInt _i64Min = BigInt.from(-9223372036854775808);
final BigInt _i64Max = BigInt.from(9223372036854775807);
const int _maxSafeInteger = 9007199254740992; // 2^53

/// Thrown when a Dart value cannot be represented as a Convex value, or a
/// wire payload is not valid Convex JSON.
class ConvexValueException implements Exception {
  ConvexValueException(this.message);
  final String message;

  @override
  String toString() => 'ConvexValueException: $message';
}

/// Encodes a Dart value into Convex's JSON wire representation.
Object? convexToJson(Object? value) {
  if (value == null || value is bool || value is String) return value;
  if (value is BigInt) return _encodeInt64(value);
  if (value is int) {
    if (value.abs() > _maxSafeInteger) {
      throw ConvexValueException(
        'int $value exceeds float64 precision; pass a BigInt for int64 fields',
      );
    }
    return value;
  }
  if (value is double) {
    final isNegativeZero = value == 0.0 && value.isNegative;
    if (value.isFinite && !isNegativeZero) return value;
    return {r'$float': _base64Float64(value)};
  }
  if (value is Uint8List) return {r'$bytes': base64Encode(value)};
  if (value is List) return value.map(convexToJson).toList();
  if (value is Map) {
    final keys = <String>[];
    for (final key in value.keys) {
      if (key is! String) {
        throw ConvexValueException('map keys must be String, got $key');
      }
      _validateFieldName(key);
      keys.add(key);
    }
    keys.sort();
    return {for (final k in keys) k: convexToJson(value[k])};
  }
  throw ConvexValueException(
    'unsupported value of type ${value.runtimeType}: $value',
  );
}

/// Encodes a function-args map. A `null` arg value means "omit this
/// argument" (the way convex-js omits `undefined`), so optional args
/// (`v.optional`) can be left out. Nested nulls are preserved as Convex null.
Map<String, Object?> convexArgsToJson(Map<String, Object?> args) {
  final filtered = <String, Object?>{
    for (final entry in args.entries)
      if (entry.value != null) entry.key: entry.value,
  };
  return (convexToJson(filtered) as Map).cast<String, Object?>();
}

/// Decodes a JSON-decoded Convex wire value into Dart types.
Object? jsonToConvex(Object? json) {
  if (json == null || json is bool || json is num || json is String) {
    return json;
  }
  if (json is List) return json.map(jsonToConvex).toList();
  if (json is Map) {
    if (json.length == 1) {
      final key = json.keys.first;
      if (key == r'$integer') return _decodeInt64(json[key]);
      if (key == r'$bytes') return _decodeBytes(json[key]);
      if (key == r'$float') return _decodeFloat64(json[key]);
      if (key is String && key.startsWith(r'$')) {
        throw ConvexValueException('unsupported wire envelope "$key"');
      }
    }
    final out = <String, Object?>{};
    json.forEach((key, value) {
      if (key is! String) {
        throw ConvexValueException('object key is not a String: $key');
      }
      if (key.startsWith(r'$')) {
        throw ConvexValueException('unexpected \$-prefixed field "$key"');
      }
      out[key] = jsonToConvex(value);
    });
    return out;
  }
  throw ConvexValueException('cannot decode ${json.runtimeType}: $json');
}

Map<String, String> _encodeInt64(BigInt value) {
  if (value < _i64Min || value > _i64Max) {
    throw ConvexValueException('$value is out of int64 range');
  }
  final bytes = ByteData(8)..setInt64(0, value.toInt(), Endian.little);
  return {r'$integer': base64Encode(bytes.buffer.asUint8List())};
}

BigInt _decodeInt64(Object? encoded) {
  if (encoded is! String) {
    throw ConvexValueException(r'$integer payload must be a base64 string');
  }
  final bytes = base64Decode(encoded);
  if (bytes.length != 8) {
    throw ConvexValueException(
      r'$integer payload must be 8 bytes, got '
      '${bytes.length}',
    );
  }
  return BigInt.from(ByteData.sublistView(bytes).getInt64(0, Endian.little));
}

Uint8List _decodeBytes(Object? encoded) {
  if (encoded is! String) {
    throw ConvexValueException(r'$bytes payload must be a base64 string');
  }
  return base64Decode(encoded);
}

String _base64Float64(double value) {
  final bytes = ByteData(8)..setFloat64(0, value, Endian.little);
  return base64Encode(bytes.buffer.asUint8List());
}

double _decodeFloat64(Object? encoded) {
  if (encoded is! String) {
    throw ConvexValueException(r'$float payload must be a base64 string');
  }
  final bytes = base64Decode(encoded);
  if (bytes.length != 8) {
    throw ConvexValueException(
      r'$float payload must be 8 bytes, got '
      '${bytes.length}',
    );
  }
  return ByteData.sublistView(bytes).getFloat64(0, Endian.little);
}

void _validateFieldName(String key) {
  if (key.isEmpty) {
    throw ConvexValueException('object field names must be non-empty');
  }
  if (key.length > 1024) {
    throw ConvexValueException('object field name exceeds 1024 characters');
  }
  if (key.startsWith(r'$')) {
    throw ConvexValueException(r'object field names must not start with $');
  }
  for (final unit in key.codeUnits) {
    if (unit < 32 || unit > 126) {
      throw ConvexValueException(
        'object field name "$key" contains non-printable-ASCII characters',
      );
    }
  }
}
