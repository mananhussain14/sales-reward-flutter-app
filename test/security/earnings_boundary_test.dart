@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static assertions about the Sales Staff earnings feature's security
/// boundary.
///
/// These read the source rather than exercising it, which makes them the
/// cheapest guard against the boundary eroding under deadline pressure — the
/// kind of regression a behavioural test cannot see.
///
/// Seven claims they defend:
///
/// 1. **No restricted table is ever read directly.** `campaign_rewards`,
///    `campaign_subject_accumulators`, `campaign_sale_evaluations`,
///    `campaign_sale_item_qualifications`, `verified_sales` and the
///    organization membership tables are default-deny for the browser roles;
///    RPC is the only way in, by design.
/// 2. **The client nominates nobody.** No profile, beneficiary, Retailer,
///    Vendor, organization or shop id is ever transmitted. The only values sent
///    are a page size and a cursor the previous page returned.
/// 3. **Nothing here writes.** No wallet, ledger, balance, payout, redemption,
///    withdrawal or claim RPC is named anywhere in the application.
/// 4. **No service-role client.** Every call travels on the caller's own
///    session.
/// 5. **`verified_sale_id` never enters a model or a screen.** Migration 69
///    exists to keep it out of a client.
/// 6. **No reward formula is reimplemented.** Nothing multiplies a rate by
///    units, applies a cap, or decides whether a target was reached.
/// 7. **This milestone changed no migration and no Web file.**
void main() {
  late List<File> lib;
  late List<File> rewardSources;

  /// The one file whose *basename* is [name].
  File named(String name) {
    final Iterable<File> matches = lib.where(
      (File f) => f.path.endsWith(Platform.pathSeparator + name),
    );
    expect(matches, hasLength(1), reason: 'expected exactly one $name');
    return matches.single;
  }

  /// [file]'s executable source, with comments removed.
  ///
  /// Every scan below is for a token that must not appear in *code*. The same
  /// tokens are legitimately discussed in the documentation comments that
  /// explain why the client does not send, compute or display them.
  String codeOf(File file) => file
      .readAsLinesSync()
      .map((String line) => line.trimLeft())
      .where(
        (String line) =>
            !line.startsWith('//') &&
            !line.startsWith('*') &&
            !line.startsWith('/*') &&
            !line.startsWith('///'),
      )
      .join('\n');

  setUpAll(() {
    lib = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();

    rewardSources = lib
        .where(
          (File f) => f.path.contains(
            '${Platform.pathSeparator}rewards${Platform.pathSeparator}',
          ),
        )
        .toList();
  });

  test('the scan is non-vacuous', () {
    expect(lib, isNotEmpty);
    expect(rewardSources, hasLength(greaterThan(8)));
  });

  // -------------------------------------------------------------------------
  group('the three RPCs are the only way in', () {
    const List<String> earningsRpcs = <String>[
      'get_my_campaign_rewards',
      'get_my_campaign_earnings_summary',
      'get_my_campaign_target_progress',
    ];

    test('each RPC name is written in exactly one place', () {
      final String src = named(
        'staff_earnings_rpc_data_source.dart',
      ).readAsStringSync();
      for (final String rpc in earningsRpcs) {
        expect(
          "'$rpc'".allMatches(src).length,
          1,
          reason: 'the data source must name $rpc exactly once',
        );
      }
    });

    test('no other file in the application names an earnings RPC', () {
      for (final File file in lib) {
        final String base = file.path.split(Platform.pathSeparator).last;
        if (base == 'staff_earnings_rpc_data_source.dart') {
          continue;
        }
        final String code = codeOf(file);
        for (final String rpc in earningsRpcs) {
          expect(
            code.contains("'$rpc'"),
            isFalse,
            reason: '${file.path} must not name $rpc',
          );
        }
      }
    });

    test('the earnings data source names no campaign RPC', () {
      // Two permissions, two contracts. A seller's earnings repository must not
      // be able to reach the campaign contract by an edit that type-checks.
      final String code = codeOf(named('staff_earnings_rpc_data_source.dart'));
      for (final String campaignRpc in <String>[
        'list_my_staff_campaigns',
        'get_my_staff_campaign',
        'list_my_staff_campaign_products',
        'list_my_retailer_campaigns',
        'get_my_retailer_campaign',
        'list_my_retailer_campaign_products',
      ]) {
        expect(code.contains(campaignRpc), isFalse, reason: campaignRpc);
      }
    });

    test('the internal earnings helper is never named by a client', () {
      // `sales_staff_earnings_profile()` is owner-execute-only: execute is
      // revoked from anon, authenticated AND service_role. A client that named
      // it could only ever be refused.
      for (final File file in lib) {
        expect(
          codeOf(file).contains('sales_staff_earnings_profile'),
          isFalse,
          reason: file.path,
        );
      }
    });

    test('the only RPC parameters are a page size and a cursor', () {
      final String code = codeOf(named('staff_earnings_rpc_data_source.dart'));
      final Set<String> declared = RegExp(
        r"'p_[a-z_]+'",
      ).allMatches(code).map((RegExpMatch m) => m.group(0)!).toSet();

      expect(declared, <String>{
        "'p_limit'",
        "'p_before_awarded_at'",
        "'p_before_reward_id'",
      });
    });

    test('the two zero-argument invokers take no arguments at all', () {
      final String code = codeOf(named('staff_earnings_rpc_data_source.dart'));
      // The zero-argument typedef, verbatim. A parameter added later would have
      // to change this line.
      expect(
        code,
        contains('StaffEarningsInvoker = Future<Object?> Function();'),
      );
    });

    test('no offset or page-number parameter exists anywhere', () {
      for (final File file in rewardSources) {
        final String code = codeOf(file);
        for (final String forbidden in <String>[
          'p_offset',
          "'offset'",
          'pageNumber',
          'p_page',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '${file.path} $forbidden',
          );
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('no direct restricted-table read', () {
    const List<String> restrictedTables = <String>[
      'campaign_rewards',
      'campaign_subject_accumulators',
      'campaign_sale_evaluations',
      'campaign_sale_item_qualifications',
      'verified_sales',
      'verified_sale_items',
      'organization_members',
      'retailer_shop_members',
      'organizations',
      'profiles',
      'campaigns',
      'campaign_versions',
    ];

    test('no file anywhere calls .from() on a restricted table', () {
      for (final File file in lib) {
        final String code = codeOf(file);
        for (final String table in restrictedTables) {
          expect(
            code.contains(".from('$table')"),
            isFalse,
            reason: '${file.path} must not read $table directly',
          );
          expect(
            code.contains('.from("$table")'),
            isFalse,
            reason: '${file.path} must not read $table directly',
          );
        }
      }
    });

    test('the earnings feature calls no PostgREST query builder at all', () {
      for (final File file in rewardSources) {
        final String code = codeOf(file);
        for (final String method in <String>[
          '.from(',
          '.select(',
          '.insert(',
          '.update(',
          '.upsert(',
          '.delete(',
          '.eq(',
          '.filter(',
          '.range(',
          '.limit(',
        ]) {
          expect(
            code.contains(method),
            isFalse,
            reason: '${file.path} must not call $method',
          );
        }
      }
    });

    test('only the data source touches the Supabase client', () {
      for (final File file in rewardSources) {
        final String base = file.path.split(Platform.pathSeparator).last;
        if (base.endsWith('_rpc_data_source.dart')) {
          continue;
        }
        expect(
          codeOf(file).contains('supabase_flutter'),
          isFalse,
          reason: '${file.path} must not import the Supabase client',
        );
      }
    });

    test('no service-role client or privileged key appears anywhere', () {
      for (final File file in lib) {
        final String code = codeOf(file).toLowerCase();
        for (final String forbidden in <String>[
          'service_role',
          'servicerole',
          'serviceroleKey'.toLowerCase(),
          'secret_key',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '${file.path} must not name $forbidden',
          );
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('nothing here writes, and there is no wallet', () {
    test('no wallet, ledger or payout RPC is named anywhere', () {
      for (final File file in lib) {
        final String code = codeOf(file);
        for (final String rpc in <String>[
          'redeem_campaign_reward',
          'withdraw_campaign_coins',
          'create_wallet',
          'get_my_wallet',
          'get_my_wallet_balance',
          'create_payout',
          'request_payout',
          'transfer_coins',
          'adjust_coin_balance',
          'evaluate_receipt_campaigns',
          'apply_campaign_reward',
        ]) {
          expect(
            code.contains(rpc),
            isFalse,
            reason: '${file.path} must not name $rpc',
          );
        }
      }
    });

    test('the repository interface exposes reads only', () {
      final String code = codeOf(named('staff_earnings_repository.dart'));
      for (final String verb in <String>[
        'create',
        'redeem',
        'withdraw',
        'transfer',
        'claim',
        'adjust',
        'delete',
        'save',
        'submit',
      ]) {
        expect(
          RegExp('Future<[^>]*> $verb').hasMatch(code),
          isFalse,
          reason: 'must not declare a $verb method',
        );
      }
    });

    test('no wallet or balance vocabulary reaches a screen', () {
      // The copy file is the ONE place these words appear, and only inside the
      // notice that says none of them exists. Everywhere else in the feature
      // they are forbidden.
      for (final File file in rewardSources) {
        final String base = file.path.split(Platform.pathSeparator).last;
        if (base == 'earnings_copy.dart') {
          continue;
        }
        final String code = codeOf(file).toLowerCase();
        for (final String forbidden in <String>[
          'walletbalance',
          'availablebalance',
          'redeemablecoins',
          'paidcoins',
          'withdrawablecoins',
          'payout',
          'ledger',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '${file.path} must not use $forbidden',
          );
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('withheld columns never enter a model', () {
    const List<String> withheldColumns = <String>[
      'verified_sale_id',
      'verifiedSaleId',
      'campaign_sale_evaluation_id',
      'campaignSaleEvaluationId',
      'cap_subject_type',
      'capSubjectType',
      'cap_subject_id',
      'capSubjectId',
      'beneficiary_profile_id',
      'beneficiaryProfileId',
      'target_bonus_awarded',
      'targetBonusAwarded',
      'coins_awarded_total',
      'coinsAwardedTotal',
      'units_counted_total',
      'unitsCountedTotal',
      'retailer_organization_id',
      'vendor_organization_id',
      'retailer_shop_id',
      'profile_id',
      'profileId',
    ];

    test('no earnings source reads or holds one', () {
      for (final File file in rewardSources) {
        final String code = codeOf(file);
        for (final String column in withheldColumns) {
          expect(
            code.contains(column),
            isFalse,
            reason: '${file.path} must not reference $column',
          );
        }
      }
    });

    test('the parser reads only the documented column names', () {
      // Every `row['...']` key the parser reads, checked against the exact set
      // the three contracts declare. A key that is not in a contract is a
      // guess; a key that IS returned but withheld is a leak.
      final String code = codeOf(named('earnings_parsers.dart'));
      final Set<String> keys = RegExp(
        r"row\['([a-z_]+)'\]",
      ).allMatches(code).map((RegExpMatch m) => m.group(1)!).toSet();

      expect(keys, <String>{
        // get_my_campaign_rewards — fifteen of the seventeen columns.
        'campaign_reward_id',
        'campaign_name',
        'receipt_submission_id',
        'shop_name',
        'sale_at',
        'awarded_at',
        'rule_type',
        'performance_scope',
        'qualifying_item_count',
        'qualifying_units',
        'coins_uncapped',
        'coins_capped_to',
        'reward_coins',
        'threshold_units',
        'configured_reward_coins',
        // get_my_campaign_earnings_summary — all seven.
        'total_reward_coins',
        'current_month_reward_coins',
        'rewarded_sale_count',
        'rewarded_campaign_count',
        'latest_reward_at',
        'current_month_start_utc',
        'current_month_end_utc',
        // get_my_campaign_target_progress — seven of the nine.
        'campaign_id',
        'target_units',
        'progress_units',
        'target_reached',
        'bonus_awarded_to_me',
      });

      // The reward contract returns `campaign_id` and `campaign_version_id`;
      // neither is carried on a reward, and `campaign_version_id` is carried
      // nowhere at all.
      expect(keys, isNot(contains('campaign_version_id')));
      expect(keys, isNot(contains('verified_sale_id')));
    });

    test('receipt_submission_id is the only sale reference', () {
      final String code = codeOf(named('campaign_reward_record.dart'));
      expect(code, contains('receiptSubmissionId'));
      expect(code.contains('verifiedSale'), isFalse);
    });

    test('the whole receipt id is shortened before it is rendered', () {
      // A reference a seller can match against their own history, and far short
      // of a value anybody could address something with.
      final String code = codeOf(named('campaign_reward_record.dart'));
      expect(code, contains('receiptReference'));
      expect(code, contains("split('-').first"));
    });
  });

  // -------------------------------------------------------------------------
  group('the client derives no authorization and no reward', () {
    test('no earnings source resolves an identity or checks a permission', () {
      for (final File file in rewardSources) {
        final String code = codeOf(file);
        for (final String token in <String>[
          'STAFF_EARNINGS_VIEW',
          'STAFF_CAMPAIGNS_VIEW',
          'resolve_retailer_member_organization',
          'auth.uid',
          'currentUser',
          'accessToken',
          'SessionBloc',
          'PortalContext',
          'RetailerCapabilit',
        ]) {
          expect(
            code.contains(token),
            isFalse,
            reason: '${file.path} must not reference $token in code',
          );
        }
      }
    });

    test('no reward formula is reimplemented', () {
      // The evaluator computes `coins_uncapped = coins_per_unit * units` and
      // `reward_coins = coalesce(coins_capped_to, coins_uncapped)`. Neither is
      // recomputed here: a client copy would be the one nobody noticed had
      // drifted, and it would be a confidently wrong statement about money.
      for (final File file in rewardSources) {
        final String code = codeOf(file);
        for (final String forbidden in <String>[
          'coinsPerUnit *',
          '* qualifyingUnits',
          'qualifyingUnits *',
          'coinsUncapped *',
          'clamp(0, coinsUncapped',
          'math.min',
          'math.max',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '${file.path} must not compute $forbidden',
          );
        }
      }
    });

    test('target_reached is read, never derived', () {
      // The single subtraction this feature permits is `coinsReducedByCap`,
      // which describes a difference between two stored values and decides
      // nothing. Comparing progress against a target WOULD decide something.
      final String code = codeOf(named('campaign_target_progress.dart'));
      expect(code, contains('final bool targetReached;'));
      expect(code.contains('progressUnits >= targetUnits'), isFalse);
    });

    test('the only arithmetic on an amount is the cap difference', () {
      final String code = codeOf(named('campaign_reward_record.dart'));
      final Iterable<RegExpMatch> subtractions = RegExp(
        r'\w+ - \w+',
      ).allMatches(code);
      expect(subtractions.map((RegExpMatch m) => m.group(0)), <String>[
        'coinsUncapped - rewardCoins',
      ]);
    });
  });

  // -------------------------------------------------------------------------
  group('role isolation in the shells and routes', () {
    test('only the Sales Staff shell provides an earnings cubit', () {
      final String seller = codeOf(named('sales_staff_shell.dart'));
      expect(seller, contains('SalesStaffEarningsCubit'));
      expect(seller, contains('SalesStaffCampaignProgressCubit'));

      for (final String shell in <String>[
        'retailer_owner_shell.dart',
        'retailer_manager_shell.dart',
        'vendor_shell.dart',
      ]) {
        final String code = codeOf(named(shell));
        expect(
          code.contains('StaffEarningsRepository'),
          isFalse,
          reason: shell,
        );
        expect(code.contains('EarningsCubit'), isFalse, reason: shell);
        expect(code.contains('CampaignProgressCubit'), isFalse, reason: shell);
      }
    });

    test('the earnings route stays inside the Sales Staff prefix', () {
      final String seller = codeOf(named('sales_staff_navigation.dart'));
      expect(seller, contains("earnings = '\$prefix/earnings'"));

      for (final String other in <String>[
        'retailer_owner_navigation.dart',
        'retailer_manager_navigation.dart',
        'vendor_navigation.dart',
      ]) {
        expect(
          codeOf(named(other)).toLowerCase().contains('earnings'),
          isFalse,
          reason: other,
        );
      }
    });

    test('the earnings cubits clear on a session change', () {
      // What somebody has been paid must not survive into another person's
      // session for even one frame.
      final String code = codeOf(named('sales_staff_shell.dart'));
      expect(code, contains('earnings.clear()'));
      expect(code, contains('campaignProgress.clear()'));
    });
  });

  // -------------------------------------------------------------------------
  group('this milestone touched nothing it should not have', () {
    test('the Flutter repository carries no Supabase migration', () {
      // Migrations live in the Web repository and are deployed from there. A
      // migration appearing here would mean two owners for one schema.
      expect(Directory('supabase').existsSync(), isFalse);
      final Iterable<File> sql = Directory('.')
          .listSync(recursive: false)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.sql'));
      expect(sql, isEmpty);
    });

    test('no Web source file lives in this repository', () {
      for (final String forbidden in <String>[
        'package.json',
        'next.config.js',
        'next.config.ts',
        'tsconfig.json',
      ]) {
        expect(File(forbidden).existsSync(), isFalse, reason: forbidden);
      }
    });

    test('no deployment or hosted-write command is named in the source', () {
      for (final File file in lib) {
        final String code = codeOf(file);
        for (final String forbidden in <String>[
          'supabase db push',
          'supabase functions deploy',
          'supabase migration',
          'flutter build apk',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '${file.path} must not name $forbidden',
          );
        }
      }
    });
  });
}
