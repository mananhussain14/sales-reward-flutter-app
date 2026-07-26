import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_product_detail.dart';
import '../../../domain/entities/vendor_product_status.dart';
import '../../../domain/entities/vendor_product_status_change.dart';
import '../cubit/vendor_product_status_cubit.dart';
import 'vendor_product_copy.dart';
import 'vendor_product_write_notices.dart';

/// Activate or deactivate one product, in its own section, behind a confirmation.
///
/// ## Why it is a section of its own and not a control in the edit form
///
/// `update_vendor_product` never writes `status` and `set_vendor_product_status`
/// never writes the display fields — the two are separate operations on separate
/// RPCs, serialized by `FOR UPDATE` on the same row, neither able to clobber the
/// other's columns. Putting a status control inside the edit form would suggest that
/// correcting a name and withdrawing a product are one decision, which is exactly
/// what the contract refuses to let them be. So the action sits apart from Edit,
/// with its own heading, its own explanation and its own confirmation.
///
/// ## Which action is offered comes from the product
///
/// An `ACTIVE` product offers Deactivate; an `INACTIVE` one offers Activate. A status
/// token this build does not recognise offers **neither**, and says so: the opposite
/// of an unfamiliar status is not knowable, and guessing would invent a transition.
///
/// This is presentation, not authorization. Whether this caller may change a status
/// is decided in SQL on every call, by a permission this client never names.
///
/// ## Nothing is optimistic
///
/// The visible status is never flipped ahead of the backend. It changes when — and
/// only when — a fresh `get_vendor_product_detail` says so, which is why a failure
/// leaves the previous status untouched rather than having to undo a guess. While a
/// request is in flight the button is disabled and shows progress, and the whole
/// product stays legible beside it.
class VendorProductStatusAction extends StatelessWidget {
  const VendorProductStatusAction({super.key, required this.detail});

  final VendorProductDetail detail;

  @override
  Widget build(BuildContext context) {
    final VendorProductStatusChange? change =
        VendorProductStatusChange.forCurrent(detail.status);

    return SrSectionCard(
      title: VendorProductCopy.statusSectionTitle,
      description: switch (detail.status) {
        VendorProductStatus.active =>
          VendorProductCopy.statusSectionActiveDescription,
        VendorProductStatus.inactive =>
          VendorProductCopy.statusSectionInactiveDescription,
        VendorProductStatus.unknown =>
          VendorProductCopy.statusSectionUnknownDescription,
      },
      child: BlocBuilder<VendorProductStatusCubit, VendorProductStatusState>(
        builder: (BuildContext context, VendorProductStatusState state) {
          final VendorProductStatusCubit cubit = context
              .read<VendorProductStatusCubit>();
          final bool busy = state.isBusyFor(detail.productId);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // A failure for *this* product only. A refusal that landed for another
              // product must not appear under this one.
              if (state.hasFailureFor(detail.productId)) ...<Widget>[
                SrAlert(
                  tone: SrAlertTone.error,
                  title: VendorProductCopy.statusFailedTitle,
                  message: VendorProductCopy.statusFailedBody,
                ),
                const SizedBox(height: SrSpacing.md),
                // A denial, an expired session or an outage each get their own
                // wording beneath the "status unchanged" headline, so the reader
                // learns both the effect and the reason without either being
                // guessed at.
                VendorProductWriteAlert(failure: state.failure!),
                const SizedBox(height: SrSpacing.xl),
              ],
              if (change == null)
                // An unrecognised status. Nothing to press, and the section's
                // description has already said why.
                const SizedBox.shrink()
              else
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Semantics(
                    button: true,
                    label: switch (change) {
                      VendorProductStatusChange.deactivate =>
                        VendorProductCopy.deactivateSemantics,
                      VendorProductStatusChange.activate =>
                        VendorProductCopy.activateSemantics,
                    },
                    child: SrButton(
                      label: switch (change) {
                        VendorProductStatusChange.deactivate =>
                          VendorProductCopy.deactivate,
                        VendorProductStatusChange.activate =>
                          VendorProductCopy.activate,
                      },
                      loadingLabel: switch (change) {
                        VendorProductStatusChange.deactivate =>
                          VendorProductCopy.deactivating,
                        VendorProductStatusChange.activate =>
                          VendorProductCopy.activating,
                      },
                      // Deactivation is destructive-looking but is not a deletion, so
                      // it takes the outline treatment rather than the danger one:
                      // red would say "this cannot be undone" about something that
                      // reverses with one press and removes nothing.
                      variant: SrButtonVariant.outline,
                      icon: switch (change) {
                        VendorProductStatusChange.deactivate =>
                          Icons.block_rounded,
                        VendorProductStatusChange.activate =>
                          Icons.check_circle_outline_rounded,
                      },
                      loading: busy,
                      // Null while busy, which is the duplicate-confirmation guard's
                      // visible half. The cubit refuses a second call regardless, and
                      // a same-status request is an idempotent no-op in SQL — so even
                      // a request that got through twice could not record two
                      // decisions.
                      onPressed: busy
                          ? null
                          : () => _confirmAndApply(context, cubit, change),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Asks first, then applies.
  ///
  /// The dialog is the screen's job and the cubit knows nothing about it, so a test
  /// can exercise the write without a widget *and* a screen cannot skip the
  /// confirmation by calling something cheaper — the only path to
  /// [VendorProductStatusCubit.apply] from this feature's UI is through here.
  ///
  /// Cancelling calls nothing at all: no RPC, no state change, no optimistic flip.
  Future<void> _confirmAndApply(
    BuildContext context,
    VendorProductStatusCubit cubit,
    VendorProductStatusChange change,
  ) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(switch (change) {
              VendorProductStatusChange.deactivate =>
                VendorProductCopy.deactivateConfirmTitle,
              VendorProductStatusChange.activate =>
                VendorProductCopy.activateConfirmTitle,
            }),
            // Scrollable so the deactivation explanation — which is deliberately
            // several sentences, because each one is a claim the backend proves —
            // stays readable on a small phone and under large text scaling.
            content: SingleChildScrollView(
              child: Text(switch (change) {
                VendorProductStatusChange.deactivate =>
                  VendorProductCopy.deactivateConfirmBody,
                VendorProductStatusChange.activate =>
                  VendorProductCopy.activateConfirmBody,
              }),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text(VendorProductCopy.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(switch (change) {
                  VendorProductStatusChange.deactivate =>
                    VendorProductCopy.deactivate,
                  VendorProductStatusChange.activate =>
                    VendorProductCopy.activate,
                }),
              ),
            ],
          ),
        ) ??
        // Dismissed by tapping outside or by the back gesture. Treated as a refusal,
        // because a status change nobody confirmed is a status change nobody asked
        // for.
        false;

    if (confirmed) {
      await cubit.apply(detail.productId, change);
    }
  }
}
