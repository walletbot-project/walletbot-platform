import 'dart:convert';
import 'dart:typed_data';

/// Convex wire format helpers.
///
/// The convex_flutter package serializes mutation/query args by running
/// `jsonEncode` on each argument value. Dart's default `jsonEncode` does not
/// support `BigInt`, and Convex's `v.int64()` validator expects an envelope
/// of the shape `{"$integer": "<base64 of 8 little-endian bytes>"}`.
///
/// These helpers convert between Dart `BigInt`s and the wire envelope.

const _intKey = r'$integer';

/// Encodes a `BigInt` as Convex's int64 envelope.
Map<String, String> int64Wire(BigInt value) {
  final bytes = ByteData(8)..setInt64(0, value.toInt(), Endian.little);
  // BigInt.toInt() truncates to a Dart int (64-bit on native). We only
  // store epoch-ms timestamps and cents — well within int64 range.
  return {_intKey: base64Encode(bytes.buffer.asUint8List())};
}

/// Decodes a Convex int64 envelope back to a `BigInt`.
BigInt parseInt64Wire(Object value) {
  if (value is Map && value[_intKey] is String) {
    final bytes = base64Decode(value[_intKey] as String);
    if (bytes.length != 8) {
      throw FormatException('expected 8 bytes for int64, got ${bytes.length}');
    }
    final view = ByteData.sublistView(bytes);
    return BigInt.from(view.getInt64(0, Endian.little));
  }
  if (value is num) return BigInt.from(value.toInt());
  if (value is String) return BigInt.parse(value);
  if (value is BigInt) return value;
  throw FormatException('cannot decode int64 from: $value');
}

/// Walks an arbitrary JSON-decoded structure replacing `BigInt` instances
/// with their int64 wire envelope, so the result is safe to pass into
/// `convex_flutter`'s arg map (which runs `jsonEncode` on each value).
Object? prepareArgValue(Object? value) {
  if (value is BigInt) return int64Wire(value);
  if (value is Map) {
    final out = <String, Object?>{};
    value.forEach((k, v) {
      out[k as String] = prepareArgValue(v);
    });
    return out;
  }
  if (value is List) {
    return value.map(prepareArgValue).toList();
  }
  return value;
}

/// Walks a JSON-decoded structure produced by Convex, replacing every int64
/// envelope with its `BigInt` equivalent. Other values pass through.
Object? unwrapInt64s(Object? value) {
  if (value is Map) {
    final keys = value.keys.toList();
    if (keys.length == 1 && keys.first == _intKey) {
      return parseInt64Wire(value);
    }
    final out = <String, Object?>{};
    value.forEach((k, v) {
      out[k as String] = unwrapInt64s(v);
    });
    return out;
  }
  if (value is List) {
    return value.map(unwrapInt64s).toList();
  }
  return value;
}

/// Decodes a JSON response string from convex_flutter, recursively converting
/// int64 envelopes into `BigInt`. Returns `null` if `raw` is empty / "null".
Object? decodeConvexResponse(String raw) {
  if (raw.isEmpty) return null;
  final decoded = jsonDecode(raw);
  return unwrapInt64s(decoded);
}
