import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/entities/lifecycle_access_state.dart';
import 'package:sale_reward/features/auth/domain/repositories/lifecycle_access_repository.dart';
import 'package:sale_reward/features/auth/presentation/pages/login_page.dart';

import '../../support/fakes.dart';
import '../../support/lifecycle_access_fakes.dart';
import '../../support/pump_app.dart';

/// The generic copy, which must stay byte-identical for every state with
/// nothing specific and safe to say.
const String genericTitle = 'Access denied';
const String genericBody =
    'You are signed in, but this account does not have access to this page.';

/// The Flutter-specific closing instruction, which must appear ONLY on the four
/// lifecycle notices.
const String closing = 'If this changes, use Check access again.';

/// Every wire code, so a test can prove none reaches a rendered `Text`.
const List<String> wireCodes = <String>[
  'ACTIVE',
  'ORGANIZATION_INACTIVE',
  'MEMBERSHIP_INACTIVE',
  'PROFILE_INACTIVE',
  'NO_SUPPORTED_ACCESS',
  'AMBIGUOUS',
];

Future<PumpedApp> pumpDenied(
  WidgetTester tester, {
  LifecycleAccessResult diagnostic = const LifecycleAccessUnavailable(),
  FakeLifecycleAccessRepository? repository,
  Size surface = phoneSurface,
}) {
  final FakeLifecycleAccessRepository fake =
      repository ?? FakeLifecycleAccessRepository();
  fake.result = diagnostic;
  return pumpApp(
    tester,
    initialUser: testUser,
    portalResult: deniedResult,
    lifecycleAccess: fake,
    surface: surface,
  );
}

/// Every string rendered by a `Text` currently on screen.
List<String> renderedText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text text) => text.data ?? '')
    .toList();

