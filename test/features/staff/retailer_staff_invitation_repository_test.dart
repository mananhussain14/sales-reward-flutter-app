import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sale_reward/core/errors/retailer_read_problem.dart';
import 'package:sale_reward/features/staff/data/datasources/retailer_staff_invitation_rpc_data_source.dart';
import 'package:sale_reward/features/staff/data/repositories/supabase_retailer_staff_invitation_repository.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_assignable_shop.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_invitation_outcome.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_invitation_request.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_invitation_role.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_staff_invitation_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../support/retailer_invite_staff_fakes.dart';

/// The repository: classify the fault, map the answer, and never retry.
void main() {
  RetailerStaffInvitationRequest requestFor({
    RetailerStaffInvitationRole role = RetailerStaffInvitationRole.salesStaff,
    List<String> shopIds = const <String>[northwindMarinaId],
  }) {
    final RetailerStaffInvitationInput input =
        RetailerStaffInvitationRequest.validated(
          firstName: 'Priya',
          lastName: 'Raman',
          email: 'priya@example.com',
          role: role,
          shopIds: shopIds,
        );
    return (input as RetailerStaffInvitationValid).request;
  }

  SupabaseRetailerStaffInvitationRepository repositoryWith({
    RetailerAssignableShopsInvoker? shops,
    RetailerStaffInvitationSender? send,
    Duration readTimeout = const Duration(seconds: 20),
    Duration sendTimeout = const Duration(seconds: 45),
  }) {
    return SupabaseRetailerStaffInvitationRepository(
      rpc: RetailerStaffInvitationRpcDataSource(
        assignableShops:
            shops ?? () async => throw StateError('shops not expected'),
        send: send ?? (_) async => throw StateError('send not expected'),
      ),
      readTimeout: readTimeout,
      sendTimeout: sendTimeout,
    );
  }

  group('assignableShops()', () {
    test('parses rows into domain shops', () async {
      final RetailerAssignableShopsResult result = await repositoryWith(
        shops: () async => <Object?>[
          <String, Object?>{
            'shop_id': northwindMarinaId,
            'shop_name': 'Northwind Marina',
            'shop_code': 'NW-01',
            'city': 'Dubai',
          },
        ],
      ).assignableShops();

      expect(result, isA<RetailerAssignableShopsLoaded>());
      final List<RetailerAssignableShop> shops =
          (result as RetailerAssignableShopsLoaded).shops;
      expect(shops.single.name, 'Northwind Marina');
    });

    test('42501 is a denial, never an empty picker', () async {
      final RetailerAssignableShopsResult result = await repositoryWith(
        shops: () async =>
            throw const sb.PostgrestException(message: 'x', code: '42501'),
      ).assignableShops();

      expect(
        (result as RetailerAssignableShopsFailed).problem,
        RetailerReadProblem.denied,
      );
    });

    test('an unreadable body is malformed, not empty', () async {
      final RetailerAssignableShopsResult result = await repositoryWith(
        shops: () async => <Object?>[
          <String, Object?>{'shop_id': 'nope', 'shop_name': 'X'},
        ],
      ).assignableShops();

      expect(
        (result as RetailerAssignableShopsFailed).problem,
        RetailerReadProblem.malformed,
      );
    });

    test('a transport fault is a network problem', () async {
      final RetailerAssignableShopsResult result = await repositoryWith(
        shops: () async => throw http.ClientException('failed'),
      ).assignableShops();

      expect(
        (result as RetailerAssignableShopsFailed).problem,
        RetailerReadProblem.network,
      );
    });

    test('a read that never settles times out', () async {
      final RetailerAssignableShopsResult result = await repositoryWith(
        shops: () => Completer<Object?>().future,
        readTimeout: const Duration(milliseconds: 10),
      ).assignableShops();

      expect(
        (result as RetailerAssignableShopsFailed).problem,
        RetailerReadProblem.timeout,
      );
    });
  });

  group('send()', () {
    test('posts exactly the five contract fields', () async {
      Map<String, Object?>? captured;

      await repositoryWith(
        send: (Map<String, Object?> body) async {
          captured = body;
          return const RetailerStaffInvitationReply(
            status: 200,
            body: <String, Object?>{
              'version': 1,
              'outcome': 'SENT',
              'code': 'SENT',
            },
          );
        },
      ).send(requestFor());

      expect(captured, isNotNull);
      expect(captured!.keys, hasLength(5));
      expect(captured!['firstName'], 'Priya');
      expect(captured!['lastName'], 'Raman');
      expect(captured!['email'], 'priya@example.com');
      expect(captured!['roleCode'], 'SALES_STAFF');
      expect(captured!['shopIds'], <String>[northwindMarinaId]);
    });

    test('a Retailer Manager posts an empty shopIds array', () async {
      Map<String, Object?>? captured;

      await repositoryWith(
        send: (Map<String, Object?> body) async {
          captured = body;
          return const RetailerStaffInvitationReply(
            status: 200,
            body: <String, Object?>{
              'version': 1,
              'outcome': 'SENT',
              'code': 'SENT',
            },
          );
        },
      ).send(
        requestFor(
          role: RetailerStaffInvitationRole.retailerManager,
          shopIds: const <String>[],
        ),
      );

      expect(captured!['shopIds'], isEmpty);
      expect(captured!['roleCode'], 'RETAILER_MANAGER');
    });

    test('the request is made exactly once, and never retried', () async {
      int calls = 0;

      await repositoryWith(
        send: (_) async {
          calls++;
          // A 502 delivery failure: retryable in principle, and still not
          // retried here. Whether to try again is a person's decision.
          return const RetailerStaffInvitationReply(
            status: 502,
            body: <String, Object?>{
              'version': 1,
              'outcome': 'DELIVERY_FAILED',
              'code': 'DELIVERY_FAILED',
            },
          );
        },
      ).send(requestFor());

      expect(calls, 1);
    });

    test('a 202 is not retried either', () async {
      int calls = 0;

      final RetailerStaffInvitationSendResult result = await repositoryWith(
        send: (_) async {
          calls++;
          return const RetailerStaffInvitationReply(
            status: 202,
            body: <String, Object?>{
              'version': 1,
              'outcome': 'DELIVERY_ACCEPTED_STATUS_UNCONFIRMED',
              'code': 'DELIVERY_ACCEPTED_STATUS_UNCONFIRMED',
            },
          );
        },
      ).send(requestFor());

      expect(calls, 1);
      expect(
        (result as RetailerStaffInvitationAnswered).outcome,
        RetailerStaffInvitationOutcome.deliveryAcceptedStatusUnconfirmed,
      );
    });

    test('a transport fault means nothing was sent', () async {
      final RetailerStaffInvitationSendResult result = await repositoryWith(
        send: (_) async => throw http.ClientException('failed'),
      ).send(requestFor());

      expect(
        (result as RetailerStaffInvitationUnanswered).problem,
        RetailerStaffInvitationTransportProblem.network,
      );
    });

    test('an auth fault means there is no usable session', () async {
      final RetailerStaffInvitationSendResult result = await repositoryWith(
        send: (_) async => throw const sb.AuthException('no session'),
      ).send(requestFor());

      expect(
        (result as RetailerStaffInvitationUnanswered).problem,
        RetailerStaffInvitationTransportProblem.signedOut,
      );
    });

    test('an unexpected throw does not borrow the connection copy', () async {
      final RetailerStaffInvitationSendResult result = await repositoryWith(
        send: (_) async => throw StateError('a programming error'),
      ).send(requestFor());

      expect(
        (result as RetailerStaffInvitationUnanswered).problem,
        RetailerStaffInvitationTransportProblem.unexpected,
      );
    });

    test('a request that never settles is a timeout, not a failure', () async {
      // The function may have delivered while this client stopped waiting, so
      // the honest answer is "unknown" and the history is the authority.
      final RetailerStaffInvitationSendResult result = await repositoryWith(
        send: (_) => Completer<RetailerStaffInvitationReply>().future,
        sendTimeout: const Duration(milliseconds: 10),
      ).send(requestFor());

      expect(
        (result as RetailerStaffInvitationUnanswered).problem,
        RetailerStaffInvitationTransportProblem.timeout,
      );
    });
  });

  group('the boundary names one function and one RPC', () {
    test('the Edge Function name is exact', () {
      expect(
        sendRetailerStaffInvitationFunction,
        'send-retailer-staff-invitation',
      );
    });

    test('the assignable-shops RPC name is exact', () {
      expect(
        retailerStaffAssignableShopsRpc,
        'list_retailer_staff_assignable_shops',
      );
    });
  });
}
