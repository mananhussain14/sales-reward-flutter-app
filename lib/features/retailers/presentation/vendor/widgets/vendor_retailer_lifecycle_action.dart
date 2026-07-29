import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_retailer_detail.dart';
import '../../../domain/entities/vendor_retailer_lifecycle_action.dart';
import '../cubit/vendor_retailer_capability_cubit.dart';
import '../cubit/vendor_retailer_lifecycle_cubit.dart';
import 'vendor_retailer_lifecycle_confirmations.dart';
import 'vendor_retailer_lifecycle_copy.dart';
import 'vendor_retailer_lifecycle_notices.dart';

/// Resolves the action a loaded Retailer offers, or null.
///
/// A named seam over [VendorRetailerLifecycleAction.forPair] so a test can
/// assert the same decision the screen makes without building a widget, and so
/// the screen has exactly one way to ask the question.
abstract final class VendorRetailerLifecycleOffer {
  static VendorRetailerLifecycleAction? forDetail(
    VendorRetailerDetail detail,
  ) => VendorRetailerLifecycleAction.forPair(
    retailerStatus: detail.retailerStatus,
    relationshipStatus: detail.relationshipStatus,
  );
}

/// Deactivate or reactivate one Retailer, in its own section, behind a
/// confirmation.
///
/// ## It renders nothing unless two things are true at once
///
/// 1. `RETAILERS_MANAGE` is **confirmed** — positive equality against a settled
///    probe. A denied answer, an unavailable one, and a probe that has not
///    finished all render nothing at all: not a disabled button, which would
///    still advertise that the operation exists.
/// 2. The canonical pair resolves to a [VendorRetailerLifecycleAction] —
///    `ACTIVE`/`ACTIVE` or `SUSPENDED`/`SUSPENDED` and nothing else. A mismatch,
///    a `DEACTIVATED` row, an unknown token and any future value all resolve to
///    null and render nothing.
///
/// Both are expressed positively, so a new state added to any of the enums
/// involved hides the control rather than falling through into it.
///
/// The Retailer acted on is the one whose row this widget was handed, which the
/// detail page only builds for the route it loaded — so the id sent to the RPC
/// is always the id the canonical read confirmed.
///
/// **This is presentation, not authorization.** Whether this caller may change a
/// Retailer's status is decided in SQL on every call, under row locks this
/// client cannot take, by a permission this widget never compares against
/// anything.
///
/// ## Why a whole section rather than a button beside the badges
///
/// Deactivating a Retailer stops every person at a company from working. It is
/// not a toggle, and putting it next to a status pill would present it as one.
/// The section carries its own heading and its own explanation, and the dialog
/// carries the consequences, so nobody reaches the write without having been
/// told what it does.
///
/// ## Nothing is optimistic
///
/// The badges above are never flipped ahead of the backend. They change when —
/// and only when — a fresh `get_vendor_retailer_detail` says so, which is why a
/// failure leaves the previous statuses untouched rather than having to undo a
/// guess. While a request is in flight the button is disabled and shows
/// progress, and the whole Retailer stays legible beside it.
class VendorRetailerLifecycleSection extends StatelessWidget {
  const VendorRetailerLifecycleSection({super.key, required this.detail});

  final VendorRetailerDetail detail;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<
      VendorRetailerCapabilityCubit,
      VendorRetailerCapabilityState
    >(
      builder: (BuildContext context, VendorRetailerCapabilityState state) {
        if (!state.isConfirmed) {
          return const SizedBox.shrink();
        }

        final VendorRetailerLifecycleAction? action =
            VendorRetailerLifecycleOffer.forDetail(detail);
        if (action == null) {
          return const SizedBox.shrink();
        }

        // The leading gap belongs to the control rather than to the page, so a
        // hidden control contributes no height at all and the sections around
        // it keep their normal spacing.
        return Padding(
          padding: const EdgeInsets.only(top: SrSpacing.xxl),
          child: _LifecycleCard(detail: detail, action: action),
        );
      },
    );
  }
}

class _LifecycleCard extends StatelessWidget {
  const _LifecycleCard({required this.detail, required this.action});

  final VendorRetailerDetail detail;
  final VendorRetailerLifecycleAction action;

  @override
  Widget build(BuildContext context) {
    return SrSectionCard(
      title: VendorRetailerLifecycleCopy.sectionTitle,
      description: action.isDeactivation
          ? VendorRetailerLifecycleCopy.sectionActiveDescription
          : VendorRetailerLifecycleCopy.sectionInactiveDescription,
      child:
          BlocBuilder<
            VendorRetailerLifecycleCubit,
            VendorRetailerLifecycleState
          >(
            builder: (BuildContext context, VendorRetailerLifecycleState state) {
              final VendorRetailerLifecycleCubit cubit = context
                  .read<VendorRetailerLifecycleCubit>();
              final bool busy = state.isBusyFor(detail.relationshipId);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // A failure for *this* Retailer only. A refusal that landed
                  // for another Retailer must not appear under this one.
                  if (state.hasFailureFor(detail.relationshipId)) ...<Widget>[
                    VendorRetailerLifecycleFailureAlert(
                      failure: state.failure!,
                    ),
                    const SizedBox(height: SrSpacing.xl),
                  ],
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Semantics(
                      button: true,
                      label: action.isDeactivation
                          ? VendorRetailerLifecycleCopy.deactivateSemantics
                          : VendorRetailerLifecycleCopy.reactivateSemantics,
                      child: SrButton(
                        label: action.actionLabel,
                        loadingLabel: action.isDeactivation
                            ? VendorRetailerLifecycleCopy.deactivating
                            : VendorRetailerLifecycleCopy.reactivating,
                        // Outline rather than danger. Deactivation is reversible
                        // with one press and destroys nothing — red would say
                        // "this cannot be undone" about something that can.
                        variant: SrButtonVariant.outline,
                        icon: action.isDeactivation
                            ? Icons.pause_circle_outline_rounded
                            : Icons.play_circle_outline_rounded,
                        loading: busy,
                        // Null while busy, which is the duplicate-submission
                        // guard's visible half. The cubit refuses a second call
                        // regardless, and a same-status request is an idempotent
                        // no-op in SQL — so even a request that got through
                        // twice could not record two decisions.
                        onPressed: busy
                            ? null
                            : () => _confirmAndApply(context, cubit),
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
  /// The dialog is the screen's job and the cubit knows nothing about it, so a
  /// test can exercise the write without a widget *and* a screen cannot skip the
  /// confirmation by calling something cheaper — the only path to
  /// [VendorRetailerLifecycleCubit.apply] from this feature's UI is through
  /// here.
  ///
  /// Cancelling calls nothing at all: no RPC, no state change, no optimistic
  /// flip.
  Future<void> _confirmAndApply(
    BuildContext context,
    VendorRetailerLifecycleCubit cubit,
  ) async {
    final bool confirmed = await confirmVendorRetailerLifecycle(
      context,
      action: action,
      // Display text from the canonical read. It is never sent anywhere and is
      // never an authorization input.
      retailerName: detail.retailerName,
    );

    if (confirmed) {
      // The relationship id from the canonical detail row — the same
      // `vendor_retailers.id` the route addressed and the read confirmed. The
      // Retailer organization id is deliberately not used: the schema permits
      // several Vendors to manage one Retailer, so it does not identify whose
      // relationship is meant.
      await cubit.apply(detail.relationshipId, action);
    }
  }
}
