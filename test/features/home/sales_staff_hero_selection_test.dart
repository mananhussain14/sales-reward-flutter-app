import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_lifecycle_state.dart';
import 'package:sale_reward/features/campaigns/presentation/shared/campaign_presentation.dart';
import 'package:sale_reward/features/home/presentation/sales_staff/widgets/sales_staff_opportunity.dart';
import 'package:sale_reward/features/rewards/domain/entities/campaign_target_progress.dart';

import '../../support/campaign_fakes.dart';
import '../../support/earnings_fakes.dart';

/// The rule that decides which campaign the Sales Staff home leads with.
///
/// It is a **presentation** rule and these tests exist to keep it one: three
/// ordered filters over the order the backend already returned, with nothing
/// scored, weighted or compared against another campaign. A test that started
/// asserting "the best campaign" would be describing a recommendation engine
/// this application does not have and has no contract to build.
void main() {
  CampaignPresentation campaign({
    required String id,
    required String name,
    CampaignLifecycleState state = CampaignLifecycleState.active,
  }) => CampaignPresentation.staff(
    exampleStaffCampaign(
      offer: exampleOffer(campaignId: id, name: name, lifecycleState: state),
    ),
  );

  SalesStaffOpportunity opportunity({
    required String id,
    required String name,
    CampaignLifecycleState state = CampaignLifecycleState.active,
    CampaignTargetProgress? progress,
  }) => SalesStaffOpportunity(
    campaign: campaign(id: id, name: name, state: state),
    progress: progress,
  );

  group('buildOpportunities', () {
    test('joins progress on the campaign id, never on the name', () {
      final CampaignTargetProgress row = exampleTargetProgress(
        campaignId: campaignIdB,
        campaignName: 'A completely different name',
      );

      final List<SalesStaffOpportunity> built =
          buildOpportunities(<CampaignPresentation>[
            campaign(id: campaignIdA, name: 'First'),
            campaign(id: campaignIdB, name: 'Second'),
          ], (String id) => id == campaignIdB ? row : null);

      expect(built.first.progress, isNull);
      expect(built.last.progress, row);
    });

    test('preserves the order the backend returned', () {
      final List<SalesStaffOpportunity> built =
          buildOpportunities(<CampaignPresentation>[
            campaign(id: campaignIdA, name: 'First'),
            campaign(id: campaignIdB, name: 'Second'),
          ], (_) => null);

      expect(
        built.map((SalesStaffOpportunity o) => o.campaign.offer.name),
        <String>['First', 'Second'],
      );
    });
  });

  group('selectHeroOpportunity', () {
    test('nothing to show returns null', () {
      expect(selectHeroOpportunity(const <SalesStaffOpportunity>[]), isNull);
    });

    test('prefers the first running campaign that has a target', () {
      final SalesStaffOpportunity withTarget = opportunity(
        id: campaignIdB,
        name: 'Has a target',
        progress: exampleTargetProgress(campaignId: campaignIdB),
      );

      final SalesStaffOpportunity? hero = selectHeroOpportunity(
        <SalesStaffOpportunity>[
          opportunity(id: campaignIdA, name: 'Per unit, listed first'),
          withTarget,
        ],
      );

      expect(hero, withTarget);
    });

    test('a target that is already reached is not skipped', () {
      // Preferring an unreached target over a reached one would be a judgement
      // about which reward deserves attention, and the contract gives no basis
      // for one. First is first.
      final SalesStaffOpportunity reached = opportunity(
        id: campaignIdA,
        name: 'Reached',
        progress: exampleTargetProgress(
          campaignId: campaignIdA,
          progressUnits: 5,
          targetUnits: 3,
          targetReached: true,
          bonusAwardedToMe: true,
        ),
      );

      final SalesStaffOpportunity? hero =
          selectHeroOpportunity(<SalesStaffOpportunity>[
            reached,
            opportunity(
              id: campaignIdB,
              name: 'Not reached',
              progress: exampleTargetProgress(campaignId: campaignIdB),
            ),
          ]);

      expect(hero, reached);
    });

    test('falls back to the first running campaign when none has a target', () {
      final SalesStaffOpportunity first = opportunity(
        id: campaignIdA,
        name: 'Per unit',
      );

      final SalesStaffOpportunity? hero = selectHeroOpportunity(
        <SalesStaffOpportunity>[
          first,
          opportunity(id: campaignIdB, name: 'Another per unit'),
        ],
      );

      expect(hero, first);
    });

    test('a scheduled campaign never outranks a running one', () {
      final SalesStaffOpportunity running = opportunity(
        id: campaignIdB,
        name: 'Running',
      );

      final SalesStaffOpportunity? hero =
          selectHeroOpportunity(<SalesStaffOpportunity>[
            opportunity(
              id: campaignIdA,
              name: 'Starting soon',
              state: CampaignLifecycleState.scheduled,
            ),
            running,
          ]);

      expect(hero, running);
    });

    test('a scheduled campaign is shown when nothing is running', () {
      final SalesStaffOpportunity scheduled = opportunity(
        id: campaignIdA,
        name: 'Starting soon',
        state: CampaignLifecycleState.scheduled,
      );

      expect(
        selectHeroOpportunity(<SalesStaffOpportunity>[scheduled]),
        scheduled,
      );
    });

    test('a scheduled campaign with progress is still not preferred', () {
      // The first filter is "running AND has a target", not "has a target".
      final SalesStaffOpportunity running = opportunity(
        id: campaignIdB,
        name: 'Running, no target',
      );

      final SalesStaffOpportunity? hero =
          selectHeroOpportunity(<SalesStaffOpportunity>[
            opportunity(
              id: campaignIdA,
              name: 'Scheduled with a target',
              state: CampaignLifecycleState.scheduled,
              progress: exampleTargetProgress(campaignId: campaignIdA),
            ),
            running,
          ]);

      expect(hero, running);
    });
  });

  group('remainingOpportunities', () {
    test('drops exactly the hero, keeping the order', () {
      final SalesStaffOpportunity a = opportunity(
        id: campaignIdA,
        name: 'First',
      );
      final SalesStaffOpportunity b = opportunity(
        id: campaignIdB,
        name: 'Second',
      );

      expect(
        remainingOpportunities(<SalesStaffOpportunity>[a, b], a),
        <SalesStaffOpportunity>[b],
      );
    });

    test('no hero keeps everything', () {
      final SalesStaffOpportunity a = opportunity(
        id: campaignIdA,
        name: 'First',
      );

      expect(
        remainingOpportunities(<SalesStaffOpportunity>[a], null),
        <SalesStaffOpportunity>[a],
      );
    });
  });
}
