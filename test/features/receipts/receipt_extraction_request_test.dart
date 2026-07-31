import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/receipts/data/datasources/receipt_extraction_function_client.dart';
import 'package:sale_reward/features/receipts/data/models/receipt_confirmation_request_body.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_civil_date.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_civil_time.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_input.dart';

import '../../support/receipt_extraction_fakes.dart';

/// What leaves the device, exhaustively.
///
/// Two request shapes exist in this feature and both are pinned here rather than
/// trusted to a comment: the one-key Edge Function body, and the nine-parameter
/// confirmation. A field the backend derives must be impossible to send, and the
/// only way to prove that cheaply is to assert the whole key set.
void main() {
  ReceiptConfirmationInput input({
    String submissionId = extractionSubmissionUuid,
    ReceiptCivilDate transactionDate = const ReceiptCivilDate(2026, 7, 25),
    String currencyCode = 'AED',
    int totalMinor = 12550,
    String? merchantName,
    String? documentNumber,
    ReceiptCivilTime? transactionTime,
    int? subtotalMinor,
    int? taxTotalMinor,
  }) {
    return ReceiptConfirmationInput(
      submissionId: submissionId,
      transactionDate: transactionDate,
      currencyCode: currencyCode,
      totalMinor: totalMinor,
      merchantName: merchantName,
      documentNumber: documentNumber,
      transactionTime: transactionTime,
      subtotalMinor: subtotalMinor,
      taxTotalMinor: taxTotalMinor,
    );
  }

  group('the Edge Function request body', () {
    test('carries exactly one key', () {
      final Map<String, Object?> body = receiptExtractionRequestBody(
        extractionSubmissionUuid,
      );

      expect(body.keys.toList(), <String>['submission_id']);
      expect(body['submission_id'], extractionSubmissionUuid);
    });

    test('the one key is the name the endpoints allowlist', () {
      // An unknown key is a 400 on all three endpoints, not an ignored extra.
      expect(extractionSubmissionIdField, 'submission_id');
    });

    test('the three function names are the deployed ones', () {
      expect(requestReceiptExtractionFunction, 'request-receipt-extraction');
      expect(getReceiptExtractionFunction, 'get-receipt-extraction');
      expect(receiptImagePreviewFunction, 'receipt-image-preview');
    });
  });

  group('the confirmation parameter map', () {
    test('names exactly the nine parameters the RPC declares', () {
      expect(buildReceiptConfirmationParams(input()).keys.toList(), <String>[
        'p_submission_id',
        'p_transaction_date',
        'p_currency_code',
        'p_total_minor',
        'p_merchant_name',
        'p_document_number',
        'p_transaction_time',
        'p_subtotal_minor',
        'p_tax_total_minor',
      ]);
    });

    test('the key set is fixed, whatever the optional values are', () {
      final Map<String, Object?> minimal = buildReceiptConfirmationParams(
        input(),
      );
      final Map<String, Object?> full = buildReceiptConfirmationParams(
        input(
          merchantName: 'Marina Pharmacy',
          documentNumber: 'INV-2026/004512',
          transactionTime: const ReceiptCivilTime(9, 24),
          subtotalMinor: 11952,
          taxTotalMinor: 598,
        ),
      );

      expect(full.keys.toList(), minimal.keys.toList());
    });

    test('no derived value can be expressed', () {
      final Set<String> keys = buildReceiptConfirmationParams(
        input(),
      ).keys.toSet();

      for (final String forbidden in <String>[
        'p_organization_id',
        'p_retailer_id',
        'p_shop_id',
        'p_profile_id',
        'p_membership_id',
        'p_extraction_id',
        'p_entry_mode',
        'p_changed_fields',
        'p_attempt_number',
        'p_mode',
        'p_provider',
        'p_claim_token',
      ]) {
        expect(keys.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    group('integer minor units survive the encoding', () {
      test('the three amounts are sent as ints, unscaled', () {
        final Map<String, Object?> params = buildReceiptConfirmationParams(
          input(totalMinor: 12550, subtotalMinor: 11952, taxTotalMinor: 598),
        );

        expect(params['p_total_minor'], 12550);
        expect(params['p_subtotal_minor'], 11952);
        expect(params['p_tax_total_minor'], 598);
        expect(params['p_total_minor'], isA<int>());
        expect(params['p_subtotal_minor'], isA<int>());
        expect(params['p_tax_total_minor'], isA<int>());
      });

      test('no amount is ever a double', () {
        final Map<String, Object?> params = buildReceiptConfirmationParams(
          input(totalMinor: 1999),
        );

        expect(params['p_total_minor'], isNot(isA<double>()));
        // 19.99 as minor units is 1999 — never 19.99 * 100, which is not 1999
        // in binary floating point.
        expect(params['p_total_minor'], 1999);
      });

      test('zero is sent as zero', () {
        expect(
          buildReceiptConfirmationParams(input(totalMinor: 0))['p_total_minor'],
          0,
        );
      });

      test('the ceiling survives without precision loss', () {
        expect(
          buildReceiptConfirmationParams(
            input(totalMinor: 1000000000000),
          )['p_total_minor'],
          1000000000000,
        );
      });

      test('an omitted subtotal is null, never zero', () {
        final Map<String, Object?> params = buildReceiptConfirmationParams(
          input(),
        );

        expect(params['p_subtotal_minor'], isNull);
        expect(params['p_tax_total_minor'], isNull);
        expect(params['p_subtotal_minor'], isNot(0));
      });

      test('an explicit zero tax stays zero, not null', () {
        // Zero tax is a fact; unknown tax is not. `is distinct from` keeps them
        // apart in the comparison, so the encoding must too.
        expect(
          buildReceiptConfirmationParams(
            input(taxTotalMinor: 0),
          )['p_tax_total_minor'],
          0,
        );
      });
    });

    test('the date and time are sent in the backend representation', () {
      final Map<String, Object?> params = buildReceiptConfirmationParams(
        input(
          transactionDate: const ReceiptCivilDate(2026, 1, 5),
          transactionTime: const ReceiptCivilTime(9, 4),
        ),
      );

      expect(params['p_transaction_date'], '2026-01-05');
      expect(params['p_transaction_time'], '09:04:00');
    });

    test('an omitted time is null', () {
      expect(
        buildReceiptConfirmationParams(input())['p_transaction_time'],
        isNull,
      );
    });

    test('the currency is trimmed and upper-cased', () {
      expect(
        buildReceiptConfirmationParams(
          input(currencyCode: ' aed '),
        )['p_currency_code'],
        'AED',
      );
    });

    test('blank optional text becomes null', () {
      final Map<String, Object?> params = buildReceiptConfirmationParams(
        input(merchantName: '   ', documentNumber: ''),
      );

      expect(params['p_merchant_name'], isNull);
      expect(params['p_document_number'], isNull);
    });

    test('optional text is trimmed but otherwise sent as typed', () {
      final Map<String, Object?> params = buildReceiptConfirmationParams(
        input(
          merchantName: '  Marina  Pharmacy  ',
          documentNumber: ' INV-2026/004512 ',
        ),
      );

      // Whitespace collapsing and punctuation stripping are the backend's
      // comparison rules, applied to both sides. This client does not
      // pre-apply them and cannot, because it does not hold the stored value.
      expect(params['p_merchant_name'], 'Marina  Pharmacy');
      expect(params['p_document_number'], 'INV-2026/004512');
    });
  });

  group('the client-side pre-check', () {
    test('a well-formed input passes', () {
      expect(input().validate(), isNull);
    });

    test('a malformed submission id is refused', () {
      expect(
        input(submissionId: 'not-a-uuid').validate(),
        ReceiptConfirmationProblem.invalidSubmissionId,
      );
    });

    test('a currency of the wrong shape is refused', () {
      expect(
        input(currencyCode: 'AE').validate(),
        ReceiptConfirmationProblem.invalidCurrency,
      );
      expect(
        input(currencyCode: 'AE1').validate(),
        ReceiptConfirmationProblem.invalidCurrency,
      );
    });

    test('a three-letter code this client does not know still passes', () {
      // Membership is a 165-row foreign key the backend owns. Checking the
      // shape here must not become a second, drifting definition of the list.
      expect(input(currencyCode: 'XCD').validate(), isNull);
    });

    test('a negative or oversized amount is refused', () {
      expect(
        input(totalMinor: -1).validate(),
        ReceiptConfirmationProblem.invalidTotal,
      );
      expect(
        input(totalMinor: 1000000000001).validate(),
        ReceiptConfirmationProblem.invalidTotal,
      );
      expect(
        input(subtotalMinor: -1).validate(),
        ReceiptConfirmationProblem.invalidSubtotal,
      );
      expect(
        input(taxTotalMinor: 1000000000001).validate(),
        ReceiptConfirmationProblem.invalidTax,
      );
    });

    test('the ceiling itself is accepted', () {
      expect(input(totalMinor: maxMinorAmount).validate(), isNull);
      expect(input(totalMinor: minMinorAmount).validate(), isNull);
    });

    test('over-long text is refused at the backend bounds', () {
      expect(
        input(merchantName: 'a' * 256).validate(),
        ReceiptConfirmationProblem.merchantNameTooLong,
      );
      expect(input(merchantName: 'a' * 255).validate(), isNull);
      expect(
        input(documentNumber: 'a' * 101).validate(),
        ReceiptConfirmationProblem.documentNumberTooLong,
      );
      expect(input(documentNumber: 'a' * 100).validate(), isNull);
    });

    test('a date below the floor is refused', () {
      expect(
        input(transactionDate: const ReceiptCivilDate(1999, 12, 31)).validate(),
        ReceiptConfirmationProblem.dateTooEarly,
      );
      expect(
        input(transactionDate: const ReceiptCivilDate(2000, 1, 1)).validate(),
        isNull,
      );
    });
  });
}
