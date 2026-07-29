import 'dart:async';

import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/auth/domain/entities/auth_user.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_context.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';
import 'package:sale_reward/features/auth/domain/entities/retailer_capabilities.dart';
import 'package:sale_reward/features/auth/domain/repositories/auth_repository.dart';
import 'package:sale_reward/features/auth/domain/repositories/portal_context_repository.dart';

/// A hand-written [AuthRepository] fake.
///
/// mocktail could do this, but a hand-written fake makes the auth *stream* — the
/// part these tests care most about — explicit and controllable: a test drives
/// [emitSignedIn] / [emitSignedOut] / [emitTokenRefreshed] and watches the
/// coordinator react.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AuthUser? initialUser}) : _currentUser = initialUser;

  final StreamController<AuthChange> _controller =
      StreamController<AuthChange>.broadcast();

  AuthUser? _currentUser;

  /// Scripts the next [signInWithPassword] result. Defaults to success.
  SignInResult nextSignInResult = const SignInSucceeded();

  /// Scripts the next [signOut] result. Defaults to success.
  SignOutResult nextSignOutResult = const SignOutSucceeded();

  int signInCallCount = 0;
  int signOutCallCount = 0;
  ({String email, String password})? lastSignIn;

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  Stream<AuthChange> get changes => _controller.stream;

  @override
  Future<SignInResult> signInWithPassword({
    required String email,
    required String password,
  }) async {
    signInCallCount++;
    lastSignIn = (email: email, password: password);
    if (nextSignInResult is SignInSucceeded) {
      _currentUser = AuthUser(id: 'user-1', email: email);
      emitSignedIn(_currentUser!);
    }
    return nextSignInResult;
  }

  @override
  Future<SignOutResult> signOut() async {
    signOutCallCount++;
    if (nextSignOutResult is SignOutSucceeded) {
      _currentUser = null;
      emitSignedOut();
    }
    return nextSignOutResult;
  }

  // -- stream controls -------------------------------------------------------

  void emitSignedIn(AuthUser user) {
    _currentUser = user;
    _controller.add(AuthSignedIn(user));
  }

  void emitSignedOut() {
    _currentUser = null;
    _controller.add(const AuthSignedOut());
  }

  void emitTokenRefreshed(AuthUser user) {
    _currentUser = user;
    _controller.add(AuthTokenRefreshed(user));
  }

  /// Changes [currentUser] **without** emitting on the stream.
  ///
  /// Deliberately silent, and only useful for one thing: proving that a consumer
  /// which re-reads `currentUser` after an await catches a subject change on its
  /// own, rather than because `SessionBloc` happened to tear its widget down
  /// first. Every ordinary test should drive identity through [emitSignedIn],
  /// [emitSignedOut] or [emitTokenRefreshed] so the session machinery stays in
  /// the loop — this bypasses it on purpose, to isolate the guard under test.
  void setCurrentUserSilently(AuthUser? user) {
    _currentUser = user;
  }

  Future<void> dispose() => _controller.close();
}

/// A [PortalContextRepository] fake that returns a scripted result and counts
/// its calls — so a test can assert "resolved exactly once".
///
/// For race tests, set [manualCompletion] and each `resolve()` returns a future
/// the test completes by hand via [completeNext]. That makes "an older RPC
/// finishes after a newer state was emitted" a deterministic, timing-free
/// scenario rather than a sleep-and-hope.
class FakePortalContextRepository implements PortalContextRepository {
  FakePortalContextRepository(this.result);

  PortalContextResult result;
  int resolveCallCount = 0;

  /// An optional delay, to open a window in which a second concurrent resolve
  /// can be attempted and shown to be collapsed.
  Duration delay = Duration.zero;

  /// When true, every `resolve()` stays pending until [completeNext] is called.
  bool manualCompletion = false;

  final List<Completer<PortalContextResult>> _pending =
      <Completer<PortalContextResult>>[];

  /// How many `resolve()` calls are still awaiting a manual completion.
  int get pendingCount => _pending.length;

  /// Completes the oldest pending `resolve()` with [override] (or [result]),
  /// in FIFO order — so a test can finish an older request after a newer one.
  void completeNext([PortalContextResult? override]) {
    _pending.removeAt(0).complete(override ?? result);
  }

