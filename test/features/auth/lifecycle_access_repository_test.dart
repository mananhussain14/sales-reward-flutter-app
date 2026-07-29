import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:sale_reward/core/parsing/rpc_row.dart';
import 'package:sale_reward/features/auth/data/datasources/lifecycle_access_rpc_data_source.dart';
import 'package:sale_reward/features/auth/data/repositories/supabase_lifecycle_access_repository.dart';
import 'package:sale_reward/features/auth/domain/entities/lifecycle_access_state.dart';
import 'package:sale_reward/features/auth/domain/repositories/lifecycle_access_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Counts invocations and scripts one answer.
///
/// The invoker is nullary, so this fake could not record an argument even if the
/// repository tried to pass one — which is the point being asserted.
class _Invoker {
  _Invoker({this.body, this.error, this.delay = Duration.zero});

  Object? body;
  Object? error;
  Duration delay;
  int callCount = 0;

  LifecycleAccessInvoker get call => () async {
    callCount++;
    if (delay != Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (error != null) {
      throw error!;
    }
    return body;
  };
}

SupabaseLifecycleAccessRepository _repositoryFor(
  _Invoker invoker, {
  Duration timeout = lifecycleAccessTimeout,
}) => SupabaseLifecycleAccessRepository(
  LifecycleAccessRpcDataSource(invoker.call),
  timeout: timeout,
);

List<Object?> body(Object? accessState) => <Object?>[
  <String, Object?>{'access_state': accessState},
];

void main() {
  group('the RPC surface', () {
    test('names exactly get_my_lifecycle_access_state', () {
      expect(getMyLifecycleAccessStateRpc, 'get_my_lifecycle_access_state');
    });

    test('the invoker typedef is nullary, so no argument is expressible', () {
      // A compile-time property, asserted at runtime for the record: the
      // repository can only ever call `_invoke()`.
      const LifecycleAccessInvoker invoker = _nullaryProbe;
      expect(invoker, isA<Future<Object?> Function()>());
    });

    test('a read performs exactly one fetch', () async {
      final _Invoker invoker = _Invoker(body: body('ACTIVE'));

      await _repositoryFor(invoker).read();

      expect(invoker.callCount, 1);
    });

    test('a failed read is not retried', () async {
      final _Invoker invoker = _Invoker(
        error: const PostgrestException(message: 'nope', code: '42501'),
      );

      final LifecycleAccessResult result = await _repositoryFor(invoker).read();

      expect(result, isA<LifecycleAccessUnavailable>());
      expect(invoker.callCount, 1);
    });
  });

  group('resolved states', () {
    final Map<String, LifecycleAccessState> cases =
        <String, LifecycleAccessState>{
          'ACTIVE': LifecycleAccessState.active,
          'ORGANIZATION_INACTIVE': LifecycleAccessState.organizationInactive,
          'MEMBERSHIP_INACTIVE': LifecycleAccessState.membershipInactive,
          'PROFILE_INACTIVE': LifecycleAccessState.profileInactive,
          'NO_SUPPORTED_ACCESS': LifecycleAccessState.noSupportedAccess,
          'AMBIGUOUS': LifecycleAccessState.ambiguous,
        };

    for (final MapEntry<String, LifecycleAccessState> entry in cases.entries) {
      test('${entry.key} resolves', () async {
        final _Invoker invoker = _Invoker(body: body(entry.key));

        final LifecycleAccessResult result = await _repositoryFor(
          invoker,
        ).read();

        expect(result, isA<LifecycleAccessResolved>());
        expect((result as LifecycleAccessResolved).state, entry.value);
      });
    }
  });

  group('every failure collapses to unavailable', () {
    Future<void> expectUnavailable(Object error) async {
      final _Invoker invoker = _Invoker(error: error);

      final LifecycleAccessResult result = await _repositoryFor(invoker).read();

      expect(
        result,
        isA<LifecycleAccessUnavailable>(),
        reason: '$error must not be distinguishable',
      );
    }

    test('PostgrestException 42501', () {
      return expectUnavailable(
        const PostgrestException(message: 'insufficient', code: '42501'),
      );
    });

    test('PostgrestException 55000', () {
      return expectUnavailable(
        const PostgrestException(message: 'not ready', code: '55000'),
      );
    });

    test('PostgrestException 22P02', () {
      return expectUnavailable(
        const PostgrestException(message: 'bad text', code: '22P02'),
      );
    });

    test('PostgrestException with no code at all', () {
      return expectUnavailable(const PostgrestException(message: 'unknown'));
    });

    test('AuthException', () {
      return expectUnavailable(const AuthException('no session'));
    });

    test('ClientException', () {
      return expectUnavailable(ClientException('connection closed'));
    });

    test('TimeoutException', () {
      return expectUnavailable(TimeoutException('slow'));
    });

    test('RpcFormatException thrown from the parser', () {
      return expectUnavailable(const RpcFormatException('synthetic'));
    });

    test('an arbitrary Object', () {
      return expectUnavailable(Object());
    });

    test('a plain String thrown as an error', () {
      return expectUnavailable('boom');
    });

    test('a StateError', () {
      return expectUnavailable(StateError('bad state'));
    });
  });

  group('malformed bodies become unavailable, never a state', () {
    Future<void> expectUnavailableBody(Object? raw) async {
      final _Invoker invoker = _Invoker(body: raw);

      final LifecycleAccessResult result = await _repositoryFor(invoker).read();

      expect(result, isA<LifecycleAccessUnavailable>());
    }

    test('null body', () => expectUnavailableBody(null));
    test('empty list', () => expectUnavailableBody(<Object?>[]));
    test('two rows', () {
      return expectUnavailableBody(<Object?>[
        <String, Object?>{'access_state': 'ACTIVE'},
        <String, Object?>{'access_state': 'AMBIGUOUS'},
      ]);
    });
    test('bare map root', () {
      return expectUnavailableBody(<String, Object?>{'access_state': 'ACTIVE'});
    });
    test('missing field', () {
      return expectUnavailableBody(<Object?>[<String, Object?>{}]);
    });
    test('null field', () => expectUnavailableBody(body(null)));
    test('numeric field', () => expectUnavailableBody(body(7)));
    test('lower-case value', () => expectUnavailableBody(body('active')));
    test('padded value', () => expectUnavailableBody(body(' ACTIVE ')));
    test('unknown value', () => expectUnavailableBody(body('WHAT')));
  });

  group('the timeout branch', () {
    test('a call that outruns the bound becomes unavailable', () async {
      final _Invoker invoker = _Invoker(
        body: body('ACTIVE'),
        delay: const Duration(milliseconds: 60),
      );

      final LifecycleAccessResult result = await _repositoryFor(
        invoker,
        timeout: const Duration(milliseconds: 5),
      ).read();

      expect(result, isA<LifecycleAccessUnavailable>());
    });

    test('the default bound matches the portal-context convention', () {
      expect(lifecycleAccessTimeout, const Duration(seconds: 20));
    });
  });

  group('the unavailable result is payload-free', () {
    test('it is a const with no fields to carry an error', () async {
      final _Invoker invoker = _Invoker(
        error: const PostgrestException(
          message: 'relation "profiles" does not exist',
          code: '42P01',
        ),
      );

      final LifecycleAccessResult result = await _repositoryFor(invoker).read();

      // Identical to the const instance: nothing from the backend survived.
      expect(result, same(const LifecycleAccessUnavailable()));
    });
  });
}

Future<Object?> _nullaryProbe() async => null;
