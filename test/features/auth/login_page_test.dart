import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/theme/app_theme.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/domain/repositories/auth_repository.dart';
import 'package:sale_reward/features/auth/presentation/pages/login_page.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';

void main() {
  Future<void> pumpLogin(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    Size surface = phoneSurface,
  }) async {
    useSurface(tester, surface);
    final FakeAuthRepository auth = FakeAuthRepository();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      RepositoryProvider<AuthRepository>.value(
        value: auth,
        child: MaterialApp(
          theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
          home: const LoginPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('layout', () {
    for (final Size surface in <Size>[smallPhoneSurface, phoneSurface]) {
      testWidgets('does not overflow at ${surface.width}×${surface.height}', (
        tester,
      ) async {
        await pumpLogin(tester, surface: surface);
        expect(tester.takeException(), isNull);
        expect(find.text('Welcome back'), findsOneWidget);
      });
    }

    testWidgets('stays above the keyboard when it appears', (tester) async {
      await pumpLogin(tester);
      // Simulate the keyboard by injecting a bottom viewInset.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();

      expect(tester.takeException(), isNull);
      // The submit button is still reachable in the scroll view.
      expect(find.text('Sign in'), findsOneWidget);
    });
  });

  group('both themes', () {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('renders in ${brightness.name}', (tester) async {
        await pumpLogin(tester, brightness: brightness);
        expect(find.byType(SrBrandLockup), findsOneWidget);
        expect(find.byType(SrTextField), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('password visibility', () {
    testWidgets('toggles obscuring and updates its label', (tester) async {
      await pumpLogin(tester);

      expect(find.bySemanticsLabel('Show password'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Show password'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Hide password'), findsOneWidget);
    });
  });

  group('no forbidden affordances', () {
    testWidgets('shows no sign-up, forgot-password, or social login', (
      tester,
    ) async {
      await pumpLogin(tester);

      for (final String forbidden in <String>[
        'Sign up',
        'Create account',
        'Register',
        'Forgot',
        'Continue with',
      ]) {
        expect(
          find.textContaining(forbidden),
          findsNothing,
          reason: '"$forbidden" is not part of this milestone',
        );
      }
    });
  });
}
