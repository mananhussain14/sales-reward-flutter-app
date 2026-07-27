import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/config/startup_failure.dart';
import 'package:sale_reward/app/startup_failure_app.dart';

/// The screen a failed startup renders.
///
/// The defect it replaces: `bootstrap()` validated configuration and awaited
/// `Supabase.initialize()` with no guard, so any throw escaped before
/// `runApp()`. Android keeps the activity's window background up until Flutter
/// draws its first frame and there is no native-splash plugin here to remove,
/// which means "never reached runApp" and "stuck on the splash screen" are the
/// same observable event — with the reason visible only in `logcat`.
///
/// So the requirement under test is blunt: a failed startup must still produce a
/// frame, that frame must say something true, and it must not say anything a
/// user should not see.
void main() {
  Future<void> pump(
    WidgetTester tester,
    StartupFailure failure, {
    Future<void> Function()? onRetry,
  }) =>
      tester.pumpWidget(StartupFailureApp(failure: failure, onRetry: onRetry));

  group('it renders a frame for every failure', () {
    for (final StartupFailure failure in StartupFailure.values) {
      testWidgets('${failure.name} produces a readable screen', (tester) async {
        await pump(tester, failure);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(MaterialApp), findsOneWidget);
        // Something explanatory is on screen — not a blank background.
        expect(find.byType(Text), findsWidgets);
      });
    }
  });

  group('retry is offered only when it could work', () {
    for (final StartupFailure failure in <StartupFailure>[
      StartupFailure.timedOut,
      StartupFailure.initializationFailed,
    ]) {
      testWidgets('${failure.name} offers a retry', (tester) async {
        await pump(tester, failure, onRetry: () async {});
        await tester.pumpAndSettle();

        expect(find.text('Try again'), findsOneWidget);
      });
    }

    for (final StartupFailure failure in <StartupFailure>[
      StartupFailure.missingConfiguration,
      StartupFailure.invalidConfiguration,
    ]) {
      testWidgets('${failure.name} offers no retry', (tester) async {
        // The values are compiled into the binary. A retry would read the same
        // empty or malformed string and fail identically, and a control that
        // cannot work is worse than none.
        await pump(tester, failure, onRetry: () async {});
        await tester.pumpAndSettle();

        expect(find.text('Try again'), findsNothing);
      });
    }

    testWidgets('a retry runs the supplied initialization once', (
      tester,
    ) async {
      int calls = 0;
      await pump(
        tester,
        StartupFailure.initializationFailed,
        onRetry: () async => calls++,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(calls, 1);
    });

    testWidgets('the retry control blocks a second concurrent press', (
      tester,
    ) async {
      int calls = 0;
      await pump(
        tester,
        StartupFailure.timedOut,
        onRetry: () async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        },
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Try again'));
      await tester.pump();

      // The control is now in its loading state: the label has changed and the
      // underlying button is disabled, so a second press cannot start a second
      // initialization while the first is still running.
      expect(find.text('Starting…'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);

      await tester.tap(find.byType(TextButton), warnIfMissed: false);
      await tester.pump();

      await tester.pumpAndSettle();
      expect(calls, 1);
    });
  });

  group('the screen is safe to show anyone', () {
    testWidgets('no failure names an internal detail', (tester) async {
      for (final StartupFailure failure in StartupFailure.values) {
        await pump(tester, failure);
        await tester.pumpAndSettle();

        final Iterable<String> shown = tester
            .widgetList<Text>(find.byType(Text))
            .map((Text t) => t.data ?? '')
            .map((String s) => s.toLowerCase());
        final String all = shown.join(' ');

        for (final String forbidden in <String>[
          'supabase',
          'https://',
          'sb_publishable',
          'anon',
          'apikey',
          'token',
          'exception',
          'stateerror',
          'stack',
          'postgres',
          'sqlstate',
          'null check',
        ]) {
          expect(
            all.contains(forbidden),
            isFalse,
            reason:
                '${failure.name} shows "$forbidden"; the startup screen must '
                'not name backend internals, credentials or exceptions',
          );
        }
      }
    });
  });
}
