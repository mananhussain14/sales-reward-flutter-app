import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/retailer_read_problem.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_lifecycle_state.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_product.dart';
import 'package:sale_reward/features/campaigns/domain/entities/retailer_campaign.dart';
import 'package:sale_reward/features/campaigns/domain/repositories/retailer_campaign_repository.dart';
import 'package:sale_reward/features/campaigns/domain/repositories/staff_campaign_repository.dart';
import 'package:sale_reward/features/campaigns/presentation/shared/campaign_detail_cubit.dart';
import 'package:sale_reward/features/campaigns/presentation/shared/campaign_list_cubit.dart';
import 'package:sale_reward/features/campaigns/presentation/shared/campaign_presentation.dart';

import '../../support/campaign_fakes.dart';

void main() {
  // -------------------------------------------------------------------------
  group('the campaign list cubit', () {
    test('loadOnce reads once, and returning reads nothing', () async {
      final FakeRetailerCampaignRepository repository =
          FakeRetailerCampaignRepository();
      final RetailerCampaignListCubit cubit = RetailerCampaignListCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.loadOnce();
      expect(repository.callCount, 1);

      // The whole point of `loadOnce`: opening an already-loaded tab issues
      // nothing, and Refresh is the way to re-read.
      await cubit.loadOnce();
      expect(repository.callCount, 1);
    });

    test('a duplicate refresh while one is in flight is suppressed', () async {
      final FakeRetailerCampaignRepository repository =
          FakeRetailerCampaignRepository()..manual = true;
      final RetailerCampaignListCubit cubit = RetailerCampaignListCubit(
        repository,
      );
      addTearDown(cubit.close);

      unawaited(cubit.load());
      unawaited(cubit.refresh());
      unawaited(cubit.refresh());

      // No request storm: three calls, one round trip.
      expect(repository.callCount, 1);
      repository.complete();
    });

    test(
      'a failure keeps rows already on screen, and marks them stale',
      () async {
        final FakeRetailerCampaignRepository repository =
            FakeRetailerCampaignRepository();
        final RetailerCampaignListCubit cubit = RetailerCampaignListCubit(
          repository,
        );
        addTearDown(cubit.close);

        await cubit.load();
        expect(cubit.state.campaigns, hasLength(1));

        repository.listResult = const RetailerCampaignsFailed(
          RetailerReadProblem.network,
        );
        await cubit.refresh();

        expect(cubit.state.isStale, isTrue);
        expect(cubit.state.hasFailedOutright, isFalse);
        // The rows stay: they are still the last thing the backend actually said.
        expect(cubit.state.campaigns, hasLength(1));
      },
    );

    test(
      'a first-load failure is an outright failure, never an empty list',
      () async {
        final FakeRetailerCampaignRepository repository =
            FakeRetailerCampaignRepository()
              ..listResult = const RetailerCampaignsFailed(
                RetailerReadProblem.denied,
              );
        final RetailerCampaignListCubit cubit = RetailerCampaignListCubit(
          repository,
        );
        addTearDown(cubit.close);

        await cubit.load();

        expect(cubit.state.hasFailedOutright, isTrue);
        expect(cubit.state.isEmpty, isFalse);
        expect(cubit.state.campaigns, isNull);
        expect(cubit.state.problem, RetailerReadProblem.denied);
      },
    );

    test('an empty list is a real answer, distinct from a failure', () async {
      final FakeRetailerCampaignRepository repository =
          FakeRetailerCampaignRepository()
            ..listResult = const RetailerCampaignsLoaded(<RetailerCampaign>[]);
      final RetailerCampaignListCubit cubit = RetailerCampaignListCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.isEmpty, isTrue);
      expect(cubit.state.hasFailedOutright, isFalse);
      expect(cubit.state.problem, isNull);
    });

    test('clear drops the campaigns and advances the request token', () async {
      final FakeRetailerCampaignRepository repository =
          FakeRetailerCampaignRepository();
      final RetailerCampaignListCubit cubit = RetailerCampaignListCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.load();
      final int before = cubit.requestToken;

      cubit.clear();

      expect(cubit.state.campaigns, isNull);
      expect(cubit.state.phase, CampaignListPhase.initial);
      expect(cubit.requestToken, greaterThan(before));
      // The audience survives: a cubit does not change which contract it reads.
      expect(cubit.state.audience, CampaignAudience.retailerOwner);
    });

    test(
      'a stale answer landing after clear cannot repopulate the list',
      () async {
        final FakeRetailerCampaignRepository repository =
            FakeRetailerCampaignRepository()..manual = true;
        final RetailerCampaignListCubit cubit = RetailerCampaignListCubit(
          repository,
        );
        addTearDown(cubit.close);

        unawaited(cubit.load());
        cubit.clear();
        repository.complete();
        await Future<void>.delayed(Duration.zero);

        // The previous identity's campaigns must not land on the new session.
        expect(cubit.state.campaigns, isNull);
        expect(cubit.state.phase, CampaignListPhase.initial);
      },
    );

    test('the Sales Staff cubit carries the seller audience', () async {
      final FakeStaffCampaignRepository repository =
          FakeStaffCampaignRepository();
      final SalesStaffCampaignListCubit cubit = SalesStaffCampaignListCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.audience, CampaignAudience.salesStaff);
      // And no Vendor name, because the contract returns none.
      expect(cubit.state.campaigns!.single.vendorName, isNull);
    });

    test('a Retailer Owner campaign carries its Vendor name', () async {
      final FakeRetailerCampaignRepository repository =
          FakeRetailerCampaignRepository();
      final RetailerCampaignListCubit cubit = RetailerCampaignListCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.campaigns!.single.vendorName, 'Northwind Trading');
    });
  });

  // -------------------------------------------------------------------------
  group('section grouping', () {
    test('groups every lifecycle state, and omits empty sections', () async {
      final FakeRetailerCampaignRepository repository =
          FakeRetailerCampaignRepository()
            ..nextCampaigns =
                <CampaignLifecycleState>[
                  CampaignLifecycleState.active,
                  CampaignLifecycleState.scheduled,
                  CampaignLifecycleState.paused,
                  CampaignLifecycleState.ended,
                  CampaignLifecycleState.cancelled,
                ].map((CampaignLifecycleState state) {
                  return exampleRetailerCampaign(
                    offer: exampleOffer(lifecycleState: state),
                  );
                }).toList();

      final RetailerCampaignListCubit cubit = RetailerCampaignListCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.load();

      expect(
        cubit.state.sections.map((CampaignSection s) => s.kind).toList(),
        <CampaignSectionKind>[
          CampaignSectionKind.runningNow,
          CampaignSectionKind.startingSoon,
          CampaignSectionKind.paused,
          CampaignSectionKind.finished,
          CampaignSectionKind.cancelled,
        ],
      );
      // Never rendered because it is never populated, but the switch has a
      // branch for it so nothing can be silently dropped.
      expect(
        cubit.state.sections.map((CampaignSection s) => s.kind),
        isNot(contains(CampaignSectionKind.notPublished)),
      );
    });

    test('a seller only ever populates two sections', () async {
      final FakeStaffCampaignRepository repository =
          FakeStaffCampaignRepository()
            ..nextCampaigns =
                <CampaignLifecycleState>[
                  CampaignLifecycleState.active,
                  CampaignLifecycleState.scheduled,
                ].map((CampaignLifecycleState state) {
                  return exampleStaffCampaign(
                    offer: exampleOffer(lifecycleState: state),
                  );
                }).toList();

      final SalesStaffCampaignListCubit cubit = SalesStaffCampaignListCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.load();

      expect(
        cubit.state.sections.map((CampaignSection s) => s.kind).toList(),
        <CampaignSectionKind>[
          CampaignSectionKind.runningNow,
          CampaignSectionKind.startingSoon,
        ],
      );
    });

    test('the backend order is preserved inside a section', () async {
      // The two contracts order differently on purpose — the Owner's is
      // `starts_at desc` and the seller's is `starts_at` — so this must
      // partition without sorting.
      final FakeRetailerCampaignRepository repository =
          FakeRetailerCampaignRepository()
            ..nextCampaigns = <String>['Zulu', 'Alpha', 'Mike']
                .map(
                  (String name) =>
                      exampleRetailerCampaign(offer: exampleOffer(name: name)),
                )
                .toList();

      final RetailerCampaignListCubit cubit = RetailerCampaignListCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.load();

      expect(
        cubit.state.sections.single.campaigns
            .map((CampaignPresentation c) => c.offer.name)
            .toList(),
        <String>['Zulu', 'Alpha', 'Mike'],
      );
    });

    test('every lifecycle state maps to a section', () {
      // Exhaustiveness in one assertion: no state falls through and vanishes.
      for (final CampaignLifecycleState state
          in CampaignLifecycleState.values) {
        expect(sectionKindFor(state), isNotNull, reason: state.name);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('the campaign detail cubit', () {
    test('open reads once and is idempotent for the same id', () async {
      final FakeRetailerCampaignRepository repository =
          FakeRetailerCampaignRepository();
      final RetailerCampaignDetailCubit cubit = RetailerCampaignDetailCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.open(campaignIdA);
      expect(repository.detailCallCount, 1);

      await cubit.open(campaignIdA);
      expect(repository.detailCallCount, 1);
    });

    test('a different id always re-reads', () async {
      final FakeRetailerCampaignRepository repository =
          FakeRetailerCampaignRepository();
      final RetailerCampaignDetailCubit cubit = RetailerCampaignDetailCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.open(campaignIdA);
      await cubit.open(campaignIdB);

      expect(repository.requestedCampaignIds, <String>[
        campaignIdA,
        campaignIdB,
      ]);
    });

    test('the id is sent verbatim and nothing else is', () async {
      final FakeRetailerCampaignRepository repository =
          FakeRetailerCampaignRepository();
      final RetailerCampaignDetailCubit cubit = RetailerCampaignDetailCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.open(campaignIdA);

      expect(repository.requestedCampaignIds, <String>[campaignIdA]);
    });

    test('Missing is notFound, not a failure, and offers no problem', () async {
      final FakeRetailerCampaignRepository repository =
          FakeRetailerCampaignRepository()
            ..detailResult = const RetailerCampaignDetailMissing();
      final RetailerCampaignDetailCubit cubit = RetailerCampaignDetailCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.open(campaignIdA);

      expect(cubit.state.phase, CampaignDetailPhase.notFound);
      expect(cubit.state.problem, isNull);
      expect(cubit.state.campaign, isNull);
    });

    test('a failure is distinct from notFound', () async {
      final FakeRetailerCampaignRepository repository =
          FakeRetailerCampaignRepository()
            ..detailResult = const RetailerCampaignDetailFailed(
              RetailerReadProblem.timeout,
            );
      final RetailerCampaignDetailCubit cubit = RetailerCampaignDetailCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.open(campaignIdA);

      expect(cubit.state.phase, CampaignDetailPhase.failed);
      expect(cubit.state.problem, RetailerReadProblem.timeout);
    });

    test('a loaded campaign carries its products', () async {
      final FakeRetailerCampaignRepository repository =
          FakeRetailerCampaignRepository();
      final RetailerCampaignDetailCubit cubit = RetailerCampaignDetailCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.open(campaignIdA);

      expect(cubit.state.phase, CampaignDetailPhase.ready);
      expect(cubit.state.products, hasLength(2));
    });

    test('an empty product list is a real answer, not a failure', () async {
      final FakeRetailerCampaignRepository repository =
          FakeRetailerCampaignRepository()
            ..detailResult = RetailerCampaignDetailLoaded(
              campaign: exampleRetailerCampaign(
                offer: exampleOffer(eligibleProductCount: 0),
              ),
              products: const <CampaignProduct>[],
            );
      final RetailerCampaignDetailCubit cubit = RetailerCampaignDetailCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.open(campaignIdA);

      expect(cubit.state.phase, CampaignDetailPhase.ready);
      expect(cubit.state.products, isEmpty);
      expect(
        cubit.state.campaign!.offer.productEligibility.eligibleProductCount,
        0,
      );
    });

    test(
      'opening a second campaign does not show the first for a frame',
      () async {
        final FakeRetailerCampaignRepository repository =
            FakeRetailerCampaignRepository();
        final RetailerCampaignDetailCubit cubit = RetailerCampaignDetailCubit(
          repository,
        );
        addTearDown(cubit.close);

        await cubit.open(campaignIdA);
        final Future<void> second = cubit.open(campaignIdB);

        // While the second read is in flight the first campaign is already gone:
        // one campaign's reward must never appear under another's name.
        expect(cubit.state.phase, CampaignDetailPhase.loading);
        expect(cubit.state.campaign, isNull);
        expect(cubit.state.products, isEmpty);
        await second;
      },
    );

    test('a second id is not dropped while the first is still loading', () async {
      // The cubit is provided at the shell and shared by every detail route, so
      // suppressing a DIFFERENT id here would leave one campaign's terms on
      // screen under another campaign's address.
      final FakeRetailerCampaignRepository repository =
          FakeRetailerCampaignRepository();
      final RetailerCampaignDetailCubit cubit = RetailerCampaignDetailCubit(
        repository,
      );
      addTearDown(cubit.close);

      final Future<void> first = cubit.open(campaignIdA);
      final Future<void> second = cubit.open(campaignIdB);
      await Future.wait(<Future<void>>[first, second]);

      expect(repository.requestedCampaignIds, <String>[
        campaignIdA,
        campaignIdB,
      ]);
      // The second id is the one held, and the first read's answer was dropped
      // on arrival by the request token rather than overwriting it.
      expect(cubit.state.campaignId, campaignIdB);
      expect(cubit.state.phase, CampaignDetailPhase.ready);
    });

    test('a repeat of the id already loading is still suppressed', () async {
      final FakeRetailerCampaignRepository repository =
          FakeRetailerCampaignRepository();
      final RetailerCampaignDetailCubit cubit = RetailerCampaignDetailCubit(
        repository,
      );
      addTearDown(cubit.close);

      final Future<void> first = cubit.open(campaignIdA);
      final Future<void> repeat = cubit.open(campaignIdA);
      await Future.wait(<Future<void>>[first, repeat]);

      expect(repository.detailCallCount, 1);
    });

    test('clear drops the campaign and the open id', () async {
      final FakeRetailerCampaignRepository repository =
          FakeRetailerCampaignRepository();
      final RetailerCampaignDetailCubit cubit = RetailerCampaignDetailCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.open(campaignIdA);
      cubit.clear();

      expect(cubit.state.campaign, isNull);
      expect(cubit.state.campaignId, isNull);
      expect(cubit.state.phase, CampaignDetailPhase.initial);
    });

    test('refresh before anything is open reads nothing', () async {
      final FakeRetailerCampaignRepository repository =
          FakeRetailerCampaignRepository();
      final RetailerCampaignDetailCubit cubit = RetailerCampaignDetailCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.refresh();

      expect(repository.detailCallCount, 0);
    });

    test('a seller reaches the same notFound for a paused campaign', () async {
      final FakeStaffCampaignRepository repository =
          FakeStaffCampaignRepository()
            ..detailResult = const StaffCampaignDetailMissing();
      final SalesStaffCampaignDetailCubit cubit = SalesStaffCampaignDetailCubit(
        repository,
      );
      addTearDown(cubit.close);

      await cubit.open(campaignIdA);

      expect(cubit.state.phase, CampaignDetailPhase.notFound);
      expect(cubit.state.audience, CampaignAudience.salesStaff);
    });
  });
}
