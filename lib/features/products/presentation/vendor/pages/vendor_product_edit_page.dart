import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/shells/vendor/vendor_navigation.dart';
import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../../domain/entities/vendor_product_detail.dart';
import '../../../domain/entities/vendor_product_field.dart';
import '../cubit/vendor_product_detail_cubit.dart';
import '../cubit/vendor_product_edit_cubit.dart';
import '../widgets/vendor_product_copy.dart';
import '../widgets/vendor_product_form_fields.dart';
import '../widgets/vendor_product_write_notices.dart';

/// The edit-a-product form, addressed by `product_id` from the route.
///
/// Backed by **one** call to `update_vendor_product(p_product_id, p_product_name,
/// p_barcode, p_brand, p_description)` — the id and the four mutable display
/// fields, and nothing else.
///
/// ## The form is filled from the canonical product, never from the route
///
/// This screen reads the shell's detail cubit, whose row came from
/// `get_vendor_product_detail`, and seeds the form from that. The route contributes
/// an **id** and no content, so a link cannot pre-fill a name, a barcode, a brand or
/// a description and have it saved back as though somebody had typed it.
///
/// That also settles the malformed-id case with no special path. Opening
/// `/vendor/products/not-a-uuid/edit` runs the same canonical read the detail route
/// runs, the repository answers it locally without a request leaving the device, and
/// this screen shows the same non-leaking "not available" state — with no form and
/// therefore no reachable write. The repository guards the id again at the boundary
/// that talks to PostgREST.
///
/// ## The product code is context, and the status is not here at all
///
/// The code is shown read-only because a person needs to know which product they are
/// changing; it is never submitted, because `update_vendor_product` has no parameter
/// for it and a trigger refuses a direct change. The product's status has no control
/// here either: the edit RPC never writes `status`, so activating and deactivating is
/// a separate action, on the product's own screen, behind its own confirmation.
///
/// ## After a successful save
///
/// The RPC returns `void`. So the catalogue is invalidated, the canonical product is
/// re-read, and the router returns to the product's screen — which renders what the
/// backend stored and acknowledges the save there. Nothing here echoes the submitted
/// values as though they were the record, and the assigned-Retailer section the
/// product screen already loaded is left exactly as it is: an edit touches no
/// assignment row.
class VendorProductEditPage extends StatefulWidget {
  const VendorProductEditPage({super.key, required this.productId});

  /// The `:productId` segment, verbatim. Not validated here: the canonical read
  /// behind this screen answers a malformed id exactly as the backend answers an id
  /// that names no product — without issuing a request — so a mistyped URL, an
  /// unknown id and another Vendor's id are one case.
  final String productId;

  @override
  State<VendorProductEditPage> createState() => _VendorProductEditPageState();
}

class _VendorProductEditPageState extends State<VendorProductEditPage> {
  @override
  void initState() {
    super.initState();
    _openAndSeed();
  }

  @override
  void didUpdateWidget(VendorProductEditPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId) {
      _openAndSeed();
    }
  }

  /// Starts the canonical read, and seeds the form from a row that is already held.
  ///
  /// Both halves run here, in a lifecycle callback rather than in `build`: seeding
  /// emits, and emitting from a build is how a frame ends up rebuilding itself.
  ///
  /// [VendorProductDetailCubit.open] is idempotent, so entering this route from the
  /// product's own screen finds the row loaded and issues nothing — in which case
  /// there is no state change for the listener below to hear, and this is the only
  /// place the seed can happen. A deep link straight to `/edit` loads the row for the
  /// first time, and the listener seeds from it when it lands.
  void _openAndSeed() {
    final VendorProductDetailCubit detailCubit = context
        .read<VendorProductDetailCubit>();
    detailCubit.open(widget.productId);

    final VendorProductDetail? detail = detailCubit.state.detail;
    if (detailCubit.state.phase == VendorProductDetailPhase.ready &&
        detail != null &&
        detail.productId == widget.productId) {
      context.read<VendorProductEditCubit>().seed(detail);
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    // A deep link or a hard browser reload, where the product's screen is not
    // beneath this one to pop back to.
    context.go(VendorNavigation.productDetailPath(widget.productId));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VendorProductDetailCubit, VendorProductDetailState>(
      listenWhen:
          (
            VendorProductDetailState previous,
            VendorProductDetailState current,
          ) =>
              // The shell's session isolation empties the detail cubit when the
              // signed-in person changes; returning to `initial` is that event, and
              // the route is re-read under the new caller's own identity.
              current.phase == VendorProductDetailPhase.initial ||
              // A freshly loaded row is what the form is seeded from.
              (current.phase == VendorProductDetailPhase.ready &&
                  previous.detail != current.detail),
      listener: (BuildContext context, VendorProductDetailState state) {
        if (state.phase == VendorProductDetailPhase.initial) {
          context.read<VendorProductDetailCubit>().open(widget.productId);
          return;
        }
        final VendorProductDetail? detail = state.detail;
        if (detail != null) {
          context.read<VendorProductEditCubit>().seed(detail);
        }
      },
      builder: (BuildContext context, VendorProductDetailState detailState) {
        if (detailState.phase == VendorProductDetailPhase.initial ||
            detailState.phase == VendorProductDetailPhase.loading) {
          return const SrLoadingView(label: VendorProductCopy.loadingDetail);
        }

        return SrPageBody(
          maxWidth: SrSpacing.formMaxWidth,
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                button: true,
                label: VendorProductCopy.backToProduct,
                child: SrButton(
                  label: VendorProductCopy.backToProduct,
                  variant: SrButtonVariant.ghost,
                  size: SrButtonSize.sm,
                  icon: Icons.arrow_back_rounded,
                  onPressed: _back,
                ),
              ),
            ),
            const SizedBox(height: SrSpacing.lg),
            ..._content(context, detailState),
          ],
        );
      },
    );
  }

  List<Widget> _content(
    BuildContext context,
    VendorProductDetailState detailState,
  ) {
    switch (detailState.phase) {
      case VendorProductDetailPhase.initial:
      case VendorProductDetailPhase.loading:
        return const <Widget>[];

      case VendorProductDetailPhase.notFound:
        // One wording for an unknown id, another Vendor's id, an id from another
        // table and a malformed id alike, and no form — so no write is reachable
        // from here. No retry either: the backend answered, and it will answer the
        // same way.
        return <Widget>[
          SrEmptyState(
            icon: Icons.search_off_rounded,
            title: VendorProductCopy.detailNotFoundTitle,
            description: VendorProductCopy.detailNotFoundBody,
            action: SrButton(
              label: VendorProductCopy.backToList,
              variant: SrButtonVariant.outline,
              icon: Icons.arrow_back_rounded,
              onPressed: () => context.go(VendorNavigation.products),
            ),
          ),
        ];

      case VendorProductDetailPhase.failed:
        return <Widget>[
          SrFailureView(
            failure: detailState.failure!,
            onRetry: context.read<VendorProductDetailCubit>().retryDetail,
          ),
        ];

      case VendorProductDetailPhase.ready:
        return <Widget>[
          Semantics(
            header: true,
            child: SrPageHeader(
              eyebrow: PortalKind.vendorSuperAdmin.displayName,
              title: VendorProductCopy.editTitle,
              description: VendorProductCopy.editDescription,
            ),
          ),
          const SizedBox(height: SrSpacing.xxl),
          _EditForm(productId: widget.productId, onCancel: _back),
        ];
    }
  }
}

