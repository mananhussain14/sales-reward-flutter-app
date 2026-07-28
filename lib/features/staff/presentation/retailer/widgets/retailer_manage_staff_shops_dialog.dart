import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/retailer_assignable_shop.dart';
import '../../../domain/entities/retailer_staff_member.dart';
import '../../../domain/entities/retailer_staff_shop_assignment.dart';
import '../cubit/retailer_manage_staff_shops_cubit.dart';
import 'retailer_manage_staff_shops_copy.dart';

/// Opens the shop editor for one staff member, and cleans up after it.
///
/// The options read starts **before** the surface is shown, so the list is
/// already in flight while the dialog appears rather than after it.
///
/// Closing drops the target, the selection and the options: shop availability is
/// exactly the thing that goes stale, and a reopened editor asks again rather
/// than offering a shop that may have been suspended in between. The last
/// result survives deliberately — it is acknowledged beside the roster it
/// changed.
Future<void> showRetailerManageStaffShopsDialog(
  BuildContext context, {
  required RetailerStaffMember member,
}) async {
  final RetailerManageStaffShopsCubit cubit = context
      .read<RetailerManageStaffShopsCubit>();

  cubit.open(member);

  await showDialog<void>(
    context: context,
    // A save is a write. Dismissing the surface by tapping outside it while one
    // is in flight would leave the person with no idea what happened, so the
    // barrier is inert and Cancel disables itself for the same moments.
    barrierDismissible: false,
    builder: (BuildContext dialogContext) =>
        BlocProvider<RetailerManageStaffShopsCubit>.value(
          // `showDialog` inserts the route on the **root** navigator, which is
          // above the Retailer Owner shell that owns this cubit — so the value
          // is carried across explicitly rather than looked up from a context
          // that could not see it.
          value: cubit,
          child: const _ManageShopsDialog(),
        ),
  );

  // Idempotent, and needed for the Cancel and back-button paths: a committed
  // save has already closed the editor itself.
  cubit.closeEditor();
}

/// The editor.
///
/// ## What may be selected, and how
///
/// Only shops `list_retailer_staff_assignable_shops()` returned — the
/// Retailer's currently ACTIVE estate. Selection is keyed on the id that read
/// supplied and is held in a `Set`, so a duplicate is structurally impossible.
/// **No shop is ever selected by display name**, because two shops may
/// legitimately share one, and **no identifier is displayed** — not the shop's,
/// and not the membership's.
///
/// ## What it says about what it cannot see
///
/// The current-assignment list and the options are both the **ACTIVE
/// projection**. Nothing here claims to show every assignment a person holds,
/// and no control offers to remove an assignment to a shop that is not on the
/// list — the write preserves those, by design.
///
/// ## Accessibility
///
/// The heading is a real header node. The picker rows are focusable controls
/// with `checked` semantics and a 44pt minimum target, announced by shop name
/// rather than by an unlabelled checkbox. The selected-count line and the
/// failure notice are live regions, so a change of either is announced without
/// the person hunting for it.
class _ManageShopsDialog extends StatelessWidget {
  const _ManageShopsDialog();

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final Size screen = MediaQuery.sizeOf(context);

