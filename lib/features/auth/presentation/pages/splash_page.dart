import 'package:flutter/material.dart';

import '../../../../core/design/design.dart';
import '../../../../core/widgets/widgets.dart';

/// The launch screen, shown while the session is being resolved.
///
/// It is deliberately quiet: the brand lockup over a loading skeleton, and
/// nothing that presumes an answer. This is the screen that stands between app
/// launch and the first shell, and its entire job is to exist for exactly as
/// long as resolution takes — no role shell may render until the backend has
/// answered, so *something* must hold the frame in the meantime.
///
/// The router redirects away from it the instant the session settles into any
/// terminal state (a role, denial, unavailable, or unauthenticated), so a user
/// only sees it during the resolving window.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Scaffold(
      backgroundColor: sr.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: SrSpacing.compactMaxWidth,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SrBrandLockup(size: 44),
                const SizedBox(height: SrSpacing.xxxl),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: sr.brand,
                  ),
                ),
                const SizedBox(height: SrSpacing.lg),
                // Generic on purpose: a loading label must never name a record,
                // an organization, or a person.
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Loading…',
                    style: SrTypography.body.copyWith(color: sr.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
