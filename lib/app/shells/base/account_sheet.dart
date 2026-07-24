import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/design/design.dart';
import '../../../core/widgets/widgets.dart';
import '../../../features/auth/domain/entities/portal_context.dart';
import '../../../features/auth/domain/repositories/auth_repository.dart';
import '../../../features/auth/presentation/cubit/logout_cubit.dart';
import '../../theme/cubit/theme_cubit.dart';

/// The account sheet, opened from the app-bar avatar.
///
/// ## Why a sheet and not a screen
///
/// **The web has no profile screen** — no route, no component, and no RPC that
/// returns a user their own profile (§ 5.13, decision **D-5**). The handoff's
/// recommendation is an account sheet reachable from the avatar, containing
/// exactly what the app bar already knows plus sign-out — inventing nothing.
///
/// This sheet shows the signed-in email, the resolved role, the appearance
/// control (a device-local preference needing no backend), and sign-out. It
/// fabricates no field the backend did not provide.
class AccountSheet extends StatelessWidget {
  const AccountSheet({
    super.key,
    required this.portalContext,
    required this.portalName,
    this.email,
  });

  final PortalContext portalContext;
  final String portalName;

  /// The signed-in email, or null. Passed in rather than read here so the sheet
  /// stays a pure presentation widget.
  final String? email;

  /// Opens the sheet. A bottom sheet rather than a dialog: the mobile form of a
  /// desktop popover, keeping the action within thumb reach.
  ///
  /// The two BLoCs the sheet needs — [ThemeCubit] for appearance, and a fresh
  /// [LogoutCubit] over the [AuthRepository] — are provided into the modal
  /// route, which sits outside the calling widget's provider scope.
  static Future<void> show(
    BuildContext context, {
    required PortalContext portalContext,
    required String portalName,
  }) {
    final ThemeCubit themeCubit = context.read<ThemeCubit>();
    final AuthRepository authRepository = context.read<AuthRepository>();

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => MultiBlocProvider(
        providers: <BlocProvider<dynamic>>[
          BlocProvider<ThemeCubit>.value(value: themeCubit),
          BlocProvider<LogoutCubit>(
            create: (_) => LogoutCubit(authRepository: authRepository),
          ),
        ],
        child: AccountSheet(
          email: authRepository.currentUser?.email,
          portalContext: portalContext,
          portalName: portalName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SrSpacing.xl,
          0,
          SrSpacing.xl,
          SrSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                SrInitialsAvatar(name: email),
                const SizedBox(width: SrSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        email ?? 'Signed in',
                        style: SrTypography.label.copyWith(
                          color: sr.foreground,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: SrSpacing.xxs),
                      Text(
                        portalName,
                        style: SrTypography.caption.copyWith(
                          color: sr.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // The resolved role, from the backend. Presentation only.
                SrBadge(
                  label: portalContext.portalKind.displayName,
                  tone: SrTone.emerald,
                ),
              ],
            ),

            const SizedBox(height: SrSpacing.xxl),
            Text(
              'APPEARANCE',
              style: SrTypography.eyebrow.copyWith(color: sr.brand),
            ),
            const SizedBox(height: SrSpacing.md),
            const _ThemeModeSelector(),

            const SizedBox(height: SrSpacing.xxl),
            const _SignOutSection(),
          ],
        ),
      ),
    );
  }
}

/// The sign-out control and its failure state.
///
/// On success nothing is rendered further: the auth stream carries the change
/// to `SessionBloc`, the router replaces this whole shell with the login screen,
/// and this widget is gone before any "signed out" state could appear. A
/// failure is surfaced inline — the user is still legitimately signed in, and a
/// silent failure that left them staring at an authenticated screen would be
/// worse than saying so.
class _SignOutSection extends StatelessWidget {
  const _SignOutSection();

  Future<void> _confirmAndSignOut(BuildContext context) async {
    final LogoutCubit cubit = context.read<LogoutCubit>();

    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('Sign out?'),
            content: const Text(
              'You will need to sign in again to use SalesReward.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmed && context.mounted) {
      await cubit.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LogoutCubit, LogoutStatus>(
      builder: (BuildContext context, LogoutStatus status) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (status == LogoutStatus.failed) ...<Widget>[
              const SrAlert(
                tone: SrAlertTone.error,
                message:
                    'Could not sign out. Check your connection and try again.',
              ),
              const SizedBox(height: SrSpacing.md),
            ],
            SrButton(
              label: 'Sign out',
              loadingLabel: 'Signing out…',
              variant: SrButtonVariant.outline,
              fullWidth: true,
              loading: status == LogoutStatus.inProgress,
              onPressed: status == LogoutStatus.inProgress
                  ? null
                  : () => _confirmAndSignOut(context),
            ),
          ],
        );
      },
    );
  }
}

/// The light / dark / system control.
///
/// Three explicit choices rather than a two-state switch, because "follow the
/// device" is a distinct and default-correct answer a toggle cannot express.
class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector();

  static const List<(ThemeMode, String, IconData)> _options =
      <(ThemeMode, String, IconData)>[
        (ThemeMode.system, 'System', Icons.brightness_auto_outlined),
        (ThemeMode.light, 'Light', Icons.light_mode_outlined),
        (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
      ];

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return BlocBuilder<ThemeCubit, ThemeMode>(
      builder: (BuildContext context, ThemeMode mode) {
        return Row(
          children: <Widget>[
            for (final (ThemeMode value, String label, IconData icon)
                in _options) ...<Widget>[
              if (value != _options.first.$1)
                const SizedBox(width: SrSpacing.sm),
              Expanded(
                child: _ThemeOption(
                  label: label,
                  icon: icon,
                  selected: mode == value,
                  onTap: () => context.read<ThemeCubit>().select(value),
                  sr: sr,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.sr,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final SrColorScheme sr;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? sr.navActiveFill : sr.surface,
        borderRadius: BorderRadius.circular(SrRadii.control),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SrRadii.control),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: SrSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SrRadii.control),
              border: Border.all(
                color: selected ? sr.navActiveRail : sr.borderStrong,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  icon,
                  size: 20,
                  color: selected ? sr.navActiveLabel : sr.textSecondary,
                ),
                const SizedBox(height: SrSpacing.xs),
                Text(
                  label,
                  style: SrTypography.caption.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? sr.navActiveLabel : sr.textSecondary,
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