    return BlocConsumer<
      RetailerManageStaffShopsCubit,
      RetailerManageStaffShopsState
    >(
      // The cubit closes the editor itself on a committed save and when the
      // target leaves the roster. The surface follows that state rather than
      // deciding for itself, so there is exactly one place that knows when the
      // editor is finished.
      listenWhen:
          (
            RetailerManageStaffShopsState previous,
            RetailerManageStaffShopsState current,
          ) => previous.isOpen && !current.isOpen,
      listener: (BuildContext context, RetailerManageStaffShopsState state) {
        final NavigatorState navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        }
      },
      builder: (BuildContext context, RetailerManageStaffShopsState state) {
        final RetailerManageStaffShopsCubit cubit = context
            .read<RetailerManageStaffShopsCubit>();

        return PopScope(
          // The back gesture is refused only while a write is in flight, for the
          // same reason the barrier is inert.
          canPop: !state.isSubmitting,
          child: Dialog(
            insetPadding: const EdgeInsets.all(SrSpacing.lg),
            child: ConstrainedBox(
              // Bounded in both directions: wide enough for a shop name beside
              // its code and city on a tablet or the web, never wider than a
              // comfortable measure; tall enough for several rows and never
              // taller than the viewport, so the picker scrolls inside the
              // dialog rather than pushing its own header off screen.
              constraints: BoxConstraints(
                maxWidth: 560,
                maxHeight: screen.height * 0.85,
              ),
              child: Padding(
                padding: const EdgeInsets.all(SrSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _Header(state: state),
                    const SizedBox(height: SrSpacing.lg),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _CurrentShops(state: state),
                            const SizedBox(height: SrSpacing.xl),
                            _Options(state: state, cubit: cubit),
                            if (state.notice != null) ...<Widget>[
                              const SizedBox(height: SrSpacing.xl),
                              _Notice(state: state),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: SrSpacing.xl),
                    Divider(height: 1, color: sr.border),
                    const SizedBox(height: SrSpacing.lg),
                    _Actions(state: state, cubit: cubit),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The person this editor is about: their name, their role, and what the change
/// will do.
///
/// The name and the role's **display name** are shown. The membership id is not,
/// and could not be — it is an address, and an address on screen is noise a
/// person cannot act on.
class _Header extends StatelessWidget {
  const _Header({required this.state});

  final RetailerManageStaffShopsState state;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            RetailerManageStaffShopsCopy.title,
            style: SrTypography.sectionTitle.copyWith(color: sr.foreground),
          ),
        ),
        const SizedBox(height: SrSpacing.xs),
        if (state.staffName != null)
          Text(
            state.staffName!,
            style: SrTypography.body.copyWith(
              color: sr.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (state.roleName != null) ...<Widget>[
          const SizedBox(height: SrSpacing.xxs),
          // `roles.name`, never `role_code`: `SALES_STAFF` on a screen would be
          // an internal token leaking into the UI.
          SrBadge(label: state.roleName!, tone: SrTone.blue),
        ],
        const SizedBox(height: SrSpacing.sm),
        Text(
          RetailerManageStaffShopsCopy.description,
          style: SrTypography.caption.copyWith(color: sr.textMuted),
        ),
      ],
    );
  }
}

/// What the roster says this person holds today.
///
/// Names only, from the canonical read. An empty list is stated plainly rather
/// than left as a gap that reads like missing data.
class _CurrentShops extends StatelessWidget {
  const _CurrentShops({required this.state});

  final RetailerManageStaffShopsState state;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final List<String> names = state.currentShopNames;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          RetailerManageStaffShopsCopy.currentLabel,
          style: SrTypography.caption.copyWith(color: sr.textMuted),
        ),
        const SizedBox(height: SrSpacing.xs),
        if (names.isEmpty)
          Text(
            RetailerManageStaffShopsCopy.currentNone,
            style: SrTypography.body.copyWith(color: sr.textMuted),
          )
        else
          Wrap(
            spacing: SrSpacing.sm,
            runSpacing: SrSpacing.sm,
            children: <Widget>[
              for (final String name in names)
                SrBadge(
                  label: name,
                  tone: SrTone.slate,
                  icon: Icons.storefront_rounded,
                ),
            ],
          ),
      ],
    );
  }
}

/// The picker, or whatever stands in for it.
class _Options extends StatelessWidget {
  const _Options({required this.state, required this.cubit});

  final RetailerManageStaffShopsState state;
  final RetailerManageStaffShopsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return SrField(
      label: RetailerManageStaffShopsCopy.optionsLabel,
      required: true,
      hint: RetailerManageStaffShopsCopy.optionsHint,
      errorText: _messageFor(state, RetailerStaffShopAssignmentField.shops),
      child: _OptionsBody(state: state, cubit: cubit),
    );
  }

  static String? _messageFor(
    RetailerManageStaffShopsState state,
    RetailerStaffShopAssignmentField field,
  ) {
    final RetailerStaffShopAssignmentInputProblem? problem = state.problemFor(
      field,
    );
    return problem == null
        ? null
        : RetailerManageStaffShopsCopy.fieldMessage(field, problem);
  }
}

class _OptionsBody extends StatelessWidget {
  const _OptionsBody({required this.state, required this.cubit});

  final RetailerManageStaffShopsState state;
  final RetailerManageStaffShopsCubit cubit;

