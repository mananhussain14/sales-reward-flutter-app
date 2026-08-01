import 'package:flutter/material.dart';

import '../../../../core/design/design.dart';
import '../../../../core/widgets/widgets.dart';
import 'campaign_copy.dart';

/// The prominent zero-eligible-product notice, for a **detail** screen.
///
/// ## When it appears
///
/// Only when `CampaignOffer.showsEmptyProductWarning` is true: the count is
/// exactly zero **and** the campaign is `ACTIVE` or `SCHEDULED`. A finished,
/// paused or cancelled campaign with no eligible products gets nothing, because
/// it cannot reward anything either way and a warning there would imply a
/// consequence that does not follow.
///
/// It never appears above zero. One eligible product is not a problem worth a
/// warning, and a notice that fired at low counts would train readers to ignore
/// the one that matters.
///
/// ## Three channels, not colour
///
/// [SrAlert] renders a warning **icon**, a bold **title** and the full sentence,
/// on an amber field. Any one of the icon, the title or the body carries the
/// meaning on its own, so a reader who cannot perceive the tone loses nothing.
///
/// It is also a live region, which is what makes a screen reader announce it on
/// arrival — **once**. This widget is used on the detail screen only, where
/// there is exactly one. The card wears [CampaignCardEmptyProductsNote]
/// instead, which is silent: a card's whole content is already spoken as one
/// label, and a second live region per card would announce the same warning
/// repeatedly down a list.
class CampaignEmptyProductsNotice extends StatelessWidget {
  const CampaignEmptyProductsNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return const SrAlert(
      tone: SrAlertTone.warning,
      title: CampaignCopy.noProductsTitle,
      message: CampaignCopy.noProductsBody,
    );
  }
}

/// The compact zero-eligible-product note, for a **card**.
///
/// The same fact in fewer words, so a list of cards stays scannable while still
/// carrying the warning where the campaign is — the milestone asks for it on the
/// card *where practical*, and this is what practical looks like at card size.
///
/// Deliberately **not** a live region and deliberately not announced on its own:
/// the card that owns it excludes its children from the semantics tree and
/// speaks one label that already ends with this sentence. Two announcements per
/// card, times a list, is the "announced repeatedly" failure the accessibility
/// requirement names.
///
/// Icon **and** text, on an amber field. Colour is the third channel, never the
/// only one.
class CampaignCardEmptyProductsNote extends StatelessWidget {
  const CampaignCardEmptyProductsNote({super.key});

  @override
  Widget build(BuildContext context) {
    final SrToneColors colors = context.sr.tone(SrTone.amber);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: SrSpacing.md,
        vertical: SrSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(SrRadii.control),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: SrSpacing.xxs),
            child: Icon(
              Icons.warning_amber_rounded,
              size: 14,
              color: colors.foreground,
            ),
          ),
          const SizedBox(width: SrSpacing.sm),
          Expanded(
            child: Text(
              CampaignCopy.noProductsCardNote,
              style: SrTypography.caption.copyWith(color: colors.alertText),
            ),
          ),
        ],
      ),
    );
  }
}
