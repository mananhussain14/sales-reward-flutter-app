import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/auth/data/models/portal_context_parser.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_context.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';

/// The parser is the app's fail-safe boundary: a malformed or unfamiliar
/// response must never become a privileged role. These cases pin every branch
/// the migration's contract can produce, and every branch it must reject.
void main() {
  Map<String, Object?> vendorBody({int version = 1}) => <String, Object?>{
    'context_version': version,
    'portal_kind': 'VENDOR_SUPER_ADMIN',
    'vendor': <String, Object?>{
      'organization_id': '11111111-1111-1111-1111-111111111111',
      'organization_name': 'Vendor Co',
    },
    'retailer': null,
  };

  Map<String, Object?> capabilities({bool submit = true}) => <String, Object?>{
    'view_retailer_overview': true,
    'view_shops': true,
    'view_staff': true,
    'manage_staff': true,
    'assign_staff_shops': true,
    'view_assigned_products': true,
    'submit_receipts': submit,
  };

  Map<String, Object?> retailerBody(String kind) => <String, Object?>{
    'context_version': 1,
    'portal_kind': kind,
    'vendor': null,
    'retailer': <String, Object?>{
      'kind': kind,
      'organization_id': '22222222-2222-2222-2222-222222222222',
      'organization_name': 'Retail Co',
      'capabilities': capabilities(),
    },
  };

  group('valid contexts', () {
    test('every portal kind parses to its own kind', () {
      expect(
        PortalContextParser.parse(vendorBody()).portalKind,
        PortalKind.vendorSuperAdmin,
      );
      expect(
        PortalContextParser.parse(retailerBody('RETAILER_OWNER')).portalKind,
        PortalKind.retailerOwner,
      );
      expect(
        PortalContextParser.parse(retailerBody('RETAILER_MANAGER')).portalKind,
        PortalKind.retailerManager,
      );
      expect(
        PortalContextParser.parse(retailerBody('SALES_STAFF')).portalKind,
        PortalKind.salesStaff,
      );
    });

    test('the vendor block parses its organization', () {
      final PortalContext context = PortalContextParser.parse(vendorBody());
      expect(context.vendor, isNotNull);
      expect(context.vendor!.organizationName, 'Vendor Co');
      expect(context.organizationName, 'Vendor Co');
      expect(context.retailer, isNull);
    });

    test('the retailer owner block parses its organization and kind', () {
      final PortalContext context = PortalContextParser.parse(
        retailerBody('RETAILER_OWNER'),
      );
      expect(context.retailer!.kind, RetailerKind.owner);
      expect(context.retailer!.organizationName, 'Retail Co');
      expect(context.vendor, isNull);
    });

    test('every capability value parses', () {
      final PortalContext context = PortalContextParser.parse(
        retailerBody('RETAILER_OWNER'),
      );
      final caps = context.capabilities;
      expect(caps.viewRetailerOverview, isTrue);
      expect(caps.viewShops, isTrue);
      expect(caps.viewStaff, isTrue);
      expect(caps.manageStaff, isTrue);
      expect(caps.assignStaffShops, isTrue);
      expect(caps.viewAssignedProducts, isTrue);
      expect(caps.submitReceipts, isTrue);
    });

    test('a false capability parses as false', () {
      final Map<String, Object?> body = retailerBody('SALES_STAFF');
      (body['retailer']! as Map<String, Object?>)['capabilities'] =
          capabilities(submit: false);
      final PortalContext context = PortalContextParser.parse(body);
      expect(context.capabilities.submitReceipts, isFalse);
    });

    test('a caller who holds both keeps both blocks and vendor precedence', () {
      final Map<String, Object?> body = vendorBody();
      body['retailer'] = <String, Object?>{
        'kind': 'RETAILER_OWNER',
        'organization_id': '22222222-2222-2222-2222-222222222222',
        'organization_name': 'Retail Co',
        'capabilities': capabilities(),
      };
      final PortalContext context = PortalContextParser.parse(body);
      expect(context.portalKind, PortalKind.vendorSuperAdmin);
      expect(context.vendor, isNotNull);
      expect(context.retailer, isNotNull);
    });

    test('NONE parses to a denied context with no blocks', () {
      final PortalContext context = PortalContextParser.parse(<String, Object?>{
        'context_version': 1,
        'portal_kind': 'NONE',
        'vendor': null,
        'retailer': null,
      });
      expect(context.portalKind, PortalKind.none);
      expect(context.isDenied, isTrue);
      expect(context.vendor, isNull);
      expect(context.retailer, isNull);
    });

    test('an unrecognized extra key is ignored, not rejected', () {
      final Map<String, Object?> body = vendorBody()
        ..['some_future_key'] = <String, Object?>{'anything': true};
      expect(
        PortalContextParser.parse(body).portalKind,
        PortalKind.vendorSuperAdmin,
      );
    });

    test('a missing capability defaults to false, never true', () {
      final Map<String, Object?> body = retailerBody('SALES_STAFF');
      (body['retailer']! as Map<String, Object?>)['capabilities'] =
          <String, Object?>{'submit_receipts': true};
      final caps = PortalContextParser.parse(body).capabilities;
      expect(caps.submitReceipts, isTrue);
      // Everything not mentioned is conservatively off.
      expect(caps.viewStaff, isFalse);
      expect(caps.manageStaff, isFalse);
    });
  });

  group('fail-safe rejections', () {
    void expectRejected(Object? body) {
      expect(
        () => PortalContextParser.parse(body),
        throwsA(isA<PortalContextFormatException>()),
      );
    }

    test('an unsupported (higher) context_version fails safely', () {
      expectRejected(vendorBody(version: 2));
    });

    test('a lower context_version fails safely', () {
      expectRejected(vendorBody(version: 0));
    });

    test('a non-integer context_version fails safely', () {
      final Map<String, Object?> body = vendorBody()..['context_version'] = '1';
      expectRejected(body);
    });

    test('an unknown portal_kind fails safely, never a role', () {
      final Map<String, Object?> body = vendorBody()
        ..['portal_kind'] = 'SUPER_USER';
      expectRejected(body);
    });

    test('a missing portal_kind fails safely', () {
      final Map<String, Object?> body = vendorBody()..remove('portal_kind');
      expectRejected(body);
    });

    test('a non-object response fails safely', () {
      expectRejected('NONE');
      expectRejected(null);
      expectRejected(<Object?>[]);
    });

    test('a malformed organization UUID fails safely', () {
      final Map<String, Object?> body = vendorBody();
      (body['vendor']! as Map<String, Object?>)['organization_id'] =
          'not-a-uuid';
      expectRejected(body);
    });

    test('a blank organization name fails safely', () {
      final Map<String, Object?> body = vendorBody();
      (body['vendor']! as Map<String, Object?>)['organization_name'] = '   ';
      expectRejected(body);
    });

    test('a missing required vendor field fails safely', () {
      final Map<String, Object?> body = vendorBody();
      (body['vendor']! as Map<String, Object?>).remove('organization_id');
      expectRejected(body);
    });

    test('portal_kind naming a block that is absent fails safely', () {
      // Told to open the Vendor shell, but no vendor block — incoherent.
      final Map<String, Object?> body = vendorBody()..['vendor'] = null;
      expectRejected(body);
    });

    test('portal_kind disagreeing with retailer.kind fails safely', () {
      final Map<String, Object?> body = retailerBody('RETAILER_OWNER');
      (body['retailer']! as Map<String, Object?>)['kind'] = 'SALES_STAFF';
      expectRejected(body);
    });

    test('an unknown retailer.kind fails safely', () {
      final Map<String, Object?> body = retailerBody('RETAILER_OWNER');
      (body['retailer']! as Map<String, Object?>)['kind'] = 'RETAILER_ADMIN';
      // portal_kind is still RETAILER_OWNER, so the disagreement is caught
      // either way; the point is it never yields a role.
      expectRejected(body);
    });

    test('NONE carrying a stray block fails safely', () {
      expectRejected(<String, Object?>{
        'context_version': 1,
        'portal_kind': 'NONE',
        'vendor': <String, Object?>{
          'organization_id': '11111111-1111-1111-1111-111111111111',
          'organization_name': 'X',
        },
        'retailer': null,
      });
    });
  });
}
