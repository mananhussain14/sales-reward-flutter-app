import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/shells/vendor/vendor_navigation.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/domain/repositories/portal_context_repository.dart';
import 'package:sale_reward/features/retailers/domain/entities/retailer_owner_state.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_detail.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_lifecycle_status.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_manage_capability.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_status.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_summary.dart';
import 'package:sale_reward/features/retailers/domain/repositories/vendor_retailer_write_result.dart';
import 'package:sale_reward/features/retailers/presentation/vendor/widgets/vendor_retailer_lifecycle_copy.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';
import '../../support/vendor_retailer_fakes.dart';
import '../../support/vendor_retailer_lifecycle_fakes.dart';

/// Drives the Vendor Retailer lifecycle control through the real application:
/// real router, real shell, real cubits, over fakes that never touch Supabase.

/// The organization id `resolvedResult(vendorSuperAdmin)` resolves to. Stated
/// here so a test can prove the capability probe was pointed at the **session's**
/// Vendor rather than at a Retailer.
const String sessionVendorOrganizationId =
    '11111111-1111-1111-1111-111111111111';

/// A **second** Vendor organization, so a `Vendor A -> Vendor B` switch is a
/// genuine change of identity rather than two states that compare equal.
const String secondVendorOrganizationId =
    '33333333-3333-3333-3333-333333333333';

Future<void> goTo(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Navigator).first)).go(location);
  await tester.pumpAndSettle();
}

/// A detail row holding one synchronized lifecycle pair.
VendorRetailerDetail detailWith(VendorRetailerStatus status) =>
    VendorRetailerDetail(
      relationshipId: northwindRelationshipUuid,
      retailerOrganizationId: northwindOrganizationUuid,
      retailerName: 'Northwind Retail',
      retailerStatus: status,
      countryCode: 'AE',
      defaultCurrency: 'AED',
      relationshipStatus: status,
      relationshipCreatedAt: northwindOnboardedAt,
      shopCount: 4,
      activeShopCount: 3,
      ownerState: RetailerOwnerState.active,
    );

/// A detail row whose two statuses disagree — a state this operation cannot
/// have created, and which the RPC refuses with 55000.
VendorRetailerDetail mismatchedDetail({
  required VendorRetailerStatus retailer,
  required VendorRetailerStatus relationship,
}) => VendorRetailerDetail(
  relationshipId: northwindRelationshipUuid,
  retailerOrganizationId: northwindOrganizationUuid,
  retailerName: 'Northwind Retail',
  retailerStatus: retailer,
  countryCode: 'AE',
  defaultCurrency: 'AED',
  relationshipStatus: relationship,
  relationshipCreatedAt: northwindOnboardedAt,
  shopCount: 4,
  activeShopCount: 3,
  ownerState: RetailerOwnerState.active,
);