  @override
  Future<PortalContextResult> resolve() async {
    resolveCallCount++;
    if (manualCompletion) {
      final Completer<PortalContextResult> completer =
          Completer<PortalContextResult>();
      _pending.add(completer);
      return completer.future;
    }
    if (delay != Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return result;
  }
}

/// Builds a resolved [PortalContext] for a given kind, with all capabilities on
/// — the shape the backend actually returns for a well-formed context.
PortalContext contextFor(
  PortalKind kind, {
  String organizationName = 'Example Org',
  RetailerCapabilities? capabilities,
  String organizationId = '11111111-1111-1111-1111-111111111111',
}) {
  final String orgId = organizationId;

  switch (kind) {
    case PortalKind.vendorSuperAdmin:
      return PortalContext(
        contextVersion: supportedPortalContextVersion,
        portalKind: kind,
        vendor: VendorContext(
          organizationId: orgId,
          organizationName: organizationName,
        ),
      );
    case PortalKind.retailerOwner:
    case PortalKind.retailerManager:
    case PortalKind.salesStaff:
      final RetailerKind retailerKind = switch (kind) {
        PortalKind.retailerOwner => RetailerKind.owner,
        PortalKind.retailerManager => RetailerKind.manager,
        _ => RetailerKind.salesStaff,
      };
      return PortalContext(
        contextVersion: supportedPortalContextVersion,
        portalKind: kind,
        retailer: RetailerContext(
          kind: retailerKind,
          organizationId: orgId,
          organizationName: organizationName,
          capabilities: capabilities ?? _allCapabilities,
        ),
      );
    case PortalKind.none:
      return PortalContext.denied;
  }
}

const RetailerCapabilities _allCapabilities = RetailerCapabilities(
  viewRetailerOverview: true,
  viewShops: true,
  viewStaff: true,
  manageStaff: true,
  assignStaffShops: true,
  viewAssignedProducts: true,
  submitReceipts: true,
);

/// A [PortalContextResolved] for [kind].
PortalContextResult resolvedResult(PortalKind kind) =>
    PortalContextResolved(contextFor(kind));

/// A **second** Retailer organization, for session-isolation tests.
///
/// A different `organization_id` is what makes an `Owner A -> Owner B` switch a
/// genuine identity change rather than two states that happen to compare equal.
/// The id is compared locally only; it is never sent anywhere, because the
/// overview RPC takes no arguments.
const String otherRetailerOrganizationId =
    '22222222-2222-2222-2222-222222222222';

/// A resolved Retailer Owner in a **different** organization from the default.
PortalContextResult otherRetailerOwnerResult() => PortalContextResolved(
  contextFor(
    PortalKind.retailerOwner,
    organizationName: 'Southgate Stores',
    organizationId: otherRetailerOrganizationId,
  ),
);

/// A resolved Retailer Owner whose Overview capability hint is off, and whose
/// Shops/Staff/Products hints are on — so a test can prove the hint is a
/// presentation input and never a gate on the screen's own read.
PortalContextResult ownerWithoutOverviewHintResult() => PortalContextResolved(
  contextFor(
    PortalKind.retailerOwner,
    capabilities: const RetailerCapabilities(
      viewRetailerOverview: false,
      viewShops: true,
      viewStaff: true,
      manageStaff: true,
      assignStaffShops: true,
      viewAssignedProducts: true,
      submitReceipts: true,
    ),
  ),
);

/// The denied result.
const PortalContextResult deniedResult = PortalContextDenied(
  PortalContext.denied,
);

/// An operational failure result.
const PortalContextResult unavailableResult = PortalContextFailed(
  UnavailableFailure(),
);

/// A signed-in user for seeding a restored session.
const AuthUser testUser = AuthUser(id: 'user-1', email: 'sam@example.com');

/// A resolved Retailer Owner whose `view_shops` capability is off — for proving
/// the shell hides the Shops destination when the hint says so.
PortalContextResult ownerWithoutShopsResult() {
  return PortalContextResolved(
    contextFor(
      PortalKind.retailerOwner,
      capabilities: const RetailerCapabilities(
        viewRetailerOverview: true,
        viewShops: false,
        viewStaff: true,
        manageStaff: true,
        assignStaffShops: true,
        viewAssignedProducts: true,
        submitReceipts: true,
      ),
    ),
  );
}
