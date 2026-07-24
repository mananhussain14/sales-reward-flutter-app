import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/design/design.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/app_role.dart';
import '../bloc/role_session_bloc.dart';

/// The application's entry screen: "which experience is this caller in?".
///
/// When role resolution works, this screen is transient — the router redirects
/// straight to the resolved role's landing path and the user never sees it.
///
/// **In this milestone it is not transient**, because
/// `public.get_my_portal_context()` does not exist. So it renders the truth: the
/// backend cannot answer, and the four shells below can only be *previewed*.
///
/// The preview controls are the one deliberate compromise in this build, and
/// they are built to be impossible to mistake for the real thing:
///
/// * The screen states plainly that role resolution is not connected.
/// * Choosing a role emits [RoleSessionPreviewSelected], which marks the result
///   [RoleTrust.localPreview].
/// * Every shell built from a preview role shows a permanent, non-dismissible
///   banner saying so.
/// * No repository, and nothing that talks to Supabase, ever reads the choice.
///
/// When [PortalContextRepository] is implemented, the preview section should be
/// deleted along with [RoleSessionPreviewSelected]. Nothing else here changes.
class RoleGatePage extends StatelessWidget {
  const RoleGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SrColors.appBackground,
      body: SafeArea(
        child: BlocBuilder<RoleSessionBloc, RoleSessionState>(
          builder: (BuildContext context, RoleSessionState state) {
            return switch (state) {
              RoleSessionInitial() || RoleSessionResolving() =>
                const SrLoadingView(message: 'Checking your access…'),

              // The router redirects out of this screen for these two, so they
              // are only ever seen for a frame.
              RoleSessionActive() => const SrLoadingView(),
              RoleSessionNoAccess() => const SrLoadingView(),

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
    final bool unimplemented = failure is NotImplementedFailure;

    return SrPageBody(
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
                  style: SrTypography.screenTitle,
                ),
                const SizedBox(height: SrSpacing.sm),
                Text(
                  'The backend function that decides which experience an '
                  'account belongs in — '
                  '${(failure as NotImplementedFailure).capability} — has not '
                  'been built. Until it exists this app cannot know your role, '
                  'and nothing below reflects any real permission.',
                  style: SrTypography.bodyMuted,
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
          SrSectionCard(
            title: 'Preview a role interface',
            description:
                'Opens a shell so its layout and theme can be reviewed. This '
                'grants no access, and every screen stays disconnected from '
                'Supabase.',
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
          ),
        ],
      ],
    );
  }
}
