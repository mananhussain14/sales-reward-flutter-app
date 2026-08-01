import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_lifecycle_state.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_measurement.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_product_eligibility.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_reward.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_stacking_mode.dart';
import 'package:sale_reward/features/campaigns/presentation/shared/campaign_copy.dart';
import 'package:sale_reward/features/campaigns/presentation/shared/campaign_presentation.dart';

import '../../support/campaign_fakes.dart';

/// Every sentence these screens render, and the one rule they all obey: **no
/// backend token is ever interpolated.**
void main() {
  // -------------------------------------------------------------------------
  group('reward wording', () {
    test('a capped per-unit rule', () {
      expect(
        CampaignCopy.rewardSentence(
          exampleOffer(
            reward: const CampaignPerUnitReward(
              coinsPerUnit: 10,
              maxRewardCoins: 100,
              metric: CampaignMetricType.unitsSold,
            ),
          ),
          CampaignAudience.salesStaff,
        ),
        'Earn 10 coins per eligible unit, up to 100 coins.',
      );
    });

    test('an uncapped per-unit rule omits the cap clause', () {
      expect(
        CampaignCopy.rewardSentence(
          exampleOffer(
            reward: const CampaignPerUnitReward(
              coinsPerUnit: 10,
              maxRewardCoins: null,
              metric: CampaignMetricType.unitsSold,
            ),
          ),
          CampaignAudience.salesStaff,
        ),
        'Earn 10 coins per eligible unit.',
      );
    });

    test('a rate of one is singular', () {
      expect(
        CampaignCopy.rewardSentence(
          exampleOffer(
            reward: const CampaignPerUnitReward(
              coinsPerUnit: 1,
              maxRewardCoins: null,
              metric: CampaignMetricType.unitsSold,
            ),
          ),
          CampaignAudience.salesStaff,
        ),
        'Earn 1 coin per eligible unit.',
      );
    });

    test('an individual target, to a seller', () {
      expect(
        CampaignCopy.rewardSentence(
          exampleOffer(
            performanceScope: CampaignPerformanceScope.individualStaff,
            reward: const CampaignTargetReward(
              thresholdUnits: 25,
              rewardCoins: 2500,
              maxRewardCoins: null,
              metric: CampaignMetricType.unitsSold,
            ),
          ),
          CampaignAudience.salesStaff,
        ),
        'Reach 25 eligible units to qualify for the configured 2,500-coin '
        'reward.',
      );
    });

    test('an individual target, to an Owner, is written for a non-seller', () {
      expect(
        CampaignCopy.rewardSentence(
          exampleOffer(
            performanceScope: CampaignPerformanceScope.individualStaff,
            reward: const CampaignTargetReward(
              thresholdUnits: 25,
              rewardCoins: 2500,
              maxRewardCoins: null,
              metric: CampaignMetricType.unitsSold,
            ),
          ),
          CampaignAudience.retailerOwner,
        ),
        'A Sales Staff member who reaches 25 eligible units qualifies for the '
        'configured 2,500-coin reward.',
      );
    });

    test('a Retailer-team target reads the same way to both roles', () {
      const String expected =
          'When your Retailer reaches 25 eligible units, contributing Sales '
          'Staff share the configured 2,500-coin reward according to the '
          'campaign rules.';

      for (final CampaignAudience audience in CampaignAudience.values) {
        expect(
          CampaignCopy.rewardSentence(
            exampleOffer(
              performanceScope: CampaignPerformanceScope.retailerTeam,
              reward: const CampaignTargetReward(
                thresholdUnits: 25,
                rewardCoins: 2500,
                maxRewardCoins: null,
                metric: CampaignMetricType.unitsSold,
              ),
            ),
            audience,
          ),
          expected,
          reason: audience.name,
        );
      }
    });

    test('a capped target bonus states the campaign ceiling separately', () {
      expect(
        CampaignCopy.rewardSentence(
          exampleOffer(
            reward: const CampaignTargetReward(
              thresholdUnits: 25,
              rewardCoins: 2500,
              maxRewardCoins: 10000,
              metric: CampaignMetricType.unitsSold,
            ),
          ),
          CampaignAudience.salesStaff,
        ),
        endsWith('This campaign pays no more than 10,000 coins in total.'),
      );
    });

    test('a threshold of one is singular', () {
      expect(
        CampaignCopy.rewardSentence(
          exampleOffer(
            reward: const CampaignTargetReward(
              thresholdUnits: 1,
              rewardCoins: 500,
              maxRewardCoins: null,
              metric: CampaignMetricType.unitsSold,
            ),
          ),
          CampaignAudience.salesStaff,
        ),
        contains('1 eligible unit '),
      );
    });

    test('no reward sentence claims a result', () {
      // The contract returns the OFFER. Nothing here says what has been sold,
      // earned, accrued, or how far along anyone is.
      for (final CampaignAudience audience in CampaignAudience.values) {
        for (final CampaignReward reward in <CampaignReward>[
          const CampaignPerUnitReward(
            coinsPerUnit: 10,
            maxRewardCoins: 100,
            metric: CampaignMetricType.unitsSold,
          ),
          const CampaignTargetReward(
            thresholdUnits: 25,
            rewardCoins: 2500,
            maxRewardCoins: null,
            metric: CampaignMetricType.unitsSold,
          ),
        ]) {
          final String sentence = CampaignCopy.rewardSentence(
            exampleOffer(reward: reward),
            audience,
          );
          for (final String forbidden in <String>[
            'earned',
            'so far',
            'progress',
            'balance',
            'remaining',
            'you have',
          ]) {
            expect(
              sentence.toLowerCase(),
              isNot(contains(forbidden)),
              reason: '"$forbidden" in: $sentence',
            );
          }
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('measurement wording', () {
    test('individual, to a seller — the specified sentence, verbatim', () {
      expect(
        CampaignCopy.measurementSentence(
          CampaignPerformanceScope.individualStaff,
          CampaignAudience.salesStaff,
        ),
        'Your eligible sales are measured separately.',
      );
    });

    test('Retailer team, to a seller — the specified sentence, verbatim', () {
      expect(
        CampaignCopy.measurementSentence(
          CampaignPerformanceScope.retailerTeam,
          CampaignAudience.salesStaff,
        ),
        'Eligible Sales Staff sales in your Retailer contribute to the shared '
        'Retailer target.',
      );
    });

    test('an Owner is not addressed as though they sell', () {
      final String owner = CampaignCopy.measurementSentence(
        CampaignPerformanceScope.individualStaff,
        CampaignAudience.retailerOwner,
      );

      expect(owner, contains('Sales Staff'));
      expect(owner, isNot(startsWith('Your eligible sales')));
    });

    test('the short labels never render a backend token', () {
      expect(
        CampaignCopy.measurementLabel(CampaignPerformanceScope.individualStaff),
        'Individual',
      );
      expect(
        CampaignCopy.measurementLabel(CampaignPerformanceScope.retailerTeam),
        'Retailer team',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('product eligibility wording', () {
    test('selected products / snapshot — the specified sentence', () {
      expect(
        CampaignCopy.eligibilitySentence(CampaignProductScope.selectedProducts),
        'Only the products selected for this campaign version count. '
        'Eligibility was frozen when the campaign was published.',
      );
    });

    test('all eligible products / live-temporal — the specified sentence', () {
      expect(
        CampaignCopy.eligibilitySentence(
          CampaignProductScope.allEligibleProducts,
        ),
        'Products assigned to your Retailer count while they are eligible. '
        'Later assignment changes affect later sales, not earlier sales.',
      );
    });

    test('the product count is pluralised, and zero is named', () {
      expect(CampaignCopy.productCountLabel(0), 'No eligible products');
      expect(CampaignCopy.productCountLabel(1), '1 eligible product');
      expect(CampaignCopy.productCountLabel(7), '7 eligible products');
    });
  });

  // -------------------------------------------------------------------------
  group('stacking wording', () {
    test('stackable', () {
      expect(
        CampaignCopy.stackingSentence(CampaignStackingMode.stackable),
        'This campaign can apply at the same time as other campaigns that '
        'also allow it.',
      );
    });

    test('exclusive', () {
      expect(
        CampaignCopy.stackingSentence(CampaignStackingMode.exclusive),
        'This campaign does not combine with other campaigns. Only one '
        'exclusive campaign applies to an eligible sale.',
      );
    });

    test('neither sentence mentions a key or a priority', () {
      // The Vendor's competition configuration is withheld by both contracts,
      // and there is nothing here that could hint at it.
      for (final CampaignStackingMode mode in CampaignStackingMode.values) {
        final String sentence = CampaignCopy.stackingSentence(
          mode,
        ).toLowerCase();
        expect(sentence, isNot(contains('key')));
        expect(sentence, isNot(contains('priority')));
        expect(sentence, isNot(contains('rank')));
      }
    });
  });

  // -------------------------------------------------------------------------
  group('the zero-eligible-product notice', () {
    test('is the approved wording, verbatim', () {
      expect(
        CampaignCopy.noProductsBody,
        'No eligible products are currently assigned to your Retailer for '
        'this campaign. Sales cannot earn coins until an eligible product is '
        'available.',
      );
    });

    test('says "your Retailer", never "you"', () {
      // Eligibility is a fact about the organization's assignments. A seller
      // must not read it as something about their own account.
      expect(CampaignCopy.noProductsBody, contains('your Retailer'));
      expect(CampaignCopy.noProductsCardNote, contains('your Retailer'));
    });

    test('does not imply the reader can repair it, or that anything broke', () {
      for (final String copy in <String>[
        CampaignCopy.noProductsBody,
        CampaignCopy.noProductsCardNote,
      ]) {
        final String lower = copy.toLowerCase();
        for (final String forbidden in <String>[
          'error',
          'broken',
          'invalid',
          'contact',
          'fix',
          'assign a product',
          'try again',
        ]) {
          expect(lower, isNot(contains(forbidden)), reason: forbidden);
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('the calculation-engine notice', () {
    test('is the specified sentence', () {
      expect(
        CampaignCopy.engineNotice,
        'Campaign results and coin calculation will appear when the '
        'calculation engine is connected.',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('no backend token reaches a screen', () {
    test('every lifecycle label is prose, not a code', () {
      for (final CampaignLifecycleState state
          in CampaignLifecycleState.values) {
        final String label = CampaignCopy.lifecycleLabel(state);
        expect(label, isNot(equals(state.code)));
        expect(label, isNot(contains('_')));
        expect(CampaignCopy.lifecycleExplanation(state), isNotEmpty);
      }
    });

    test('every section title is prose', () {
      for (final CampaignSectionKind kind in CampaignSectionKind.values) {
        final String title = CampaignCopy.sectionTitle(kind);
        expect(title, isNotEmpty);
        expect(title, isNot(contains('_')));
      }
    });

    test('every enum label and sentence avoids SCREAMING_SNAKE_CASE', () {
      final List<String> everySentence = <String>[
        for (final CampaignPerformanceScope scope
            in CampaignPerformanceScope.values) ...<String>[
          CampaignCopy.measurementLabel(scope),
          for (final CampaignAudience audience in CampaignAudience.values)
            CampaignCopy.measurementSentence(scope, audience),
        ],
        for (final CampaignProductScope scope
            in CampaignProductScope.values) ...<String>[
          CampaignCopy.eligibilitySentence(scope),
          CampaignCopy.productScopeLabel(scope),
        ],
        for (final CampaignStackingMode mode
            in CampaignStackingMode.values) ...<String>[
          CampaignCopy.stackingSentence(mode),
          CampaignCopy.stackingLabel(mode),
        ],
      ];

      final RegExp token = RegExp(r'\b[A-Z]{2,}(_[A-Z]+)+\b');
      for (final String sentence in everySentence) {
        expect(token.hasMatch(sentence), isFalse, reason: sentence);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('number formatting', () {
    test('groups thousands', () {
      expect(formatCampaignNumber(0), '0');
      expect(formatCampaignNumber(7), '7');
      expect(formatCampaignNumber(999), '999');
      expect(formatCampaignNumber(1000), '1,000');
      expect(formatCampaignNumber(2500), '2,500');
      expect(formatCampaignNumber(1000000), '1,000,000');
      expect(formatCampaignNumber(campaignCoinCeiling), '1,000,000,000');
    });

    test('handles a negative, though no campaign number can be one', () {
      expect(formatCampaignNumber(-2500), '-2,500');
    });
  });

  // -------------------------------------------------------------------------
  group('the schedule', () {
    test('an evergreen campaign says so rather than showing a blank', () {
      final String range = CampaignCopy.dateRange(
        exampleOffer(evergreen: true).schedule,
      );

      expect(range, contains('No end date'));
      expect(
        CampaignCopy.endDateValue(exampleOffer(evergreen: true).schedule),
        'No end date',
      );
    });

    test('a bounded campaign shows both dates', () {
      final String range = CampaignCopy.dateRange(exampleOffer().schedule);

      expect(range, contains('–'));
      expect(range, isNot(contains('No end date')));
    });

    test('the time-zone note discloses which zone the dates are in', () {
      // The app ships no IANA database, so it cannot render the campaign's own
      // wall clock. Saying so beats implying otherwise.
      final String note = CampaignCopy.timeZoneNote('Asia/Dubai');

      expect(note, contains('device time zone'));
      expect(note, contains('Asia/Dubai'));
    });
  });

  // -------------------------------------------------------------------------
  group('the card semantic label', () {
    test('reads name, status, Vendor, reward, facts and dates in order', () {
      final String label = CampaignCopy.cardSemanticLabel(
        CampaignPresentation.retailer(exampleRetailerCampaign()),
      );

      expect(label, startsWith('Summer Push. Running.'));
      expect(label, contains('Vendor: Northwind Trading.'));
      expect(label, contains('Earn 10 coins per eligible unit'));
      expect(label, contains('Individual.'));
      expect(label, contains('3 eligible products.'));
    });

    test('omits the Vendor for a seller, with no empty label left behind', () {
      final String label = CampaignCopy.cardSemanticLabel(
        CampaignPresentation.staff(exampleStaffCampaign()),
      );

      expect(label, isNot(contains('Vendor')));
      expect(label, isNot(contains('Northwind')));
    });

    test('carries the zero-product warning exactly once, at the end', () {
      final String label = CampaignCopy.cardSemanticLabel(
        CampaignPresentation.retailer(
          exampleRetailerCampaign(offer: exampleOffer(eligibleProductCount: 0)),
        ),
      );

      expect(label, endsWith(CampaignCopy.noProductsCardNote));
      expect(CampaignCopy.noProductsCardNote.allMatches(label).length, 1);
    });

    test('omits the warning when products exist', () {
      final String label = CampaignCopy.cardSemanticLabel(
        CampaignPresentation.retailer(exampleRetailerCampaign()),
      );

      expect(label, isNot(contains(CampaignCopy.noProductsCardNote)));
    });
  });
}
