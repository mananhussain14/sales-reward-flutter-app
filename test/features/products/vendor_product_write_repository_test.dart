import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/products/data/datasources/vendor_product_rpc_data_source.dart';
import 'package:sale_reward/features/products/data/datasources/vendor_product_write_rpc_data_source.dart';
import 'package:sale_reward/features/products/data/repositories/supabase_vendor_product_repository.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_draft.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_edit.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_status_change.dart';
import 'package:sale_reward/features/products/domain/repositories/vendor_product_write_result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/vendor_product_fakes.dart';

/// The write repository, driven over recording invokers.
///
/// These assert what leaves the client — the function name, the exact parameter
/// names, and, just as importantly, the parameters that are **absent** — and how each
/// answer is classified. The invokers stand in for `client.rpc`, so nothing here
/// touches Supabase.
void main() {
  late List<({String rpc, Map<String, Object?> params})> calls;
  Object? thrown;
  Object? createBody = createdProductUuid;
  Object? voidBody;

  setUp(() {
    calls = <({String rpc, Map<String, Object?> params})>[];
    thrown = null;
    createBody = createdProductUuid;
    voidBody = null;
  });

  /// A repository whose write invokers record the payload verbatim.
  ///
  /// The payload is rebuilt from the *deployed parameter-name constants*, not from
  /// restated literals — so a rename of one of those constants cannot pass these
  /// tests while breaking the real call.
  SupabaseVendorProductRepository buildRepository() {
    return SupabaseVendorProductRepository(
      // A write path must issue no read. These throw so a stray one is a failure
      // rather than a silent extra round trip.
      rpc: VendorProductRpcDataSource(
        products: () async =>
            throw StateError('a write path read the catalogue'),
        detail: (String productId) async =>
            throw StateError('a write path read the detail'),
        assignedRetailers: (String productId) async =>
            throw StateError('a write path read the assignments'),
      ),
      writes: VendorProductWriteRpcDataSource(
        create:
            ({
              required String productCode,
              required String productName,
              required String? barcode,
              required String? brand,
              required String? description,
            }) async {
              calls.add((
                rpc: createVendorProductRpc,
                params: <String, Object?>{
                  productCodeParameter: productCode,
                  productNameParameter: productName,
                  barcodeParameter: barcode,
                  brandParameter: brand,
                  descriptionParameter: description,
                },
              ));
              if (thrown != null) throw thrown!;
              return createBody;
            },
        update:
            ({
              required String productId,
              required String productName,
              required String? barcode,
              required String? brand,
              required String? description,
            }) async {
              calls.add((
                rpc: updateVendorProductRpc,
                params: <String, Object?>{
                  writeProductIdParameter: productId,
                  productNameParameter: productName,
                  barcodeParameter: barcode,
                  brandParameter: brand,
                  descriptionParameter: description,
                },
              ));
              if (thrown != null) throw thrown!;
              return voidBody;
            },
        setStatus: ({required String productId, required String status}) async {
          calls.add((
            rpc: setVendorProductStatusRpc,
            params: <String, Object?>{
              writeProductIdParameter: productId,
              statusParameter: status,
            },
          ));
          if (thrown != null) throw thrown!;
          return voidBody;
        },
      ),
    );
  }

  const VendorProductDraft draft = VendorProductDraft(
    productCode: 'ESP-1000',
    productName: 'Espresso Blend 1kg',
    barcode: '5012345678900',
    brand: 'Harvest Roasters',
    description: 'A dark roast blend.',
  );

  const VendorProductEdit edit = VendorProductEdit(
    productName: 'Espresso Blend 1kg',
    barcode: '5012345678900',
    brand: 'Harvest Roasters',
    description: 'A dark roast blend.',
  );

  /// A refusal carrying [failure].
  ///
  /// `VendorProductWriteResult` is deliberately not `Equatable` — `ReadResult` is not
  /// either — so a refusal is matched on the discriminant it carries rather than on
  /// instance identity. The `Failure` itself IS `Equatable`, which is what makes the
  /// comparison meaningful.
  Matcher refusedWith<T>(Failure failure) =>
      isA<VendorProductWriteFailure<T>>().having(
        (VendorProductWriteFailure<T> r) => r.failure,
        'failure',
        failure,
      );

  PostgrestException pg(String code, String message) =>
      PostgrestException(message: message, code: code);

  group('the deployed function names', () {
    test('they are exactly the three shipped write RPCs', () {
      expect(createVendorProductRpc, 'create_vendor_product');
      expect(updateVendorProductRpc, 'update_vendor_product');
      expect(setVendorProductStatusRpc, 'set_vendor_product_status');
    });

    test('the seven parameter names are the deployed ones', () {
      expect(productCodeParameter, 'p_product_code');
      expect(productNameParameter, 'p_product_name');
      expect(barcodeParameter, 'p_barcode');
      expect(brandParameter, 'p_brand');
      expect(descriptionParameter, 'p_description');
      expect(writeProductIdParameter, 'p_product_id');
      expect(statusParameter, 'p_status');
    });
  });

  group('create', () {
    test('calls create_vendor_product with exactly five parameters', () async {
      await buildRepository().createProduct(draft);

      expect(calls.length, 1);
      expect(calls.single.rpc, 'create_vendor_product');
      expect(calls.single.params, <String, Object?>{
        'p_product_code': 'ESP-1000',
        'p_product_name': 'Espresso Blend 1kg',
        'p_barcode': '5012345678900',
        'p_brand': 'Harvest Roasters',
        'p_description': 'A dark roast blend.',
      });
    });

    test('there is no sixth parameter of any kind', () async {
      await buildRepository().createProduct(draft);

      expect(calls.single.params.keys.length, 5);
      for (final String forbidden in <String>[
        'p_status',
        'p_product_id',
        'p_organization_id',
        'p_vendor_organization_id',
        'p_user_id',
        'p_profile_id',
        'p_created_by',
        'p_actor',
        'p_metadata',
        'p_retailer_organization_id',
        'p_price',
        'p_stock',
      ]) {
        expect(calls.single.params.containsKey(forbidden), isFalse);
      }
    });

    test('optional nulls are sent as null, never as empty strings', () async {
      await buildRepository().createProduct(
        const VendorProductDraft(
          productCode: 'DEC-2000',
          productName: 'Decaf Ground 500g',
        ),
      );

      expect(calls.single.params['p_barcode'], isNull);
      expect(calls.single.params['p_brand'], isNull);
      expect(calls.single.params['p_description'], isNull);
      // The two required values are still there.
      expect(calls.single.params['p_product_code'], 'DEC-2000');
      expect(calls.single.params['p_product_name'], 'Decaf Ground 500g');
    });

    test('a multiline description travels intact', () async {
      await buildRepository().createProduct(
        const VendorProductDraft(
          productCode: 'A',
          productName: 'B',
          description: 'Line one.\n\nLine two.\n  indented',
        ),
      );

      expect(
        calls.single.params['p_description'],
        'Line one.\n\nLine two.\n  indented',
      );
    });

    test('a barcode is sent as text, with its leading zero', () async {
      await buildRepository().createProduct(
        const VendorProductDraft(
          productCode: 'A',
          productName: 'B',
          barcode: '012345678905',
        ),
      );

      expect(calls.single.params['p_barcode'], isA<String>());
      expect(calls.single.params['p_barcode'], '012345678905');
    });

    test('a well-formed uuid answers success carrying it', () async {
      final VendorProductWriteResult<String> result = await buildRepository()
          .createProduct(draft);

      expect(result, isA<VendorProductWriteSuccess<String>>());
      expect(
        (result as VendorProductWriteSuccess<String>).value,
        createdProductUuid,
      );
    });

    test('a malformed id answers UNCONFIRMED, never a failure', () async {
      // The product exists: the function commits or raises, never both. Reporting a
      // failure would be false, and would invite a duplicate.
      for (final Object? body in <Object?>[
        null,
        '',
        'not-a-uuid',
        <Object?>[createdProductUuid],
        <String, Object?>{'id': createdProductUuid},
        42,
      ]) {
        calls.clear();
        createBody = body;
        final VendorProductWriteResult<String> result = await buildRepository()
            .createProduct(draft);

        expect(
          result,
          isA<VendorProductWriteUnconfirmed<String>>(),
          reason: 'a body of $body must not be reported as a failed create',
        );
        // And exactly one call was made — nothing retried it.
        expect(calls.length, 1);
      }
    });

    test('a duplicate code is a field-attributed duplicate', () async {
      thrown = pg('23505', 'A product with that code already exists');
      final VendorProductWriteResult<String> result = await buildRepository()
          .createProduct(draft);

      expect(
        result,
        refusedWith<String>(const DuplicateFailure(field: 'productCode')),
      );
    });

    test('a duplicate barcode is attributed to the barcode instead', () async {
      thrown = pg('23505', 'A product with that barcode already exists');
      final VendorProductWriteResult<String> result = await buildRepository()
          .createProduct(draft);

      expect(
        result,
        refusedWith<String>(const DuplicateFailure(field: 'barcode')),
      );
    });

    test('42501 is one generic denial', () async {
      thrown = pg('42501', 'Not authorized to manage products');
      expect(
        await buildRepository().createProduct(draft),
        refusedWith<String>(const DeniedFailure()),
      );
    });

    test('23514 is a generic invalid with no field', () async {
      thrown = pg('23514', 'Enter a valid product code');
      final VendorProductWriteResult<String> result = await buildRepository()
          .createProduct(draft);

      expect(result, isA<VendorProductWriteFailure<String>>());
      final Failure failure =
          (result as VendorProductWriteFailure<String>).failure;
      expect(failure, isA<InvalidFailure>());
      expect((failure as InvalidFailure).field, isNull);
    });

    test('a transport failure is unavailable, never a denial', () async {
      thrown = Exception('SocketException: failed host lookup');
      expect(
        await buildRepository().createProduct(draft),
        refusedWith<String>(const UnavailableFailure()),
      );
    });

    test('an expired session is unauthenticated', () async {
      thrown = const AuthException('token expired');
      expect(
        await buildRepository().createProduct(draft),
        refusedWith<String>(const UnauthenticatedFailure()),
      );
    });

    test('a failure is never reported as unconfirmed', () async {
      // The distinction the result type exists for: a refusal rolls the whole
      // function back, so nothing was written and a retry is legitimate.
      thrown = pg('42501', 'Not authorized to manage products');
      expect(
        await buildRepository().createProduct(draft),
        isNot(isA<VendorProductWriteUnconfirmed<String>>()),
      );
    });
  });

  group('edit', () {
    test('calls update_vendor_product with the id and four fields', () async {
      await buildRepository().updateProduct(espressoProductUuid, edit);

      expect(calls.length, 1);
      expect(calls.single.rpc, 'update_vendor_product');
      expect(calls.single.params, <String, Object?>{
        'p_product_id': espressoProductUuid,
        'p_product_name': 'Espresso Blend 1kg',
        'p_barcode': '5012345678900',
        'p_brand': 'Harvest Roasters',
        'p_description': 'A dark roast blend.',
      });
    });

    test('there is NO p_product_code parameter', () async {
      // The code is the canonical key assignments are made against; re-keying in
      // place would silently change what every downstream reference means.
      await buildRepository().updateProduct(espressoProductUuid, edit);

      expect(calls.single.params.containsKey('p_product_code'), isFalse);
      expect(
        calls.single.params.values.contains('ESP-1000'),
        isFalse,
        reason: 'a product code must not travel in an edit under any key',
      );
    });

    test('there is NO status parameter', () async {
      await buildRepository().updateProduct(espressoProductUuid, edit);

      expect(calls.single.params.containsKey('p_status'), isFalse);
      for (final Object? value in calls.single.params.values) {
        expect(value, isNot('ACTIVE'));
        expect(value, isNot('INACTIVE'));
      }
    });

    test(
      'there is no owner, organization, actor or assignment parameter',
      () async {
        await buildRepository().updateProduct(espressoProductUuid, edit);

        expect(calls.single.params.keys.length, 5);
        for (final String forbidden in <String>[
          'p_organization_id',
          'p_vendor_organization_id',
          'p_user_id',
          'p_profile_id',
          'p_created_by',
          'p_actor',
          'p_metadata',
          'p_retailer_organization_id',
          'p_assignment_status',
        ]) {
          expect(calls.single.params.containsKey(forbidden), isFalse);
        }
      },
    );

    test('cleared optionals are sent as null', () async {
      await buildRepository().updateProduct(
        espressoProductUuid,
        const VendorProductEdit(productName: 'Renamed'),
      );

      expect(calls.single.params['p_product_name'], 'Renamed');
      expect(calls.single.params['p_barcode'], isNull);
      expect(calls.single.params['p_brand'], isNull);
      expect(calls.single.params['p_description'], isNull);
    });

    test('an empty body is success', () async {
      expect(
        await buildRepository().updateProduct(espressoProductUuid, edit),
        isA<VendorProductWriteSuccess<void>>(),
      );
    });

    test('an unexpected body is UNCONFIRMED, never a failure', () async {
      // A 2xx means the row and its audit row are committed. Telling somebody their
      // saved change was not saved would be the worst answer available.
      for (final Object body in <Object>['ok', <Object?>[], 0]) {
        calls.clear();
        voidBody = body;
        final VendorProductWriteResult<void> result = await buildRepository()
            .updateProduct(espressoProductUuid, edit);

        expect(result, isA<VendorProductWriteUnconfirmed<void>>());
        expect(result, isNot(isA<VendorProductWriteFailure<void>>()));
      }
    });

    test('a malformed product id is refused before any request', () async {
      // A malformed uuid would come back as 22P02 from the type system — raised
      // before the function body runs, and therefore before any authorization check.
      for (final String malformed in <String>['', 'not-a-uuid', 'ESP-1000']) {
        calls.clear();
        final VendorProductWriteResult<void> result = await buildRepository()
            .updateProduct(malformed, edit);

        expect(calls, isEmpty, reason: 'no request may leave for $malformed');
        // Answered as the backend answers an id naming no product: one generic
        // denial, saying nothing about whether any product exists.
        expect(result, refusedWith<void>(const DeniedFailure()));
      }
    });

    test('a duplicate barcode is attributed to the barcode field', () async {
      thrown = pg('23505', 'A product with that barcode already exists');
      expect(
        await buildRepository().updateProduct(espressoProductUuid, edit),
        refusedWith<void>(const DuplicateFailure(field: 'barcode')),
      );
    });

    test('an unknown or foreign product is one generic denial', () async {
      // The backend refuses both byte-identically, so this client cannot and must not
      // tell them apart.
      thrown = pg('42501', 'Not authorized to manage this product');
      expect(
        await buildRepository().updateProduct(unknownProductUuid, edit),
        refusedWith<void>(const DeniedFailure()),
      );
    });

    test('a transport failure is unavailable', () async {
      thrown = Exception('Connection closed before full header was received');
      expect(
        await buildRepository().updateProduct(espressoProductUuid, edit),
        refusedWith<void>(const UnavailableFailure()),
      );
    });
  });

  group('status', () {
    test('deactivate sends INACTIVE and nothing else', () async {
      await buildRepository().setProductStatus(
        espressoProductUuid,
        VendorProductStatusChange.deactivate,
      );

      expect(calls.length, 1);
      expect(calls.single.rpc, 'set_vendor_product_status');
      expect(calls.single.params, <String, Object?>{
        'p_product_id': espressoProductUuid,
        'p_status': 'INACTIVE',
      });
    });

    test('activate sends ACTIVE', () async {
      await buildRepository().setProductStatus(
        retiredProductUuid,
        VendorProductStatusChange.activate,
      );

      expect(calls.single.params, <String, Object?>{
        'p_product_id': retiredProductUuid,
        'p_status': 'ACTIVE',
      });
    });

    test('only ACTIVE and INACTIVE are expressible', () async {
      // The request enum has two members, so there is no third token to send.
      final Set<Object?> sent = <Object?>{};
      for (final VendorProductStatusChange change
          in VendorProductStatusChange.values) {
        calls.clear();
        await buildRepository().setProductStatus(espressoProductUuid, change);
        sent.add(calls.single.params['p_status']);
      }
      expect(sent, <String>{'ACTIVE', 'INACTIVE'});
    });

    test(
      'there is no product field, actor or organization parameter',
      () async {
        await buildRepository().setProductStatus(
          espressoProductUuid,
          VendorProductStatusChange.deactivate,
        );

        expect(calls.single.params.keys.length, 2);
        for (final String forbidden in <String>[
          'p_product_code',
          'p_product_name',
          'p_barcode',
          'p_brand',
          'p_description',
          'p_organization_id',
          'p_actor',
          'p_metadata',
          'p_retailer_organization_id',
        ]) {
          expect(calls.single.params.containsKey(forbidden), isFalse);
        }
      },
    );

    test('an empty body is success', () async {
      expect(
        await buildRepository().setProductStatus(
          espressoProductUuid,
          VendorProductStatusChange.deactivate,
        ),
        isA<VendorProductWriteSuccess<void>>(),
      );
    });

    test('an unexpected body is UNCONFIRMED, never a failure', () async {
      voidBody = <String, Object?>{'status': 'INACTIVE'};
      expect(
        await buildRepository().setProductStatus(
          espressoProductUuid,
          VendorProductStatusChange.deactivate,
        ),
        isA<VendorProductWriteUnconfirmed<void>>(),
      );
    });

    test('a malformed product id is refused before any request', () async {
      final VendorProductWriteResult<void> result = await buildRepository()
          .setProductStatus('not-a-uuid', VendorProductStatusChange.activate);

      expect(calls, isEmpty);
      expect(result, refusedWith<void>(const DeniedFailure()));
    });

    test('an invalid status answer is a generic invalid', () async {
      // Unreachable from this client's own types, but the classification is honest
      // rather than special-cased.
      thrown = pg('23514', 'Choose a valid product status');
      final VendorProductWriteResult<void> result = await buildRepository()
          .setProductStatus(
            espressoProductUuid,
            VendorProductStatusChange.activate,
          );
      expect(
        (result as VendorProductWriteFailure<void>).failure,
        isA<InvalidFailure>(),
      );
    });

    test('a denial is generic and says nothing about existence', () async {
      thrown = pg('42501', 'Not authorized to manage this product');
      expect(
        await buildRepository().setProductStatus(
          unknownProductUuid,
          VendorProductStatusChange.deactivate,
        ),
        refusedWith<void>(const DeniedFailure()),
      );
    });
  });

  group('a write issues no read, and one write is one call', () {
    test('none of the three touches a read invoker', () async {
      // The read invokers throw; reaching one would surface here rather than as a
      // silent extra round trip.
      final SupabaseVendorProductRepository repository = buildRepository();
      await repository.createProduct(draft);
      await repository.updateProduct(espressoProductUuid, edit);
      await repository.setProductStatus(
        espressoProductUuid,
        VendorProductStatusChange.activate,
      );

      expect(
        calls.map((({String rpc, Map<String, Object?> params}) c) => c.rpc),
        <String>[
          'create_vendor_product',
          'update_vendor_product',
          'set_vendor_product_status',
        ],
      );
    });

    test('no assignment or audit RPC is ever named', () async {
      final SupabaseVendorProductRepository repository = buildRepository();
      await repository.createProduct(draft);
      await repository.updateProduct(espressoProductUuid, edit);
      await repository.setProductStatus(
        espressoProductUuid,
        VendorProductStatusChange.deactivate,
      );

      for (final String forbidden in <String>[
        'assign_vendor_product_to_retailer',
        'unassign_vendor_product_from_retailer',
        'delete_vendor_product',
        'list_vendor_product_retailer_assignments',
        'insert_audit_log',
      ]) {
        expect(
          calls.any(
            (({String rpc, Map<String, Object?> params}) c) =>
                c.rpc == forbidden,
          ),
          isFalse,
        );
      }
    });

    test('a refused write makes exactly one call', () async {
      // Nothing retries. A create in particular must never be re-issued on its own.
      thrown = pg('23505', 'A product with that code already exists');
      await buildRepository().createProduct(draft);
      expect(calls.length, 1);
    });
  });
}