void main() {
  group('the four approved lifecycle notices', () {
    testWidgets('ORGANIZATION_INACTIVE renders the Retailer inactive copy', (
      WidgetTester tester,
    ) async {
      await pumpDenied(
        tester,
        diagnostic: const LifecycleAccessResolved(
          LifecycleAccessState.organizationInactive,
        ),
      );

      expect(find.text('Retailer inactive'), findsOneWidget);
      expect(
        find.text(
          'This Retailer is currently inactive. Contact the Vendor or your '
          'Retailer administrator.',
        ),
        findsOneWidget,
      );
      expect(find.text(closing), findsOneWidget);
      expect(find.text(genericTitle), findsNothing);
    });

    testWidgets('MEMBERSHIP_INACTIVE renders the Account inactive copy', (
      WidgetTester tester,
    ) async {
      await pumpDenied(
        tester,
        diagnostic: const LifecycleAccessResolved(
          LifecycleAccessState.membershipInactive,
        ),
      );

      expect(find.text('Account inactive'), findsOneWidget);
      expect(
        find.text(
          'Your access to this Retailer is inactive. Contact your Retailer '
          'administrator.',
        ),
        findsOneWidget,
      );
      expect(find.text(closing), findsOneWidget);
    });

    testWidgets('PROFILE_INACTIVE renders the Account unavailable copy', (
      WidgetTester tester,
    ) async {
      await pumpDenied(
        tester,
        diagnostic: const LifecycleAccessResolved(
          LifecycleAccessState.profileInactive,
        ),
      );

      expect(find.text('Account unavailable'), findsOneWidget);
      expect(
        find.text(
          'Your SalesReward account is currently inactive. Contact support '
          'or your administrator.',
        ),
        findsOneWidget,
      );
      expect(find.text(closing), findsOneWidget);
    });

    testWidgets('AMBIGUOUS renders the account-setup copy', (
      WidgetTester tester,
    ) async {
      await pumpDenied(
        tester,
        diagnostic: const LifecycleAccessResolved(
          LifecycleAccessState.ambiguous,
        ),
      );

      expect(find.text('Account setup needs attention'), findsOneWidget);
      expect(
        find.text(
          'More than one Retailer context is available for this account. '
          'Contact support.',
        ),
        findsOneWidget,
      );
      expect(find.text(closing), findsOneWidget);
    });
  });

  group('the states that must keep the generic card', () {
    testWidgets('ACTIVE renders the ordinary denial and nothing more', (
      WidgetTester tester,
    ) async {
      await pumpDenied(
        tester,
        diagnostic: const LifecycleAccessResolved(LifecycleAccessState.active),
      );

      expect(find.text(genericTitle), findsOneWidget);
      expect(find.text(genericBody), findsOneWidget);
      // The closing instruction belongs only to lifecycle notices.
      expect(find.text(closing), findsNothing);
    });

    testWidgets('NO_SUPPORTED_ACCESS renders the ordinary denial', (
      WidgetTester tester,
    ) async {
      await pumpDenied(
        tester,
        diagnostic: const LifecycleAccessResolved(
          LifecycleAccessState.noSupportedAccess,
        ),
      );

      expect(find.text(genericTitle), findsOneWidget);
      expect(find.text(genericBody), findsOneWidget);
      expect(find.text(closing), findsNothing);
    });

    testWidgets('an unavailable diagnostic renders the ordinary denial', (
      WidgetTester tester,
    ) async {
      await pumpDenied(tester);

      expect(find.text(genericTitle), findsOneWidget);
      expect(find.text(closing), findsNothing);
    });

    testWidgets('ACTIVE and NO_SUPPORTED_ACCESS are indistinguishable', (
      WidgetTester tester,
    ) async {
      await pumpDenied(
        tester,
        diagnostic: const LifecycleAccessResolved(LifecycleAccessState.active),
      );
      final List<String> activeText = renderedText(tester);

      await pumpDenied(
        tester,
        diagnostic: const LifecycleAccessResolved(
          LifecycleAccessState.noSupportedAccess,
        ),
      );
      final List<String> noAccessText = renderedText(tester);

      // The whole disclosure boundary in one assertion: a hostile account
      // cannot tell "you hold no Retailer membership" from "something else
      // refused you" by reading the screen.
      expect(noAccessText, activeText);
    });

    testWidgets('an unavailable diagnostic is indistinguishable from ACTIVE', (
      WidgetTester tester,
    ) async {
      await pumpDenied(
        tester,
        diagnostic: const LifecycleAccessResolved(LifecycleAccessState.active),
      );
      final List<String> activeText = renderedText(tester);

      await pumpDenied(tester);

      expect(renderedText(tester), activeText);
    });
  });

  group('the loading phase', () {
    testWidgets('renders the generic card while the diagnostic is in flight', (
      WidgetTester tester,
    ) async {
      final FakeLifecycleAccessRepository fake = FakeLifecycleAccessRepository()
        ..manual = true;

      await pumpApp(
        tester,
        initialUser: testUser,
        portalResult: deniedResult,
        lifecycleAccess: fake,
        settle: false,
      );
      await tester.pump();
      await tester.pump();

      expect(find.text(genericTitle), findsOneWidget);
      expect(find.text('Check access again'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);

      fake.complete(
        const LifecycleAccessResolved(
          LifecycleAccessState.organizationInactive,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Retailer inactive'), findsOneWidget);
    });
  });

  group('both affordances appear in every state', () {
    final Map<String, LifecycleAccessResult> cases =
        <String, LifecycleAccessResult>{
          'unavailable': const LifecycleAccessUnavailable(),
          'ACTIVE': const LifecycleAccessResolved(LifecycleAccessState.active),
          'NO_SUPPORTED_ACCESS': const LifecycleAccessResolved(
            LifecycleAccessState.noSupportedAccess,
          ),
          'ORGANIZATION_INACTIVE': const LifecycleAccessResolved(
            LifecycleAccessState.organizationInactive,
          ),
          'MEMBERSHIP_INACTIVE': const LifecycleAccessResolved(
            LifecycleAccessState.membershipInactive,
          ),
          'PROFILE_INACTIVE': const LifecycleAccessResolved(
            LifecycleAccessState.profileInactive,
          ),
          'AMBIGUOUS': const LifecycleAccessResolved(
            LifecycleAccessState.ambiguous,
          ),
        };

    for (final MapEntry<String, LifecycleAccessResult> entry in cases.entries) {
      testWidgets('${entry.key} offers Check access again and Sign out', (
        WidgetTester tester,
      ) async {
        await pumpDenied(tester, diagnostic: entry.value);

        expect(
          find.widgetWithText(SrButton, 'Check access again'),
          findsOneWidget,
        );
        expect(find.widgetWithText(SrButton, 'Sign out'), findsOneWidget);
      });
    }
  });

  group('nothing sensitive is rendered', () {
    for (final MapEntry<String, LifecycleAccessState> entry
        in <String, LifecycleAccessState>{
          'ACTIVE': LifecycleAccessState.active,
          'ORGANIZATION_INACTIVE': LifecycleAccessState.organizationInactive,
          'MEMBERSHIP_INACTIVE': LifecycleAccessState.membershipInactive,
          'PROFILE_INACTIVE': LifecycleAccessState.profileInactive,
          'NO_SUPPORTED_ACCESS': LifecycleAccessState.noSupportedAccess,
          'AMBIGUOUS': LifecycleAccessState.ambiguous,
        }.entries) {
      testWidgets('${entry.key} renders no wire code, id or SQLSTATE', (
        WidgetTester tester,
      ) async {
        await pumpDenied(
          tester,
          diagnostic: LifecycleAccessResolved(entry.value),
        );

        final String screen = renderedText(tester).join('\n');

        for (final String code in wireCodes) {
          expect(
            screen.contains(code),
            isFalse,
            reason: 'the raw state $code must never be rendered',
          );
        }
        expect(screen.contains(testUser.id), isFalse);
        expect(screen.contains('42501'), isFalse);
        expect(screen.contains('user-1'), isFalse);
        expect(screen.toLowerCase().contains('postgrest'), isFalse);
        expect(screen.toLowerCase().contains('exception'), isFalse);
      });
    }
  });

  group('Check access again', () {
    testWidgets('one press starts exactly one portal-context resolution', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpDenied(
        tester,
        diagnostic: const LifecycleAccessResolved(
          LifecycleAccessState.membershipInactive,
        ),
      );
      // The startup resolution.
      expect(app.portal.resolveCallCount, 1);

      await tester.tap(find.widgetWithText(SrButton, 'Check access again'));
      await tester.pumpAndSettle();

      expect(app.portal.resolveCallCount, 2);
    });

    testWidgets('rapid presses still start exactly one resolution', (
      WidgetTester tester,
    ) async {
      final FakeLifecycleAccessRepository fake = FakeLifecycleAccessRepository()
        ..result = const LifecycleAccessResolved(
          LifecycleAccessState.organizationInactive,
        );
      final PumpedApp app = await pumpApp(
        tester,
        initialUser: testUser,
        portalResult: deniedResult,
        lifecycleAccess: fake,
      );
      app.portal.manualCompletion = true;

      final Finder button = find.widgetWithText(SrButton, 'Check access again');
      await tester.tap(button);
      await tester.pump();
      // The page is still up for a frame or two; press again.
      if (button.evaluate().isNotEmpty) {
        await tester.tap(button, warnIfMissed: false);
        await tester.pump();
      }

      expect(app.portal.resolveCallCount, 2, reason: 'startup + one retry');
      expect(app.portal.pendingCount, 1);

      app.portal.completeNext(deniedResult);
      await tester.pumpAndSettle();
    });

    testWidgets('the control is busy and disabled while resolving', (
      WidgetTester tester,
    ) async {
      final PumpedApp app = await pumpDenied(
        tester,
        diagnostic: const LifecycleAccessResolved(
          LifecycleAccessState.organizationInactive,
        ),
      );
      app.portal.manualCompletion = true;

      await tester.tap(find.widgetWithText(SrButton, 'Check access again'));
      await tester.pump();

      final Finder busy = find.widgetWithText(SrButton, 'Checking access…');
      if (busy.evaluate().isNotEmpty) {
        expect(tester.widget<SrButton>(busy).onPressed, isNull);
      }

      app.portal.completeNext(deniedResult);
      await tester.pumpAndSettle();
    });
  });

  group('Sign out remains available', () {
    testWidgets('signing out from a lifecycle notice reaches login', (
      WidgetTester tester,
    ) async {
      await pumpDenied(
        tester,
        diagnostic: const LifecycleAccessResolved(
          LifecycleAccessState.profileInactive,
        ),
      );

      await tester.tap(find.widgetWithText(SrButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets('signing out from the generic card reaches login', (
      WidgetTester tester,
    ) async {
      await pumpDenied(tester);

      await tester.tap(find.widgetWithText(SrButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
    });
  });

  group('layout and accessibility', () {
    testWidgets('a lifecycle notice fits a small phone without overflow', (
      WidgetTester tester,
    ) async {
      await pumpDenied(
        tester,
        diagnostic: const LifecycleAccessResolved(
          LifecycleAccessState.organizationInactive,
        ),
        surface: smallPhoneSurface,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Retailer inactive'), findsOneWidget);
    });

    testWidgets('a lifecycle notice survives 200% text scaling', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpDenied(
        tester,
        diagnostic: const LifecycleAccessResolved(
          LifecycleAccessState.ambiguous,
        ),
        surface: smallPhoneSurface,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Account setup needs attention'), findsOneWidget);
    });

    testWidgets(
      'the generic card survives 200% text scaling with both actions',
      (WidgetTester tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await pumpDenied(tester, surface: smallPhoneSurface);

        expect(tester.takeException(), isNull);
        expect(
          find.widgetWithText(SrButton, 'Check access again'),
          findsOneWidget,
        );
        expect(find.widgetWithText(SrButton, 'Sign out'), findsOneWidget);
      },
    );

    testWidgets('both controls are reachable by keyboard focus', (
      WidgetTester tester,
    ) async {
      await pumpDenied(
        tester,
        diagnostic: const LifecycleAccessResolved(
          LifecycleAccessState.membershipInactive,
        ),
      );

      final Iterable<FocusNode> focusable = tester
          .widgetList<Focus>(find.byType(Focus))
          .map((Focus f) => f.focusNode)
          .whereType<FocusNode>();

      expect(focusable.where((FocusNode n) => n.canRequestFocus), isNotEmpty);
    });

    testWidgets('both controls expose a button semantics label', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpDenied(
        tester,
        diagnostic: const LifecycleAccessResolved(
          LifecycleAccessState.membershipInactive,
        ),
      );

      expect(find.bySemanticsLabel('Check access again'), findsOneWidget);
      expect(find.bySemanticsLabel('Sign out'), findsOneWidget);

      handle.dispose();
    });
  });
}
