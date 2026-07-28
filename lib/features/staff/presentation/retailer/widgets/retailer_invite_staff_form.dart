import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/retailer_assignable_shop.dart';
import '../../../domain/entities/retailer_staff_invitation_request.dart';
import '../../../domain/entities/retailer_staff_invitation_role.dart';
import '../cubit/retailer_invite_staff_cubit.dart';
import 'retailer_invite_staff_copy.dart';

/// The Owner's Invite Staff form.
///
/// ## Where it is rendered, and why that is not an authorization decision
///
/// Only inside the Retailer Owner shell, which is the only shell that provides
/// [RetailerInviteStaffCubit]. That mirrors the invitation history exactly: both
/// contracts resolve through the permission a Retailer Manager does not hold, so
/// a Manager pressing send would receive a refusal and a Manager *seeing* the
/// form would be shown a dead end.
///
/// The backend still decides. `reserve_retailer_staff_invitation()` re-derives
/// the Retailer from `auth.uid()`, re-checks the permission, and validates every
/// submitted shop against that Retailer — and the Edge Function re-applies the
/// whole request contract before any of that. Hiding a form removes the
/// accident; only those checks remove the capability.
///
/// ## What the form can express, exhaustively
///
/// Two names, an email address, one of two roles, and a set of shops chosen from
/// the list the backend returned. There is no organization selector, no
/// "invite as Owner", no permission picker, no expiry control, no custom message
/// and no resend or revoke control — none of those is a parameter of the
/// deployed contract, and a control for one would be a promise nothing can keep.
///
/// ## Accessibility
///
/// Every control carries its own visible label; requirement is marked with a
/// visible asterisk rather than by colour. A validation message replaces the
/// field's hint **below** the control, so it never displaces what is being
/// typed. The role buttons and the shop checkboxes are real focusable controls
/// with `selected` / `checked` semantics, so a keyboard or a screen reader can
/// work the whole form, and the form-level notice is a live region.
class RetailerInviteStaffForm extends StatefulWidget {
  const RetailerInviteStaffForm({super.key, required this.onRefreshHistory});

  /// A **read**: re-reads the invitation history. Offered only when a send
  /// landed and the history beside it did not reload — never as a way to retry
  /// the send.
  final VoidCallback onRefreshHistory;

  @override
  State<RetailerInviteStaffForm> createState() =>
      _RetailerInviteStaffFormState();
}

class _RetailerInviteStaffFormState extends State<RetailerInviteStaffForm> {
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _email = TextEditingController();

  final FocusNode _firstNameFocus = FocusNode(debugLabel: 'inviteFirstName');
  final FocusNode _lastNameFocus = FocusNode(debugLabel: 'inviteLastName');
  final FocusNode _emailFocus = FocusNode(debugLabel: 'inviteEmail');

