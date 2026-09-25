import 'package:app/attachments/attachment_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves by reported type first, then by extension', () {
    expect(resolveAttachmentType('application/pdf', 'x.bin')?.kind, 'pdf');
    expect(
      resolveAttachmentType('', 'resumen.OFX')?.mimeType,
      'application/x-ofx',
    );
    expect(
      resolveAttachmentType('application/octet-stream', 'gastos.csv')?.kind,
      'text',
    );
    expect(resolveAttachmentType('image/heic', 'IMG_1.heic'), isNull);
    expect(isConvertibleImage('image/heic', 'photo'), isTrue);
    expect(isConvertibleImage(null, 'IMG_0001.HEIF'), isTrue);
  });

  test('composed messages split back into text and attachments', () {
    const attachments = [
      SentAttachment(id: 'a1', name: 'ticket "1".jpg', kind: 'image'),
      SentAttachment(id: 'b2', name: 'resumen.pdf', kind: 'pdf'),
    ];
    final message = composeMessageText(' Te paso esto ', attachments);
    expect(
      message,
      'Te paso esto\n'
      '[Attachment id=a1 name="ticket \\"1\\".jpg" type=image]\n'
      '[Attachment id=b2 name="resumen.pdf" type=pdf]',
    );
    final split = splitAttachmentLines(message);
    expect(split.text, 'Te paso esto');
    expect(split.attachments, attachments);
  });

  test('a message without attachment lines comes back unchanged', () {
    final split = splitAttachmentLines('Hola\n[no es un adjunto]');
    expect(split.text, 'Hola\n[no es un adjunto]');
    expect(split.attachments, isEmpty);
  });
}
