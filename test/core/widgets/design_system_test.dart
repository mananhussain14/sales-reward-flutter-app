import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/design/design.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/widgets/widgets.dart';

import '../../support/pump_app.dart';

/// The shared design system.
///
/// Every widget is asserted in **both** themes, because the whole point of the
/// token refactor is that none of them carries a hard-coded colour.
void main() {
  group('SrBrandMark', () {
    forEachBrightness((Brightness brightness) {
      testWidgets(
        'renders and is labelled for assistive tech (${brightness.name})',
        (tester) async {
          await pumpThemed(
            tester,
            const SrBrandMark(size: 40),
            brightness: brightness,
          );

          expect(find.byType(SrBrandMark), findsOneWidget);
          expect(find.bySemanticsLabel('SalesReward'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    });

    testWidgets(
      'the lockup shows the wordmark and an optional portal caption',
      (tester) async {
        await pumpThemed(tester, const SrBrandLockup(portal: 'Vendor Admin'));

        expect(find.text('SalesReward'), findsOneWidget);
        expect(find.text('VENDOR ADMIN'), findsOneWidget);
      },
    );
  });

  group('SrInitialsAvatar', () {
    test('takes the first and last word, upper-cased', () {
      expect(SrInitialsAvatar.initialsFor('Ada Lovelace'), 'AL');
      expect(SrInitialsAvatar.initialsFor('ada byron lovelace'), 'AL');
    });

    test('a single word contributes two characters', () {
      expect(SrInitialsAvatar.initialsFor('Ada'), 'AD');
      expect(SrInitialsAvatar.initialsFor('A'), 'A');
    });

    test('falls back rather than rendering nothing', () {
      expect(SrInitialsAvatar.initialsFor(null), 'SR');
      expect(SrInitialsAvatar.initialsFor('   '), 'SR');
      expect(SrInitialsAvatar.initialsFor('', fallback: 'VA'), 'VA');
    });
  });

  group('SrButton', () {
    forEachBrightness((Brightness brightness) {
      testWidgets('every variant renders (${brightness.name})', (tester) async {
        for (final SrButtonVariant variant in SrButtonVariant.values) {
          await pumpThemed(
            tester,
            SrButton(label: variant.name, variant: variant, onPressed: () {}),
            brightness: brightness,
          );
          expect(find.text(variant.name), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      });
    });

    testWidgets('a null handler disables the control', (tester) async {
      await pumpThemed(tester, const SrButton(label: 'Submit'));

      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
    });

    testWidgets('loading shows a spinner, swaps the label and disables', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        SrButton(
          label: 'Sign in',
          loading: true,
          loadingLabel: 'Signing in…',
          onPressed: () {},
        ),
      );

      expect(find.text('Signing in…'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
        reason:
            'onboard_vendor_retailer() has no server-side idempotency, so a '
            'double submit must be impossible from the control itself',
      );
    });

    testWidgets('md and lg clear the 44pt touch target', (tester) async {
      for (final SrButtonSize size in <SrButtonSize>[
        SrButtonSize.md,
        SrButtonSize.lg,
      ]) {
        expect(size.height, greaterThanOrEqualTo(44));
      }
    });
  });

  group('SrBadge and SrStatusBadge', () {
    forEachBrightness((Brightness brightness) {
      testWidgets('every tone renders (${brightness.name})', (tester) async {
        for (final SrTone tone in SrTone.values) {
          await pumpThemed(
            tester,
            SrBadge(label: tone.name, tone: tone),
            brightness: brightness,
          );
          expect(find.text(tone.name), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      });
    });

    test('maps every documented backend status', () {
      const Map<String, String> expected = <String, String>{
        'ACTIVE': 'Active',
        'ACCEPTED': 'Accepted',
        'APPROVED': 'Approved',
        'INVITED': 'Invited',
        'PENDING': 'Pending',
        'AWAITING': 'Awaiting acceptance',
        'SUSPENDED': 'Suspended',
        'PROCESSING': 'Processing',
        'UPLOADED': 'Uploaded',
        'SUBMITTED': 'Submitted',
        'EXPIRED': 'Expired',
        'REVOKED': 'Revoked',
        'DEACTIVATED': 'Deactivated',
        'INACTIVE': 'Inactive',
        'FAILED': 'Failed',
        'REJECTED': 'Rejected',
      };

      expected.forEach((String status, String label) {
        expect(SrStatusBadge.labelFor(status), label);
      });
    });

    test('an unrecognised status never leaks the raw enum', () {
      expect(SrStatusBadge.labelFor('SOME_FUTURE_STATE'), 'Unknown');
      expect(SrStatusBadge.labelFor(''), 'Unknown');
    });

    test('a null derived_state renders rather than crashing', () {
      // list_retailer_staff_invitations().derived_state has no ELSE in SQL and
      // can genuinely be NULL — contract fix #2.
      expect(SrStatusBadge.labelFor(null), 'Unknown');
    });

    testWidgets('renders the mapped label, not the enum', (tester) async {
      await pumpThemed(tester, const SrStatusBadge(status: 'AWAITING'));

      expect(find.text('Awaiting acceptance'), findsOneWidget);
      expect(find.text('AWAITING'), findsNothing);
    });
  });

  group('SrCard', () {
    forEachBrightness((Brightness brightness) {
      testWidgets('every variant renders (${brightness.name})', (tester) async {
        for (final SrCardVariant variant in SrCardVariant.values) {
          await pumpThemed(
            tester,
            SrCard(variant: variant, child: Text(variant.name)),
            brightness: brightness,
          );
          expect(find.text(variant.name), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      });
    });

    testWidgets('a section card shows its title, description and body', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        const SrSectionCard(
          title: 'Assigned shops',
          description: 'Read-only.',
          child: Text('body'),
        ),
      );

      expect(find.text('Assigned shops'), findsOneWidget);
      expect(find.text('Read-only.'), findsOneWidget);
      expect(find.text('body'), findsOneWidget);
    });
  });

  group('SrStatCard', () {
    test('formats with grouped digits in a fixed locale', () {
      expect(SrStatCard.format(0), '0');
      expect(SrStatCard.format(42), '42');
      expect(SrStatCard.format(1000), '1,000');
      expect(SrStatCard.format(1234567), '1,234,567');
      expect(SrStatCard.format(-1500), '-1,500');
    });

    forEachBrightness((Brightness brightness) {
      testWidgets('null renders "Unavailable", never 0 (${brightness.name})', (
        tester,
      ) async {
        await pumpThemed(
          tester,
          const SrStatCard(label: 'Members', value: null, hint: 'hint'),
          brightness: brightness,
        );

        expect(find.text('Unavailable'), findsOneWidget);
        expect(find.text('0'), findsNothing);
        expect(find.text('—'), findsNothing);
      });
    });

    testWidgets('zero is a real figure and renders as 0', (tester) async {
      await pumpThemed(
        tester,
        const SrStatCard(label: 'Members', value: 0, hint: 'hint'),
      );

      expect(find.text('0'), findsOneWidget);
      expect(find.text('Unavailable'), findsNothing);
    });
  });

  group('SrTextField', () {
    forEachBrightness((Brightness brightness) {
      testWidgets('renders label, control and hint (${brightness.name})', (
        tester,
      ) async {
        await pumpThemed(
          tester,
          const SrTextField(label: 'Email address', hint: 'We never share it.'),
          brightness: brightness,
        );

        expect(find.text('Email address (optional)'), findsOneWidget);
        expect(find.text('We never share it.'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
      });
    });

    testWidgets('an error replaces the hint, below the control', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        const SrTextField(
          label: 'Email address',
          hint: 'We never share it.',
          errorText: 'Enter a valid address.',
          required: true,
        ),
      );

      expect(find.text('Enter a valid address.'), findsOneWidget);
      expect(find.text('We never share it.'), findsNothing);

      // The message sits below the control, never between label and input.
      final double controlY = tester.getTopLeft(find.byType(TextField)).dy;
      final double messageY = tester
          .getTopLeft(find.text('Enter a valid address.'))
          .dy;
      expect(messageY, greaterThan(controlY));
    });

    testWidgets('a required field shows a visible marker', (tester) async {
      await pumpThemed(
        tester,
        const SrTextField(label: 'Shop', required: true),
      );

      // Requirement is never signalled by colour alone.
      expect(find.textContaining('*'), findsOneWidget);
    });
  });

  group('SrAlert', () {
    forEachBrightness((Brightness brightness) {
      testWidgets('every tone renders with its message (${brightness.name})', (
        tester,
      ) async {
        for (final SrAlertTone tone in SrAlertTone.values) {
          await pumpThemed(
            tester,
            SrAlert(tone: tone, message: 'message ${tone.name}'),
            brightness: brightness,
          );
          expect(find.text('message ${tone.name}'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      });
    });

    testWidgets('carries an icon as well as a colour', (tester) async {
      await pumpThemed(
        tester,
        const SrAlert(tone: SrAlertTone.error, message: 'failed'),
      );

      // Meaning is never carried by colour alone.
      expect(find.byType(Icon), findsOneWidget);
    });
  });

  group('loading state', () {
    forEachBrightness((Brightness brightness) {
      testWidgets(
        'renders skeletons, not a page spinner (${brightness.name})',
        (tester) async {
          await pumpThemed(
            tester,
            const SrLoadingView(),
            brightness: brightness,
          );
          await tester.pump(const Duration(milliseconds: 100));

          expect(find.byType(SrSkeleton), findsWidgets);
          expect(
            find.byType(CircularProgressIndicator),
            findsNothing,
            reason:
                'skeletons, not spinners, are this product\'s loading language',
          );
        },
      );
    });

    testWidgets('announces a generic busy label that names nothing', (
      tester,
    ) async {
      await pumpThemed(tester, const SrLoadingView());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.bySemanticsLabel('Loading…'), findsOneWidget);
    });

    testWidgets('keeps the placeholder under reduced motion', (tester) async {
      useSurface(tester, phoneSurface);
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(home: Scaffold(body: SrLoadingView())),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // The sweep is dropped; the block is not.
      expect(find.byType(SrSkeleton), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('empty state', () {
    forEachBrightness((Brightness brightness) {
      testWidgets('shows title, description and action (${brightness.name})', (
        tester,
      ) async {
        await pumpThemed(
          tester,
          SrEmptyState(
            icon: Icons.group_outlined,
            title: 'No staff yet',
            description: 'Invite someone to get started.',
            action: SrButton(label: 'Invite', onPressed: () {}),
          ),
          brightness: brightness,
        );

        expect(find.text('No staff yet'), findsOneWidget);
        expect(find.text('Invite someone to get started.'), findsOneWidget);
        expect(find.text('Invite'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('renders without an icon or an action', (tester) async {
      await pumpThemed(tester, const SrEmptyState(title: 'No shops to show'));

      expect(find.text('No shops to show'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('failure state', () {
    forEachBrightness((Brightness brightness) {
      testWidgets('every failure renders copy (${brightness.name})', (
        tester,
      ) async {
        const List<Failure> failures = <Failure>[
          DeniedFailure(),
          UnauthenticatedFailure(),
          DuplicateFailure(),
          InvalidFailure(),
          NotReadyFailure(),
          UnavailableFailure(),
          NotImplementedFailure(capability: 'some_rpc()'),
        ];

        for (final Failure failure in failures) {
          await pumpThemed(
            tester,
            SrFailureView(failure: failure),
            brightness: brightness,
          );
          expect(
            find.text(SrFailureView.copyFor(failure).title),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      });
    });

    testWidgets('an outage offers a retry', (tester) async {
      await pumpThemed(
        tester,
        SrFailureView(failure: const UnavailableFailure(), onRetry: () {}),
      );

      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a denial does not offer a retry, even when one is passed', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        SrFailureView(failure: const DeniedFailure(), onRetry: () {}),
      );

      expect(find.text('Try again'), findsNothing);
    });

    test('a denial never reads as "not found"', () {
      // 42501 is deliberately overloaded in SQL so it is not an existence
      // oracle. The copy must not undo that.
      final SrFailureCopy copy = SrFailureView.copyFor(const DeniedFailure());
      for (final String forbidden in <String>[
        'not found',
        'does not exist',
        'no such',
      ]) {
        expect(copy.title.toLowerCase(), isNot(contains(forbidden)));
        expect(copy.description.toLowerCase(), isNot(contains(forbidden)));
      }
    });

    test('an outage never reads as a denial', () {
      final SrFailureCopy copy = SrFailureView.copyFor(
        const UnavailableFailure(),
      );
      for (final String forbidden in <String>[
        'access',
        'permission',
        'denied',
        'authoriz',
      ]) {
        expect(copy.title.toLowerCase(), isNot(contains(forbidden)));
        expect(copy.description.toLowerCase(), isNot(contains(forbidden)));
      }
      expect(copy.retryable, isTrue);
    });
  });

  group('access-denied surface', () {
    forEachBrightness((Brightness brightness) {
      testWidgets('renders the fixed copy (${brightness.name})', (
        tester,
      ) async {
        await pumpThemed(
          tester,
          const SrAccessDeniedView(),
          brightness: brightness,
        );

        expect(find.text('Access denied'), findsOneWidget);
        expect(find.byType(SrBrandLockup), findsOneWidget);
        expect(find.text('Sign out'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });
}
