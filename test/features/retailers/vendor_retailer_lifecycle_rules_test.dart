import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_lifecycle_action.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_lifecycle_status.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_status.dart';
import 'package:sale_reward/features/retailers/presentation/vendor/widgets/vendor_retailer_badges.dart';

/// The pure lifecycle rules, with no I/O and no widget.
///
/// Every case is built the way production builds one — through
/// `VendorRetailerStatus.fromCode`, the same function the detail parser uses —
/// so a token this build does not recognise reaches the rule exactly as it would
/// at run time rather than through a shortcut a test invented.
void main() {
  VendorRetailerLifecycleAction? resolve(String retailer, String relationship) {
    return VendorRetailerLifecycleAction.forPair(
      retailerStatus: VendorRetailerStatus.fromCode(retailer),
      relationshipStatus: VendorRetailerStatus.fromCode(relationship),
    );
  }

  group('eligible pairs', () {
    test('1. ACTIVE/ACTIVE is eligible', () {
      expect(resolve('ACTIVE', 'ACTIVE'), isNotNull);
    });

    test('2. ACTIVE/ACTIVE displays Active', () {
      expect(resolve('ACTIVE', 'ACTIVE')!.displayLabel, 'Active');
    });

    test('3. ACTIVE/ACTIVE offers Deactivate Retailer', () {
      expect(resolve('ACTIVE', 'ACTIVE')!.actionLabel, 'Deactivate Retailer');
    });

    test('4. ACTIVE/ACTIVE requests SUSPENDED', () {
      final VendorRetailerLifecycleAction action = resolve('ACTIVE', 'ACTIVE')!;
      expect(action.requestedStatus, VendorRetailerLifecycleStatus.suspended);
      // The wire token, not the display word.
      expect(action.requestedStatus.code, 'SUSPENDED');
      expect(action.isDeactivation, isTrue);
    });

    test('5. SUSPENDED/SUSPENDED is eligible', () {
      expect(resolve('SUSPENDED', 'SUSPENDED'), isNotNull);
    });

    test('6. SUSPENDED/SUSPENDED displays Inactive, never Suspended', () {
      expect(resolve('SUSPENDED', 'SUSPENDED')!.displayLabel, 'Inactive');
    });

    test('7. SUSPENDED/SUSPENDED offers Reactivate Retailer', () {
      expect(
        resolve('SUSPENDED', 'SUSPENDED')!.actionLabel,
        'Reactivate Retailer',
      );
    });

    test('8. SUSPENDED/SUSPENDED requests ACTIVE', () {
      final VendorRetailerLifecycleAction action = resolve(
        'SUSPENDED',
        'SUSPENDED',
      )!;
      expect(action.requestedStatus, VendorRetailerLifecycleStatus.active);
      expect(action.requestedStatus.code, 'ACTIVE');
      expect(action.isDeactivation, isFalse);
    });
  });

  group('excluded pairs', () {
    test('9. ACTIVE/SUSPENDED is excluded', () {
      // A mismatch is a state this operation cannot have created. The RPC
      // refuses it with 55000 and deliberately does not reconcile it.
      expect(resolve('ACTIVE', 'SUSPENDED'), isNull);
    });

    test('10. SUSPENDED/ACTIVE is excluded', () {
      expect(resolve('SUSPENDED', 'ACTIVE'), isNull);
    });

    test('11. a DEACTIVATED organization is excluded', () {
      expect(resolve('DEACTIVATED', 'ACTIVE'), isNull);
      expect(resolve('DEACTIVATED', 'SUSPENDED'), isNull);
    });

    test('12. a DEACTIVATED relationship is excluded', () {
      expect(resolve('ACTIVE', 'DEACTIVATED'), isNull);
      expect(resolve('SUSPENDED', 'DEACTIVATED'), isNull);
    });

    test('13. DEACTIVATED/DEACTIVATED is excluded', () {
      // Terminal, and not this operation's to clear — even though the pair
      // agrees, which is why the vocabulary test runs before the equality test.
      expect(resolve('DEACTIVATED', 'DEACTIVATED'), isNull);
    });

    test('14. an unknown token is excluded, on either row and on both', () {
      expect(resolve('PAUSED', 'ACTIVE'), isNull);
      expect(resolve('ACTIVE', 'PAUSED'), isNull);
      expect(resolve('PAUSED', 'PAUSED'), isNull);
    });

    test('15. a missing or empty status is excluded', () {
      expect(resolve('', ''), isNull);
      expect(resolve('', 'ACTIVE'), isNull);
      expect(resolve('ACTIVE', ''), isNull);
    });

    test('16. INACTIVE is excluded — it is a display word, not a status', () {
      expect(resolve('INACTIVE', 'INACTIVE'), isNull);
      expect(resolve('INACTIVE', 'ACTIVE'), isNull);
      expect(resolve('ACTIVE', 'INACTIVE'), isNull);
    });

    test('a lower-case token is excluded', () {
      // The RPC compares case-sensitively. A client that accepted 'active' here
      // would offer a control the database refuses with 23514.
      expect(resolve('active', 'active'), isNull);
      expect(resolve('suspended', 'suspended'), isNull);
    });
  });

  group('the request vocabulary is closed', () {
    test('17. INACTIVE is not a request enum value', () {
      expect(
        VendorRetailerLifecycleStatus.values.map(
          (VendorRetailerLifecycleStatus s) => s.code,
        ),
        <String>['ACTIVE', 'SUSPENDED'],
      );
      expect(VendorRetailerLifecycleStatus.tryParse('INACTIVE'), isNull);
      expect(VendorRetailerLifecycleStatus.tryParse('DEACTIVATED'), isNull);
      expect(VendorRetailerLifecycleStatus.tryParse('active'), isNull);
      expect(VendorRetailerLifecycleStatus.tryParse(''), isNull);
      expect(VendorRetailerLifecycleStatus.tryParse(null), isNull);
      expect(VendorRetailerLifecycleStatus.tryParse(1), isNull);
    });

    test('every offered action requests a token the RPC accepts', () {
      for (final String status in <String>['ACTIVE', 'SUSPENDED']) {
        final VendorRetailerLifecycleAction action = resolve(status, status)!;
        expect(<String>[
          'ACTIVE',
          'SUSPENDED',
        ], contains(action.requestedStatus.code));
      }
    });

    test('the requested status is the opposite of the current one', () {
      expect(
        resolve('ACTIVE', 'ACTIVE')!.requestedStatus,
        isNot(resolve('ACTIVE', 'ACTIVE')!.currentStatus),
      );
      expect(
        resolve('SUSPENDED', 'SUSPENDED')!.requestedStatus,
        isNot(resolve('SUSPENDED', 'SUSPENDED')!.currentStatus),
      );
    });
  });

  group('badge terminology', () {
    test('18. DEACTIVATED remains displayed as Deactivated', () {
      expect(
        VendorRetailerStatusBadge.labelFor(VendorRetailerStatus.deactivated),
        'Deactivated',
      );
    });

    test('SUSPENDED displays Inactive', () {
      expect(
        VendorRetailerStatusBadge.labelFor(VendorRetailerStatus.suspended),
        'Inactive',
      );
    });

    test('ACTIVE displays Active and unknown displays Unknown', () {
      expect(
        VendorRetailerStatusBadge.labelFor(VendorRetailerStatus.active),
        'Active',
      );
      expect(
        VendorRetailerStatusBadge.labelFor(VendorRetailerStatus.unknown),
        'Unknown',
      );
    });

    test('no Vendor Retailer status label says Suspended', () {
      for (final VendorRetailerStatus status in VendorRetailerStatus.values) {
        expect(
          VendorRetailerStatusBadge.labelFor(status),
          isNot('Suspended'),
          reason: '$status must not read "Suspended"',
        );
      }
    });

    test('SUSPENDED and DEACTIVATED are not collapsed into one word', () {
      // The web renders both as "Inactive". This build deliberately does not:
      // one is reversible by this very control and the other is terminal, and
      // rendering both the same would invite somebody to look for a Reactivate
      // button that cannot exist.
      expect(
        VendorRetailerStatusBadge.labelFor(VendorRetailerStatus.suspended),
        isNot(
          VendorRetailerStatusBadge.labelFor(VendorRetailerStatus.deactivated),
        ),
      );
    });

    test('no label leaks a raw backend token', () {
      for (final VendorRetailerStatus status in VendorRetailerStatus.values) {
        final String label = VendorRetailerStatusBadge.labelFor(status);
        expect(label, isNot('ACTIVE'));
        expect(label, isNot('SUSPENDED'));
        expect(label, isNot('DEACTIVATED'));
      }
    });
  });
}
