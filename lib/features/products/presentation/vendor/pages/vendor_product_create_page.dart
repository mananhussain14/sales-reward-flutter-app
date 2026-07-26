import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/shells/vendor/vendor_navigation.dart';
import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../../auth/domain/entities/portal_kind.dart';
import '../../../domain/entities/vendor_product_field.dart';
import '../cubit/vendor_product_create_cubit.dart';
import '../widgets/vendor_product_copy.dart';
import '../widgets/vendor_product_form_fields.dart';
import '../widgets/vendor_product_write_notices.dart';

/// The create-a-product form.
///
/// Backed by **one** call to `create_vendor_product(p_product_code,
/// p_product_name, p_barcode, p_brand, p_description)` — five values, and no
/// organization, tenant, user, profile, role, permission, status or assignment
/// argument, because the deployed function has no parameter for one.
///
/// ## The five fields, and the reason there are only five
///
/// Product code, name, barcode, brand, description. There is no status selector
/// (a new product is `ACTIVE`, decided by the function), no Vendor selector (the
/// Vendor is derived from `auth.uid()` in SQL), no Retailer assignment control
/// (assignment writes are a separate milestone on a separate permission, and a
/// create writes no assignment row), and no price, stock, image, reward, incentive,
/// campaign or receipt field, because no such column exists anywhere in the schema.
///
/// ## What happens after the write
///
/// The RPC returns a uuid and nothing else — deliberately, because a returned row
/// would be a third product shape on top of the list row and the detail row. So on
/// success the catalogue is invalidated, the **canonical** product is read with
/// `get_vendor_product_detail`, and the router moves to that product's own screen,
/// which renders what the backend stored. Nothing here builds a product from the
/// form: every field is normalized server-side, so the stored values can
/// legitimately differ from what was typed, and echoing the form would present a
/// guess as a record.
///
/// ## The one case this screen exists to get right
///
/// A create that succeeded whose id could not be read leaves
/// [VendorProductCreatePhase.unconfirmed]. The product **exists**. So this screen
/// does not say the create failed, does not re-arm the button, and does not offer a
/// retry — pressing Create again would either duplicate the product or be refused
/// as a duplicate code. It sends the reader to the catalogue instead, which is the
/// only authority on what exists, and says plainly not to create it twice.
class VendorProductCreatePage extends StatefulWidget {
  const VendorProductCreatePage({super.key});

  @override
  State<VendorProductCreatePage> createState() =>
      _VendorProductCreatePageState();
}

class _VendorProductCreatePageState extends State<VendorProductCreatePage> {
  @override
  void initState() {
    super.initState();
    // A blank form each time the route is entered. `start` is a no-op while a
    // submission is in flight, so a rebuild cannot discard a create that is already
    // on its way.
    context.read<VendorProductCreateCubit>().start();
  }

  void _cancel() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    // Reached by a deep link or a hard browser reload, where there is no catalogue
    // beneath this route to pop back to.
    context.go(VendorNavigation.products);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VendorProductCreateCubit, VendorProductCreateState>(
      // Fires once, on the transition into `created`. The cubit has already asked
      // the detail cubit to read the new product canonically, so by the time this
      // route is replaced that read is in flight and the product screen's own
      // `open` recognises it rather than issuing a second one.
      listenWhen:
          (
            VendorProductCreateState previous,
            VendorProductCreateState current,
          ) =>
              current.phase == VendorProductCreatePhase.created &&
              previous.phase != VendorProductCreatePhase.created,
      listener: (BuildContext context, VendorProductCreateState state) {
        final String? productId = state.createdProductId;
        if (productId == null) {
          return;
        }
        context.go(VendorNavigation.productDetailPath(productId));
      },
      builder: (BuildContext context, VendorProductCreateState state) {
        final VendorProductCreateCubit cubit = context
            .read<VendorProductCreateCubit>();

        return SrPageBody(
          // A form is capped narrower than a catalogue: a single column of controls
          // stretched across a desktop browser is harder to read, not easier, and
          // this is the same width the receipt form uses.
          maxWidth: SrSpacing.formMaxWidth,
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                button: true,
                label: VendorProductCopy.backToList,
                child: SrButton(
                  label: VendorProductCopy.backToList,
                  variant: SrButtonVariant.ghost,
                  size: SrButtonSize.sm,
                  icon: Icons.arrow_back_rounded,
                  onPressed: state.isSubmitting ? null : _cancel,
                ),
              ),
            ),
            const SizedBox(height: SrSpacing.lg),
            Semantics(
              header: true,
              child: SrPageHeader(
                eyebrow: PortalKind.vendorSuperAdmin.displayName,
                title: VendorProductCopy.createTitle,
                description: VendorProductCopy.createDescription,
              ),
            ),
            const SizedBox(height: SrSpacing.xxl),
            if (state.phase == VendorProductCreatePhase.unconfirmed)
              const _Unconfirmed()
            else
              _CreateForm(state: state, cubit: cubit, onCancel: _cancel),
          ],
        );
      },
    );
  }
}

