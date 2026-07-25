import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sale_reward/app/router/app_router.dart';
import 'package:sale_reward/app/shells/base/placeholder_destination_page.dart';
import 'package:sale_reward/app/shells/vendor/vendor_navigation.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/audit/domain/entities/vendor_audit_log_entry.dart';
import 'package:sale_reward/features/audit/presentation/vendor/pages/vendor_audit_logs_page.dart';
import 'package:sale_reward/features/audit/presentation/vendor/widgets/vendor_audit_log_copy.dart';
import 'package:sale_reward/features/audit/presentation/vendor/widgets/vendor_audit_log_labels.dart';
import 'package:sale_reward/features/audit/presentation/vendor/widgets/vendor_audit_log_tile.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/presentation/bloc/session_bloc.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';
import '../../support/vendor_audit_log_fakes.dart';

/// Drives the Vendor Audit Logs screen through the real application: real
/// router, real shell, real cubit, over a fake repository that never touches
/// Supabase.

/// Navigates the live router, as a deep link or a typed URL would.
Future<void> goTo(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Navigator).first)).go(location);
  await tester.pumpAndSettle();
}

/// Where the router actually ended up.
String currentLocation(WidgetTester tester) => GoRouter.of(
  tester.element(find.byType(Navigator).first),
).routeInformationProvider.value.uri.path;

/// Scrolls [finder] into view before tapping it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Any [Semantics] whose label contains [fragment].
Finder semanticsContaining(String fragment) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is Semantics &&
      (widget.properties.label?.contains(fragment) ?? false),
  description: 'Semantics whose label contains "$fragment"',
);

