import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/shells/retailer_manager/retailer_manager_navigation.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_navigation.dart';
import 'package:sale_reward/app/shells/sales_staff/sales_staff_navigation.dart';
import 'package:sale_reward/app/shells/vendor/vendor_navigation.dart';
import 'package:sale_reward/core/errors/retailer_read_problem.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_assignable_shop.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_invitation_outcome.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_invitation_role.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_staff_invitation_repository.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_staff_repository.dart';
import 'package:sale_reward/features/staff/presentation/retailer/cubit/retailer_invite_staff_cubit.dart';
import 'package:sale_reward/features/staff/presentation/retailer/widgets/retailer_invite_staff_copy.dart';
import 'package:sale_reward/features/staff/presentation/retailer/widgets/retailer_invite_staff_form.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';
import '../../support/retailer_invite_staff_fakes.dart';
import '../../support/retailer_read_fakes.dart';

/// The Invite Staff form, driven through the real application: real router,
/// real shells, real cubits, over fakes that never touch Supabase.
/// A second Retailer Owner, so a session switch is a genuine change of person
/// rather than the same identity re-emitted.
const AuthUser otherUser = AuthUser(id: 'user-2', email: 'b@example.com');

void main() {
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> goTo(WidgetTester tester, String location) async {
    GoRouter.of(tester.element(find.byType(Navigator).first)).go(location);
    await tester.pumpAndSettle();
  }

  Finder semanticsContaining(String fragment) => find.byWidgetPredicate(
    (Widget widget) =>
        widget is Semantics &&
        (widget.properties.label?.contains(fragment) ?? false),
    description: 'Semantics whose label contains "$fragment"',
  );

  Future<PumpedApp> onOwnerStaff(
    WidgetTester tester, {
    FakeRetailerStaffInvitationRepository? invitations,
    FakeRetailerStaffRepository? staff,
    Size surface = phoneSurface,
  }) async {
    final PumpedApp app = await pumpAppInRole(
      tester,
      PortalKind.retailerOwner,
      surface: surface,
      retailerStaff: staff,
      retailerStaffInvitations: invitations,
    );
    await goTo(tester, RetailerOwnerNavigation.staff);
    return app;
  }

  /// Addresses one of the form's three text controls by its visible label.
  Finder fieldNamed(String label) => find.descendant(
    of: find.ancestor(
      of: find.textContaining(label),
      matching: find.byType(SrTextField),
    ),
    matching: find.byType(TextField),
  );

  Future<void> typeInvitation(
    WidgetTester tester, {
    String firstName = 'Priya',
    String lastName = 'Raman',
    String email = 'priya@example.com',
  }) async {
    await tester.enterText(
      fieldNamed(RetailerInviteStaffCopy.firstNameLabel),
      firstName,
    );
    await tester.enterText(
      fieldNamed(RetailerInviteStaffCopy.lastNameLabel),
      lastName,
    );
    await tester.enterText(
      fieldNamed(RetailerInviteStaffCopy.emailLabel),
      email,
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseRole(
    WidgetTester tester,
    RetailerStaffInvitationRole role,
  ) async {
    await tapVisible(tester, find.widgetWithText(SrButton, role.label).last);
  }

  /// Taps a control after scrolling it into view, then pumps a single frame —
  /// so a state that only exists while a request is in flight is observable.
  Future<void> tapAndPumpOnce(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    await tapVisible(
      tester,
      find.widgetWithText(SrButton, RetailerInviteStaffCopy.submit),
    );
  }

  // -------------------------------------------------------------------------
  group('who sees the form', () {
    testWidgets('the Retailer Owner does', (WidgetTester tester) async {
      await onOwnerStaff(tester);

      expect(find.byType(RetailerInviteStaffForm), findsOneWidget);
      expect(find.text(RetailerInviteStaffCopy.title), findsOneWidget);
    });

    testWidgets('a Retailer Manager does not', (WidgetTester tester) async {
      await pumpAppInRole(tester, PortalKind.retailerManager);
      await goTo(tester, RetailerManagerNavigation.staff);

      expect(find.byType(RetailerInviteStaffForm), findsNothing);
      expect(find.text(RetailerInviteStaffCopy.submit), findsNothing);
    });

    testWidgets('Sales Staff does not', (WidgetTester tester) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);
      await goTo(tester, SalesStaffNavigation.submit);

      expect(find.byType(RetailerInviteStaffForm), findsNothing);
      expect(find.text(RetailerInviteStaffCopy.submit), findsNothing);
    });

    testWidgets('a Vendor does not', (WidgetTester tester) async {
      await pumpAppInRole(tester, PortalKind.vendorSuperAdmin);
      await goTo(tester, VendorNavigation.dashboard);

      expect(find.byType(RetailerInviteStaffForm), findsNothing);
      expect(find.text(RetailerInviteStaffCopy.submit), findsNothing);
    });

    testWidgets('the Manager shell provides no invitation cubit at all', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerManager);
      await goTo(tester, RetailerManagerNavigation.staff);

      // Not merely hidden — the machinery is absent from the subtree, so the
      // form could not be rendered there even by mistake.
      expect(find.byType(BlocProvider<RetailerInviteStaffCubit>), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('role and shops', () {
    testWidgets('no role is chosen by default', (WidgetTester tester) async {
      final PumpedApp app = await onOwnerStaff(tester);

      expect(
        find.textContaining(RetailerInviteStaffCopy.shopsLabel),
        findsNothing,
      );
      expect(app.retailerStaffInvitations.shopCallCount, 0);
    });

    testWidgets('choosing Retailer Manager shows no shop selector', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onOwnerStaff(tester);

      await chooseRole(tester, RetailerStaffInvitationRole.retailerManager);

      expect(
        find.textContaining(RetailerInviteStaffCopy.shopsLabel),
        findsNothing,
      );
      // Not read at all: a Manager invitation has no shop to assign.
      expect(app.retailerStaffInvitations.shopCallCount, 0);
    });

    testWidgets('choosing Sales Staff shows the shop selector', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onOwnerStaff(tester);

      await chooseRole(tester, RetailerStaffInvitationRole.salesStaff);

      expect(
        find.textContaining(RetailerInviteStaffCopy.shopsLabel),
        findsOneWidget,
      );
      expect(app.retailerStaffInvitations.shopCallCount, 1);
      expect(find.text('Northwind Marina'), findsWidgets);
    });

    testWidgets('the picker shows a loading state while it reads', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffInvitationRepository repo =
          FakeRetailerStaffInvitationRepository()..manualShops = true;
      await onOwnerStaff(tester, invitations: repo);

      await tapAndPumpOnce(
        tester,
        find
            .widgetWithText(
              SrButton,
              RetailerStaffInvitationRole.salesStaff.label,
            )
            .last,
      );

      expect(find.text(RetailerInviteStaffCopy.shopsLoading), findsOneWidget);

      repo.completeShops();
      await tester.pumpAndSettle();
      expect(find.text(RetailerInviteStaffCopy.shopsLoading), findsNothing);
    });

    testWidgets('an empty estate is not shown as a refusal', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffInvitationRepository repo =
          FakeRetailerStaffInvitationRepository()
            ..nextShops = const <RetailerAssignableShop>[];
      await onOwnerStaff(tester, invitations: repo);

      await chooseRole(tester, RetailerStaffInvitationRole.salesStaff);

      expect(
        find.text(RetailerInviteStaffCopy.shopsEmptyTitle),
        findsOneWidget,
      );
      expect(find.text(RetailerInviteStaffCopy.shopsRetry), findsNothing);
    });

    testWidgets('a refusal is not shown as an empty estate', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffInvitationRepository repo =
          FakeRetailerStaffInvitationRepository()
            ..shopsResult = const RetailerAssignableShopsFailed(
              RetailerReadProblem.denied,
            );
      await onOwnerStaff(tester, invitations: repo);

      await chooseRole(tester, RetailerStaffInvitationRole.salesStaff);

      expect(
        find.text(RetailerInviteStaffCopy.shopsUnavailableTitle),
        findsOneWidget,
      );
      expect(find.text(RetailerInviteStaffCopy.shopsEmptyTitle), findsNothing);
      expect(
        find.text(RetailerInviteStaffCopy.shopsDeniedBody),
        findsOneWidget,
      );
    });

    testWidgets('a failure offers a retry that re-reads', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffInvitationRepository repo =
          FakeRetailerStaffInvitationRepository()
            ..shopsResult = const RetailerAssignableShopsFailed(
              RetailerReadProblem.network,
            );
      await onOwnerStaff(tester, invitations: repo);

      await chooseRole(tester, RetailerStaffInvitationRole.salesStaff);
      expect(repo.shopCallCount, 1);

      repo.shopsResult = null;
      await tapVisible(tester, find.text(RetailerInviteStaffCopy.shopsRetry));

      expect(repo.shopCallCount, 2);
      expect(find.text('Northwind Marina'), findsWidgets);
    });

    testWidgets('a malformed list is not reported as a connection problem', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffInvitationRepository repo =
          FakeRetailerStaffInvitationRepository()
            ..shopsResult = const RetailerAssignableShopsFailed(
              RetailerReadProblem.malformed,
            );
      await onOwnerStaff(tester, invitations: repo);

      await chooseRole(tester, RetailerStaffInvitationRole.salesStaff);

      expect(
        find.text(
          RetailerInviteStaffCopy.shopsProblemBody(
            RetailerReadProblem.malformed,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          RetailerInviteStaffCopy.shopsProblemBody(RetailerReadProblem.network),
        ),
        findsNothing,
      );
    });

    testWidgets('no shop id is ever rendered', (WidgetTester tester) async {
      await onOwnerStaff(tester);
      await chooseRole(tester, RetailerStaffInvitationRole.salesStaff);

      for (final String id in <String>[
        northwindMarinaId,
        northwindDowntownId,
        northwindWarehouseId,
      ]) {
        expect(find.textContaining(id), findsNothing, reason: id);
        expect(semanticsContaining(id), findsNothing, reason: id);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('validation', () {
    testWidgets('an empty form is refused without sending', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onOwnerStaff(tester);

      await submit(tester);

      expect(app.retailerStaffInvitations.sendCallCount, 0);
      expect(find.text('Enter their first name.'), findsOneWidget);
      expect(find.text('Enter their last name.'), findsOneWidget);
      expect(find.text('Enter their email address.'), findsOneWidget);
      expect(find.text('Choose a role for this person.'), findsOneWidget);
    });

    testWidgets('an invalid email is blocked', (WidgetTester tester) async {
      final PumpedApp app = await onOwnerStaff(tester);

      await typeInvitation(tester, email: 'not-an-address');
      await chooseRole(tester, RetailerStaffInvitationRole.retailerManager);
      await submit(tester);

      expect(app.retailerStaffInvitations.sendCallCount, 0);
      expect(
        find.text('Enter a valid email address, like name@example.com.'),
        findsOneWidget,
      );
    });

    testWidgets('Sales Staff with no shop is blocked', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onOwnerStaff(tester);

      await typeInvitation(tester);
      await chooseRole(tester, RetailerStaffInvitationRole.salesStaff);
      await submit(tester);

      expect(app.retailerStaffInvitations.sendCallCount, 0);
      expect(
        find.text(RetailerInviteStaffCopy.shopsRequiredMessage),
        findsWidgets,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('submission', () {
    testWidgets('a Manager invitation sends, clears and re-reads history', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffRepository staff = FakeRetailerStaffRepository();
      final PumpedApp app = await onOwnerStaff(tester, staff: staff);

      await typeInvitation(tester);
      await chooseRole(tester, RetailerStaffInvitationRole.retailerManager);
      await submit(tester);

      expect(app.retailerStaffInvitations.sendCallCount, 1);
      expect(app.retailerStaffInvitations.sentRequests.single.shopIds, isEmpty);
      expect(
        find.text(
          RetailerInviteStaffCopy.noticeTitle(RetailerInviteStaffNotice.sent),
        ),
        findsOneWidget,
      );
      // The canonical re-read: the second call to the invitation history.
      expect(staff.invitationCallCount, 2);
      // The roster is left alone — sending creates no membership.
      expect(staff.memberCallCount, 1);
      // Cleared.
      expect(
        tester
            .widget<TextField>(
              fieldNamed(RetailerInviteStaffCopy.firstNameLabel),
            )
            .controller!
            .text,
        isEmpty,
      );
    });

    testWidgets('a Sales Staff invitation sends the ticked shops', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onOwnerStaff(tester);

      await typeInvitation(tester);
      await chooseRole(tester, RetailerStaffInvitationRole.salesStaff);
      await tapVisible(tester, find.text('Northwind Marina').first);
      await submit(tester);

      expect(app.retailerStaffInvitations.sentRequests.single.shopIds, <String>[
        northwindMarinaId,
      ]);
      expect(
        app.retailerStaffInvitations.sentRequests.single.role,
        RetailerStaffInvitationRole.salesStaff,
      );
    });

    testWidgets('the submit control shows progress and disables itself', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffInvitationRepository repo =
          FakeRetailerStaffInvitationRepository()..manualSend = true;
      await onOwnerStaff(tester, invitations: repo);

      await typeInvitation(tester);
      await chooseRole(tester, RetailerStaffInvitationRole.retailerManager);

      await tapAndPumpOnce(
        tester,
        find.widgetWithText(SrButton, RetailerInviteStaffCopy.submit),
      );

      expect(find.text(RetailerInviteStaffCopy.submitting), findsOneWidget);

      repo.completeSend();
      await tester.pumpAndSettle();
    });

    testWidgets('a double tap sends exactly one invitation', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffInvitationRepository repo =
          FakeRetailerStaffInvitationRepository()..manualSend = true;
      await onOwnerStaff(tester, invitations: repo);

      await typeInvitation(tester);
      await chooseRole(tester, RetailerStaffInvitationRole.retailerManager);

      // The label swaps to "Sending…" while the request is in flight, so the
      // second tap is aimed at the button widget itself rather than at its
      // text.
      final Finder button = find.byType(RetailerInviteStaffForm);
      final Finder submitControl = find.descendant(
        of: button,
        matching: find.widgetWithText(SrButton, RetailerInviteStaffCopy.submit),
      );
      await tapAndPumpOnce(tester, submitControl);

      // The second tap lands on the same coordinates while the request is in
      // flight. The button has disabled itself, and the cubit refuses a second
      // submission regardless.
      final Finder sendingControl = find.descendant(
        of: button,
        matching: find.widgetWithText(
          SrButton,
          RetailerInviteStaffCopy.submitting,
        ),
      );
      await tester.tap(sendingControl, warnIfMissed: false);
      await tester.pump();

      expect(repo.sendCallCount, 1);

      repo.completeSend();
      await tester.pumpAndSettle();
    });

    testWidgets('RESENT says the previous link is no longer current', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffInvitationRepository repo =
          FakeRetailerStaffInvitationRepository()..sendResult = resentAnswer;
      await onOwnerStaff(tester, invitations: repo);

      await typeInvitation(tester);
      await chooseRole(tester, RetailerStaffInvitationRole.retailerManager);
      await submit(tester);

      expect(
        find.textContaining('previous invitation link is no longer current'),
        findsOneWidget,
      );
    });

    testWidgets('the 202 partial success never claims the send failed', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffInvitationRepository repo =
          FakeRetailerStaffInvitationRepository()
            ..sendResult = unconfirmedAnswer;
      final FakeRetailerStaffRepository staff = FakeRetailerStaffRepository();
      await onOwnerStaff(tester, invitations: repo, staff: staff);

      await typeInvitation(tester);
      await chooseRole(tester, RetailerStaffInvitationRole.retailerManager);
      await submit(tester);

      expect(
        find.textContaining(
          'The email may have been sent, but the latest invitation status '
          'could not be confirmed.',
        ),
        findsOneWidget,
      );
      // Never a second write.
      expect(repo.sendCallCount, 1);
      // And the history is re-read, because it is the only authority.
      expect(staff.invitationCallCount, 2);
    });

    testWidgets('a delivery failure keeps the entered values on screen', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffInvitationRepository repo =
          FakeRetailerStaffInvitationRepository()
            ..sendResult = deliveryFailedAnswer;
      await onOwnerStaff(tester, invitations: repo);

      await typeInvitation(tester);
      await chooseRole(tester, RetailerStaffInvitationRole.retailerManager);
      await submit(tester);

      expect(
        find.text(
          RetailerInviteStaffCopy.noticeTitle(
            RetailerInviteStaffNotice.deliveryFailed,
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(fieldNamed(RetailerInviteStaffCopy.emailLabel))
            .controller!
            .text,
        'priya@example.com',
      );
      // The button is armed again for a deliberate retry, and nothing retried
      // on its own.
      expect(repo.sendCallCount, 1);
    });

    testWidgets('an invitation conflict gets its own notice', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffInvitationRepository repo =
          FakeRetailerStaffInvitationRepository()
            ..sendResult = notSentAnswer(
              RetailerStaffInvitationCode.invitationConflict,
            );
      await onOwnerStaff(tester, invitations: repo);

      await typeInvitation(tester);
      await chooseRole(tester, RetailerStaffInvitationRole.retailerManager);
      await submit(tester);

      expect(
        find.text(
          RetailerInviteStaffCopy.noticeTitle(
            RetailerInviteStaffNotice.invitationConflict,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a network failure is the only notice mentioning connection', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffInvitationRepository repo =
          FakeRetailerStaffInvitationRepository()
            ..sendResult = const RetailerStaffInvitationUnanswered(
              RetailerStaffInvitationTransportProblem.network,
            );
      await onOwnerStaff(tester, invitations: repo);

      await typeInvitation(tester);
      await chooseRole(tester, RetailerStaffInvitationRole.retailerManager);
      await submit(tester);

      expect(find.textContaining('Check your connection'), findsOneWidget);
    });

    testWidgets(
      'a send that landed with a failed history reread offers a read, not a resend',
      (WidgetTester tester) async {
        final FakeRetailerStaffRepository staff = FakeRetailerStaffRepository();
        final FakeRetailerStaffInvitationRepository repo =
            FakeRetailerStaffInvitationRepository();
        await onOwnerStaff(tester, invitations: repo, staff: staff);

        // The history read fails from the second call onward.
        staff.invitationsResult = const RetailerInvitationsFailed(
          RetailerReadProblem.timeout,
        );

        await typeInvitation(tester);
        await chooseRole(tester, RetailerStaffInvitationRole.retailerManager);
        await submit(tester);

        // The send stands.
        expect(
          find.text(
            RetailerInviteStaffCopy.noticeTitle(RetailerInviteStaffNotice.sent),
          ),
          findsOneWidget,
        );
        // And the stale history is reported separately.
        expect(
          find.text(RetailerInviteStaffCopy.historyRereadFailedTitle),
          findsOneWidget,
        );

        // The action offered is a read. Taking it re-reads the history and
        // sends nothing.
        staff.invitationsResult = null;
        await tapVisible(
          tester,
          find.text(RetailerInviteStaffCopy.refreshHistory),
        );

        expect(staff.invitationCallCount, 3);
        expect(repo.sendCallCount, 1);
      },
    );

    testWidgets('the invitation history is still on screen after a send', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);

      await typeInvitation(tester);
      await chooseRole(tester, RetailerStaffInvitationRole.retailerManager);
      await submit(tester);

      // Read back from the canonical contract, never assembled from the form.
      expect(find.text('lena@example.com'), findsOneWidget);
      expect(find.text('priya@example.com'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('session isolation', () {
    testWidgets('logging out clears the typed values', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onOwnerStaff(tester);

      await typeInvitation(tester);
      await chooseRole(tester, RetailerStaffInvitationRole.salesStaff);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      app.portal.result = resolvedResult(PortalKind.retailerOwner);
      app.auth.emitSignedIn(otherUser);
      await tester.pumpAndSettle();
      await goTo(tester, RetailerOwnerNavigation.staff);

      expect(
        tester
            .widget<TextField>(
              fieldNamed(RetailerInviteStaffCopy.firstNameLabel),
            )
            .controller!
            .text,
        isEmpty,
      );
      // No role and therefore no shop selector survived either.
      expect(
        find.textContaining(RetailerInviteStaffCopy.shopsLabel),
        findsNothing,
      );
    });

    testWidgets('another Owner sees no stale form or shop selection', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onOwnerStaff(tester);

      await typeInvitation(tester);
      await chooseRole(tester, RetailerStaffInvitationRole.salesStaff);
      await tapVisible(tester, find.text('Northwind Marina').first);

      app.retailerStaffInvitations.nextShops = otherAssignableShops;
      app.portal.result = resolvedResult(PortalKind.retailerOwner);
      app.auth.emitSignedIn(otherUser);
      await tester.pumpAndSettle();
      await goTo(tester, RetailerOwnerNavigation.staff);

      expect(
        tester
            .widget<TextField>(fieldNamed(RetailerInviteStaffCopy.emailLabel))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        find.textContaining(RetailerInviteStaffCopy.shopsLabel),
        findsNothing,
      );
      expect(find.text('Northwind Marina'), findsNothing);
    });

    testWidgets('a send answered after logout leaves no notice behind', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffInvitationRepository repo =
          FakeRetailerStaffInvitationRepository()..manualSend = true;
      final PumpedApp app = await onOwnerStaff(tester, invitations: repo);

      await typeInvitation(tester);
      await chooseRole(tester, RetailerStaffInvitationRole.retailerManager);

      await tapAndPumpOnce(
        tester,
        find.widgetWithText(SrButton, RetailerInviteStaffCopy.submit),
      );

      // The session ends mid-flight.
      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      repo.completeSend();
      await tester.pumpAndSettle();

      // Back in as somebody else: no previous session's success on their
      // screen.
      app.portal.result = resolvedResult(PortalKind.retailerOwner);
      app.auth.emitSignedIn(otherUser);
      await tester.pumpAndSettle();
      await goTo(tester, RetailerOwnerNavigation.staff);

      expect(
        find.text(
          RetailerInviteStaffCopy.noticeTitle(RetailerInviteStaffNotice.sent),
        ),
        findsNothing,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('layout and accessibility', () {
    for (final (String name, Size surface) in <(String, Size)>[
      ('a small Android phone', smallPhoneSurface),
      ('a phone', phoneSurface),
      ('a tablet', tabletSurface),
      ('a desktop browser', desktopSurface),
    ]) {
      testWidgets('$name lays the form out without overflowing', (
        WidgetTester tester,
      ) async {
        await onOwnerStaff(tester, surface: surface);
        await chooseRole(tester, RetailerStaffInvitationRole.salesStaff);

        expect(find.byType(RetailerInviteStaffForm), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('every control carries a visible label', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);
      await chooseRole(tester, RetailerStaffInvitationRole.salesStaff);

      for (final String label in <String>[
        RetailerInviteStaffCopy.firstNameLabel,
        RetailerInviteStaffCopy.lastNameLabel,
        RetailerInviteStaffCopy.emailLabel,
        RetailerInviteStaffCopy.roleLabel,
        RetailerInviteStaffCopy.shopsLabel,
      ]) {
        expect(find.textContaining(label), findsWidgets, reason: label);
      }
    });

    testWidgets('the role buttons announce their selection', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);

      await chooseRole(tester, RetailerStaffInvitationRole.salesStaff);

      final Iterable<Semantics> roleNodes = tester
          .widgetList<Semantics>(
            semanticsContaining(RetailerStaffInvitationRole.salesStaff.label),
          )
          .where((Semantics s) => s.properties.selected != null);
      expect(
        roleNodes.any((Semantics s) => s.properties.selected == true),
        isTrue,
      );
    });

    testWidgets('each shop option is one checkable, named row', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);
      await chooseRole(tester, RetailerStaffInvitationRole.salesStaff);

      final Finder marina = semanticsContaining('Northwind Marina');
      expect(marina, findsWidgets);

      final Iterable<Semantics> checkable = tester
          .widgetList<Semantics>(marina)
          .where((Semantics s) => s.properties.checked != null);
      expect(checkable, isNotEmpty);
      expect(
        checkable.every((Semantics s) => s.properties.checked == false),
        isTrue,
      );
    });

    testWidgets('the text fields are reachable by keyboard focus', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);

      final Finder first = fieldNamed(RetailerInviteStaffCopy.firstNameLabel);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(first).focusNode!.hasFocus, isTrue);

      // The action on each field moves to the next one rather than submitting,
      // so a keyboard user is never one Return away from an invitation.
      expect(
        tester.widget<TextField>(first).textInputAction,
        TextInputAction.next,
      );
    });
  });
}
