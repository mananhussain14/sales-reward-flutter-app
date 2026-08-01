@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static assertions about the campaign feature's security boundary.
///
/// These read the source rather than exercising it, which makes them the
/// cheapest guard against the boundary eroding under deadline pressure — the
/// kind of regression a behavioural test cannot see.
///
/// Five claims they defend:
///
/// 1. **No campaign table is ever read directly.** All eleven are default-deny
///    with zero RLS policies and no privilege for `authenticated`; RPC is the
///    only way in, by design.
/// 2. **The client nominates nothing but an address.** Both list reads take
///    zero arguments; the four addressed reads take a campaign id and nothing
///    else. No organization, Vendor, group, version, snapshot, profile or role
///    is ever transmitted.
/// 3. **Nothing here writes.** No campaign create, update, publish, lifecycle,
///    version or Retailer-group write RPC is named anywhere in the application.
/// 4. **Vendor-private fields never enter a presentation model.** No
///    exclusivity key, no priority, no audience mode, no group name, no version
///    or snapshot id.
/// 5. **The two roles cannot reach each other's contract.**
void main() {
  late List<File> lib;
  late List<File> campaignSources;

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
  /// explain why the client does not send, compare or display them.
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

    campaignSources = lib
        .where(
          (File f) => f.path.contains(
            '${Platform.pathSeparator}campaigns${Platform.pathSeparator}',
          ),
        )
        .toList();
  });

  test('the scan is non-vacuous', () {
    expect(lib, isNotEmpty);
    expect(campaignSources, hasLength(greaterThan(15)));
  });

  // -------------------------------------------------------------------------
  group('the six RPCs are the only way in', () {
    test('each RPC name is written in exactly one place', () {
      final Map<String, List<String>> rpcs = <String, List<String>>{
        'retailer_campaign_rpc_data_source.dart': <String>[
          "'list_my_retailer_campaigns'",
          "'get_my_retailer_campaign'",
          "'list_my_retailer_campaign_products'",
        ],
        'staff_campaign_rpc_data_source.dart': <String>[
          "'list_my_staff_campaigns'",
          "'get_my_staff_campaign'",
          "'list_my_staff_campaign_products'",
        ],
      };

      rpcs.forEach((String file, List<String> names) {
        final String src = named(file).readAsStringSync();
        for (final String rpc in names) {
          expect(
            rpc.allMatches(src).length,
            1,
            reason: '$file must name $rpc exactly once',
          );
        }
      });
    });

    test('no other file in the application names a campaign RPC', () {
      const List<String> rpcNames = <String>[
        'list_my_retailer_campaigns',
        'get_my_retailer_campaign',
        'list_my_retailer_campaign_products',
        'list_my_staff_campaigns',
        'get_my_staff_campaign',
        'list_my_staff_campaign_products',
      ];

      for (final File file in lib) {
        final String base = file.path.split(Platform.pathSeparator).last;
        if (base == 'retailer_campaign_rpc_data_source.dart' ||
            base == 'staff_campaign_rpc_data_source.dart') {
          continue;
        }
        final String code = codeOf(file);
        for (final String rpc in rpcNames) {
          expect(
            code.contains("'$rpc'"),
            isFalse,
            reason: '${file.path} must not name $rpc',
          );
        }
      }
    });

    test('the two data sources name only their own role\'s RPCs', () {
      // A Sales Staff repository must not be able to reach the Owner contract
      // by an edit that type-checks.
      final String staff = codeOf(named('staff_campaign_rpc_data_source.dart'));
      for (final String owner in <String>[
        'list_my_retailer_campaigns',
        'get_my_retailer_campaign',
        'list_my_retailer_campaign_products',
      ]) {
        expect(staff.contains(owner), isFalse, reason: owner);
      }

      final String retailer = codeOf(
        named('retailer_campaign_rpc_data_source.dart'),
      );
      for (final String seller in <String>[
        'list_my_staff_campaigns',
        'get_my_staff_campaign',
        'list_my_staff_campaign_products',
      ]) {
        expect(retailer.contains(seller), isFalse, reason: seller);
      }
    });

    test('the only RPC parameter is the campaign id', () {
      // The parameter name is declared once, in the Retailer data source, and
      // imported by the Sales Staff one — so a rename cannot leave one behind.
      final String retailer = codeOf(
        named('retailer_campaign_rpc_data_source.dart'),
      );
      final Set<String> declared = RegExp(
        r"'p_[a-z_]+'",
      ).allMatches(retailer).map((RegExpMatch m) => m.group(0)!).toSet();
      expect(declared, <String>{"'p_campaign_id'"});

      // The staff source declares no parameter name of its own.
      final String staff = codeOf(named('staff_campaign_rpc_data_source.dart'));
      expect(RegExp(r"'p_[a-z_]+'").hasMatch(staff), isFalse);
      expect(staff, contains('campaignIdParam'));

      // And neither builds a params map with anything else in it.
      for (final String code in <String>[retailer, staff]) {
        final Set<String> mapKeys = RegExp(
          r'<String, Object\?>\{([^}]*)\}',
        ).allMatches(code).map((RegExpMatch m) => m.group(1)!.trim()).toSet();
        for (final String entry in mapKeys) {
          expect(entry, startsWith('campaignIdParam:'));
          expect(
            entry.split(',').where((String e) => e.trim().isNotEmpty),
            hasLength(1),
          );
        }
      }
    });

    test('the list invokers take no arguments at all', () {
      for (final String file in <String>[
        'retailer_campaign_rpc_data_source.dart',
        'staff_campaign_rpc_data_source.dart',
      ]) {
        final String code = codeOf(named(file));
        // The zero-argument typedef, verbatim. A parameter added later would
        // have to change this line.
        expect(
          code,
          contains('Invoker = Future<Object?> Function();'),
          reason: file,
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  group('no direct campaign-table read', () {
    const List<String> campaignTables = <String>[
      'campaigns',
      'campaign_versions',
      'campaign_rules',
      'campaign_rule_tiers',
      'campaign_eligible_retailers',
      'campaign_eligible_products',
      'campaign_retailer_groups',
      'campaign_retailer_group_members',
      'vendor_products',
      'organizations',
      'organization_members',
    ];

    test('no file anywhere calls .from() on a campaign table', () {
      for (final File file in lib) {
        final String code = codeOf(file);
        for (final String table in campaignTables) {
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

    test('the campaign feature calls no PostgREST query builder at all', () {
      // `rpc()` is the only client method this feature uses. `.select()`,
      // `.from()`, `.insert()`, `.update()`, `.upsert()`, `.delete()` and the
      // filter builders would all indicate a table path.
      for (final File file in campaignSources) {
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
        ]) {
          expect(
            code.contains(method),
            isFalse,
            reason: '${file.path} must not call $method',
          );
        }
      }
    });

    test('only the two data sources touch the Supabase client', () {
      for (final File file in campaignSources) {
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
  });

  // -------------------------------------------------------------------------
  group('nothing in this feature writes', () {
    const List<String> writeRpcs = <String>[
      'create_vendor_campaign_draft',
      'update_vendor_campaign_draft',
      'publish_vendor_campaign',
      'set_vendor_campaign_lifecycle',
      'create_vendor_campaign_version',
      'create_vendor_retailer_group',
      'update_vendor_retailer_group',
      'set_vendor_retailer_group_members',
      'preview_vendor_campaign_publication',
    ];

    test('no campaign write RPC is named anywhere in the application', () {
      for (final File file in lib) {
        final String code = codeOf(file);
        for (final String rpc in writeRpcs) {
          expect(
            code.contains(rpc),
            isFalse,
            reason: '${file.path} must not name $rpc',
          );
        }
      }
    });

    test('no Vendor campaign read RPC is named either', () {
      // This milestone builds no Vendor campaign surface in Flutter at all.
      for (final File file in lib) {
        final String code = codeOf(file);
        for (final String rpc in <String>[
          'list_vendor_campaigns',
          'get_vendor_campaign',
          'get_vendor_campaign_version',
          'list_vendor_campaign_version_retailers',
          'list_vendor_campaign_version_groups',
          'list_vendor_campaign_version_products',
          'list_vendor_campaign_eligible_retailers',
          'list_vendor_retailer_groups',
        ]) {
          expect(
            code.contains(rpc),
            isFalse,
            reason: '${file.path} must not name $rpc',
          );
        }
      }
    });

    test('the two repository interfaces expose reads only', () {
      for (final String file in <String>[
        'retailer_campaign_repository.dart',
        'staff_campaign_repository.dart',
      ]) {
        final String code = codeOf(named(file));
        for (final String verb in <String>[
          'create',
          'publish',
          'pause',
          'resume',
          'cancel',
          'delete',
          'save',
          'submit',
        ]) {
          expect(
            RegExp('Future<[^>]*> $verb').hasMatch(code),
            isFalse,
            reason: '$file must not declare a $verb method',
          );
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('Vendor-private fields never enter a model', () {
    const List<String> privateColumns = <String>[
      'exclusivity_key',
      'exclusivityKey',
      'priority',
      'audience_mode',
      'audienceMode',
      'version_number',
      'versionNumber',
      'campaign_version_id',
      'campaignVersionId',
      'source_group_id',
      'sourceGroupId',
      'group_id',
      'groupId',
      'retailer_organization_id',
      'retailerOrganizationId',
      'vendor_organization_id',
      'vendorOrganizationId',
      'organization_id',
      'organizationId',
      'created_by',
      'createdBy',
      'profile_id',
      'profileId',
      'member_count',
      'memberCount',
      'retailer_count',
      'retailerCount',
    ];

    test('no campaign source reads or holds one', () {
      for (final File file in campaignSources) {
        final String code = codeOf(file);
        for (final String column in privateColumns) {
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
      // the two contracts declare. A key added here that the backend does not
      // return is a guess; a key that IS returned but withheld from a role is a
      // leak.
      final String code = codeOf(named('campaign_parsers.dart'));
      final Set<String> keys = RegExp(
        r"row\['([a-z_]+)'\]",
      ).allMatches(code).map((RegExpMatch m) => m.group(1)!).toSet();

      expect(keys, <String>{
        // The seventeen shared columns.
        'campaign_id',
        'campaign_name',
        'description',
        'derived_state',
        'starts_at',
        'ends_at',
        'timezone_name',
        'performance_scope',
        'product_scope',
        'product_eligibility_resolution',
        'stacking_mode',
        'reward_recipient_scope',
        'rule_type',
        'metric_type',
        'coins_per_unit',
        'max_reward_coins',
        'threshold_units',
        'reward_coins',
        'eligible_product_count',
        // The two the Retailer Owner contract adds.
        'vendor_name',
        'campaign_status',
        // The product contract.
        'product_code',
        'product_name',
        'barcode',
        'brand',
      });

      // `product_id` is returned by both product contracts and deliberately not
      // carried: this milestone is read-only and nothing could address a
      // product.
      expect(keys, isNot(contains('product_id')));
    });

    test('the Sales Staff parser reads neither withheld column', () {
      final String code = codeOf(named('campaign_parsers.dart'));
      final int staffRowStart = code.indexOf('parseStaffCampaignRow');
      expect(staffRowStart, greaterThan(-1));

      // The staff row parser body, up to the next member.
      final String staffRow = code.substring(
        staffRowStart,
        code.indexOf('static ', staffRowStart + 1),
      );
      expect(staffRow.contains('vendor_name'), isFalse);
      expect(staffRow.contains('campaign_status'), isFalse);
    });

    test('StaffCampaign has no field for a Vendor name', () {
      final String code = codeOf(named('staff_campaign.dart'));
      expect(code.toLowerCase().contains('vendorname'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('the client derives no authorization', () {
    test('no campaign source resolves a Retailer or checks a permission', () {
      for (final File file in campaignSources) {
        final String code = codeOf(file);
        for (final String token in <String>[
          'CAMPAIGNS_VIEW_ASSIGNED',
          'STAFF_CAMPAIGNS_VIEW',
          'CAMPAIGNS_MANAGE',
          'RETAILER_GROUPS_MANAGE',
          'resolve_retailer_member_organization',
          'auth.uid',
          'currentUser',
          'accessToken',
        ]) {
          expect(
            code.contains(token),
            isFalse,
            reason: '${file.path} must not reference $token in code',
          );
        }
      }
    });

    test('no campaign source reads the session or the portal context', () {
      // Whether a caller may read a campaign is decided in SQL on every call.
      // Nothing in this feature inspects who is signed in to decide anything.
      for (final File file in campaignSources) {
        final String base = file.path.split(Platform.pathSeparator).last;
        // The two thin role pages import their role's navigation for a route
        // prefix; neither reads a session.
        final String code = codeOf(file);
        expect(
          code.contains('SessionBloc'),
          isFalse,
          reason: '$base must not read the session',
        );
        expect(
          code.contains('PortalContext'),
          isFalse,
          reason: '$base must not read the portal context',
        );
        expect(
          code.contains('RetailerCapabilit'),
          isFalse,
          reason: '$base must not read a capability hint',
        );
      }
    });

    test('the campaign id is the only value transmitted', () {
      // Both `campaignDetail` signatures take one String and nothing else.
      for (final String file in <String>[
        'retailer_campaign_repository.dart',
        'staff_campaign_repository.dart',
      ]) {
        final String code = codeOf(named(file));
        expect(
          code,
          contains('campaignDetail(String campaignId)'),
          reason: file,
        );
        expect(code, contains('campaigns();'), reason: file);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('role isolation in the shells and routes', () {
    test('the Sales Staff shell provides no Retailer Owner campaign cubit', () {
      final String code = codeOf(named('sales_staff_shell.dart'));
      expect(code.contains('RetailerCampaignListCubit'), isFalse);
      expect(code.contains('RetailerCampaignDetailCubit'), isFalse);
      expect(code.contains('RetailerCampaignRepository'), isFalse);
    });

    test('the Retailer Owner shell provides no Sales Staff campaign cubit', () {
      final String code = codeOf(named('retailer_owner_shell.dart'));
      expect(code.contains('SalesStaffCampaignListCubit'), isFalse);
      expect(code.contains('SalesStaffCampaignDetailCubit'), isFalse);
      expect(code.contains('StaffCampaignRepository'), isFalse);
    });

    test('the Retailer Manager shell provides no campaign cubit at all', () {
      // CAMPAIGNS_VIEW_ASSIGNED is mapped to RETAILER_OWNER alone.
      final String code = codeOf(named('retailer_manager_shell.dart'));
      expect(code.toLowerCase().contains('campaign'), isFalse);
    });

    test('the Vendor shell provides no campaign cubit', () {
      final String code = codeOf(named('vendor_shell.dart'));
      expect(code.toLowerCase().contains('campaign'), isFalse);
    });

    test('each role page binds only its own cubit type', () {
      final String owner = codeOf(named('retailer_owner_campaigns_page.dart'));
      expect(owner, contains('CampaignListPage<RetailerCampaignListCubit>'));
      expect(owner.contains('SalesStaff'), isFalse);

      final String seller = codeOf(named('sales_staff_campaigns_page.dart'));
      expect(seller, contains('CampaignListPage<SalesStaffCampaignListCubit>'));
      expect(seller.contains('RetailerCampaignListCubit'), isFalse);
    });

    test('each role route stays inside its own prefix', () {
      final String owner = codeOf(named('retailer_owner_navigation.dart'));
      expect(owner, contains("campaigns = '\$prefix/campaigns'"));

      final String seller = codeOf(named('sales_staff_navigation.dart'));
      expect(seller, contains("campaigns = '\$prefix/campaigns'"));

      // Neither names the other's prefix.
      expect(owner.contains('/sales-staff'), isFalse);
      expect(seller.contains('/retailer-owner'), isFalse);
    });

    test('the Retailer Manager navigation offers no campaign destination', () {
      final String code = codeOf(named('retailer_manager_navigation.dart'));
      expect(code.toLowerCase().contains('campaign'), isFalse);
    });

    test(
      'the Vendor navigation campaign entry stays a non-routable placeholder',
      () {
        // The Vendor drawer has carried a "Campaigns" roadmap placeholder since
        // before this milestone. It must STAY a placeholder: Vendor campaign
        // management lives on the Web application, and this milestone builds no
        // Vendor campaign surface in Flutter. A `RoleDestination.soon` has no
        // path, so there is nothing to navigate to.
        final String code = codeOf(named('vendor_navigation.dart'));
        final int entry = code.indexOf("label: 'Campaigns'");
        expect(entry, greaterThan(-1));
        // The declaration immediately preceding it is the `.soon` constructor.
        expect(
          code.substring(0, entry).trimRight(),
          endsWith('RoleDestination.soon('),
        );
        // And no Vendor campaign route exists.
        expect(code.contains('campaigns ='), isFalse);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('no fabricated results', () {
    test('nothing in this feature names a progress or balance concept', () {
      for (final File file in campaignSources) {
        final String code = codeOf(file);
        // `unitsSold` / `UNITS_SOLD` is deliberately NOT in this list: it is
        // `campaign_rules.metric_type`, the name of what a rule counts, and it
        // says nothing about how much anyone has sold.
        for (final String token in <String>[
          'coinsEarned',
          'coins_earned',
          'earnedCoins',
          'coinBalance',
          'coin_balance',
          'progressValue',
          'percentComplete',
          'claimed',
          'payout',
          'LinearProgressIndicator',
        ]) {
          expect(
            code.contains(token),
            isFalse,
            reason: '${file.path} must not reference $token',
          );
        }
      }
    });

    test('no campaign source compares against the device clock', () {
      // The lifecycle state is derived by the backend against the SERVER's
      // clock. Recomputing it here would let a wrong phone clock move a
      // campaign between sections.
      for (final File file in campaignSources) {
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
}
