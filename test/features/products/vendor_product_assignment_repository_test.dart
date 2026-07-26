import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/products/data/datasources/vendor_product_assignment_rpc_data_source.dart';
import 'package:sale_reward/features/products/data/datasources/vendor_product_rpc_data_source.dart';
import 'package:sale_reward/features/products/data/repositories/supabase_vendor_product_repository.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assignment_request.dart';
import 'package:sale_reward/features/products/domain/repositories/vendor_product_write_result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/vendor_product_fakes.dart';

/// The assignment write repository, driven over recording invokers.
///
/// These assert what leaves the client — the function name, the exact parameter
/// names, and, just as importantly, the parameters that are **absent** — and how
/// each answer is classified. The invokers stand in for `client.rpc`, so nothing
/// here touches Supabase.
void main() {
  late List<({String rpc, Map<String, Object?> params})> calls;
  Object? thrown;
  Object? voidBody;

  setUp(() {
    calls = <({String rpc, Map<String, Object?> params})>[];
    thrown = null;
    voidBody = null;
  });

  /// A repository whose assignment invokers record the payload verbatim.
  ///
  /// The payload is rebuilt from the *deployed parameter-name constants*, not
  /// from restated literals — so a rename of one of those constants cannot pass
  /// these tests while breaking the real call.
  SupabaseVendorProductRepository buildRepository() {
    return SupabaseVendorProductRepository(
      // An assignment write must issue no read of its own: the canonical
      // re-reads are the detail cubit's, deliberately, so there is one place
      // that decides what a screen shows after a transition.
      rpc: VendorProductRpcDataSource(
        products: () async =>
            throw StateError('an assignment write read the catalogue'),
        detail: (String productId) async =>
            throw StateError('an assignment write read the detail'),
        assignedRetailers: (String productId) async =>
            throw StateError('an assignment write read the assignments'),
      ),
      // And no product-record write either: assigning changes no product row.
      writes: unusedVendorProductWrites(),
      assignments: VendorProductAssignmentRpcDataSource(
        assign:
            ({
              required String productId,
              required String retailerOrganizationId,
            }) async {
              calls.add((
                rpc: assignVendorProductToRetailerRpc,
                params: <String, Object?>{
                  assignmentProductIdParameter: productId,
                  assignmentRetailerParameter: retailerOrganizationId,
                },
              ));
              if (thrown != null) throw thrown!;
              return voidBody;
            },
        withdraw:
            ({
              required String productId,
              required String retailerOrganizationId,
            }) async {
              calls.add((
                rpc: unassignVendorProductFromRetailerRpc,
                params: <String, Object?>{
                  assignmentProductIdParameter: productId,
                  assignmentRetailerParameter: retailerOrganizationId,
                },
              ));
              if (thrown != null) throw thrown!;
              return voidBody;
            },
      ),
    );
  }

  const VendorProductAssignmentRequest request = VendorProductAssignmentRequest(
    productId: espressoProductUuid,
    retailerOrganizationId: northwindOrgId,
  );

  PostgrestException postgrest(String code) => PostgrestException(
    message: 'backend text that must never be rendered',
    code: code,
  );

  group('assign reaches assign_vendor_product_to_retailer', () {
    test('with exactly the two addresses, and nothing else', () async {
      await buildRepository().assignRetailer(request);

      expect(calls.length, 1);
      expect(calls.single.rpc, 'assign_vendor_product_to_retailer');
      expect(calls.single.params, <String, Object?>{
        'p_product_id': espressoProductUuid,
        'p_retailer_organization_id': northwindOrgId,
      });
    });

    test('the payload has exactly two keys', () {
      // Restated as a count so a future third parameter fails here rather than
      // travelling silently.
      buildRepository().assignRetailer(request);
      expect(calls.single.params.keys.length, 2);
    });

    test(
      'no relationship, tenant, actor, status or audit key is sent',
      () async {
        await buildRepository().assignRetailer(request);

        for (final String forbidden in <String>[
          'p_relationship_id',
          'p_vendor_organization_id',
          'p_organization_id',
          'p_tenant_id',
          'p_user_id',
          'p_profile_id',
          'p_membership_id',
          'p_actor_profile_id',
          'p_status',
          'p_assignment_status',
          'p_metadata',
          'p_permission',
          'p_role',
        ]) {
          expect(
            calls.single.params.containsKey(forbidden),
            isFalse,
            reason: 'the assign payload carries $forbidden',
          );
        }
        // And no value that is a relationship id under any key.
        expect(
          calls.single.params.values.contains(northwindRelationshipId),
          isFalse,
        );
      },
    );

    test('an empty body is a plain success', () async {
      final VendorProductWriteResult<void> result = await buildRepository()
          .assignRetailer(request);

      expect(result, isA<VendorProductWriteSuccess<void>>());
    });

    test('an unexpected body is unconfirmed, never a failure', () async {
      // A 2xx means the row and its audit row are committed. Reporting a failure
      // would be false, and it would invite a repeat.
      voidBody = <String, Object?>{'unexpected': true};

      final VendorProductWriteResult<void> result = await buildRepository()
          .assignRetailer(request);

      expect(result, isA<VendorProductWriteUnconfirmed<void>>());
      expect(calls.length, 1, reason: 'an unconfirmed write is never retried');
    });
  });

  group('withdraw reaches unassign_vendor_product_from_retailer', () {
    test('with exactly the same two addresses', () async {
      await buildRepository().withdrawRetailer(request);

      expect(calls.single.rpc, 'unassign_vendor_product_from_retailer');
      expect(calls.single.params, <String, Object?>{
        'p_product_id': espressoProductUuid,
        'p_retailer_organization_id': northwindOrgId,
      });
      expect(calls.single.params.keys.length, 2);
    });

    test('no delete or status argument travels with it', () async {
      await buildRepository().withdrawRetailer(request);

      for (final String forbidden in <String>[
        'p_status',
        'p_delete',
        'p_hard_delete',
        'p_relationship_id',
        'p_assignment_id',
      ]) {
        expect(calls.single.params.containsKey(forbidden), isFalse);
      }
    });

    test('an unexpected body is unconfirmed, and is not repeated', () async {
      voidBody = <Object?>['something'];

      final VendorProductWriteResult<void> result = await buildRepository()
          .withdrawRetailer(request);

      expect(result, isA<VendorProductWriteUnconfirmed<void>>());
      expect(calls.length, 1);
    });
  });

  group('a malformed address never reaches PostgREST', () {
    test('a malformed product id is refused locally, as a denial', () async {
      final VendorProductWriteResult<void> result = await buildRepository()
          .assignRetailer(
            const VendorProductAssignmentRequest(
              productId: 'not-a-uuid',
              retailerOrganizationId: northwindOrgId,
            ),
          );

      expect(calls, isEmpty);
      expect(
        result,
        isA<VendorProductWriteFailure<void>>().having(
          (VendorProductWriteFailure<void> f) => f.failure,
          'failure',
          // Byte-identical to what the backend answers for an id naming no
          // product, an id belonging to another Vendor, and a null id.
          const DeniedFailure(),
        ),
      );
    });

    test('a malformed Retailer id is refused locally too', () async {
      final VendorProductWriteResult<void> result = await buildRepository()
          .withdrawRetailer(
            const VendorProductAssignmentRequest(
              productId: espressoProductUuid,
              retailerOrganizationId: 'Northwind Retail',
            ),
          );

      expect(calls, isEmpty);
      expect(result, isA<VendorProductWriteFailure<void>>());
    });
  });

  group('refusals are classified by SQLSTATE alone', () {
    test('42501 is one generic denial for both functions', () async {
      thrown = postgrest('42501');

      for (final Future<VendorProductWriteResult<void>> Function() call
          in <Future<VendorProductWriteResult<void>> Function()>[
            () => buildRepository().assignRetailer(request),
            () => buildRepository().withdrawRetailer(request),
          ]) {
        final VendorProductWriteResult<void> result = await call();
        expect(
          result,
          isA<VendorProductWriteFailure<void>>().having(
            (VendorProductWriteFailure<void> f) => f.failure,
            'failure',
            const DeniedFailure(),
          ),
        );
      }
    });

    test('55000 — an ineligible product — is its own outcome', () async {
      thrown = postgrest('55000');

      final VendorProductWriteResult<void> result = await buildRepository()
          .assignRetailer(request);

      expect(
        result,
        isA<VendorProductWriteFailure<void>>().having(
          (VendorProductWriteFailure<void> f) => f.failure,
          'failure',
          const NotReadyFailure(),
        ),
      );
    });

    test(
      '23505 — the uniqueness race — is a duplicate, not a denial',
      () async {
        thrown = postgrest('23505');

        final VendorProductWriteResult<void> result = await buildRepository()
            .assignRetailer(request);

        expect(
          result,
          isA<VendorProductWriteFailure<void>>().having(
            (VendorProductWriteFailure<void> f) => f.failure,
            'failure',
            const DuplicateFailure(),
          ),
        );
      },
    );

    test('a duplicate carries NO field hint on this path', () async {
      // The product-record writes attribute a duplicate to a code or a barcode
      // by matching two fixed message literals. These functions accept no text
      // input at all, so there is nothing to attribute and no message is read.
      thrown = postgrest('23505');

      final VendorProductWriteResult<void> result = await buildRepository()
          .assignRetailer(request);

      expect(
        ((result as VendorProductWriteFailure<void>).failure
                as DuplicateFailure)
            .field,
        isNull,
      );
    });

    test('an expired session is unauthenticated, not denied', () async {
      thrown = const AuthException('token expired');

      final VendorProductWriteResult<void> result = await buildRepository()
          .withdrawRetailer(request);

      expect(
        result,
        isA<VendorProductWriteFailure<void>>().having(
          (VendorProductWriteFailure<void> f) => f.failure,
          'failure',
          const UnauthenticatedFailure(),
        ),
      );
    });

    test('a transport fault is unavailable, never a denial', () async {
      thrown = Exception('connection reset');

      final VendorProductWriteResult<void> result = await buildRepository()
          .assignRetailer(request);

      expect(
        result,
        isA<VendorProductWriteFailure<void>>().having(
          (VendorProductWriteFailure<void> f) => f.failure,
          'failure',
          const UnavailableFailure(),
        ),
      );
    });

    test('an unrecognised SQLSTATE falls closed to unavailable', () async {
      thrown = postgrest('XX000');

      final VendorProductWriteResult<void> result = await buildRepository()
          .withdrawRetailer(request);

      expect(
        result,
        isA<VendorProductWriteFailure<void>>().having(
          (VendorProductWriteFailure<void> f) => f.failure,
          'failure',
          const UnavailableFailure(),
        ),
      );
    });

    test('no backend message survives classification', () async {
      thrown = postgrest('42501');

      final VendorProductWriteResult<void> result = await buildRepository()
          .assignRetailer(request);

      // A Failure is a discriminant. `DeniedFailure` has no fields at all, so
      // there is nowhere for a Postgres message, table name, constraint name or
      // SQLSTATE to travel.
      final Failure failure =
          (result as VendorProductWriteFailure<void>).failure;
      expect(failure.props, isEmpty);
      expect(failure.toString().contains('backend text'), isFalse);
    });
  });

  group('the two functions never substitute for one another', () {
    test('assigning calls only the assign invoker', () async {
      await buildRepository().assignRetailer(request);

      expect(
        calls.map((({String rpc, Map<String, Object?> params}) c) => c.rpc),
        <String>['assign_vendor_product_to_retailer'],
      );
    });

    test('withdrawing calls only the withdraw invoker', () async {
      await buildRepository().withdrawRetailer(request);

      expect(
        calls.map((({String rpc, Map<String, Object?> params}) c) => c.rpc),
        <String>['unassign_vendor_product_from_retailer'],
      );
    });

    test(
      'one write is one call — there is no read-back and no retry',
      () async {
        final SupabaseVendorProductRepository repository = buildRepository();
        await repository.assignRetailer(request);
        await repository.withdrawRetailer(request);

        expect(calls.length, 2);
      },
    );
  });
}
