import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../../../auth/presentation/bloc/session_bloc.dart';
import '../../../domain/entities/vendor_administrator_profile.dart';
import '../cubit/vendor_profile_cubit.dart';
import '../widgets/vendor_profile_administrator_card.dart';
import '../widgets/vendor_profile_company_card.dart';
import '../widgets/vendor_profile_copy.dart';

/// The Vendor Super Admin's company and administrator profile.
///
/// ## Two trusted sources, composed here and nowhere else
///
/// * The **Vendor organization name** comes from the Session / PortalContext the
///   application already holds, resolved by `get_my_portal_context()`.
/// * The **administrator display name and active role names** come from
///   `public.get_my_vendor_profile()` — one call, zero arguments.
///
/// Nothing is sent from either to the other. The profile function takes no
/// arguments, so it could not accept an organization id even if one were offered;
/// and the organization name is never queried from `organizations` directly, nor
/// looked for in the profile response, which deliberately does not carry it.
/// Both contracts derive their Vendor from `auth.uid()` through the same resolver
/// with the same lowest-organization-id tie-break, so the company named here and
/// the roles listed here describe the same organization by construction rather
/// than by coincidence.
///
/// ## Read-only, and it does not pretend otherwise
///
/// There is no Edit button, no disabled input, no placeholder dash and no "coming
/// soon" row. There is no legal name, registration identifier, tax identifier,
/// website, business email, business phone or address field, because **no such
/// column exists anywhere in the schema** — the company section says so once, in
/// neutral product language that does not read as a failure. There is no logo or
/// avatar upload, no password or security screen, no organization switcher and no
/// write action of any kind: the backend function is `STABLE` and this screen has
/// nothing to call that is not.
///
/// ## No status, and none inferred
///
/// A caller who receives a row **is** an active administrator of an active
/// Vendor — those are conditions of the read, not output — so the contract
/// returns no profile status, membership status or organization status, and
/// nothing here builds a badge from their absence. A caller who is not receives a
/// generic denial and has no profile to render at all.
///
/// ## Refreshing
///
/// Two affordances for one action: pull-to-refresh, which is what a phone user
/// reaches for, and a header button, which is what a browser user reaches for and
/// what a keyboard or screen-reader user can actually operate. Both call the same
/// method, and that method ignores a second call while a read is in flight — so a
/// repeated tap cannot produce simultaneous requests.
///
/// A refresh **replaces the whole profile atomically** and never merges a field.
/// A refresh that fails keeps the profile and says so above it, because it is
/// still the last thing the backend actually said. The organization name is not
/// refreshed from here at all: it belongs to the session, and it changes when the
/// effective session identity changes.
class VendorCompanyProfilePage extends StatelessWidget {
  const VendorCompanyProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    // The trusted organization name, from the session the application already
    // resolved. Read through `vendor` directly rather than through a portal-kind
    // switch: the block is null unless the backend resolved a Vendor for this
    // caller, so there is no branch here that could caption this page with a
    // Retailer's name.
    //
    // `watch` rather than `read` so a re-resolution updates the company card in
    // the same frame the shell clears the administrator profile.
    final SessionState session = context.watch<SessionBloc>().state;
    final String? organizationName = session is SessionActive
        ? session.portalContext.vendor?.organizationName
        : null;

    return BlocBuilder<VendorProfileCubit, VendorProfileState>(
      builder: (BuildContext context, VendorProfileState state) {
        final VendorProfileCubit cubit = context.read<VendorProfileCubit>();

        // The skeleton stands in only for the *first* read. A refresh over a
        // profile already on screen keeps it.
        if (state.isFirstLoad) {
          return const SrLoadingView(label: VendorProfileCopy.loading);
        }

        return RefreshIndicator(
          onRefresh: cubit.refresh,
          child: SrPageBody(
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              Semantics(
                header: true,
                child: SrPageHeader(
                  eyebrow: PortalKind.vendorSuperAdmin.displayName,
                  title: VendorProfileCopy.title,
                  description: VendorProfileCopy.description,
                  actions: <Widget>[
                    Semantics(
                      button: true,
                      label: VendorProfileCopy.refresh,
                      child: SrButton(
                        label: VendorProfileCopy.refresh,
                        variant: SrButtonVariant.outline,
                        icon: Icons.refresh_rounded,
                        loading: state.isRefreshing,
                        loadingLabel: VendorProfileCopy.refreshing,
                        // Disabled while a read is in flight, so a repeated press
                        // cannot issue two requests for the same profile.
                        onPressed: state.isRefreshing ? null : cubit.refresh,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SrSpacing.xxl),

              // A refresh that failed over a profile already on screen says so
              // without throwing it away. Non-blocking: the cards below stay
              // exactly as they were, and the Refresh button remains the retry.
              if (state.isStale) ...<Widget>[
                const SrAlert(
                  tone: SrAlertTone.warning,
                  title: VendorProfileCopy.staleTitle,
                  message: VendorProfileCopy.staleBody,
                ),
                const SizedBox(height: SrSpacing.xxl),
              ],

              // Stacked on a phone, paired once there is room for two columns —
              // the same responsive rule every other card surface in the product
              // uses, so company and administrator stay visually distinct without
              // a bespoke layout.
              SrCardGrid(
                children: <Widget>[
                  if (organizationName != null)
                    VendorProfileCompanyCard(
                      organizationName: organizationName,
                    ),
                  _AdministratorSection(state: state, cubit: cubit),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The administrator half: the profile, or the reason there is none.
class _AdministratorSection extends StatelessWidget {
  const _AdministratorSection({required this.state, required this.cubit});

  final VendorProfileState state;
  final VendorProfileCubit cubit;

  @override
  Widget build(BuildContext context) {
    // A failure with nothing loaded is the whole administrator section.
    // `SrFailureView` decides the wording and whether a retry is offered, per
    // discriminant — a denial never offers one, an outage always does, and
    // neither ever names a permission code or a backend object.
    //
    // Critically, no card renders here. A denied caller must never be shown a
    // blank name over an empty role list: "you may not read this profile" and
    // "you have no name and no roles" are opposite claims, and the backend
    // deliberately refuses to say which gate stopped them.
    if (state.hasFailedFirstRead) {
      return SrFailureView(failure: state.failure!, onRetry: cubit.load);
    }

    final VendorAdministratorProfile? profile = state.profile;
    if (profile == null) {
      // Unreachable: `isFirstLoad` covers "nothing read yet" above and
      // `hasFailedFirstRead` covers "the read failed". Kept as a shrink rather
      // than an assertion so an unforeseen ordering renders nothing at all —
      // never a placeholder identity.
      return const SizedBox.shrink();
    }

    return VendorProfileAdministratorCard(profile: profile);
  }
}
