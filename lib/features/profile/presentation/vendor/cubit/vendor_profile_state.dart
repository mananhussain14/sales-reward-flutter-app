part of 'vendor_profile_cubit.dart';

/// Where the administrator profile read has reached.
enum VendorProfilePhase {
  /// Nothing has been read yet.
  initial,

  /// The first read is in flight.
  loading,

  /// A profile is on screen.
  ready,

  /// The read did not produce an answer. With a profile held this means a
  /// *refresh* failed and the name and roles are stale; with none it means the
  /// first read failed.
  failed,
}

/// The loaded Vendor administrator profile, and how it got there.
///
/// **The organization name is deliberately absent.** It belongs to the session,
/// not to this read, and the page composes the two. Holding a copy here would be
/// a second source for the one company field this product has.
final class VendorProfileState extends Equatable {
  const VendorProfileState({
    this.phase = VendorProfilePhase.initial,
    this.profile,
    this.failure,
    this.isRefreshing = false,
  });

  final VendorProfilePhase phase;

  /// The name and the role list as one answer, or null when none has been read.
  ///
  /// Null is **not** an anonymous administrator and is never rendered as one. A
  /// profile that could not be read has no fields at all; an authorized caller
  /// always has a real name and at least one real role. The screen must be able
  /// to tell those apart, which is why the whole profile is nullable rather than
  /// the individual fields.
  final VendorAdministratorProfile? profile;

  /// Why the first read or a refresh failed. A discriminant; never the backend's
  /// own message, and never a permission code.
  final Failure? failure;

  /// True while a read is in flight, first or subsequent.
  ///
  /// Also the duplicate-request guard: one read at a time, so a repeated tap on
  /// Refresh and a pull-to-refresh landing together cannot produce two calls.
  final bool isRefreshing;

  /// A profile is on screen but the last refresh did not succeed.
  ///
  /// A non-blocking state: the card stays, and the notice sits above it.
  bool get isStale => phase == VendorProfilePhase.failed && profile != null;

  /// The first read failed with nothing to show. The administrator section is
  /// the failure.
  bool get hasFailedFirstRead =>
      phase == VendorProfilePhase.failed && profile == null;

  /// Whether the loading skeleton should stand in for the whole screen.
  ///
  /// Only before anything has ever been read. A refresh over a profile already on
  /// screen keeps it, because it is still the last thing the backend actually
  /// said.
  bool get isFirstLoad =>
      phase == VendorProfilePhase.initial ||
      (phase == VendorProfilePhase.loading && profile == null);

  VendorProfileState copyWith({
    VendorProfilePhase? phase,
    VendorAdministratorProfile? profile,
    Failure? failure,
    bool clearFailure = false,
    bool? isRefreshing,
  }) {
    return VendorProfileState(
      phase: phase ?? this.phase,
      // Replaced whole or kept whole. There is deliberately no per-field setter:
      // the name and the roles come from one statement about one person, and a
      // state that could update one of them would be a state that could show one
      // administrator's name beside another's roles.
      profile: profile ?? this.profile,
      failure: clearFailure ? null : (failure ?? this.failure),
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }

  @override
  List<Object?> get props => <Object?>[phase, profile, failure, isRefreshing];
}
