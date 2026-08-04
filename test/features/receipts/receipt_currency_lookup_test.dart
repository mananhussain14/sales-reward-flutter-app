import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/receipts/data/datasources/receipt_extraction_function_client.dart';
import 'package:sale_reward/features/receipts/data/datasources/receipt_extraction_rpc_data_source.dart';
import 'package:sale_reward/features/receipts/data/repositories/supabase_receipt_extraction_repository.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_currency_minor_unit.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_problem.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_extraction_result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/receipt_extraction_fakes.dart';

/// The authoritative currency-width lookup, end to end through the data layer.
///
/// This is the call that replaced a hard-coded two. Three properties are
/// asserted repeatedly, because each is the reason it exists:
///
/// 1. **It names one function and passes one parameter.** No table is read, no
///    list is fetched, and nothing beside the code travels.
/// 2. **Zero rows is `null`, and `null` means unsupported.** Never a width,
///    never a default, never an error.
/// 3. **An answer this build cannot read is a refusal.** A malformed row and a
///    second row are both `ExtractionMalformedResponseProblem`, because taking
///    one of two candidate widths is precisely the silent mis-scaling the whole
///    correction removes.
void main() {
  late List<String> currencyCodes;
  late Object? rpcResult;
  late Object? rpcThrows;

  SupabaseReceiptExtractionRepository buildRepository() {
    return SupabaseReceiptExtractionRepository(
      functions: ReceiptExtractionFunctionClient(
        invoke: (String name, Map<String, Object?> body) async =>
            const ReceiptExtractionReply(status: 200, body: null),
      ),
      rpc: ReceiptExtractionRpcDataSource(
        lineItems: (String id) async => rpcResult,
        confirmation: (String id) async => rpcResult,
        currencyMinorUnit: (String code) async {
          currencyCodes.add(code);
          if (rpcThrows != null) throw rpcThrows!;
          return rpcResult;
        },
        confirm: (Map<String, Object?> params) async => rpcResult,
        confirmWithProducts: (Map<String, Object?> params) async => rpcResult,
        productProposal: (String id) async => rpcResult,
      ),
    );
  }

  Future<ReceiptCurrencyMinorUnit?> resolve(String code) async {
    final ReceiptExtractionResult<ReceiptCurrencyMinorUnit?> result =
        await buildRepository().currencyMinorUnit(code);
    return (result as ReceiptExtractionSuccess<ReceiptCurrencyMinorUnit?>)
        .value;
  }

  Future<ReceiptExtractionProblem> refuse(String code) async {
    final ReceiptExtractionResult<ReceiptCurrencyMinorUnit?> result =
        await buildRepository().currencyMinorUnit(code);
    return (result as ReceiptExtractionFailed<ReceiptCurrencyMinorUnit?>)
        .problem;
  }

  setUp(() {
    currencyCodes = <String>[];
    rpcResult = <Object?>[];
    rpcThrows = null;
  });

  group('the call itself', () {
    test('names exactly one RPC, and it is the lookup', () {
      expect(getReceiptCurrencyMinorUnitRpc, 'get_receipt_currency_minor_unit');
    });

    test('passes exactly one parameter, and it is the code', () {
      expect(currencyMinorUnitCodeParameter, 'p_currency_code');
    });

    test('sends the normalized code and nothing beside it', () async {
      rpcResult = <Map<String, Object?>>[currencyMinorUnitRow('EUR', 2)];

      await resolve('  eur ');

      // The same normalization the function applies to its own argument, so the
      // two can never disagree about which code an input names.
      expect(currencyCodes, <String>['EUR']);
    });
  });

  group('the four widths the seeded list holds', () {
    test('EUR is two', () async {
      rpcResult = <Map<String, Object?>>[currencyMinorUnitRow('EUR', 2)];
      expect((await resolve('EUR'))!.minorUnit, 2);
    });

    test('JPY is zero', () async {
      rpcResult = <Map<String, Object?>>[currencyMinorUnitRow('JPY', 0)];
      expect((await resolve('JPY'))!.minorUnit, 0);
    });

    test('KWD is three', () async {
      rpcResult = <Map<String, Object?>>[currencyMinorUnitRow('KWD', 3)];
      expect((await resolve('KWD'))!.minorUnit, 3);
    });

    test('CLF is four', () async {
      rpcResult = <Map<String, Object?>>[currencyMinorUnitRow('CLF', 4)];
      expect((await resolve('CLF'))!.minorUnit, 4);
    });

    test('the returned code comes back normalized', () async {
      rpcResult = <Map<String, Object?>>[currencyMinorUnitRow(' jpy ', 0)];

      final ReceiptCurrencyMinorUnit? resolved = await resolve('JPY');

      // The width is bound to a code, and a caller compares that code to what
      // is typed. A stray space would break the comparison and take the width
      // with it.
      expect(resolved!.currencyCode, 'JPY');
    });
  });

  group('unsupported is zero rows, and zero rows is null', () {
    test('an unknown code resolves to null, never to a width', () async {
      rpcResult = <Object?>[];

      expect(await resolve('ZZZ'), isNull);
    });

    test('a code that is not three letters never leaves the device', () async {
      expect(await resolve(''), isNull);
      expect(await resolve('   '), isNull);
      expect(await resolve('EU'), isNull);
      expect(await resolve('EURO'), isNull);
      expect(await resolve('E1R'), isNull);

      // The backend answers a blank code with zero rows too, so this is the
      // same answer without the round trip — not a membership rule of its own.
      expect(currencyCodes, isEmpty);
    });

    test('unsupported is not an error and carries no problem', () async {
      rpcResult = <Object?>[];

      final ReceiptExtractionResult<ReceiptCurrencyMinorUnit?> result =
          await buildRepository().currencyMinorUnit('ZZZ');

      expect(
        result,
        isA<ReceiptExtractionSuccess<ReceiptCurrencyMinorUnit?>>(),
      );
    });
  });

  group('an unreadable answer is refused, never guessed at', () {
    test('a row missing its width is malformed', () async {
      rpcResult = <Map<String, Object?>>[
        <String, Object?>{'currency_code': 'EUR'},
      ];

      expect(await refuse('EUR'), const ExtractionMalformedResponseProblem());
    });

    test('a row missing its code is malformed', () async {
      rpcResult = <Map<String, Object?>>[
        <String, Object?>{'minor_unit': 2},
      ];

      expect(await refuse('EUR'), const ExtractionMalformedResponseProblem());
    });

    test(
      'a width outside the range the backend can report is malformed',
      () async {
        rpcResult = <Map<String, Object?>>[currencyMinorUnitRow('EUR', 9)];

        expect(await refuse('EUR'), const ExtractionMalformedResponseProblem());
      },
    );

    test('a negative width is malformed', () async {
      rpcResult = <Map<String, Object?>>[currencyMinorUnitRow('EUR', -1)];

      expect(await refuse('EUR'), const ExtractionMalformedResponseProblem());
    });

    test('a fractional width is malformed', () async {
      rpcResult = <Map<String, Object?>>[
        <String, Object?>{'currency_code': 'EUR', 'minor_unit': 2.5},
      ];

      expect(await refuse('EUR'), const ExtractionMalformedResponseProblem());
    });

    test('more than one row is malformed, never first-wins', () async {
      rpcResult = <Map<String, Object?>>[
        currencyMinorUnitRow('EUR', 2),
        currencyMinorUnitRow('EUR', 0),
      ];

      // Two candidate widths and a first-wins rule is how an amount silently
      // becomes 100x wrong. The response is simply not this contract's.
      expect(await refuse('EUR'), const ExtractionMalformedResponseProblem());
    });

    test('a body that is not a list is malformed', () async {
      rpcResult = <String, Object?>{'currency_code': 'EUR', 'minor_unit': 2};

      expect(await refuse('EUR'), const ExtractionMalformedResponseProblem());
    });
  });

  group('refusals keep the meanings the rest of the feature gives them', () {
    test('42501 is forbidden, never an unsupported currency', () async {
      rpcThrows = const PostgrestException(message: 'x', code: '42501');

      // A Retailer Owner, a Vendor admin or a suspended profile. Answering
      // "unsupported currency" would tell them to retype a perfectly good code.
      expect(await refuse('EUR'), const ExtractionForbiddenProblem());
    });

    test(
      'a transport fault is the network problem, and is retryable',
      () async {
        rpcThrows = const SocketFault();

        expect(
          await refuse('EUR'),
          const ExtractionServiceUnavailableProblem(),
        );
      },
    );

    test('an expired session is unauthenticated, never forbidden', () async {
      rpcThrows = const AuthException('expired');

      expect(await refuse('EUR'), const ExtractionUnauthenticatedProblem());
    });

    test('no refusal carries backend text', () async {
      rpcThrows = const PostgrestException(
        message: 'permission denied for table iso_currency_codes',
        code: '42501',
      );

      final ReceiptExtractionProblem problem = await refuse('EUR');

      expect(problem.props, isEmpty);
      expect(problem.toString(), isNot(contains('iso_currency_codes')));
    });
  });
}

/// A transport fault that never reached an answer.
class SocketFault implements Exception {
  const SocketFault();
}
