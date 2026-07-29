import 'package:flutter/material.dart';

import '../design/design.dart';
import 'sr_alert.dart';
import 'sr_brand_mark.dart';
import 'sr_button.dart';
import 'sr_card.dart';

/// The signed-in access-denied surface, with a lifecycle explanation.
///
/// The sibling of `SrAccessDeniedView`, and deliberately the same card: the 40px
/// brand lockup, 32px below it a card at `p-6`, a 56px amber disc with a 1px
/// inset ring and a 28px shield, a 20px title, supporting paragraphs, and
/// full-width actions. Somebody moved from one to the other should feel they are
/// on the same screen with a better sentence, not on a different product.
///
/// ## Why this is a separate widget rather than parameters on the generic one
///
/// `SrAccessDeniedView` carries a standing prohibition in its own documentation:
/// do not add a `role` or `reason` parameter, because telling a caller *which*
/// check refused them turns a denial into an enumeration oracle. A `title` or
/// `body` override would be that parameter under another name.
///
/// So the generic view keeps its fixed, reason-free copy and gains only an
/// optional action, and the explained case lives here. The split is what lets a
/// reviewer answer "can the generic card ever say something specific?" by
/// reading one short widget.
///
/// ## The copy is supplied, but never free-form
///
/// [title], [body] and [closing] come from the const map in
/// `lifecycle_access_copy.dart`, keyed on an enum that carries no backend
/// string. Nothing reaches this widget from a response body, a query parameter,
/// an exception or a database message — there is no path by which it could.
class SrLifecycleNoticeView extends StatelessWidget {
  const SrLifecycleNoticeView({
    super.key,
    required this.title,
    required this.body,
    required this.closing,
    this.onCheckAccessAgain,
    this.onSignOut,
    this.checkingAccess = false,
    this.signingOut = false,
    this.signOutFailed = false,
  });

  /// The approved lifecycle title, e.g. "Retailer inactive".
  final String title;

  /// The approved lifecycle body.
  final String body;

  /// The Flutter-specific closing instruction.
  final String closing;

  /// Re-runs canonical portal-context resolution. When null the control is
  /// disabled — which is how the screen presents a resolution already in flight
  /// rather than hiding an affordance.
  final VoidCallback? onCheckAccessAgain;

  /// The sign-out action, preserved from the generic card.
  final VoidCallback? onSignOut;

  /// Whether a portal-context resolution is running.
  final bool checkingAccess;

  /// Whether a sign-out is in progress.
  final bool signingOut;

  /// Whether the last sign-out attempt failed, so a failed sign-out never leaves
  /// the user silently stuck here.
  final bool signOutFailed;

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
                  SrCard(
                    padding: const EdgeInsets.all(SrSpacing.xxl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // The same disc as the generic card. A different glyph
                        // or tone per lifecycle state would make the icon itself
                        // a state code.
                        const SrIconDisc(
                          icon: Icons.shield_outlined,
                          tone: SrTone.amber,
                          ringed: true,
                        ),
                        const SizedBox(height: SrSpacing.xl),
                        Text(
                          title,
                          style: SrTypography.screenTitle.copyWith(
                            color: sr.foreground,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: SrSpacing.sm),
                        Text(
                          body,
                          style: SrTypography.body.copyWith(
                            color: sr.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: SrSpacing.md),
                        Text(
                          closing,
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
                        SrButton(
                          label: 'Check access again',
                          loadingLabel: 'Checking access…',
                          fullWidth: true,
                          loading: checkingAccess,
                          onPressed: onCheckAccessAgain,
                        ),
                        const SizedBox(height: SrSpacing.md),
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
