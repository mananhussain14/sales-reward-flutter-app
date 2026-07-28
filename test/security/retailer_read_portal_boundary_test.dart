@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static assertions about the Retailer **read portal's** security boundary.
///
/// These read the source rather than exercising it, which makes them the
/// cheapest guard against the boundary eroding under deadline pressure — the
/// kind of regression a behavioural test cannot see.
///
/// Two claims they defend:
///
/// 1. **The client nominates nothing.** Not an organization, not a Vendor, not a
///    shop, not a person, not a role, not a permission. All four RPCs take zero
///    arguments and derive everything from `auth.uid()`.
/// 2. **Nothing here writes.** No shop create/edit/status, no invitation
///    send/resend/revoke, no membership change, no product assignment.
void main() {
  late List<File> lib;
  late List<File> retailerSources;

  /// The one file whose *basename* is [name].
  ///
  /// Matched on the separator deliberately: a bare `endsWith` would let
  /// `supabase_retailer_shop_repository.dart` satisfy a lookup for
  /// `retailer_shop_repository.dart`, so an assertion about the domain interface
  /// would silently run against the data implementation instead.
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
            !line.startsWith('/*'),
      )
      .join('\n');

  setUpAll(() {
    lib = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();

    // Everything this milestone added on the Retailer side, plus the shells and
    // navigation that route to it.
    retailerSources = lib
        .where(
          (File f) =>
              f.path.contains('retailer_shop') ||
              f.path.contains('retailer_staff') ||
              f.path.contains('retailer_assigned_product') ||
              f.path.contains('retailer_product') ||
              f.path.contains('retailer_invitation') ||
              f.path.contains(
                '${Platform.pathSeparator}retailer'
                '${Platform.pathSeparator}',
              ) ||
              f.path.contains('retailer_owner') ||
              f.path.contains('retailer_manager'),
        )
        .toList();
  });

  test('the scan is non-vacuous', () {
    expect(lib, isNotEmpty);
    expect(retailerSources, hasLength(greaterThan(10)));
  });

  // -------------------------------------------------------------------------
  group('all four RPCs are called with zero arguments', () {
    const List<String> dataSources = <String>[
      'retailer_shop_rpc_data_source.dart',
      'retailer_staff_rpc_data_source.dart',
      'retailer_product_rpc_data_source.dart',
    ];

    test('each RPC name is written in exactly one place', () {
      final Map<String, String> rpcs = <String, String>{
        'retailer_shop_rpc_data_source.dart':
            "'list_retailer_owner_portal_shops'",
        'retailer_product_rpc_data_source.dart':
            "'list_retailer_assigned_products'",
      };

      rpcs.forEach((String file, String rpc) {
        final String src = named(file).readAsStringSync();
        expect(
          rpc.allMatches(src).length,
          1,
          reason: '$file must name $rpc exactly once',
        );
      });

      // The staff data source names two.
      final String staff = named(
        'retailer_staff_rpc_data_source.dart',
      ).readAsStringSync();
      for (final String rpc in <String>[
        "'list_retailer_staff_members'",
        "'list_retailer_staff_invitations'",
      ]) {
        expect(rpc.allMatches(staff).length, 1, reason: rpc);
      }
    });

    test('no params map is passed, not even an empty one', () {
      for (final String file in dataSources) {
        final String src = codeOf(named(file));
        expect(src.contains('params:'), isFalse, reason: file);
        expect(src.contains('{}'), isFalse, reason: file);
      }
    });

    test('no call site carries an identity or tenant argument', () {
      for (final String file in dataSources) {
        final String src = codeOf(named(file));
        for (final String forbidden in <String>[
          'organization_id',
          'p_organization',
          'retailer_id',
          'p_retailer',
          'vendor_id',
          'p_vendor',
          'shop_id',
          'p_shop',
          'membership_id',
          'p_membership',
          'invitation_id',
          'p_invitation',
          'product_id',
          'p_product',
          'user_id',
          'p_user',
          'auth_user_id',
          'profile_id',
          'tenant',
          'role_code',
          'p_role',
          'permission_code',
          'p_permission',
          'access_token',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '$file must pass no $forbidden argument',
          );
        }
      }
    });

    test('every invoker typedef is nullary', () {
      // The security property is enforced by the type system: a nullary function
      // cannot be handed an organization id. This asserts the shape stays
      // nullary, so widening it becomes a deliberate, visible edit.
      for (final (String file, List<String> typedefs) in <(String, List<String>)>[
        (
          'retailer_shop_rpc_data_source.dart',
          <String>[
            'typedef RetailerShopsInvoker = Future<Object?> Function();',
          ],
        ),
        (
          'retailer_staff_rpc_data_source.dart',
          <String>[
            'typedef RetailerStaffMembersInvoker = Future<Object?> Function();',
            'typedef RetailerStaffInvitationsInvoker = '
                'Future<Object?> Function();',
          ],
        ),
        (
          'retailer_product_rpc_data_source.dart',
          <String>[
            'typedef RetailerAssignedProductsInvoker = '
                'Future<Object?> Function();',
          ],
        ),
      ]) {
        final String src = named(file).readAsStringSync();
        for (final String typedef in typedefs) {
          expect(src.contains(typedef), isTrue, reason: '$file: $typedef');
        }
      }
    });

    test('every repository method is nullary', () {
      for (final (String file, List<String> methods)
          in <(String, List<String>)>[
            (
              'retailer_shop_repository.dart',
              <String>['Future<RetailerShopsResult> shops();'],
            ),
            (
              'retailer_staff_repository.dart',
              <String>[
                'Future<RetailerStaffResult> members();',
                'Future<RetailerInvitationsResult> invitations();',
              ],
            ),
            (
              'retailer_product_repository.dart',
              <String>['Future<RetailerProductsResult> products();'],
            ),
          ]) {
        final String src = codeOf(named(file));
        for (final String method in methods) {
          expect(src.contains(method), isTrue, reason: '$file: $method');
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('no direct table access, and no write anywhere', () {
    test('no Retailer source reads or writes a table', () {
      for (final File file in retailerSources) {
        final String src = codeOf(file);
        for (final String forbidden in <String>[
          '.from(',
          '.select(',
          '.insert(',
          '.update(',
          '.upsert(',
          '.delete(',
          '.rpc(',
        ]) {
          // `.rpc(` is allowed in the three data sources and nowhere else.
          final bool isDataSource = file.path.contains('rpc_data_source.dart');
          if (forbidden == '.rpc(' && isDataSource) continue;
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} performs direct data access ($forbidden)',
          );
        }
      }
    });

    test('no Retailer source names a backend table in code', () {
      for (final File file in retailerSources) {
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          for (final String table in <String>[
            "'retailer_shops'",
            "'retailer_shop_members'",
            "'retailer_staff_invitations'",
            "'retailer_invitation_shop_assignments'",
            "'vendor_products'",
            "'vendor_product_retailer_assignments'",
            "'organizations'",
            "'organization_members'",
            "'member_roles'",
            "'profiles'",
          ]) {
            expect(
              lines[i].contains(table),
              isFalse,
              reason: '${file.path}:${i + 1} names $table',
            );
          }
        }
      }
    });

    test('no invitation write RPC is named anywhere in lib', () {
      // Sending needs the send-staff-invitation Edge Function, which holds the
      // delivery credential; revoking and resending are writes this milestone
      // does not implement.
      for (final File file in lib) {
        final String src = codeOf(file);
        for (final String rpc in <String>[
          'send_retailer_staff_invitation',
          'resend_retailer_staff_invitation',
          'revoke_retailer_staff_invitation',
          'create_retailer_staff_invitation',
          'send-staff-invitation',
        ]) {
          expect(src.contains(rpc), isFalse, reason: '${file.path}: $rpc');
        }
      }
    });

    test('no Product assignment write RPC is named in the Retailer portal', () {
      // Assignment is a Vendor capability on PRODUCT_RETAILER_ASSIGN. The Vendor
      // feature legitimately names these; the Retailer portal must not.
      for (final File file in retailerSources) {
        final String src = codeOf(file);
        for (final String rpc in <String>[
          'assign_vendor_product_to_retailer',
          'unassign_vendor_product_from_retailer',
          'create_vendor_product',
          'update_vendor_product',
          'set_vendor_product_status',
        ]) {
          expect(src.contains(rpc), isFalse, reason: '${file.path}: $rpc');
        }
      }
    });

    test('no shop write RPC exists anywhere', () {
      for (final File file in lib) {
        final String src = codeOf(file);
        for (final String rpc in <String>[
          'create_retailer_shop',
          'update_retailer_shop',
          'set_retailer_shop_status',
          'delete_retailer_shop',
        ]) {
          expect(src.contains(rpc), isFalse, reason: '${file.path}: $rpc');
        }
      }
    });

    test('no membership write RPC exists anywhere', () {
      for (final File file in lib) {
        final String src = codeOf(file);
        for (final String rpc in <String>[
          'set_retailer_staff_status',
          'update_retailer_staff_role',
          'assign_retailer_staff_shop',
          'remove_retailer_staff_shop',
        ]) {
          expect(src.contains(rpc), isFalse, reason: '${file.path}: $rpc');
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('no authorization is decided in Dart', () {
    test('no Retailer source compares a permission code', () {
      for (final File file in retailerSources) {
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          for (final String code in <String>[
            'RETAILER_PORTAL_READ',
            'RETAILER_SHOPS_READ',
            'RETAILER_STAFF_READ',
            'RETAILER_STAFF_MANAGE',
            'RETAILER_STAFF_SHOP_ASSIGN',
            'RETAILER_PRODUCTS_READ',
            'PRODUCT_RETAILER_ASSIGN',
            'RECEIPT_SUBMIT',
          ]) {
            expect(
              lines[i].contains(code),
              isFalse,
              reason: '${file.path}:${i + 1} names permission $code in code',
            );
          }
        }
      }
    });

    test('the roster page re-implements no membership-status filter', () {
      // `and (v_can_manage or m.status = 'ACTIVE')` is SQL's. Restating it here
      // would create a second definition free to drift from the enforced one.
      for (final String file in <String>[
        'retailer_staff_page.dart',
        'retailer_staff_cubit.dart',
        'retailer_staff_state.dart',
        'supabase_retailer_staff_repository.dart',
      ]) {
        final String src = codeOf(named(file));
        expect(
          RegExp(r'where\s*\(.*status\.isActive').hasMatch(src),
          isFalse,
          reason: '$file filters the roster by membership status',
        );
        expect(
          src.contains('RetailerMemberStatus.active =='),
          isFalse,
          reason: file,
        );
      }
    });

    test('the Manager scope flag is presentation only', () {
      // `includeInvitations` decides whether to *issue* a read, never whether a
      // caller is permitted. It must not appear in the repository or the parser.
      for (final String file in <String>[
        'supabase_retailer_staff_repository.dart',
        'retailer_staff_parsers.dart',
        'retailer_staff_repository.dart',
      ]) {
        expect(
          codeOf(named(file)).contains('includeInvitations'),
          isFalse,
          reason: '$file must not know about the presentation flag',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  group('nothing identifying reaches the client', () {
    test('no Retailer entity holds an identifier', () {
      // `retailer_staff_member.dart` is deliberately absent from this list: the
      // shop editor addresses a membership and preselects from its ACTIVE shop
      // ids, so that one entity carries exactly two identifiers. Its own
      // narrower assertions are the group below.
      for (final String file in <String>[
        'retailer_shop.dart',
        'retailer_staff_invitation.dart',
        'retailer_assigned_product.dart',
      ]) {
        final String src = codeOf(named(file));
        for (final String forbidden in <String>[
          'this.id',
          'shopId',
          'shopIds',
          'membershipId',
          'invitationId',
          'productId',
          'organizationId',
          'profileId',
          'userId',
          'vendorId',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '$file must carry no $forbidden',
          );
        }
      }
    });

    test('the parsers never read an id column into an entity', () {
      // The staff roster parser is deliberately absent: it reads exactly two id
      // columns, because the shop editor addresses a membership and preselects
      // from its ACTIVE shop ids. The group below pins which two, and no more.
      for (final String file in <String>[
        'retailer_shop_parser.dart',
        'retailer_assigned_product_parser.dart',
      ]) {
        final String src = codeOf(named(file));
        for (final String column in <String>[
          "row['membership_id']",
          "row['invitation_id']",
          "row['product_id']",
          "row['shop_ids']",
          "row['shop_id']",
        ]) {
          expect(src.contains(column), isFalse, reason: '$file reads $column');
        }
      }
    });

    group('the staff roster carries exactly two identifiers', () {
      test('the entity holds the membership id and the ACTIVE shop ids, and '
          'nothing else addressable', () {
        final String src = codeOf(named('retailer_staff_member.dart'));

        // The two the shop editor needs.
        expect(src.contains('this.membershipId'), isTrue);
        expect(src.contains('this.shopIds'), isTrue);

        // And no other address, in either direction: nothing that could name a
        // person outside this membership, and nothing that could name a tenant.
        for (final String forbidden in <String>[
          'invitationId',
          'productId',
          'organizationId',
          'retailerId',
          'tenantId',
          'profileId',
          'userId',
          'authUserId',
          'memberRoleId',
          'roleId',
          'vendorId',
          'email',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: 'the roster entity must carry no $forbidden',
          );
        }
      });

      test('the parser reads those two columns and no other id column', () {
        final String src = codeOf(named('retailer_staff_parsers.dart'));

        expect(src.contains("row['membership_id']"), isTrue);
        expect(src.contains("row['shop_ids']"), isTrue);

        for (final String column in <String>[
          "row['invitation_id']",
          "row['user_id']",
          "row['profile_id']",
          "row['organization_id']",
          "row['member_role_id']",
          "row['role_id']",
        ]) {
          expect(
            src.contains(column),
            isFalse,
            reason: 'the roster parser reads $column',
          );
        }
      });

      test('neither identifier is rendered by the roster card', () {
        final String src = codeOf(
          named('retailer_staff_member_card.dart'),
        ).replaceAll(RegExp(r'\s+'), '');

        for (final String forbidden in <String>[
          'member.membershipId',
          'member.shopIds',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: 'the card must not touch $forbidden at all',
          );
        }
      });
    });

    test('failure_code is not carried onto the invitation entity', () {
      // Reduced to a boolean at the parser; the token never reaches a screen.
      final String entity = codeOf(named('retailer_staff_invitation.dart'));
      expect(entity.contains('failureCode'), isFalse);
      expect(entity.contains('EMAIL_DISPATCH_FAILED'), isFalse);
    });

    test('user-facing copy contains no backend identifier or code', () {
      for (final String file in <String>[
        'retailer_shops_copy.dart',
        'retailer_staff_copy.dart',
        'retailer_products_copy.dart',
      ]) {
        final String src = codeOf(named(file));
        for (final String forbidden in <String>[
          '42501',
          'SQLSTATE',
          'PostgrestException',
          'public.',
          'auth.uid',
          'retailer_shops',
          'EMAIL_DISPATCH_FAILED',
          'list_retailer',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '$file must not mention $forbidden',
          );
        }
      }
    });

    test('no Retailer presentation source touches Supabase', () {
      final Iterable<File> presentation = retailerSources.where(
        (File f) =>
            f.path.contains(
              '${Platform.pathSeparator}presentation'
              '${Platform.pathSeparator}',
            ) ||
            f.path.contains(
              '${Platform.pathSeparator}shells'
              '${Platform.pathSeparator}',
            ),
      );
      expect(presentation, isNotEmpty);

      for (final File file in presentation) {
        final String src = codeOf(file);
        expect(
          src.contains('Supabase.instance'),
          isFalse,
          reason: '${file.path} reaches Supabase directly',
        );
        expect(
          src.contains('package:supabase_flutter'),
          isFalse,
          reason: '${file.path} imports the SDK outside the data layer',
        );
      }
    });

    test('no cubit state holds an unparsed map', () {
      for (final String file in <String>[
        'retailer_shops_state.dart',
        'retailer_staff_state.dart',
        'retailer_products_state.dart',
      ]) {
        final String src = codeOf(named(file));
        for (final String forbidden in <String>[
          'Map<String, dynamic>',
          'Map<String, Object?>',
          'dynamic ',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '$file must hold parsed domain types only',
          );
        }
      }
    });

    test('no service-role key is named in any Retailer source', () {
      for (final File file in retailerSources) {
        final String src = codeOf(file);
        for (final String forbidden in <String>[
          'SUPABASE_SERVICE_ROLE_KEY',
          'service_role',
          'serviceRoleKey',
          'RESEND_API_KEY',
        ]) {
          expect(src.contains(forbidden), isFalse, reason: file.path);
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('search is local and cannot become a backend filter', () {
    test('no search term reaches a repository or data source', () {
      for (final String file in <String>[
        'supabase_retailer_shop_repository.dart',
        'supabase_retailer_staff_repository.dart',
        'supabase_retailer_product_repository.dart',
        'retailer_shop_rpc_data_source.dart',
        'retailer_staff_rpc_data_source.dart',
        'retailer_product_rpc_data_source.dart',
      ]) {
        final String src = codeOf(named(file));
        for (final String forbidden in <String>[
          'searchTerm',
          'search',
          'filter',
          'query',
          'ilike',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '$file must know nothing about searching',
          );
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('role separation holds', () {
    test('the Manager shell provides no Shops or Overview cubit', () {
      final String src = codeOf(named('retailer_manager_shell.dart'));
      expect(src.contains('RetailerShopsCubit'), isFalse);
      expect(src.contains('RetailerOwnerOverviewCubit'), isFalse);
    });

    test('the Manager navigation has no Shops or Overview destination', () {
      final String src = codeOf(named('retailer_manager_navigation.dart'));
      expect(src.contains('viewShops'), isFalse);
      expect(src.contains('viewRetailerOverview'), isFalse);
      expect(src.contains('/retailer-owner'), isFalse);
    });

    test('neither Retailer shell provides a Vendor cubit', () {
      for (final String file in <String>[
        'retailer_owner_shell.dart',
        'retailer_manager_shell.dart',
      ]) {
        final String src = codeOf(named(file));
        expect(
          RegExp(r'BlocProvider<Vendor\w+>').hasMatch(src),
          isFalse,
          reason: file,
        );
      }
    });

    test('the Vendor shell provides no Retailer read cubit', () {
      final String src = codeOf(named('vendor_shell.dart'));
      for (final String cubit in <String>[
        'RetailerShopsCubit',
        'RetailerStaffCubit',
        'RetailerProductsCubit',
      ]) {
        expect(src.contains(cubit), isFalse, reason: cubit);
      }
    });
  });

  // -------------------------------------------------------------------------
  test('dart_defines.json is still untracked', () {
    final ProcessResult result = Process.runSync('git', <String>[
      'ls-files',
      'dart_defines.json',
    ]);
    expect(
      (result.stdout as String).trim(),
      isEmpty,
      reason: 'dart_defines.json holds environment values and must stay local',
    );
  });
}
