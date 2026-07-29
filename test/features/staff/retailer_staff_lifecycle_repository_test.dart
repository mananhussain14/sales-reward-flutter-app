import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sale_reward/core/errors/sql_state.dart';
import 'package:sale_reward/features/staff/data/datasources/retailer_staff_lifecycle_rpc_data_source.dart';
import 'package:sale_reward/features/staff/data/repositories/supabase_retailer_staff_lifecycle_repository.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_lifecycle_status.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_staff_lifecycle_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/retailer_staff_lifecycle_fakes.dart';

/// The lifecycle repository, driven over a recording invoker.
///
/// These assert what leaves the client — the function name, the exact parameter
/// names, and, just as importantly, the parameters that are **absent** — and how
/// each answer is classified. The invoker stands in for `client.rpc`, so nothing
/// here touches Supabase.
void main() {
  late List<({String rpc, Map<String, Object?> params})> calls;
  Object? thrown;
  Object? body;

  const String membershipId = '11111111-1111-4111-8111-111111111111';
  const String otherId = '22222222-2222-4222-8222-222222222222';

  setUp(() {
    calls = <({String rpc, Map<String, Object?> params})>[];
    thrown = null;
    body = staffLifecycleRows(membershipId: membershipId);
  });

  /// A repository whose invoker records the payload verbatim.
  ///
  /// The payload is rebuilt from the *deployed parameter-name constants*, not
  /// from restated literals — so a rename of one of those constants cannot pass
  /// these tests while breaking the real call.
  SupabaseRetailerStaffLifecycleRepository buildRepository() {
    return SupabaseRetailerStaffLifecycleRepository(
      rpc: RetailerStaffLifecycleRpcDataSource(
        setStatus:
            ({required String membershipId, required String status}) async {
              calls.add((
                rpc: setRetailerStaffMembershipStatusRpc,
                params: <String, Object?>{
                  staffLifecycleMembershipIdParameter: membershipId,
                  staffLifecycleStatusParameter: status,
                },
              ));
              if (thrown != null) throw thrown!;
              return body;
            },
      ),
    );
  }

  Future<RetailerStaffLifecycleResult> deactivate() =>
      buildRepository().setMembershipStatus(
        membershipId: membershipId,
        status: RetailerStaffLifecycleStatus.deactivated,
      );

  PostgrestException postgrest(String code) => PostgrestException(
    message: 'relation "organization_members" leaked',
    code: code,
  );

  group('the RPC contract', () {
    test('names exactly the deployed function', () {
      expect(
        setRetailerStaffMembershipStatusRpc,
        'set_retailer_staff_membership_status',
      );
    });

    test('sends exactly two argument keys', () async {
      await deactivate();

      expect(calls.single.params.keys.toSet(), <String>{
        'p_membership_id',
        'p_status',
      });
    });

    test('issues exactly one RPC call', () async {
      await deactivate();

      expect(calls, hasLength(1));
      expect(calls.single.rpc, 'set_retailer_staff_membership_status');
    });

    test('sends no third argument of any kind', () async {
      await deactivate();

      for (final String forbidden in <String>[
        'p_organization_id',
        'p_retailer_id',
        'p_user_id',
        'p_profile_id',
        'p_actor',
        'p_role',
        'p_role_code',
        'p_permission',
        'p_current_status',
        'p_audit_action',
        'p_timestamp',
        'p_shop_ids',
        'target_organization_id',
      ]) {
        expect(
          calls.single.params.containsKey(forbidden),
          isFalse,
          reason: 'the lifecycle write must send no $forbidden',
        );
      }
    });

    test('a DEACTIVATED request is sent as the token DEACTIVATED', () async {
      await deactivate();
      expect(calls.single.params['p_status'], 'DEACTIVATED');
    });

    test('an ACTIVE request is sent as the token ACTIVE', () async {
      await buildRepository().setMembershipStatus(
        membershipId: membershipId,
        status: RetailerStaffLifecycleStatus.active,
      );
      expect(calls.single.params['p_status'], 'ACTIVE');
    });

    test(
      'INACTIVE and SUSPENDED are never sent, in either direction',
      () async {
        for (final RetailerStaffLifecycleStatus status
            in RetailerStaffLifecycleStatus.values) {
          calls.clear();
          await buildRepository().setMembershipStatus(
            membershipId: membershipId,
            status: status,
          );
          expect(calls.single.params['p_status'], isNot('INACTIVE'));
          expect(calls.single.params['p_status'], isNot('SUSPENDED'));
          expect(calls.single.params['p_status'], isNot('INVITED'));
          expect(<String>[
            'ACTIVE',
            'DEACTIVATED',
          ], contains(calls.single.params['p_status']));
        }
      },
    );

    test('the submitted membership id is sent verbatim', () async {
      await deactivate();
      expect(calls.single.params['p_membership_id'], membershipId);
    });

    test('nothing is retried after any failure', () async {
      for (final String code in <String>['42501', '23514', '55000', '22P02']) {
        calls.clear();
        thrown = postgrest(code);
        await deactivate();
        expect(
          calls,
          hasLength(1),
          reason: 'SQLSTATE $code must not produce a second call',
        );
      }

      for (final Object error in <Object>[
        StateError('transport'),
        http.ClientException('refused'),
        TimeoutException('slow'),
      ]) {
        calls.clear();
        thrown = error;
        await deactivate();
        expect(calls, hasLength(1), reason: '$error must not be retried');
      }
    });

    test('nothing is retried after an unconfirmed success either', () async {
      body = <Map<String, Object?>>[];

      final RetailerStaffLifecycleResult result = await deactivate();

      expect(result, isA<RetailerStaffLifecycleUnconfirmed>());
      expect(calls, hasLength(1));
    });
  });

  group('SQLSTATE mapping', () {
    Future<RetailerStaffLifecycleProblem> problemFor(Object error) async {
      thrown = error;
      final RetailerStaffLifecycleResult result = await deactivate();
      return (result as RetailerStaffLifecycleRefused).problem;
    }

    test('42501 maps to denied', () async {
      expect(SqlState.insufficientPrivilege, '42501');
      expect(
        await problemFor(postgrest(SqlState.insufficientPrivilege)),
        RetailerStaffLifecycleProblem.denied,
      );
    });

    test('23514 maps to invalidStatus', () async {
      expect(
        await problemFor(postgrest(SqlState.checkViolation)),
        RetailerStaffLifecycleProblem.invalidStatus,
      );
    });

    test('55000 maps to retailerUnavailable', () async {
      expect(
        await problemFor(postgrest(SqlState.objectNotInPrerequisiteState)),
        RetailerStaffLifecycleProblem.retailerUnavailable,
      );
    });

    test('22P02 maps to malformedRequest', () async {
      expect(
        await problemFor(postgrest(SqlState.invalidTextRepresentation)),
        RetailerStaffLifecycleProblem.malformedRequest,
      );
    });

    test('an unexpected SQLSTATE maps to unexpected', () async {
      expect(
        await problemFor(postgrest('23505')),
        RetailerStaffLifecycleProblem.unexpected,
      );
      expect(
        await problemFor(postgrest('XX000')),
        RetailerStaffLifecycleProblem.unexpected,
      );
    });

    test('an AuthException maps to signedOut', () async {
      expect(
        await problemFor(const AuthException('token expired')),
        RetailerStaffLifecycleProblem.signedOut,
      );
    });

    test('transport and timeout are classified apart', () async {
      expect(
        await problemFor(http.ClientException('refused')),
        RetailerStaffLifecycleProblem.network,
      );
      expect(
        await problemFor(TimeoutException('slow')),
        RetailerStaffLifecycleProblem.timeout,
      );
      expect(
        await problemFor(StateError('bug')),
        RetailerStaffLifecycleProblem.unexpected,
      );
    });

    test('the raw backend message is never exposed', () async {
      thrown = postgrest('42501');
      final RetailerStaffLifecycleResult result = await deactivate();
      final RetailerStaffLifecycleProblem problem =
          (result as RetailerStaffLifecycleRefused).problem;

      // The problem is an enum: it has no field a message, table name or
      // SQLSTATE could occupy.
      expect(problem.toString(), isNot(contains('organization_members')));
      expect(problem.toString(), isNot(contains('42501')));
    });
  });

  group('response classification', () {
    test('a described success carries the confirmed status and flag', () async {
      final RetailerStaffLifecycleResult result = await deactivate();

      final RetailerStaffLifecycleApplied applied =
          result as RetailerStaffLifecycleApplied;
      expect(applied.confirmedStatus, RetailerStaffLifecycleStatus.deactivated);
      expect(applied.statusChanged, isTrue);
    });

    test("the confirmed status is the response's, not the request's", () async {
      body = staffLifecycleRows(
        membershipId: membershipId,
        membershipStatus: 'ACTIVE',
      );

      final RetailerStaffLifecycleResult result = await deactivate();

      expect(
        (result as RetailerStaffLifecycleApplied).confirmedStatus,
        RetailerStaffLifecycleStatus.active,
      );
    });

    test('an idempotent no-op is a success, not a refusal', () async {
      body = staffLifecycleRows(
        membershipId: membershipId,
        statusChanged: false,
      );

      final RetailerStaffLifecycleResult result = await deactivate();

      expect((result as RetailerStaffLifecycleApplied).statusChanged, isFalse);
    });

    test(
      'every malformed successful response is Unconfirmed, not Refused',
      () async {
        for (final Object? malformed in <Object?>[
          null,
          <Map<String, Object?>>[],
          <Map<String, Object?>>[
            staffLifecycleRow(membershipId: membershipId),
            staffLifecycleRow(membershipId: membershipId),
          ],
          staffLifecycleRows(membershipId: otherId),
          staffLifecycleRows(membershipId: 'not-a-uuid'),
          staffLifecycleRows(
            membershipId: membershipId,
            membershipStatus: 'INACTIVE',
          ),
          staffLifecycleRows(
            membershipId: membershipId,
            membershipStatus: 'SUSPENDED',
          ),
          staffLifecycleRows(membershipId: membershipId, statusChanged: 'yes'),
          'a string',
          42,
        ]) {
          body = malformed;
          final RetailerStaffLifecycleResult result = await deactivate();

          expect(
            result,
            isA<RetailerStaffLifecycleUnconfirmed>(),
            reason: 'body $malformed must be unconfirmed, never a refusal',
          );
          expect(result, isNot(isA<RetailerStaffLifecycleRefused>()));
          expect(result, isNot(isA<RetailerStaffLifecycleApplied>()));
        }
      },
    );
  });

  group('no direct table access exists on this path', () {
    test('a write issues the lifecycle RPC and nothing else', () async {
      await deactivate();

      expect(
        calls.map((({String rpc, Map<String, Object?> params}) c) => c.rpc),
        <String>['set_retailer_staff_membership_status'],
      );
    });
  });
}
