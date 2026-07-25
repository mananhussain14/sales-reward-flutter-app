import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/retailers/data/datasources/vendor_retailer_rpc_data_source.dart';
import 'package:sale_reward/features/retailers/data/repositories/supabase_vendor_retailer_repository.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_detail.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_shop.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_summary.dart';
import 'package:sale_reward/features/retailers/domain/repositories/vendor_retailer_result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/vendor_retailer_fakes.dart';

/// The data layer's contract with the backend.
///
/// Three properties are asserted over and over, because each is a security
/// boundary rather than a convenience:
///
/// 1. **`list_vendor_retailers()` is called with no arguments at all**, so
///    nothing in the client can nominate whose directory comes back.
/// 2. **The other two send one relationship id and nothing beside it** — no
///    identity, no Vendor organization, no role, no tenant, no permission.
/// 3. **A thrown call is classified by SQLSTATE, and an unreadable body is an
///    outage** — never a denial, and never a fabricated empty list.
void main() {
  late int retailerCalls;
  late List<List<Object?>> retailerCallArguments;
  late List<Map<String, Object?>> detailParams;
  late List<Map<String, Object?>> shopParams;

  Object? retailerBody = retailerRows();
  Object? detailBody = <Map<String, Object?>>[detailRow()];
  Object? shopBody = shopRows();
  Object? thrown;

  setUp(() {
    retailerCalls = 0;
    retailerCallArguments = <List<Object?>>[];
    detailParams = <Map<String, Object?>>[];
    shopParams = <Map<String, Object?>>[];
    retailerBody = retailerRows();
    detailBody = <Map<String, Object?>>[detailRow()];
    shopBody = shopRows();
    thrown = null;
  });

  SupabaseVendorRetailerRepository buildRepository() {
    return SupabaseVendorRetailerRepository(
      rpc: VendorRetailerRpcDataSource(
        retailers: () async {
          retailerCalls++;
          // The invoker takes no parameters, so there is literally nothing to
          // record beyond the fact that it was called with none.
          retailerCallArguments.add(const <Object?>[]);
          if (thrown != null) throw thrown!;
          return retailerBody;
        },
        detail: (String relationshipId) async {
          detailParams.add(<String, Object?>{
            relationshipIdParameter: relationshipId,
          });
          if (thrown != null) throw thrown!;
          return detailBody;
        },
        shops: (String relationshipId) async {
          shopParams.add(<String, Object?>{
            relationshipIdParameter: relationshipId,
          });
          if (thrown != null) throw thrown!;
          return shopBody;
        },
      ),
    );
  }

  PostgrestException postgrest(String code) => PostgrestException(
    message: 'backend detail that must not escape',
    code: code,
  );

  group('the RPC contract', () {
    test('list_vendor_retailers is invoked with zero arguments', () async {
      await buildRepository().retailers();

      expect(retailerCalls, 1);
      expect(retailerCallArguments.single, isEmpty);
    });

    test('get_vendor_retailer_detail sends only p_relationship_id', () async {
      await buildRepository().retailerDetail(northwindRelationshipUuid);

      expect(detailParams, hasLength(1));
      expect(detailParams.single.keys, <String>[relationshipIdParameter]);
      expect(
        detailParams.single[relationshipIdParameter],
        northwindRelationshipUuid,
      );
    });

    test('list_vendor_retailer_shops sends only p_relationship_id', () async {
      await buildRepository().retailerShops(northwindRelationshipUuid);

      expect(shopParams, hasLength(1));
      expect(shopParams.single.keys, <String>[relationshipIdParameter]);
      expect(
        shopParams.single[relationshipIdParameter],
        northwindRelationshipUuid,
      );
    });

    test('p_relationship_id is the only parameter name in the data source', () {
      // The typedefs make an extra argument unrepresentable; this pins the
      // literal too, so a future edit that adds a params map is visible here.
      expect(relationshipIdParameter, 'p_relationship_id');
    });

    test('the three RPC names are the deployed ones, spelled once each', () {
      expect(listVendorRetailersRpc, 'list_vendor_retailers');
      expect(getVendorRetailerDetailRpc, 'get_vendor_retailer_detail');
      expect(listVendorRetailerShopsRpc, 'list_vendor_retailer_shops');
    });

    test('a Retailer organization id is never sent, only received', () async {
      // The list returns it; the detail read is addressed by the *relationship*
      // id, which is the narrower selector.
      final VendorRetailerResult<List<VendorRetailerSummary>> listed =
          await buildRepository().retailers();
      final VendorRetailerSummary first =
          (listed as VendorRetailerReadSuccess<List<VendorRetailerSummary>>)
              .value
              .first;

      expect(first.retailerOrganizationId, northwindOrganizationUuid);

      await buildRepository().retailerDetail(first.relationshipId);
      expect(
        detailParams.single[relationshipIdParameter],
        isNot(northwindOrganizationUuid),
      );
      expect(
        detailParams.single[relationshipIdParameter],
        northwindRelationshipUuid,
      );
    });
  });

  group('successful reads', () {
    test('the list maps into entities in the backend order', () async {
      final VendorRetailerResult<List<VendorRetailerSummary>> result =
          await buildRepository().retailers();

      expect(
        result,
        isA<VendorRetailerReadSuccess<List<VendorRetailerSummary>>>(),
      );
      final List<VendorRetailerSummary> value =
          (result as VendorRetailerReadSuccess<List<VendorRetailerSummary>>)
              .value;
      expect(value.map((VendorRetailerSummary r) => r.retailerName), <String>[
        'Northwind Retail',
        'Contoso Stores',
      ]);
    });

    test('an empty list is a success, not a failure', () async {
      retailerBody = const <Object?>[];

      final VendorRetailerResult<List<VendorRetailerSummary>> result =
          await buildRepository().retailers();

      expect(
        (result as VendorRetailerReadSuccess<List<VendorRetailerSummary>>)
            .value,
        isEmpty,
      );
    });

    test('the detail maps into one entity', () async {
      final VendorRetailerResult<VendorRetailerDetail?> result =
          await buildRepository().retailerDetail(northwindRelationshipUuid);

      final VendorRetailerDetail? value =
          (result as VendorRetailerReadSuccess<VendorRetailerDetail?>).value;
      expect(value!.retailerName, 'Northwind Retail');
      expect(value.countryCode, 'AE');
      expect(value.defaultCurrency, 'AED');
    });

    test('zero detail rows is a success carrying null', () async {
      // Not a failure: the backend answered, and its answer is "no row you may
      // read". Mapping it to a failure would let the UI word it as an outage.
      detailBody = const <Object?>[];

      final VendorRetailerResult<VendorRetailerDetail?> result =
          await buildRepository().retailerDetail(foreignRelationshipUuid);

      expect(result, isA<VendorRetailerReadSuccess<VendorRetailerDetail?>>());
      expect(
        (result as VendorRetailerReadSuccess<VendorRetailerDetail?>).value,
        isNull,
      );
    });

    test('an empty shop list is a success', () async {
      shopBody = const <Object?>[];

      final VendorRetailerResult<List<VendorRetailerShop>> result =
          await buildRepository().retailerShops(northwindRelationshipUuid);

      expect(
        (result as VendorRetailerReadSuccess<List<VendorRetailerShop>>).value,
        isEmpty,
      );
    });
  });

  group('a malformed id never reaches the backend', () {
    test('the detail read answers null without calling the RPC', () async {
      final VendorRetailerResult<VendorRetailerDetail?> result =
          await buildRepository().retailerDetail('not-a-uuid');

      expect(detailParams, isEmpty);
      expect(
        (result as VendorRetailerReadSuccess<VendorRetailerDetail?>).value,
        isNull,
      );
    });

    test('an empty id is the same answer, and is indistinguishable', () async {
      final VendorRetailerResult<VendorRetailerDetail?> malformed =
          await buildRepository().retailerDetail('');
      detailBody = const <Object?>[];
      final VendorRetailerResult<VendorRetailerDetail?> foreign =
          await buildRepository().retailerDetail(foreignRelationshipUuid);

      expect(
        (malformed as VendorRetailerReadSuccess<VendorRetailerDetail?>).value,
        isNull,
      );
      expect(
        (foreign as VendorRetailerReadSuccess<VendorRetailerDetail?>).value,
        isNull,
      );
    });

    test('the shop read refuses rather than reporting "no shops"', () async {
      // Unreachable in the shipped flow, and deliberately not an empty list: an
      // empty list means "this Retailer has no shops", which a client-side
      // refusal is not.
      final VendorRetailerResult<List<VendorRetailerShop>> result =
          await buildRepository().retailerShops('nope');

      expect(shopParams, isEmpty);
      expect(
        (result as VendorRetailerReadFailure<List<VendorRetailerShop>>).failure,
        isA<InvalidFailure>(),
      );
    });
  });

  group('thrown calls are classified by SQLSTATE, never by message', () {
    test('42501 becomes a denial on all three reads', () async {
      thrown = postgrest('42501');

      expect(
        (await buildRepository().retailers()
                as VendorRetailerReadFailure<List<VendorRetailerSummary>>)
            .failure,
        isA<DeniedFailure>(),
      );
      expect(
        (await buildRepository().retailerDetail(northwindRelationshipUuid)
                as VendorRetailerReadFailure<VendorRetailerDetail?>)
            .failure,
        isA<DeniedFailure>(),
      );
      expect(
        (await buildRepository().retailerShops(northwindRelationshipUuid)
                as VendorRetailerReadFailure<List<VendorRetailerShop>>)
            .failure,
        isA<DeniedFailure>(),
      );
    });

    test('an unrecognized SQLSTATE is an outage, never a denial', () async {
      thrown = postgrest('08006');

      final VendorRetailerResult<List<VendorRetailerSummary>> result =
          await buildRepository().retailers();

      expect(
        (result as VendorRetailerReadFailure<List<VendorRetailerSummary>>)
            .failure,
        isA<UnavailableFailure>(),
      );
    });

    test('an auth exception is unauthenticated, not denied', () async {
      thrown = const AuthException('expired');

      final VendorRetailerResult<List<VendorRetailerSummary>> result =
          await buildRepository().retailers();

      expect(
        (result as VendorRetailerReadFailure<List<VendorRetailerSummary>>)
            .failure,
        isA<UnauthenticatedFailure>(),
      );
    });

    test('a plain transport error is an outage', () async {
      thrown = Exception('socket closed');

      final VendorRetailerResult<VendorRetailerDetail?> result =
          await buildRepository().retailerDetail(northwindRelationshipUuid);

      expect(
        (result as VendorRetailerReadFailure<VendorRetailerDetail?>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('the backend message never travels into the failure', () async {
      thrown = postgrest('42501');

      final VendorRetailerResult<List<VendorRetailerSummary>> result =
          await buildRepository().retailers();
      final Failure failure =
          (result as VendorRetailerReadFailure<List<VendorRetailerSummary>>)
              .failure;

      expect(failure.toString(), isNot(contains('backend detail')));
      expect(failure.props, isEmpty);
    });
  });

  group('a malformed body is an outage, never an empty list', () {
    test('the list', () async {
      retailerBody = <Map<String, Object?>>[retailerRow(relationshipId: 'x')];

      final VendorRetailerResult<List<VendorRetailerSummary>> result =
          await buildRepository().retailers();

      expect(
        (result as VendorRetailerReadFailure<List<VendorRetailerSummary>>)
            .failure,
        isA<UnavailableFailure>(),
      );
    });

    test('the detail — and it is not reported as "not found"', () async {
      // Unreadable and "not addressable by you" are different events. Collapsing
      // the first into the second would tell a Vendor their Retailer is gone.
      detailBody = <Map<String, Object?>>[detailRow(shopCount: -1)];

      final VendorRetailerResult<VendorRetailerDetail?> result =
          await buildRepository().retailerDetail(northwindRelationshipUuid);

      expect(result, isA<VendorRetailerReadFailure<VendorRetailerDetail?>>());
      expect(
        (result as VendorRetailerReadFailure<VendorRetailerDetail?>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('the shops', () async {
      shopBody = <Map<String, Object?>>[shopRow(shopStatus: null)];

      final VendorRetailerResult<List<VendorRetailerShop>> result =
          await buildRepository().retailerShops(northwindRelationshipUuid);

      expect(
        (result as VendorRetailerReadFailure<List<VendorRetailerShop>>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('a non-list body is an outage rather than a crash', () async {
      retailerBody = <String, Object?>{'unexpected': true};

      final VendorRetailerResult<List<VendorRetailerSummary>> result =
          await buildRepository().retailers();

      expect(
        (result as VendorRetailerReadFailure<List<VendorRetailerSummary>>)
            .failure,
        isA<UnavailableFailure>(),
      );
    });
  });

  group('one read per call', () {
    test('each method issues exactly one RPC', () async {
      final SupabaseVendorRetailerRepository repository = buildRepository();

      await repository.retailers();
      await repository.retailerDetail(northwindRelationshipUuid);
      await repository.retailerShops(northwindRelationshipUuid);

      expect(retailerCalls, 1);
      expect(detailParams, hasLength(1));
      expect(shopParams, hasLength(1));
    });

    test('listing Retailers never reads any shop', () async {
      // The counts come from a SQL lateral aggregate. A per-row shop read would
      // reintroduce exactly the row-transfer defect the backend removed.
      await buildRepository().retailers();

      expect(shopParams, isEmpty);
      expect(detailParams, isEmpty);
    });
  });
}
