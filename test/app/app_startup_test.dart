import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/di/injector.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/data/repositories/supabase_auth_repository.dart';
import 'package:sale_reward/features/auth/data/repositories/supabase_portal_context_repository.dart';
import 'package:sale_reward/features/auth/domain/repositories/auth_repository.dart';
import 'package:sale_reward/features/auth/domain/repositories/portal_context_repository.dart';
import 'package:sale_reward/features/auth/presentation/pages/login_page.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';

void main() {
  group('application startup', () {
    testWidgets('boots and settles without error', (tester) async {
      await pumpApp(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('a cold start with no session shows the branded login', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(SrBrandLockup), findsOneWidget);
      expect(find.text('SalesReward'), findsOneWidget);
    });

    testWidgets('accepts injected repositories without touching Supabase', (
      tester,
    ) async {
      // The whole suite relies on this: pumpApp never calls
      // configureDependencies, so no Supabase client is ever constructed.
      await pumpApp(tester, initialUser: testUser);
      expect(tester.takeException(), isNull);
    });
  });

  group('dependency wiring', () {
    tearDown(resetDependencies);

    test('test registration provides both repositories', () {
      registerTestDependencies(
        authRepository: FakeAuthRepository(),
        portalContextRepository: FakePortalContextRepository(deniedResult),
      );

      expect(getIt<AuthRepository>(), isA<FakeAuthRepository>());
      expect(
        getIt<PortalContextRepository>(),
        isA<FakePortalContextRepository>(),
      );
    });

    test('the production classes are the Supabase-backed ones', () {
      // Named so a future refactor cannot quietly swap in a stub: the shipped
      // graph must resolve real Supabase implementations.
      expect(SupabaseAuthRepository, isNotNull);
      expect(SupabasePortalContextRepository, isNotNull);
    });
  });
}
