@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/di/injector.dart';
import 'package:sale_reward/features/auth/data/repositories/unimplemented_portal_context_repository.dart';
import 'package:sale_reward/features/auth/domain/entities/app_role.dart';
import 'package:sale_reward/features/auth/domain/repositories/portal_context_repository.dart';
import 'package:sale_reward/features/auth/presentation/bloc/role_session_bloc.dart';

import '../support/pump_app.dart';

/// **No production build may hardcode a role.**
///
/// `public.get_my_portal_context()` does not exist, so this app genuinely cannot
/// know who anyone is. The failure mode this file exists to prevent is a
/// convenience default — "assume Sales Staff for now" — that survives into a
/// release and silently becomes an authorization claim the backend never made.
///
/// The role-flow map's rule: *never store a role string and branch security on
/// it; store it, if at all, only to pick a widget tree.*
void main() {
  group('the shipped dependency graph resolves no role', () {
    tearDown(resetDependencies);

    test('the only registered repository is the unimplemented one', () async {
      await configureDependencies();

      expect(
        getIt<PortalContextRepository>(),
        isA<UnimplementedPortalContextRepository>(),
      );
    });

    test('it never returns a resolved role, for any number of calls', () async {
      const UnimplementedPortalContextRepository repository =
          UnimplementedPortalContextRepository();

      for (int i = 0; i < 5; i++) {
        final PortalContextResult result = await repository.resolve();
        expect(result, isA<PortalContextFailed>());
        expect(result, isNot(isA<PortalContextResolved>()));
      }
    });

    test('resolving through the BLoC yields no role in effect', () async {
      final RoleSessionBloc bloc = RoleSessionBloc(
        repository: const UnimplementedPortalContextRepository(),
      );
      addTearDown(bloc.close);

      bloc.add(const RoleSessionResolveRequested());
      await bloc.stream.firstWhere(
        (RoleSessionState s) => s is! RoleSessionResolving,
      );

      expect(bloc.state, isA<RoleSessionFailed>());
      expect(
        bloc.state.resolved,
        isNull,
        reason: 'a missing RPC must not become a role',
      );
    });
  });

  group('a preview role is never presented as resolved', () {
    test('the preview constructor always marks local provenance', () {
      for (final AppRole role in AppRole.values) {
        final ResolvedRole preview = ResolvedRole.preview(role);
        expect(preview.trust, RoleTrust.localPreview);
        expect(preview.isServerResolved, isFalse);
      }
    });

    test('the preview event cannot produce a server-resolved role', () async {
      final RoleSessionBloc bloc = RoleSessionBloc(
        repository: const UnimplementedPortalContextRepository(),
      );
      addTearDown(bloc.close);

      for (final AppRole role in AppRole.values) {
        bloc.add(RoleSessionPreviewSelected(role));
        await bloc.stream.first;

        expect(bloc.state.resolved!.role, role);
        expect(bloc.state.resolved!.isServerResolved, isFalse);
      }
    });
  });

  group('the running app claims no role until one is chosen', () {
    testWidgets('startup leaves no role in effect', (tester) async {
      await pumpApp(tester);

      // No shell chrome of any kind: not a bar, not a rail, not a drawer.
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(Drawer), findsNothing);
    });

    testWidgets('and says so, naming the missing backend function', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(find.text('Role resolution is not connected'), findsOneWidget);
      expect(
        find.textContaining(
          UnimplementedPortalContextRepository.missingCapability,
        ),
        findsOneWidget,
      );
    });

    // One test per role: pumping the same const app twice in one test reuses
    // the element and skips initState, so the second pump would not remount.
    for (final AppRole role in AppRole.values) {
      testWidgets('the ${role.displayName} preview shell is labelled as one', (
        tester,
      ) async {
        await pumpAppInRole(tester, role);

        expect(
          find.textContaining('Interface preview'),
          findsOneWidget,
          reason: '${role.displayName} must not look resolved',
        );
        expect(find.textContaining('grants no access'), findsOneWidget);
      });
    }
  });

  group('source-level guarantees', () {
    late List<File> sources;

    setUpAll(() {
      sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList();
    });

    test('only the domain entity constructs a server-resolved role', () {
      // Anywhere else would be a client asserting an authorization answer the
      // backend never gave.
      final List<String> offenders = <String>[];

      for (final File file in sources) {
        if (file.path.endsWith('app_role.dart')) continue;

        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (line.contains('RoleTrust.serverResolved')) {
            offenders.add('${file.path}:${i + 1}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'server-resolved provenance asserted outside the entity:\n'
            '${offenders.join('\n')}',
      );
    });

    test('no source defaults a role when resolution fails', () {
      // The pattern this guards against is a *fallback* — `?? AppRole.x`, or a
      // ternary whose else-branch is a role. A named argument such as
      // `role: AppRole.salesStaff` is a declaration of which role a navigation
      // model belongs to, not a guess about the caller, so it is excluded.
      final RegExp nullCoalesced = RegExp(r'\?\?\s*(const\s+)?AppRole\.');
      final RegExp ternaryElse = RegExp(r':\s*(const\s+)?AppRole\.');
      final List<String> offenders = <String>[];

      for (final File file in sources) {
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String line = lines[i];
          final String trimmed = line.trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) {
            continue;
          }

          final bool isFallback =
              nullCoalesced.hasMatch(line) ||
              (line.contains('?') &&
                  !line.contains('??') &&
                  ternaryElse.hasMatch(line));

          if (isFallback) {
            offenders.add('${file.path}:${i + 1} → ${line.trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'a role used as a fallback value:\n${offenders.join('\n')}',
      );
    });

    test('the preview affordance is confined to the gate screen', () {
      final List<String> users = <String>[];

      for (final File file in sources) {
        if (!file.readAsStringSync().contains('RoleSessionPreviewSelected')) {
          continue;
        }
        users.add(file.path);
      }

      // Its declaration, the BLoC that handles it, and the one screen that
      // dispatches it. Nothing else may reference it.
      expect(
        users.map((String p) => p.split('/').last).toSet(),
        <String>{
          'role_session_event.dart',
          'role_session_bloc.dart',
          'role_gate_page.dart',
        },
        reason: 'the development-only showcase must not spread beyond the gate',
      );
    });

    test('no repository or data source reads a role to decide anything', () {
      for (final File file in sources) {
        if (!file.path.contains('/data/') && !file.path.contains('/domain/')) {
          continue;
        }
        // The entity itself is allowed to mention its own values.
        if (file.path.endsWith('app_role.dart')) continue;

        final String source = file.readAsStringSync();
        for (final AppRole role in AppRole.values) {
          expect(
            source.contains('AppRole.${role.name}'),
            isFalse,
            reason: '${file.path} branches on a role',
          );
        }
      }
    });
  });
}
