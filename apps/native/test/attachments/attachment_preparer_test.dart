import 'dart:typed_data';

import 'package:app/attachments/attachment_preparer.dart';
import 'package:app/voice/agent_generated.dart';
import 'package:flutter_test/flutter_test.dart';

PickedAttachment picked(String name, {String? mimeType, int length = 4}) =>
    PickedAttachment(
      name: name,
      mimeType: mimeType,
      size: length,
      readBytes: () async => Uint8List(length),
    );

int maxBytesFor(String kind) =>
    kAttachmentTypes.firstWhere((type) => type.kind == kind).maxBytes;

void main() {
  test('refuses unsupported types and files over their kind limit', () async {
    expect(
      await prepareAttachment(picked('app.exe')),
      isA<PrepareFailed>().having(
        (f) => f.failure,
        'failure',
        PrepareFailure.unsupportedType,
      ),
    );
    expect(
      await prepareAttachment(
        picked('big.csv', length: maxBytesFor('text') + 1),
      ),
      isA<PrepareFailed>().having(
        (f) => f.failure,
        'failure',
        PrepareFailure.tooLarge,
      ),
    );
  });

  test('documents pass through untouched', () async {
    final outcome = await prepareAttachment(picked('resumen.pdf'));
    expect(outcome, isA<Prepared>());
    final file = (outcome as Prepared).file;
    expect(file.name, 'resumen.pdf');
    expect(file.type.mimeType, 'application/pdf');
  });

  test('images that fit are sent as they are', () async {
    final outcome = await prepareAttachment(
      picked('ticket.jpg'),
      resize: (bytes, {required force}) async => bytes,
    );
    expect((outcome as Prepared).file.type.mimeType, 'image/jpeg');
  });

  test('oversized images and HEIC become PNG', () async {
    final png = Uint8List.fromList([1, 2, 3]);
    final resized = await prepareAttachment(
      picked('huge.jpg'),
      resize: (bytes, {required force}) async => png,
    );
    expect((resized as Prepared).file.name, 'huge.png');
    expect(resized.file.type.mimeType, 'image/png');

    var forced = false;
    final heic = await prepareAttachment(
      picked('IMG_0001.HEIC', mimeType: 'image/heic'),
      resize: (bytes, {required force}) async {
        forced = force;
        return png;
      },
    );
    expect(forced, isTrue);
    expect((heic as Prepared).file.name, 'IMG_0001.png');
  });

  test('HEIC the platform cannot decode is refused', () async {
    expect(
      await prepareAttachment(
        picked('IMG_0001.heic'),
        resize: (bytes, {required force}) async => null,
      ),
      isA<PrepareFailed>(),
    );
  });
}
