import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/design/design.dart';
import '../../../core/widgets/widgets.dart';
import '../../../features/auth/domain/entities/app_role.dart';
import '../../theme/cubit/theme_cubit.dart';

/// The account sheet, opened from the app-bar avatar.
///
/// ## Why a sheet and not a screen
///
/// **The web has no profile screen** — no route, no component, and no RPC that
/// returns a user their own profile (§ 5.13, decision **D-5**). Building one
/// would require a new backend read and a decision about what is editable.
///
/// The handoff's recommendation is therefore *"an account sheet reachable from
/// the avatar, containing exactly what the app bar already shows plus sign-out —
/// inventing nothing."* That is what this is, plus the appearance control, which
/// is a genuinely device-local preference and needs no backend at all.
///
/// Nothing here is fabricated: because authentication is not implemented, the
/// identity block says so rather than showing a placeholder name, and the role
/// row states its **provenance** rather than presenting a preview selection as
/// if the backend had returned it.
class AccountSheet extends StatelessWidget {
  const AccountSheet({super.key, required this.role, required this.portalName});

  final ResolvedRole role;
  final String portalName;

  /// Opens the sheet. A bottom sheet rather than a dialog: it is the mobile form
  /// of a desktop popover, and it keeps the action within thumb reach.
  static Future<void> show(
    BuildContext context, {
    required ResolvedRole role,
    required String portalName,
  }) {
    final ThemeCubit themeCubit = context.read<ThemeCubit>();

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => BlocProvider<ThemeCubit>.value(
        value: themeCubit,
        child: AccountSheet(role: role, portalName: portalName),
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
                const SrInitialsAvatar(name: null),
                const SizedBox(width: SrSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'Not signed in',
                        style: SrTypography.label.copyWith(
                          color: sr.foreground,
                        ),
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
                // The role in effect, and — crucially — where it came from. A
                // locally previewed role must never read as a resolved one.
                SrBadge(
                  label: role.isServerResolved
                      ? role.role.displayName
                      : '${role.role.displayName} · preview',
                  tone: role.isServerResolved ? SrTone.emerald : SrTone.amber,
                ),
              ],
            ),
            const SizedBox(height: SrSpacing.lg),

            // Honest about what this build is. Authentication is not
            // implemented, so there is no identity to show.
            const SrAlert(
              tone: SrAlertTone.info,
              message:
                  'Sign-in is not built yet, so no account details are '
                  'available.',
            ),

            const SizedBox(height: SrSpacing.xxl),
            Text(
              'APPEARANCE',
              style: SrTypography.eyebrow.copyWith(color: sr.brand),
            ),
            const SizedBox(height: SrSpacing.md),
            const _ThemeModeSelector(),

            const SizedBox(height: SrSpacing.xxl),
            SrButton(
              label: 'Sign out',
              variant: SrButtonVariant.outline,
              fullWidth: true,
              // No handler: there is no session to end.
              onPressed: null,
            ),
          ],
        ),
      ),
    );
  }
}

/// The light / dark / system control.
///
/// Three explicit choices rather than a two-state switch, because "follow the
/// device" is a distinct and default-correct answer that a toggle cannot
/// express.
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
