import 'package:flutter/material.dart';

import '../design/design.dart';
import 'sr_alert.dart';
import 'sr_brand_mark.dart';
import 'sr_button.dart';
import 'sr_card.dart';

/// The shared access-denied surface (§ 3.17).
///
/// A centred `max-w-md` column: the 40px brand lockup, 32px below it a card at
/// `p-6`, holding a 56px amber disc with a 1px inset ring and a 28px shield, the
/// 20px title **"Access denied"**, two supporting paragraphs, and a full-width
/// sign-out button.
///
/// ## The copy is fixed, role-neutral and reason-free
///
/// Both the Vendor route (`/access-denied`) and the Retailer route
/// (`/retailer-access-denied`) render this identical card — deliberately, so
/// that the two are **indistinguishable to a signed-in but unauthorized,
/// possibly hostile, account**.
///
/// The handoff is explicit: Flutter must not add a reason, a role name or a
/// "contact your administrator" line. **Do not add a `role`, `reason`, `title`
/// or `body` parameter to this widget** — telling a caller *which* check refused
/// them turns a denial into an enumeration oracle, which is exactly what the
/// backend's overloaded `42501` exists to prevent. A lifecycle state that has
/// something specific and safe to say renders `SrLifecycleNoticeView` instead;
/// this card's copy stays fixed.
///
/// ## The optional recovery action
///
/// [onCheckAccessAgain] re-runs canonical portal-context resolution. It is an
/// **action**, not a reason, so it does not weaken the rule above — and it is
/// offered on this card precisely so that it is offered on *every* signed-in
/// denial. If the control appeared only alongside a lifecycle explanation, its
/// absence would itself disclose that the caller is in one of the states that
/// has no explanation, which is the oracle the fixed copy exists to close.
///
/// When [onCheckAccessAgain] is null the control is not rendered at all, and
/// this widget behaves exactly as it did before the parameter existed — which is
/// what the route guard's fallback use of it relies on.
///
/// This widget is presentation and decides nothing. The route guard that leads
/// here is a convenience; the real refusal happens in SQL, on every call.
class SrAccessDeniedView extends StatelessWidget {
  const SrAccessDeniedView({
    super.key,
    this.onSignOut,
    this.signingOut = false,
    this.signOutFailed = false,
    this.onCheckAccessAgain,
    this.checkingAccess = false,
  });

  /// The sign-out action. When null the control is disabled — which is how the
  /// screen presents an in-flight sign-out rather than hiding its only
  /// affordance.
  final VoidCallback? onSignOut;

  /// Whether a sign-out is in progress. Shows a busy button.
  final bool signingOut;

  /// Whether the last sign-out attempt failed. Surfaces an inline notice, so a
  /// failed sign-out never leaves the user silently stuck on this screen.
  final bool signOutFailed;

  /// Re-runs canonical portal-context resolution. **Null hides the control
  /// entirely**, which keeps every existing consumer rendering exactly as it did
  /// before this parameter was added.
  final VoidCallback? onCheckAccessAgain;

  /// Whether a portal-context resolution is already running. Shows a busy
  /// button.
  final bool checkingAccess;

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
                  // Mirrors the login lockup, so every entry point reads as one
                  // product.
                  const SrBrandLockup(size: 40),
                  const SizedBox(height: SrSpacing.xxxl),
                  SrCard(
                    padding: const EdgeInsets.all(SrSpacing.xxl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const SrIconDisc(
                          icon: Icons.shield_outlined,
                          tone: SrTone.amber,
                          ringed: true,
                        ),
                        const SizedBox(height: SrSpacing.xl),
                        Text(
                          'Access denied',
                          style: SrTypography.screenTitle.copyWith(
                            color: sr.foreground,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: SrSpacing.sm),
                        Text(
                          'You are signed in, but this account does not have '
                          'access to this page.',
                          style: SrTypography.body.copyWith(
                            color: sr.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: SrSpacing.md),
                        Text(
                          'Use the navigation available to your account, or '
                          'sign in with a different account.',
                          style: SrTypography.body.copyWith(
                            color: sr.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (signOutFailed) ...<Widget>[
                          const SizedBox(height: SrSpacing.xl),
                          const SrAlert(
                            tone: SrAlertTone.error,
                            message:
                                'Could not sign out. Check your connection and '
                                'try again.',
                          ),
                        ],
                        const SizedBox(height: SrSpacing.xxl),
                        if (onCheckAccessAgain != null ||
                            checkingAccess) ...<Widget>[
                          SrButton(
                            label: 'Check access again',
                            loadingLabel: 'Checking access…',
                            fullWidth: true,
                            loading: checkingAccess,
                            onPressed: onCheckAccessAgain,
                          ),
                          const SizedBox(height: SrSpacing.md),
                        ],
                        SrButton(
                          label: 'Sign out',
                          loadingLabel: 'Signing out…',
                          variant: SrButtonVariant.outline,
                          fullWidth: true,
                          loading: signingOut,
                          onPressed: onSignOut,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
