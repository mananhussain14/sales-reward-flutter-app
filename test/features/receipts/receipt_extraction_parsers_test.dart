import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/receipts/data/models/receipt_extraction_parsers.dart';
import 'package:sale_reward/features/receipts/data/models/receipt_parsers.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_civil_date.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_civil_time.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_entry_mode.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_field.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_outcome.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_result.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_failure_code.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_line_item.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_request_outcome.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_request_result.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_status.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_warning_code.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_image_preview.dart';

import '../../support/receipt_extraction_fakes.dart';

/// The parsers' contract with the backend.
///
/// Three properties are asserted over and over, because each is the difference
/// between an honest screen and a fabricated one:
///
/// 1. **A value the backend did not send is never invented.** Every missing
///    required field, wrong type and out-of-range number is a refusal, not a
///    default — and a refusal is `ReceiptFormatException`, never an empty list
///    and never a zero total.
/// 2. **Money stays an integer.** No amount is read through a decimal reader,
///    and a fractional amount is refused rather than rounded.
/// 3. **An unknown enum token degrades; a missing one refuses.** The two are
///    different facts: one is a newer backend, the other is a broken response.
void main() {
  group('every extraction status parses', () {
    for (final (String token, ReceiptExtractionStatus expected)
        in <(String, ReceiptExtractionStatus)>[
          ('QUEUED', ReceiptExtractionStatus.queued),
          ('PROCESSING', ReceiptExtractionStatus.processing),
          ('SUCCEEDED', ReceiptExtractionStatus.succeeded),
          ('FAILED', ReceiptExtractionStatus.failed),
        ]) {
      test(token, () {
        final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
          extractionPayload(<String, Object?>{'status': token}),
        );
        expect(parsed.status, expected);
      });
    }

    test(
      'an unrecognised token degrades to unknown, and unknown is not open',
      () {
        final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
          extractionPayload(<String, Object?>{'status': 'REVIEWING'}),
        );

        expect(parsed.status, ReceiptExtractionStatus.unknown);
        // A build that treated an unrecognised token as in-flight would poll for
        // a job that will never move.
        expect(parsed.status.isOpen, isFalse);
        expect(parsed.status.isTerminal, isFalse);
      },
    );

    test('a missing status is refused, not degraded', () {
      expect(
        () => ReceiptExtractionParser.parse(
          extractionPayload()..remove('status'),
        ),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('only QUEUED and PROCESSING are open', () {
      expect(ReceiptExtractionStatus.queued.isOpen, isTrue);
      expect(ReceiptExtractionStatus.processing.isOpen, isTrue);
      expect(ReceiptExtractionStatus.succeeded.isOpen, isFalse);
      expect(ReceiptExtractionStatus.failed.isOpen, isFalse);
    });
  });

  group('failure codes', () {
    test('the three client codes parse, and only three exist', () {
      expect(
        ReceiptExtractionFailureCode.values
            .where(
              (ReceiptExtractionFailureCode c) =>
                  c != ReceiptExtractionFailureCode.unknown,
            )
            .map((ReceiptExtractionFailureCode c) => c.code)
            .toList(),
        <String>[
          'IMAGE_NOT_A_RECEIPT',
          'IMAGE_UNUSABLE',
          'EXTRACTION_UNAVAILABLE',
        ],
      );
    });

    test('a FAILED attempt carries its client code', () {
      final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
        extractionPayload(<String, Object?>{
          'status': 'FAILED',
          'failure_code': 'IMAGE_NOT_A_RECEIPT',
        }),
      );

      expect(parsed.failureCode, ReceiptExtractionFailureCode.imageNotAReceipt);
      expect(parsed.failureCode!.isAboutTheImage, isTrue);
    });

    test('EXTRACTION_UNAVAILABLE is not about the image', () {
      expect(
        ReceiptExtractionFailureCode.extractionUnavailable.isAboutTheImage,
        isFalse,
      );
    });

    test('no failure code is null, not unknown', () {
      expect(
        ReceiptExtractionParser.parse(extractionPayload()).failureCode,
        isNull,
      );
    });

    test('a stored code that leaked through would still read as a failure', () {
      // The backend maps ten stored codes to three before they reach a client,
      // so this is unreachable today. If it ever were reachable, it must not
      // read as "no failure".
      final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
        extractionPayload(<String, Object?>{
          'status': 'FAILED',
          'failure_code': 'PROVIDER_QUOTA_EXCEEDED',
        }),
      );

      expect(parsed.failureCode, ReceiptExtractionFailureCode.unknown);
      expect(parsed.failureCode, isNotNull);
    });
  });

  group('warning codes', () {
    test('all twelve parse', () {
      const List<String> tokens = <String>[
        'LOW_CONFIDENCE_TOTAL',
        'LOW_CONFIDENCE_DATE',
        'MISSING_MERCHANT_NAME',
        'MISSING_DOCUMENT_NUMBER',
        'MISSING_TRANSACTION_TIME',
        'SUBTOTAL_TAX_TOTAL_MISMATCH',
        'AMBIGUOUS_AMOUNT_FORMAT',
        'NEGATIVE_AMOUNT_REJECTED',
        'ZERO_TOTAL',
        'DATE_IN_FUTURE',
        'CURRENCY_INFERRED_FROM_DEFAULT',
        'MULTIPLE_TOTALS_FOUND',
      ];

      final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
        extractionPayload(<String, Object?>{'warning_codes': tokens}),
      );

      expect(parsed.warningCodes, hasLength(12));
      expect(
        parsed.warningCodes.contains(ReceiptExtractionWarningCode.unknown),
        isFalse,
      );
      // The order the backend sent is preserved.
      expect(
        parsed.warningCodes.map((ReceiptExtractionWarningCode w) => w.code),
        tokens,
      );
    });

    test('an unknown warning is kept as unknown, never dropped', () {
      final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
        extractionPayload(<String, Object?>{
          'warning_codes': <String>['ZERO_TOTAL', 'TAX_LOOKS_ODD'],
        }),
      );

      expect(parsed.warningCodes, <ReceiptExtractionWarningCode>[
        ReceiptExtractionWarningCode.zeroTotal,
        ReceiptExtractionWarningCode.unknown,
      ]);
    });

    test('a null array is malformed, not "no warnings"', () {
      expect(
        () => ReceiptExtractionParser.parse(
          extractionPayload(<String, Object?>{'warning_codes': null}),
        ),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('a non-string element is refused rather than skipped', () {
      expect(
        () => ReceiptExtractionParser.parse(
          extractionPayload(<String, Object?>{
            'warning_codes': <Object?>['ZERO_TOTAL', 7],
          }),
        ),
        throwsA(isA<ReceiptFormatException>()),
      );
    });
  });

  group('integer minor units', () {
    test('the three amounts are ints, not doubles', () {
      final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
        extractionPayload(),
      );

      expect(parsed.total.value, 12550);
      expect(parsed.subtotal.value, 11952);
      expect(parsed.taxTotal.value, 598);
      expect(parsed.total.value, isA<int>());
      expect(parsed.subtotal.value, isA<int>());
      expect(parsed.taxTotal.value, isA<int>());
    });

    test('an integral JSON number is accepted as an integer', () {
      // JSON has one number type; a transport is entitled to hand back 12550.0.
      final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
        extractionPayload(<String, Object?>{'total_minor': 12550.0}),
      );
      expect(parsed.total.value, 12550);
    });

    test('a fractional amount is refused, never rounded', () {
      expect(
        () => ReceiptExtractionParser.parse(
          extractionPayload(<String, Object?>{'total_minor': 125.5}),
        ),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('zero is a real total and parses', () {
      // A fully discounted receipt is real, and carries ZERO_TOTAL.
      final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
        extractionPayload(<String, Object?>{
          'total_minor': 0,
          'warning_codes': <String>['ZERO_TOTAL'],
        }),
      );

      expect(parsed.total.value, 0);
      expect(parsed.total.isPresent, isTrue);
    });

    test('a negative amount is refused', () {
      expect(
        () => ReceiptExtractionParser.parse(
          extractionPayload(<String, Object?>{'total_minor': -1}),
        ),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('the 10^12 ceiling is inclusive, and one above it is refused', () {
      expect(
        ReceiptExtractionParser.parse(
          extractionPayload(<String, Object?>{'total_minor': 1000000000000}),
        ).total.value,
        1000000000000,
      );
      expect(
        () => ReceiptExtractionParser.parse(
          extractionPayload(<String, Object?>{'total_minor': 1000000000001}),
        ),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('a zero-minor-unit currency keeps its integer intact', () {
      // JPY 1,000 is 1000 minor units with zero decimal places.
      final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
        extractionPayload(<String, Object?>{
          'currency_code': 'JPY',
          'currency_minor_unit': 0,
          'total_minor': 1000,
          'total_source_text': '1,000',
        }),
      );

      expect(parsed.currencyMinorUnit, 0);
      expect(parsed.total.value, 1000);
    });

    test('a three-minor-unit currency keeps its integer intact', () {
      // KWD 12.500 is twelve and a half dinars: 12500 minor units.
      final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
        extractionPayload(<String, Object?>{
          'currency_code': 'KWD',
          'currency_minor_unit': 3,
          'total_minor': 12500,
          'total_source_text': 'KWD 12.500',
        }),
      );

      expect(parsed.currencyMinorUnit, 3);
      expect(parsed.total.value, 12500);
    });
  });

  group('nullable extracted fields', () {
    test('source text may exist while the value is null', () {
      // The important case: an amount whose separator could not be resolved.
      final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
        extractionPayload(<String, Object?>{
          'total_minor': null,
          'total_source_text': '1.234',
          'total_confidence': 0.4,
          'warning_codes': <String>['AMBIGUOUS_AMOUNT_FORMAT'],
        }),
      );

      expect(parsed.total.value, isNull);
      expect(parsed.total.sourceText, '1.234');
      expect(parsed.total.needsAttention, isTrue);
      expect(parsed.total.isAbsent, isFalse);
    });

    test('a field the provider never found is absent on all three parts', () {
      final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
        extractionPayload(<String, Object?>{
          'merchant_name': null,
          'merchant_name_source_text': null,
          'merchant_name_confidence': null,
          'warning_codes': <String>['MISSING_MERCHANT_NAME'],
        }),
      );

      expect(parsed.merchantName.isAbsent, isTrue);
      expect(parsed.merchantName.needsAttention, isFalse);
      expect(parsed.merchantName.confidence, isNull);
    });

    test('null tax is not zero tax', () {
      final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
        extractionPayload(<String, Object?>{'tax_total_minor': null}),
      );

      expect(parsed.taxTotal.value, isNull);
      expect(parsed.taxTotal.value, isNot(0));
    });

    test('an open attempt has no values and no completion time', () {
      final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
        extractionPayload(<String, Object?>{
          'status': 'PROCESSING',
          'completed_at': null,
          'merchant_name': null,
          'merchant_name_source_text': null,
          'merchant_name_confidence': null,
          'transaction_date': null,
          'transaction_date_source_text': null,
          'transaction_date_confidence': null,
          'transaction_time': null,
          'transaction_time_source_text': null,
          'transaction_time_confidence': null,
          'currency_code': null,
          'currency_code_source_text': null,
          'currency_code_confidence': null,
          'currency_minor_unit': null,
          'total_minor': null,
          'total_source_text': null,
          'total_confidence': null,
          'subtotal_minor': null,
          'subtotal_source_text': null,
          'subtotal_confidence': null,
          'tax_total_minor': null,
          'tax_source_text': null,
          'tax_confidence': null,
          'document_number': null,
          'document_number_source_text': null,
          'document_number_confidence': null,
          'line_item_count': 0,
        }),
      );

      expect(parsed.status, ReceiptExtractionStatus.processing);
      expect(parsed.completedAt, isNull);
      expect(parsed.currencyMinorUnit, isNull);
      expect(parsed.total.isAbsent, isTrue);
      expect(parsed.hasReading, isFalse);
    });

    test('a confidence outside 0..1 is malformed', () {
      expect(
        () => ReceiptExtractionParser.parse(
          extractionPayload(<String, Object?>{'total_confidence': 1.5}),
        ),
        throwsA(isA<ReceiptFormatException>()),
      );
    });
  });

  group('dates and times keep the backend representation', () {
    test('a date is a civil date, with no zone applied', () {
      final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
        extractionPayload(),
      );

      expect(parsed.transactionDate.value, const ReceiptCivilDate(2026, 7, 25));
      expect(parsed.transactionDate.value!.iso, '2026-07-25');
    });

    test('a time is a civil time, and round-trips', () {
      final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
        extractionPayload(),
      );

      expect(parsed.transactionTime.value, const ReceiptCivilTime(9, 24));
      expect(parsed.transactionTime.value!.iso, '09:24:00');
    });

    test('a timestamptz is normalized to UTC', () {
      final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
        extractionPayload(<String, Object?>{
          'requested_at': '2026-07-25T13:30:00+04:00',
        }),
      );

      expect(parsed.requestedAt.isUtc, isTrue);
      expect(parsed.requestedAt, DateTime.utc(2026, 7, 25, 9, 30));
    });

    test('a date that does not exist is refused, never rolled forward', () {
      expect(ReceiptCivilDate.tryParse('2026-02-30'), isNull);
      expect(
        () => ReceiptExtractionParser.parse(
          extractionPayload(<String, Object?>{
            'transaction_date': '2026-02-30',
          }),
        ),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('a timestamp is not accepted where a date belongs', () {
      expect(ReceiptCivilDate.tryParse('2026-07-25T00:00:00Z'), isNull);
    });

    test('minute truncation matches the comparison contract', () {
      expect(
        const ReceiptCivilTime(9, 24, 37).truncatedToMinute,
        const ReceiptCivilTime(9, 24),
      );
    });

    test('24:00:00 is refused', () {
      expect(ReceiptCivilTime.tryParse('24:00:00'), isNull);
    });

    test('fractional seconds parse and are dropped', () {
      expect(
        ReceiptCivilTime.tryParse('09:24:37.512'),
        const ReceiptCivilTime(9, 24, 37),
      );
    });
  });

  group('attempt counters and retry_allowed', () {
    test('the counters pass through untouched', () {
      final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
        extractionPayload(<String, Object?>{
          'attempt_number': 3,
          'attempts_used': 3,
          'attempts_remaining': 0,
        }),
      );

      expect(parsed.attemptNumber, 3);
      expect(parsed.attemptsUsed, 3);
      expect(parsed.attemptsRemaining, 0);
    });

    test('retry_allowed is read, never derived from the counters', () {
      // Two remaining attempts and retry_allowed false is the ordinary shape
      // when a gate is shut. Nothing may widen it.
      final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
        extractionPayload(<String, Object?>{
          'status': 'FAILED',
          'failure_code': 'EXTRACTION_UNAVAILABLE',
          'attempts_used': 1,
          'attempts_remaining': 2,
          'retry_allowed': false,
        }),
      );

      expect(parsed.attemptsRemaining, 2);
      expect(parsed.retryAllowed, isFalse);
    });

    test('retry_allowed true parses as true', () {
      expect(
        ReceiptExtractionParser.parse(
          extractionPayload(<String, Object?>{'retry_allowed': true}),
        ).retryAllowed,
        isTrue,
      );
    });

    test('a non-boolean flag is malformed, never coerced', () {
      for (final Object? value in <Object?>['true', 1, null]) {
        expect(
          () => ReceiptExtractionParser.parse(
            extractionPayload(<String, Object?>{'retry_allowed': value}),
          ),
          throwsA(isA<ReceiptFormatException>()),
          reason: '$value must not become true',
        );
      }
    });

    test('manual confirmation and confirmation_exists are read as sent', () {
      final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
        extractionPayload(<String, Object?>{
          'manual_confirmation_allowed': false,
          'confirmation_exists': true,
        }),
      );

      expect(parsed.isConfirmable, isFalse);
      expect(parsed.confirmationExists, isTrue);
    });
  });

  group('the request response', () {
    test('every outcome parses', () {
      for (final (String token, ReceiptExtractionRequestOutcome expected)
          in <(String, ReceiptExtractionRequestOutcome)>[
            (
              'ALREADY_CONFIRMED',
              ReceiptExtractionRequestOutcome.alreadyConfirmed,
            ),
            ('ACTIVE', ReceiptExtractionRequestOutcome.active),
            ('SUCCEEDED', ReceiptExtractionRequestOutcome.succeeded),
            ('EXHAUSTED', ReceiptExtractionRequestOutcome.exhausted),
            (
              'EXTRACTION_UNAVAILABLE',
              ReceiptExtractionRequestOutcome.extractionUnavailable,
            ),
            ('QUEUED', ReceiptExtractionRequestOutcome.queued),
          ]) {
        expect(
          ReceiptExtractionRequestResultParser.parse(
            requestExtractionBody(outcome: token),
          ).outcome,
          expected,
          reason: token,
        );
      }
    });

    test('an unknown outcome is not treated as QUEUED', () {
      final ReceiptExtractionRequestResult parsed =
          ReceiptExtractionRequestResultParser.parse(
            requestExtractionBody(outcome: 'RESCHEDULED'),
          );

      expect(parsed.outcome, ReceiptExtractionRequestOutcome.unknown);
      expect(parsed.outcome.consumedAnAttempt, isFalse);
      expect(parsed.outcome.isInFlight, isFalse);
    });

    test('a null extraction is a real answer', () {
      // ALREADY_CONFIRMED with a MANUAL confirmation, or a shut gate that has
      // never created a row.
      final ReceiptExtractionRequestResult parsed =
          ReceiptExtractionRequestResultParser.parse(
            requestExtractionBody(
              outcome: 'EXTRACTION_UNAVAILABLE',
              attemptsUsed: 0,
              attemptsRemaining: 3,
            ),
          );

      expect(parsed.extraction, isNull);
      expect(parsed.attemptsUsed, 0);
      expect(parsed.attemptsRemaining, 3);
      expect(parsed.retryAllowed, isFalse);
    });

    test('a nested extraction is parsed in full', () {
      final ReceiptExtractionRequestResult parsed =
          ReceiptExtractionRequestResultParser.parse(
            requestExtractionBody(
              outcome: 'QUEUED',
              extraction: extractionPayload(),
            ),
          );

      expect(parsed.extraction, isNotNull);
      expect(parsed.extraction!.extractionId, extractionAttemptUuid);
      expect(parsed.outcome.consumedAnAttempt, isTrue);
    });

    test(
      'an EXHAUSTED response reports zero remaining and manual confirmation',
      () {
        final ReceiptExtractionRequestResult parsed =
            ReceiptExtractionRequestResultParser.parse(
              requestExtractionBody(
                outcome: 'EXHAUSTED',
                attemptsUsed: 3,
                attemptsRemaining: 0,
              ),
            );

        expect(parsed.outcome, ReceiptExtractionRequestOutcome.exhausted);
        expect(parsed.attemptsRemaining, 0);
        expect(parsed.manualConfirmationAllowed, isTrue);
      },
    );

    test('a missing counter is malformed, not zero', () {
      expect(
        () => ReceiptExtractionRequestResultParser.parse(
          requestExtractionBody()..remove('attempts_used'),
        ),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('the get envelope requires its payload', () {
      expect(
        ReceiptExtractionEnvelopeParser.parse(getExtractionBody()).submissionId,
        extractionSubmissionUuid,
      );
      expect(
        () => ReceiptExtractionEnvelopeParser.parse(<String, Object?>{
          'status': 'ok',
          'extraction': null,
        }),
        throwsA(isA<ReceiptFormatException>()),
      );
    });
  });

  group('line items', () {
    test(
      'a full row parses, with money as integers and quantity as a decimal',
      () {
        final List<ReceiptExtractionLineItem> parsed =
            ReceiptExtractionLineItemParser.parseList(<Map<String, Object?>>[
              lineItemRow(),
            ]);

        expect(parsed, hasLength(1));
        expect(parsed.single.lineNumber, 1);
        expect(parsed.single.unitPriceMinor, 1250);
        expect(parsed.single.lineTotalMinor, 2500);
        expect(parsed.single.unitPriceMinor, isA<int>());
        expect(parsed.single.quantity, 2.0);
        expect(parsed.single.confidence, 0.87);
      },
    );

    test('an empty array is a real answer, not a refusal', () {
      expect(ReceiptExtractionLineItemParser.parseList(<Object?>[]), isEmpty);
    });

    test('a zero amount is a reading, and survives as zero', () {
      final ReceiptExtractionLineItem parsed =
          ReceiptExtractionLineItemParser.parseList(<Map<String, Object?>>[
            lineItemRow(<String, Object?>{
              'unit_price_minor': 0,
              'line_total_minor': 0,
            }),
          ]).single;

      // Zero and absent are different facts and the parser keeps them apart. A
      // free item priced at nothing is not an item whose price went unread.
      expect(parsed.unitPriceMinor, 0);
      expect(parsed.lineTotalMinor, 0);
      expect(parsed.unitPriceMinor, isNot(isNull));
      expect(parsed.lineTotalMinor, isNot(isNull));
    });

    test('a column the contract does not carry reaches nothing', () {
      // The line-item contract has no SKU, product code, reference or barcode.
      // Should one appear on the wire, there is no field to receive it and no
      // display to leak it into — the parser reads an explicit set of keys.
      final ReceiptExtractionLineItem parsed =
          ReceiptExtractionLineItemParser.parseList(<Map<String, Object?>>[
            lineItemRow(<String, Object?>{
              'sku': 'SKU-100',
              'product_code': 'PC-1',
              'barcode': '01234567',
              'reference': 'REF-9',
            }),
          ]).single;

      expect(parsed.description, 'Paracetamol 500mg');
      // Nothing on the entity holds any of them, so nothing can render one.
      expect(
        parsed.props.whereType<String>(),
        isNot(contains(anyOf('SKU-100', 'PC-1', '01234567', 'REF-9'))),
      );
    });

    test('every optional column may be null', () {
      final ReceiptExtractionLineItem parsed =
          ReceiptExtractionLineItemParser.parseList(<Map<String, Object?>>[
            lineItemRow(<String, Object?>{
              'description': null,
              'description_source_text': null,
              'quantity': null,
              'quantity_source_text': null,
              'unit_price_minor': null,
              'unit_price_source_text': null,
              'line_total_minor': null,
              'line_total_source_text': null,
              'confidence': null,
            }),
          ]).single;

      expect(parsed.lineNumber, 1);
      expect(parsed.description, isNull);
      expect(parsed.quantity, isNull);
      expect(parsed.unitPriceMinor, isNull);
      expect(parsed.lineTotalMinor, isNull);
    });

    test('the backend order is preserved', () {
      final List<ReceiptExtractionLineItem> parsed =
          ReceiptExtractionLineItemParser.parseList(<Map<String, Object?>>[
            lineItemRow(<String, Object?>{'line_number': 1}),
            lineItemRow(<String, Object?>{'line_number': 2}),
            lineItemRow(<String, Object?>{'line_number': 3}),
          ]);

      expect(parsed.map((ReceiptExtractionLineItem i) => i.lineNumber), <int>[
        1,
        2,
        3,
      ]);
    });

    test('a fractional line amount is refused', () {
      expect(
        () => ReceiptExtractionLineItemParser.parseList(<Map<String, Object?>>[
          lineItemRow(<String, Object?>{'line_total_minor': 25.5}),
        ]),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('a body that is not a list is malformed', () {
      expect(
        () => ReceiptExtractionLineItemParser.parseList(<String, Object?>{
          'line_number': 1,
        }),
        throwsA(isA<ReceiptFormatException>()),
      );
    });
  });

  group('image preview', () {
    test('the url and window parse', () {
      final ReceiptImagePreview parsed = ReceiptImagePreviewParser.parse(
        imagePreviewBody(),
      );

      expect(parsed.expiresInSeconds, 120);
      expect(parsed.url, isNotEmpty);
    });

    test('the url never appears in toString or in equality', () {
      // A value object printed into a debug log is the ordinary way a
      // credential outlives its window.
      final ReceiptImagePreview parsed = ReceiptImagePreviewParser.parse(
        imagePreviewBody(),
      );

      expect(parsed.toString(), isNot(contains(parsed.url)));
      expect(
        parsed,
        ReceiptImagePreviewParser.parse(
          imagePreviewBody(url: 'https://example.supabase.co/other'),
        ),
      );
    });

    test('a missing url is malformed', () {
      expect(
        () => ReceiptImagePreviewParser.parse(imagePreviewBody(url: null)),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('a blank url is malformed', () {
      expect(
        () => ReceiptImagePreviewParser.parse(imagePreviewBody(url: '   ')),
        throwsA(isA<ReceiptFormatException>()),
      );
    });
  });

  group('confirmation', () {
    test('every entry mode parses', () {
      for (final (String token, ReceiptConfirmationEntryMode expected)
          in <(String, ReceiptConfirmationEntryMode)>[
            ('MANUAL', ReceiptConfirmationEntryMode.manual),
            ('EXTRACTED', ReceiptConfirmationEntryMode.extracted),
            ('MIXED', ReceiptConfirmationEntryMode.mixed),
          ]) {
        expect(
          ReceiptConfirmationParser.parseSingle(<Map<String, Object?>>[
            confirmationRow(<String, Object?>{'entry_mode': token}),
          ])!.entryMode,
          expected,
          reason: token,
        );
      }
    });

    test('an unknown entry mode degrades', () {
      expect(
        ReceiptConfirmationParser.parseSingle(<Map<String, Object?>>[
          confirmationRow(<String, Object?>{'entry_mode': 'IMPORTED'}),
        ])!.entryMode,
        ReceiptConfirmationEntryMode.unknown,
      );
    });

    test('all eight changed fields parse, in the order sent', () {
      const List<String> sorted = <String>[
        'currency_code',
        'document_number',
        'merchant_name',
        'subtotal_minor',
        'tax_total_minor',
        'total_minor',
        'transaction_date',
        'transaction_time',
      ];

      final ReceiptConfirmation parsed = ReceiptConfirmationParser.parseSingle(
        <Map<String, Object?>>[
          confirmationRow(<String, Object?>{
            'entry_mode': 'MIXED',
            'changed_fields': sorted,
          }),
        ],
      )!;

      expect(
        parsed.changedFields.map((ReceiptConfirmationField f) => f.code),
        sorted,
      );
      expect(
        parsed.changedFields.contains(ReceiptConfirmationField.unknown),
        isFalse,
      );
      expect(parsed.wasCorrected, isTrue);
    });

    test('an unknown changed field is kept, so the count stays honest', () {
      final ReceiptConfirmation parsed = ReceiptConfirmationParser.parseSingle(
        <Map<String, Object?>>[
          confirmationRow(<String, Object?>{
            'entry_mode': 'MIXED',
            'changed_fields': <String>['total_minor', 'tip_minor'],
          }),
        ],
      )!;

      expect(parsed.changedFields, hasLength(2));
      expect(parsed.changedFields.last, ReceiptConfirmationField.unknown);
    });

    test('a MANUAL confirmation has no source extraction', () {
      final ReceiptConfirmation parsed = ReceiptConfirmationParser.parseSingle(
        <Map<String, Object?>>[
          confirmationRow(<String, Object?>{
            'entry_mode': 'MANUAL',
            'source_extraction_id': null,
            'changed_fields': <String>[],
          }),
        ],
      )!;

      expect(parsed.entryMode, ReceiptConfirmationEntryMode.manual);
      expect(parsed.sourceExtractionId, isNull);
      expect(parsed.wasCorrected, isFalse);
    });

    test('optional values may be null and amounts stay integers', () {
      final ReceiptConfirmation parsed = ReceiptConfirmationParser.parseSingle(
        <Map<String, Object?>>[
          confirmationRow(<String, Object?>{
            'transaction_time': null,
            'subtotal_minor': null,
            'tax_total_minor': null,
            'merchant_name': null,
            'document_number': null,
          }),
        ],
      )!;

      expect(parsed.transactionTime, isNull);
      expect(parsed.subtotalMinor, isNull);
      expect(parsed.taxTotalMinor, isNull);
      expect(parsed.totalMinor, 12550);
      expect(parsed.totalMinor, isA<int>());
      expect(parsed.currencyCode, 'AED');
      expect(parsed.currencyMinorUnit, 2);
      expect(parsed.confirmedAt.isUtc, isTrue);
    });

    test('zero rows is null, not a refusal', () {
      expect(ReceiptConfirmationParser.parseSingle(<Object?>[]), isNull);
    });

    test('more than one row is malformed', () {
      expect(
        () => ReceiptConfirmationParser.parseSingle(<Map<String, Object?>>[
          confirmationRow(),
          confirmationRow(),
        ]),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('a missing required value is malformed', () {
      for (final String key in <String>[
        'confirmation_id',
        'entry_mode',
        'transaction_date',
        'currency_code',
        'currency_minor_unit',
        'total_minor',
        'confirmed_at',
      ]) {
        expect(
          () => ReceiptConfirmationParser.parseSingle(<Map<String, Object?>>[
            confirmationRow()..remove(key),
          ]),
          throwsA(isA<ReceiptFormatException>()),
          reason: key,
        );
      }
    });
  });

  group('the confirmation result', () {
    test('every outcome parses', () {
      for (final (String token, ReceiptConfirmationOutcome expected)
          in <(String, ReceiptConfirmationOutcome)>[
            ('CONFIRMED', ReceiptConfirmationOutcome.confirmed),
            ('ALREADY_CONFIRMED', ReceiptConfirmationOutcome.alreadyConfirmed),
            (
              'EXTRACTION_IN_PROGRESS',
              ReceiptConfirmationOutcome.extractionInProgress,
            ),
          ]) {
        expect(
          ReceiptConfirmationResultParser.parseSingle(<Map<String, Object?>>[
            confirmationResultRow(<String, Object?>{'outcome': token}),
          ])!.outcome,
          expected,
          reason: token,
        );
      }
    });

    test('an unknown outcome is never read as confirmed', () {
      final ReceiptConfirmationResult parsed =
          ReceiptConfirmationResultParser.parseSingle(<Map<String, Object?>>[
            confirmationResultRow(<String, Object?>{'outcome': 'DEFERRED'}),
          ])!;

      expect(parsed.outcome, ReceiptConfirmationOutcome.unknown);
      expect(parsed.outcome.isSettled, isFalse);
    });

    test('the blocked branch carries three nulls and an empty list', () {
      final ReceiptConfirmationResult parsed =
          ReceiptConfirmationResultParser.parseSingle(<Map<String, Object?>>[
            confirmationResultRow(<String, Object?>{
              'outcome': 'EXTRACTION_IN_PROGRESS',
              'confirmation_id': null,
              'entry_mode': null,
              'changed_fields': null,
            }),
          ])!;

      expect(parsed.outcome, ReceiptConfirmationOutcome.extractionInProgress);
      expect(parsed.confirmationId, isNull);
      expect(parsed.entryMode, isNull);
      expect(parsed.changedFields, isEmpty);
    });

    test('ALREADY_CONFIRMED returns the stored row', () {
      final ReceiptConfirmationResult parsed =
          ReceiptConfirmationResultParser.parseSingle(<Map<String, Object?>>[
            confirmationResultRow(<String, Object?>{
              'outcome': 'ALREADY_CONFIRMED',
              'entry_mode': 'MIXED',
              'changed_fields': <String>['total_minor'],
            }),
          ])!;

      expect(parsed.outcome.isSettled, isTrue);
      expect(parsed.confirmationId, extractionConfirmationUuid);
      expect(parsed.entryMode, ReceiptConfirmationEntryMode.mixed);
      expect(parsed.changedFields, <ReceiptConfirmationField>[
        ReceiptConfirmationField.totalMinor,
      ]);
    });

    test('zero rows is null — the access predicate said no', () {
      expect(ReceiptConfirmationResultParser.parseSingle(<Object?>[]), isNull);
    });
  });

  group('malformed responses', () {
    test('a body that is not an object is refused', () {
      expect(
        () => ReceiptExtractionParser.parse(<String, Object?>{}),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('every required extraction field is required', () {
      for (final String key in <String>[
        'submission_id',
        'extraction_id',
        'status',
        'attempt_number',
        'attempts_used',
        'attempts_remaining',
        'retry_allowed',
        'manual_confirmation_allowed',
        'confirmation_exists',
        'requested_at',
        'warning_codes',
        'line_item_count',
      ]) {
        expect(
          () => ReceiptExtractionParser.parse(extractionPayload()..remove(key)),
          throwsA(isA<ReceiptFormatException>()),
          reason: key,
        );
      }
    });

    test('an id that is not a UUID is refused', () {
      expect(
        () => ReceiptExtractionParser.parse(
          extractionPayload(<String, Object?>{'extraction_id': 'not-a-uuid'}),
        ),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test('a wrong-typed value is refused rather than coerced', () {
      expect(
        () => ReceiptExtractionParser.parse(
          extractionPayload(<String, Object?>{'merchant_name': 7}),
        ),
        throwsA(isA<ReceiptFormatException>()),
      );
      expect(
        () => ReceiptExtractionParser.parse(
          extractionPayload(<String, Object?>{'attempts_used': 'two'}),
        ),
        throwsA(isA<ReceiptFormatException>()),
      );
    });

    test(
      'an unrecognised extra key is ignored, so an additive column is safe',
      () {
        final ReceiptExtraction parsed = ReceiptExtractionParser.parse(
          extractionPayload(<String, Object?>{'tip_minor': 500}),
        );
        expect(parsed.total.value, 12550);
      },
    );
  });
}
