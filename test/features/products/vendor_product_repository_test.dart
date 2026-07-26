import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/products/data/datasources/vendor_product_rpc_data_source.dart';
import 'package:sale_reward/features/products/data/repositories/supabase_vendor_product_repository.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assigned_retailer.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_detail.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_status.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_summary.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/vendor_product_fakes.dart';

/// The data layer's contract with the backend.
///
/// Four properties are asserted over and over, because each is a security
/// boundary rather than a convenience:
///
/// 1. **`list_vendor_products()` is called with no arguments at all**, so
///    nothing in the client can nominate whose catalogue comes back.
/// 2. **The two companions send one product id and nothing beside it** — no auth
///    user id, no profile id, no organization or tenant, no Retailer
///    organization id, no product code, no status, no permission code, no page
///    cursor.
/// 3. **A thrown call is classified by SQLSTATE, and an unreadable body is an
///    outage** — never a denial, and never a fabricated empty catalogue or empty
///    assignment list.
/// 4. **A malformed selector never reaches PostgREST**, because a `uuid`
///    parameter would answer `22P02` — a cast error raised *before* the function
///    body runs, and therefore before any authorization check — and an outage
///    wearing that error's clothes would offer a retry that can never succeed.
void main() {
  late int productCalls;
  late List<List<Object?>> productCallArguments;
  late List<Map<String, Object?>> detailParams;
  late List<Map<String, Object?>> assignmentParams;

  Object? productBody = productRows();
  Object? detailBody = <Map<String, Object?>>[productDetailRow()];
  Object? assignmentBody = <Map<String, Object?>>[assignedRetailerRow()];
  Object? thrown;

  setUp(() {
    productCalls = 0;
    productCallArguments = <List<Object?>>[];
    detailParams = <Map<String, Object?>>[];
    assignmentParams = <Map<String, Object?>>[];
    productBody = productRows();
    detailBody = <Map<String, Object?>>[productDetailRow()];
    assignmentBody = <Map<String, Object?>>[assignedRetailerRow()];
    thrown = null;
  });

  SupabaseVendorProductRepository buildRepository() {
    return SupabaseVendorProductRepository(
      rpc: VendorProductRpcDataSource(
        products: () async {
          productCalls++;
          // The invoker takes no parameters, so there is literally nothing to
          // record beyond the fact that it was called with none.
          productCallArguments.add(const <Object?>[]);
          if (thrown != null) throw thrown!;
          return productBody;
        },
        detail: (String productId) async {
          detailParams.add(<String, Object?>{productIdParameter: productId});
          if (thrown != null) throw thrown!;
          return detailBody;
        },
        assignedRetailers: (String productId) async {
          assignmentParams.add(<String, Object?>{
            productIdParameter: productId,
          });
          if (thrown != null) throw thrown!;
          return assignmentBody;
        },
      ),
      writes: unusedVendorProductWrites(),
      assignments: unusedVendorProductAssignments(),
    );
  }

  PostgrestException postgrest(String code) => PostgrestException(
    message: 'backend detail that must not escape',
    code: code,
  );

  group('the RPC contract', () {
    test('list_vendor_products is invoked with zero arguments', () async {
      await buildRepository().products();

      expect(productCalls, 1);
      expect(productCallArguments.single, isEmpty);
    });

    test('get_vendor_product_detail sends only p_product_id', () async {
      await buildRepository().productDetail(espressoProductUuid);

      expect(detailParams, hasLength(1));
      expect(detailParams.single, <String, Object?>{
        'p_product_id': espressoProductUuid,
      });
      expect(detailParams.single.keys, hasLength(1));
    });

    test(
      'list_vendor_product_assigned_retailers sends only p_product_id',
      () async {
        await buildRepository().assignedRetailers(espressoProductUuid);

        expect(assignmentParams, hasLength(1));
        expect(assignmentParams.single, <String, Object?>{
          'p_product_id': espressoProductUuid,
        });
        expect(assignmentParams.single.keys, hasLength(1));
      },
    );

    test('the two companions address the same id space', () async {
      // One selector for both, so the operations cannot drift into two address
      // spaces — and so the detail read is genuinely authoritative about the id
      // the companion was asked for.
      final SupabaseVendorProductRepository repository = buildRepository();
      await repository.productDetail(retiredProductUuid);
      await repository.assignedRetailers(retiredProductUuid);

      expect(
        detailParams.single[productIdParameter],
        assignmentParams.single[productIdParameter],
      );
    });

    test('no identity, tenant, permission or Retailer argument', () async {
      final SupabaseVendorProductRepository repository = buildRepository();
      await repository.products();
      await repository.productDetail(espressoProductUuid);
      await repository.assignedRetailers(espressoProductUuid);

      final Set<String> sent = <String>{
        ...detailParams.expand((Map<String, Object?> p) => p.keys),
        ...assignmentParams.expand((Map<String, Object?> p) => p.keys),
      };

      expect(sent, <String>{'p_product_id'});
      for (final String forbidden in <String>[
        'p_user_id',
        'p_auth_user_id',
        'p_profile_id',
        'p_membership_id',
        'p_organization_id',
        'p_vendor_id',
        'p_vendor_organization_id',
        'p_tenant_id',
        // The Retailer organization id is an OUTPUT only: it names a tenant
        // other Vendors may also manage.
        'p_retailer_organization_id',
        'p_relationship_id',
        'p_product_code',
        'p_barcode',
        'p_status',
        'p_assignment_status',
        'p_role_code',
        'p_permission_code',
        'p_search',
        'p_limit',
        'p_offset',
      ]) {
        expect(sent.contains(forbidden), isFalse, reason: 'sent $forbidden');
      }
    });

    test('the parameter name is the deployed one, exactly', () {
      expect(productIdParameter, 'p_product_id');
    });

    test('only the three deployed functions are named', () {
      expect(listVendorProductsRpc, 'list_vendor_products');
      expect(getVendorProductDetailRpc, 'get_vendor_product_detail');
      expect(
        listVendorProductAssignedRetailersRpc,
        'list_vendor_product_assigned_retailers',
      );
    });

    test('the shipped editor matrix read is never named', () {
      // list_vendor_product_retailer_assignments() requires the permission to
      // CHANGE assignments, returns every managed Retailer including
      // never-assigned ones, and carries no relationship id. It is the web's,
      // and this client must not call it.
      final String source = File(
        'lib/features/products/data/datasources/'
        'vendor_product_rpc_data_source.dart',
      ).readAsStringSync();

      expect(
        source.contains('list_vendor_product_retailer_assignments'),
        isFalse,
      );
    });

    test('no write RPC is reachable from the data source', () {
      // The interface has three methods and all three are reads. This asserts
      // the *source* has no write name in it, which is what a future edit would
      // have to add.
      final String source = File(
        'lib/features/products/data/datasources/'
        'vendor_product_rpc_data_source.dart',
      ).readAsStringSync();

      for (final String forbidden in <String>[
        'create_vendor_product',
        'update_vendor_product',
        'delete_vendor_product',
        'set_vendor_product_status',
        'assign_vendor_product_to_retailer',
        'unassign_vendor_product_from_retailer',
      ]) {
        expect(source.contains(forbidden), isFalse, reason: 'names $forbidden');
      }
    });

    test('no storage or signed-URL call exists in the data layer', () {
      // No product image exists anywhere in the product — no column, no bucket,
      // no rendering — so there is nothing to fetch and nothing to sign.
      for (final String path in <String>[
        'lib/features/products/data/datasources/'
            'vendor_product_rpc_data_source.dart',
        'lib/features/products/data/repositories/'
            'supabase_vendor_product_repository.dart',
      ]) {
        final String source = File(path).readAsStringSync();
        for (final String forbidden in <String>[
          'storage.from(',
          'createSignedUrl',
          'getPublicUrl',
          'uploadBinary(',
        ]) {
          expect(
            source.contains(forbidden),
            isFalse,
            reason: '$path performs $forbidden',
          );
        }
      }
    });

    test('no table is read directly', () {
      // Both product tables have RLS enabled with ZERO policies and no
      // privilege for `authenticated`, so a direct read would not merely be
      // poor layering — it would not work.
      final String source = File(
        'lib/features/products/data/repositories/'
        'supabase_vendor_product_repository.dart',
      ).readAsStringSync();

      for (final String forbidden in <String>[
        '.from(',
        '.select(',
        '.eq(',
        '.maybeSingle(',
      ]) {
        expect(source.contains(forbidden), isFalse, reason: 'uses $forbidden');
      }
    });
  });

  group('the catalogue read', () {
    test('a successful body becomes parsed rows, in backend order', () async {
      final ReadResult<List<VendorProductSummary>> result =
          await buildRepository().products();

      expect(result, isA<ReadSuccess<List<VendorProductSummary>>>());
      final List<VendorProductSummary> rows =
          (result as ReadSuccess<List<VendorProductSummary>>).value;
      expect(rows, hasLength(2));
      expect(rows.first.productCode, 'ESP-1000');
      expect(rows.last.productCode, 'DEC-2000');
    });

    test('an empty catalogue is a success carrying an empty list', () async {
      // A Vendor with no products is a real, reachable state.
      productBody = const <Object?>[];

      final ReadResult<List<VendorProductSummary>> result =
          await buildRepository().products();

      expect(
        (result as ReadSuccess<List<VendorProductSummary>>).value,
        isEmpty,
      );
    });

    test('42501 becomes a denial', () async {
      thrown = postgrest('42501');

      final ReadResult<List<VendorProductSummary>> result =
          await buildRepository().products();

      expect(
        (result as ReadFailure<List<VendorProductSummary>>).failure,
        isA<DeniedFailure>(),
      );
    });

    test('a transport failure is an outage, never a denial', () async {
      thrown = const SocketException('no route to host');

      final ReadResult<List<VendorProductSummary>> result =
          await buildRepository().products();

      final Failure failure =
          (result as ReadFailure<List<VendorProductSummary>>).failure;
      expect(failure, isA<UnavailableFailure>());
      expect(failure, isNot(isA<DeniedFailure>()));
    });

    test('an unreadable body is an outage, never an empty catalogue', () async {
      // Fabricating an empty list would tell a Vendor they have no products
      // when the response simply could not be understood.
      productBody = <Map<String, Object?>>[productRow(productName: null)];

      final ReadResult<List<VendorProductSummary>> result =
          await buildRepository().products();

      expect(result, isA<ReadFailure<List<VendorProductSummary>>>());
      expect(
        (result as ReadFailure<List<VendorProductSummary>>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('the backend message never escapes into the failure', () async {
      thrown = postgrest('42501');

      final ReadResult<List<VendorProductSummary>> result =
          await buildRepository().products();

      expect(
        (result as ReadFailure<List<VendorProductSummary>>).failure.props,
        isEmpty,
      );
    });

    test('counts arrive on the row and are never a second read', () async {
      // A per-product assignment query would be N+1 over work the backend
      // already did, and a second place for the counting rule to be got wrong.
      final ReadResult<List<VendorProductSummary>> result =
          await buildRepository().products();
      final List<VendorProductSummary> rows =
          (result as ReadSuccess<List<VendorProductSummary>>).value;

      expect(rows.first.activeAssignmentCount, 2);
      expect(productCalls, 1);
      expect(detailParams, isEmpty);
      expect(assignmentParams, isEmpty);
    });
  });

  group('the detail read', () {
    test('one row becomes a detail, with both counts', () async {
      final ReadResult<VendorProductDetail?> result = await buildRepository()
          .productDetail(espressoProductUuid);

      final VendorProductDetail? detail =
          (result as ReadSuccess<VendorProductDetail?>).value;
      expect(detail!.productName, 'Espresso Blend 1kg');
      expect(detail.status, VendorProductStatus.active);
      expect(detail.assignmentCount, 3);
      expect(detail.activeAssignmentCount, 2);
    });

    test('zero rows is a success carrying null', () async {
      detailBody = const <Object?>[];

      final ReadResult<VendorProductDetail?> result = await buildRepository()
          .productDetail(unknownProductUuid);

      expect(result, isA<ReadSuccess<VendorProductDetail?>>());
      expect((result as ReadSuccess<VendorProductDetail?>).value, isNull);
    });

    test('a malformed id answers null without calling the RPC', () async {
      final ReadResult<VendorProductDetail?> result = await buildRepository()
          .productDetail('not-a-uuid');

      expect(detailParams, isEmpty);
      expect((result as ReadSuccess<VendorProductDetail?>).value, isNull);
    });

    test('an empty id answers null without calling the RPC', () async {
      // What a route with a missing segment produces.
      final ReadResult<VendorProductDetail?> result = await buildRepository()
          .productDetail('');

      expect(detailParams, isEmpty);
      expect((result as ReadSuccess<VendorProductDetail?>).value, isNull);
    });

    test(
      'a product code is not a selector and never reaches the RPC',
      () async {
        // The code is unique per Vendor, not globally, so it could not name one
        // row without a tenant beside it — which is the input this contract
        // refuses.
        final ReadResult<VendorProductDetail?> result = await buildRepository()
            .productDetail('ESP-1000');

        expect(detailParams, isEmpty);
        expect((result as ReadSuccess<VendorProductDetail?>).value, isNull);
      },
    );

    test('a well-formed unknown id DOES reach the RPC', () async {
      // A valid uuid is a legitimate question, so it is asked; its zero-row
      // answer maps to the same null.
      detailBody = const <Object?>[];

      await buildRepository().productDetail(unknownProductUuid);

      expect(detailParams, hasLength(1));
    });

    test('42501 becomes a denial rather than a null', () async {
      thrown = postgrest('42501');

      final ReadResult<VendorProductDetail?> result = await buildRepository()
          .productDetail(espressoProductUuid);

      expect(
        (result as ReadFailure<VendorProductDetail?>).failure,
        isA<DeniedFailure>(),
      );
    });

    test('an unreadable body is an outage, never a null', () async {
      // Null means "not addressable"; unreadable is a different event, and
      // conflating them would show the wrong screen and withhold the retry.
      detailBody = <Map<String, Object?>>[
        productDetailRow(assignmentCount: -3),
      ];

      final ReadResult<VendorProductDetail?> result = await buildRepository()
          .productDetail(espressoProductUuid);

      expect(
        (result as ReadFailure<VendorProductDetail?>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test(
      'an impossible count pair is an outage, never a rendered row',
      () async {
        detailBody = <Map<String, Object?>>[
          productDetailRow(assignmentCount: 1, activeAssignmentCount: 9),
        ];

        final ReadResult<VendorProductDetail?> result = await buildRepository()
            .productDetail(espressoProductUuid);

        expect(
          (result as ReadFailure<VendorProductDetail?>).failure,
          isA<UnavailableFailure>(),
        );
      },
    );
  });

  group('the assignment companion', () {
    test('a successful body becomes parsed rows', () async {
      final ReadResult<List<VendorProductAssignedRetailer>> result =
          await buildRepository().assignedRetailers(espressoProductUuid);

      final List<VendorProductAssignedRetailer> rows =
          (result as ReadSuccess<List<VendorProductAssignedRetailer>>).value;
      expect(rows.single.retailerName, 'Northwind Retail');
      expect(rows.single.relationshipId, northwindRelationshipId);
    });

    test('an empty list is a success, not a failure', () async {
      assignmentBody = const <Object?>[];

      final ReadResult<List<VendorProductAssignedRetailer>> result =
          await buildRepository().assignedRetailers(unassignedProductUuid);

      expect(
        (result as ReadSuccess<List<VendorProductAssignedRetailer>>).value,
        isEmpty,
      );
    });

    test('a null-relationship row survives the whole layer', () async {
      assignmentBody = <Map<String, Object?>>[
        assignedRetailerRow(relationshipId: null, relationshipStatus: null),
      ];

      final ReadResult<List<VendorProductAssignedRetailer>> result =
          await buildRepository().assignedRetailers(espressoProductUuid);

      final List<VendorProductAssignedRetailer> rows =
          (result as ReadSuccess<List<VendorProductAssignedRetailer>>).value;
      expect(rows, hasLength(1));
      expect(rows.single.relationshipId, isNull);
      expect(rows.single.isCrossLinkable, isFalse);
      expect(rows.single.retailerName, 'Northwind Retail');
    });

    test('a malformed id never reaches the RPC', () async {
      // Defence in depth: the cubit never calls this for an id the detail read
      // could not resolve, but the rule holds at the boundary regardless.
      final ReadResult<List<VendorProductAssignedRetailer>> result =
          await buildRepository().assignedRetailers('not-a-uuid');

      expect(assignmentParams, isEmpty);
      expect(
        (result as ReadSuccess<List<VendorProductAssignedRetailer>>).value,
        isEmpty,
      );
    });

    test('42501 becomes a denial', () async {
      // The same generic denial whether the caller lacks PRODUCTS_READ or
      // RETAILERS_READ. The split is enforced in SQL and is invisible here.
      thrown = postgrest('42501');

      final ReadResult<List<VendorProductAssignedRetailer>> result =
          await buildRepository().assignedRetailers(espressoProductUuid);

      final Failure failure =
          (result as ReadFailure<List<VendorProductAssignedRetailer>>).failure;
      expect(failure, isA<DeniedFailure>());
      // And it carries nothing: no permission code, no hint at which of the two
      // this caller was missing.
      expect(failure.props, isEmpty);
    });

    test('a transport failure is retryable, not a denial', () async {
      thrown = const SocketException('reset by peer');

      final ReadResult<List<VendorProductAssignedRetailer>> result =
          await buildRepository().assignedRetailers(espressoProductUuid);

      expect(
        (result as ReadFailure<List<VendorProductAssignedRetailer>>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test(
      'an unreadable body is an outage, never an empty assignment list',
      () async {
        // An empty list here means "this product has never been assigned to
        // anybody" — a claim that must never be manufactured from a body that
        // could not be read.
        assignmentBody = <Map<String, Object?>>[
          assignedRetailerRow(assignmentStatus: null),
        ];

        final ReadResult<List<VendorProductAssignedRetailer>> result =
            await buildRepository().assignedRetailers(espressoProductUuid);

        expect(result, isA<ReadFailure<List<VendorProductAssignedRetailer>>>());
        expect(
          (result as ReadFailure<List<VendorProductAssignedRetailer>>).failure,
          isA<UnavailableFailure>(),
        );
      },
    );
  });

  group('no service-role key and no privileged transport', () {
    test('neither data-layer file names a privileged credential', () {
      for (final String path in <String>[
        'lib/features/products/data/datasources/'
            'vendor_product_rpc_data_source.dart',
        'lib/features/products/data/repositories/'
            'supabase_vendor_product_repository.dart',
        'lib/features/products/data/models/vendor_product_parsers.dart',
      ]) {
        final String source = File(path).readAsStringSync();
        for (final String forbidden in <String>[
          'SUPABASE_SERVICE_ROLE_KEY',
          'service_role',
          'serviceRoleKey',
          'sb_secret_',
          'String.fromEnvironment',
        ]) {
          expect(
            source.contains(forbidden),
            isFalse,
            reason: '$path names $forbidden',
          );
        }
      }
    });

    test('the repository reaches only the three RPC invokers', () async {
      final SupabaseVendorProductRepository repository = buildRepository();
      await repository.products();
      await repository.productDetail(espressoProductUuid);
      await repository.assignedRetailers(espressoProductUuid);

      expect(productCalls, 1);
      expect(detailParams, hasLength(1));
      expect(assignmentParams, hasLength(1));
    });
  });
}
