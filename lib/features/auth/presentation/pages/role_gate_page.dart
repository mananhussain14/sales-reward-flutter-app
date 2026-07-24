import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/design/design.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/app_role.dart';
import '../bloc/role_session_bloc.dart';

/// The application's entry screen: "which experience is this caller in?".
///
/// When role resolution works this screen is transient — the router redirects
/// straight to the resolved role's landing path and the user never sees it.
///
/// **In this milestone it is not transient**, because
/// `public.get_my_portal_context()` does not exist. The role-flow map calls
/// shipping that RPC *"the single most important thing to fix before Flutter
/// ships"*, and lists it as the #1 phase-1 backend item. Until it exists this
/// screen renders the truth: the backend cannot answer.
///
/// ## The development-only role showcase
///
/// The preview controls below are a **development affordance**, not
/// authentication and not a role. They exist so the four shells can be reviewed
/// before the RPC lands, and they are built to be impossible to mistake for the
/// real thing:
///
/// * The screen states plainly that role resolution is not connected, and names
///   the missing function.
/// * Choosing a role emits [RoleSessionPreviewSelected], which marks the result
///   [RoleTrust.localPreview] — never [RoleTrust.serverResolved].
/// * Every shell built from a preview role carries a permanent, non-dismissible
///   banner saying so.
/// * Nothing that talks to Supabase ever reads the choice, and no repository
///   consults it.
/// * The controls appear **only** in the [NotImplementedFailure] branch. Once
///   the repository is implemented, a real resolution never reaches this branch,
///   so the showcase disappears on its own.
///
/// When `PortalContextRepository` is implemented, delete [_PreviewSection] along
/// with [RoleSessionPreviewSelected]. Nothing else here changes.
class RoleGatePage extends StatelessWidget {
  const RoleGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.sr.background,
      body: SafeArea(
        child: BlocBuilder<RoleSessionBloc, RoleSessionState>(
          builder: (BuildContext context, RoleSessionState state) {
            return switch (state) {
              RoleSessionInitial() || RoleSessionResolving() =>
                const SrLoadingView(rows: 2, label: 'Loading…'),

              // The router redirects out of this screen for both of these, so
              // they are only ever on screen for a frame.
              RoleSessionActive() ||
              RoleSessionNoAccess() => const SrLoadingView(rows: 2),

              RoleSessionFailed(:final Failure failure) => _GateFailure(
                failure: failure,
              ),
            };
          },
        ),
      ),
    );
  }
}

class _GateFailure extends StatelessWidget {
  const _GateFailure({required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final bool unimplemented = failure is NotImplementedFailure;

    return SrPageBody(
      maxWidth: SrSpacing.compactMaxWidth,
      children: <Widget>[
        const Center(child: SrBrandLockup(size: 44)),
        const SizedBox(height: SrSpacing.xxxl),

        if (unimplemented)
          SrCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SrIconDisc(
                  icon: Icons.construction_rounded,
                  tone: SrTone.amber,
                  size: 44,
                  ringed: true,
                ),
                const SizedBox(height: SrSpacing.lg),
                Text(
                  'Role resolution is not connected',
                  style: SrTypography.screenTitle.copyWith(
                    color: sr.foreground,
                  ),
                ),
                const SizedBox(height: SrSpacing.sm),
                Text(
                  'The backend function that decides which experience an '
                  'account belongs in — '
                  '${(failure as NotImplementedFailure).capability} — has not '
                  'been built. Until it exists this app cannot know your role, '
                  'and nothing below reflects any real permission.',
                  style: SrTypography.body.copyWith(color: sr.textSecondary),
                ),
              ],
            ),
          )
        else
          SrFailureView(
            failure: failure,
            onRetry: () => context.read<RoleSessionBloc>().add(
              const RoleSessionResolveRequested(),
            ),
          ),

        if (unimplemented) ...<Widget>[
          const SizedBox(height: SrSpacing.xxl),
          const _PreviewSection(),
        ],
      ],
    );
  }
}

/// The development-only role showcase. See the note on [RoleGatePage].
class _PreviewSection extends StatelessWidget {
  const _PreviewSection();

  @override
  Widget build(BuildContext context) {
    return SrSectionCard(
      title: 'Preview a role interface',
      description:
          'A development-only showcase. It opens a shell so its layout and '
          'theme can be reviewed. It grants no access, signs nobody in, and '
          'every screen stays disconnected from Supabase.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final AppRole role in AppRole.values) ...<Widget>[
            SrButton(
              label: role.displayName,
              variant: SrButtonVariant.outline,
              icon: Icons.arrow_forward_rounded,
              fullWidth: true,
              onPressed: () => context.read<RoleSessionBloc>().add(
                RoleSessionPreviewSelected(role),
              ),
            ),
            if (role != AppRole.values.last)
              const SizedBox(height: SrSpacing.md),
          ],
        ],
      ),
    );
  }
}
