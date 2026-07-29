import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/auth_user.dart';
import '../../domain/entities/lifecycle_access_state.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/lifecycle_access_repository.dart';

part 'lifecycle_access_view_state.dart';

/// Asks the backend, once, why *this* caller's access was refused.
///
/// ## ⚠️ It is a diagnostic. It is not an authorization gate, and must not become one.
///
/// `SessionBloc` and the `SECURITY DEFINER` functions behind every RPC remain
/// the only things that decide whether a request may proceed. A resolved
/// [LifecycleAccessState.active] here is **not** permission to do anything — it
/// is a description of why the real gate said no, read after the real gate said
/// no. This Cubit therefore holds no router, no `BuildContext`, no
/// `GoRouter` and no navigation callback: it *cannot* route, by construction
/// rather than by discipline, and its answer chooses a SENTENCE and nothing else.
///
/// ## Page-scoped, and that is a security property
///
/// Created by `BlocProvider` inside `AccessDeniedPage` and disposed with it. It
/// is never registered in the service locator, never app- or shell-scoped, holds
/// no `static`, and writes nothing to disk. There is consequently no object that
/// outlives the page in which a previous person's diagnostic could survive to be
/// rendered under the next person's session — the guards below are defence in
/// depth on top of that structural guarantee, not the guarantee itself.
///
/// ## One request, ever
///
/// [load] answers exactly once per Cubit, and the page creates one Cubit per
/// denied episode. There is no refresh, no timer, no polling, no
/// `Stream.periodic`, no `Future.delayed` and no retry. The user's way to ask
/// again is the page's **Check access again** control, which re-runs *canonical
/// portal-context resolution* — the only thing that can actually restore access
/// — and in doing so unmounts this page and disposes this Cubit.
///
/// ## Why it subscribes to nothing
///
/// It does not listen to `AuthRepository.changes` and does not listen to
/// `SessionBloc`. The shells do the latter because they are long-lived and must
/// survive an identity change; a page-scoped Cubit does not — the router
/// unmounts the page on every session transition, which closes this Cubit. Adding
/// a second subscription would create, in the words of the Vendor shell's own
/// documentation, "a second opinion about who is signed in, and two opinions is
/// one too many". It reads `currentUser` at two points and subscribes to nothing.
final class LifecycleAccessCubit extends Cubit<LifecycleAccessViewState> {
  LifecycleAccessCubit({
    required LifecycleAccessRepository repository,
    required AuthRepository authRepository,
  }) : _repository = repository,
       _auth = authRepository,
       super(const LifecycleAccessViewState.initial());

  final LifecycleAccessRepository _repository;
  final AuthRepository _auth;

  /// Bumped on every request and on [close]. A result may only commit at the
  /// generation that started it, so any newer intent invalidates an in-flight
  /// read.
  int _generation = 0;

  /// True between starting a request and committing or discarding it. Together
  /// with the phase check in [load] this makes a rebuild-triggered second call
  /// impossible.
  bool _inFlight = false;

  /// Reads the diagnostic once.
  ///
  /// Idempotent in both directions: a request already in flight is dropped, and
  /// a Cubit that has already answered is dropped. A widget rebuild, a second
  /// `initState` in a co-mounted route, or a defensive double call therefore
  /// issues at most one RPC.
  Future<void> load() async {
    if (_inFlight || state.phase != LifecycleAccessPhase.initial) {
      return;
    }

    // The owner is captured BEFORE the request, from the same source
    // `SessionBloc` uses to decide whether a resolution may commit — never from
    // a decoded token, an email, a display name or a role label.
    final AuthUser? user = _auth.currentUser;
    final String? owner = user?.id;

    // No session means no subject, and the RPC would raise 42501 anyway. Staying
    // in `initial` renders the ordinary denial, which is the honest answer for
    // somebody the diagnostic cannot describe. Signing them out here would be
    // this screen taking an action the session coordinator owns.
    if (owner == null) {
      return;
    }

    _inFlight = true;
    final int generation = ++_generation;
    emit(const LifecycleAccessViewState.loading());

    final LifecycleAccessResult result = await _repository.read();

    // The four-part commit check. The RPC cannot be un-called, but its result
    // can be — and is — discarded.
    if (isClosed) {
      return;
    }
    if (generation != _generation) {
      return;
    }
    // Re-read after the await: a subject swap can land while the request is in
    // flight and before the widget tree has been torn down. `SessionBloc`
    // performs the same re-read at its own commit point.
    final String? currentOwner = _auth.currentUser?.id;
    if (currentOwner == null || currentOwner != owner) {
      return;
    }

    _inFlight = false;
    emit(switch (result) {
      LifecycleAccessResolved(:final LifecycleAccessState state) =>
        LifecycleAccessViewState.resolved(state),
      LifecycleAccessUnavailable() =>
        const LifecycleAccessViewState.unavailable(),
    });
  }

  /// Advances the generation before delegating, so a read still in flight is
  /// invalidated rather than merely unable to emit.
  ///
  /// `isClosed` alone would stop the `emit`, but making the generation the thing
  /// that fails keeps the invariant true for any future post-await work that is
  /// not an emit. The capability probe's `clear()` advances its token first for
  /// the same reason.
  @override
  Future<void> close() {
    _generation++;
    return super.close();
  }
}