void main() {
  /// Signs in as a Vendor Super Admin and opens the Audit Logs feed.
  Future<PumpedApp> onAuditLogs(
    WidgetTester tester, {
    FakeVendorAuditLogRepository? auditLogs,
    Size surface = phoneSurface,
  }) async {
    final PumpedApp app = await pumpAppInRole(
      tester,
      PortalKind.vendorSuperAdmin,
      surface: surface,
      vendorAuditLogs: auditLogs,
    );
    await goTo(tester, VendorNavigation.auditLogs);
    return app;
  }

  group('route isolation', () {
    test('the guard sends every other role away', () {
      for (final PortalKind kind in <PortalKind>[
        PortalKind.retailerOwner,
        PortalKind.retailerManager,
        PortalKind.salesStaff,
      ]) {
        final SessionState session = SessionActive(contextFor(kind));
        expect(
          redirectFor(session, VendorNavigation.auditLogs),
          sessionHome(session),
        );
      }
    });

    test('a Vendor Super Admin is allowed in', () {
      expect(
        redirectFor(
          SessionActive(contextFor(PortalKind.vendorSuperAdmin)),
          VendorNavigation.auditLogs,
        ),
        isNull,
      );
    });

    test('a signed-out caller is sent to login, not to the feed', () {
      expect(
        redirectFor(const SessionUnauthenticated(), VendorNavigation.auditLogs),
        '/login',
      );
    });

    test('the route is the one the milestone names', () {
      expect(VendorNavigation.auditLogs, '/vendor/audit-logs');
    });

    testWidgets('a Retailer Owner typing the URL lands on their own home', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.retailerOwner);

      await goTo(tester, VendorNavigation.auditLogs);

      expect(find.byType(VendorAuditLogsPage), findsNothing);
      expect(currentLocation(tester), isNot(VendorNavigation.auditLogs));
    });

    testWidgets('a Sales Staff user typing the URL lands on their own home', (
      WidgetTester tester,
    ) async {
      await pumpAppInRole(tester, PortalKind.salesStaff);

      await goTo(tester, VendorNavigation.auditLogs);

      expect(find.byType(VendorAuditLogsPage), findsNothing);
    });
  });

  group('the placeholder is gone', () {
    testWidgets('the route renders the real page, not a coming-soon card', (
      WidgetTester tester,
    ) async {
      await onAuditLogs(tester);

      expect(find.byType(VendorAuditLogsPage), findsOneWidget);
      expect(find.byType(PlaceholderDestinationPage), findsNothing);
    });

    testWidgets('the Audit Logs destination stays selected on the route', (
      WidgetTester tester,
    ) async {
      await onAuditLogs(tester, surface: tabletSurface);

      final int selected = VendorNavigation.model.indexForLocation(
        VendorNavigation.auditLogs,
      );
      expect(
        VendorNavigation.destinations[selected].label,
        VendorAuditLogCopy.listTitle,
      );
    });

    testWidgets('there is no detail route beneath it', (
      WidgetTester tester,
    ) async {
      // No audit detail read exists, so no address under this path may resolve.
      await onAuditLogs(tester);

      await goTo(
        tester,
        '${VendorNavigation.auditLogs}/$createdProductAuditId',
      );

      expect(find.byType(VendorAuditLogsPage), findsNothing);
    });
  });

  group('loading and the first page', () {
    testWidgets('a skeleton stands in while the first read is in flight', (
      WidgetTester tester,
    ) async {
      final FakeVendorAuditLogRepository repository =
          FakeVendorAuditLogRepository()..manual = true;

      await pumpApp(
        tester,
        initialUser: testUser,
        portalResult: resolvedResult(PortalKind.vendorSuperAdmin),
        vendorAuditLogs: repository,
        settle: false,
      );
      await tester.pump();
      await tester.pump();
      GoRouter.of(
        tester.element(find.byType(Navigator).first),
      ).go(VendorNavigation.auditLogs);
      await tester.pump();
      await tester.pump();

      expect(find.byType(SrSkeletonScreen), findsWidgets);

      repository.complete();
      await tester.pumpAndSettle();

      expect(find.byType(VendorAuditLogTile), findsWidgets);
    });

    testWidgets('every returned event is rendered', (
      WidgetTester tester,
    ) async {
      await onAuditLogs(tester);

      expect(
        find.byType(VendorAuditLogTile),
        findsNWidgets(auditFirstPage.length),
      );
    });

    testWidgets('the loaded count is labelled as loaded, never as a total', (
      WidgetTester tester,
    ) async {
      await onAuditLogs(tester);

      expect(find.text('5 events loaded'), findsOneWidget);
      expect(find.textContaining('total'), findsNothing);
    });
  });

  group('what one event says', () {
    testWidgets('a named actor is shown by name', (WidgetTester tester) async {
      await onAuditLogs(tester);

      expect(find.text('Ada Vendor'), findsWidgets);
    });

    testWidgets('an UNKNOWN actor is neutral and unnamed', (
      WidgetTester tester,
    ) async {
      await onAuditLogs(tester);

      expect(find.text('Unknown actor'), findsOneWidget);
    });

    testWidgets('a SYSTEM actor states the ambiguity exactly', (
      WidgetTester tester,
    ) async {
      await onAuditLogs(tester);

      // The whole point of the wording: `SYSTEM` means "no actor identity
      // remains", not "a system process acted".
      expect(find.text('System or unavailable actor'), findsOneWidget);
      expect(find.text('System'), findsNothing);
      expect(find.textContaining('Automated'), findsNothing);
      expect(find.textContaining('Deleted user'), findsNothing);
      expect(find.textContaining('Former user'), findsNothing);
    });

    testWidgets('a known action code reads as its friendly label', (
      WidgetTester tester,
    ) async {
      await onAuditLogs(tester);

      expect(find.text('Product created'), findsOneWidget);
      expect(find.text('Retailer onboarded'), findsOneWidget);
      expect(find.text('Product deactivated'), findsOneWidget);
      // And the raw code is NOT shown beside a code this build knows.
      expect(find.textContaining('PRODUCT_CREATED'), findsNothing);
    });

    testWidgets('an unknown action code is humanized and stays visible', (
      WidgetTester tester,
    ) async {
      await onAuditLogs(tester);

      expect(find.text('Something not yet invented'), findsOneWidget);
      // Its raw code is shown beneath, subdued and labelled, because a reader
      // meeting an unfamiliar event needs to know what was actually recorded.
      expect(
        find.text('Recorded action code: SOMETHING_NOT_YET_INVENTED'),
        findsOneWidget,
      );
    });

    testWidgets('an entity display name is shown beside its type', (
      WidgetTester tester,
    ) async {
      await onAuditLogs(tester);

      expect(find.text('Product · Espresso Beans'), findsWidgets);
      expect(find.text('Retailer · Acme Retail'), findsOneWidget);
    });

    testWidgets('a missing entity name is stated, never filled in', (
      WidgetTester tester,
    ) async {
      await onAuditLogs(tester);

      expect(
        find.text('Retailer shop · Affected item unavailable'),
        findsOneWidget,
      );
    });

    testWidgets('an unknown entity type falls back to neutral wording', (
      WidgetTester tester,
    ) async {
      await onAuditLogs(tester);

      expect(
        find.text('Future entity · Affected item unavailable'),
        findsOneWidget,
      );
    });

    testWidgets('the timestamp is rendered in local time', (
      WidgetTester tester,
    ) async {
      await onAuditLogs(tester);

      final DateTime local = createdProductEvent.occurredAt.toLocal();
      expect(
        find.textContaining('${local.day} Jul ${local.year}'),
        findsWidgets,
      );
    });

    testWidgets('a row shows no id, metadata, IP or user agent', (
      WidgetTester tester,
    ) async {
      await onAuditLogs(tester);

      expect(find.textContaining(createdProductAuditId), findsNothing);
      expect(find.textContaining('metadata'), findsNothing);
      expect(find.textContaining('@'), findsNothing);
    });

    testWidgets('an event carries one spoken sentence', (
      WidgetTester tester,
    ) async {
      await onAuditLogs(tester);

      expect(semanticsContaining('Product created'), findsWidgets);
      expect(
        semanticsContaining('Recorded actor: System or unavailable actor'),
        findsWidgets,
      );
      expect(semanticsContaining('Affected item: Product'), findsWidgets);
      expect(semanticsContaining('Recorded at:'), findsWidgets);
    });
  });

  group('refresh', () {
    testWidgets('the header button re-reads the newest page', (
      WidgetTester tester,
    ) async {
      final FakeVendorAuditLogRepository repository =
          FakeVendorAuditLogRepository();
      await onAuditLogs(tester, auditLogs: repository);
      expect(repository.callCount, 1);

      await tapVisible(tester, find.text(VendorAuditLogCopy.refresh));

      expect(repository.callCount, 2);
      expect(repository.requestedCursors.last, isNull);
    });

    testWidgets('a failed refresh keeps the rows and says so', (
      WidgetTester tester,
    ) async {
      final FakeVendorAuditLogRepository repository =
          FakeVendorAuditLogRepository();
      await onAuditLogs(tester, auditLogs: repository);

      repository.result = unavailableAuditRead<List<VendorAuditLogEntry>>();
      await tapVisible(tester, find.text(VendorAuditLogCopy.refresh));

      expect(find.text(VendorAuditLogCopy.staleTitle), findsOneWidget);
      expect(
        find.byType(VendorAuditLogTile),
        findsNWidgets(auditFirstPage.length),
      );
    });

    testWidgets('a refresh after a failure clears the notice', (
      WidgetTester tester,
    ) async {
      final FakeVendorAuditLogRepository repository =
          FakeVendorAuditLogRepository();
      await onAuditLogs(tester, auditLogs: repository);

      repository.result = unavailableAuditRead<List<VendorAuditLogEntry>>();
      await tapVisible(tester, find.text(VendorAuditLogCopy.refresh));
      expect(find.text(VendorAuditLogCopy.staleTitle), findsOneWidget);

      repository.result = null;
      await tapVisible(tester, find.text(VendorAuditLogCopy.refresh));

      expect(find.text(VendorAuditLogCopy.staleTitle), findsNothing);
    });

    testWidgets('the feed can be pulled to refresh on a phone', (
      WidgetTester tester,
    ) async {
      final FakeVendorAuditLogRepository repository =
          FakeVendorAuditLogRepository();
      await onAuditLogs(tester, auditLogs: repository);

      expect(find.byType(RefreshIndicator), findsOneWidget);

      await tester.fling(
        find.byType(VendorAuditLogTile).first,
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();

      expect(repository.callCount, greaterThan(1));
    });
  });

  group('empty and failed states', () {
    testWidgets('an empty history is worded as a fact, not a denial', (
      WidgetTester tester,
    ) async {
      final FakeVendorAuditLogRepository repository =
          FakeVendorAuditLogRepository()..history = <VendorAuditLogEntry>[];

      await onAuditLogs(tester, auditLogs: repository);

      expect(find.text(VendorAuditLogCopy.emptyTitle), findsOneWidget);
      expect(find.byType(VendorAuditLogTile), findsNothing);
      expect(find.textContaining('access'), findsNothing);
    });

    testWidgets('a failed first read offers a retry that can succeed', (
      WidgetTester tester,
    ) async {
      final FakeVendorAuditLogRepository repository =
          FakeVendorAuditLogRepository()
            ..result = unavailableAuditRead<List<VendorAuditLogEntry>>();

      await onAuditLogs(tester, auditLogs: repository);
      expect(find.text('Could not load this'), findsOneWidget);

      repository.result = null;
      await tapVisible(tester, find.text('Try again'));

      expect(
        find.byType(VendorAuditLogTile),
        findsNWidgets(auditFirstPage.length),
      );
    });

    testWidgets('a denial offers no retry and names no permission', (
      WidgetTester tester,
    ) async {
      final FakeVendorAuditLogRepository repository =
          FakeVendorAuditLogRepository()
            ..result = deniedAuditRead<List<VendorAuditLogEntry>>();

      await onAuditLogs(tester, auditLogs: repository);

      expect(find.text('Not available to this account'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.textContaining('AUDIT'), findsNothing);
      expect(find.textContaining('42501'), findsNothing);
    });
  });

  group('older activity', () {
    testWidgets('a short first page shows the end rather than a button', (
      WidgetTester tester,
    ) async {
      await onAuditLogs(tester);

      expect(find.text(VendorAuditLogCopy.endOfHistoryTitle), findsOneWidget);
      expect(find.text(VendorAuditLogCopy.loadMore), findsNothing);
    });

    testWidgets('a full first page offers the older-activity button', (
      WidgetTester tester,
    ) async {
      final FakeVendorAuditLogRepository repository =
          FakeVendorAuditLogRepository()..history = auditHistoryOf(60);

      await onAuditLogs(tester, auditLogs: repository);

      expect(find.text(VendorAuditLogCopy.loadMore), findsOneWidget);
      expect(find.text(VendorAuditLogCopy.endOfHistoryTitle), findsNothing);
    });

    testWidgets('pressing it appends older rows and then shows the end', (
      WidgetTester tester,
    ) async {
      final FakeVendorAuditLogRepository repository =
          FakeVendorAuditLogRepository()..history = auditHistoryOf(60);

      await onAuditLogs(tester, auditLogs: repository, surface: tabletSurface);
      await tapVisible(tester, find.text(VendorAuditLogCopy.loadMore));

      expect(repository.olderCursors, hasLength(1));
      expect(repository.olderCursors.single.auditLogId, syntheticAuditId(49));
      expect(find.text('60 events loaded'), findsOneWidget);
      expect(find.text(VendorAuditLogCopy.endOfHistoryTitle), findsOneWidget);
      expect(find.text(VendorAuditLogCopy.loadMore), findsNothing);
    });

    testWidgets('a failed older page keeps the rows and offers a retry', (
      WidgetTester tester,
    ) async {
      final FakeVendorAuditLogRepository repository =
          FakeVendorAuditLogRepository()..history = auditHistoryOf(60);

      await onAuditLogs(tester, auditLogs: repository, surface: tabletSurface);
      repository.result = unavailableAuditRead<List<VendorAuditLogEntry>>();
      await tapVisible(tester, find.text(VendorAuditLogCopy.loadMore));

      expect(find.text(VendorAuditLogCopy.loadMoreFailedTitle), findsOneWidget);
      expect(find.text(VendorAuditLogCopy.retryLoadMore), findsOneWidget);
      expect(find.text('50 events loaded'), findsOneWidget);

      repository.result = null;
      await tapVisible(tester, find.text(VendorAuditLogCopy.retryLoadMore));

      expect(find.text(VendorAuditLogCopy.loadMoreFailedTitle), findsNothing);
      expect(find.text('60 events loaded'), findsOneWidget);
    });

    testWidgets('the control is a button, never an automatic fetch', (
      WidgetTester tester,
    ) async {
      final FakeVendorAuditLogRepository repository =
          FakeVendorAuditLogRepository()..history = auditHistoryOf(60);

      await onAuditLogs(tester, auditLogs: repository, surface: tabletSurface);

      // Scrolling to the very bottom must not fetch anything on its own.
      await tester.ensureVisible(find.text(VendorAuditLogCopy.loadMore));
      await tester.pumpAndSettle();

      expect(repository.callCount, 1);
      expect(semanticsContaining(VendorAuditLogCopy.loadMore), findsWidgets);
    });
  });

  group('responsive and themed', () {
    for (final (String name, Size surface) in <(String, Size)>[
      ('a small phone', smallPhoneSurface),
      ('a phone', phoneSurface),
      ('a tablet', tabletSurface),
      ('a desktop browser', desktopSurface),
    ]) {
      testWidgets('the feed lays out on $name without overflowing', (
        WidgetTester tester,
      ) async {
        await onAuditLogs(tester, surface: surface);

        expect(tester.takeException(), isNull);
        expect(find.byType(VendorAuditLogTile), findsWidgets);
      });
    }

    testWidgets('large text scale does not overflow a small phone', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await onAuditLogs(tester, surface: smallPhoneSurface);

      expect(tester.takeException(), isNull);
    });

    for (final ThemeMode mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
      testWidgets('the feed renders in $mode', (WidgetTester tester) async {
        await pumpApp(
          tester,
          initialUser: testUser,
          portalResult: resolvedResult(PortalKind.vendorSuperAdmin),
          themeMode: mode,
        );
        await goTo(tester, VendorNavigation.auditLogs);

        expect(find.byType(VendorAuditLogTile), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the label helpers', () {
    test('every mapped action code is one the backend actually writes', () {
      // Read from the deployed migrations. Nothing here is anticipated.
      const List<String> shipped = <String>[
        'RETAILER_ONBOARDED',
        'RETAILER_SHOP_ADDED',
        'RETAILER_OWNER_INVITED',
        'RETAILER_OWNER_INVITATION_ACCEPTED',
        'RETAILER_OWNER_INVITATION_REVOKED',
        'STAFF_INVITATION_RESERVED',
        'STAFF_INVITATION_SENT',
        'STAFF_INVITATION_RESENT',
        'STAFF_INVITATION_REVOKED',
        'STAFF_INVITATION_DELIVERY_FAILED',
        'STAFF_INVITATION_ACCEPTED',
        'PRODUCT_CREATED',
        'PRODUCT_UPDATED',
        'PRODUCT_ACTIVATED',
        'PRODUCT_DEACTIVATED',
        'PRODUCT_ASSIGNED_TO_RETAILER',
        'PRODUCT_UNASSIGNED_FROM_RETAILER',
      ];

      for (final String code in shipped) {
        expect(
          VendorAuditLogLabels.isKnownAction(code),
          isTrue,
          reason: '$code is written by the backend but has no label',
        );
      }
    });

    test('an unknown code humanizes without claiming an outcome', () {
      expect(
        VendorAuditLogLabels.actionLabel('PRODUCT_STATUS_CHANGED'),
        'Product status changed',
      );
      expect(
        VendorAuditLogLabels.isKnownAction('PRODUCT_STATUS_CHANGED'),
        isFalse,
      );

      // Never mapped to a create, an update, a delete, a success or a failure.
      for (final String word in <String>[
        'created',
        'updated',
        'deleted',
        'succeeded',
        'failed',
      ]) {
        expect(
          VendorAuditLogLabels.actionLabel('WHOLLY_UNFAMILIAR_TOKEN'),
          isNot(contains(word)),
        );
      }
    });

    test('a malformed code still produces a visible neutral label', () {
      expect(VendorAuditLogLabels.actionLabel('___'), 'Recorded activity');
      expect(VendorAuditLogLabels.actionLabel('   '), 'Recorded activity');
      expect(VendorAuditLogLabels.actionLabel('-'), 'Recorded activity');
      expect(VendorAuditLogLabels.actionLabel('x'), 'X');
    });

    test('the five whitelisted entity types have labels', () {
      const Map<String, String> expected = <String, String>{
        'VENDOR_PRODUCT': 'Product',
        'RETAILER_ORGANIZATION': 'Retailer',
        'RETAILER_SHOP': 'Retailer shop',
        'RETAILER_INVITATION': 'Retailer owner invitation',
        'RETAILER_STAFF_INVITATION': 'Retailer staff invitation',
      };

      expected.forEach((String code, String label) {
        expect(VendorAuditLogLabels.entityTypeLabel(code), label);
      });
    });

    test('an unknown entity type humanizes neutrally', () {
      expect(
        VendorAuditLogLabels.entityTypeLabel('FUTURE_ENTITY'),
        'Future entity',
      );
    });

    test('the actor wording is one string per state', () {
      expect(
        VendorAuditLogLabels.actorLabel(createdProductEvent),
        'Ada Vendor',
      );
      expect(
        VendorAuditLogLabels.actorLabel(unknownActorEvent),
        'Unknown actor',
      );
      expect(
        VendorAuditLogLabels.actorLabel(systemActorEvent),
        'System or unavailable actor',
      );
    });
  });
}
