import 'dart:async';

import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/profile/domain/entities/vendor_administrator_profile.dart';
import 'package:sale_reward/features/profile/domain/repositories/vendor_profile_repository.dart';

/// A hand-written [VendorProfileRepository] fake.
///
/// Hand-written rather than mocked because these tests care about *how many
/// times* the profile was asked for as much as what came back: [callCount] is how
/// a test proves that a duplicate refresh is suppressed, that a session change
/// reloads exactly once, and that an identical re-emitted session reloads not at
/// all.
///
/// There is nothing to record about *what was sent*, because nothing is ever
/// sent — the contract takes zero arguments, which is why this fake has no
/// captured-parameter list at all. That absence is itself the shape of the
/// contract.
class FakeVendorProfileRepository implements VendorProfileRepository {
  /// When set, every call answers this — how a test scripts a failure.
  ReadResult<VendorAdministratorProfile>? result;

  /// The profile returned when [result] is unset.
  VendorAdministratorProfile nextProfile = aminaAdministratorProfile;

  int callCount = 0;

  /// When true, every call stays pending until it is completed by hand — so "a
  /// second refresh while one is in flight" and "a stale answer arriving after a
  /// session change" are deterministic rather than a sleep-and-hope.
  bool manual = false;
  final List<Completer<ReadResult<VendorAdministratorProfile>>> _pending =
      <Completer<ReadResult<VendorAdministratorProfile>>>[];

  int get pendingCount => _pending.length;

  /// Completes the oldest pending call.
  void complete([ReadResult<VendorAdministratorProfile>? override]) =>
      completeAt(0, override);

  /// Completes a pending call **out of order**, so a test can make an older
  /// request answer after a newer one — the stale-response race the request token
  /// exists to close. [index] is into the pending queue, oldest first.
  void completeAt(
    int index, [
    ReadResult<VendorAdministratorProfile>? override,
  ]) {
    _pending
        .removeAt(index)
        .complete(
          override ??
              result ??
              ReadSuccess<VendorAdministratorProfile>(nextProfile),
        );
  }

  @override
  Future<ReadResult<VendorAdministratorProfile>> administratorProfile() {
    callCount++;
    if (manual) {
      final Completer<ReadResult<VendorAdministratorProfile>> completer =
          Completer<ReadResult<VendorAdministratorProfile>>();
      _pending.add(completer);
      return completer.future;
    }
    return Future<ReadResult<VendorAdministratorProfile>>.value(
      result ?? ReadSuccess<VendorAdministratorProfile>(nextProfile),
    );
  }
}

// ---------------------------------------------------------------------------
// Fixtures
//
// Invented people. Nothing here is a real name from any environment, and no
// fixture carries an id, an email, a mobile number, a status or a timestamp —
// the contract returns none of them, so a fixture that had one would be testing
// a shape the backend cannot produce.
//
// The two administrators deliberately hold DIFFERENT roles as well as different
// names, so a session-isolation test asserting "A's roles are gone" cannot pass
// by accidentally reading a shared value.
// ---------------------------------------------------------------------------

/// The ordinary answer: one administrator, one role.
const VendorAdministratorProfile aminaAdministratorProfile =
    VendorAdministratorProfile(
      displayName: 'Amina Rahman',
      roleNames: <String>['Vendor Super Admin'],
    );

/// A second administrator, for session-isolation tests.
const VendorAdministratorProfile joAdministratorProfile =
    VendorAdministratorProfile(
      displayName: 'Jo Nakamura',
      roleNames: <String>['Finance Admin', 'Vendor Super Admin'],
    );

/// An administrator holding several roles, in the backend's own order.
///
/// Ordered by role display name — `Catalogue Manager`, `Finance Admin`,
/// `Vendor Super Admin` — exactly as `order by r.name, r.id` produces it. A test
/// that re-sorted in Dart would still pass on this fixture, which is why the
/// order-preservation test uses [reversedOrderProfile] instead.
const VendorAdministratorProfile multiRoleAdministratorProfile =
    VendorAdministratorProfile(
      displayName: 'Amina Rahman',
      roleNames: <String>[
        'Catalogue Manager',
        'Finance Admin',
        'Vendor Super Admin',
      ],
    );

/// A role list in an order Dart's own `compareTo` would NOT produce.
///
/// The point of the fixture: if anything in the client re-sorted the array, this
/// would come back alphabetised and the assertion would fail. It is not a shape
/// the deployed function emits — it exists to prove the client does not impose
/// one of its own.
const VendorAdministratorProfile reversedOrderProfile =
    VendorAdministratorProfile(
      displayName: 'Amina Rahman',
      roleNames: <String>[
        'Vendor Super Admin',
        'Finance Admin',
        'Catalogue Manager',
      ],
    );

/// The defensive empty-role answer.
///
/// **Unreachable for an authorized caller** — the ACTIVE Vendor Super Admin
/// assignment that authorized them is always in the array, and removing it denies
/// the read rather than emptying it. Kept as a fixture only so the safe
/// presentation can be exercised, and deliberately not used as the default.
const VendorAdministratorProfile noRoleAdministratorProfile =
    VendorAdministratorProfile(
      displayName: 'Amina Rahman',
      roleNames: <String>[],
    );

/// One `get_my_vendor_profile()` row, as PostgREST returns it.
///
/// Two keys, in the contract's own order, and **no** id, organization name,
/// organization id, email, mobile number, status, timestamp, role code or
/// permission code — the function returns none of them.
Map<String, Object?> administratorProfileRow({
  Object? displayName = 'Amina Rahman',
  Object? roleNames = const <Object?>['Vendor Super Admin'],
}) => <String, Object?>{
  'administrator_display_name': displayName,
  'administrator_role_names': roleNames,
};

/// A well-formed body: a list of exactly one row.
List<Map<String, Object?>> administratorProfileBody([
  Map<String, Object?>? row,
]) => <Map<String, Object?>>[row ?? administratorProfileRow()];

/// A read that failed the way an unreadable body does.
ReadResult<T> unavailableProfileRead<T>() =>
    ReadFailure<T>(const UnavailableFailure());

/// A read the backend refused with `42501` — which covers a caller who is not
/// signed in, is not a Vendor Super Admin, whose profile, membership or
/// organization is suspended, or whose role no longer holds `RBAC_READ`. All of
/// them are the same answer here, exactly as they are in SQL.
ReadResult<T> deniedProfileRead<T>() => ReadFailure<T>(const DeniedFailure());
