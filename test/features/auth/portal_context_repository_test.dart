import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/auth/data/datasources/portal_context_data_source.dart';
import 'package:sale_reward/features/auth/data/repositories/supabase_portal_context_repository.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/domain/repositories/portal_context_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  Map<String, Object?> ownerBody() => <String, Object?>{
    'context_version': 1,
    'portal_kind': 'RETAILER_OWNER',
    'vendor': null,
    'retailer': <String, Object?>{
      'kind': 'RETAILER_OWNER',
      'organization_id': '22222222-2222-2222-2222-222222222222',
      'organization_name': 'Retail Co',
      'capabilities': <String, Object?>{
        'view_retailer_overview': true,
        'view_shops': true,
        'view_staff': true,
        'manage_staff': true,
        'assign_staff_shops': true,
        'view_assigned_products': true,
        'submit_receipts': false,
      },
    },
  };

  /// Builds a repository whose invoker returns [body] or throws [error], and
  /// records that it was called with no arguments (the invoker is nullary, so
  /// there is nothing to record but the call itself).
  ({SupabasePortalContextRepository repo, int Function() calls}) repository({
    Object? body,
    Object? error,
  }) {
    int calls = 0;
    Future<Object?> invoker() async {
      calls++;
      if (error != null) {
        throw error;
      }
      return body;
    }

    return (
      repo: SupabasePortalContextRepository(PortalContextDataSource(invoker)),
      calls: () => calls,
    );
  }

  group('the RPC contract', () {
    test('the RPC name is exactly get_my_portal_context', () {
      expect(getMyPortalContextRpc, 'get_my_portal_context');
    });

    test('the invoker signature accepts no arguments at all', () {
      // A compile-time guarantee: PortalContextInvoker is a nullary function, so
      // no user id, email, organization, role, token or tenant can be passed at
      // this boundary. This test documents the property; that it compiles is the
      // proof.
      const PortalContextInvoker invoker = _noArgInvoker;
      expect(invoker, isA<Future<Object?> Function()>());
    });

    test('resolve calls the RPC exactly once', () async {
      final repo = repository(body: ownerBody());
      await repo.repo.resolve();
      expect(repo.calls(), 1);
    });
  });

  group('classification', () {
    test('a valid body resolves to the parsed context', () async {
      final repo = repository(body: ownerBody());
      final PortalContextResult result = await repo.repo.resolve();
      expect(result, isA<PortalContextResolved>());
      expect(
        (result as PortalContextResolved).context.portalKind,
        PortalKind.retailerOwner,
      );
      expect(result.context.capabilities.submitReceipts, isFalse);
    });

    test('a NONE body is a denial, not a failure', () async {
      final repo = repository(
        body: <String, Object?>{
          'context_version': 1,
          'portal_kind': 'NONE',
          'vendor': null,
          'retailer': null,
        },
      );
      expect(await repo.repo.resolve(), isA<PortalContextDenied>());
    });

    test('a thrown Postgres error is an operational failure', () async {
      final repo = repository(
        error: const PostgrestException(message: 'boom', code: 'XX000'),
      );
      final PortalContextResult result = await repo.repo.resolve();
      expect(result, isA<PortalContextFailed>());
      expect(
        (result as PortalContextFailed).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('a signed-out refusal (42501) maps to a denial failure, not NONE', () {
      // The RPC is granted only to `authenticated`; a call without a session is
      // a transport refusal. It is a *failure* discriminant, never the NONE
      // decision — the two must stay distinguishable.
      expectLater(
        repository(
          error: const PostgrestException(message: 'denied', code: '42501'),
        ).repo.resolve(),
        completion(isA<PortalContextFailed>()),
      );
    });

    test('a malformed body is a failure, not a denial', () async {
      final repo = repository(
        body: <String, Object?>{'context_version': 99, 'portal_kind': 'NONE'},
      );
      final PortalContextResult result = await repo.repo.resolve();
      expect(result, isA<PortalContextFailed>());
      expect(
        (result as PortalContextFailed).failure,
        isA<UnavailableFailure>(),
      );
    });

    test(
      'an arbitrary transport exception is an operational failure',
      () async {
        final repo = repository(error: Exception('offline'));
        expect(await repo.repo.resolve(), isA<PortalContextFailed>());
      },
    );
  });
}

Future<Object?> _noArgInvoker() async => null;
