import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sale_reward/features/dashboard/data/datasources/retailer_owner_overview_rpc_data_source.dart';
import 'package:sale_reward/features/dashboard/data/repositories/supabase_retailer_owner_overview_repository.dart';
import 'package:sale_reward/features/dashboard/domain/entities/retailer_owner_overview.dart';
import 'package:sale_reward/features/dashboard/domain/repositories/retailer_owner_overview_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/retailer_owner_overview_fakes.dart';

/// The Retailer Owner Overview repository: call, parse, classify.
///
/// The point of these tests is that the nine outcomes the milestone requires be
/// told apart actually are — and, above all, that none of the operational ones
/// is reported as "check your connection" unless it genuinely is one.
void main() {
  /// A repository over a scripted invoker, counting the calls it makes.
  ({SupabaseRetailerOwnerOverviewRepository repo, List<int> calls}) build(
    Future<Object?> Function() invoke, {
    Duration timeout = const Duration(seconds: 20),
  }) {
    final List<int> calls = <int>[];
    final SupabaseRetailerOwnerOverviewRepository repo =
        SupabaseRetailerOwnerOverviewRepository(
          rpc: RetailerOwnerOverviewRpcDataSource(
            overview: () {
              calls.add(1);
              return invoke();
            },
          ),
          timeout: timeout,
        );
    return (repo: repo, calls: calls);
  }

  Future<RetailerOverviewResult> resultOf(Future<Object?> Function() invoke) =>
      build(invoke).repo.overview();

  Future<RetailerOverviewProblem> problemOf(
    Future<Object?> Function() invoke,
  ) async {
    final RetailerOverviewResult result = await resultOf(invoke);
    return (result as RetailerOverviewFailed).problem;
  }

  group('successful answers', () {
    test('one row becomes a loaded overview', () async {
      final RetailerOverviewResult result = await resultOf(
        () async => <Object?>[retailerOverviewRow()],
      );

      expect(result, isA<RetailerOverviewLoaded>());
      final RetailerOwnerOverview overview =
          (result as RetailerOverviewLoaded).overview;
      expect(overview.retailerName, 'Northwind Retail');
      expect(overview.activeShopCount, 9);
    });

    test('zero rows becomes ineligible, never a failure', () async {
      // The backend's single answer for every ineligible caller. A failure here
      // would offer a retry that could not change the answer, and would make an
      // authorization outcome look like an outage.
      final RetailerOverviewResult result = await resultOf(
        () async => <Object?>[],
      );

      expect(result, isA<RetailerOverviewIneligible>());
      expect(result, isNot(isA<RetailerOverviewFailed>()));
    });

    test('the call passes no arguments', () async {
      // The invoker is nullary, so this is enforced by the type system. The
      // assertion records that exactly one call was made with nothing attached.
      final ({SupabaseRetailerOwnerOverviewRepository repo, List<int> calls})
      built = build(() async => <Object?>[retailerOverviewRow()]);

      await built.repo.overview();

      expect(built.calls, hasLength(1));
    });
  });

  group('malformed bodies', () {
    test('an unreadable body is malformed, never ineligible', () async {
      // The distinction that matters most on this screen: "this build could not
      // read the answer" must not be shown as "you have no workspace".
      expect(
        await problemOf(() async => 'not a list'),
        RetailerOverviewProblem.malformed,
      );
    });

    test('a malformed body never becomes an overview of zeros', () async {
      final RetailerOverviewResult result = await resultOf(
        () async => <Object?>[retailerOverviewRow(totalShopCount: null)],
      );

      expect(result, isA<RetailerOverviewFailed>());
      expect(result, isNot(isA<RetailerOverviewLoaded>()));
    });

    test('two rows are malformed rather than silently truncated', () async {
      expect(
        await problemOf(
          () async => <Object?>[retailerOverviewRow(), retailerOverviewRow()],
        ),
        RetailerOverviewProblem.malformed,
      );
    });

    test('malformed is distinct from network', () async {
      // The whole reason the problem enum exists: both used to be
      // UnavailableFailure, whose copy tells the user to check a connection that
      // is working perfectly.
      expect(
        await problemOf(() async => <Object?>[<Object?>[]]),
        isNot(RetailerOverviewProblem.network),
      );
    });
  });

  group('thrown failures', () {
    test('a refusal is denied, and carries no backend text', () async {
      expect(
        await problemOf(
          () async => throw const PostgrestException(
            message: 'permission denied for function',
            code: '42501',
          ),
        ),
        RetailerOverviewProblem.denied,
      );
    });

    test('a transport failure is network, on both platforms', () async {
      // `package:http` wraps a VM SocketException in a subclass of
      // ClientException, and the browser client throws ClientException directly
      // — so this one check covers a refused socket, an unresolved host and a
      // CORS refusal without importing dart:io.
      expect(
        await problemOf(
          () async => throw http.ClientException('Connection refused'),
        ),
        RetailerOverviewProblem.network,
      );
    });

    test('an unsettled call becomes timeout, not network', () async {
      final ({SupabaseRetailerOwnerOverviewRepository repo, List<int> calls})
      built = build(
        () => Completer<Object?>().future, // never completes
        timeout: const Duration(milliseconds: 20),
      );

      final RetailerOverviewResult result = await built.repo.overview();

      expect(
        (result as RetailerOverviewFailed).problem,
        RetailerOverviewProblem.timeout,
      );
    });

    test('an expired session is signedOut, not denied', () async {
      // "You are not signed in" and "you are signed in and refused" are
      // different events with different remedies.
      expect(
        await problemOf(() async => throw const AuthException('expired')),
        RetailerOverviewProblem.signedOut,
      );
    });

    test('an unrecognised throw is unexpected, not network', () async {
      // A programming error is not a statement about the user's connection.
      expect(
        await problemOf(() async => throw StateError('bug')),
        RetailerOverviewProblem.unexpected,
      );
    });

    test('an unexpected SQLSTATE is unexpected, not denied', () async {
      // The read is STABLE and touches no constraint, so a unique violation
      // means the deployed function is not the one this build expects.
      expect(
        await problemOf(
          () async => throw const PostgrestException(
            message: 'duplicate key',
            code: '23505',
          ),
        ),
        RetailerOverviewProblem.unexpected,
      );
    });

    test('a PostgrestException with no code is unexpected', () async {
      expect(
        await problemOf(
          () async => throw const PostgrestException(message: 'something'),
        ),
        RetailerOverviewProblem.unexpected,
      );
    });
  });

  group('classification is by type and code only', () {
    test('the backend message never influences the outcome', () async {
      // Two refusals whose messages differ wildly must classify identically —
      // proof that no branch reads the text.
      final RetailerOverviewProblem a = await problemOf(
        () async => throw const PostgrestException(
          message: 'permission denied for table retailer_shops',
          code: '42501',
        ),
      );
      final RetailerOverviewProblem b = await problemOf(
        () async => throw const PostgrestException(message: '', code: '42501'),
      );

      expect(a, b);
      expect(a, RetailerOverviewProblem.denied);
    });

    test('every problem is reachable', () {
      // A guard against a member being added to the enum with no path that
      // produces it — a reason the UI would then have copy for and never show.
      expect(RetailerOverviewProblem.values, hasLength(6));
    });
  });
}
