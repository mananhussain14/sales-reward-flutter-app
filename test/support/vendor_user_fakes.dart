import 'dart:async';

import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/users/domain/entities/vendor_user_detail.dart';
import 'package:sale_reward/features/users/domain/entities/vendor_user_status.dart';
import 'package:sale_reward/features/users/domain/entities/vendor_user_summary.dart';
import 'package:sale_reward/features/users/domain/repositories/vendor_user_repository.dart';

/// A hand-written [VendorUserRepository] fake.
///
/// Hand-written rather than mocked because these tests care about *what was
/// sent* as much as what came back: [requestedMembershipIds] is how a test
/// proves that one membership id — and nothing beside it — ever leaves the
/// client.
class FakeVendorUserRepository implements VendorUserRepository {
  ReadResult<List<VendorUserSummary>> usersResult =
      ReadSuccess<List<VendorUserSummary>>(<VendorUserSummary>[
        aminaSummary,
        joSummary,
      ]);

  /// When set, every detail read answers this whatever id was asked for — how a
  /// test scripts a failure or a blanket "not addressable".
  ReadResult<VendorUserDetail?>? detailResult;

  /// Otherwise the fake answers the way the backend does: a membership this
  /// caller may read returns its row, and **every** other id — unknown, another
  /// Vendor's, a Retailer's, or malformed — returns zero rows,
  /// indistinguishably.
  Map<String, VendorUserDetail> knownDetails = <String, VendorUserDetail>{
    aminaMembershipUuid: aminaDetail,
    joMembershipUuid: joDetail,
  };

  int usersCallCount = 0;
  final List<String> requestedMembershipIds = <String>[];

  int get detailCallCount => requestedMembershipIds.length;

  /// When true, every [users] call stays pending until [completeUsers] is
  /// called — so "a second refresh while one is in flight" is deterministic
  /// rather than a sleep-and-hope.
  bool manualUsers = false;
  final List<Completer<ReadResult<List<VendorUserSummary>>>> _pendingUsers =
      <Completer<ReadResult<List<VendorUserSummary>>>>[];

  int get pendingUserCount => _pendingUsers.length;

  void completeUsers([ReadResult<List<VendorUserSummary>>? override]) {
    _pendingUsers.removeAt(0).complete(override ?? usersResult);
  }

  /// The same control for the detail read.
  bool manualDetail = false;
  final List<Completer<ReadResult<VendorUserDetail?>>> _pendingDetail =
      <Completer<ReadResult<VendorUserDetail?>>>[];

  int get pendingDetailCount => _pendingDetail.length;

  void completeDetail([ReadResult<VendorUserDetail?>? override]) {
    _pendingDetail
        .removeAt(0)
        .complete(override ?? _detailFor(requestedMembershipIds.last));
  }

  @override
  Future<ReadResult<List<VendorUserSummary>>> users() {
    usersCallCount++;
    if (manualUsers) {
      final Completer<ReadResult<List<VendorUserSummary>>> completer =
          Completer<ReadResult<List<VendorUserSummary>>>();
      _pendingUsers.add(completer);
      return completer.future;
    }
    return Future<ReadResult<List<VendorUserSummary>>>.value(usersResult);
  }

  @override
  Future<ReadResult<VendorUserDetail?>> userDetail(String membershipId) {
    requestedMembershipIds.add(membershipId);
    if (manualDetail) {
      final Completer<ReadResult<VendorUserDetail?>> completer =
          Completer<ReadResult<VendorUserDetail?>>();
      _pendingDetail.add(completer);
      return completer.future;
    }
    return Future<ReadResult<VendorUserDetail?>>.value(
      _detailFor(membershipId),
    );
  }

  ReadResult<VendorUserDetail?> _detailFor(String membershipId) =>
      detailResult ??
      ReadSuccess<VendorUserDetail?>(knownDetails[membershipId]);
}

// ---------------------------------------------------------------------------
// Fixtures
//
// Invented names and invented ids. Nothing here is a real person, a real
// organization or a real identifier from any environment.
// ---------------------------------------------------------------------------

const String aminaMembershipUuid = '8a1b2c3d-4e5f-4061-9273-8495a6b7c8d9';
const String joMembershipUuid = '9b2c3d4e-5f60-4172-a384-95a6b7c8d9e0';

/// A membership id belonging to no row this caller may read. Well formed on
/// purpose: the point is that a *valid-looking* foreign id is inert. It stands
/// in equally for another Vendor's membership and for a Retailer-owned one —
/// the backend answers zero rows for both, indistinguishably.
const String foreignMembershipUuid = 'a3c4d5e6-f071-4283-b495-a6b7c8d9e0f1';

final DateTime aminaCreatedAt = DateTime.utc(2026, 1, 14, 9, 5);
final DateTime aminaJoinedAt = DateTime.utc(2026, 1, 15, 10, 30);
final DateTime joCreatedAt = DateTime.utc(2026, 6, 2, 14, 0);
final DateTime joDeactivatedAt = DateTime.utc(2026, 7, 20, 16, 45);

