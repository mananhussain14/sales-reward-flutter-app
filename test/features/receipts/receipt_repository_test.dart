import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/receipts/data/datasources/receipt_rpc_data_source.dart';
import 'package:sale_reward/features/receipts/data/datasources/submit_receipt_function_client.dart';
import 'package:sale_reward/features/receipts/data/repositories/supabase_receipt_repository.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_product.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_shop.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_submission.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_submission_outcome.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/receipt_fakes.dart';
import 'http_recorder.dart';

/// The data layer's contract with the backend.
///
/// Three properties are asserted over and over, because each is a security
/// boundary rather than a convenience:
///
/// 1. **Three of the four reads take no arguments at all**, so nothing in the
///    client can nominate whose data comes back.
/// 2. **The fourth sends one submission id and nothing beside it.**
/// 3. **A thrown call is classified by SQLSTATE, and an unreadable body is an
///    outage** — never a denial, and never a fabricated empty list.
void main() {
  late int shopCalls;
  late int productCalls;
  late int submissionsCalls;
  late List<String> submissionIds;
  late List<Map<String, Object?>> capturedParams;

  Object? shopBody = shopRows();
  Object? productBody = productRows();
  Object? submissionsBody = <Map<String, Object?>>[submissionRow()];
  Object? submissionBody = <Map<String, Object?>>[submissionRow()];
  Object? thrown;

  ReceiptRpcDataSource buildDataSource() {
    return ReceiptRpcDataSource(
      assignedShops: () async {
        shopCalls++;
        if (thrown != null) throw thrown!;
        return shopBody;
      },
      products: () async {
        productCalls++;
        if (thrown != null) throw thrown!;
        return productBody;
      },
      submissions: () async {
        submissionsCalls++;
        if (thrown != null) throw thrown!;
        return submissionsBody;
      },
      submission: (String id) async {
        submissionIds.add(id);
        capturedParams.add(<String, Object?>{submissionIdParameter: id});
        if (thrown != null) throw thrown!;
        return submissionBody;
      },
    );
  }

  SupabaseReceiptRepository buildRepository({http.Client? client}) {
    return SupabaseReceiptRepository(
      rpc: buildDataSource(),
      functions: SubmitReceiptFunctionClient(
        endpoint: Uri.parse(
          'https://example.supabase.co/functions/v1/submit-receipt',
        ),
        publishableKey: 'sb_publishable_test',
        accessToken: () async => 'test-access-token',
        httpClient: client ?? RecordingHttpClient(),
      ),
    );
  }

  setUp(() {
    shopCalls = 0;
    productCalls = 0;
    submissionsCalls = 0;
    submissionIds = <String>[];
    capturedParams = <Map<String, Object?>>[];
    shopBody = shopRows();
    productBody = productRows();
    submissionsBody = <Map<String, Object?>>[submissionRow()];
    submissionBody = <Map<String, Object?>>[submissionRow()];
    thrown = null;
  });

  group('the RPC contract', () {
    test('the four RPC names are exactly the deployed ones', () {
      expect(listMyAssignedReceiptShopsRpc, 'list_my_assigned_receipt_shops');
      expect(listMyReceiptProductsRpc, 'list_my_receipt_products');
      expect(listMyReceiptSubmissionsRpc, 'list_my_receipt_submissions');
      expect(getMyReceiptSubmissionRpc, 'get_my_receipt_submission');
    });

    test('the three list invokers accept no arguments at all', () {
      // The typedef is the security property: there is no argument to pass, so
      // no user id, organization id, Retailer id, membership id, role code,
      // permission code, email or token can be expressed here.
      const ReceiptListInvoker invoker = _noArguments;
      expect(invoker, isA<Future<Object?> Function()>());
    });

    test(
      'list_my_assigned_receipt_shops is called with zero arguments',
      () async {
        await buildRepository().assignedShops();
        expect(shopCalls, 1);
      },
    );

    test('list_my_receipt_products is called with zero arguments', () async {
      await buildRepository().receiptProducts();
      expect(productCalls, 1);
    });

    test('list_my_receipt_submissions is called with zero arguments', () async {
      await buildRepository().submissions();
      expect(submissionsCalls, 1);
    });

    test('get_my_receipt_submission sends only p_submission_id', () async {
      await buildRepository().submission(submissionUuid);

      expect(submissionIds, <String>[submissionUuid]);
      expect(capturedParams.single.keys, <String>['p_submission_id']);
      expect(capturedParams.single.values, <Object?>[submissionUuid]);
    });

    test(
      'no identity, tenant, role or status parameter is ever sent',
      () async {
        await buildRepository().submission(submissionUuid);

        const List<String> forbidden = <String>[
          'user_id',
          'p_user_id',
          'profile_id',
          'p_profile_id',
          'organization_id',
          'p_organization_id',
          'retailer_id',
          'membership_id',
          'role',
          'role_code',
          'permission',
          'status',
          'storage_bucket',
          'storage_object_path',
          'file_sha256',
          'email',
          'access_token',
          'tenant',
        ];
        for (final String key in forbidden) {
          expect(
            capturedParams.single.containsKey(key),
            isFalse,
            reason: 'the RPC must pass no $key argument',
          );
        }
      },
    );
  });

  group('read classification', () {
    test('a well-formed body parses into domain entities', () async {
      final ReceiptResult<List<ReceiptShop>> shops = await buildRepository()
          .assignedShops();
      final ReceiptResult<List<ReceiptProduct>> products =
          await buildRepository().receiptProducts();

      expect(
        (shops as ReceiptReadSuccess<List<ReceiptShop>>).value.first.shopName,
        'Marina Mall',
      );
      expect(
        (products as ReceiptReadSuccess<List<ReceiptProduct>>).value,
        hasLength(2),
      );
    });

    test('42501 is a denial', () async {
      thrown = const PostgrestException(message: 'refused', code: '42501');

      final ReceiptResult<List<ReceiptShop>> result = await buildRepository()
          .assignedShops();

      expect(
        (result as ReceiptReadFailure<List<ReceiptShop>>).failure,
        isA<DeniedFailure>(),
      );
    });

    test(
      'an arbitrary transport exception is an outage, never a denial',
      () async {
        thrown = StateError('socket closed');

        final ReceiptResult<List<ReceiptShop>> result = await buildRepository()
            .assignedShops();

        final Failure failure =
            (result as ReceiptReadFailure<List<ReceiptShop>>).failure;
        expect(failure, isA<UnavailableFailure>());
        expect(failure, isNot(isA<DeniedFailure>()));
      },
    );

    test(
      'a malformed body is an outage, not a fabricated empty list',
      () async {
        shopBody = <Map<String, Object?>>[
          <String, Object?>{'shop_id': 'not-a-uuid'},
        ];

        final ReceiptResult<List<ReceiptShop>> result = await buildRepository()
            .assignedShops();

        expect(result, isA<ReceiptReadFailure<List<ReceiptShop>>>());
        expect(
          (result as ReceiptReadFailure<List<ReceiptShop>>).failure,
          isA<UnavailableFailure>(),
        );
      },
    );

    test('a body that is not a list at all is an outage', () async {
      productBody = 'unexpected';

      final ReceiptResult<List<ReceiptProduct>> result = await buildRepository()
          .receiptProducts();

      expect(result, isA<ReceiptReadFailure<List<ReceiptProduct>>>());
    });

    test('an empty result is a success, distinct from a denial', () async {
      shopBody = <Object?>[];

      final ReceiptResult<List<ReceiptShop>> result = await buildRepository()
          .assignedShops();

      expect((result as ReceiptReadSuccess<List<ReceiptShop>>).value, isEmpty);
    });

    test('zero rows from the single read is a success carrying null', () async {
      submissionBody = <Object?>[];

      final ReceiptResult<ReceiptSubmission?> result = await buildRepository()
          .submission(submissionUuid);

      expect((result as ReceiptReadSuccess<ReceiptSubmission?>).value, isNull);
    });

    test('a malformed submission id is refused without a round trip', () async {
      final ReceiptResult<ReceiptSubmission?> result = await buildRepository()
          .submission('not-a-uuid');

      expect(submissionIds, isEmpty);
      expect(
        (result as ReceiptReadFailure<ReceiptSubmission?>).failure,
        isA<InvalidFailure>(),
      );
    });
  });

  group('the Edge Function request', () {
    test('sends exactly one shop_id field and one file part', () async {
      final RecordingHttpClient client = RecordingHttpClient();
      await buildRepository(
        client: client,
      ).submitReceipt(shopId: shopAUuid, file: testReceiptFile());

      expect(client.requestCount, 1);
      expect(client.lastMethod, 'POST');
      expect(client.fieldNames(), <String>['shop_id']);
      expect(client.fileFieldNames(), <String>['file']);
      expect(client.fieldValue('shop_id'), shopAUuid);
      expect(client.lastFileName(), 'receipt.png');
    });

    test('the URL is the deployed function and nothing else', () async {
      final RecordingHttpClient client = RecordingHttpClient();
      await buildRepository(
        client: client,
      ).submitReceipt(shopId: shopAUuid, file: testReceiptFile());

      expect(
        client.lastUrl.toString(),
        endsWith('/functions/v1/submit-receipt'),
      );
      expect(client.lastUrl.queryParameters, isEmpty);
    });

    test('authorization is the caller\'s current access token', () async {
      final RecordingHttpClient client = RecordingHttpClient();
      await buildRepository(
        client: client,
      ).submitReceipt(shopId: shopAUuid, file: testReceiptFile());

      expect(client.lastHeaders['Authorization'], 'Bearer test-access-token');
      expect(client.lastHeaders['apikey'], 'sb_publishable_test');
    });

    test(
      'no identity, tenant, role, status, path or key is in the body',
      () async {
        final RecordingHttpClient client = RecordingHttpClient();
        await buildRepository(
          client: client,
        ).submitReceipt(shopId: shopAUuid, file: testReceiptFile());

        const List<String> forbidden = <String>[
          'user_id',
          'profile_id',
          'submitted_by',
          'organization_id',
          'retailer_id',
          'membership_id',
          'role',
          'permission',
          'status',
          'product_id',
          'reward',
          'coin',
          'sha256',
          'file_sha256',
          'hash',
          'bucket',
          'storage_bucket',
          'storage_object_path',
          'object_path',
          'service_role',
          'sb_secret_',
        ];
        for (final String key in forbidden) {
          expect(
            client.lastBodyText.contains(key),
            isFalse,
            reason: 'the multipart body must not carry $key',
          );
        }
        // And nothing privileged in a header either.
        expect(
          client.lastHeaders.keys.map((String k) => k.toLowerCase()),
          <String>['authorization', 'apikey', 'content-type'],
        );
      },
    );

    test('the file bytes travel verbatim', () async {
      final RecordingHttpClient client = RecordingHttpClient();
      await buildRepository(
        client: client,
      ).submitReceipt(shopId: shopAUuid, file: testReceiptFile());

      // The PNG signature must survive: hashing on the server is over the bytes
      // it receives, so any client-side re-encoding would silently defeat the
      // duplicate guard.
      expect(
        client.lastBodyBytes,
        containsAllInOrder(<int>[0x89, 0x50, 0x4e, 0x47]),
      );
    });

    test('a malformed shop id never leaves the device', () async {
      final RecordingHttpClient client = RecordingHttpClient();
      final ReceiptSubmissionOutcome outcome = await buildRepository(
        client: client,
      ).submitReceipt(shopId: 'not-a-uuid', file: testReceiptFile());

      expect(client.requestCount, 0);
      expect(outcome, isA<ReceiptSubmissionRefused>());
    });

    test('no session means no request at all', () async {
      final RecordingHttpClient client = RecordingHttpClient();
      final SubmitReceiptFunctionClient functions = SubmitReceiptFunctionClient(
        endpoint: Uri.parse('https://example.supabase.co/functions/v1/x'),
        publishableKey: 'sb_publishable_test',
        accessToken: () async => null,
        httpClient: client,
      );

      final ReceiptSubmissionOutcome outcome = await functions.submit(
        shopId: shopAUuid,
        file: testReceiptFile(),
      );

      expect(client.requestCount, 0);
      expect(outcome, isA<ReceiptSubmissionUnauthenticated>());
    });

    test('a failing token provider is unauthenticated, not denied', () async {
      final RecordingHttpClient client = RecordingHttpClient();
      final SubmitReceiptFunctionClient functions = SubmitReceiptFunctionClient(
        endpoint: Uri.parse('https://example.supabase.co/functions/v1/x'),
        publishableKey: 'sb_publishable_test',
        accessToken: () async => throw StateError('refresh failed'),
        httpClient: client,
      );

      final ReceiptSubmissionOutcome outcome = await functions.submit(
        shopId: shopAUuid,
        file: testReceiptFile(),
      );

      expect(client.requestCount, 0);
      expect(outcome, isA<ReceiptSubmissionUnauthenticated>());
      expect(outcome, isNot(isA<ReceiptSubmissionDenied>()));
    });

    test('the endpoint is derived from the project URL', () {
      expect(
        SubmitReceiptFunctionClient.endpointFor(
          'https://abc.supabase.co',
        ).toString(),
        'https://abc.supabase.co/functions/v1/submit-receipt',
      );
    });
  });

  group('HTTP response mapping', () {
    Future<ReceiptSubmissionOutcome> respond(
      int status,
      String body, {
      Object? throws,
      Duration? delay,
    }) {
      final RecordingHttpClient client = RecordingHttpClient(
        statusCode: status,
        body: body,
        throws: throws,
        delay: delay,
      );
      return SubmitReceiptFunctionClient(
        endpoint: Uri.parse('https://example.supabase.co/functions/v1/x'),
        publishableKey: 'k',
        accessToken: () async => 't',
        httpClient: client,
        timeout: const Duration(milliseconds: 40),
      ).submit(shopId: shopAUuid, file: testReceiptFile());
    }

    test('200 submitted parses the submission id', () async {
      final ReceiptSubmissionOutcome outcome = await respond(
        200,
        jsonEncode(<String, Object?>{
          'status': 'submitted',
          'submission_id': submissionUuid,
        }),
      );

      expect(
        (outcome as ReceiptSubmissionAccepted).submissionId,
        submissionUuid,
      );
    });

    test('400 carries the reason from the fixed vocabulary', () async {
      final ReceiptSubmissionOutcome outcome = await respond(
        400,
        jsonEncode(<String, Object?>{
          'status': 'invalid',
          'reason': 'too-large',
        }),
      );

      expect(outcome, isA<ReceiptSubmissionRefused>());
    });

    test('401 is unauthenticated', () async {
      expect(
        await respond(401, '{"status":"unauthenticated"}'),
        isA<ReceiptSubmissionUnauthenticated>(),
      );
    });

    test('403 is denied and carries no detail', () async {
      final ReceiptSubmissionOutcome outcome = await respond(
        403,
        '{"status":"denied"}',
      );

      expect(outcome, isA<ReceiptSubmissionDenied>());
      // A denied outcome has no field to hold a reason, so the four
      // indistinguishable backend situations stay indistinguishable.
      expect(outcome.toString(), isNot(contains('shop')));
    });

    test('409 is duplicate', () async {
      expect(
        await respond(409, '{"status":"duplicate"}'),
        isA<ReceiptSubmissionDuplicate>(),
      );
    });

    test('502 is a definite, retryable upload failure', () async {
      expect(
        await respond(502, '{"status":"upload-failed"}'),
        isA<ReceiptSubmissionUploadFailed>(),
      );
    });

    test('503 is unavailable, never a denial', () async {
      final ReceiptSubmissionOutcome outcome = await respond(
        503,
        '{"status":"unavailable"}',
      );

      expect(outcome, isA<ReceiptSubmissionUnavailable>());
      expect(outcome, isNot(isA<ReceiptSubmissionDenied>()));
    });

    test('an unmapped status falls through to unavailable', () async {
      expect(await respond(405, ''), isA<ReceiptSubmissionUnavailable>());
      expect(await respond(418, 'teapot'), isA<ReceiptSubmissionUnavailable>());
    });

    test('a 200 with an unusable body is unconfirmed, not a success', () async {
      // The receipt may well be stored; only the history can settle it, so the
      // client must not claim either outcome.
      expect(
        await respond(200, 'not json'),
        isA<ReceiptSubmissionUnconfirmed>(),
      );
      expect(
        await respond(200, '{"status":"submitted"}'),
        isA<ReceiptSubmissionUnconfirmed>(),
      );
      expect(
        await respond(
          200,
          '{"status":"submitted","submission_id":"not-a-uuid"}',
        ),
        isA<ReceiptSubmissionUnconfirmed>(),
      );
    });

    test(
      'a timeout is unconfirmed, so nothing is resent automatically',
      () async {
        expect(
          await respond(200, '{}', delay: const Duration(milliseconds: 400)),
          isA<ReceiptSubmissionUnconfirmed>(),
        );
      },
    );

    test('a dropped connection is unconfirmed', () async {
      expect(
        await respond(
          200,
          '{}',
          throws: http.ClientException('connection closed'),
        ),
        isA<ReceiptSubmissionUnconfirmed>(),
      );
    });

    test('the mapper is a pure function of status and body', () {
      expect(
        mapSubmitReceiptResponse(statusCode: 409, body: ''),
        isA<ReceiptSubmissionDuplicate>(),
      );
      expect(
        mapSubmitReceiptResponse(statusCode: 502, body: 'garbage'),
        isA<ReceiptSubmissionUploadFailed>(),
      );
    });
  });

  group('storage', () {
    test('the repository exposes no upload path of its own', () async {
      // The Edge Function performs the protected upload; `storage.objects` has
      // RLS with zero policies, so a client-side write cannot work and an
      // attempt to add one would be the first step toward a key on a device.
      // The source-level guard lives in test/security; this is the behavioural
      // half — submitting produces exactly one HTTP request, to the function.
      final RecordingHttpClient client = RecordingHttpClient();
      await buildRepository(
        client: client,
      ).submitReceipt(shopId: shopAUuid, file: testReceiptFile());

      expect(client.requestCount, 1);
      expect(client.lastUrl.path, '/functions/v1/submit-receipt');
    });
  });
}

Future<Object?> _noArguments() async => null;
