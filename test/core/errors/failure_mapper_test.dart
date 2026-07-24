import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/errors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The shared error contract.
///
/// These tests pin the three rules § 8.3 of the architecture recommendation
/// requires the mobile client to inherit from the web layer: no raw message
/// escapes, a transport failure is never a denial, and everything unrecognized
/// fails closed.
void main() {
  PostgrestException postgrest(String code) => PostgrestException(
    message: 'relation "vendor_retailers" does not exist',
    code: code,
  );

  group('mapSupabaseError', () {
    test('maps each documented SQLSTATE to its discriminant', () {
      expect(
        mapSupabaseError(postgrest(SqlState.insufficientPrivilege)),
        isA<DeniedFailure>(),
      );
      expect(
        mapSupabaseError(postgrest(SqlState.uniqueViolation)),
        isA<DuplicateFailure>(),
      );
      expect(
        mapSupabaseError(postgrest(SqlState.checkViolation)),
        isA<InvalidFailure>(),
      );
      expect(
        mapSupabaseError(postgrest(SqlState.objectNotInPrerequisiteState)),
        isA<NotReadyFailure>(),
      );
    });

    test('an unrecognized SQLSTATE is unavailable, not a denial', () {
      expect(mapSupabaseError(postgrest('XX000')), isA<UnavailableFailure>());
      expect(mapSupabaseError(postgrest('')), isA<UnavailableFailure>());
    });

    test('a transport failure is unavailable, never a denial', () {
      expect(
        mapSupabaseError(Exception('connection reset')),
        isA<UnavailableFailure>(),
      );
      expect(
        mapSupabaseError(const SocketExceptionStub()),
        isA<UnavailableFailure>(),
      );
    });

    test('an auth failure is unauthenticated, not denied', () {
      expect(
        mapSupabaseError(const AuthException('invalid claim')),
        isA<UnauthenticatedFailure>(),
      );
    });

    test('never carries the backend message forward', () {
      // The stringified failure must not contain the Postgres text, which can
      // name tables, columns, functions and policies.
      for (final String code in <String>[
        SqlState.insufficientPrivilege,
        SqlState.uniqueViolation,
        SqlState.checkViolation,
        SqlState.objectNotInPrerequisiteState,
        'XX000',
      ]) {
        final Failure failure = mapSupabaseError(postgrest(code));
        expect(failure.toString(), isNot(contains('vendor_retailers')));
        expect(failure.props.join(), isNot(contains('vendor_retailers')));
      }
    });

    test('a denial carries no detail at all', () {
      // 42501 is deliberately overloaded in SQL so it is not an existence
      // oracle. Attaching a field or a reason here would undo that.
      final Failure failure = mapSupabaseError(
        postgrest(SqlState.insufficientPrivilege),
      );

      expect(failure, const DeniedFailure());
      expect(failure.props, isEmpty);
    });
  });

  group('SqlState', () {
    test('records the four codes the backend actually raises', () {
      expect(SqlState.insufficientPrivilege, '42501');
      expect(SqlState.uniqueViolation, '23505');
      expect(SqlState.checkViolation, '23514');
      expect(SqlState.objectNotInPrerequisiteState, '55000');
    });
  });

  group('NotImplementedFailure', () {
    test('names the missing capability without implying a denial', () {
      const Failure failure = NotImplementedFailure(capability: 'some_rpc()');

      expect(failure, isNot(isA<DeniedFailure>()));
      expect(failure, isNot(isA<UnavailableFailure>()));
      expect((failure as NotImplementedFailure).capability, 'some_rpc()');
    });
  });
}

/// Stands in for a `dart:io` socket error without importing `dart:io`, which is
/// unavailable on the web target this package also builds for.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
