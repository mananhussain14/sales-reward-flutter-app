import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_file.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_image_type.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_rejection_reason.dart';

import '../../support/receipt_fakes.dart';

/// The client-side pre-check exists for immediate feedback and for nothing
/// else — the Edge Function validates the same bytes again and its answer is the
/// one that is stored. What these tests protect is that the pre-check is neither
/// *more* permissive than the backend (which would produce a confusing late
/// refusal) nor authoritative (which it must never become).
void main() {
  group('signature sniffing', () {
    test('recognises the three supported formats from their leading bytes', () {
      expect(ReceiptImageType.sniff(jpegBytes()), ReceiptImageType.jpeg);
      expect(ReceiptImageType.sniff(pngBytes()), ReceiptImageType.png);
      expect(ReceiptImageType.sniff(webpBytes()), ReceiptImageType.webp);
    });

    test('the three mime types match the backend vocabulary exactly', () {
      expect(
        ReceiptImageType.values.map((ReceiptImageType t) => t.mimeType),
        <String>['image/jpeg', 'image/png', 'image/webp'],
      );
    });

    test('a PDF is refused however it is named or declared', () {
      // The whole point: a file called receipt.jpg whose bytes are a PDF.
      expect(ReceiptImageType.sniff(pdfBytes()), isNull);

      final ReceiptFileValidation result = ReceiptFileValidator.validate(
        fileName: 'receipt.jpg',
        bytes: pdfBytes(),
      );

      expect(result, isA<ReceiptFileRefused>());
      expect(
        (result as ReceiptFileRefused).reason,
        ReceiptRejectionReason.unsupportedType,
      );
    });

    test('a truncated signature is not a match', () {
      expect(
        ReceiptImageType.sniff(Uint8List.fromList(<int>[0xff, 0xd8])),
        isNull,
      );
      expect(ReceiptImageType.sniff(Uint8List(0)), isNull);
    });

    test('RIFF without WEBP at offset 8 is not a WebP', () {
      final Uint8List riffOnly = Uint8List(32);
      for (int i = 0; i < 4; i++) {
        riffOnly[i] = <int>[0x52, 0x49, 0x46, 0x46][i];
      }
      expect(ReceiptImageType.sniff(riffOnly), isNull);
    });
  });

  group('validation', () {
    test('accepts a well-formed image and derives the type from the bytes', () {
      final ReceiptFileValidation result = ReceiptFileValidator.validate(
        // A deliberately wrong extension. The type must come from the bytes.
        fileName: 'receipt.jpg',
        bytes: pngBytes(),
      );

      expect(result, isA<ReceiptFileAccepted>());
      final ReceiptFile file = (result as ReceiptFileAccepted).file;
      expect(file.imageType, ReceiptImageType.png);
      expect(file.imageType.mimeType, 'image/png');
      expect(file.fileName, 'receipt.jpg');
      expect(file.sizeBytes, 64);
    });

    test('refuses absent bytes', () {
      final ReceiptFileValidation result = ReceiptFileValidator.validate(
        fileName: 'receipt.png',
        bytes: null,
      );

      expect(
        (result as ReceiptFileRefused).reason,
        ReceiptRejectionReason.missing,
      );
    });

    test('refuses an empty file', () {
      final ReceiptFileValidation result = ReceiptFileValidator.validate(
        fileName: 'receipt.png',
        bytes: Uint8List(0),
      );

      expect(
        (result as ReceiptFileRefused).reason,
        ReceiptRejectionReason.empty,
      );
    });

    test(
      'refuses a file over 10 MiB, and accepts one exactly at the limit',
      () {
        expect(maxReceiptFileBytes, 10 * 1024 * 1024);

        final ReceiptFileValidation over = ReceiptFileValidator.validate(
          fileName: 'receipt.png',
          bytes: pngBytes(length: maxReceiptFileBytes + 1),
        );
        final ReceiptFileValidation at = ReceiptFileValidator.validate(
          fileName: 'receipt.png',
          bytes: pngBytes(length: maxReceiptFileBytes),
        );

        expect(
          (over as ReceiptFileRefused).reason,
          ReceiptRejectionReason.tooLarge,
        );
        expect(at, isA<ReceiptFileAccepted>());
      },
    );

    test('size is checked before the signature, as it is on the server', () {
      // An oversized file is refused without being sniffed, so the reason a
      // person sees is the actionable one.
      final ReceiptFileValidation result = ReceiptFileValidator.validate(
        fileName: 'receipt.pdf',
        bytes: Uint8List(maxReceiptFileBytes + 1),
      );

      expect(
        (result as ReceiptFileRefused).reason,
        ReceiptRejectionReason.tooLarge,
      );
    });

    test('refuses a name that sanitizes to nothing', () {
      final ReceiptFileValidation result = ReceiptFileValidator.validate(
        fileName: '   ',
        bytes: pngBytes(),
      );

      expect(
        (result as ReceiptFileRefused).reason,
        ReceiptRejectionReason.invalidName,
      );
    });
  });

  group('filename sanitization', () {
    test('a traversal attempt reduces to its last segment', () {
      expect(
        sanitizeReceiptFileName('../../etc/My Receipt.png'),
        'My Receipt.png',
      );
      expect(sanitizeReceiptFileName(r'C:\Users\sam\y.jpg'), 'y.jpg');
    });

    test('control characters are removed and whitespace collapsed', () {
      expect(
        sanitizeReceiptFileName('  re\u0000ceipt   copy.png  '),
        'receipt copy.png',
      );
    });

    test('a name longer than the column is capped', () {
      final String long = '${'a' * 400}.png';
      expect(
        sanitizeReceiptFileName(long)!.length,
        lessThanOrEqualTo(maxReceiptFileNameLength),
      );
    });

    test('nothing usable yields null rather than a placeholder', () {
      expect(sanitizeReceiptFileName(null), isNull);
      expect(sanitizeReceiptFileName(''), isNull);
      expect(sanitizeReceiptFileName('///'), isNull);
      expect(sanitizeReceiptFileName('\u0000'), isNull);
    });
  });

  group('file facts', () {
    test('readable sizes match the backend thresholds', () {
      expect(formatReceiptFileSize(0), '0 B');
      expect(formatReceiptFileSize(1023), '1023 B');
      expect(formatReceiptFileSize(1024), '1 KB');
      expect(formatReceiptFileSize(1024 * 1024), '1.0 MB');
      expect(formatReceiptFileSize(-1), '—');
    });

    test('two selections are never equal, even with identical facts', () {
      // Identity equality is deliberate: replacing a file with another of the
      // same name, type and length must still emit a new state, and up to
      // 10 MiB of bytes must never be deep-compared on every emission.
      final ReceiptFile a = testReceiptFile();
      final ReceiptFile b = testReceiptFile();

      expect(a == b, isFalse);
      expect(a == a, isTrue);
    });
  });

  group('rejection vocabulary', () {
    test('maps every token the Edge Function can return', () {
      expect(
        ReceiptRejectionReason.fromCode('malformed-body'),
        ReceiptRejectionReason.malformedBody,
      );
      expect(
        ReceiptRejectionReason.fromCode('invalid-shop'),
        ReceiptRejectionReason.invalidShop,
      );
      expect(
        ReceiptRejectionReason.fromCode('missing'),
        ReceiptRejectionReason.missing,
      );
      expect(
        ReceiptRejectionReason.fromCode('empty'),
        ReceiptRejectionReason.empty,
      );
      expect(
        ReceiptRejectionReason.fromCode('too-large'),
        ReceiptRejectionReason.tooLarge,
      );
      expect(
        ReceiptRejectionReason.fromCode('unsupported-type'),
        ReceiptRejectionReason.unsupportedType,
      );
      expect(
        ReceiptRejectionReason.fromCode('invalid-name'),
        ReceiptRejectionReason.invalidName,
      );
      expect(
        ReceiptRejectionReason.fromCode('too-many-files'),
        ReceiptRejectionReason.tooManyFiles,
      );
      expect(
        ReceiptRejectionReason.fromCode('rejected'),
        ReceiptRejectionReason.rejected,
      );
    });

    test('an unfamiliar token becomes unknown rather than being carried', () {
      expect(
        ReceiptRejectionReason.fromCode('some-future-reason'),
        ReceiptRejectionReason.unknown,
      );
      expect(
        ReceiptRejectionReason.fromCode(null),
        ReceiptRejectionReason.unknown,
      );
    });
  });
}
