import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/auth/data/repositories/unimplemented_portal_context_repository.dart';
import 'package:sale_reward/features/auth/domain/entities/app_role.dart';
import 'package:sale_reward/features/auth/domain/repositories/portal_context_repository.dart';
import 'package:sale_reward/features/auth/presentation/bloc/role_session_bloc.dart';

/// A stub that answers with whatever the test hands it.
class _StubRepository implements PortalContextRepository {
  _StubRepository(this._result);

  final PortalContextResult _result;

  @override
  Future<PortalContextResult> resolve() async => _result;
}

void main() {
  group('AppRole', () {
    test('covers exactly the four application roles', () {
      expect(AppRole.values, hasLength(4));
      expect(
        AppRole.values.map((AppRole r) => r.displayName),
        containsAll(<String>[
          'Vendor Super Admin',
          'Retailer Owner',
          'Retailer Manager',
          'Sales Staff',
        ]),
      );
    });

    test('maps to the backend kind vocabulary', () {
      expect(AppRole.vendorSuperAdmin.wireKind, 'vendor');
      expect(AppRole.retailerOwner.wireKind, 'owner');
      expect(AppRole.retailerManager.wireKind, 'reader');
      expect(AppRole.salesStaff.wireKind, 'submitter');
    });

    test('parses a known kind', () {
      for (final AppRole role in AppRole.values) {
        expect(AppRole.fromWireKind(role.wireKind), role);
      }
    });

    test('fails closed on none, null and anything unrecognized', () {
      expect(AppRole.fromWireKind('none'), isNull);
      expect(AppRole.fromWireKind(null), isNull);
      expect(AppRole.fromWireKind(''), isNull);
      expect(AppRole.fromWireKind('VENDOR'), isNull);
      expect(AppRole.fromWireKind('superuser'), isNull);
    });
  });

  group('ResolvedRole', () {
    test('a preview role is never server-resolved', () {
      const ResolvedRole preview = ResolvedRole.preview(AppRole.salesStaff);

      expect(preview.trust, RoleTrust.localPreview);
      expect(preview.isServerResolved, isFalse);
      expect(preview.retailerName, isNull);
    });

    test('a server-resolved role reports its provenance', () {
      const ResolvedRole resolved = ResolvedRole(
        role: AppRole.retailerOwner,
        trust: RoleTrust.serverResolved,
        retailerName: 'Example Retail',
      );

      expect(resolved.isServerResolved, isTrue);
      expect(resolved.retailerName, 'Example Retail');
    });

    test('provenance is part of identity', () {
      expect(
        const ResolvedRole.preview(AppRole.salesStaff),
        isNot(
          const ResolvedRole(
            role: AppRole.salesStaff,
            trust: RoleTrust.serverResolved,
          ),
        ),
      );
    });
  });

  group('UnimplementedPortalContextRepository', () {
    test(
      'reports the missing capability rather than guessing a role',
      () async {
        const UnimplementedPortalContextRepository repository =
            UnimplementedPortalContextRepository();

        final PortalContextResult result = await repository.resolve();

        expect(result, isA<PortalContextFailed>());
        final Failure failure = (result as PortalContextFailed).failure;
        expect(failure, isA<NotImplementedFailure>());
        expect(
          (failure as NotImplementedFailure).capability,
          'get_my_portal_context()',
        );
      },
    );

    test('never reports a denial', () async {
      // A missing RPC is not an authorization answer. Reporting DeniedFailure
      // here would tell users they lack access to something nobody has built.
      final PortalContextResult result =
          await const UnimplementedPortalContextRepository().resolve();

      expect(
        (result as PortalContextFailed).failure,
        isNot(isA<DeniedFailure>()),
      );
    });
  });

  group('RoleSessionBloc', () {
    blocTest<RoleSessionBloc, RoleSessionState>(
      'starts with no role in effect',
      build: () => RoleSessionBloc(
        repository: const UnimplementedPortalContextRepository(),
      ),
      verify: (RoleSessionBloc bloc) {
        expect(bloc.state, isA<RoleSessionInitial>());
        expect(bloc.state.resolved, isNull);
      },
    );

    blocTest<RoleSessionBloc, RoleSessionState>(
      'resolves to a failure that names the unbuilt backend capability',
      build: () => RoleSessionBloc(
        repository: const UnimplementedPortalContextRepository(),
      ),
      act: (RoleSessionBloc bloc) =>
          bloc.add(const RoleSessionResolveRequested()),
      expect: () => <Matcher>[
        isA<RoleSessionResolving>(),
        isA<RoleSessionFailed>().having(
          (RoleSessionFailed s) => s.isUnimplemented,
          'isUnimplemented',
          isTrue,
        ),
      ],
    );

    blocTest<RoleSessionBloc, RoleSessionState>(
      'a resolved backend role is marked server-resolved',
      build: () => RoleSessionBloc(
        repository: _StubRepository(
          const PortalContextResolved(
            ResolvedRole(
              role: AppRole.retailerManager,
              trust: RoleTrust.serverResolved,
            ),
          ),
        ),
      ),
      act: (RoleSessionBloc bloc) =>
          bloc.add(const RoleSessionResolveRequested()),
      skip: 1,
      expect: () => <Matcher>[
        isA<RoleSessionActive>().having(
          (RoleSessionActive s) => s.role.isServerResolved,
          'isServerResolved',
          isTrue,
        ),
      ],
    );

    blocTest<RoleSessionBloc, RoleSessionState>(
      'kind = none becomes no-access, not a failure',
      build: () => RoleSessionBloc(
        repository: _StubRepository(const PortalContextNone()),
      ),
      act: (RoleSessionBloc bloc) =>
          bloc.add(const RoleSessionResolveRequested()),
      skip: 1,
      expect: () => <Matcher>[isA<RoleSessionNoAccess>()],
    );

    blocTest<RoleSessionBloc, RoleSessionState>(
      'a transport failure is unavailable, never a denial',
      build: () => RoleSessionBloc(
        repository: _StubRepository(
          const PortalContextFailed(UnavailableFailure()),
        ),
      ),
      act: (RoleSessionBloc bloc) =>
          bloc.add(const RoleSessionResolveRequested()),
      skip: 1,
      expect: () => <Matcher>[
        isA<RoleSessionFailed>().having(
          (RoleSessionFailed s) => s.failure,
          'failure',
          isA<UnavailableFailure>(),
        ),
      ],
    );

    blocTest<RoleSessionBloc, RoleSessionState>(
      'a previewed role is always marked as a local preview',
      build: () => RoleSessionBloc(
        repository: const UnimplementedPortalContextRepository(),
      ),
      act: (RoleSessionBloc bloc) =>
          bloc.add(const RoleSessionPreviewSelected(AppRole.vendorSuperAdmin)),
      expect: () => <Matcher>[
        isA<RoleSessionActive>()
            .having(
              (RoleSessionActive s) => s.role.role,
              'role',
              AppRole.vendorSuperAdmin,
            )
            .having(
              (RoleSessionActive s) => s.role.trust,
              'trust',
              RoleTrust.localPreview,
            )
            .having(
              (RoleSessionActive s) => s.role.isServerResolved,
              'isServerResolved',
              isFalse,
            ),
      ],
    );

    blocTest<RoleSessionBloc, RoleSessionState>(
      'clearing drops the role in effect',
      build: () => RoleSessionBloc(
        repository: const UnimplementedPortalContextRepository(),
      ),
      act: (RoleSessionBloc bloc) => bloc
        ..add(const RoleSessionPreviewSelected(AppRole.salesStaff))
        ..add(const RoleSessionCleared()),
      expect: () => <Matcher>[
        isA<RoleSessionActive>(),
        isA<RoleSessionInitial>(),
      ],
      verify: (RoleSessionBloc bloc) => expect(bloc.state.resolved, isNull),
    );
  });
}
