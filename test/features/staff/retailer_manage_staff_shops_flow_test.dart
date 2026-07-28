import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/shells/retailer_manager/retailer_manager_navigation.dart';
import 'package:sale_reward/app/shells/retailer_owner/retailer_owner_navigation.dart';
import 'package:sale_reward/core/errors/retailer_read_problem.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/domain/entities/retailer_capabilities.dart';
import 'package:sale_reward/features/auth/domain/repositories/portal_context_repository.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_assignable_shop.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_member.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_shop_assignment.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_assignable_shops_reader.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_staff_repository.dart';
import 'package:sale_reward/features/staff/presentation/retailer/cubit/retailer_manage_staff_shops_cubit.dart';
import 'package:sale_reward/features/staff/presentation/retailer/widgets/retailer_invite_staff_copy.dart';
import 'package:sale_reward/features/staff/presentation/retailer/widgets/retailer_manage_staff_shops_copy.dart';
import 'package:sale_reward/features/staff/presentation/retailer/widgets/retailer_staff_member_card.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';
import '../../support/retailer_invite_staff_fakes.dart';
import '../../support/retailer_manage_staff_shops_fakes.dart';
import '../../support/retailer_read_fakes.dart';

/// Manage Shops, driven through the real application: real router, real shells,
/// real cubits, over fakes that never touch Supabase.
///
/// A second Retailer Owner, so a session switch is a genuine change of person
/// rather than the same identity re-emitted.
const AuthUser otherUser = AuthUser(id: 'user-2', email: 'b@example.com');

/// The labels the picker rows announce — name, code and city, exactly as the
/// assignable-shops contract returned them, and never an id.
const String marinaLabel = 'Northwind Marina · NW-01 · Dubai';
const String downtownLabel = 'Northwind Downtown · NW-02 · Abu Dhabi';

/// Recorded with a name alone: both optional columns are nullable.
const String warehouseLabel = 'Northwind Warehouse';

