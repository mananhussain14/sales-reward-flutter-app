import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/design/design.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/widgets/widgets.dart';
import '../bloc/session_bloc.dart';

/// The retry screen for an operational failure.
///
/// Reached when `get_my_portal_context()` threw, or returned a body this build
/// could not parse. It is **not** an access denial: the session is intact, the
/// backend simply could not be reached or understood, and the honest response
/// is "try again", not "you are not allowed".
///
/// ## Retry
///
/// The retry dispatches [SessionContextRequested], which re-checks that a
/// session still exists before calling the RPC again, and routes only on a valid
/// result. [SessionBloc] collapses concurrent resolutions, so a user hammering
/// the button cannot start two calls — but the button also disables itself while
/// a resolution is in flight, so the impossibility is visible as well as
/// enforced.
class UnavailablePage extends StatelessWidget {
  const UnavailablePage({super.key});

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Scaffold(
      backgroundColor: sr.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: SrSpacing.lg,
              vertical: SrSpacing.huge,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: SrSpacing.compactMaxWidth,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SrBrandLockup(size: 40),
                  const SizedBox(height: SrSpacing.xxxl),
                  BlocBuilder<SessionBloc, SessionState>(
                    builder: (BuildContext context, SessionState state) {
                      // Disable retry while a resolution is already running.
                      final bool resolving = state is SessionResolving;
                      return SrFailureView(
                        failure: _failureOf(state),
                        onRetry: resolving
                            ? null
                            : () => context.read<SessionBloc>().add(
                                const SessionContextRequested(),
                              ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The failure to render. While a retry is in flight the state is
  /// [SessionResolving]; keep showing an unavailable message rather than
  /// flickering, since the router still has us on this page.
  static Failure _failureOf(SessionState state) {
    return state is SessionUnavailable
        ? state.failure
        : const UnavailableFailure();
  }
}
