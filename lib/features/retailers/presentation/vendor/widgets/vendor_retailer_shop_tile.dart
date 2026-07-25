import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_retailer_shop.dart';
import 'vendor_retailer_badges.dart';
import 'vendor_retailer_formatting.dart';

/// One shop of the open Retailer.
///
/// ## Active and inactive are distinguished four ways, none of them colour alone
///
/// 1. The badge **says** the status — "Active", "Suspended", "Deactivated".
/// 2. The badge carries a distinct glyph per status.
/// 3. An inactive shop sits on the recessed [SrCardVariant.muted] surface, so
///    the difference survives a greyscale screenshot.
/// 4. Its leading disc uses the slate tone rather than the emerald one.
///
/// ## Nothing is inferred from an absent value
///
/// `code`, `city` and `country_code` are all nullable in the schema, and a
/// missing one renders "Not recorded" rather than being dropped or guessed. The
/// status is **not** nullable, so a missing one never reaches this widget — the
/// parser refuses the row first. An absent status is never read as active.
///
/// ## No action
///
/// This milestone is read-only: there is no edit, no create, no deactivate and
/// no way to open a shop. The tile is deliberately not tappable, so it does not
/// promise a screen that does not exist.
class VendorRetailerShopTile extends StatelessWidget {
  const VendorRetailerShopTile({super.key, required this.shop});

  final VendorRetailerShop shop;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final bool isActive = shop.shopStatus.isActive;

    return Semantics(
      container: true,
      label:
          '${shop.shopName}. '
          '${VendorRetailerStatusBadge.labelFor(shop.shopStatus)}. '
          'Code ${shop.shopCode ?? notRecorded}. '
          'City ${shop.city ?? notRecorded}. '
          'Country ${shop.countryCode ?? notRecorded}.',
      excludeSemantics: true,
      child: SrCard(
        variant: isActive ? SrCardVariant.standard : SrCardVariant.muted,
        padding: const EdgeInsets.all(SrSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SrIconDisc(
                  icon: isActive
                      ? Icons.store_rounded
                      : Icons.store_mall_directory_outlined,
                  tone: isActive ? SrTone.emerald : SrTone.slate,
                  size: 40,
                ),
                const SizedBox(width: SrSpacing.md),
                Expanded(
                  child: Text(
                    shop.shopName,
                    style: SrTypography.label.copyWith(color: sr.foreground),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SrSpacing.md),
            Wrap(
              spacing: SrSpacing.sm,
              runSpacing: SrSpacing.sm,
              children: <Widget>[
                VendorRetailerStatusBadge(status: shop.shopStatus),
              ],
            ),
            const SizedBox(height: SrSpacing.md),
            _ShopFact(label: 'Code', value: shop.shopCode),
            _ShopFact(label: 'City', value: shop.city),
            _ShopFact(label: 'Country', value: shop.countryCode),
          ],
        ),
      ),
    );
  }
}

/// One nullable shop column, labelled.
///
/// Rendered even when absent, so the reader learns that the Retailer did not
/// record a value rather than wondering whether the app dropped one.
class _ShopFact extends StatelessWidget {
  const _ShopFact({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final bool present = value != null;

    return Padding(
      padding: const EdgeInsets.only(top: SrSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: SrTypography.caption.copyWith(color: sr.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value ?? notRecorded,
              style: SrTypography.caption.copyWith(
                color: present ? sr.textSecondary : sr.textMuted,
                fontStyle: present ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
