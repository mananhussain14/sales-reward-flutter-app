import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/parsing/rpc_row.dart';
import 'package:sale_reward/features/campaigns/data/models/campaign_parsers.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_lifecycle_state.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_measurement.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_product.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_product_eligibility.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_reward.dart';
import 'package:sale_reward/features/campaigns/domain/entities/campaign_stacking_mode.dart';
import 'package:sale_reward/features/campaigns/domain/entities/retailer_campaign.dart';
import 'package:sale_reward/features/campaigns/domain/entities/staff_campaign.dart';

import '../../support/campaign_fakes.dart';

/// Strict parsing of the six campaign read contracts.
///
/// The governing rule, and the reason these tests are stricter than the Vendor
/// Product parser's: **an unrecognised value fails the read.** A campaign's
/// enums decide which section it is filed under, whether a reader is told a
/// reward is available now, and which sentence describes how money is earned.
/// There is no neutral rendering of "we could not read how this pays", so the
/// honest options are the right sentence or no campaign.
void main() {
  Matcher throwsFormat() => throwsA(isA<RpcFormatException>());

  // -------------------------------------------------------------------------
  group('Retailer campaign list parsing', () {
    test('parses a complete row into every field', () {
      final List<RetailerCampaign> parsed =
          CampaignParsers.parseRetailerCampaigns(<Object?>[
            retailerCampaignRow(),
          ]);

      expect(parsed, hasLength(1));
      final RetailerCampaign campaign = parsed.single;

      expect(campaign.vendorName, 'Northwind Trading');
      expect(campaign.managementStatus, CampaignManagementStatus.published);
      expect(campaign.offer.campaignId, campaignIdA);
      expect(campaign.offer.name, 'Summer Push');
      expect(campaign.offer.description, 'Sell more of the summer range.');
      expect(campaign.offer.lifecycleState, CampaignLifecycleState.active);
      expect(
        campaign.offer.performanceScope,
        CampaignPerformanceScope.individualStaff,
      );
      expect(
        campaign.offer.rewardRecipientScope,
        CampaignRewardRecipientScope.contributingStaff,
      );
      expect(campaign.offer.stackingMode, CampaignStackingMode.stackable);
      expect(campaign.offer.productEligibility.eligibleProductCount, 3);
    });

    test('an empty list is a real answer, not a failure', () {
      expect(CampaignParsers.parseRetailerCampaigns(<Object?>[]), isEmpty);
    });

    test('an unrecognised extra key is ignored — the contract is additive', () {
      final Map<String, Object?> row = retailerCampaignRow()
        ..['some_future_column'] = 'whatever';

      expect(
        CampaignParsers.parseRetailerCampaigns(<Object?>[row]),
        hasLength(1),
      );
    });

    test('a body that is not a list is refused', () {
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<String, Object?>{}),
        throwsFormat(),
      );
    });

    test('one malformed row fails the whole list', () {
      // Under-reporting what a Retailer has been offered is worse than an
      // honest failure, so a bad row is never skipped.
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(),
          retailerCampaignRow(derivedState: 'HIBERNATING'),
        ]),
        throwsFormat(),
      );
    });

    test('a missing vendor_name is refused', () {
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(vendorName: null),
        ]),
        throwsFormat(),
      );
    });

    test('a blank vendor_name is refused', () {
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(vendorName: '   '),
        ]),
        throwsFormat(),
      );
    });

    test('a campaign_id that is not a uuid is refused', () {
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(campaignId: 'not-a-uuid'),
        ]),
        throwsFormat(),
      );
    });

    test('a null description is a real answer', () {
      final List<RetailerCampaign> parsed =
          CampaignParsers.parseRetailerCampaigns(<Object?>[
            retailerCampaignRow(description: null),
          ]);

      expect(parsed.single.offer.description, isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('Retailer campaign detail parsing', () {
    test('one row parses', () {
      final RetailerCampaign? campaign =
          CampaignParsers.parseRetailerCampaignSingle(<Object?>[
            retailerCampaignRow(),
          ]);

      expect(campaign, isNotNull);
      expect(campaign!.offer.campaignId, campaignIdA);
    });

    test('zero rows is null — the safe not-found, not a failure', () {
      // What an unknown id, another Retailer's id and a superseded version all
      // produce. The repository turns this into `Missing`, never into an error.
      expect(CampaignParsers.parseRetailerCampaignSingle(<Object?>[]), isNull);
    });

    test('more than one row is refused rather than silently truncated', () {
      expect(
        () => CampaignParsers.parseRetailerCampaignSingle(<Object?>[
          retailerCampaignRow(),
          retailerCampaignRow(campaignId: campaignIdB),
        ]),
        throwsFormat(),
      );
    });

    test('the detail shape is identical to the list shape', () {
      // The migration states this explicitly: "same column names, same order,
      // same types, same withheld fields — so one client-side model
      // deserializes both". One row through both entry points must agree.
      final Map<String, Object?> row = retailerCampaignRow();

      expect(
        CampaignParsers.parseRetailerCampaignSingle(<Object?>[row]),
        CampaignParsers.parseRetailerCampaigns(<Object?>[row]).single,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('Sales Staff campaign parsing', () {
    test('parses a row that carries neither withheld column', () {
      final Map<String, Object?> row = staffCampaignRow();

      // The fixture itself proves the two columns are absent from the contract.
      expect(row.containsKey('vendor_name'), isFalse);
      expect(row.containsKey('campaign_status'), isFalse);

      final List<StaffCampaign> parsed = CampaignParsers.parseStaffCampaigns(
        <Object?>[row],
      );

      expect(parsed, hasLength(1));
      expect(parsed.single.offer.name, 'Summer Push');
    });

    test('a Vendor name in the response cannot reach a staff entity', () {
      // Defence in depth: even if the backend started returning one, the staff
      // parser reads no such key and `StaffCampaign` has nowhere to hold it.
      final Map<String, Object?> row = staffCampaignRow()
        ..['vendor_name'] = 'Northwind Trading';

      final StaffCampaign parsed = CampaignParsers.parseStaffCampaigns(
        <Object?>[row],
      ).single;

      expect(parsed.props, isNot(contains('Northwind Trading')));
      expect(parsed.offer.props, isNot(contains('Northwind Trading')));
    });

    test('the shared columns parse identically for both roles', () {
      // One parser for the seventeen shared columns is what keeps the two roles
      // from describing one campaign differently.
      final StaffCampaign staff = CampaignParsers.parseStaffCampaigns(<Object?>[
        staffCampaignRow(),
      ]).single;
      final RetailerCampaign retailer = CampaignParsers.parseRetailerCampaigns(
        <Object?>[retailerCampaignRow()],
      ).single;

      expect(staff.offer, retailer.offer);
    });

    test('zero rows is null', () {
      expect(CampaignParsers.parseStaffCampaignSingle(<Object?>[]), isNull);
    });

    test('an empty list is a real answer', () {
      expect(CampaignParsers.parseStaffCampaigns(<Object?>[]), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('unknown enum tokens are refused, never defaulted', () {
    // Every one of the seven closed vocabularies. A default here would be a
    // value the backend never sent, presented as though it had.
    final Map<String, Map<String, Object?>> cases =
        <String, Map<String, Object?>>{
          'derived_state': retailerCampaignRow(derivedState: 'HIBERNATING'),
          'campaign_status': retailerCampaignRow(campaignStatus: 'ARCHIVED'),
          'performance_scope': retailerCampaignRow(
            performanceScope: 'INDIVIDUAL',
          ),
          'product_scope': retailerCampaignRow(productScope: 'SOME_PRODUCTS'),
          'product_eligibility_resolution': retailerCampaignRow(
            productScope: 'SELECTED_PRODUCTS',
            productEligibilityResolution: 'FROZEN',
          ),
          'stacking_mode': retailerCampaignRow(stackingMode: 'COMBINABLE'),
          'reward_recipient_scope': retailerCampaignRow(
            rewardRecipientScope: 'RETAILER_ORGANIZATION',
          ),
          'rule_type': retailerCampaignRow(ruleType: 'PERCENT_OF_VALUE'),
          'metric_type': retailerCampaignRow(metricType: 'VALUE_SOLD'),
        };

    cases.forEach((String column, Map<String, Object?> row) {
      test('an unknown $column fails the read', () {
        expect(
          () => CampaignParsers.parseRetailerCampaigns(<Object?>[row]),
          throwsFormat(),
        );
      });
    });

    test("'INDIVIDUAL' is not the token — 'INDIVIDUAL_STAFF' is", () {
      // The one place this vocabulary differs from the shorthand people use.
      expect(CampaignPerformanceScope.tryFromCode('INDIVIDUAL'), isNull);
      expect(
        CampaignPerformanceScope.tryFromCode('INDIVIDUAL_STAFF'),
        CampaignPerformanceScope.individualStaff,
      );
    });

    test('a missing enum column is refused, like an unknown one', () {
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(stackingMode: null),
        ]),
        throwsFormat(),
      );
    });
  });

  // -------------------------------------------------------------------------
  group('timestamps', () {
    test('an unparseable starts_at is refused', () {
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(startsAt: 'not-a-date'),
        ]),
        throwsFormat(),
      );
    });

    test('a missing starts_at is refused — the column is NOT NULL', () {
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(startsAt: null),
        ]),
        throwsFormat(),
      );
    });

    test('an unparseable ends_at is refused, not dropped to null', () {
      // "No end date" and "an end date this build could not read" are different
      // facts, and only one of them is the backend's.
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(endsAt: 'soon'),
        ]),
        throwsFormat(),
      );
    });

    test('a numeric timestamp is refused', () {
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(startsAt: 1767225600),
        ]),
        throwsFormat(),
      );
    });

    test('a null ends_at is the evergreen campaign, and parses', () {
      final RetailerCampaign campaign = CampaignParsers.parseRetailerCampaigns(
        <Object?>[retailerCampaignRow(endsAt: null)],
      ).single;

      expect(campaign.offer.schedule.isEvergreen, isTrue);
      expect(campaign.offer.schedule.endsAt, isNull);
    });

    test('an end that is not after the start is refused', () {
      // `campaign_versions_period_ordered` is strict: a zero-length period can
      // reward nothing.
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(
            startsAt: '2026-07-01T00:00:00Z',
            endsAt: '2026-06-01T00:00:00Z',
          ),
        ]),
        throwsFormat(),
      );
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(
            startsAt: '2026-07-01T00:00:00Z',
            endsAt: '2026-07-01T00:00:00Z',
          ),
        ]),
        throwsFormat(),
      );
    });

    test('instants are parsed to UTC and the zone stays a separate label', () {
      final RetailerCampaign campaign =
          CampaignParsers.parseRetailerCampaigns(<Object?>[
            retailerCampaignRow(
              startsAt: '2026-07-01T04:00:00+04:00',
              timezoneName: 'Asia/Dubai',
            ),
          ]).single;

      expect(campaign.offer.schedule.startsAt.isUtc, isTrue);
      expect(campaign.offer.schedule.startsAt, DateTime.utc(2026, 7));
      // The IANA identifier is carried untouched and never folded into the
      // instant.
      expect(campaign.offer.schedule.timeZoneName, 'Asia/Dubai');
    });
  });

  // -------------------------------------------------------------------------
  group('reward parsing', () {
    test('a per-unit rule parses its rate and cap', () {
      final RetailerCampaign campaign = CampaignParsers.parseRetailerCampaigns(
        <Object?>[retailerCampaignRow(coinsPerUnit: 10, maxRewardCoins: 100)],
      ).single;

      final CampaignReward reward = campaign.offer.reward;
      expect(reward, isA<CampaignPerUnitReward>());
      expect((reward as CampaignPerUnitReward).coinsPerUnit, 10);
      expect(reward.maxRewardCoins, 100);
      expect(reward.metric, CampaignMetricType.unitsSold);
    });

    test('an uncapped per-unit rule parses', () {
      final RetailerCampaign campaign = CampaignParsers.parseRetailerCampaigns(
        <Object?>[retailerCampaignRow(maxRewardCoins: null)],
      ).single;

      expect(campaign.offer.reward.maxRewardCoins, isNull);
      expect(campaign.offer.reward.isCapped, isFalse);
    });

    test('a target rule parses its threshold and bonus', () {
      final RetailerCampaign campaign =
          CampaignParsers.parseRetailerCampaigns(<Object?>[
            retailerCampaignRow(
              ruleType: 'TARGET_BONUS',
              coinsPerUnit: null,
              maxRewardCoins: null,
              thresholdUnits: 25,
              rewardCoins: 2500,
            ),
          ]).single;

      final CampaignReward reward = campaign.offer.reward;
      expect(reward, isA<CampaignTargetReward>());
      expect((reward as CampaignTargetReward).thresholdUnits, 25);
      expect(reward.rewardCoins, 2500);
    });

    test('a per-unit rule with no rate is refused', () {
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(coinsPerUnit: null),
        ]),
        throwsFormat(),
      );
    });

    test('a per-unit rule carrying a target tier is refused', () {
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(thresholdUnits: 25, rewardCoins: 2500),
        ]),
        throwsFormat(),
      );
    });

    test('a target rule carrying a per-unit rate is refused', () {
      // The other half of `campaign_rules_rate_paired`.
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(
            ruleType: 'TARGET_BONUS',
            coinsPerUnit: 10,
            thresholdUnits: 25,
            rewardCoins: 2500,
          ),
        ]),
        throwsFormat(),
      );
    });

    test('a target rule with no tier is refused', () {
      // No target to reach and no reward to describe: the row cannot be
      // rendered truthfully at all.
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(ruleType: 'TARGET_BONUS', coinsPerUnit: null),
        ]),
        throwsFormat(),
      );
    });

    test('a missing rule_type is refused', () {
      // Representable through the LEFT JOIN, but `publish_vendor_campaign`
      // refuses a draft with no rule, so a published campaign always has one.
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(ruleType: null),
        ]),
        throwsFormat(),
      );
    });

    group('malformed numeric rewards are refused', () {
      final Map<String, Map<String, Object?>> cases =
          <String, Map<String, Object?>>{
            'a zero rate': retailerCampaignRow(coinsPerUnit: 0),
            'a negative rate': retailerCampaignRow(coinsPerUnit: -5),
            'a rate above the coin ceiling': retailerCampaignRow(
              coinsPerUnit: campaignCoinCeiling + 1,
            ),
            'a zero cap': retailerCampaignRow(maxRewardCoins: 0),
            'a cap above the coin ceiling': retailerCampaignRow(
              maxRewardCoins: campaignCoinCeiling + 1,
            ),
            'a string rate': retailerCampaignRow(coinsPerUnit: '10'),
            'a fractional rate': retailerCampaignRow(coinsPerUnit: 10.5),
            'a zero threshold': retailerCampaignRow(
              ruleType: 'TARGET_BONUS',
              coinsPerUnit: null,
              thresholdUnits: 0,
              rewardCoins: 2500,
            ),
            'a zero bonus': retailerCampaignRow(
              ruleType: 'TARGET_BONUS',
              coinsPerUnit: null,
              thresholdUnits: 25,
              rewardCoins: 0,
            ),
            'a bonus above the coin ceiling': retailerCampaignRow(
              ruleType: 'TARGET_BONUS',
              coinsPerUnit: null,
              thresholdUnits: 25,
              rewardCoins: campaignCoinCeiling + 1,
            ),
          };

      cases.forEach((String name, Map<String, Object?> row) {
        test(name, () {
          expect(
            () => CampaignParsers.parseRetailerCampaigns(<Object?>[row]),
            throwsFormat(),
          );
        });
      });

      test('the ceiling itself is accepted', () {
        final RetailerCampaign campaign =
            CampaignParsers.parseRetailerCampaigns(<Object?>[
              retailerCampaignRow(coinsPerUnit: campaignCoinCeiling),
            ]).single;

        expect(
          (campaign.offer.reward as CampaignPerUnitReward).coinsPerUnit,
          campaignCoinCeiling,
        );
      });

      test('an integral double is accepted — JSON has one number type', () {
        final RetailerCampaign campaign =
            CampaignParsers.parseRetailerCampaigns(<Object?>[
              retailerCampaignRow(coinsPerUnit: 10.0),
            ]).single;

        expect(
          (campaign.offer.reward as CampaignPerUnitReward).coinsPerUnit,
          10,
        );
      });
    });
  });

  // -------------------------------------------------------------------------
  group('product eligibility: snapshot versus live-temporal', () {
    test('SELECTED_PRODUCTS pairs with SNAPSHOT', () {
      final RetailerCampaign campaign =
          CampaignParsers.parseRetailerCampaigns(<Object?>[
            retailerCampaignRow(
              productScope: 'SELECTED_PRODUCTS',
              productEligibilityResolution: 'SNAPSHOT',
            ),
          ]).single;

      expect(
        campaign.offer.productEligibility.scope,
        CampaignProductScope.selectedProducts,
      );
      expect(
        campaign.offer.productEligibility.resolution,
        CampaignProductEligibilityResolution.snapshot,
      );
      expect(campaign.offer.productEligibility.isCoherent, isTrue);
    });

    test('ALL_ELIGIBLE_PRODUCTS pairs with LIVE_TEMPORAL', () {
      final RetailerCampaign campaign =
          CampaignParsers.parseRetailerCampaigns(<Object?>[
            retailerCampaignRow(
              productScope: 'ALL_ELIGIBLE_PRODUCTS',
              productEligibilityResolution: 'LIVE_TEMPORAL',
            ),
          ]).single;

      expect(
        campaign.offer.productEligibility.scope,
        CampaignProductScope.allEligibleProducts,
      );
      expect(
        campaign.offer.productEligibility.resolution,
        CampaignProductEligibilityResolution.liveTemporal,
      );
    });

    test('SELECTED_PRODUCTS with LIVE_TEMPORAL is refused', () {
      // `campaign_versions_resolution_matches_scope` refuses it at the table, so
      // a row carrying it is not this shape.
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(
            productScope: 'SELECTED_PRODUCTS',
            productEligibilityResolution: 'LIVE_TEMPORAL',
          ),
        ]),
        throwsFormat(),
      );
    });

    test('ALL_ELIGIBLE_PRODUCTS with SNAPSHOT is refused', () {
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(
            productScope: 'ALL_ELIGIBLE_PRODUCTS',
            productEligibilityResolution: 'SNAPSHOT',
          ),
        ]),
        throwsFormat(),
      );
    });
  });

  // -------------------------------------------------------------------------
  group('the eligible-product count', () {
    test('a count of zero is preserved exactly', () {
      // The whole point of the warning this feature renders. It is never
      // rounded away, never treated as missing, and never treated as an error.
      final RetailerCampaign campaign = CampaignParsers.parseRetailerCampaigns(
        <Object?>[retailerCampaignRow(eligibleProductCount: 0)],
      ).single;

      expect(campaign.offer.productEligibility.eligibleProductCount, 0);
      expect(campaign.offer.productEligibility.hasNoEligibleProducts, isTrue);
    });

    test('zero is preserved for a Sales Staff row too', () {
      final StaffCampaign campaign = CampaignParsers.parseStaffCampaigns(
        <Object?>[staffCampaignRow(eligibleProductCount: 0)],
      ).single;

      expect(campaign.offer.productEligibility.eligibleProductCount, 0);
    });

    test('a positive count does not read as empty', () {
      final RetailerCampaign campaign = CampaignParsers.parseRetailerCampaigns(
        <Object?>[retailerCampaignRow(eligibleProductCount: 1)],
      ).single;

      expect(campaign.offer.productEligibility.hasNoEligibleProducts, isFalse);
    });

    test('a negative count is refused — count(*) cannot produce one', () {
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(eligibleProductCount: -1),
        ]),
        throwsFormat(),
      );
    });

    test('a missing count is refused', () {
      expect(
        () => CampaignParsers.parseRetailerCampaigns(<Object?>[
          retailerCampaignRow(eligibleProductCount: null),
        ]),
        throwsFormat(),
      );
    });
  });

  // -------------------------------------------------------------------------
  group('campaign product parsing', () {
    test('parses the five columns and drops product_id', () {
      final List<CampaignProduct> products =
          CampaignParsers.parseCampaignProducts(<Object?>[
            campaignProductRow(),
          ]);

      expect(products, hasLength(1));
      final CampaignProduct product = products.single;
      expect(product.productCode, 'SUM-001');
      expect(product.productName, 'Summer Cooler 500ml');
      expect(product.barcode, '05012345678900');
      expect(product.brand, 'Northwind');
      // No product_id is carried, so no UUID can reach state or a screen.
      expect(
        product.props,
        isNot(contains('ffffffff-1111-4222-8333-444444444444')),
      );
    });

    test('an empty list is a real answer — the zero-eligible state', () {
      expect(CampaignParsers.parseCampaignProducts(<Object?>[]), isEmpty);
    });

    test('null barcode and brand pass through', () {
      final CampaignProduct product = CampaignParsers.parseCampaignProducts(
        <Object?>[campaignProductRow(barcode: null, brand: null)],
      ).single;

      expect(product.barcode, isNull);
      expect(product.brand, isNull);
    });

    test('a numeric barcode is refused, not stringified', () {
      // A number that has been through a JSON parser has already lost its
      // leading zeros, and a GTIN with a leading zero is a different barcode.
      expect(
        () => CampaignParsers.parseCampaignProducts(<Object?>[
          campaignProductRow(barcode: 5012345678900),
        ]),
        throwsFormat(),
      );
    });

    test('a missing product_name is refused', () {
      expect(
        () => CampaignParsers.parseCampaignProducts(<Object?>[
          campaignProductRow(productName: null),
        ]),
        throwsFormat(),
      );
    });

    test('duplicates are kept, both of them', () {
      final List<CampaignProduct> products =
          CampaignParsers.parseCampaignProducts(<Object?>[
            campaignProductRow(),
            campaignProductRow(),
          ]);

      expect(products, hasLength(2));
    });
  });

  // -------------------------------------------------------------------------
  group('the campaign id shape guard', () {
    test('accepts a canonical uuid', () {
      expect(isCampaignIdShaped(campaignIdA), isTrue);
      expect(isCampaignIdShaped(campaignIdB), isTrue);
    });

    test('refuses anything else', () {
      for (final String value in <String>[
        '',
        'not-a-uuid',
        '11111111-2222-4333-8444',
        '11111111222243338444555555555555',
        ' $campaignIdA',
        "$campaignIdA' or '1'='1",
      ]) {
        expect(isCampaignIdShaped(value), isFalse, reason: value);
      }
    });
  });
}
