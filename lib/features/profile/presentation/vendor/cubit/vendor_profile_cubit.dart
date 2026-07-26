import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../../../core/result/read_result.dart';
import '../../../domain/entities/vendor_administrator_profile.dart';
import '../../../domain/repositories/vendor_profile_repository.dart';

part 'vendor_profile_state.dart';

/// The signed-in Vendor administrator's own profile.
///
/// Backed by repeated calls to `public.get_my_vendor_profile()`, which derives
/// both the person and the Vendor from `auth.uid()` and **accepts nothing at
/// all**. There is no selector, no filter and no identity to pass — so nothing on
/// this screen can widen what comes back, and nothing can narrow it either.
///
/// ## It holds only half the screen
///
/// The Vendor organization name is **not** here and never will be. It comes from
/// the trusted Session / PortalContext the application already resolved, and the
/// page composes the two. A cubit that cached the company name beside the
/// administrator profile would be a second source for it, free to go stale
/// against the session that owns it.
///
/// ## Two operations, and each one's failure is a different event
///
/// * [load] — the first read. A failure here is the administrator section, and
///   retrying it is the only thing worth offering.
/// * [refresh] — the same read again. A failure here must **not** throw away the
///   profile already on screen: it is still the last thing the backend actually
///   said, and blanking an identity because a re-read failed would be worse than
///   showing a slightly old one.
///
/// ## The profile is replaced whole, never merged
///
/// The backend answers both fields in one statement, so they describe one
/// instant and one person. [_fetch] therefore swaps the entire
/// [VendorAdministratorProfile] on success and never updates a field in place.
/// Merging would splice a name read at one moment onto roles read at another —
/// and after a session change that pairing could be one person's name beside
/// another person's roles, which would look entirely plausible.
///
/// ## A denial is never a blank profile
///
/// A refused read leaves [VendorProfileState.profile] exactly as it was — null on
/// a first read, so the screen shows the shared denial state rather than an empty
/// name over an empty role list. "You may not read this profile" and "you have no
/// name and no roles" are opposite claims, and the backend deliberately does not
/// distinguish *which* gate refused, so neither does this.
final class VendorProfileCubit extends Cubit<VendorProfileState> {
  VendorProfileCubit(this._repository) : super(const VendorProfileState());

  final VendorProfileRepository _repository;

  /// Discriminates the answer this cubit is currently waiting for, so a read that
  /// lands after a session change cannot repopulate a cleared profile — and with
  /// it, the previous administrator's name and roles under the new one's session.
  ///
  /// Advanced by every request and by [clear], so a stale first read and a stale
  /// refresh are both dropped on arrival.
  int _token = 0;

  /// Reads the profile, showing the full loading state.
  Future<void> load() => _fetch(showLoading: true);

  /// Re-reads the profile in place.
  ///
  /// Deliberately does not blank the card first: a refresh should update the name
  /// and the roles, not make them flash empty and fill in again. The refresh is
  /// still *visible* — [VendorProfileState.isRefreshing] drives the button
  /// spinner and the pull-to-refresh indicator.
  ///
  /// With nothing loaded yet — a refresh after a failed first read, or a pull on
  /// an empty screen — it shows the loading state instead, because there is
  /// nothing on screen for it to preserve.
  Future<void> refresh() => _fetch(showLoading: state.profile == null);

  Future<void> _fetch({required bool showLoading}) async {
    // Repeated taps must not produce simultaneous requests. One in-flight read at
    // a time, and a second call is a no-op rather than a queued duplicate — two
    // answers to the same question could arrive out of order and leave the older
    // one on screen.
    if (state.isRefreshing) {
      return;
    }

    final int token = ++_token;

    emit(
      state.copyWith(
        phase: showLoading
            ? VendorProfilePhase.loading
            : VendorProfilePhase.ready,
        isRefreshing: true,
        clearFailure: true,
      ),
    );

    final ReadResult<VendorAdministratorProfile> result = await _repository
        .administratorProfile();

    if (isClosed || token != _token) {
      return;
    }

    switch (result) {
      case ReadSuccess<VendorAdministratorProfile>(
        :final VendorAdministratorProfile value,
      ):
        emit(
          state.copyWith(
            phase: VendorProfilePhase.ready,
            // The whole profile, atomically. Neither the name nor the role list
            // is carried over from the previous read.
            profile: value,
            isRefreshing: false,
            clearFailure: true,
          ),
        );

      case ReadFailure<VendorAdministratorProfile>(:final Failure failure):
        emit(
          state.copyWith(
            phase: VendorProfilePhase.failed,
            failure: failure,
            isRefreshing: false,
            // The profile already on screen stays exactly as it is. It is still
            // the last thing the backend actually said, and discarding it because
            // a re-read failed would replace a real identity with nothing.
          ),
        );
    }
  }

  /// Drops the profile held in memory, along with the loading state, the refresh
  /// state and the failure.
  ///
  /// Called when the signed-in person changes. Both fields are personal data —
  /// who the previous administrator is and what they are entitled to do — so the
  /// profile goes as a whole rather than being pruned. A half-cleared profile
  /// would be a shape no backend answer ever produces.
  ///
  /// Advancing the token first means an answer already in flight for the previous
  /// person cannot refill the card after it has been emptied, whichever of the
  /// two reads it was.
  void clear() {
    _token++;
    emit(const VendorProfileState());
  }
}
