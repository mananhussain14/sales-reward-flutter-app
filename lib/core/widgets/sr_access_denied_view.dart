import 'package:flutter/material.dart';

import '../design/design.dart';
import 'sr_brand_mark.dart';
import 'sr_button.dart';
import 'sr_card.dart';

/// The shared, role-neutral "Access denied" screen, translated from
/// `components/ui/access-denied-card.tsx`.
///
/// Every role's shell routes here for a denial, so the wording, the shield
/// motif, and the only-way-out sign-out control stay in one place.
///
/// **The copy is fixed and neutral on purpose.** It names no role, no
/// organization, and no failing condition, because every caller must be
/// indistinguishable to a signed-in but unauthorized — possibly hostile —
/// account. Do not add a `role` or `reason` parameter to this widget: telling a
/// caller *which* check refused them turns a denial into an enumeration oracle,
/// which is precisely what the backend's overloaded `42501` exists to prevent.
///
/// This widget is presentation and decides nothing. The route guard that sends a
/// user here is a convenience; the real refusal happens in SQL, on every call.
class SrAccessDeniedView extends StatelessWidget {
  const SrAccessDeniedView({super.key, this.onSignOut});

  /// Wired to a real sign-out once authentication is implemented. When null the
  /// control is disabled rather than hidden, so the screen's shape does not
  /// change between this milestone and the next.
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SrColors.appBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: SrSpacing.lg,
              vertical: SrSpacing.huge,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Mirrors the login lockup so every entry point reads as one
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
                          style: SrTypography.screenTitle,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: SrSpacing.sm),
                        Text(
                          'You are signed in, but this account does not have '
                          'access to this page.',
                          style: SrTypography.bodyMuted,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: SrSpacing.md),
                        Text(
                          'Use the navigation available to your account, or '
                          'sign in with a different account.',
                          style: SrTypography.bodyMuted,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: SrSpacing.xxl),
                        SrButton(
                          label: 'Sign out',
                          variant: SrButtonVariant.outline,
                          fullWidth: true,
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