  /// The last reset the cubit performed, so an emptied form is observable as a
  /// change rather than inferred from values that may already have been empty.
  int _appliedRevision = 0;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  /// Follows the cubit only when it has genuinely reset the form.
  ///
  /// Assigning on every rebuild would move the caret to the end on every
  /// keystroke; never assigning would leave a cleared form still full of the
  /// previous invitation's values — including, after a session change, the
  /// previous person's colleague's name and address.
  void _syncControllers(RetailerInviteStaffState state) {
    if (state.formRevision == _appliedRevision) {
      return;
    }
    _appliedRevision = state.formRevision;
    _firstName.text = state.firstName;
    _lastName.text = state.lastName;
    _email.text = state.email;
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RetailerInviteStaffCubit, RetailerInviteStaffState>(
      listenWhen:
          (
            RetailerInviteStaffState previous,
            RetailerInviteStaffState current,
          ) => previous.formRevision != current.formRevision,
      listener: (BuildContext context, RetailerInviteStaffState state) {
        _syncControllers(state);
      },
      builder: (BuildContext context, RetailerInviteStaffState state) {
        final RetailerInviteStaffCubit cubit = context
            .read<RetailerInviteStaffCubit>();
        // Also applied here, so a state restored before the first listener runs
        // — a rebuild after a session change, say — is not missed.
        _syncControllers(state);

        return SrCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SrSectionHeader(
                title: RetailerInviteStaffCopy.title,
                description: RetailerInviteStaffCopy.description,
              ),
              const SizedBox(height: SrSpacing.xl),

              if (state.notice != null) ...<Widget>[
                _Notice(
                  state: state,
                  onRefreshHistory: widget.onRefreshHistory,
                ),
                const SizedBox(height: SrSpacing.xl),
              ],

              _NameFields(
                state: state,
                cubit: cubit,
                firstName: _firstName,
                lastName: _lastName,
                firstNameFocus: _firstNameFocus,
                lastNameFocus: _lastNameFocus,
              ),
              const SizedBox(height: SrSpacing.xl),

              SrTextField(
                label: RetailerInviteStaffCopy.emailLabel,
                controller: _email,
                focusNode: _emailFocus,
                required: true,
                enabled: !state.isSubmitting,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.email],
                maxLength: maxInvitationEmailLength,
                hint: RetailerInviteStaffCopy.emailHint,
                errorText: _messageFor(
                  state,
                  RetailerStaffInvitationField.email,
                ),
                onChanged: cubit.emailChanged,
              ),
              const SizedBox(height: SrSpacing.xl),

              _RoleField(state: state, cubit: cubit),

              if (state.showsShopPicker) ...<Widget>[
                const SizedBox(height: SrSpacing.xl),
                _ShopsField(state: state, cubit: cubit),
              ],

              const SizedBox(height: SrSpacing.xxl),
              Semantics(
                button: true,
                enabled: !state.isSubmitting,
                label: RetailerInviteStaffCopy.submit,
                child: SrButton(
                  label: RetailerInviteStaffCopy.submit,
                  loadingLabel: RetailerInviteStaffCopy.submitting,
                  size: SrButtonSize.lg,
                  icon: Icons.send_rounded,
                  fullWidth: true,
                  loading: state.isSubmitting,
                  // Disabled *and* guarded in the cubit. The button is the
                  // courtesy; the cubit's own refusal is what makes a queued
                  // second tap impossible to turn into a second invitation.
                  onPressed: state.isSubmitting ? null : cubit.submit,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String? _messageFor(
    RetailerInviteStaffState state,
    RetailerStaffInvitationField field,
  ) {
    final RetailerStaffInvitationProblem? problem = state.problemFor(field);
    return problem == null
        ? null
        : RetailerInviteStaffCopy.fieldMessage(field, problem);
  }
}

/// First and last name, side by side once there is room for two columns.
class _NameFields extends StatelessWidget {
  const _NameFields({
    required this.state,
    required this.cubit,
    required this.firstName,
    required this.lastName,
    required this.firstNameFocus,
    required this.lastNameFocus,
  });

  final RetailerInviteStaffState state;
  final RetailerInviteStaffCubit cubit;
  final TextEditingController firstName;
  final TextEditingController lastName;
  final FocusNode firstNameFocus;
  final FocusNode lastNameFocus;

  @override
  Widget build(BuildContext context) {
    final Widget first = SrTextField(
      label: RetailerInviteStaffCopy.firstNameLabel,
      controller: firstName,
      focusNode: firstNameFocus,
      required: true,
      enabled: !state.isSubmitting,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
      autofillHints: const <String>[AutofillHints.givenName],
      maxLength: maxInvitationNameLength,
      errorText: _RetailerInviteStaffFormState._messageFor(
        state,
        RetailerStaffInvitationField.firstName,
      ),
      onChanged: cubit.firstNameChanged,
    );

    final Widget last = SrTextField(
      label: RetailerInviteStaffCopy.lastNameLabel,
      controller: lastName,
      focusNode: lastNameFocus,
      required: true,
      enabled: !state.isSubmitting,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
      autofillHints: const <String>[AutofillHints.familyName],
      maxLength: maxInvitationNameLength,
      errorText: _RetailerInviteStaffFormState._messageFor(
        state,
        RetailerStaffInvitationField.lastName,
      ),
      onChanged: cubit.lastNameChanged,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // One column on a phone. Two side by side only once each half is still
        // a usable width, which is what keeps a long validation message from
        // wrapping into a wall.
        if (constraints.maxWidth < SrSpacing.breakpointSm) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              first,
              const SizedBox(height: SrSpacing.xl),
              last,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: first),
            const SizedBox(width: SrSpacing.lg),
            Expanded(child: last),
          ],
        );
      },
    );
  }
}

