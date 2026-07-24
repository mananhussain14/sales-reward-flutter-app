import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/receipt_shop.dart';

/// The assigned-shop picker.
///
/// A tappable field that opens a bottom sheet, rather than a
/// `DropdownButtonFormField`. A dropdown's menu is a floating overlay sized to
/// its longest item, which on a phone either overflows or truncates a shop name;
/// a sheet gives every option a full-width row, a checkmark for the current
/// choice, and a target big enough for a thumb on a shop floor.
///
/// ## Accessibility
///
/// The field is an [InkWell], so it takes keyboard focus and activates with
/// Enter or Space, and it is wrapped in [Semantics] as a button whose value is
/// the current selection — a screen reader announces `Shop, <name>, button`
/// rather than reading a decorative box. Each row in the sheet reports its own
/// selected state to assistive technology, and marks the current choice with a
/// glyph as well as a fill, so the selection is never carried by colour alone.
class ReceiptShopSelector extends StatelessWidget {
  const ReceiptShopSelector({
    super.key,
    required this.shops,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    this.errorText,
  });

  final List<ReceiptShop> shops;
  final ReceiptShop? selected;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final bool interactive = enabled && shops.isNotEmpty;
    final String label = selected?.displayLabel ?? 'Select a shop…';

    return SrField(
      label: 'Shop',
      required: true,
      errorText: errorText,
      hint: shops.isEmpty
          ? null
          : 'A receipt is always submitted against one assigned shop.',
      child: Semantics(
        button: true,
        container: true,
        enabled: interactive,
        // Distinct from the visible "Shop" label so a screen reader announces
        // one unambiguous control rather than repeating the field caption.
        label: 'Assigned shop',
        value: selected?.displayLabel ?? 'No shop selected',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: interactive ? () => _openSheet(context) : null,
            borderRadius: BorderRadius.circular(SrRadii.control),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(
                horizontal: SrSpacing.mdPlus,
                vertical: SrSpacing.md,
              ),
              decoration: BoxDecoration(
                color: interactive ? sr.inputFill : sr.inputDisabledFill,
                borderRadius: BorderRadius.circular(SrRadii.control),
                border: Border.all(
                  color: errorText == null
                      ? sr.inputBorder
                      : sr.inputErrorBorder,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.storefront_outlined,
                    size: 16,
                    color: selected == null ? sr.textMuted : sr.brand,
                  ),
                  const SizedBox(width: SrSpacing.sm),
                  Expanded(
                    child: Text(
                      label,
                      style: SrTypography.body.copyWith(
                        color: selected == null ? sr.textMuted : sr.foreground,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: sr.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    final SrColorScheme sr = context.sr;

    final String? chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: sr.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(SrRadii.surface),
        ),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            // Never taller than 70% of the viewport, so the sheet cannot swallow
            // a short screen — and it scrolls inside that bound.
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SrSpacing.xl,
                    0,
                    SrSpacing.xl,
                    SrSpacing.md,
                  ),
                  child: Text(
                    'Choose a shop',
                    style: SrTypography.sectionTitle.copyWith(
                      color: sr.foreground,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: SrSpacing.lg),
                    itemCount: shops.length,
                    itemBuilder: (BuildContext itemContext, int index) {
                      final ReceiptShop shop = shops[index];
                      final bool isSelected = shop.shopId == selected?.shopId;

                      return Semantics(
                        selected: isSelected,
                        button: true,
                        child: ListTile(
                          onTap: () =>
                              Navigator.of(sheetContext).pop(shop.shopId),
                          selected: isSelected,
                          selectedTileColor: sr.navActiveFill,
                          title: Text(
                            shop.shopName,
                            style: SrTypography.label.copyWith(
                              color: isSelected
                                  ? sr.navActiveLabel
                                  : sr.foreground,
                            ),
                          ),
                          subtitle: shop.shopCode == null
                              ? null
                              : Text(
                                  shop.shopCode!,
                                  style: SrTypography.caption.copyWith(
                                    color: sr.textSecondary,
                                  ),
                                ),
                          // The selection is a glyph as well as a fill, so it is
                          // never carried by colour alone.
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: sr.brand,
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (chosen != null) {
      onChanged(chosen);
    }
  }
}
