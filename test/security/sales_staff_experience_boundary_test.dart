@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-safety assertions for the Sales Staff experience redesign.
///
/// The companion to `campaign_boundary_test.dart`, `earnings_boundary_test.dart`
/// and `receipt_boundary_test.dart`. Those defend three contracts; this defends
/// the **screen that composes them**, which is the one surface in this
/// application that reads from more than one.
///
/// A composition surface has failure modes the individual features do not:
///
/// * it is the obvious place to add a shortcut straight to Supabase, because it
///   already needs four things at once;
/// * it is the obvious place to add up two contracts' numbers into a third that
///   no backend returned;
/// * it is the obvious place for encouraging copy to drift into a claim.
///
/// Six properties are defended, stated once each:
///
/// * **The home screen owns no data path.** No Supabase client, no RPC name, no
///   PostgREST query builder, no repository — it reads the cubits the shell
///   already provides and nothing else.
/// * **It derives no figure.** No sum, no percentage of a percentage, no
///   projection, no comparison against a previous period.
/// * **No value is a balance.** The one place wallet, payout and redemption are
///   named is the shared notice that says none of them exists.
/// * **Nothing is fabricated.** No streak, rank, leaderboard, countdown or
///   prediction vocabulary anywhere in the feature.
/// * **The motion system honours reduced motion.** Every animating primitive
///   consults `SrMotion.respects`.
/// * **The milestone added no dependency and no migration.**
void main() {
  late List<File> lib;
  late List<File> homeSources;
  late List<File> motionSources;

  /// [file]'s executable source, with comments removed.
  ///
  /// Every scan below is for a token that must not appear in *code*. The same
  /// tokens are legitimately discussed in the documentation comments that
  /// explain why the screen does not send, compute or display them.
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

  File named(String name) {
    final Iterable<File> matches = lib.where(
      (File f) => f.path.endsWith(Platform.pathSeparator + name),
    );
    expect(matches, hasLength(1), reason: 'expected exactly one $name');
    return matches.single;
  }

  setUpAll(() {
    lib = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();

    homeSources = lib
        .where(
          (File f) => f.path.contains(
            '${Platform.pathSeparator}home${Platform.pathSeparator}',
          ),
        )
        .toList();

    motionSources = <File>[
      named('sr_animations.dart'),
      named('sr_progress_ring.dart'),
    ];
  });

  test('the scan is non-vacuous', () {
    expect(lib, isNotEmpty);
    expect(homeSources, hasLength(greaterThan(3)));
  });

  // -------------------------------------------------------------------------
  group('the landing screen owns no data path', () {
    test('no home source touches Supabase', () {
      for (final File file in homeSources) {
        final String code = codeOf(file);
        for (final String token in <String>[
          'supabase',
          'Supabase',
          'SupabaseClient',
          'PostgrestClient',
          '.rpc(',
          '.from(',
          '.select(',
          'service_role',
          'serviceRole',
        ]) {
          expect(
            code.contains(token),
            isFalse,
            reason: '${file.path} must not reference $token',
          );
        }
      }
    });

    test('no home source names an RPC', () {
      // Every figure on this screen arrives through a cubit the shell already
      // provides. Naming a function here would be a second caller for a
      // contract that already has one, and the two would drift.
      for (final File file in homeSources) {
        final String code = codeOf(file);
        for (final String rpc in <String>[
          'list_my_staff_campaigns',
          'get_my_staff_campaign',
          'list_my_staff_campaign_products',
          'get_my_campaign_rewards',
          'get_my_campaign_earnings_summary',
          'get_my_campaign_target_progress',
          'list_my_receipt_submissions',
          'submit-receipt',
        ]) {
          expect(
            code.contains(rpc),
            isFalse,
            reason: '${file.path} must not name $rpc',
          );
        }
      }
    });

    test('no home source holds a repository', () {
      for (final File file in homeSources) {
        final String code = codeOf(file);
        for (final String token in <String>[
          'StaffCampaignRepository',
          'StaffEarningsRepository',
          'ReceiptRepository',
          'ReceiptExtractionRepository',
        ]) {
          expect(
            code.contains(token),
            isFalse,
            reason: '${file.path} must not depend on $token',
          );
        }
      }
    });

    test('the landing screen performs no write', () {
      // The only calls it makes on a cubit are `loadOnce` and `refresh`.
      final String page = codeOf(named('sales_staff_home_page.dart'));
      for (final String verb in <String>[
        '.submit(',
        '.confirm(',
        '.delete(',
        '.claim(',
        '.redeem(',
        '.chooseImage(',
        '.selectShop(',
      ]) {
        expect(
          page.contains(verb),
          isFalse,
          reason: 'the home screen must not call $verb',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  group('no figure is derived on the client', () {
    test('the landing screen performs no arithmetic on an amount', () {
      final String page = codeOf(named('sales_staff_home_page.dart'));
      final String panel = codeOf(named('sales_staff_coins_panel.dart'));

      for (final String code in <String>[page, panel]) {
        for (final String token in <String>[
          'totalRewardCoins +',
          '+ totalRewardCoins',
          'rewardCoins *',
          'currentMonthRewardCoins +',
          'coinsPerUnit',
          '.fold(',
          '.reduce(',
        ]) {
          expect(code.contains(token), isFalse, reason: token);
        }
      }
    });

    test('the campaign order is the backend\'s, never re-sorted', () {
      final String page = codeOf(named('sales_staff_home_page.dart'));
      // The screen partitions and truncates; it does not sort, score or rank.
      expect(page.contains('.sort('), isFalse);
      expect(page.contains('compareTo'), isFalse);
      expect(page.contains('recommend'), isFalse);
    });

    test('no home source reads the device clock', () {
      // Every lifecycle state, schedule window and month boundary on this
      // screen was derived by the backend against the SERVER's clock.
      for (final File file in homeSources) {
        final String code = codeOf(file);
        for (final String token in <String>[
          'DateTime.now',
          'isBefore(DateTime',
          'isAfter(DateTime',
          'clock.now',
        ]) {
          expect(
            code.contains(token),
            isFalse,
            reason: '${file.path} must not read the device clock',
          );
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('nothing is a balance, and nothing is fabricated', () {
    test('no wallet or payout vocabulary is written in the home feature', () {
      // The single qualifying notice lives on `EarningsCopy` and is REFERENCED
      // here, never restated — so these words appear in this feature's compiled
      // output exactly once, in the sentence that says none of them exists.
      for (final File file in homeSources) {
        // The shared notice is referenced by name, not restated — so the
        // identifier is removed before the scan rather than special-cased
        // inside it, exactly as the earnings boundary does with its copy file.
        final String code = codeOf(
          file,
        ).replaceAll('EarningsCopy.walletNotice', '').toLowerCase();
        for (final String forbidden in <String>[
          'wallet',
          'availablebalance',
          'redeemable',
          'paidcoins',
          'withdraw',
          'payout',
          'ledger',
          'cash out',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '${file.path} must not use $forbidden',
          );
        }
      }
    });

    test('no invented motivation vocabulary anywhere in the feature', () {
      for (final File file in homeSources) {
        final String code = codeOf(file).toLowerCase();
        for (final String forbidden in <String>[
          'streak',
          'leaderboard',
          'ranking',
          'countdown',
          'guaranteed',
          'you will earn',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '${file.path} must not use $forbidden',
          );
        }
      }
    });

    test('the coin figure is labelled as earned', () {
      final String copy = codeOf(named('sales_staff_home_copy.dart'));
      expect(copy, contains("coinsSectionTitle = 'Campaign coins earned'"));
    });
  });

  // -------------------------------------------------------------------------
  group('the motion system', () {
    test('every animating primitive consults reduced motion', () {
      for (final File file in motionSources) {
        expect(
          codeOf(file),
          contains('SrMotion.respects'),
          reason: '${file.path} must honour reduced motion',
        );
      }
    });

    test('nothing in the motion system repeats', () {
      // The only looping animation in the product is the skeleton shimmer,
      // which lives on `SrSkeleton` and is removed entirely under reduced
      // motion. A second one would be movement a reader cannot stop.
      for (final File file in motionSources) {
        final String code = codeOf(file);
        expect(code.contains('.repeat('), isFalse, reason: file.path);
        expect(code.contains('reverse: true'), isFalse, reason: file.path);
      }
    });

    test('the progress ring claims nothing about reaching a target', () {
      final String ring = codeOf(named('sr_progress_ring.dart'));
      // It draws a ratio the caller supplies. A painter that compared two
      // numbers would be a second definition of "reached".
      for (final String token in <String>[
        'targetReached',
        'progressUnits',
        'targetUnits',
        'bonusAwarded',
      ]) {
        expect(ring.contains(token), isFalse, reason: token);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('this milestone touched nothing it should not have', () {
    test('no new dependency was added for the redesign', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      for (final String forbidden in <String>[
        'lottie',
        'rive',
        'flutter_animate',
        'shimmer',
        'percent_indicator',
        'fl_chart',
        'golden_toolkit',
        'alchemist',
      ]) {
        expect(
          pubspec.contains(forbidden),
          isFalse,
          reason: 'the redesign must not add $forbidden',
        );
      }
    });

    test('the Flutter repository still carries no Supabase migration', () {
      expect(Directory('supabase').existsSync(), isFalse);
      final Iterable<File> sql = Directory('.')
          .listSync(recursive: false)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.sql'));
      expect(sql, isEmpty);
    });

    test('the landing route stays inside the Sales Staff prefix', () {
      final String navigation = codeOf(named('sales_staff_navigation.dart'));
      expect(navigation, contains("home = '\$prefix/home'"));
      expect(navigation, contains('landingPath: home'));

      for (final String other in <String>[
        'retailer_owner_navigation.dart',
        'retailer_manager_navigation.dart',
        'vendor_navigation.dart',
      ]) {
        expect(
          codeOf(named(other)).contains('sales-staff'),
          isFalse,
          reason: other,
        );
      }
    });
  });
}