/// An active administrator holding two roles, in the backend's order.
final VendorUserSummary aminaSummary = VendorUserSummary(
  membershipId: aminaMembershipUuid,
  displayName: 'Amina Rahman',
  profileStatus: VendorUserStatus.active,
  membershipStatus: VendorUserStatus.active,
  membershipCreatedAt: aminaCreatedAt,
  joinedAt: aminaJoinedAt,
  roleNames: const <String>['Finance Admin', 'Vendor Super Admin'],
);

/// Deliberately **invited**, **never joined** and holding **no role**: each of
/// those is a real state the screens must render rather than hide, and the empty
/// role array is the one that must never become a privilege.
final VendorUserSummary joSummary = VendorUserSummary(
  membershipId: joMembershipUuid,
  displayName: 'Jo Nakamura',
  profileStatus: VendorUserStatus.invited,
  membershipStatus: VendorUserStatus.invited,
  membershipCreatedAt: joCreatedAt,
  joinedAt: null,
  roleNames: const <String>[],
);

/// The detail for [aminaSummary] — a live membership, so no deactivation date.
final VendorUserDetail aminaDetail = VendorUserDetail(
  membershipId: aminaMembershipUuid,
  displayName: 'Amina Rahman',
  profileStatus: VendorUserStatus.active,
  membershipStatus: VendorUserStatus.active,
  membershipCreatedAt: aminaCreatedAt,
  joinedAt: aminaJoinedAt,
  deactivatedAt: null,
  roleNames: const <String>['Finance Admin', 'Vendor Super Admin'],
);

/// The detail for [joSummary].
final VendorUserDetail joDetail = VendorUserDetail(
  membershipId: joMembershipUuid,
  displayName: 'Jo Nakamura',
  profileStatus: VendorUserStatus.invited,
  membershipStatus: VendorUserStatus.invited,
  membershipCreatedAt: joCreatedAt,
  joinedAt: null,
  deactivatedAt: null,
  roleNames: const <String>[],
);

/// A deactivated membership, so the deactivation row has something to render.
final VendorUserDetail deactivatedDetail = VendorUserDetail(
  membershipId: joMembershipUuid,
  displayName: 'Jo Nakamura',
  profileStatus: VendorUserStatus.suspended,
  membershipStatus: VendorUserStatus.deactivated,
  membershipCreatedAt: joCreatedAt,
  joinedAt: aminaJoinedAt,
  deactivatedAt: joDeactivatedAt,
  roleNames: const <String>[],
);

/// A `list_vendor_users()` body, as PostgREST returns it.
List<Map<String, Object?>> userRows() => <Map<String, Object?>>[
  userRow(),
  userRow(
    membershipId: joMembershipUuid,
    displayName: 'Jo Nakamura',
    profileStatus: 'INVITED',
    membershipStatus: 'INVITED',
    createdAt: '2026-06-02T14:00:00+00:00',
    joinedAt: null,
    roleNames: <Object?>[],
  ),
];

Map<String, Object?> userRow({
  Object? membershipId = aminaMembershipUuid,
  Object? displayName = 'Amina Rahman',
  Object? profileStatus = 'ACTIVE',
  Object? membershipStatus = 'ACTIVE',
  Object? createdAt = '2026-01-14T09:05:00+00:00',
  Object? joinedAt = '2026-01-15T10:30:00+00:00',
  Object? roleNames = const <Object?>['Finance Admin', 'Vendor Super Admin'],
}) => <String, Object?>{
  'membership_id': membershipId,
  'display_name': displayName,
  'profile_status': profileStatus,
  'membership_status': membershipStatus,
  'membership_created_at': createdAt,
  'joined_at': joinedAt,
  'role_names': roleNames,
};

/// A `get_vendor_user_detail(uuid)` row — the list shape plus `deactivated_at`.
Map<String, Object?> userDetailRow({
  Object? membershipId = aminaMembershipUuid,
  Object? displayName = 'Amina Rahman',
  Object? profileStatus = 'ACTIVE',
  Object? membershipStatus = 'ACTIVE',
  Object? createdAt = '2026-01-14T09:05:00+00:00',
  Object? joinedAt = '2026-01-15T10:30:00+00:00',
  Object? deactivatedAt,
  Object? roleNames = const <Object?>['Finance Admin', 'Vendor Super Admin'],
}) => <String, Object?>{
  ...userRow(
    membershipId: membershipId,
    displayName: displayName,
    profileStatus: profileStatus,
    membershipStatus: membershipStatus,
    createdAt: createdAt,
    joinedAt: joinedAt,
    roleNames: roleNames,
  ),
  'deactivated_at': deactivatedAt,
};

/// A read that failed the way an unreadable body does.
ReadResult<T> unavailableUserRead<T>() =>
    ReadFailure<T>(const UnavailableFailure());

/// A read the backend refused with `42501`.
ReadResult<T> deniedUserRead<T>() => ReadFailure<T>(const DeniedFailure());
