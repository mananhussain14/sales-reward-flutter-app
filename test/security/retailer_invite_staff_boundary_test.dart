@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/staff/data/datasources/retailer_staff_invitation_rpc_data_source.dart';
import 'package:sale_reward/features/staff/data/models/retailer_staff_invitation_request_body.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_assignable_shop.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_invitation_outcome.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_invitation_request.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_invitation_role.dart';

/// Static assertions about the Retailer staff **invitation** boundary.
///
/// These read the source rather than exercising it, which makes them the
/// cheapest guard against the boundary eroding under deadline pressure — the
/// kind of regression a behavioural test cannot see.
///
/// Four claims they defend:
///
/// 1. **The client nominates nothing but the five contract fields.** No
///    Retailer, no actor, no membership, no invitation, no token.
/// 2. **No privileged credential exists here.** Not the database's, not the
///    email provider's. Both live only inside the Edge Function.
/// 3. **Nothing writes a table.** The invitation and shop-membership rows are
///    written by the function, under a key this application does not hold.
/// 4. **Nothing retries a 2xx.** The 202 partial success exists precisely so no
///    client resubmits, and no automatic retry appears anywhere on this path.
void main() {
  late List<File> lib;
  late List<File> invitationSources;

  /// The one file whose *basename* is [name].
  ///
  /// Matched on the separator deliberately: a bare `endsWith` would let
  /// `supabase_retailer_staff_invitation_repository.dart` satisfy a lookup for
  /// `retailer_staff_invitation_repository.dart`, so an assertion about the
  /// domain interface would silently run against the data implementation
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
  /// For assertions about a *signature* or a *call site*, which `dart format`
  /// is free to wrap differently as a file grows. Matching the flattened form
  /// pins what the code says rather than how it happens to be laid out.
  String flatCodeOf(File file) => codeOf(file).replaceAll(RegExp(r'\s+'), '');

  setUpAll(() {
    lib = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();

    invitationSources = lib
        .where(
          (File f) =>
              f.path.contains('retailer_staff_invitation') ||
              f.path.contains('retailer_invite_staff') ||
              f.path.contains('retailer_assignable_shop'),
        )
        .toList();
  });

  test('the scan is non-vacuous', () {
    expect(lib, isNotEmpty);
    expect(invitationSources, hasLength(greaterThan(8)));
  });

  // -------------------------------------------------------------------------
  group('the Edge Function is named once, exactly', () {
    test('the constant is the deployed name', () {
      expect(
        sendRetailerStaffInvitationFunction,
        'send-retailer-staff-invitation',
      );
    });

    test('the literal appears in exactly one file, once', () {
      final Iterable<File> naming = lib.where(
        (File f) => codeOf(f).contains("'send-retailer-staff-invitation'"),
      );
      expect(naming.map((File f) => f.uri.pathSegments.last), <String>[
        'retailer_staff_invitation_rpc_data_source.dart',
      ]);
      expect(
        "'send-retailer-staff-invitation'"
            .allMatches(codeOf(naming.single))
            .length,
        1,
      );
    });

    test('no other invitation function or write RPC is named anywhere', () {
      for (final File file in lib) {
        final String src = codeOf(file);
        for (final String forbidden in <String>[
          // Reserving, preparing and recording all happen inside the function,
          // and three of the four are granted to the privileged database role
          // alone.
          'reserve_retailer_staff_invitation',
          'prepare_retailer_staff_invitation',
          'record_retailer_staff_invitation_sent',
          'record_retailer_staff_invitation_failure',
          // Acceptance lives in the emailed link, not in this app.
          'accept_retailer_staff_invitation',
          'get_retailer_staff_invitation_for_recipient',
          // Out of scope for this milestone.
          'revoke_retailer_staff_invitation',
          'resend_retailer_staff_invitation',
          'send-staff-invitation',
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
  group('the request carries exactly five fields', () {
    test('the declared field list is the contract\'s', () {
      expect(retailerStaffInvitationRequestFields, <String>[
        'firstName',
        'lastName',
        'email',
        'roleCode',
        'shopIds',
      ]);
    });

    test('the encoder writes those five keys and no others', () {
      final String src = codeOf(
        named('retailer_staff_invitation_request_body.dart'),
      );

      // Each key appears twice: once in the declared list, once in the map.
      for (final String field in retailerStaffInvitationRequestFields) {
        expect("'$field'".allMatches(src).length, 2, reason: field);
      }
    });

    test('a real encoded body has exactly five keys', () {
      final RetailerStaffInvitationInput input =
          RetailerStaffInvitationRequest.validated(
            firstName: 'Priya',
            lastName: 'Raman',
            email: 'priya@example.com',
            role: RetailerStaffInvitationRole.retailerManager,
            shopIds: const <String>[],
          );
      final Map<String, Object?> body = encodeRetailerStaffInvitationRequest(
        (input as RetailerStaffInvitationValid).request,
      );

      expect(body.keys.toSet(), retailerStaffInvitationRequestFields.toSet());
      expect(body.keys, hasLength(5));
    });

    test('the request entity has no field for an identity or a secret', () {
      final String src = codeOf(
        named('retailer_staff_invitation_request.dart'),
      );

      for (final String forbidden in <String>[
        'retailerOrganizationId',
        'organizationId',
        'retailerId',
        'tenantId',
        'actorId',
        'authUserId',
        'userId',
        'profileId',
        'membershipId',
        'invitationId',
        'tokenHash',
        'expiresAt',
        'normalizedEmail',
        'permissionCode',
        'auditMetadata',
      ]) {
        expect(src.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('the repository interface takes nothing but the request', () {
      final String src = codeOf(
        named('retailer_staff_invitation_repository.dart'),
      );

      // Zero arguments for the read; one domain request for the write. Widening
      // either is an edit to this line.
      expect(
        src.contains(
          'Future<RetailerAssignableShopsResult> assignableShops();',
        ),
        isTrue,
      );
      expect(
        flatCodeOf(named('retailer_staff_invitation_repository.dart')).contains(
          'Future<RetailerStaffInvitationSendResult>send('
          'RetailerStaffInvitationRequestrequest,);',
        ),
        isTrue,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('the assignable-shops RPC is called with zero arguments', () {
    test('the RPC name is written in exactly one place', () {
      final String src = named(
        'retailer_staff_invitation_rpc_data_source.dart',
      ).readAsStringSync();

      expect(
        "'list_retailer_staff_assignable_shops'".allMatches(src).length,
        1,
      );
      expect(
        retailerStaffAssignableShopsRpc,
        'list_retailer_staff_assignable_shops',
      );
    });

    test('the invoker typedef is nullary', () {
      // The security property is enforced by the type system: a nullary function
      // cannot be handed an organization id.
      expect(
        named(
          'retailer_staff_invitation_rpc_data_source.dart',
        ).readAsStringSync().contains(
          'typedef RetailerAssignableShopsInvoker = Future<Object?> Function();',
        ),
        isTrue,
      );
    });

    test('no params map is passed, not even an empty one', () {
      final String src = codeOf(
        named('retailer_staff_invitation_rpc_data_source.dart'),
      );
      expect(src.contains('params:'), isFalse);
      expect(
        RegExp(
          r'\.rpc<Object\?>\(\s*retailerStaffAssignableShopsRpc\s*\)',
        ).hasMatch(src),
        isTrue,
        reason: 'the call site must carry a name and nothing else',
      );
    });

    test('no call site carries an identity or tenant argument', () {
      final String src = codeOf(
        named('retailer_staff_invitation_rpc_data_source.dart'),
      );
      for (final String forbidden in <String>[
        'organization_id',
        'p_organization',
        'retailer_id',
        'p_retailer',
        'membership_id',
        'p_membership',
        'invitation_id',
        'p_invitation',
        'user_id',
        'p_user',
        'auth_user_id',
        'profile_id',
        'tenant',
        'p_role',
        'permission_code',
        'p_permission',
        'access_token',
      ]) {
        expect(src.contains(forbidden), isFalse, reason: forbidden);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('no privileged credential and no direct table write', () {
    test('no invitation source names a privileged key', () {
      for (final File file in invitationSources) {
        final String src = codeOf(file);
        for (final String forbidden in <String>[
          'SUPABASE_SERVICE_ROLE_KEY',
          'serviceRoleKey',
          'SERVICE_ROLE',
          'RESEND_API_KEY',
          'RESEND_FROM',
          'resendApiKey',
          'APP_ORIGIN',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path}: $forbidden',
          );
        }
      }
    });

    test('no invitation source reads or writes a table', () {
      for (final File file in invitationSources) {
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
            'retailer_staff_invitation_rpc_data_source.dart',
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

    test('no invitation source names a backend table in code', () {
      for (final File file in invitationSources) {
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          for (final String table in <String>[
            "'retailer_staff_invitations'",
            "'retailer_invitation_shop_assignments'",
            "'retailer_shop_members'",
            "'retailer_shops'",
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

    test('no membership or shop-assignment write RPC exists anywhere', () {
      // Post-acceptance shop reassignment, role changes and staff activation
      // are explicitly out of scope for this milestone.
      for (final File file in lib) {
        final String src = codeOf(file);
        for (final String rpc in <String>[
          'assign_retailer_staff_shop',
          'remove_retailer_staff_shop',
          'set_retailer_staff_shops',
          'update_retailer_staff_role',
          'set_retailer_staff_status',
        ]) {
          expect(src.contains(rpc), isFalse, reason: '${file.path}: $rpc');
        }
      }
    });

    test('no invitation source decides a permission', () {
      for (final File file in invitationSources) {
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          for (final String code in <String>[
            'RETAILER_STAFF_MANAGE',
            'RETAILER_STAFF_SHOP_ASSIGN',
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
  });

  // -------------------------------------------------------------------------
  group('nothing identifying or raw reaches the screen', () {
    test('no presentation source touches Supabase', () {
      final Iterable<File> presentation = invitationSources.where(
        (File f) => f.path.contains(
          '${Platform.pathSeparator}presentation${Platform.pathSeparator}',
        ),
      );
      expect(presentation, isNotEmpty);

      for (final File file in presentation) {
        final String src = codeOf(file);
        expect(src.contains('Supabase.instance'), isFalse, reason: file.path);
        expect(
          src.contains('package:supabase_flutter'),
          isFalse,
          reason: '${file.path} imports the SDK outside the data layer',
        );
      }
    });

    test('the cubit state holds no unparsed map', () {
      final String src = codeOf(named('retailer_invite_staff_state.dart'));
      for (final String forbidden in <String>[
        'Map<String, dynamic>',
        'Map<String, Object?>',
        'dynamic ',
        'FunctionResponse',
        'statusCode',
      ]) {
        expect(src.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('the raw reply never leaves the data layer', () {
      // `RetailerStaffInvitationReply` is the only type that holds a body, and
      // it is constructed and consumed inside the data layer alone.
      final Iterable<File> holders = lib.where(
        (File f) => codeOf(f).contains('RetailerStaffInvitationReply'),
      );
      for (final File file in holders) {
        expect(
          file.path.contains(
            '${Platform.pathSeparator}data${Platform.pathSeparator}',
          ),
          isTrue,
          reason: '${file.path} holds a raw reply outside the data layer',
        );
      }
    });

    test('user-facing copy contains no backend identifier, code or secret', () {
      final String src = codeOf(named('retailer_invite_staff_copy.dart'));
      for (final String forbidden in <String>[
        '42501',
        'SQLSTATE',
        'PostgrestException',
        'public.',
        'auth.uid',
        'list_retailer',
        'send-retailer-staff-invitation',
        'RETAILER_MANAGER',
        'SALES_STAFF',
        'INVITATION_CONFLICT',
        'DELIVERY_ACCEPTED_STATUS_UNCONFIRMED',
        'NOT_SENT',
        'Resend',
        'token',
        'uuid',
        'rate limit',
      ]) {
        expect(src.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('the copy never claims a rate limiter exists', () {
      // There is no rate limiter in this system, so there is no RATE_LIMITED
      // code and nothing here may imply one.
      final String src = named(
        'retailer_invite_staff_copy.dart',
      ).readAsStringSync().toLowerCase();
      for (final String forbidden in <String>[
        'rate limit',
        'too many requests',
        'slow down',
        'try again in a moment',
      ]) {
        expect(src.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('the wire tokens never reach a widget', () {
      // Role labels and outcome copy are chosen from enums; the tokens
      // themselves live on the domain entities and stay there.
      final Iterable<File> widgets = invitationSources.where(
        (File f) => f.path.contains(
          '${Platform.pathSeparator}widgets${Platform.pathSeparator}',
        ),
      );
      expect(widgets, isNotEmpty);

      for (final File file in widgets) {
        final String src = codeOf(file);
        for (final String token in <String>[
          "'RETAILER_MANAGER'",
          "'SALES_STAFF'",
          "'SENT'",
          "'RESENT'",
          "'DELIVERY_FAILED'",
          "'INTERNAL_ERROR'",
        ]) {
          expect(src.contains(token), isFalse, reason: '${file.path}: $token');
        }
      }
    });

    test('a shop id is never rendered', () {
      // `displayLabel` is the only string built from a shop, and it is the
      // string the picker announces. Asserted on the value rather than on the
      // source, so no reformatting can weaken it.
      for (final RetailerAssignableShop shop in <RetailerAssignableShop>[
        const RetailerAssignableShop(
          id: '11111111-1111-4111-8111-111111111111',
          name: 'Northwind Marina',
          code: 'NW-01',
          city: 'Dubai',
        ),
        const RetailerAssignableShop(
          id: '22222222-2222-4222-8222-222222222222',
          name: 'Northwind Warehouse',
          code: null,
          city: null,
        ),
      ]) {
        expect(
          shop.displayLabel.contains(shop.id),
          isFalse,
          reason: 'displayLabel must never carry the id',
        );
        expect(shop.displayLabel, contains(shop.name));
      }

      // The form paints the name, the code and the city. The id is a selection
      // key and a callback argument, never a widget's text.
      final String form = flatCodeOf(named('retailer_invite_staff_form.dart'));
      expect(form.contains('Text(shop.id'), isFalse);
      expect(form.contains('shop.id.toString'), isFalse);
      expect(
        form.contains('cubit.shopSelectionToggled(shop.id)'),
        isTrue,
        reason: 'the id addresses a selection and nothing else',
      );
      expect(
        form.contains('label:shop.displayLabel'),
        isTrue,
        reason: 'the announced label is the display label, never the id',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('nothing retries', () {
    test('the outcome vocabulary has no RATE_LIMITED', () {
      expect(
        RetailerStaffInvitationCode.values.map(
          (RetailerStaffInvitationCode c) => c.token,
        ),
        isNot(contains('RATE_LIMITED')),
      );
    });

    test('no invitation source loops or schedules a resend', () {
      for (final File file in invitationSources) {
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

    test('the repository calls the sender exactly once per send', () {
      final String src = flatCodeOf(
        named('supabase_retailer_staff_invitation_repository.dart'),
      );
      expect('_rpc.sendInvitation('.allMatches(src).length, 1);
    });

    test('the cubit calls the repository send exactly once per submit', () {
      final String src = flatCodeOf(named('retailer_invite_staff_cubit.dart'));
      expect('_repository.send('.allMatches(src).length, 1);
    });

    test('a 2xx never triggers another write', () {
      // The only thing a delivered outcome triggers is the history re-read,
      // which is a read.
      final String src = codeOf(named('retailer_invite_staff_cubit.dart'));
      expect(src.contains('_rereadHistory()'), isTrue);
      expect('_rereadHistory()'.allMatches(src).length, 1);
    });
  });
}
