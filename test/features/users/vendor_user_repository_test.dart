import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/users/data/datasources/vendor_user_rpc_data_source.dart';
import 'package:sale_reward/features/users/data/repositories/supabase_vendor_user_repository.dart';
import 'package:sale_reward/features/users/domain/entities/vendor_user_detail.dart';
import 'package:sale_reward/features/users/domain/entities/vendor_user_summary.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/vendor_user_fakes.dart';

/// The data layer's contract with the backend.
///
/// Three properties are asserted over and over, because each is a security
/// boundary rather than a convenience:
///
/// 1. **`list_vendor_users()` is called with no arguments at all**, so nothing
///    in the client can nominate whose directory comes back.
/// 2. **The detail read sends one membership id and nothing beside it** — no
///    auth user id, no profile id, no organization, no role, no permission, no
///    email.
/// 3. **A thrown call is classified by SQLSTATE, and an unreadable body is an
///    outage** — never a denial, and never a fabricated empty list.
void main() {
  late int userCalls;
  late List<List<Object?>> userCallArguments;
  late List<Map<String, Object?>> detailParams;

  Object? userBody = userRows();
  Object? detailBody = <Map<String, Object?>>[userDetailRow()];
  Object? thrown;

  setUp(() {
    userCalls = 0;
    userCallArguments = <List<Object?>>[];
    detailParams = <Map<String, Object?>>[];
    userBody = userRows();
    detailBody = <Map<String, Object?>>[userDetailRow()];
    thrown = null;
  });

  SupabaseVendorUserRepository buildRepository() {
    return SupabaseVendorUserRepository(
      rpc: VendorUserRpcDataSource(
        users: () async {
          userCalls++;
          // The invoker takes no parameters, so there is literally nothing to
          // record beyond the fact that it was called with none.
          userCallArguments.add(const <Object?>[]);
          if (thrown != null) throw thrown!;
          return userBody;
        },
        detail: (String membershipId) async {
          detailParams.add(<String, Object?>{
            membershipIdParameter: membershipId,
          });
          if (thrown != null) throw thrown!;
          return detailBody;
        },
      ),
    );
  }

  PostgrestException postgrest(String code) => PostgrestException(
    message: 'backend detail that must not escape',
    code: code,
  );

  group('the RPC contract', () {
    test('list_vendor_users is invoked with zero arguments', () async {
      await buildRepository().users();

      expect(userCalls, 1);
      expect(userCallArguments.single, isEmpty);
    });

    test('get_vendor_user_detail sends only p_membership_id', () async {
      await buildRepository().userDetail(aminaMembershipUuid);

      expect(detailParams, hasLength(1));
      expect(detailParams.single.keys, <String>[membershipIdParameter]);
      expect(detailParams.single[membershipIdParameter], aminaMembershipUuid);
    });

    test('the parameter literal is the deployed one', () {
      expect(membershipIdParameter, 'p_membership_id');
    });

    test('the two RPC names are the deployed ones, spelled once each', () {
      expect(listVendorUsersRpc, 'list_vendor_users');
      expect(getVendorUserDetailRpc, 'get_vendor_user_detail');
    });

    test('the list invoker type admits no argument', () {
      // The typedef is the security property. This assignment only compiles
      // while the invoker stays nullary.
      const VendorUserListInvoker nullary = _neverCalled;
      expect(nullary, isA<Future<Object?> Function()>());
    });

    test('nothing but a membership id is ever addressable', () async {
      // The selector is the membership id, not the profile id or the auth user
      // id. There is no second parameter to carry either.
      await buildRepository().userDetail(joMembershipUuid);

      expect(detailParams.single, hasLength(1));
      expect(detailParams.single[membershipIdParameter], joMembershipUuid);
    });
  });

  group('successful reads', () {
    test('the list maps into entities in the backend order', () async {
      final ReadResult<List<VendorUserSummary>> result = await buildRepository()
          .users();

      expect(result, isA<ReadSuccess<List<VendorUserSummary>>>());
      final List<VendorUserSummary> value =
          (result as ReadSuccess<List<VendorUserSummary>>).value;
      expect(value.map((VendorUserSummary u) => u.displayName), <String>[
        'Amina Rahman',
        'Jo Nakamura',
      ]);
      expect(value.first.roleNames, <String>[
        'Finance Admin',
        'Vendor Super Admin',
      ]);
      expect(value.last.roleNames, isEmpty);
      expect(value.last.joinedAt, isNull);
    });

    test('an empty list is a success, not a failure', () async {
      userBody = const <Object?>[];

      final ReadResult<List<VendorUserSummary>> result = await buildRepository()
          .users();

      expect((result as ReadSuccess<List<VendorUserSummary>>).value, isEmpty);
    });

    test('a single-user directory is a success', () async {
      userBody = <Map<String, Object?>>[userRow()];

      final ReadResult<List<VendorUserSummary>> result = await buildRepository()
          .users();

      expect(
        (result as ReadSuccess<List<VendorUserSummary>>).value,
        hasLength(1),
      );
    });

    test('the detail maps into one entity', () async {
      final ReadResult<VendorUserDetail?> result = await buildRepository()
          .userDetail(aminaMembershipUuid);

      final VendorUserDetail? value =
          (result as ReadSuccess<VendorUserDetail?>).value;
      expect(value!.displayName, 'Amina Rahman');
      expect(value.deactivatedAt, isNull);
      expect(value.roleNames, hasLength(2));
    });

    test('zero detail rows is a success carrying null', () async {
      // Not a failure: the backend answered, and its answer is "no row you may
      // read". Mapping it to a failure would let the UI word it as an outage.
      detailBody = const <Object?>[];

      final ReadResult<VendorUserDetail?> result = await buildRepository()
          .userDetail(foreignMembershipUuid);

      expect(result, isA<ReadSuccess<VendorUserDetail?>>());
      expect((result as ReadSuccess<VendorUserDetail?>).value, isNull);
    });
  });

  group('a malformed id never reaches the backend', () {
    test('the detail read answers null without calling the RPC', () async {
      final ReadResult<VendorUserDetail?> result = await buildRepository()
          .userDetail('not-a-uuid');

      expect(detailParams, isEmpty);
      expect((result as ReadSuccess<VendorUserDetail?>).value, isNull);
    });

    test('an empty id is the same answer, and is indistinguishable', () async {
      final ReadResult<VendorUserDetail?> malformed = await buildRepository()
          .userDetail('');
      detailBody = const <Object?>[];
      final ReadResult<VendorUserDetail?> foreign = await buildRepository()
          .userDetail(foreignMembershipUuid);

      expect((malformed as ReadSuccess<VendorUserDetail?>).value, isNull);
      expect((foreign as ReadSuccess<VendorUserDetail?>).value, isNull);
    });
  });

  group('thrown calls are classified by SQLSTATE, never by message', () {
    test('42501 becomes a denial on both reads', () async {
      thrown = postgrest('42501');

      expect(
        (await buildRepository().users()
                as ReadFailure<List<VendorUserSummary>>)
            .failure,
        isA<DeniedFailure>(),
      );
      expect(
        (await buildRepository().userDetail(aminaMembershipUuid)
                as ReadFailure<VendorUserDetail?>)
            .failure,
        isA<DeniedFailure>(),
      );
    });

    test('an unrecognized SQLSTATE is an outage, never a denial', () async {
      thrown = postgrest('08006');

      final ReadResult<List<VendorUserSummary>> result = await buildRepository()
          .users();

      expect(
        (result as ReadFailure<List<VendorUserSummary>>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('an auth exception is unauthenticated, not denied', () async {
      thrown = const AuthException('expired');

      final ReadResult<List<VendorUserSummary>> result = await buildRepository()
          .users();

      expect(
        (result as ReadFailure<List<VendorUserSummary>>).failure,
        isA<UnauthenticatedFailure>(),
      );
    });

    test('a plain transport error is an outage', () async {
      thrown = Exception('socket closed');

      final ReadResult<VendorUserDetail?> result = await buildRepository()
          .userDetail(aminaMembershipUuid);

      expect(
        (result as ReadFailure<VendorUserDetail?>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('the backend message never travels into the failure', () async {
      thrown = postgrest('42501');

      final ReadResult<List<VendorUserSummary>> result = await buildRepository()
          .users();
      final Failure failure =
          (result as ReadFailure<List<VendorUserSummary>>).failure;

      expect(failure.toString(), isNot(contains('backend detail')));
      expect(failure.props, isEmpty);
    });
  });

  group('a malformed body is an outage, never an empty list', () {
    test('the list', () async {
      userBody = <Map<String, Object?>>[userRow(membershipId: 'x')];

      final ReadResult<List<VendorUserSummary>> result = await buildRepository()
          .users();

      expect(
        (result as ReadFailure<List<VendorUserSummary>>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('a null role array on the list', () async {
      userBody = <Map<String, Object?>>[userRow(roleNames: null)];

      final ReadResult<List<VendorUserSummary>> result = await buildRepository()
          .users();

      expect(
        (result as ReadFailure<List<VendorUserSummary>>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('the detail — and it is not reported as "not found"', () async {
      // Unreadable and "not addressable by you" are different events. Collapsing
      // the first into the second would tell a Vendor a colleague is gone.
      detailBody = <Map<String, Object?>>[
        userDetailRow(deactivatedAt: 'last week'),
      ];

      final ReadResult<VendorUserDetail?> result = await buildRepository()
          .userDetail(aminaMembershipUuid);

      expect(result, isA<ReadFailure<VendorUserDetail?>>());
      expect(
        (result as ReadFailure<VendorUserDetail?>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('a non-list body is an outage rather than a crash', () async {
      userBody = <String, Object?>{'unexpected': true};

      final ReadResult<List<VendorUserSummary>> result = await buildRepository()
          .users();

      expect(
        (result as ReadFailure<List<VendorUserSummary>>).failure,
        isA<UnavailableFailure>(),
      );
    });
  });

  group('one read per call', () {
    test('each method issues exactly one RPC', () async {
      final SupabaseVendorUserRepository repository = buildRepository();

      await repository.users();
      await repository.userDetail(aminaMembershipUuid);

      expect(userCalls, 1);
      expect(detailParams, hasLength(1));
    });

    test('listing users never opens a detail', () async {
      // Roles arrive inside the row from a correlated aggregate. A per-user
      // detail read would be N+1 over a join the backend already did.
      await buildRepository().users();

      expect(detailParams, isEmpty);
    });
  });
}

Future<Object?> _neverCalled() async => null;
