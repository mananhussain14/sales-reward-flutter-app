import 'package:flutter/material.dart';

import '../../../../core/design/design.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/campaign_lifecycle_state.dart';
import 'campaign_copy.dart';

/// The lifecycle pill.
///
/// ## Why not `SrStatusBadge`
///
/// That widget maps a **raw backend token** through a fixed table and renders
/// "Unknown" for anything it does not recognise. Neither half fits here:
/// `CampaignLifecycleState` is already a parsed enum, so there is no token to
/// map and no unknown case to fall back to — an unreadable state failed the read
/// long before it reached a widget.
///
/// Its table is also wrong for this vocabulary. `PAUSED` is not in it at all,
/// and `ACTIVE` there means "in good standing" — a Retailer, a membership, a
/// product — whereas here it means "sales count toward this right now", which
/// wants different words.
///
/// ## Status is never carried by colour alone
///
/// Every state renders a **label** and an **icon** as well as a tone, so the
/// three channels agree and any one of them is sufficient. The detail screen
/// additionally states the same fact in a full sentence — see
/// [CampaignCopy.lifecycleExplanation] — so a reader who cannot resolve a pill
/// at all still gets it in prose.
class CampaignStatusBadge extends StatelessWidget {
  const CampaignStatusBadge({super.key, required this.state});

  final CampaignLifecycleState state;

  /// The tone for [state].
  ///
  /// [CampaignLifecycleState.ended] and [CampaignLifecycleState.cancelled] are
  /// deliberately given **different** tones and different icons: both are over,
  /// but one ran its course and the other was stopped, and a Retailer Owner
  /// reviewing what happened needs to tell them apart at a glance.
  static SrTone toneFor(CampaignLifecycleState state) => switch (state) {
    CampaignLifecycleState.active => SrTone.emerald,
    CampaignLifecycleState.scheduled => SrTone.blue,
    CampaignLifecycleState.paused => SrTone.amber,
    CampaignLifecycleState.ended => SrTone.slate,
    CampaignLifecycleState.cancelled => SrTone.red,
    CampaignLifecycleState.draft => SrTone.slate,
  };

  /// The icon for [state]. Never the only channel — see the class doc.
  static IconData iconFor(CampaignLifecycleState state) => switch (state) {
    CampaignLifecycleState.active => Icons.play_arrow_rounded,
    CampaignLifecycleState.scheduled => Icons.schedule_rounded,
    CampaignLifecycleState.paused => Icons.pause_rounded,
    CampaignLifecycleState.ended => Icons.flag_outlined,
    CampaignLifecycleState.cancelled => Icons.block_rounded,
    CampaignLifecycleState.draft => Icons.edit_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return SrBadge(
      label: CampaignCopy.lifecycleLabel(state),
      tone: toneFor(state),
      icon: iconFor(state),
    );
  }
}
