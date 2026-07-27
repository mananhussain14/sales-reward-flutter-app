import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/retailer_shop.dart';
import 'retailer_shops_copy.dart';

/// One shop.
///
/// ## Deliberately not tappable
///
/// There is **no `onTap`, no chevron, no "View details", no edit control and no
/// overflow menu** — not disabled ones, none at all. The contract returns no
/// `shop_id`, so there is nothing to address and no detail screen to open; an
/// affordance here would be a promise the backend cannot keep, and a disabled
/// one would imply the feature exists and is merely switched off.
///
/// `SrCard` is used without its `onTap`, so it renders no ink response and no
/// hover state — the card reads as information, not as a control.
///
/// ## Absent fields are omitted, never faked
///
/// `shop_code`, `city` and `country_code` are all nullable in the schema. A null
/// one is left out of the card entirely rather than rendered as an empty row or
/// a dash: an absent code is a fact about the shop, and inventing a placeholder
/// for it would make every incompletely-recorded shop look identical.
///
/// ## Accessibility
///
/// The whole card is one semantics node reading a single sentence — name,
/// status, then whichever optional fields are present — rather than four
/// fragments a screen reader would announce as unrelated strings. Status is
/// announced by its **label**, never by colour.
class RetailerShopCard extends StatelessWidget {
  const RetailerShopCard({super.key, required this.shop});

  final RetailerShop shop;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    final List<({String label, String value})> details =
        <({String label, String value})>[
          if (shop.code != null)
            (label: RetailerShopsCopy.codeLabel, value: shop.code!),
          if (shop.city != null)
            (label: RetailerShopsCopy.cityLabel, value: shop.city!),
          if (shop.countryCode != null)
            (label: RetailerShopsCopy.countryLabel, value: shop.countryCode!),
        ];

    return Semantics(
      label: _semanticLabel(details),
      excludeSemantics: true,
      child: SrCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: SrSpacing.xxs),
                  child: Icon(
                    Icons.storefront_rounded,
                    size: 18,
                    color: sr.textMuted,
                  ),
                ),
                const SizedBox(width: SrSpacing.md),
                Expanded(
                  child: Text(
                    shop.name,
                    style: SrTypography.sectionTitle.copyWith(
                      color: sr.foreground,
                    ),
                  ),
                ),
                const SizedBox(width: SrSpacing.sm),
                SrBadge(label: shop.status.label, tone: _tone(shop.status)),
              ],
            ),
            if (details.isNotEmpty) ...<Widget>[
              const SizedBox(height: SrSpacing.lg),
              Wrap(
                spacing: SrSpacing.xl,
                runSpacing: SrSpacing.sm,
                children: <Widget>[
                  for (final ({String label, String value}) detail in details)
                    _Detail(label: detail.label, value: detail.value),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _semanticLabel(List<({String label, String value})> details) {
    final StringBuffer buffer = StringBuffer('${shop.name}. ')
      ..write('${shop.status.label}.');
    for (final ({String label, String value}) detail in details) {
      buffer.write(' ${detail.label}: ${detail.value}.');
    }
    return buffer.toString();
  }

  static SrTone _tone(RetailerShopStatus status) => switch (status) {
    RetailerShopStatus.active => SrTone.emerald,
    RetailerShopStatus.suspended => SrTone.amber,
    RetailerShopStatus.deactivated => SrTone.red,
    RetailerShopStatus.unknown => SrTone.slate,
  };
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: SrTypography.caption.copyWith(color: sr.textMuted)),
        const SizedBox(height: SrSpacing.xxs),
        Text(value, style: SrTypography.body.copyWith(color: sr.foreground)),
      ],
    );
  }
}
