import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/shells/vendor/vendor_navigation.dart';
import '../../../../../core/widgets/widgets.dart';
import 'vendor_product_copy.dart';

/// The one write affordance on the catalogue: open the create form.
///
/// Its own widget because it appears twice — in the page header, and inside the
/// empty state, where "no products yet" is exactly the moment somebody wants to add
/// one. Two copies would be two labels and two semantics strings to keep in step.
///
/// It navigates and nothing else. There is no permission check here, and there
/// cannot be a meaningful one: whether this caller may create a product is decided in
/// SQL on the call, by a permission this client never names, sends or inspects — so
/// this button's presence is a statement about the *route*, and the create itself is
/// refused generically if the backend disagrees.
///
/// `go` rather than `push`, matching how the catalogue opens a product: it stacks the
/// create route above the catalogue, so browser back — and the form's own Cancel —
/// return to a list that is still loaded.
class VendorProductAddButton extends StatelessWidget {
  const VendorProductAddButton({super.key, this.variant});

  /// Overrides the button treatment. The header uses the primary one, because
  /// adding a product is the page's main action; the empty state uses it too, for
  /// the same reason.
  final SrButtonVariant? variant;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: VendorProductCopy.addProductSemantics,
      child: SrButton(
        label: VendorProductCopy.addProduct,
        variant: variant ?? SrButtonVariant.primary,
        icon: Icons.add_rounded,
        onPressed: () => context.go(VendorNavigation.productCreate),
      ),
    );
  }
}