  @override
  Widget build(BuildContext context) {
    if (state.isOptionsLoading) {
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
                RetailerManageStaffShopsCopy.optionsLoading,
                style: SrTypography.body.copyWith(
                  color: context.sr.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (state.hasOptionsFailed) {
      // Scoped to this read, and never converted into a write failure: nothing
      // was sent, the roster underneath is untouched, and the retry is the read
      // alone. A refusal is `42501` and arrives here, never as an empty picker.
      return SrEmptyState(
        icon: Icons.storefront_outlined,
        tone: SrTone.amber,
        title: RetailerManageStaffShopsCopy.optionsUnavailableTitle,
        description: RetailerManageStaffShopsCopy.optionsProblemBody(
          state.optionsProblem!,
        ),
        action: Semantics(
          button: true,
          label: RetailerManageStaffShopsCopy.optionsRetry,
          child: SrButton(
            label: RetailerManageStaffShopsCopy.optionsRetry,
            variant: SrButtonVariant.outline,
            icon: Icons.refresh_rounded,
            onPressed: state.isSubmitting ? null : cubit.loadAssignableShops,
          ),
        ),
      );
    }

    if (state.isOptionsEmpty) {
      return const SrEmptyState(
        icon: Icons.storefront_outlined,
        tone: SrTone.slate,
        title: RetailerManageStaffShopsCopy.optionsEmptyTitle,
        description: RetailerManageStaffShopsCopy.optionsEmptyBody,
      );
    }

    final List<RetailerAssignableShop> shops =
        state.shops ?? const <RetailerAssignableShop>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (state.availabilityChanged) ...<Widget>[
          const SrAlert(
            tone: SrAlertTone.warning,
            title: RetailerManageStaffShopsCopy.availabilityChangedTitle,
            message: RetailerManageStaffShopsCopy.availabilityChangedBody,
          ),
          const SizedBox(height: SrSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              button: true,
              label: RetailerManageStaffShopsCopy.availabilityChangedAction,
              child: SrButton(
                label: RetailerManageStaffShopsCopy.availabilityChangedAction,
                variant: SrButtonVariant.outline,
                size: SrButtonSize.sm,
                icon: Icons.checklist_rounded,
                onPressed: cubit.acknowledgeAvailabilityChange,
              ),
            ),
          ),
          const SizedBox(height: SrSpacing.md),
        ],

        Semantics(
          liveRegion: true,
          child: Text(
            RetailerManageStaffShopsCopy.selectedCount(state.selectedCount),
            style: SrTypography.caption.copyWith(
              color: context.sr.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: SrSpacing.sm),

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
                            <String>[?shop.code, ?shop.city].join(' · '),
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

/// The failure notice shown **inside** the editor.
///
/// A committed save closes the editor, so the success sentence belongs beside
/// the roster rather than here. What remains is a refusal or an unresolved
/// outcome, which is exactly where the person is still looking.
class _Notice extends StatelessWidget {
  const _Notice({required this.state});

  final RetailerManageStaffShopsState state;

  @override
  Widget build(BuildContext context) {
    final RetailerManageShopsNotice notice = state.notice!;

    return Semantics(
      liveRegion: true,
      child: SrAlert(
        tone: notice.isUnresolved ? SrAlertTone.warning : SrAlertTone.error,
        title: RetailerManageStaffShopsCopy.noticeTitle(notice),
        message: RetailerManageStaffShopsCopy.noticeBody(
          notice,
          change: state.change,
        ),
      ),
    );
  }
}

/// Cancel and Save.
///
/// Both are disabled while a write is in flight — Cancel because closing the
/// surface then would leave the person with no report, and Save because a second
/// press must not become a second write. The cubit refuses both independently;
/// these are the courtesy, not the rule.
class _Actions extends StatelessWidget {
  const _Actions({required this.state, required this.cubit});

  final RetailerManageStaffShopsState state;
  final RetailerManageStaffShopsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget cancel = Semantics(
          button: true,
          enabled: !state.isSubmitting,
          label: RetailerManageStaffShopsCopy.cancel,
          child: SrButton(
            label: RetailerManageStaffShopsCopy.cancel,
            variant: SrButtonVariant.outline,
            fullWidth: constraints.maxWidth < SrSpacing.breakpointSm,
            // Closes the editor and writes nothing. The cubit's `close` is what
            // drops the target and the selection.
            onPressed: state.isSubmitting ? null : cubit.closeEditor,
          ),
        );

        final Widget save = Semantics(
          button: true,
          enabled: state.canSave,
          label: RetailerManageStaffShopsCopy.saveSemantics,
          child: SrButton(
            label: RetailerManageStaffShopsCopy.save,
            loadingLabel: RetailerManageStaffShopsCopy.saving,
            icon: Icons.check_rounded,
            fullWidth: constraints.maxWidth < SrSpacing.breakpointSm,
            loading: state.isSubmitting,
            onPressed: state.canSave ? cubit.save : null,
          ),
        );

        // Stacked on a narrow phone so neither label is squeezed; side by side,
        // trailing-aligned, once there is room.
        if (constraints.maxWidth < SrSpacing.breakpointSm) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              save,
              const SizedBox(height: SrSpacing.sm),
              cancel,
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            cancel,
            const SizedBox(width: SrSpacing.md),
            save,
          ],
        );
      },
    );
  }
}
