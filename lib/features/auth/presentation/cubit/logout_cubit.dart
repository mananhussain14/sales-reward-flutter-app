import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/repositories/auth_repository.dart';

/// The state of a sign-out attempt.
enum LogoutStatus { idle, inProgress, failed }

/// Performs sign-out, and owns only the button's own state.
///
/// ## Why this is separate from [SessionBloc]
///
/// The two have different jobs and different lifetimes. This Cubit *performs*
/// the sign-out and reports whether the request itself succeeded; the session
/// coordinator *reacts* to the resulting auth change and clears the context.
/// Neither drives the other, so there is exactly one caller of `signOut()` and
/// exactly one listener of the auth stream.
///
/// Folding this into the coordinator would mean adding a transient "sign-out
/// failed" case to a state machine whose states are otherwise durable — and a
/// failed sign-out must not disturb the session state at all, because the user
/// is still legitimately signed in.
class LogoutCubit extends Cubit<LogoutStatus> {
  LogoutCubit({required AuthRepository authRepository})
    : _auth = authRepository,
      super(LogoutStatus.idle);

  final AuthRepository _auth;

  /// Signs out. Re-entrant calls while a sign-out is in flight are dropped.
  ///
  /// On success this emits nothing further: the auth stream carries the change
  /// to [SessionBloc], the router follows, and this Cubit's widget is gone
  /// before any success state could be rendered.
  ///
  /// On failure the status becomes [LogoutStatus.failed] so the sheet can say
  /// so. Silently leaving the user on an authenticated screen after a failed
  /// sign-out is the outcome this exists to prevent.
  Future<void> signOut() async {
    if (state == LogoutStatus.inProgress) {
      return;
    }
    emit(LogoutStatus.inProgress);

    final SignOutResult result = await _auth.signOut();
    if (isClosed) {
      return;
    }

    emit(switch (result) {
      SignOutSucceeded() => LogoutStatus.inProgress,
      SignOutFailed() => LogoutStatus.failed,
    });
  }
}
