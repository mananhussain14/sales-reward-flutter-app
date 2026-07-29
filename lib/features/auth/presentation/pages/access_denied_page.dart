import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/lifecycle_access_state.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/lifecycle_access_repository.dart';
import '../bloc/session_bloc.dart';
import '../cubit/lifecycle_access_cubit.dart';
import '../cubit/logout_cubit.dart';
import '../widgets/lifecycle_access_copy.dart';

/// The route that renders the shared, role-neutral access-denied screen.
///
/// Reached two ways, and the two must stay distinguishable *to this widget* even
/// though they look identical to the user:
///
/// * the backend answered `portal_kind: NONE`, so [SessionBloc] is
///   [SessionDenied] — a verified identity that qualifies for no supported
///   experience. **This is the only case that runs the lifecycle diagnostic.**
/// * the route guard caught an attempt to enter a role group the caller's
///   resolved role does not own, and `_roleShell` built this page directly as a
///   fallback. Here the session may be resolving, unavailable, or active for a
///   different role.
///
/// ## Why the diagnostic is gated on [SessionDenied] rather than on mounting
///
/// `_roleShell` renders `const AccessDeniedPage()` whenever the session is not
/// [SessionActive] for its own role, and pages genuinely co-mount for a frame or
/// two during a go_router transition. A diagnostic fired from `initState` alone
/// would therefore run for a caller who has not been denied anything — during a
/// resolution, during an outage, or while an authorized user crosses between
/// shells.
///
/// The gate is read **once**, in [State.initState], and never re-read. Capturing
/// it rather than watching it is deliberate: a rebuild while the session is
/// already moving to [SessionResolving] would otherwise tear the diagnostic
/// subtree down and flash the generic card in the last frame before the router
/// unmounts this page anyway.
///
/// ## One diagnostic per denied *episode*, and why remounting is not enough
///
/// The obvious design is to let the page's own lifetime bound the diagnostic:
/// press **Check access again**, the session goes `Denied → Resolving → Denied`,
/// the router shows the splash in between, this page is rebuilt from scratch,
/// and a fresh cubit asks again. That is what happens when the portal-context
/// RPC takes a real round trip.
///
/// **It is not what happens when the resolution is fast.** `SessionResolving`
/// and the next `SessionDenied` can be emitted within a single frame, in which
/// case `redirectFor` never gets a chance to send the user to the splash, the
/// location never leaves `/access-denied`, this [State] survives, and a
/// mount-scoped cubit would never re-ask — leaving the *previous* episode's
/// lifecycle copy on screen after the user explicitly asked for a fresh answer.
/// A member reactivated moments ago would keep reading "your access to this
/// Retailer is inactive", and the faster the backend, the more likely it is.
///
/// So the episode is tracked explicitly rather than inferred from the widget
/// lifetime. [_deniedEpisode] counts entries *into* [SessionDenied]; the
/// provider below is keyed on it, so each new denial builds a genuinely new
/// [LifecycleAccessCubit] which asks exactly once. The previous cubit is closed
/// by the framework, and its in-flight answer — if any — is dropped by that
/// cubit's own generation and owner guards.
///
/// This is deliberately **not** an in-place refresh: no cubit ever performs a
/// second read, and nothing polls, retries or re-asks on a timer. It is one
/// cubit per denial, made correct whether or not the router happens to unmount
/// the page in between.
///
/// Sign-out remains, unchanged, in every case. This widget does not route
/// itself: routing from here would be a second opinion about where a user
/// belongs, and only [SessionBloc] holds the first one.
class AccessDeniedPage extends StatefulWidget {
  const AccessDeniedPage({super.key});

  @override
  State<AccessDeniedPage> createState() => _AccessDeniedPageState();
}

class _AccessDeniedPageState extends State<AccessDeniedPage> {
  /// Which denial this page is currently explaining, or null if the backend has
  /// denied nothing and this is the route guard's fallback render.
  ///
  /// Seeded once in [initState] and advanced only on a transition *into*
  /// [SessionDenied]. `context.read` is the correct accessor in `initState`;
  /// watching there is not allowed and would be the wrong question anyway.
  int? _deniedEpisode;