void main() {
  late FakeVendorRetailerRepository retailers;
  late FakeVendorRetailerLifecycleRepository lifecycle;

  setUp(() {
    retailers = FakeVendorRetailerRepository();
    lifecycle = FakeVendorRetailerLifecycleRepository();
  });

  /// Signs in as a Vendor Super Admin and opens one Retailer's detail screen.
  Future<PumpedApp> onDetail(
    WidgetTester tester, {
    VendorRetailerDetail? detail,
    Size surface = phoneSurface,
  }) async {
    if (detail != null) {
      retailers.knownDetails = <String, VendorRetailerDetail>{
        detail.relationshipId: detail,
      };
    }
    final PumpedApp app = await pumpAppInRole(
      tester,
      PortalKind.vendorSuperAdmin,
      surface: surface,
      retailers: retailers,
      retailerLifecycle: lifecycle,
    );
    await goTo(
      tester,
      VendorNavigation.retailerDetailPath(northwindRelationshipUuid),
    );
    return app;
  }

  /// Scrolls the lifecycle button into view and taps it.
  ///
  /// The detail screen is a long scrolling page, so the control is not
  /// hit-testable until it has been brought on screen — which is exactly what a
  /// person does before pressing it.
  Future<void> tapAction(WidgetTester tester, String label) async {
    final Finder button = find.text(label);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  /// Confirms the dialog the action opens.
  ///
  /// Scoped to the [AlertDialog] because the page's own action button carries
  /// the same label — which is deliberate, and is why the dialog's primary
  /// action must be addressed inside the dialog rather than by its text alone.
  /// Set [settle] to false when the write is deliberately left pending: the
  /// button's progress spinner animates indefinitely by design, so
  /// `pumpAndSettle` would time out rather than fail meaningfully.
  Future<void> confirmDialog(
    WidgetTester tester,
    String label, {
    bool settle = true,
  }) async {
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text(label)),
    );
    if (settle) {
      await tester.pumpAndSettle();
      return;
    }
    // Enough frames to dismiss the dialog and render the pending state.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('when the control is offered', () {
    testWidgets(
      '69. a confirmed capability and an ACTIVE pair show Deactivate',
      (WidgetTester tester) async {
        await onDetail(tester, detail: detailWith(VendorRetailerStatus.active));

        expect(
          find.text(VendorRetailerLifecycleCopy.deactivate),
          findsOneWidget,
        );
        expect(find.text(VendorRetailerLifecycleCopy.reactivate), findsNothing);
        expect(
          find.text(VendorRetailerLifecycleCopy.sectionTitle),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '70. a confirmed capability and a SUSPENDED pair show Reactivate',
      (WidgetTester tester) async {
        await onDetail(
          tester,
          detail: detailWith(VendorRetailerStatus.suspended),
        );

        expect(
          find.text(VendorRetailerLifecycleCopy.reactivate),
          findsOneWidget,
        );
        expect(find.text(VendorRetailerLifecycleCopy.deactivate), findsNothing);
      },
    );

    testWidgets('59. the probe is pointed at the session Vendor organization', (
      WidgetTester tester,
    ) async {
      await onDetail(tester, detail: detailWith(VendorRetailerStatus.active));

      expect(lifecycle.capabilityOrganizationIds, <String>[
        sessionVendorOrganizationId,
      ]);
      // Never the Retailer's organization, and never the relationship id.
      expect(
        lifecycle.capabilityOrganizationIds,
        isNot(contains(northwindOrganizationUuid)),
      );
      expect(
        lifecycle.capabilityOrganizationIds,
        isNot(contains(northwindRelationshipUuid)),
      );
    });
  });

  group('when the control is hidden', () {
    testWidgets('71. a denied capability shows no action', (
      WidgetTester tester,
    ) async {
      lifecycle.capabilityResult = VendorRetailerManageCapability.denied;

      await onDetail(tester, detail: detailWith(VendorRetailerStatus.active));

      expect(find.text(VendorRetailerLifecycleCopy.deactivate), findsNothing);
      expect(find.text(VendorRetailerLifecycleCopy.reactivate), findsNothing);
      // Not a disabled button either — that would still advertise that the
      // operation exists.
      expect(find.text(VendorRetailerLifecycleCopy.sectionTitle), findsNothing);
    });

    testWidgets('72. an unavailable capability shows no action', (
      WidgetTester tester,
    ) async {
      lifecycle.capabilityResult = VendorRetailerManageCapability.unavailable;

      await onDetail(tester, detail: detailWith(VendorRetailerStatus.active));

      expect(find.text(VendorRetailerLifecycleCopy.sectionTitle), findsNothing);
    });

    testWidgets('73. a mismatched pair shows no action, in both directions', (
      WidgetTester tester,
    ) async {
      await onDetail(
        tester,
        detail: mismatchedDetail(
          retailer: VendorRetailerStatus.active,
          relationship: VendorRetailerStatus.suspended,
        ),
      );

      expect(find.text(VendorRetailerLifecycleCopy.sectionTitle), findsNothing);
    });

    testWidgets('74. a DEACTIVATED row shows no action', (
      WidgetTester tester,
    ) async {
      await onDetail(
        tester,
        detail: detailWith(VendorRetailerStatus.deactivated),
      );

      expect(find.text(VendorRetailerLifecycleCopy.sectionTitle), findsNothing);
    });

    testWidgets('an unknown status shows no action', (
      WidgetTester tester,
    ) async {
      await onDetail(tester, detail: detailWith(VendorRetailerStatus.unknown));

      expect(find.text(VendorRetailerLifecycleCopy.sectionTitle), findsNothing);
    });

    testWidgets('the control stays hidden while the probe is in flight', (
      WidgetTester tester,
    ) async {
      lifecycle.manualCapability = true;

      await onDetail(tester, detail: detailWith(VendorRetailerStatus.active));

      expect(find.text(VendorRetailerLifecycleCopy.sectionTitle), findsNothing);

      lifecycle.completeCapability(VendorRetailerManageCapability.confirmed);
      await tester.pumpAndSettle();

      expect(find.text(VendorRetailerLifecycleCopy.deactivate), findsOneWidget);
    });
  });

  group('the confirmation dialog', () {
    testWidgets('81. states every deactivation consequence and preservation', (
      WidgetTester tester,
    ) async {
      await onDetail(tester, detail: detailWith(VendorRetailerStatus.active));

      await tapAction(tester, VendorRetailerLifecycleCopy.deactivate);

      expect(
        find.text(
          '${VendorRetailerLifecycleCopy.deactivateConfirmTitle}\n'
          'Northwind Retail',
        ),
        findsOneWidget,
      );

      final String body = VendorRetailerLifecycleCopy.deactivateConfirmBody;
      expect(body, contains('Retailer Owner, Manager and Sales Staff'));
      expect(body, contains('already signed in are blocked'));
      expect(body, contains('not signed out'));
      expect(body, contains('Receipt submission stops'));
      expect(
        body,
        contains('Shop creation, product assignment and invitation'),
      );
      expect(
        body,
        contains(
          'Existing users, Shops, assignments, receipts and invitations are '
          'preserved',
        ),
      );
      expect(body, contains('Reactivating restores prior access'));
      // Nothing is destroyed by this write. The body says so outright, and
      // never the reverse — no clause may claim that anything is deleted,
      // removed or erased.
      expect(body, contains('Nothing is deleted'));
      for (final String claim in <String>[
        'will be deleted',
        'are deleted',
        'will be removed',
        'are removed',
        'erase',
      ]) {
        expect(
          body.toLowerCase(),
          isNot(contains(claim.toLowerCase())),
          reason: 'the deactivation body must not claim "\$claim"',
        );
      }
      expect(find.text(body), findsOneWidget);
    });

    testWidgets('82. states every reactivation restoration', (
      WidgetTester tester,
    ) async {
      await onDetail(
        tester,
        detail: detailWith(VendorRetailerStatus.suspended),
      );

      await tapAction(tester, VendorRetailerLifecycleCopy.reactivate);

      final String body = VendorRetailerLifecycleCopy.reactivateConfirmBody;
      expect(body, contains('users, roles, Shops and assignments'));
      expect(body, contains('valid and unexpired become usable'));
      expect(body, contains('Receipt access resumes'));
      expect(find.text(body), findsOneWidget);
    });

    testWidgets('83. the Retailer name is display only and no id is shown', (
      WidgetTester tester,
    ) async {
      await onDetail(tester, detail: detailWith(VendorRetailerStatus.active));

      await tapAction(tester, VendorRetailerLifecycleCopy.deactivate);

      expect(find.textContaining('Northwind Retail'), findsWidgets);
      expect(find.textContaining(northwindRelationshipUuid), findsNothing);
      expect(find.textContaining(northwindOrganizationUuid), findsNothing);

      await confirmDialog(tester, VendorRetailerLifecycleCopy.deactivate);

      // The name is never sent: the write carries an id and a status token.
      expect(lifecycle.writes.single.relationshipId, northwindRelationshipUuid);
    });

    testWidgets('cancelling writes nothing at all', (
      WidgetTester tester,
    ) async {
      await onDetail(tester, detail: detailWith(VendorRetailerStatus.active));

      await tapAction(tester, VendorRetailerLifecycleCopy.deactivate);
      await confirmDialog(tester, VendorRetailerLifecycleCopy.cancel);

      expect(lifecycle.writeCallCount, 0);
      // And the badge is untouched.
      expect(find.text('Relationship: Active'), findsOneWidget);
    });

    testWidgets('the body scrolls, so it stays readable on a small phone', (
      WidgetTester tester,
    ) async {
      await onDetail(
        tester,
        detail: detailWith(VendorRetailerStatus.active),
        surface: smallPhoneSurface,
      );

      await tapAction(tester, VendorRetailerLifecycleCopy.deactivate);

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('submitting', () {
    testWidgets('the confirmed direction is what reaches the repository', (
      WidgetTester tester,
    ) async {
      await onDetail(tester, detail: detailWith(VendorRetailerStatus.active));

      await tapAction(tester, VendorRetailerLifecycleCopy.deactivate);
      await confirmDialog(tester, VendorRetailerLifecycleCopy.deactivate);

      expect(lifecycle.writeCallCount, 1);
      expect(
        lifecycle.writes.single.status,
        VendorRetailerLifecycleStatus.suspended,
      );
    });

    testWidgets('a reactivation requests ACTIVE', (WidgetTester tester) async {
      lifecycle.writeResult = const VendorRetailerWriteSuccess(
        confirmedStatus: VendorRetailerLifecycleStatus.active,
        statusChanged: true,
      );
      await onDetail(
        tester,
        detail: detailWith(VendorRetailerStatus.suspended),
      );

      await tapAction(tester, VendorRetailerLifecycleCopy.reactivate);
      await confirmDialog(tester, VendorRetailerLifecycleCopy.reactivate);

      expect(
        lifecycle.writes.single.status,
        VendorRetailerLifecycleStatus.active,
      );
    });

    testWidgets('75. a pending request disables duplicate submission', (
      WidgetTester tester,
    ) async {
      lifecycle.manualWrite = true;
      await onDetail(tester, detail: detailWith(VendorRetailerStatus.active));

      await tapAction(tester, VendorRetailerLifecycleCopy.deactivate);
      await confirmDialog(
        tester,
        VendorRetailerLifecycleCopy.deactivate,
        settle: false,
      );

      // The button now shows progress and is not hit-testable as the action.
      expect(
        find.text(VendorRetailerLifecycleCopy.deactivating),
        findsOneWidget,
      );
      expect(find.text(VendorRetailerLifecycleCopy.deactivate), findsNothing);
      expect(lifecycle.writeCallCount, 1);

      lifecycle.completeWrite();
      await tester.pumpAndSettle();

      expect(lifecycle.writeCallCount, 1);
    });

    testWidgets('76. the badge does not change while the write is in flight', (
      WidgetTester tester,
    ) async {
      lifecycle.manualWrite = true;
      await onDetail(tester, detail: detailWith(VendorRetailerStatus.active));

      await tapAction(tester, VendorRetailerLifecycleCopy.deactivate);
      await confirmDialog(
        tester,
        VendorRetailerLifecycleCopy.deactivate,
        settle: false,
      );

      // Nothing is optimistic: the statuses are still what the canonical read
      // returned.
      expect(find.text('Relationship: Active'), findsOneWidget);
      expect(find.text('Retailer: Active'), findsOneWidget);

      lifecycle.completeWrite();
      await tester.pumpAndSettle();
    });

    testWidgets('77. a committed change shows the success notice and re-reads', (
      WidgetTester tester,
    ) async {
      // The canonical re-read is what moves the badge, so the fake must answer
      // with the new pair.
      await onDetail(tester, detail: detailWith(VendorRetailerStatus.active));
      final int readsBefore = retailers.detailCallCount;
      retailers.knownDetails = <String, VendorRetailerDetail>{
        northwindRelationshipUuid: detailWith(VendorRetailerStatus.suspended),
      };

      await tapAction(tester, VendorRetailerLifecycleCopy.deactivate);
      await confirmDialog(tester, VendorRetailerLifecycleCopy.deactivate);

      expect(
        find.text(VendorRetailerLifecycleCopy.deactivatedTitle),
        findsOneWidget,
      );
      // The canonical detail was re-read, and the badge follows it.
      expect(retailers.detailCallCount, readsBefore + 1);
      expect(find.text('Relationship: Inactive'), findsOneWidget);
      // And the action now offers the opposite direction.
      expect(find.text(VendorRetailerLifecycleCopy.reactivate), findsOneWidget);
    });

    testWidgets('an idempotent no-op says so rather than claiming a change', (
      WidgetTester tester,
    ) async {
      lifecycle.writeResult = const VendorRetailerWriteSuccess(
        confirmedStatus: VendorRetailerLifecycleStatus.suspended,
        statusChanged: false,
      );
      await onDetail(tester, detail: detailWith(VendorRetailerStatus.active));

      await tapAction(tester, VendorRetailerLifecycleCopy.deactivate);
      await confirmDialog(tester, VendorRetailerLifecycleCopy.deactivate);

      expect(
        find.text(VendorRetailerLifecycleCopy.alreadyInactiveTitle),
        findsOneWidget,
      );
      expect(
        find.text(VendorRetailerLifecycleCopy.deactivatedTitle),
        findsNothing,
      );
    });

    testWidgets('78. an unconfirmed write shows the safe copy and no retry', (
      WidgetTester tester,
    ) async {
      lifecycle.writeResult = const VendorRetailerWriteUnconfirmed();
      await onDetail(tester, detail: detailWith(VendorRetailerStatus.active));

      await tapAction(tester, VendorRetailerLifecycleCopy.deactivate);
      await confirmDialog(tester, VendorRetailerLifecycleCopy.deactivate);

      expect(
        find.text(VendorRetailerLifecycleCopy.unconfirmedTitle),
        findsOneWidget,
      );
      expect(
        find.text(VendorRetailerLifecycleCopy.unconfirmedBody),
        findsOneWidget,
      );
      // It must never invite another attempt at a committed write.
      final String copy =
          '${VendorRetailerLifecycleCopy.unconfirmedTitle} '
          '${VendorRetailerLifecycleCopy.unconfirmedBody}';
      expect(copy.toLowerCase(), isNot(contains('try again')));
      expect(copy.toLowerCase(), isNot(contains('retry')));
      expect(copy.toLowerCase(), isNot(contains('resubmit')));
      expect(lifecycle.writeCallCount, 1);
    });

    testWidgets('79. a 55000 refusal shows generic copy and discloses nothing', (
      WidgetTester tester,
    ) async {
      lifecycle.writeResult = refusedLifecycleWrite(const NotReadyFailure());
      await onDetail(tester, detail: detailWith(VendorRetailerStatus.active));

      await tapAction(tester, VendorRetailerLifecycleCopy.deactivate);
      await confirmDialog(tester, VendorRetailerLifecycleCopy.deactivate);

      expect(
        find.text(VendorRetailerLifecycleCopy.notReadyBody),
        findsOneWidget,
      );

      // The multi-Vendor cause must not be disclosed, nor any other of the four
      // that share this SQLSTATE.
      final String copy =
          '${VendorRetailerLifecycleCopy.notReadyTitle} '
          '${VendorRetailerLifecycleCopy.notReadyBody}';
      for (final String forbidden in <String>[
        'another Vendor',
        'other Vendor',
        'multi',
        'DEACTIVATED',
        'mismatch',
        'inconsistent',
        '55000',
      ]) {
        expect(
          copy.toLowerCase(),
          isNot(contains(forbidden.toLowerCase())),
          reason: 'the 55000 copy must not mention "$forbidden"',
        );
      }
      // The statuses on screen are untouched: nothing was written.
      expect(find.text('Relationship: Active'), findsOneWidget);
    });

    testWidgets('80. no UUID, SQLSTATE or backend message is ever rendered', (
      WidgetTester tester,
    ) async {
      lifecycle.writeResult = refusedLifecycleWrite(const DeniedFailure());
      await onDetail(tester, detail: detailWith(VendorRetailerStatus.active));

      await tapAction(tester, VendorRetailerLifecycleCopy.deactivate);
      await confirmDialog(tester, VendorRetailerLifecycleCopy.deactivate);

      final Iterable<String> rendered = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? '')
          .toList();

      for (final String text in rendered) {
        expect(text, isNot(contains(northwindRelationshipUuid)));
        expect(text, isNot(contains(northwindOrganizationUuid)));
        for (final String forbidden in <String>[
          '42501',
          '23514',
          '55000',
          '22P02',
          'vendor_retailers',
          'organizations',
          'PostgrestException',
          'RETAILERS_MANAGE',
        ]) {
          expect(
            text,
            isNot(contains(forbidden)),
            reason: '"$text" leaks $forbidden',
          );
        }
      }
    });

    testWidgets('a failed write leaves the action offered again', (
      WidgetTester tester,
    ) async {
      lifecycle.writeResult = refusedLifecycleWrite(const UnavailableFailure());
      await onDetail(tester, detail: detailWith(VendorRetailerStatus.active));

      await tapAction(tester, VendorRetailerLifecycleCopy.deactivate);
      await confirmDialog(tester, VendorRetailerLifecycleCopy.deactivate);

      // Nothing was written, so another attempt is legitimate — but nothing
      // made it automatically.
      expect(find.text(VendorRetailerLifecycleCopy.deactivate), findsOneWidget);
      expect(lifecycle.writeCallCount, 1);
    });
  });

  group('scope', () {
    testWidgets('84. the Retailer list carries no lifecycle action', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
        retailers: retailers,
        retailerLifecycle: lifecycle,
      );
      await goTo(tester, VendorNavigation.retailers);

      expect(find.text(VendorRetailerLifecycleCopy.deactivate), findsNothing);
      expect(find.text(VendorRetailerLifecycleCopy.reactivate), findsNothing);
      expect(find.text(VendorRetailerLifecycleCopy.sectionTitle), findsNothing);
    });

    testWidgets('100. the detail page is the only lifecycle surface', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
        retailers: retailers,
        retailerLifecycle: lifecycle,
      );

      for (final String location in <String>[
        VendorNavigation.dashboard,
        VendorNavigation.retailers,
        VendorNavigation.users,
        VendorNavigation.roles,
        VendorNavigation.products,
      ]) {
        await goTo(tester, location);
        expect(
          find.text(VendorRetailerLifecycleCopy.sectionTitle),
          findsNothing,
          reason: '$location must carry no lifecycle control',
        );
      }
    });

    testWidgets('85. the control does not overflow a narrow layout', (
      WidgetTester tester,
    ) async {
      await onDetail(
        tester,
        detail: detailWith(VendorRetailerStatus.active),
        surface: smallPhoneSurface,
      );

      expect(find.text(VendorRetailerLifecycleCopy.deactivate), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('terminology on screen', () {
    testWidgets('86. a SUSPENDED Vendor Retailer badge reads Inactive', (
      WidgetTester tester,
    ) async {
      await onDetail(
        tester,
        detail: detailWith(VendorRetailerStatus.suspended),
      );

      expect(find.text('Relationship: Inactive'), findsOneWidget);
      expect(find.text('Retailer: Inactive'), findsOneWidget);
    });

    testWidgets('87. a DEACTIVATED badge still reads Deactivated', (
      WidgetTester tester,
    ) async {
      await onDetail(
        tester,
        detail: detailWith(VendorRetailerStatus.deactivated),
      );

      expect(find.text('Relationship: Deactivated'), findsOneWidget);
      expect(find.text('Retailer: Deactivated'), findsOneWidget);
    });

    testWidgets('88. no Vendor Retailer surface says Suspended', (
      WidgetTester tester,
    ) async {
      // The directory carries a SUSPENDED relationship in its fixtures.
      await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
        retailers: retailers,
        retailerLifecycle: lifecycle,
      );
      await goTo(tester, VendorNavigation.retailers);

      expect(find.textContaining('Suspended'), findsNothing);
      expect(find.textContaining('Inactive'), findsWidgets);

      await goTo(
        tester,
        VendorNavigation.retailerDetailPath(contosoRelationshipUuid),
      );
      expect(find.textContaining('Suspended'), findsNothing);
    });

    testWidgets('a SUSPENDED summary is still listed, not hidden', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(
        tester,
        PortalKind.vendorSuperAdmin,
        retailers: retailers,
        retailerLifecycle: lifecycle,
      );
      await goTo(tester, VendorNavigation.retailers);

      final VendorRetailerSummary suspended = contosoSummary;
      expect(find.text(suspended.retailerName), findsOneWidget);
    });
  });

  group('session isolation', () {
    testWidgets('90. the capability is re-probed for the next Vendor', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onDetail(
        tester,
        detail: detailWith(VendorRetailerStatus.active),
      );
      expect(lifecycle.capabilityOrganizationIds, <String>[
        sessionVendorOrganizationId,
      ]);
      expect(find.text(VendorRetailerLifecycleCopy.deactivate), findsOneWidget);

      // A different administrator, in a different Vendor organization. The
      // shell's identity listener clears every cubit and re-probes under the new
      // caller — it must never carry the previous `confirmed` across.
      lifecycle.capabilityResult = VendorRetailerManageCapability.denied;
      app.portal.result = PortalContextResolved(
        contextFor(
          PortalKind.vendorSuperAdmin,
          organizationId: secondVendorOrganizationId,
        ),
      );
      app.auth.emitSignedIn(
        const AuthUser(id: 'user-2', email: 'pat@example.com'),
      );
      await tester.pumpAndSettle();

      // Probed again, against the NEW organization.
      expect(lifecycle.capabilityOrganizationIds, <String>[
        sessionVendorOrganizationId,
        secondVendorOrganizationId,
      ]);
      // And the control is gone, because the new caller was denied.
      expect(find.text(VendorRetailerLifecycleCopy.deactivate), findsNothing);
    });

    testWidgets('89. a pending decision does not survive a user change', (
      WidgetTester tester,
    ) async {
      lifecycle.manualWrite = true;
      final PumpedApp app = await onDetail(
        tester,
        detail: detailWith(VendorRetailerStatus.active),
      );

      await tapAction(tester, VendorRetailerLifecycleCopy.deactivate);
      await confirmDialog(
        tester,
        VendorRetailerLifecycleCopy.deactivate,
        settle: false,
      );
      expect(lifecycle.pendingWriteCount, 1);

      app.portal.result = PortalContextResolved(
        contextFor(
          PortalKind.vendorSuperAdmin,
          organizationId: secondVendorOrganizationId,
        ),
      );
      app.auth.emitSignedIn(
        const AuthUser(id: 'user-2', email: 'pat@example.com'),
      );
      await tester.pumpAndSettle();

      // The previous Vendor's answer lands after the switch. It must not leave
      // a "Retailer deactivated" acknowledgement over the new session.
      lifecycle.completeWrite();
      await tester.pumpAndSettle();

      expect(
        find.text(VendorRetailerLifecycleCopy.deactivatedTitle),
        findsNothing,
      );
      expect(lifecycle.writeCallCount, 1);
    });
  });
}
