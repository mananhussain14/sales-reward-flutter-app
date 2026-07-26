import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/products/data/models/vendor_product_write_parsers.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assignment_action.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assignment_request.dart';

import '../../support/vendor_product_fakes.dart';

/// The assignment request value object, the action vocabulary, and the `void`
/// response contract.
///
/// These are the three things the write boundary is made of, and each is
/// asserted for what it makes **impossible** as much as for what it does.
void main() {
  VendorProductAssignmentRequest request({
    String productId = espressoProductUuid,
    String retailerOrganizationId = northwindOrgId,
  }) => VendorProductAssignmentRequest(
    productId: productId,
    retailerOrganizationId: retailerOrganizationId,
  );

  group('the request carries two addresses and nothing else', () {
    test('its whole identity is the product id and the Retailer org id', () {
      // `props` is the type's full field list. Two entries, so a third field
      // could not be added without changing this number — and there is no
      // organization, tenant, auth-user, profile, membership, relationship,
      // role, permission, actor, audit, status or note field to add it as.
      expect(request().props.length, 2);
      expect(request().props, <Object?>[espressoProductUuid, northwindOrgId]);
    });

    test('two requests naming the same pairing are equal', () {
      expect(request(), request());
    });

    test('a different Retailer is a different request', () {
      expect(
        request(retailerOrganizationId: harbourOrgId),
        isNot(request(retailerOrganizationId: northwindOrgId)),
      );
    });

    test('a different product is a different request', () {
      expect(
        request(productId: decafProductUuid),
        isNot(request(productId: espressoProductUuid)),
      );
    });
  });

  group('addressability is a shape test, and never an existence test', () {
    test('two well-formed uuids are addressable', () {
      expect(request().isAddressable, isTrue);
    });

    test('a well-formed id that names nothing is still addressable', () {
      // The point of the guard: it screens the *shape* so a cast error cannot
      // masquerade as an outage. Whether the id names anything is the backend's
      // answer, and a valid-looking foreign id must reach it and be refused
      // there.
      expect(request(productId: unknownProductUuid).isAddressable, isTrue);
    });

    test('uppercase hexadecimal is accepted', () {
      expect(
        request(productId: espressoProductUuid.toUpperCase()).isAddressable,
        isTrue,
      );
    });

    test('a malformed product id is not addressable', () {
      for (final String malformed in <String>[
        '',
        '   ',
        'not-a-uuid',
        '7a1b2c3d-4e5f-4061-8273',
        '7a1b2c3d4e5f4061827394a5b6c7d8e9',
        'zzzzzzzz-4e5f-4061-8273-94a5b6c7d8e9',
      ]) {
        expect(
          request(productId: malformed).isAddressable,
          isFalse,
          reason: '"$malformed" was treated as a product address',
        );
      }
    });

    test('a malformed Retailer organization id is not addressable', () {
      for (final String malformed in <String>[
        '',
        'Northwind Retail',
        'not-a-uuid',
        '41829304-b5c6-47d8-e9f0',
      ]) {
        expect(
          request(retailerOrganizationId: malformed).isAddressable,
          isFalse,
          reason: '"$malformed" was treated as a Retailer address',
        );
      }
    });

    test('a uuid embedded in a longer string is not addressable', () {
      // Anchored at both ends, so a value that merely contains a uuid cannot
      // pass and reach a `uuid` parameter as a cast error.
      expect(
        request(productId: ' $espressoProductUuid ').isAddressable,
        isFalse,
      );
      expect(
        request(productId: '$espressoProductUuid/../x').isAddressable,
        isFalse,
      );
    });

    test('one bad half is enough to refuse the whole request', () {
      expect(
        request(retailerOrganizationId: 'nope').isAddressable,
        isFalse,
        reason: 'a well-formed product id does not rescue a malformed Retailer',
      );
      expect(request(productId: 'nope').isAddressable, isFalse);
    });
  });

  group('the action vocabulary', () {
    test('there are exactly three, and no delete or bulk member', () {
      expect(
        VendorProductAssignmentAction.values,
        <VendorProductAssignmentAction>[
          VendorProductAssignmentAction.assign,
          VendorProductAssignmentAction.reactivate,
          VendorProductAssignmentAction.withdraw,
        ],
      );
    });

    test('only withdrawal reaches the withdrawal function', () {
      expect(VendorProductAssignmentAction.withdraw.isWithdrawal, isTrue);
      expect(VendorProductAssignmentAction.assign.isWithdrawal, isFalse);
      // The load-bearing one: reactivation is the SAME call as a fresh
      // assignment, because creating and reactivating are one operation in SQL.
      expect(VendorProductAssignmentAction.reactivate.isWithdrawal, isFalse);
    });
  });

  group('the void response contract', () {
    test('an empty body is the successful shape', () {
      expect(isVoidWriteResponse(null), isTrue);
    });

    test('any other body is not accepted as the successful shape', () {
      for (final Object body in <Object>[
        '',
        'ok',
        <Object?>[],
        <String, Object?>{},
        <String, Object?>{'status': 'ACTIVE'},
        0,
        false,
      ]) {
        expect(
          isVoidWriteResponse(body),
          isFalse,
          reason: '$body was accepted as a void response',
        );
      }
    });
  });
}
