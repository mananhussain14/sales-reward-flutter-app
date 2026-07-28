import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sale_reward/features/staff/data/datasources/retailer_staff_shop_assignment_rpc_data_source.dart';
import 'package:sale_reward/features/staff/data/repositories/supabase_retailer_staff_shop_assignment_repository.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_shop_assignment.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_staff_shop_assignment_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// The shop-assignment write: what leaves, what comes back, and how a fault is
/// classified.
///
/// Three properties carry the weight here:
///
/// 1. **The request is exactly two arguments**, and every call is recorded so a
///    widened payload fails a test rather than shipping.
/// 2. **Every fault is classified by SQLSTATE or by exception type**, never by
///    message text — and the four contract codes map to four distinct problems
///    rather than collapsing into one.
/// 3. **Nothing retries**, and an unresolved outcome is never reported as a
///    definite failure.
void main() {
  const String membershipId = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
  const String marinaId = '11111111-1111-4111-8111-111111111111';
  const String downtownId = '22222222-2222-4222-8222-222222222222';

  RetailerStaffShopAssignmentRequest requestFor({
    String membership = membershipId,
    List<String> shopIds = const <String>[marinaId],
  }) {
    final RetailerStaffShopAssignmentInput input =
        RetailerStaffShopAssignmentRequest.validated(
          membershipId: membership,
          shopIds: shopIds,
        );
    return (input as RetailerStaffShopAssignmentValid).request;
  }

  /// Records every call, so the payload can be asserted exactly.
  ({
    List<({String membershipId, List<String> shopIds})> calls,
    RetailerStaffShopAssignmentInvoker invoker,
  })
  recorder(Future<Object?> Function() answer) {
    final List<({String membershipId, List<String> shopIds})> calls =
        <({String membershipId, List<String> shopIds})>[];
    return (
      calls: calls,
      invoker: ({required String membershipId, required List<String> shopIds}) {
        calls.add((membershipId: membershipId, shopIds: shopIds));
        return answer();
      },
    );
  }

  SupabaseRetailerStaffShopAssignmentRepository repositoryWith(
    RetailerStaffShopAssignmentInvoker invoker, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    return SupabaseRetailerStaffShopAssignmentRepository(
      rpc: RetailerStaffShopAssignmentRpcDataSource(setAssignments: invoker),
      timeout: timeout,
    );
  }

  List<Object?> okBody({int added = 1, int removed = 1, int unchanged = 1}) =>
      <Object?>[
        <String, Object?>{
          'shops_added': added,
          'shops_removed': removed,
          'shops_unchanged': unchanged,
        },
      ];

  // -------------------------------------------------------------------------
  group('the request', () {
    test('names the deployed RPC and its two parameters, and no third', () {
      // The constants are the whole payload vocabulary of this feature. A third
      // argument would have to be added here to exist at all.
      expect(
        setRetailerStaffShopAssignmentsRpc,
        'set_retailer_staff_shop_assignments',
      );
      expect(staffShopAssignmentMembershipParameter, 'p_membership_id');
      expect(staffShopAssignmentShopIdsParameter, 'p_shop_ids');
    });

    test('carries the membership id and the shop ids, and nothing else', () {
      final ({
        List<({String membershipId, List<String> shopIds})> calls,
        RetailerStaffShopAssignmentInvoker invoker,
      })
      rec = recorder(() async => okBody());

      repositoryWith(rec.invoker).setShopAssignments(
        requestFor(shopIds: const <String>[marinaId, downtownId]),
      );

      expect(rec.calls, hasLength(1));
      expect(rec.calls.single.membershipId, membershipId);
      // Sorted and de-duplicated by the request itself.
      expect(rec.calls.single.shopIds, <String>[marinaId, downtownId]..sort());
    });

    test('canonicalizes case and duplicates before anything is sent', () {
      final ({
        List<({String membershipId, List<String> shopIds})> calls,
        RetailerStaffShopAssignmentInvoker invoker,
      })
      rec = recorder(() async => okBody());

      repositoryWith(rec.invoker).setShopAssignments(
        requestFor(
          membership: membershipId.toUpperCase(),
          shopIds: <String>[
            marinaId.toUpperCase(),
            marinaId,
            '  $downtownId  ',
          ],
        ),
      );

      expect(rec.calls.single.membershipId, membershipId);
      expect(rec.calls.single.shopIds, <String>[marinaId, downtownId]..sort());
    });

    test('the invoker is called exactly once per save', () async {
      final ({
        List<({String membershipId, List<String> shopIds})> calls,
        RetailerStaffShopAssignmentInvoker invoker,
      })
      rec = recorder(() async => okBody());

      await repositoryWith(rec.invoker).setShopAssignments(requestFor());

      expect(rec.calls, hasLength(1));
    });

    test('a failure is not retried', () async {
      final ({
        List<({String membershipId, List<String> shopIds})> calls,
        RetailerStaffShopAssignmentInvoker invoker,
      })
      rec = recorder(
        () async =>
            throw const sb.PostgrestException(message: 'x', code: '55000'),
      );

      await repositoryWith(rec.invoker).setShopAssignments(requestFor());

      expect(rec.calls, hasLength(1));
    });
  });

  // -------------------------------------------------------------------------
  group('validation happens before anything leaves', () {
    test('an empty shop set is refused locally', () {
      final RetailerStaffShopAssignmentInput input =
          RetailerStaffShopAssignmentRequest.validated(
            membershipId: membershipId,
            shopIds: const <String>[],
          );

      expect(input, isA<RetailerStaffShopAssignmentInvalid>());
      expect(
        (input as RetailerStaffShopAssignmentInvalid)
            .problems[RetailerStaffShopAssignmentField.shops],
        RetailerStaffShopAssignmentInputProblem.noShopsSelected,
      );
    });

    test('a missing membership id is refused locally', () {
      for (final String? bad in <String?>[null, '', '   ']) {
        final RetailerStaffShopAssignmentInput input =
            RetailerStaffShopAssignmentRequest.validated(
              membershipId: bad,
              shopIds: const <String>[marinaId],
            );
        expect(
          (input as RetailerStaffShopAssignmentInvalid)
              .problems[RetailerStaffShopAssignmentField.target],
          RetailerStaffShopAssignmentInputProblem.missingTarget,
          reason: '$bad',
        );
      }
    });

    test('a non-uuid membership id or shop id is refused locally', () {
      // Both become `uuid`-typed arguments. Forwarding a malformed one would
      // turn a readable local refusal into a `22P02` cast error raised before
      // the function body ran.
      expect(
        (RetailerStaffShopAssignmentRequest.validated(
                  membershipId: 'not-a-uuid',
                  shopIds: const <String>[marinaId],
                )
                as RetailerStaffShopAssignmentInvalid)
            .problems[RetailerStaffShopAssignmentField.target],
        RetailerStaffShopAssignmentInputProblem.malformed,
      );
      expect(
        (RetailerStaffShopAssignmentRequest.validated(
                  membershipId: membershipId,
                  shopIds: const <String>['shop-1'],
                )
                as RetailerStaffShopAssignmentInvalid)
            .problems[RetailerStaffShopAssignmentField.shops],
        RetailerStaffShopAssignmentInputProblem.malformed,
      );
    });

    test('the request type has no field for anything else', () {
      final RetailerStaffShopAssignmentRequest request = requestFor();
      expect(request.props, <Object?>[request.membershipId, request.shopIds]);
    });
  });

  // -------------------------------------------------------------------------
  group('a committed answer', () {
    test('is parsed into the three counts', () async {
      final RetailerStaffShopAssignmentResult result = await repositoryWith(
        ({required String membershipId, required List<String> shopIds}) async =>
            okBody(added: 2, removed: 1, unchanged: 3),
      ).setShopAssignments(requestFor());

      final RetailerStaffShopAssignmentChange change =
          (result as RetailerStaffShopAssignmentApplied).change;
      expect(change.shopsAdded, 2);
      expect(change.shopsRemoved, 1);
      expect(change.shopsUnchanged, 3);
    });

    test('an all-unchanged answer is still a success', () async {
      final RetailerStaffShopAssignmentResult result = await repositoryWith(
        ({required String membershipId, required List<String> shopIds}) async =>
            okBody(added: 0, removed: 0, unchanged: 2),
      ).setShopAssignments(requestFor());

      expect(result, isA<RetailerStaffShopAssignmentApplied>());
      expect(
        (result as RetailerStaffShopAssignmentApplied).change.hasChanges,
        isFalse,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('SQLSTATE classification', () {
    Future<RetailerStaffShopAssignmentProblem> problemFor(Object error) async {
      final RetailerStaffShopAssignmentResult result = await repositoryWith(
        ({required String membershipId, required List<String> shopIds}) async =>
            throw error,
      ).setShopAssignments(requestFor());
      return (result as RetailerStaffShopAssignmentRefused).problem;
    }

    test('the four contract codes map to four distinct problems', () async {
      // Distinct on purpose. Collapsing them would send a person to fix a
      // selection when their session had ended, or to check a connection that
      // was working.
      expect(
        await problemFor(
          const sb.PostgrestException(message: 'not authorized', code: '42501'),
        ),
        RetailerStaffShopAssignmentProblem.denied,
      );
      expect(
        await problemFor(
          const sb.PostgrestException(message: 'check failed', code: '23514'),
        ),
        RetailerStaffShopAssignmentProblem.invalidSelection,
      );
      expect(
        await problemFor(
          const sb.PostgrestException(message: 'inactive', code: '55000'),
        ),
        RetailerStaffShopAssignmentProblem.retailerUnavailable,
      );
      expect(
        await problemFor(
          const sb.PostgrestException(message: 'bad uuid', code: '22P02'),
        ),
        RetailerStaffShopAssignmentProblem.malformedRequest,
      );
    });

    test('42501 is one answer for refusal, absence and cross-tenant', () async {
      // The backend raises it with byte-identical messages for all three so the
      // operation is not an existence oracle. Three different messages, one
      // problem — and nothing downstream is given anything to tell them apart
      // with.
      final Set<RetailerStaffShopAssignmentProblem> problems =
          <RetailerStaffShopAssignmentProblem>{
            for (final String message in <String>[
              'Not authorized to assign shops',
              'Staff member not found',
              'Staff member belongs to another retailer',
            ])
              await problemFor(
                sb.PostgrestException(message: message, code: '42501'),
              ),
          };

      expect(problems, <RetailerStaffShopAssignmentProblem>{
        RetailerStaffShopAssignmentProblem.denied,
      });
    });

    test('an unrecognised SQLSTATE is unexpected, never a guess', () async {
      // Guessing which rule was broken would put a wrong instruction on screen.
      for (final String code in <String>['23505', '40001', 'P0001', '']) {
        expect(
          await problemFor(sb.PostgrestException(message: 'x', code: code)),
          RetailerStaffShopAssignmentProblem.unexpected,
          reason: code,
        );
      }
    });

    test('a missing SQLSTATE is unexpected', () async {
      expect(
        await problemFor(const sb.PostgrestException(message: 'x')),
        RetailerStaffShopAssignmentProblem.unexpected,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('transport and session classification', () {
    Future<RetailerStaffShopAssignmentProblem> problemFor(
      Future<Object?> Function() answer, {
      Duration timeout = const Duration(seconds: 30),
    }) async {
      final RetailerStaffShopAssignmentResult result = await repositoryWith(
        ({required String membershipId, required List<String> shopIds}) =>
            answer(),
        timeout: timeout,
      ).setShopAssignments(requestFor());
      return (result as RetailerStaffShopAssignmentRefused).problem;
    }

    test('a transport fault is a network problem', () async {
      expect(
        await problemFor(() async => throw http.ClientException('no route')),
        RetailerStaffShopAssignmentProblem.network,
      );
    });

    test('a slow call times out rather than hanging', () async {
      expect(
        await problemFor(
          () => Completer<Object?>().future,
          timeout: const Duration(milliseconds: 20),
        ),
        RetailerStaffShopAssignmentProblem.timeout,
      );
    });

    test('an auth fault is signedOut, not a network problem', () async {
      expect(
        await problemFor(
          () async => throw const sb.AuthException('session missing'),
        ),
        RetailerStaffShopAssignmentProblem.signedOut,
      );
    });

    test('an unreadable body is malformedResponse, never a failed write', () {
      // The statement may well have committed; what failed is this build's
      // ability to read the answer.
      for (final Object? body in <Object?>[
        null,
        const <Object?>[],
        <Object?>[
          <String, Object?>{'shops_added': 1},
        ],
        <Object?>[
          <String, Object?>{
            'shops_added': -1,
            'shops_removed': 0,
            'shops_unchanged': 0,
          },
        ],
      ]) {
        expect(
          problemFor(() async => body),
          completion(RetailerStaffShopAssignmentProblem.malformedResponse),
          reason: '$body',
        );
      }
    });

    test(
      'an unknown throw fails closed, and never borrows the connection copy',
      () async {
        expect(
          await problemFor(() async => throw StateError('programming error')),
          RetailerStaffShopAssignmentProblem.unexpected,
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  group('definite versus unresolved', () {
    test('the three unknown-outcome problems are the only indefinite ones', () {
      // A timeout, an unreadable reply and an unexpected fault after the request
      // left all mean the change may already have been committed, so the copy
      // points at the roster rather than re-arming a button.
      final Set<RetailerStaffShopAssignmentProblem> indefinite =
          RetailerStaffShopAssignmentProblem.values
              .where((RetailerStaffShopAssignmentProblem p) => !p.isDefinite)
              .toSet();

      expect(indefinite, <RetailerStaffShopAssignmentProblem>{
        RetailerStaffShopAssignmentProblem.timeout,
        RetailerStaffShopAssignmentProblem.malformedResponse,
        RetailerStaffShopAssignmentProblem.unexpected,
      });
    });

    test('a request that never left is definite', () {
      // Nothing was written, so a deliberate retry is safe and the copy may say
      // so plainly.
      expect(RetailerStaffShopAssignmentProblem.network.isDefinite, isTrue);
      expect(RetailerStaffShopAssignmentProblem.signedOut.isDefinite, isTrue);
    });
  });
}
