import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../../../core/result/read_result.dart';
import '../../../domain/entities/vendor_role_detail.dart';
import '../../../domain/entities/vendor_role_permission.dart';
import '../../../domain/repositories/vendor_role_repository.dart';

part 'vendor_role_detail_state.dart';

/// One role, opened from the catalogue.
///
/// ## The loading order is load-bearing, not a preference
///
/// 1. `get_vendor_role_detail(p_role_id)` — **once**.
/// 2. Only after a row comes back, `list_vendor_role_permissions(p_role_id)` —
///    **once**.
///
/// The permission read answers an empty list for a genuinely permission-less
/// role *and* for an id that names no role at all. The detail read is what tells
/// those apart: zero rows **there** is the authoritative "this id is not a
/// role". Loading permissions first, or in parallel, would leave the screen
/// unable to distinguish "this role grants nothing" from "this is not a role",
/// and the safe reading of the second is not "grants nothing".
///
/// So when the detail is inaccessible the permission read is **not issued at
/// all** — including for a malformed id from the URL bar, which the repository
/// answers locally without a request ever leaving the device.
///
/// ## Zero rows is one non-leaking state
///
/// An unknown role id, an id belonging to some other table and a malformed one
/// all arrive here as the same `null` and become the same
/// [VendorRoleDetailPhase.notFound]. The screen says the role is not available
/// and says nothing further. There is no "another Vendor's role" to describe —
/// the catalogue is global, so every role readable by one authorized Vendor is
/// readable by all of them — and a message that implied otherwise would be
/// false as well as leaky.
///
/// It is also **not** an outage: `notFound` offers no retry, because retrying
/// cannot change the answer.
///
/// ## Role status travels with the permissions, always
///
/// The permission list reports what is *mapped*. An `INACTIVE` role grants none
/// of it, because `has_organization_permission()` gates on `r.status = 'ACTIVE'`
/// and there is no permission-status column anywhere to gate on instead. So the
/// detail row — which carries the status — is loaded first and stays on screen
/// beside the list, and nothing in this cubit computes effectiveness or hides a
/// mapping.
///
/// ## One instance, provided by the Vendor shell
///
/// The cubit is owned by the shell rather than created per route, for two
/// reasons. It lets the shell's session isolation clear it on a user change — a
/// cubit created below the route would be unreachable from that listener. And
/// [open] is idempotent, so a router refresh or a widget rebuild that re-enters
/// the same role issues no second pair of RPCs.
final class VendorRoleDetailCubit extends Cubit<VendorRoleDetailState> {
  VendorRoleDetailCubit(this._repository)
    : super(const VendorRoleDetailState());

  final VendorRoleRepository _repository;

  /// Discriminates the answer this cubit is currently waiting for.
  ///
  /// Every read captures the token it started under and compares it before
  /// emitting. Opening a second role while the first is in flight, or clearing
  /// on a session change, therefore cannot be overwritten by the earlier answer
  /// arriving late — the classic stale-response race, closed the same way
  /// `SessionBloc` closes it.
  int _token = 0;

  /// Loads [roleId], unless it is already loaded or loading.
  ///
  /// Idempotent on purpose: widget rebuilds, router refreshes and a second entry
  /// into the same route must not produce a second pair of requests. A
  /// *different* id always starts a fresh load, and so does the same id after
  /// [clear].
  Future<void> open(String roleId) {
    if (state.roleId == roleId &&
        state.phase != VendorRoleDetailPhase.initial) {
      return Future<void>.value();
    }
    return _load(roleId);
  }

  /// Re-runs the whole sequence for the currently open role.
  ///
  /// Offered only for an operational failure. There is no retry from
  /// [VendorRoleDetailPhase.notFound]: the backend already answered, and it will
  /// answer the same way.
  Future<void> retryDetail() {
    final String? roleId = state.roleId;
    if (roleId == null || state.isDetailLoading) {
      return Future<void>.value();
    }
    return _load(roleId);
  }

  /// Re-runs **only** the permission read, leaving the loaded role on screen.
  ///
  /// A permission failure degrades that section alone — the role's name, status,
  /// description and counts came from a call that succeeded and are still true,
  /// and re-reading the detail to recover a companion would throw away a good
  /// answer to fix a different one.
  Future<void> retryPermissions() {
    final String? roleId = state.roleId;
    if (roleId == null ||
        state.phase != VendorRoleDetailPhase.ready ||
        state.permissionsPhase == VendorRolePermissionsPhase.loading) {
      return Future<void>.value();
    }
    return _loadPermissions(roleId, _nextToken());
  }

  /// Drops the open role and its permissions.
  ///
  /// Called when the signed-in person changes. The role definition itself is
  /// global, but the row carries this Vendor's own `assigned_member_count`, so
  /// it is private data like any other. The token is advanced first, so an
  /// answer already in flight for the previous person cannot repopulate the
  /// state after it has been emptied.
  void clear() {
    _nextToken();
    emit(const VendorRoleDetailState());
  }

  int _nextToken() => ++_token;

  Future<void> _load(String roleId) async {
    final int token = _nextToken();

    emit(
      VendorRoleDetailState(
        roleId: roleId,
        phase: VendorRoleDetailPhase.loading,
      ),
    );

    final ReadResult<VendorRoleDetail?> result = await _repository.roleDetail(
      roleId,
    );

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case ReadSuccess<VendorRoleDetail?>(:final VendorRoleDetail? value):
        if (value == null) {
          // Not addressable. One state for "no such id", "an id from another
          // table" and "malformed id" alike — and no permission read, because
          // an empty permission list would look like a role that grants
          // nothing.
          emit(state.copyWith(phase: VendorRoleDetailPhase.notFound));
          return;
        }
        emit(state.copyWith(phase: VendorRoleDetailPhase.ready, detail: value));
        await _loadPermissions(roleId, token);

      case ReadFailure<VendorRoleDetail?>(:final Failure failure):
        emit(
          state.copyWith(phase: VendorRoleDetailPhase.failed, failure: failure),
        );
    }
  }

  Future<void> _loadPermissions(String roleId, int token) async {
    emit(
      state.copyWith(
        permissionsPhase: VendorRolePermissionsPhase.loading,
        clearPermissionsFailure: true,
      ),
    );

    final ReadResult<List<VendorRolePermission>> result = await _repository
        .rolePermissions(roleId);

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case ReadSuccess<List<VendorRolePermission>>(
        :final List<VendorRolePermission> value,
      ):
        emit(
          state.copyWith(
            permissionsPhase: VendorRolePermissionsPhase.ready,
            permissions: value,
            clearPermissionsFailure: true,
          ),
        );

      case ReadFailure<List<VendorRolePermission>>(:final Failure failure):
        emit(
          state.copyWith(
            permissionsPhase: VendorRolePermissionsPhase.failed,
            permissionsFailure: failure,
          ),
        );
    }
  }
}
