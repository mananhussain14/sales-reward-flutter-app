part of 'role_session_bloc.dart';

/// Events accepted by [RoleSessionBloc].
sealed class RoleSessionEvent extends Equatable {
  const RoleSessionEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Ask the backend which experience this caller is in.
///
/// Dispatched at startup, and — per § 4.3 of the architecture recommendation —
/// on app resume and after any `42501`, because roles change server-side and a
/// stale shell must be rebuilt rather than trusted.
final class RoleSessionResolveRequested extends RoleSessionEvent {
  const RoleSessionResolveRequested();
}

/// Adopt a role locally in order to preview its interface.
///
/// **This grants nothing.** It exists because backend role resolution is not
/// connected in this milestone and the four role shells still need to be
/// reviewable. The resulting state is marked [RoleTrust.localPreview], every
/// shell built from it renders a visible preview banner, and no repository
/// consults it.
///
/// When [PortalContextRepository] is implemented against the real RPC, this
/// event should be removed along with the preview banner.
final class RoleSessionPreviewSelected extends RoleSessionEvent {
  const RoleSessionPreviewSelected(this.role);

  final AppRole role;

  @override
  List<Object?> get props => <Object?>[role];
}

/// Drop the current role — on sign-out, or when returning to the role gate.
final class RoleSessionCleared extends RoleSessionEvent {
  const RoleSessionCleared();
}
