import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/convex/values.dart';

void main() {
  group('convexToJson', () {
    test('passes primitives through', () {
      expect(convexToJson(null), isNull);
      expect(convexToJson(true), true);
      expect(convexToJson(false), false);
      expect(convexToJson('hola'), 'hola');
      expect(convexToJson(5), 5);
      expect(convexToJson(2.5), 2.5);
    });

    test('encodes BigInt as \$integer with 8-byte LE two\'s complement', () {
      expect(convexToJson(BigInt.one), {r'$integer': 'AQAAAAAAAAA='});
      expect(convexToJson(BigInt.from(-1)), {r'$integer': '//////////8='});
      expect(convexToJson(BigInt.zero), {r'$integer': 'AAAAAAAAAAA='});
    });

    test('round-trips int64 boundary values', () {
      final min = BigInt.parse('-9223372036854775808');
      final max = BigInt.parse('9223372036854775807');
      expect(jsonToConvex(convexToJson(min)), min);
      expect(jsonToConvex(convexToJson(max)), max);
    });

    test('rejects BigInt outside int64 range', () {
      final tooBig = BigInt.parse('9223372036854775808');
      final tooSmall = BigInt.parse('-9223372036854775809');
      expect(() => convexToJson(tooBig), throwsA(isA<ConvexValueException>()));
      expect(
        () => convexToJson(tooSmall),
        throwsA(isA<ConvexValueException>()),
      );
    });

    test('rejects ints beyond float64 precision', () {
      expect(
        () => convexToJson(9007199254740993),
        throwsA(isA<ConvexValueException>()),
      );
      expect(convexToJson(9007199254740992), 9007199254740992);
    });

    test('encodes special doubles as \$float and plain doubles as numbers', () {
      expect(convexToJson(1.5), 1.5);
      // NaN has many valid bit patterns (Dart's is the negative quiet NaN),
      // so assert by round-trip rather than exact bytes.
      final nan = convexToJson(double.nan) as Map;
      expect(nan.keys.single, r'$float');
      expect((jsonToConvex(nan) as double).isNaN, isTrue);
      expect(convexToJson(double.infinity), {r'$float': 'AAAAAAAA8H8='});
      expect(convexToJson(double.negativeInfinity), {
        r'$float': 'AAAAAAAA8P8=',
      });
      expect(convexToJson(-0.0), {r'$float': 'AAAAAAAAAIA='});
    });

    test('encodes Uint8List as \$bytes', () {
      expect(convexToJson(Uint8List.fromList([1, 2, 3])), {
        r'$bytes': base64Encode([1, 2, 3]),
      });
    });

    test('sorts object keys byte-wise', () {
      final encoded = convexToJson({'b': 1, 'a': 2, 'aa': 3});
      expect(jsonEncode(encoded), '{"a":2,"aa":3,"b":1}');
    });

    test('recurses through lists and maps', () {
      final encoded = convexToJson({
        'list': [
          BigInt.from(7),
          {'inner': -0.0},
        ],
      });
      expect(encoded, {
        'list': [
          {r'$integer': 'BwAAAAAAAAA='},
          {
            'inner': {r'$float': 'AAAAAAAAAIA='},
          },
        ],
      });
    });

    test('rejects invalid field names', () {
      expect(
        () => convexToJson({r'$bad': 1}),
        throwsA(isA<ConvexValueException>()),
      );
      expect(() => convexToJson({'': 1}), throwsA(isA<ConvexValueException>()));
      expect(
        () => convexToJson({'ñandú': 1}),
        throwsA(isA<ConvexValueException>()),
      );
      expect(
        () => convexToJson({'x' * 1025: 1}),
        throwsA(isA<ConvexValueException>()),
      );
    });

    test('rejects unsupported types', () {
      expect(
        () => convexToJson(DateTime(2026)),
        throwsA(isA<ConvexValueException>()),
      );
      expect(
        () => convexToJson({1: 'non-string key'}),
        throwsA(isA<ConvexValueException>()),
      );
    });
  });

  group('convexArgsToJson', () {
    test('omits null-valued top-level args, keeps nested nulls', () {
      final encoded = convexArgsToJson({
        'present': 1,
        'omitted': null,
        'nested': {'kept': null},
      });
      expect(encoded, {
        'nested': {'kept': null},
        'present': 1,
      });
    });
  });

  group('jsonToConvex', () {
    test('decodes envelopes', () {
      expect(jsonToConvex({r'$integer': 'AQAAAAAAAAA='}), BigInt.one);
      expect(
        jsonToConvex({
          r'$bytes': base64Encode([9, 8]),
        }),
        Uint8List.fromList([9, 8]),
      );
      final negZero = jsonToConvex({r'$float': 'AAAAAAAAAIA='}) as double;
      expect(negZero, 0.0);
      expect(negZero.isNegative, isTrue);
      expect(
        (jsonToConvex({r'$float': 'AAAAAAAA+H8='}) as double).isNaN,
        isTrue,
      );
    });

    test('decodes nested structures', () {
      expect(
        jsonToConvex({
          'a': [
            {r'$integer': 'BwAAAAAAAAA='},
            'text',
          ],
        }),
        {
          'a': [BigInt.from(7), 'text'],
        },
      );
    });

    test('rejects legacy and unknown \$ envelopes', () {
      expect(
        () => jsonToConvex({r'$set': []}),
        throwsA(isA<ConvexValueException>()),
      );
      expect(
        () => jsonToConvex({r'$map': []}),
        throwsA(isA<ConvexValueException>()),
      );
      expect(
        () => jsonToConvex({'ok': 1, r'$weird': 2}),
        throwsA(isA<ConvexValueException>()),
      );
    });

    test('rejects malformed envelope payloads', () {
      expect(
        () => jsonToConvex({r'$integer': 'AQ=='}),
        throwsA(isA<ConvexValueException>()),
      );
      expect(
        () => jsonToConvex({r'$integer': 5}),
        throwsA(isA<ConvexValueException>()),
      );
      expect(
        () => jsonToConvex({r'$float': 'AQ=='}),
        throwsA(isA<ConvexValueException>()),
      );
    });

    test('round-trips a realistic sync push payload', () {
      final args = {
        'expectedServerSeq': BigInt.from(1724690000123),
        'rows': [
          {'amountCents': BigInt.from(-4599), 'note': 'café', 'deleted': false},
        ],
      };
      expect(jsonToConvex(convexToJson(args)), args);
    });
  });
}
