@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/staff/data/datasources/retailer_staff_shop_assignment_rpc_data_source.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_shop_assignment.dart';

/// Static assertions about the Retailer staff **shop-assignment** boundary.
///
/// These read the source rather than exercising it, which makes them the
/// cheapest guard against the boundary eroding under deadline pressure — the
/// kind of regression a behavioural test cannot see.
///
/// Six claims they defend:
///
/// 1. **`set_retailer_staff_shop_assignments` is the only assignment write**,
///    named in exactly one file, once.
/// 2. **The request carries exactly `p_membership_id` and `p_shop_ids`.** No
///    organization, actor, role, permission, status, timestamp or audit
///    argument, and no diff.
/// 3. **No Edge Function and no direct table write.** The rows and the audit
///    entry are written by the deployed function.
/// 4. **No privileged credential exists here.**
/// 5. **Nothing raw or identifying reaches a screen.** No database message, no
///    SQLSTATE, no membership or shop uuid.
/// 6. **The canonical roster is re-read after a success, and no write is ever
///    retried automatically.**
void main() {
  late List<File> lib;
  late List<File> assignmentSources;

  /// The one file whose *basename* is [name].
  ///
  /// Matched on the separator deliberately: a bare `endsWith` would let
  /// `supabase_retailer_staff_shop_assignment_repository.dart` satisfy a lookup
  /// for `retailer_staff_shop_assignment_repository.dart`, so an assertion about
  /// the domain interface would silently run against the data implementation
  /// instead.
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
  /// explain why the client does not send, hold or display them.
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

  /// [file]'s executable source with every space and newline removed.
  ///
  /// For assertions about a *signature* or a *call site*, which `dart format` is
  /// free to wrap differently as a file grows.
  String flatCodeOf(File file) => codeOf(file).replaceAll(RegExp(r'\s+'), '');

  setUpAll(() {
    lib = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();

    assignmentSources = lib
        .where(
          (File f) =>
              f.path.contains('retailer_staff_shop_assignment') ||
              f.path.contains('retailer_manage_staff_shops'),
        )
        .toList();
  });

  test('the scan is non-vacuous', () {
    expect(lib, isNotEmpty);
    expect(assignmentSources, hasLength(greaterThan(6)));
  });

  // -------------------------------------------------------------------------
  group('the write RPC is named once, exactly', () {
    test('the constant is the deployed name', () {
      expect(
        setRetailerStaffShopAssignmentsRpc,
        'set_retailer_staff_shop_assignments',
      );
    });

    test('the literal appears in exactly one file, once', () {
      final Iterable<File> naming = lib.where(
        (File f) => codeOf(f).contains("'set_retailer_staff_shop_assignments'"),
      );
      expect(naming.map((File f) => f.uri.pathSegments.last), <String>[
        'retailer_staff_shop_assignment_rpc_data_source.dart',
      ]);
      expect(
        "'set_retailer_staff_shop_assignments'"
            .allMatches(codeOf(naming.single))
            .length,
        1,
      );
    });

    test('it is the only assignment write named anywhere', () {
      // Every plausible sibling operation: none is implemented, and none is
      // named. A future milestone adding one has to edit this list.
      for (final File file in lib) {
        final String src = codeOf(file);
        for (final String forbidden in <String>[
          'assign_retailer_staff_shop',
          'remove_retailer_staff_shop',
          'add_retailer_staff_shop',
          'set_retailer_staff_shops',
          'replace_retailer_staff_shops',
          'clear_retailer_staff_shop_assignments',
          // Explicitly out of scope for this milestone.
          'update_retailer_staff_role',
          'set_retailer_staff_role',
          'set_retailer_staff_status',
          'activate_retailer_staff',
          'deactivate_retailer_staff',
          'suspend_retailer_staff',
          'accept_retailer_staff_invitation',
          'revoke_retailer_staff_invitation',
          'resend_retailer_staff_invitation',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path}: $forbidden',
          );
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('the request carries exactly two arguments', () {
    test('the two parameter constants are the contract\'s', () {
      expect(staffShopAssignmentMembershipParameter, 'p_membership_id');
      expect(staffShopAssignmentShopIdsParameter, 'p_shop_ids');
    });

    test('the invoker typedef takes those two and nothing else', () {
      // The security property enforced by the type system: a widened payload is
      // an edit to this signature.
      expect(
        flatCodeOf(
          named('retailer_staff_shop_assignment_rpc_data_source.dart'),
        ).contains(
          'typedefRetailerStaffShopAssignmentInvoker='
          'Future<Object?>Function({requiredStringmembershipId,'
          'requiredList<String>shopIds,});',
        ),
        isTrue,
      );
    });

    test('the params map has exactly the two keys', () {
      final String src = flatCodeOf(
        named('retailer_staff_shop_assignment_rpc_data_source.dart'),
      );
      expect(
        src.contains(
          'params:<String,Object?>{'
          'staffShopAssignmentMembershipParameter:membershipId,'
          'staffShopAssignmentShopIdsParameter:shopIds,},',
        ),
        isTrue,
      );
      // Two parameter names in the file, and no third string that looks like a
      // parameter.
      expect(
        RegExp(
          r"'p_[a-z_]+'",
        ).allMatches(src).map((RegExpMatch m) => m[0]).toSet(),
        <String>{"'p_membership_id'", "'p_shop_ids'"},
      );
    });

    test('the request entity has no field for an identity or a diff', () {
      final String src = codeOf(named('retailer_staff_shop_assignment.dart'));

      for (final String forbidden in <String>[
        'retailerOrganizationId',
        'organizationId',
        'retailerId',
        'tenantId',
        'actorId',
        'authUserId',
        'userId',
        'profileId',
        'memberRoleId',
        'invitationId',
        'roleCode',
        'permissionCode',
        'auditMetadata',
        'status',
        'timestamp',
        'idempotency',
        // A diff would put the retirement computation in two places.
        'shopsToAdd',
        'shopsToRemove',
        'addedShopIds',
        'removedShopIds',
        'currentShopIds',
      ]) {
        expect(src.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('a real request has exactly two fields', () {
      final RetailerStaffShopAssignmentInput input =
          RetailerStaffShopAssignmentRequest.validated(
            membershipId: 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
            shopIds: const <String>['11111111-1111-4111-8111-111111111111'],
          );
      final RetailerStaffShopAssignmentRequest request =
          (input as RetailerStaffShopAssignmentValid).request;

      expect(request.props, hasLength(2));
      expect(request.props, <Object?>[request.membershipId, request.shopIds]);
    });

    test('the repository interface takes nothing but the request', () {
      expect(
        flatCodeOf(
          named('retailer_staff_shop_assignment_repository.dart'),
        ).contains(
          'Future<RetailerStaffShopAssignmentResult>setShopAssignments('
          'RetailerStaffShopAssignmentRequestrequest,);',
        ),
        isTrue,
      );
    });

    test('no call site carries an identity or tenant argument', () {
      final String src = codeOf(
        named('retailer_staff_shop_assignment_rpc_data_source.dart'),
      );
      for (final String forbidden in <String>[
        'organization_id',
        'p_organization',
        'retailer_id',
        'p_retailer',
        'p_actor',
        'p_user',
        'auth_user_id',
        'profile_id',
        'tenant',
        'p_role',
        'permission_code',
        'p_permission',
        'p_status',
        'p_audit',
        'access_token',
      ]) {
        expect(src.contains(forbidden), isFalse, reason: forbidden);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('the assignable-shops read is still zero argument', () {
    test('the shared reader interface takes nothing', () {
      // One deployed contract, one Dart contract. The editor consumes the same
      // interface the invite form does, so neither can acquire a parameter the
      // function does not have without changing this line.
      expect(
        codeOf(
          named('retailer_assignable_shops_reader.dart'),
        ).contains('Future<RetailerAssignableShopsResult> assignableShops();'),
        isTrue,
      );
    });

    test('the reader interface has no membership or tenant parameter', () {
      final String src = codeOf(named('retailer_assignable_shops_reader.dart'));
      for (final String forbidden in <String>[
        'membershipId',
        'organizationId',
        'retailerId',
        'String ',
      ]) {
        expect(src.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('the editor reads shops through the shared interface', () {
      // Not through a second data source, and not through a second RPC call
      // site — a second path would be a second definition of which shops may be
      // assigned.
      final String src = codeOf(
        named('retailer_manage_staff_shops_cubit.dart'),
      );
      expect(src.contains('RetailerAssignableShopsReader'), isTrue);
      expect(src.contains('_shops.assignableShops()'), isTrue);
      expect(
        "'list_retailer_staff_assignable_shops'".allMatches(src).length,
        0,
        reason: 'the cubit must not name an RPC',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('no Edge Function, no credential, no direct table access', () {
    test('no assignment source invokes an Edge Function', () {
      for (final File file in assignmentSources) {
        final String src = codeOf(file);
        for (final String forbidden in <String>[
          'functions.invoke',
          'FunctionResponse',
          'FunctionException',
          'send-retailer-staff-invitation',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path}: $forbidden',
          );
        }
      }
    });

    test('no assignment source names a privileged key', () {
      for (final File file in assignmentSources) {
        final String src = codeOf(file);
        for (final String forbidden in <String>[
          'SUPABASE_SERVICE_ROLE_KEY',
          'serviceRoleKey',
          'SERVICE_ROLE',
          'service_role',
          'anonKey',
          'apiKey',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path}: $forbidden',
          );
        }
      }
    });

    test('no assignment source reads or writes a table', () {
      for (final File file in assignmentSources) {
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
          // `.rpc(` is allowed in the one data source and nowhere else.
          final bool isDataSource = file.path.endsWith(
            'retailer_staff_shop_assignment_rpc_data_source.dart',
          );
          if (forbidden == '.rpc(' && isDataSource) continue;
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} performs direct data access ($forbidden)',
          );
        }
      }
    });

    test('no assignment source names a backend table in code', () {
      for (final File file in assignmentSources) {
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          for (final String table in <String>[
            "'retailer_shop_members'",
            "'retailer_shops'",
            "'organization_members'",
            "'member_roles'",
            "'profiles'",
            "'audit_logs'",
            "'retailer_staff_invitations'",
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

    test('no assignment source decides a permission', () {
      for (final File file in assignmentSources) {
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          for (final String code in <String>[
            'RETAILER_STAFF_SHOP_ASSIGN',
            'RETAILER_STAFF_MANAGE',
            'RETAILER_STAFF_READ',
            'RETAILER_SHOPS_READ',
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

    test('the SDK is imported only in the data layer', () {
      for (final File file in assignmentSources) {
        if (file.path.contains(
          '${Platform.pathSeparator}data${Platform.pathSeparator}',
        )) {
          continue;
        }
        final String src = codeOf(file);
        expect(
          src.contains('package:supabase_flutter'),
          isFalse,
          reason: '${file.path} imports the SDK outside the data layer',
        );
        expect(src.contains('Supabase.instance'), isFalse, reason: file.path);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('nothing raw or identifying reaches a screen', () {
    test('the cubit state holds no unparsed map', () {
      final String src = codeOf(
        named('retailer_manage_staff_shops_state.dart'),
      );
      for (final String forbidden in <String>[
        'Map<String, dynamic>',
        'Map<String, Object?>',
        'dynamic ',
        'PostgrestException',
        'statusCode',
      ]) {
        expect(src.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('user-facing copy contains no backend identifier, code or table', () {
      final String src = codeOf(named('retailer_manage_staff_shops_copy.dart'));
      for (final String forbidden in <String>[
        '42501',
        '23514',
        '55000',
        '22P02',
        'SQLSTATE',
        'PostgrestException',
        'public.',
        'auth.uid',
        'set_retailer_staff_shop_assignments',
        'list_retailer_staff',
        'p_membership_id',
        'p_shop_ids',
        'retailer_shop_members',
        'removed_at',
        'SALES_STAFF',
        'RETAILER_OWNER',
        'uuid',
        // "membership" as an ordinary English word is fine and is used — an
        // Owner reads "their membership may have changed". The identifier is
        // what must never appear.
        'membershipId',
        'shopId',
        'token',
      ]) {
        expect(src.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('the copy never presents added plus unchanged as a total', () {
      // The counts describe the visible ACTIVE replacement only: assignments to
      // non-ACTIVE shops are preserved by the write and counted by none of them.
      final String src = flatCodeOf(
        named('retailer_manage_staff_shops_copy.dart'),
      );
      for (final String forbidden in <String>[
        'shopsAdded+shopsUnchanged',
        'shopsUnchanged+shopsAdded',
        'change.shopsAdded+',
        '+change.shopsUnchanged',
      ]) {
        expect(src.contains(forbidden), isFalse, reason: forbidden);
      }

      // And the type offers no total to reach for.
      expect(
        codeOf(
          named('retailer_staff_shop_assignment.dart'),
        ).contains('get total'),
        isFalse,
      );
    });

    test('the membership id is never rendered', () {
      // It reaches exactly one place: the request. It is not put in a label, a
      // semantics string, a widget key or a search index.
      for (final File file in assignmentSources.where(
        (File f) => f.path.contains(
          '${Platform.pathSeparator}widgets${Platform.pathSeparator}',
        ),
      )) {
        final String src = flatCodeOf(file);
        for (final String forbidden in <String>[
          'Text(state.membershipId',
          'membershipId.toString',
          'label:state.membershipId',
          'ValueKey(state.membershipId',
          'ValueKey<String>(state.membershipId',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path}: $forbidden',
          );
        }
      }
    });

    test('a shop id is never rendered', () {
      final String src = flatCodeOf(
        named('retailer_manage_staff_shops_dialog.dart'),
      );
      expect(src.contains('Text(shop.id'), isFalse);
      expect(src.contains('shop.id.toString'), isFalse);
      expect(
        src.contains('cubit.shopSelectionToggled(shop.id)'),
        isTrue,
        reason: 'the id addresses a selection and nothing else',
      );
      expect(
        src.contains('label:shop.displayLabel'),
        isTrue,
        reason: 'the announced label is the display label, never the id',
      );
    });

    test('the failure type carries no field a raw message could occupy', () {
      final String src = codeOf(
        named('retailer_staff_shop_assignment_repository.dart'),
      );
      for (final String forbidden in <String>[
        'String message',
        'String detail',
        'String hint',
        'String code',
        'int status',
        'StackTrace',
      ]) {
        expect(src.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('classification reads no message text', () {
      final String src = codeOf(
        named('supabase_retailer_staff_shop_assignment_repository.dart'),
      );
      for (final String forbidden in <String>[
        'error.message',
        '.message.contains',
        'message.toLowerCase',
        'contains(',
      ]) {
        expect(src.contains(forbidden), isFalse, reason: forbidden);
      }
      // Discrimination is by machine code alone.
      expect(src.contains('SqlState.insufficientPrivilege'), isTrue);
      expect(src.contains('SqlState.checkViolation'), isTrue);
      expect(src.contains('SqlState.objectNotInPrerequisiteState'), isTrue);
      expect(src.contains('SqlState.invalidTextRepresentation'), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('the roster is re-read, and no write is ever repeated', () {
    test('the repository calls the invoker exactly once per save', () {
      final String src = flatCodeOf(
        named('supabase_retailer_staff_shop_assignment_repository.dart'),
      );
      expect('_rpc.setShopAssignments('.allMatches(src).length, 1);
    });

    test('the cubit calls the repository exactly once per save', () {
      final String src = flatCodeOf(
        named('retailer_manage_staff_shops_cubit.dart'),
      );
      expect('_assignments.setShopAssignments('.allMatches(src).length, 1);
    });

    test('a success triggers the canonical roster reread, and only that', () {
      final String src = codeOf(
        named('retailer_manage_staff_shops_cubit.dart'),
      );
      expect(src.contains('_rereadRoster()'), isTrue);
      expect('_rereadRoster()'.allMatches(src).length, 1);
    });

    test('the reread is wired to the roster read, not to a local patch', () {
      // Nothing assembles a member row from what was submitted: the write's
      // answer carries three counts and no assignment rows.
      final String src = flatCodeOf(named('retailer_owner_shell.dart'));
      expect(
        src.contains(
          'rereadRoster:()=>providerContext.read<RetailerStaffCubit>()'
          '.rereadMembers(),',
        ),
        isTrue,
      );
    });

    test('the roster reread issues no invitation read and no write', () {
      final String src = codeOf(named('retailer_staff_cubit.dart'));
      final int start = src.indexOf('Future<bool> rereadMembers()');
      expect(start, greaterThan(-1));
      final String body = src.substring(
        start,
        src.indexOf('void searchChanged'),
      );

      expect(body.contains('_repository.members()'), isTrue);
      expect(body.contains('_repository.invitations()'), isFalse);
      expect(body.contains('setShopAssignments'), isFalse);
    });

    test('no assignment source loops or schedules a repeat', () {
      for (final File file in assignmentSources) {
        final String src = codeOf(file);
        for (final String forbidden in <String>[
          'retry(',
          'retries',
          'maxAttempts',
          'Timer(',
          'Timer.periodic',
          'Future.doWhile',
          'while (',
          'for (int attempt',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path}: $forbidden',
          );
        }
      }
    });

    test('a committed save closes the editor, so nothing can resubmit it', () {
      // The state after a success carries the notice and the counts, and no
      // target and no selection — which is what makes an ordinary retry a no-op
      // rather than a second write.
      final String src = flatCodeOf(
        named('retailer_manage_staff_shops_cubit.dart'),
      );
      expect(
        src.contains(
          'emit(RetailerManageStaffShopsState('
          'notice:RetailerManageShopsNotice.saved,change:change,),);',
        ),
        isTrue,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('presentation scope is never the authority', () {
    test('the eligibility rule reads only backend-supplied fields', () {
      final String src = flatCodeOf(named('retailer_staff_member.dart'));
      expect(
        src.contains(
          'boolgetisEditableSalesStaff=>'
          'roleCode==salesStaffRoleCode&&status.isActive&&joinedAt!=null;',
        ),
        isTrue,
      );
    });

    test('the page gates on a capability hint, not on a role label', () {
      final String src = codeOf(named('retailer_staff_page.dart'));
      expect(src.contains('RetailerCapability.assignStaffShops'), isTrue);
      // The role is used for the eyebrow and description only; no shop-assignment
      // decision is made from it.
      expect(
        src.contains('widget.role == PortalKind.retailerOwner'),
        isFalse,
        reason: 'a role label must not be the authority for the action',
      );
    });

    test('the capability hint is never consulted by the write path', () {
      // A hint may hide a dead end. It must never decide whether a write is
      // permitted.
      for (final File file in assignmentSources) {
        final String src = codeOf(file);
        expect(
          src.contains('RetailerCapabilit'),
          isFalse,
          reason: '${file.path} consults a capability hint',
        );
      }
    });

    test('the editor refuses an ineligible target in the cubit too', () {
      // Not only in the widget that hides the button.
      final String src = flatCodeOf(
        named('retailer_manage_staff_shops_cubit.dart'),
      );
      expect(src.contains('!member.isEditableSalesStaff'), isTrue);
    });
  });
}