class _CreateForm extends StatelessWidget {
  const _CreateForm({
    required this.state,
    required this.cubit,
    required this.onCancel,
  });

  final VendorProductCreateState state;
  final VendorProductCreateCubit cubit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    // `created` keeps the form visible and disabled while the router moves and the
    // canonical read runs, so the screen never flashes an empty form on the way out.
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
            values: state.values,
            fieldErrors: state.fieldErrors,
            enabled: !busy,
            codeIsReadOnly: false,
            firstInvalidField: state.firstInvalidField,
            onFieldChanged: (VendorProductField field, String value) =>
                _dispatch(cubit, field, value),
          ),
          const SizedBox(height: SrSpacing.xxl),
          if (state.phase == VendorProductCreatePhase.created) ...<Widget>[
            const SrAlert(
              tone: SrAlertTone.success,
              message: VendorProductCopy.createdOpening,
            ),
            const SizedBox(height: SrSpacing.xl),
          ],
          // Stacked on a phone so both actions stay reachable at a comfortable
          // width, side by side once there is room. The primary action is last in
          // reading order on wide screens and first on narrow ones, which is where a
          // thumb reaches.
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final SrButton submit = SrButton(
                label: VendorProductCopy.createSubmit,
                loadingLabel: VendorProductCopy.createSubmitting,
                size: SrButtonSize.lg,
                fullWidth: constraints.maxWidth < SrSpacing.breakpointSm,
                loading: state.isSubmitting,
                // Null while busy, which is the duplicate-submit guard's visible
                // half. The cubit refuses a second call regardless, so a stale
                // widget cannot get past it.
                onPressed: busy ? null : cubit.submit,
              );
              final SrButton cancel = SrButton(
                label: VendorProductCopy.cancel,
                variant: SrButtonVariant.outline,
                size: SrButtonSize.lg,
                fullWidth: constraints.maxWidth < SrSpacing.breakpointSm,
                onPressed: busy ? null : onCancel,
              );

              if (constraints.maxWidth < SrSpacing.breakpointSm) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Semantics(
                      button: true,
                      label: VendorProductCopy.createSubmit,
                      child: submit,
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
                    label: VendorProductCopy.createSubmit,
                    child: submit,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static void _dispatch(
    VendorProductCreateCubit cubit,
    VendorProductField field,
    String value,
  ) {
    switch (field) {
      case VendorProductField.productCode:
        cubit.productCodeChanged(value);
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

/// The product was created and cannot be opened.
///
/// A success notice, not a failure, and with **no** create action anywhere on it:
/// the only way forward is the catalogue, and the copy says so explicitly so nobody
/// resolves the ambiguity by submitting the form again.
class _Unconfirmed extends StatelessWidget {
  const _Unconfirmed();

  @override
  Widget build(BuildContext context) {
    return SrEmptyState(
      icon: Icons.check_circle_outline_rounded,
      tone: SrTone.emerald,
      title: VendorProductCopy.createUnconfirmedTitle,
      description: VendorProductCopy.createUnconfirmedBody,
      action: Semantics(
        button: true,
        label: VendorProductCopy.goToCatalogue,
        child: SrButton(
          label: VendorProductCopy.goToCatalogue,
          variant: SrButtonVariant.outline,
          icon: Icons.inventory_2_outlined,
          onPressed: () => context.go(VendorNavigation.products),
        ),
      ),
    );
  }
}