void main() {
  Future<void> goTo(WidgetTester tester, String location) async {
    GoRouter.of(tester.element(find.byType(Navigator).first)).go(location);
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Taps a control after scrolling it into view, then pumps a single frame —
  /// so a state that only exists while a request is in flight is observable.
  Future<void> tapAndPumpOnce(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
  }

  Future<PumpedApp> onOwnerStaff(
    WidgetTester tester, {
    FakeRetailerStaffRepository? staff,
    FakeRetailerStaffInvitationRepository? invitations,
    FakeRetailerStaffShopAssignmentRepository? assignments,
    Size surface = phoneSurface,
  }) async {
    final PumpedApp app = await pumpAppInRole(
      tester,
      PortalKind.retailerOwner,
      surface: surface,
      retailerStaff: staff,
      retailerStaffInvitations: invitations,
      retailerStaffShopAssignments: assignments,
    );
    await goTo(tester, RetailerOwnerNavigation.staff);
    return app;
  }

  /// The Manage shops control on the card for [name].
  Finder actionFor(String name) => find.descendant(
    of: find.ancestor(
      of: find.text(name),
      matching: find.byType(RetailerStaffMemberCard),
    ),
    matching: find.widgetWithText(
      SrButton,
      RetailerManageStaffShopsCopy.action,
    ),
  );

  Future<void> openEditorFor(WidgetTester tester, String name) async {
    await tapVisible(tester, actionFor(name));
  }

  /// One picker row's checkbox, addressed through the row's **announced label**.
  ///
  /// Deliberately not by the shop's bare name: the same name also appears in the
  /// current-assignment badges above the picker, and a finder that could match
  /// either would silently start testing the wrong widget. The announced label
  /// is the display label the row builds from the backend's own name, code and
  /// city — and never from an id.
  Finder shopOption(String displayLabel) => find.descendant(
    of: find.byWidgetPredicate(
      (Widget w) => w is Semantics && w.properties.label == displayLabel,
      description: 'the "$displayLabel" picker row',
    ),
    matching: find.byType(Checkbox),
  );

  Future<void> toggleShop(WidgetTester tester, String displayLabel) async {
    await tapVisible(tester, shopOption(displayLabel).first);
  }

  /// A control addressed by its **announced label**, which does not change when
  /// the button swaps its visible text for a progress label. Finding Save by the
  /// word "Save changes" would silently stop finding it the moment a write
  /// started — which is exactly the moment these tests care about.
  Finder buttonLabelled(String semanticsLabel) => find.descendant(
    of: find.byWidgetPredicate(
      (Widget w) => w is Semantics && w.properties.label == semanticsLabel,
      description: 'the "$semanticsLabel" control',
    ),
    matching: find.byType(SrButton),
  );

  Finder saveButton() =>
      buttonLabelled(RetailerManageStaffShopsCopy.saveSemantics);

  Finder cancelButton() => buttonLabelled(RetailerManageStaffShopsCopy.cancel);

  bool isEnabled(WidgetTester tester, Finder finder) =>
      tester.widgetList<SrButton>(finder).first.onPressed != null;

  // -------------------------------------------------------------------------
  group('who sees the action', () {
    testWidgets('an active, accepted Sales Staff member gets it', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);

      expect(actionFor('Priya Raman'), findsOneWidget);
      expect(actionFor('Noor Aziz'), findsOneWidget);
    });

    testWidgets('an Owner row does not', (WidgetTester tester) async {
      // Owners hold no shop rows at all, and the function refuses the
      // membership outright.
      await onOwnerStaff(tester);

      expect(actionFor('Amina Farouk'), findsNothing);
    });

    testWidgets('a suspended, never-accepted Sales Staff row does not', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);

      expect(actionFor('Tom Byrne'), findsNothing);
    });

    testWidgets('an invitation-history card never carries it', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);

      // The action exists only inside roster cards. Every occurrence on the
      // screen is inside one.
      final int inCards = find
          .descendant(
            of: find.byType(RetailerStaffMemberCard),
            matching: find.widgetWithText(
              SrButton,
              RetailerManageStaffShopsCopy.action,
            ),
          )
          .evaluate()
          .length;
      final int total = find
          .widgetWithText(SrButton, RetailerManageStaffShopsCopy.action)
          .evaluate()
          .length;

      expect(total, greaterThan(0));
      expect(inCards, total);
    });

    testWidgets('a Retailer Manager keeps the roster and gets no action', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffRepository staff = FakeRetailerStaffRepository()
        ..nextMembers = managerVisibleStaff;
      final FakeRetailerStaffShopAssignmentRepository assignments =
          FakeRetailerStaffShopAssignmentRepository();

      await pumpAppInRole(
        tester,
        PortalKind.retailerManager,
        retailerStaff: staff,
        retailerStaffShopAssignments: assignments,
      );
      await goTo(tester, RetailerManagerNavigation.staff);

      // The roster is untouched.
      expect(find.text('Priya Raman'), findsOneWidget);
      // And no write control exists anywhere on it.
      expect(
        find.widgetWithText(SrButton, RetailerManageStaffShopsCopy.action),
        findsNothing,
      );
      expect(assignments.callCount, 0);
    });

    testWidgets('the Manager shell provides no shop-editor cubit at all', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerManager);
      await goTo(tester, RetailerManagerNavigation.staff);

      // Not merely hidden — the machinery is absent from the subtree, so the
      // editor could not be rendered there even by mistake.
      expect(
        find.byType(BlocProvider<RetailerManageStaffShopsCubit>),
        findsNothing,
      );
    });

    testWidgets('an Owner whose capability hint is off gets no action', (
      WidgetTester tester,
    ) async {
      // The hint is computed by the same resolver, on the same permission, that
      // the write resolves through — so a false hint is a reason not to
      // advertise a dead end. It is still only presentation: the RPC decides.
      await pumpApp(
        tester,
        initialUser: testUser,
        portalResult: PortalContextResolved(
          contextFor(
            PortalKind.retailerOwner,
            capabilities: const RetailerCapabilities(
              viewRetailerOverview: true,
              viewShops: true,
              viewStaff: true,
              manageStaff: true,
              // The one that matters here.
              assignStaffShops: false,
              viewAssignedProducts: true,
              submitReceipts: true,
            ),
          ),
        ),
      );
      await goTo(tester, RetailerOwnerNavigation.staff);

      expect(find.text('Priya Raman'), findsOneWidget);
      expect(actionFor('Priya Raman'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('opening the editor', () {
    testWidgets('it names the person, their role and their current shops', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);
      await openEditorFor(tester, 'Priya Raman');

      expect(find.byType(Dialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Priya Raman'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Sales Staff'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(RetailerManageStaffShopsCopy.currentLabel),
        findsOneWidget,
      );
    });

    testWidgets('the current shops are preselected', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);
      await openEditorFor(tester, 'Priya Raman');

      expect(
        find.text(RetailerManageStaffShopsCopy.selectedCount(2)),
        findsOneWidget,
      );

      final Iterable<Checkbox> boxes = tester.widgetList<Checkbox>(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(Checkbox),
        ),
      );
      // Two of the three offered shops are held today.
      expect(boxes.where((Checkbox c) => c.value == true), hasLength(2));
    });

    testWidgets('a member with no shops opens with nothing ticked', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);
      await openEditorFor(tester, 'Noor Aziz');

      expect(
        find.text(RetailerManageStaffShopsCopy.selectedCount(0)),
        findsOneWidget,
      );
      expect(isEnabled(tester, saveButton()), isFalse);
    });

    testWidgets('the assignable shops are read with the editor', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onOwnerStaff(tester);

      expect(app.retailerStaffInvitations.shopCallCount, 0);
      await openEditorFor(tester, 'Priya Raman');
      expect(app.retailerStaffInvitations.shopCallCount, 1);
    });

    testWidgets('a shop read failure is scoped to the editor', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffInvitationRepository shops =
          FakeRetailerStaffInvitationRepository()
            ..shopsResult = const RetailerAssignableShopsFailed(
              RetailerReadProblem.network,
            );
      final PumpedApp app = await onOwnerStaff(tester, invitations: shops);
      await openEditorFor(tester, 'Priya Raman');

      expect(
        find.text(RetailerManageStaffShopsCopy.optionsUnavailableTitle),
        findsOneWidget,
      );
      // A read retry is offered, Save is not available, and nothing was written.
      expect(
        find.widgetWithText(
          SrButton,
          RetailerManageStaffShopsCopy.optionsRetry,
        ),
        findsOneWidget,
      );
      expect(isEnabled(tester, saveButton()), isFalse);
      expect(app.retailerStaffShopAssignments.callCount, 0);
    });

    testWidgets('the roster survives a shop read failure', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffInvitationRepository shops =
          FakeRetailerStaffInvitationRepository()
            ..shopsResult = const RetailerAssignableShopsFailed(
              RetailerReadProblem.denied,
            );
      await onOwnerStaff(tester, invitations: shops);
      await openEditorFor(tester, 'Priya Raman');
      await tapVisible(tester, cancelButton().first);

      expect(find.text('Priya Raman'), findsWidgets);
      expect(find.text('Amina Farouk'), findsOneWidget);
    });

    testWidgets('a retry re-reads only the shops', (WidgetTester tester) async {
      final FakeRetailerStaffInvitationRepository shops =
          FakeRetailerStaffInvitationRepository()
            ..shopsResult = const RetailerAssignableShopsFailed(
              RetailerReadProblem.timeout,
            );
      final PumpedApp app = await onOwnerStaff(tester, invitations: shops);
      await openEditorFor(tester, 'Priya Raman');

      shops.shopsResult = null;
      await tapVisible(
        tester,
        find.widgetWithText(
          SrButton,
          RetailerManageStaffShopsCopy.optionsRetry,
        ),
      );

      expect(shops.shopCallCount, 2);
      expect(app.retailerStaffShopAssignments.callCount, 0);
      expect(find.text('Northwind Marina'), findsWidgets);
    });

    testWidgets('an empty estate is not shown as a refusal', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffInvitationRepository shops =
          FakeRetailerStaffInvitationRepository()
            ..nextShops = const <RetailerAssignableShop>[];
      await onOwnerStaff(tester, invitations: shops);
      await openEditorFor(tester, 'Priya Raman');

      expect(
        find.text(RetailerManageStaffShopsCopy.optionsEmptyTitle),
        findsOneWidget,
      );
      expect(
        find.text(RetailerManageStaffShopsCopy.optionsUnavailableTitle),
        findsNothing,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('selecting and saving', () {
    testWidgets('at least one shop is required', (WidgetTester tester) async {
      final PumpedApp app = await onOwnerStaff(tester);
      await openEditorFor(tester, 'Priya Raman');

      await toggleShop(tester, marinaLabel);
      await toggleShop(tester, downtownLabel);

      expect(
        find.text(RetailerManageStaffShopsCopy.selectedCount(0)),
        findsOneWidget,
      );
      expect(isEnabled(tester, saveButton()), isFalse);
      expect(app.retailerStaffShopAssignments.callCount, 0);
    });

    testWidgets('an unchanged selection cannot be saved', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);
      await openEditorFor(tester, 'Priya Raman');

      expect(isEnabled(tester, saveButton()), isFalse);
    });

    testWidgets('multiple shops can be selected and the count follows', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);
      await openEditorFor(tester, 'Priya Raman');

      await toggleShop(tester, warehouseLabel);

      expect(
        find.text(RetailerManageStaffShopsCopy.selectedCount(3)),
        findsOneWidget,
      );
      expect(isEnabled(tester, saveButton()), isTrue);
    });

    testWidgets('saving sends the complete desired set, addressed by the '
        'roster membership id', (WidgetTester tester) async {
      final PumpedApp app = await onOwnerStaff(tester);
      await openEditorFor(tester, 'Priya Raman');

      await toggleShop(tester, warehouseLabel);
      await toggleShop(tester, downtownLabel);
      await tapVisible(tester, saveButton().first);

      final RetailerStaffShopAssignmentRequest sent =
          app.retailerStaffShopAssignments.sentRequests.single;
      expect(sent.membershipId, priyaMembershipId);
      expect(sent.shopIds.toSet(), <String>{
        northwindMarinaId,
        northwindWarehouseId,
      });
    });

    testWidgets('a success closes the editor and shows the change summary', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);
      await openEditorFor(tester, 'Priya Raman');

      await toggleShop(tester, warehouseLabel);
      await tapVisible(tester, saveButton().first);

      expect(find.byType(Dialog), findsNothing);
      expect(
        find.text(
          RetailerManageStaffShopsCopy.noticeTitle(
            RetailerManageShopsNotice.saved,
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('1 shop added'), findsOneWidget);
      expect(find.textContaining('1 shop removed'), findsOneWidget);
    });

    testWidgets('the roster is re-read after a success', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffRepository staff = FakeRetailerStaffRepository();
      await onOwnerStaff(tester, staff: staff);
      final int before = staff.memberCallCount;

      await openEditorFor(tester, 'Priya Raman');
      await toggleShop(tester, warehouseLabel);
      await tapVisible(tester, saveButton().first);

      expect(staff.memberCallCount, before + 1);
    });

    testWidgets('the displayed shops come from the canonical reread, never '
        'from what was submitted', (WidgetTester tester) async {
      final FakeRetailerStaffRepository staff = FakeRetailerStaffRepository();
      await onOwnerStaff(tester, staff: staff);

      // The backend's next word on the matter: a name that could only have come
      // from a read, and could not have been assembled from the submitted ids.
      staff.nextMembers = <RetailerStaffMember>[
        RetailerStaffMember(
          membershipId: priyaMembershipId,
          firstName: 'Priya',
          lastName: 'Raman',
          roleCode: 'SALES_STAFF',
          roleName: 'Sales Staff',
          status: RetailerMemberStatus.active,
          shopIds: const <String>[northwindWarehouseId],
          shopNames: const <String>['Renamed By The Backend'],
          joinedAt: DateTime.utc(2026, 4, 12),
          createdAt: DateTime.utc(2026, 4, 10),
        ),
      ];

      await openEditorFor(tester, 'Priya Raman');
      await toggleShop(tester, warehouseLabel);
      await tapVisible(tester, saveButton().first);

      expect(find.text('Renamed By The Backend'), findsOneWidget);
    });

    testWidgets('Save is disabled while the write is in flight', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffShopAssignmentRepository assignments =
          FakeRetailerStaffShopAssignmentRepository()..manual = true;
      await onOwnerStaff(tester, assignments: assignments);
      await openEditorFor(tester, 'Priya Raman');
      await toggleShop(tester, warehouseLabel);

      await tapAndPumpOnce(tester, saveButton().first);

      expect(isEnabled(tester, saveButton()), isFalse);
      expect(isEnabled(tester, cancelButton()), isFalse);

      assignments.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a duplicate press does not write twice', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffShopAssignmentRepository assignments =
          FakeRetailerStaffShopAssignmentRepository()..manual = true;
      await onOwnerStaff(tester, assignments: assignments);
      await openEditorFor(tester, 'Priya Raman');
      await toggleShop(tester, warehouseLabel);

      await tapAndPumpOnce(tester, saveButton().first);
      await tester.tap(saveButton().first, warnIfMissed: false);
      await tester.pump();

      expect(assignments.callCount, 1);

      assignments.complete();
      await tester.pumpAndSettle();

      expect(assignments.callCount, 1);
    });

    testWidgets('Cancel writes nothing and changes nothing', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onOwnerStaff(tester);
      await openEditorFor(tester, 'Priya Raman');
      await toggleShop(tester, warehouseLabel);
      await tapVisible(tester, cancelButton().first);

      expect(find.byType(Dialog), findsNothing);
      expect(app.retailerStaffShopAssignments.callCount, 0);
      // The roster card still shows what the backend last said.
      expect(find.text('Northwind Downtown'), findsWidgets);
    });
  });

  // -------------------------------------------------------------------------
  group('failures on the screen', () {
    testWidgets('a refusal keeps the editor open with the selection intact', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffShopAssignmentRepository assignments =
          FakeRetailerStaffShopAssignmentRepository()
            ..result = refused(RetailerStaffShopAssignmentProblem.denied);
      await onOwnerStaff(tester, assignments: assignments);
      await openEditorFor(tester, 'Priya Raman');
      await toggleShop(tester, warehouseLabel);
      await tapVisible(tester, saveButton().first);

      expect(find.byType(Dialog), findsOneWidget);
      expect(
        find.text(
          RetailerManageStaffShopsCopy.noticeTitle(
            RetailerManageShopsNotice.accessDenied,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(RetailerManageStaffShopsCopy.selectedCount(3)),
        findsOneWidget,
      );
    });

    testWidgets('a write that landed with a failed roster reread offers a '
        'read, not another save', (WidgetTester tester) async {
      final FakeRetailerStaffRepository staff = FakeRetailerStaffRepository();
      final PumpedApp app = await onOwnerStaff(tester, staff: staff);

      await openEditorFor(tester, 'Priya Raman');
      await toggleShop(tester, warehouseLabel);

      staff.rosterResult = const RetailerStaffFailed(
        RetailerReadProblem.network,
      );
      await tapVisible(tester, saveButton().first);

      // The save is still reported as done.
      expect(
        find.text(
          RetailerManageStaffShopsCopy.noticeTitle(
            RetailerManageShopsNotice.saved,
          ),
        ),
        findsOneWidget,
      );
      // And the stale roster is a separate sentence with a read for an action.
      expect(
        find.text(RetailerManageStaffShopsCopy.rosterRereadFailedTitle),
        findsOneWidget,
      );

      staff.rosterResult = null;
      final int writes = app.retailerStaffShopAssignments.callCount;
      await tapVisible(
        tester,
        find.widgetWithText(
          SrButton,
          RetailerManageStaffShopsCopy.refreshRoster,
        ),
      );

      // A read, and only a read.
      expect(app.retailerStaffShopAssignments.callCount, writes);
      expect(find.text('Priya Raman'), findsWidgets);
    });

    testWidgets('an unresolved outcome points at the roster, not the button', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffShopAssignmentRepository assignments =
          FakeRetailerStaffShopAssignmentRepository()
            ..result = refused(RetailerStaffShopAssignmentProblem.timeout);
      await onOwnerStaff(tester, assignments: assignments);
      await openEditorFor(tester, 'Priya Raman');
      await toggleShop(tester, warehouseLabel);
      await tapVisible(tester, saveButton().first);

      expect(
        find.textContaining('may or may not have been saved'),
        findsOneWidget,
      );
      // Nothing repeated it.
      expect(assignments.callCount, 1);
    });

    testWidgets('a stale option produces the availability notice and blocks '
        'Save until it is reviewed', (WidgetTester tester) async {
      final FakeRetailerStaffInvitationRepository shops =
          FakeRetailerStaffInvitationRepository();
      final PumpedApp app = await onOwnerStaff(tester, invitations: shops);
      await openEditorFor(tester, 'Priya Raman');

      await toggleShop(tester, warehouseLabel);

      // The estate changes underneath: the warehouse is no longer assignable.
      shops.nextShops = exampleAssignableShops
          .where((RetailerAssignableShop s) => s.id != northwindWarehouseId)
          .toList();
      await tester
          .element(find.byType(Dialog))
          .read<RetailerManageStaffShopsCubit>()
          .loadAssignableShops();
      await tester.pumpAndSettle();

      expect(
        find.text(RetailerManageStaffShopsCopy.availabilityChangedTitle),
        findsOneWidget,
      );
      expect(isEnabled(tester, saveButton()), isFalse);
      expect(app.retailerStaffShopAssignments.callCount, 0);
    });

    testWidgets('no failure erases the roster, the history or the form', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffShopAssignmentRepository assignments =
          FakeRetailerStaffShopAssignmentRepository()
            ..result = refused(
              RetailerStaffShopAssignmentProblem.invalidSelection,
            );
      await onOwnerStaff(tester, assignments: assignments);
      await openEditorFor(tester, 'Priya Raman');
      await toggleShop(tester, warehouseLabel);
      await tapVisible(tester, saveButton().first);
      await tapVisible(tester, cancelButton().first);

      expect(find.text('Priya Raman'), findsWidgets);
      expect(find.text('Amina Farouk'), findsOneWidget);
      // The invitation history and the Invite Staff form are untouched.
      expect(find.text('lena@example.com'), findsOneWidget);
      expect(find.text(RetailerInviteStaffCopy.title), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('session isolation', () {
    testWidgets('logging out closes the editor and clears it', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onOwnerStaff(tester);
      await openEditorFor(tester, 'Priya Raman');
      await toggleShop(tester, warehouseLabel);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Priya Raman'), findsNothing);
      expect(find.text('Northwind Warehouse'), findsNothing);
    });

    testWidgets('another Owner sees no previous editor state', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onOwnerStaff(tester);
      await openEditorFor(tester, 'Priya Raman');
      await toggleShop(tester, warehouseLabel);
      await tapVisible(tester, saveButton().first);

      app.portal.result = otherRetailerOwnerResult();
      app.retailerStaff.nextMembers = otherStaff;
      app.auth.emitSignedIn(otherUser);
      await tester.pumpAndSettle();

      // No previous colleague, no previous shop, and no previous save notice.
      // The tab is deliberately not re-fetched here — it returns to `initial`
      // and reads itself when the new session actually opens it — so what is
      // asserted is the **absence** of A's data rather than the arrival of B's.
      expect(find.text('Priya Raman'), findsNothing);
      expect(find.text('Northwind Warehouse'), findsNothing);
      expect(find.text('Northwind Downtown'), findsNothing);
      expect(
        find.text(
          RetailerManageStaffShopsCopy.noticeTitle(
            RetailerManageShopsNotice.saved,
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('a save answering after a logout leaves no notice behind', (
      WidgetTester tester,
    ) async {
      final FakeRetailerStaffShopAssignmentRepository assignments =
          FakeRetailerStaffShopAssignmentRepository()..manual = true;
      final PumpedApp app = await onOwnerStaff(
        tester,
        assignments: assignments,
      );
      await openEditorFor(tester, 'Priya Raman');
      await toggleShop(tester, warehouseLabel);
      await tapAndPumpOnce(tester, saveButton().first);

      app.auth.emitSignedOut();
      await tester.pumpAndSettle();

      assignments.complete();
      await tester.pumpAndSettle();

      expect(
        find.text(
          RetailerManageStaffShopsCopy.noticeTitle(
            RetailerManageShopsNotice.saved,
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('switching Owner to Manager leaves no editor behind', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await onOwnerStaff(tester);
      await openEditorFor(tester, 'Priya Raman');

      app.portal.result = resolvedResult(PortalKind.retailerManager);
      app.retailerStaff.nextMembers = managerVisibleStaff;
      app.auth.emitSignedIn(otherUser);
      await tester.pumpAndSettle();
      await goTo(tester, RetailerManagerNavigation.staff);

      expect(find.byType(Dialog), findsNothing);
      expect(
        find.widgetWithText(SrButton, RetailerManageStaffShopsCopy.action),
        findsNothing,
      );
    });

    testWidgets('opening Staff A then Staff B carries nothing across', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);

      await openEditorFor(tester, 'Priya Raman');
      await toggleShop(tester, warehouseLabel);
      await tapVisible(tester, cancelButton().first);

      await openEditorFor(tester, 'Noor Aziz');

      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Noor Aziz'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(RetailerManageStaffShopsCopy.selectedCount(0)),
        findsOneWidget,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('layout, accessibility and leakage', () {
    testWidgets('no raw identifier appears anywhere on the screen', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);
      await openEditorFor(tester, 'Priya Raman');

      final Iterable<String> painted = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? '')
          .toList();
      final Iterable<String> spoken = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((Semantics s) => s.properties.label ?? '')
          .toList();

      final RegExp uuid = RegExp(
        r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
        r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
      );

      for (final String text in <String>[...painted, ...spoken]) {
        expect(uuid.hasMatch(text), isFalse, reason: text);
        // And no internal role token, SQLSTATE or function name.
        for (final String forbidden in <String>[
          'SALES_STAFF',
          '42501',
          '23514',
          '55000',
          '22P02',
          'set_retailer_staff_shop_assignments',
          'p_membership_id',
          'p_shop_ids',
          'retailer_shop_members',
        ]) {
          expect(
            text.contains(forbidden),
            isFalse,
            reason: '$text / $forbidden',
          );
        }
      }
    });

    testWidgets('a small phone lays the editor out without overflowing', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester, surface: smallPhoneSurface);
      await openEditorFor(tester, 'Priya Raman');

      expect(tester.takeException(), isNull);
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('a desktop browser lays the editor out without overflowing', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester, surface: desktopSurface);
      await openEditorFor(tester, 'Priya Raman');

      expect(tester.takeException(), isNull);
      expect(saveButton(), findsOneWidget);
    });

    testWidgets('each shop option is one checkable, named row', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);
      await openEditorFor(tester, 'Priya Raman');

      final Iterable<Semantics> rows = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where(
            (Semantics s) =>
                s.properties.label == 'Northwind Marina · NW-01 · Dubai',
          );

      expect(rows, isNotEmpty);
      expect(rows.first.properties.checked, isTrue);
    });

    testWidgets('the action names the person it acts on', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);

      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Semantics &&
              w.properties.label ==
                  RetailerManageStaffShopsCopy.actionSemantics('Priya Raman'),
        ),
        findsOneWidget,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('regression', () {
    testWidgets('Invite Staff and the invitation history still work', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);

      expect(find.text(RetailerInviteStaffCopy.title), findsOneWidget);
      expect(find.text(RetailerInviteStaffCopy.submit), findsOneWidget);
      expect(find.text('lena@example.com'), findsOneWidget);
      expect(find.text('marco@example.com'), findsOneWidget);
    });

    testWidgets('the local search still filters the roster', (
      WidgetTester tester,
    ) async {
      await onOwnerStaff(tester);

      await tester.enterText(
        find.descendant(
          of: find.byType(SrSearchField),
          matching: find.byType(TextField),
        ),
        'Amina',
      );
      await tester.pumpAndSettle();

      expect(find.text('Amina Farouk'), findsOneWidget);
      expect(find.text('Priya Raman'), findsNothing);
    });

    testWidgets('a save notice survives the local search', (
      WidgetTester tester,
    ) async {
      // Filtering must never hide the confirmation of a write.
      await onOwnerStaff(tester);
      await openEditorFor(tester, 'Priya Raman');
      await toggleShop(tester, warehouseLabel);
      await tapVisible(tester, saveButton().first);

      await tester.enterText(
        find.descendant(
          of: find.byType(SrSearchField),
          matching: find.byType(TextField),
        ),
        'zzzz',
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          RetailerManageStaffShopsCopy.noticeTitle(
            RetailerManageShopsNotice.saved,
          ),
        ),
        findsOneWidget,
      );
    });
  });
}