/// The role choice: two options, and no default.
///
/// Rendered as two buttons rather than a dropdown because there are exactly two
/// and both need their consequence visible — one of them changes what else the
/// form asks for.
class _RoleField extends StatelessWidget {
  const _RoleField({required this.state, required this.cubit});

  final RetailerInviteStaffState state;
  final RetailerInviteStaffCubit cubit;

  @override
  Widget build(BuildContext context) {
    return SrField(
      label: RetailerInviteStaffCopy.roleLabel,
      required: true,
      hint: RetailerInviteStaffCopy.roleHint,
      errorText: _RetailerInviteStaffFormState._messageFor(
        state,
        RetailerStaffInvitationField.role,
      ),
      child: Wrap(
        spacing: SrSpacing.md,
        runSpacing: SrSpacing.md,
        children: <Widget>[
          for (final RetailerStaffInvitationRole role
              in RetailerStaffInvitationRole.values)
            Semantics(
              button: true,
              selected: state.role == role,
              enabled: !state.isSubmitting,
              // The user-facing name, never the wire token: `SALES_STAFF` on a
              // screen would be an internal identifier leaking into the UI.
              label: role.label,
              child: SrButton(
                label: role.label,
                variant: state.role == role
                    ? SrButtonVariant.primary
                    : SrButtonVariant.outline,
                icon: state.role == role ? Icons.check_rounded : null,
                onPressed: state.isSubmitting
                    ? null
                    : () => cubit.roleChanged(role),
              ),
            ),
        ],
      ),
    );
  }
}

/// The shop picker. Sales Staff only, and only ever built from backend rows.
class _ShopsField extends StatelessWidget {
  const _ShopsField({required this.state, required this.cubit});

  final RetailerInviteStaffState state;
  final RetailerInviteStaffCubit cubit;

  @override
  Widget build(BuildContext context) {
    return SrField(
      label: RetailerInviteStaffCopy.shopsLabel,
      required: true,
      hint: RetailerInviteStaffCopy.shopsHint,
      errorText: _RetailerInviteStaffFormState._messageFor(
        state,
        RetailerStaffInvitationField.shops,
      ),
      child: _ShopOptions(state: state, cubit: cubit),
    );
  }
}

class _ShopOptions extends StatelessWidget {
  const _ShopOptions({required this.state, required this.cubit});

  final RetailerInviteStaffState state;
  final RetailerInviteStaffCubit cubit;