class _EditForm extends StatelessWidget {
  const _EditForm({required this.productId, required this.onCancel});

  final String productId;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VendorProductEditCubit, VendorProductEditState>(
      // Fires once, on the transition into `saved`. The cubit has already asked the
      // detail cubit to re-read canonically and the catalogue to refresh, so the
      // product's screen renders the stored values and acknowledges the save there.
      listenWhen:
          (VendorProductEditState previous, VendorProductEditState current) =>
              current.phase == VendorProductEditPhase.saved &&
              previous.phase != VendorProductEditPhase.saved,
      listener: (BuildContext context, VendorProductEditState state) =>
          onCancel(),
      builder: (BuildContext context, VendorProductEditState state) {
        final VendorProductEditCubit cubit = context
            .read<VendorProductEditCubit>();

        // Not seeded for *this* product yet — a rebuild between the canonical read
        // landing and the seed taking effect. A spinner rather than an empty form,
        // which would look like a product with no name.
        if (!state.isSeeded || state.productId != productId) {
          return const SrLoadingView(label: VendorProductCopy.loadingDetail);
        }

        final bool busy = !state.canSubmit;

        return SrSectionCard(
          title: VendorProductCopy.overviewTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (state.failure != null) ...<Widget>[
                VendorProductWriteAlert(failure: state.failure!),
                const SizedBox(height: SrSpacing.xl),
              ],
              VendorProductFormFields(
                // The code travels in `values.productCode`, which the cubit fills
                // from the canonical row and never from a setter — so what is shown
                // is what is stored, and the request type has nowhere to put it.
                values: state.values.copyWith(productCode: state.productCode),
                fieldErrors: state.fieldErrors,
                enabled: !busy,
                codeIsReadOnly: true,
                firstInvalidField: state.firstInvalidField,
                onFieldChanged: (VendorProductField field, String value) =>
                    _dispatch(cubit, field, value),
              ),
              const SizedBox(height: SrSpacing.xxl),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool narrow =
                      constraints.maxWidth < SrSpacing.breakpointSm;
                  final SrButton save = SrButton(
                    label: VendorProductCopy.save,
                    loadingLabel: VendorProductCopy.saving,
                    size: SrButtonSize.lg,
                    fullWidth: narrow,
                    loading: state.isSubmitting,
                    // Null while busy — the duplicate-submit guard's visible half,
                    // which the cubit enforces again.
                    onPressed: busy ? null : cubit.submit,
                  );
                  final SrButton cancel = SrButton(
                    label: VendorProductCopy.cancel,
                    variant: SrButtonVariant.outline,
                    size: SrButtonSize.lg,
                    fullWidth: narrow,
                    onPressed: busy ? null : onCancel,
                  );

                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Semantics(
                          button: true,
                          label: VendorProductCopy.save,
                          child: save,
                        ),
                        const SizedBox(height: SrSpacing.md),
                        Semantics(
                          button: true,
                          label: VendorProductCopy.cancel,
                          child: cancel,
                        ),
                      ],
                    );
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      Semantics(
                        button: true,
                        label: VendorProductCopy.cancel,
                        child: cancel,
                      ),
                      const SizedBox(width: SrSpacing.md),
                      Semantics(
                        button: true,
                        label: VendorProductCopy.save,
                        child: save,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  static void _dispatch(
    VendorProductEditCubit cubit,
    VendorProductField field,
    String value,
  ) {
    switch (field) {
      case VendorProductField.productCode:
        // Unreachable: the code renders as read-only context on this screen, so it
        // emits no changes. Ignored rather than forwarded, because there is nothing
        // to forward it to — the cubit has no setter for it.
        break;
      case VendorProductField.productName:
        cubit.productNameChanged(value);
      case VendorProductField.barcode:
        cubit.barcodeChanged(value);
      case VendorProductField.brand:
        cubit.brandChanged(value);
      case VendorProductField.description:
        cubit.descriptionChanged(value);
    }
  }
}