  @override
  void initState() {
    super.initState();
    if (context.read<SessionBloc>().state is SessionDenied) {
      _deniedEpisode = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LogoutCubit>(
      create: (BuildContext context) =>
          LogoutCubit(authRepository: context.read<AuthRepository>()),
      // Only a transition INTO denial starts a new episode. Every other session
      // change — including the `SessionResolving` on the way there — is ignored,
      // so a single press produces exactly one new diagnostic.
      child: BlocListener<SessionBloc, SessionState>(
        listenWhen: (SessionState previous, SessionState current) =>
            current is SessionDenied && previous is! SessionDenied,
        listener: (BuildContext context, SessionState state) =>
            setState(() => _deniedEpisode = (_deniedEpisode ?? -1) + 1),
        child: _deniedEpisode == null
            ? const _GuardFallbackView()
            : BlocProvider<LifecycleAccessCubit>(
                // Keyed on the episode: a new denial replaces the provider, so
                // the old cubit is closed and a new one asks once.
                key: ValueKey<int>(_deniedEpisode!),
                // The repository is resolved here and nowhere else, so an
                // application that never reaches a denial never builds it.
                create: (BuildContext context) => LifecycleAccessCubit(
                  repository: context.read<LifecycleAccessRepository>(),
                  authRepository: context.read<AuthRepository>(),
                )..load(),
                child: const _DeniedSessionView(),
              ),
      ),
    );
  }
}

/// The access-denied screen for a confirmed `portal_kind: NONE` session.
class _DeniedSessionView extends StatelessWidget {
  const _DeniedSessionView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LogoutCubit, LogoutStatus>(
      builder: (BuildContext context, LogoutStatus logout) {
        return BlocBuilder<LifecycleAccessCubit, LifecycleAccessViewState>(
          builder: (BuildContext context, LifecycleAccessViewState diagnostic) {
            // Narrowly projected: this screen cares about exactly one bit of the
            // session, and rebuilding it for any other session change would be
            // noise. `BlocSelector` states the projection in the tree, where a
            // reviewer asking "can this button be pressed during a resolution?"
            // will look.
            return BlocSelector<SessionBloc, SessionState, bool>(
              selector: (SessionState state) => state is SessionResolving,
              builder: (BuildContext context, bool resolving) {
                final bool signingOut = logout == LogoutStatus.inProgress;

                // Check access again re-runs CANONICAL portal-context
                // resolution. It never calls the diagnostic: the diagnostic
                // explains a refusal and cannot lift one, and only
                // `PortalContextResolved` can restore access.
                final VoidCallback? onCheckAccessAgain = resolving
                    ? null
                    : () => context.read<SessionBloc>().add(
                        const SessionContextRequested(),
                      );
                final VoidCallback? onSignOut = signingOut
                    ? null
                    : () => context.read<LogoutCubit>().signOut();

                final LifecycleNotice? notice = _noticeFor(diagnostic);

                // The ordinary card for every phase with nothing specific and
                // safe to say: not asked yet, still asking, unreadable, ACTIVE,
                // and NO_SUPPORTED_ACCESS. The two controls are identical in
                // both branches, so their presence discloses nothing about
                // which of those it is.
                if (notice == null) {
                  return SrAccessDeniedView(
                    signingOut: signingOut,
                    signOutFailed: logout == LogoutStatus.failed,
                    onSignOut: onSignOut,
                    checkingAccess: resolving,
                    onCheckAccessAgain: onCheckAccessAgain,
                  );
                }

                return SrLifecycleNoticeView(
                  title: notice.title,
                  body: notice.body,
                  closing: notice.closing,
                  signingOut: signingOut,
                  signOutFailed: logout == LogoutStatus.failed,
                  onSignOut: onSignOut,
                  checkingAccess: resolving,
                  onCheckAccessAgain: onCheckAccessAgain,
                );
              },
            );
          },
        );
      },
    );
  }

  /// The lifecycle notice to render, or null to keep the ordinary card.
  ///
  /// Only a *resolved* diagnostic can produce one, and only for the four states
  /// the copy module maps. `ACTIVE` and `NO_SUPPORTED_ACCESS` resolve to null
  /// there deliberately — see `lifecycle_access_copy.dart`.
  static LifecycleNotice? _noticeFor(LifecycleAccessViewState diagnostic) {
    final LifecycleAccessState? state = diagnostic.state;
    if (diagnostic.phase != LifecycleAccessPhase.resolved || state == null) {
      return null;
    }
    return noticeFor(state);
  }
}

/// The access-denied screen as the route guard's fallback.
///
/// No diagnostic runs and no diagnostic repository is resolved: nothing here has
/// been denied by the backend, so there is no refusal to explain. Byte-for-byte
/// the screen this page rendered before the diagnostic existed.
class _GuardFallbackView extends StatelessWidget {
  const _GuardFallbackView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LogoutCubit, LogoutStatus>(
      builder: (BuildContext context, LogoutStatus status) {
        return SrAccessDeniedView(
          signingOut: status == LogoutStatus.inProgress,
          signOutFailed: status == LogoutStatus.failed,
          onSignOut: status == LogoutStatus.inProgress
              ? null
              : () => context.read<LogoutCubit>().signOut(),
        );
      },
    );
  }
}
