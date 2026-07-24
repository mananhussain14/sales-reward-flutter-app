import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/navigation/role_destination.dart';
import 'package:sale_reward/app/navigation/role_navigation_registry.dart';
import 'package:sale_reward/app/shells/retailer_manager/retailer_manager_navigation.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_navigation.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_navigation.dart';
import 'package:sale_reward/app/shells/vendor/vendor_navigation.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/domain/entities/retailer_capabilities.dart';

/// The four navigation models are **separate declarations**, not one filtered
/// list.
///
/// The web states the reason in `retailer-nav-items.tsx`: *two lists that share
/// nothing cannot leak into each other.* These tests assert that property
/// structurally, so a future refactor toward a shared filtered list fails here
/// rather than in production.
void main() {
  group('each role has its own model', () {
    test('the registry resolves each role to its own declaration', () {
      expect(
        RoleNavigationRegistry.forRole(PortalKind.vendorSuperAdmin),
        same(VendorNavigation.model),
      );
      expect(
        RoleNavigationRegistry.forRole(PortalKind.retailerOwner),
        same(RetailerOwnerNavigation.model),
      );
      expect(
        RoleNavigationRegistry.forRole(PortalKind.retailerManager),
        same(RetailerManagerNavigation.model),
      );
      expect(
        RoleNavigationRegistry.forRole(PortalKind.salesStaff),
        same(SalesStaffNavigation.model),
      );
    });

    test('every shell kind is covered exactly once', () {
      final Set<PortalKind> shellKinds = PortalKind.values
          .where((PortalKind k) => k.hasShell)
          .toSet();
      expect(RoleNavigationRegistry.ordered, hasLength(shellKinds.length));
      expect(
        RoleNavigationRegistry.ordered
            .map((RoleNavigation n) => n.role)
            .toSet(),
        shellKinds,
      );
    });

    test('PortalKind.none has no navigation model', () {
      expect(RoleNavigationRegistry.forRole(PortalKind.none), isNull);
      expect(RoleNavigationRegistry.landingPathFor(PortalKind.none), isNull);
    });

    test('no two roles share a destination list instance', () {
      final List<List<RoleDestination>> lists = RoleNavigationRegistry.ordered
          .map((RoleNavigation n) => n.destinations)
          .toList();

      for (int i = 0; i < lists.length; i++) {
        for (int j = i + 1; j < lists.length; j++) {
          expect(
            identical(lists[i], lists[j]),
            isFalse,
            reason: 'two roles are sharing one destination list',
          );
        }
      }
    });

    test('no two roles share a RoleDestination instance', () {
      // A shared entry would mean one edit silently changing two menus.
      final List<RoleDestination> seen = <RoleDestination>[];

      for (final RoleNavigation navigation in RoleNavigationRegistry.ordered) {
        for (final RoleDestination destination in navigation.destinations) {
          for (final RoleDestination previous in seen) {
            expect(identical(previous, destination), isFalse);
          }
          seen.add(destination);
        }
      }
    });

    test('the ordering records vendor-first landing precedence', () {
      // The precedence rule itself is applied by the backend resolver; this
      // list is where the mobile side writes it down.
      expect(
        RoleNavigationRegistry.ordered.first.role,
        PortalKind.vendorSuperAdmin,
      );
    });
  });

  group('destination sets match the role-flow map', () {
    test('Vendor: six active plus six "Soon"', () {
      const RoleNavigation model = VendorNavigation.model;

      expect(model.routableDestinations, hasLength(6));
      expect(model.destinations, hasLength(12));
      expect(
        model.routableDestinations.map((RoleDestination d) => d.label),
        <String>[
          'Dashboard',
          'Retailers',
          'Users',
          'Roles',
          'Products',
          'Audit Logs',
        ],
      );
      expect(
        model.destinations
            .where((RoleDestination d) => !d.isEnabled)
            .map((RoleDestination d) => d.label),
        <String>[
          'Campaigns',
          'Claims',
          'Coins',
          'Payouts',
          'Reports',
          'Settings',
        ],
      );
    });

    test('Retailer Owner: Overview, Shops, Staff, Products', () {
      expect(
        RetailerOwnerNavigation.model.destinations.map(
          (RoleDestination d) => d.label,
        ),
        <String>['Overview', 'Shops', 'Staff', 'Products'],
      );
    });

    test('Retailer Manager: Staff and Products only', () {
      expect(
        RetailerManagerNavigation.model.destinations.map(
          (RoleDestination d) => d.label,
        ),
        <String>['Staff', 'Products'],
      );
    });

    test('Sales Staff: Submit and History only', () {
      expect(
        SalesStaffNavigation.model.destinations.map(
          (RoleDestination d) => d.label,
        ),
        <String>['Submit', 'History'],
      );
    });

    test('Receipts never appears for the Owner or the Manager', () {
      // RECEIPT_SUBMIT is mapped to SALES_STAFF alone, so every receipt RPC
      // refuses them. Offering the entry would advertise a capability the
      // database will not grant.
      for (final RoleNavigation model in <RoleNavigation>[
        RetailerOwnerNavigation.model,
        RetailerManagerNavigation.model,
      ]) {
        for (final RoleDestination destination in model.destinations) {
          expect(destination.label.toLowerCase(), isNot(contains('receipt')));
          expect(destination.path, isNot(contains('receipt')));
        }
      }
    });

    test('the Retailer portal advertises no unbuilt modules', () {
      // "Soon" placeholders are for the internal Vendor audience only.
      for (final RoleNavigation model in <RoleNavigation>[
        RetailerOwnerNavigation.model,
        RetailerManagerNavigation.model,
        SalesStaffNavigation.model,
      ]) {
        expect(
          model.destinations.every((RoleDestination d) => d.isEnabled),
          isTrue,
          reason: '${model.role.name} must offer no "Soon" entry',
        );
      }
    });
  });

  group('chrome matches the destination count', () {
    test('only the Vendor uses a drawer', () {
      for (final RoleNavigation model in RoleNavigationRegistry.ordered) {
        final RoleShellChrome expected =
            model.role == PortalKind.vendorSuperAdmin
            ? RoleShellChrome.drawer
            : RoleShellChrome.bottomBar;
        expect(model.chrome, expected, reason: model.role.name);
      }
    });

    test('no bottom bar carries more than five items', () {
      for (final RoleNavigation model in RoleNavigationRegistry.ordered) {
        if (model.chrome != RoleShellChrome.bottomBar) continue;
        expect(
          model.destinations.length,
          inInclusiveRange(2, 5),
          reason: '${model.role.name} would crowd a bottom bar',
        );
      }
    });
  });

  group('landing paths', () {
    test('each role lands inside its own group, on a routable destination', () {
      for (final RoleNavigation model in RoleNavigationRegistry.ordered) {
        expect(model.owns(model.landingPath), isTrue);
        expect(
          model.routableDestinations.map((RoleDestination d) => d.path),
          contains(model.landingPath),
        );
      }
    });

    test('the Manager lands on the roster, not the overview', () {
      // The overview requires RETAILER_OWNER and would bounce them straight off.
      expect(
        RetailerManagerNavigation.model.landingPath,
        RetailerManagerNavigation.staff,
      );
    });

    test('Sales Staff lands on the primary write action', () {
      expect(
        SalesStaffNavigation.model.landingPath,
        SalesStaffNavigation.submit,
      );
      expect(
        SalesStaffNavigation.model.destinations.first.path,
        SalesStaffNavigation.submit,
        reason: 'the receipt action must be immediately visible',
      );
    });
  });

  group('indexForLocation', () {
    test('resolves each destination to its own index', () {
      for (final RoleNavigation model in RoleNavigationRegistry.ordered) {
        for (int i = 0; i < model.destinations.length; i++) {
          final String? path = model.destinations[i].path;
          if (path == null) continue;
          expect(model.indexForLocation(path), i);
        }
      }
    });

    test('longest prefix wins for a nested route', () {
      expect(
        RetailerOwnerNavigation.model.indexForLocation(
          '${RetailerOwnerNavigation.staff}/invite',
        ),
        2,
      );
    });

    test('falls back to the first destination for an unknown path', () {
      expect(SalesStaffNavigation.model.indexForLocation('/nowhere'), 0);
    });
  });

  group('capability filtering is a presentation hint', () {
    test('a false capability hides its destination', () {
      const RetailerCapabilities caps = RetailerCapabilities(
        viewRetailerOverview: true,
        viewShops: false, // hidden
        viewStaff: true,
        manageStaff: true,
        assignStaffShops: true,
        viewAssignedProducts: true,
        submitReceipts: true,
      );
      final visible = RetailerOwnerNavigation.model
          .visibleDestinations(caps)
          .map((RoleDestination d) => d.label)
          .toList();
      expect(visible, isNot(contains('Shops')));
      expect(visible, containsAll(<String>['Overview', 'Staff', 'Products']));
    });

    test('an empty capability block never empties the shell', () {
      // A backend inconsistency (or a Vendor context, which carries none) must
      // fall back to the full list rather than a shell with no destinations.
      final visible = RetailerOwnerNavigation.model.visibleDestinations(
        RetailerCapabilities.none,
      );
      expect(visible, RetailerOwnerNavigation.model.destinations);
    });

    test('all-false but non-empty still never returns an empty list', () {
      // Guard the pathological case directly: even if every mapped capability
      // were false, the shell keeps its destinations.
      final visible = RetailerManagerNavigation.model.visibleDestinations(
        const RetailerCapabilities(viewRetailerOverview: true),
      );
      expect(visible, isNotEmpty);
    });
  });
}
