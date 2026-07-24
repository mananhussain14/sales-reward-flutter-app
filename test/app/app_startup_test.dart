import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/app.dart';
import 'package:sale_reward/app/di/injector.dart';
import 'package:sale_reward/core/widgets/widgets.dart';
import 'package:sale_reward/features/auth/data/repositories/unimplemented_portal_context_repository.dart';
import 'package:sale_reward/features/auth/domain/entities/app_role.dart';
import 'package:sale_reward/features/auth/domain/repositories/portal_context_repository.dart';

import '../support/pump_app.dart';

void main() {
  group('application startup', () {
    testWidgets('boots, resolves the role, and settles without error', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('shows the SalesReward brand lockup on the entry screen', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(find.byType(SrBrandLockup), findsOneWidget);
      expect(find.text('SalesReward'), findsOneWidget);
    });

    testWidgets(
      'states plainly that backend role resolution is not connected, and '
      'names the missing capability',
      (tester) async {
        await pumpApp(tester);

        expect(find.text('Role resolution is not connected'), findsOneWidget);
        expect(
          find.textContaining(
            UnimplementedPortalContextRepository.missingCapability,
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('does not claim any role is in effect at startup', (
      tester,
    ) async {
      await pumpApp(tester);

      // Role names appear only as preview controls, never as an active shell
      // caption — there is no shell yet.
      for (final AppRole role in AppRole.values) {
        expect(
          find.widgetWithText(TextButton, role.displayName),
          findsOneWidget,
          reason: '${role.displayName} should be offered only as a preview',
        );
      }
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('offers a preview entry point for all four roles', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(AppRole.values, hasLength(4));
      expect(find.text('Vendor Super Admin'), findsOneWidget);
      expect(find.text('Retailer Owner'), findsOneWidget);
      expect(find.text('Retailer Manager'), findsOneWidget);
      expect(find.text('Sales Staff'), findsOneWidget);
    });

    testWidgets('labels the preview controls as granting no access', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(find.textContaining('grants no access'), findsOneWidget);
    });
  });

  group('dependency wiring', () {
    tearDown(resetDependencies);

    test('registers the portal context repository', () async {
      await configureDependencies();

      expect(getIt.isRegistered<PortalContextRepository>(), isTrue);
      expect(
        getIt<PortalContextRepository>(),
        isA<UnimplementedPortalContextRepository>(),
        reason:
            'the only implementation reports the missing RPC rather than '
            'guessing a role',
      );
    });

    test('is idempotent', () async {
      await configureDependencies();
      await configureDependencies();

      expect(getIt.isRegistered<PortalContextRepository>(), isTrue);
    });

    testWidgets('the app accepts an injected repository override', (
      tester,
    ) async {
      useSurface(tester, phoneSurface);

      // No configureDependencies() call: the override must be enough.
      await tester.pumpWidget(
        const SaleRewardApp(
          portalContextRepository: UnimplementedPortalContextRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