  @override
  Widget build(BuildContext context) {
    if (state.isShopsLoading) {
      // An inline row rather than the full-screen skeleton: what is loading is
      // one control inside a form, and replacing the whole card would throw away
      // everything already typed above it.
      return Semantics(
        liveRegion: true,
        child: Row(
          children: <Widget>[
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.sr.brand,
              ),
            ),
            const SizedBox(width: SrSpacing.md),
            // Flexible, so the sentence wraps on a narrow phone instead of
            // overflowing the row it shares with the spinner.
            Flexible(
              child: Text(
                RetailerInviteStaffCopy.shopsLoading,
                style: SrTypography.body.copyWith(
                  color: context.sr.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (state.hasShopsFailed) {
      // A refusal is `42501` and arrives here, never as an empty picker: the
      // deployed function raises rather than returning nothing precisely so an
      // Owner is never told their Retailer is empty when they were refused.
      return SrEmptyState(
        icon: Icons.storefront_outlined,
        tone: SrTone.amber,
        title: RetailerInviteStaffCopy.shopsUnavailableTitle,
        description: RetailerInviteStaffCopy.shopsProblemBody(
          state.shopsProblem!,
        ),
        action: Semantics(
          button: true,
          label: RetailerInviteStaffCopy.shopsRetry,
          child: SrButton(
            label: RetailerInviteStaffCopy.shopsRetry,
            variant: SrButtonVariant.outline,
            icon: Icons.refresh_rounded,
            onPressed: state.isSubmitting ? null : cubit.loadAssignableShops,
          ),
        ),
      );
    }

    if (state.isShopsEmpty) {
      return const SrEmptyState(
        icon: Icons.storefront_outlined,
        tone: SrTone.slate,
        title: RetailerInviteStaffCopy.shopsEmptyTitle,
        description: RetailerInviteStaffCopy.shopsEmptyBody,
      );
    }

    final List<RetailerAssignableShop> shops =
        state.shops ?? const <RetailerAssignableShop>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final RetailerAssignableShop shop in shops)
          Padding(
            padding: const EdgeInsets.only(bottom: SrSpacing.sm),
            child: _ShopOption(
              shop: shop,
              selected: state.selectedShopIds.contains(shop.id),
              enabled: !state.isSubmitting,
              // Keyed on the id the backend returned — never on the shop's name
              // and never on its position in this list.
              onToggle: () => cubit.shopSelectionToggled(shop.id),
            ),
          ),
      ],
    );
  }
}

/// One tickable shop.
///
/// The whole row is the target, so it clears the 44pt minimum without the
/// checkbox itself having to. The id is never rendered — only the name, and the
/// code and city when they were recorded.
class _ShopOption extends StatelessWidget {
  const _ShopOption({
    required this.shop,
    required this.selected,
    required this.enabled,
    required this.onToggle,
  });

  final RetailerAssignableShop shop;
  final bool selected;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Semantics(
      container: true,
      checked: selected,
      enabled: enabled,
      // The name plus whatever else was recorded. Never the id.
      label: shop.displayLabel,
      onTap: enabled ? onToggle : null,
      // One node for the row, so a screen reader announces "Northwind Marina,
      // checked" rather than an unlabelled checkbox beside two loose strings.
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onToggle : null,
            borderRadius: BorderRadius.circular(SrRadii.control),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(
                horizontal: SrSpacing.md,
                vertical: SrSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: selected ? sr.brandSoft : sr.inputFill,
                borderRadius: BorderRadius.circular(SrRadii.control),
                border: Border.all(color: selected ? sr.brand : sr.inputBorder),
              ),
              child: Row(
                children: <Widget>[
                  Checkbox(
                    value: selected,
                    onChanged: enabled ? (_) => onToggle() : null,
                    activeColor: sr.brand,
                  ),
                  const SizedBox(width: SrSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          shop.name,
                          style: SrTypography.body.copyWith(
                            color: sr.foreground,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (shop.code != null || shop.city != null)
                          Text(
                            <String>[
                              if (shop.code != null) shop.code!,
                              if (shop.city != null) shop.city!,
                            ].join(' · '),
                            style: SrTypography.caption.copyWith(
                              color: sr.textMuted,
                            ),
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

/// The form-level result, and — when it applies — the note that the history
/// beside it is stale.
class _Notice extends StatelessWidget {
  const _Notice({required this.state, required this.onRefreshHistory});

  final RetailerInviteStaffState state;
  final VoidCallback onRefreshHistory;

  @override
  Widget build(BuildContext context) {
    final RetailerInviteStaffNotice notice = state.notice!;

    final SrAlertTone tone = notice.isSuccess
        ? SrAlertTone.success
        : (notice.isUnresolved ? SrAlertTone.warning : SrAlertTone.error);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SrAlert(
          tone: tone,
          title: RetailerInviteStaffCopy.noticeTitle(notice),
          message: RetailerInviteStaffCopy.noticeBody(notice),
        ),
        if (state.historyRereadFailed) ...<Widget>[
          const SizedBox(height: SrSpacing.md),
          const SrAlert(
            tone: SrAlertTone.warning,
            title: RetailerInviteStaffCopy.historyRereadFailedTitle,
            message: RetailerInviteStaffCopy.historyRereadFailedBody,
          ),
          const SizedBox(height: SrSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              button: true,
              label: RetailerInviteStaffCopy.refreshHistory,
              child: SrButton(
                label: RetailerInviteStaffCopy.refreshHistory,
                variant: SrButtonVariant.outline,
                icon: Icons.refresh_rounded,
                // A read, and only a read. Nothing on this screen re-sends an
                // invitation without a person choosing to.
                onPressed: onRefreshHistory,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
