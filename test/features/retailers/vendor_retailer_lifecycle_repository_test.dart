import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/errors/sql_state.dart';
import 'package:sale_reward/features/retailers/data/datasources/vendor_retailer_capability_rpc_data_source.dart';
import 'package:sale_reward/features/retailers/data/datasources/vendor_retailer_lifecycle_rpc_data_source.dart';
import 'package:sale_reward/features/retailers/data/repositories/supabase_vendor_retailer_lifecycle_repository.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_lifecycle_status.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_manage_capability.dart';
import 'package:sale_reward/features/retailers/domain/repositories/vendor_retailer_write_result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/vendor_retailer_fakes.dart';
import '../../support/vendor_retailer_lifecycle_fakes.dart';

/// The lifecycle repository, driven over recording invokers.
///
/// These assert what leaves the client — the function name, the exact parameter
/// names, and, just as importantly, the parameters that are **absent** — and how
/// each answer is classified. The invokers stand in for `client.rpc`, so nothing
/// here touches Supabase.
void main() {
  late List<({String rpc, Map<String, Object?> params})> calls;
  Object? thrown;
  Object? writeBody;
  Object? capabilityBody;
  Object? capabilityThrown;

  const String relationshipId = northwindRelationshipUuid;
  const String vendorOrganizationId = '9f8e7d6c-5b4a-4392-8180-7f6e5d4c3b2a';

  setUp(() {
    calls = <({String rpc, Map<String, Object?> params})>[];
    thrown = null;
    writeBody = lifecycleRows(relationshipId: relationshipId);
    capabilityBody = true;
    capabilityThrown = null;
  });

  /// A repository whose invokers record the payload verbatim.
  ///
  /// The payload is rebuilt from the *deployed parameter-name constants*, not
  /// from restated literals — so a rename of one of those constants cannot pass
  /// these tests while breaking the real call.
  SupabaseVendorRetailerLifecycleRepository buildRepository() {
    return SupabaseVendorRetailerLifecycleRepository(
      rpc: VendorRetailerLifecycleRpcDataSource(
        setStatus:
            ({required String relationshipId, required String status}) async {
              calls.add((
                rpc: setVendorRetailerStatusRpc,
                params: <String, Object?>{
                  lifecycleRelationshipIdParameter: relationshipId,
                  lifecycleStatusParameter: status,
                },
              ));
              if (thrown != null) throw thrown!;
              return writeBody;
            },
      ),
      capability: VendorRetailerCapabilityRpcDataSource(
        probe: (String organizationId) async {
          calls.add((
            rpc: hasOrganizationPermissionRpc,
            params: <String, Object?>{
              targetOrganizationIdParameter: organizationId,
              targetPermissionCodeParameter: retailersManagePermissionCode,
            },
          ));
          if (capabilityThrown != null) throw capabilityThrown!;
          return capabilityBody;
        },
      ),
    );
  }

  Future<VendorRetailerWriteResult> deactivate() =>
      buildRepository().setRetailerStatus(
        relationshipId: relationshipId,
        status: VendorRetailerLifecycleStatus.suspended,
      );

  PostgrestException postgrest(String code) => PostgrestException(
    message: 'relation "vendor_retailers" leaked',
    code: code,
  );

  group('the RPC contract', () {
    test('35. names exactly the deployed function', () {
      expect(setVendorRetailerStatusRpc, 'set_vendor_retailer_status');
    });

    test('36. sends exactly two argument keys', () async {
      await deactivate();

      expect(calls.single.params.keys.toSet(), <String>{
        'p_relationship_id',
        'p_status',
      });
    });

    test('37. issues exactly one RPC call', () async {
      await deactivate();

      expect(calls, hasLength(1));
      expect(calls.single.rpc, 'set_vendor_retailer_status');
    });

    test('38. sends no third argument of any kind', () async {
      await deactivate();

      for (final String forbidden in <String>[
        'p_vendor_organization_id',
        'p_retailer_organization_id',
        'p_organization_id',
        'p_user_id',
        'p_profile_id',
        'p_membership_id',
        'p_actor',
        'p_role',
        'p_permission',
        'p_current_status',
        'p_audit_action',
        'p_timestamp',
        'target_organization_id',
      ]) {
        expect(
          calls.single.params.containsKey(forbidden),
          isFalse,
          reason: 'the lifecycle write must send no $forbidden',
        );
      }
    });

    test('39. an ACTIVE request is sent as the token ACTIVE', () async {
      await buildRepository().setRetailerStatus(
        relationshipId: relationshipId,
        status: VendorRetailerLifecycleStatus.active,
      );

      expect(calls.single.params['p_status'], 'ACTIVE');
    });

    test('40. a SUSPENDED request is sent as the token SUSPENDED', () async {
      await deactivate();

      expect(calls.single.params['p_status'], 'SUSPENDED');
    });

    test('41. INACTIVE is never sent, for either direction', () async {
      for (final VendorRetailerLifecycleStatus status
          in VendorRetailerLifecycleStatus.values) {
        calls.clear();
        await buildRepository().setRetailerStatus(
          relationshipId: relationshipId,
          status: status,
        );
        expect(calls.single.params['p_status'], isNot('INACTIVE'));
        expect(calls.single.params['p_status'], isNot('DEACTIVATED'));
        expect(<String>[
          'ACTIVE',
          'SUSPENDED',
        ], contains(calls.single.params['p_status']));
      }
    });

    test('the submitted relationship id is sent verbatim', () async {
      await deactivate();

      expect(calls.single.params['p_relationship_id'], relationshipId);
    });

    test('43. nothing is retried after any failure', () async {
      for (final String code in <String>['42501', '23514', '55000', '22P02']) {
        calls.clear();
        thrown = postgrest(code);
        await deactivate();
        expect(
          calls,
          hasLength(1),
          reason: 'SQLSTATE $code must not produce a second call',
        );
      }

      calls.clear();
      thrown = StateError('transport');
      await deactivate();
      expect(calls, hasLength(1));
    });

    test('nothing is retried after an unconfirmed success either', () async {
      writeBody = <Map<String, Object?>>[];

      final VendorRetailerWriteResult result = await deactivate();

      expect(result, isA<VendorRetailerWriteUnconfirmed>());
      expect(calls, hasLength(1));
    });
  });

  group('SQLSTATE mapping', () {
    Future<Failure> failureFor(Object error) async {
      thrown = error;
      final VendorRetailerWriteResult result = await deactivate();
      return (result as VendorRetailerWriteFailure).failure;
    }

    test('44. 42501 maps to DeniedFailure', () async {
      expect(SqlState.insufficientPrivilege, '42501');
      // One wording for an unauthenticated caller, a caller without
      // RETAILERS_MANAGE, an unknown relationship, another Vendor's
      // relationship, and a non-RETAILER target. SQL refuses all five
      // identically.
      expect(
        await failureFor(postgrest(SqlState.insufficientPrivilege)),
        isA<DeniedFailure>(),
      );
    });

    test('45. 23514 maps to InvalidFailure', () async {
      expect(SqlState.checkViolation, '23514');
      expect(
        await failureFor(postgrest(SqlState.checkViolation)),
        isA<InvalidFailure>(),
      );
    });

    test('46. 55000 maps to NotReadyFailure', () async {
      expect(SqlState.objectNotInPrerequisiteState, '55000');
      expect(
        await failureFor(postgrest(SqlState.objectNotInPrerequisiteState)),
        isA<NotReadyFailure>(),
      );
    });

    test('47. 22P02 maps to InvalidFailure, not Unavailable', () async {
      // Raised by the type system before the function body runs, so retrying
      // cannot fix it. Mapped locally rather than in the shared mapper, whose
      // every other caller currently folds 22P02 into UnavailableFailure.
      expect(SqlState.invalidTextRepresentation, '22P02');
      expect(
        await failureFor(postgrest(SqlState.invalidTextRepresentation)),
        isA<InvalidFailure>(),
      );
    });

    test('48. an unexpected SQLSTATE maps to UnavailableFailure', () async {
      expect(
        await failureFor(postgrest('23505')),
        isA<DuplicateFailure>(),
        reason: 'the shared mapper still classifies known codes',
      );
      expect(await failureFor(postgrest('XX000')), isA<UnavailableFailure>());
      expect(
        await failureFor(StateError('transport')),
        isA<UnavailableFailure>(),
      );
    });

    test('an AuthException maps to UnauthenticatedFailure', () async {
      expect(
        await failureFor(const AuthException('token expired')),
        isA<UnauthenticatedFailure>(),
      );
    });

    test('49. the raw backend message is never exposed', () async {
      thrown = postgrest('42501');
      final VendorRetailerWriteResult result = await deactivate();
      final Failure failure = (result as VendorRetailerWriteFailure).failure;

      // A Failure carries a discriminant and at most a form-field key. Nothing
      // that reaches a screen may contain the message, the table name or the
      // SQLSTATE.
      expect(failure.toString(), isNot(contains('vendor_retailers')));
      expect(failure.toString(), isNot(contains('42501')));
      expect(failure.props.whereType<String>(), isEmpty);
    });
  });

  group('response classification', () {
    test('a described success carries the confirmed status and flag', () async {
      final VendorRetailerWriteResult result = await deactivate();

      final VendorRetailerWriteSuccess success =
          result as VendorRetailerWriteSuccess;
      expect(success.confirmedStatus, VendorRetailerLifecycleStatus.suspended);
      expect(success.statusChanged, isTrue);
    });

    test(
      'the confirmed status is the response\'s, not the request\'s',
      () async {
        // The two agree on the ordinary path. Stating the database's answer is
        // what keeps this honest when they do not.
        writeBody = lifecycleRows(
          relationshipId: relationshipId,
          retailerStatus: 'ACTIVE',
          relationshipStatus: 'ACTIVE',
        );

        final VendorRetailerWriteResult result = await deactivate();

        expect(
          (result as VendorRetailerWriteSuccess).confirmedStatus,
          VendorRetailerLifecycleStatus.active,
        );
      },
    );

    test('an idempotent no-op is a success, not a failure', () async {
      writeBody = lifecycleRows(
        relationshipId: relationshipId,
        statusChanged: false,
      );

      final VendorRetailerWriteResult result = await deactivate();

      expect((result as VendorRetailerWriteSuccess).statusChanged, isFalse);
    });

    test(
      '50. every malformed successful response is Unconfirmed, not Failure',
      () async {
        for (final Object? body in <Object?>[
          null,
          <Map<String, Object?>>[],
          <Map<String, Object?>>[
            lifecycleRow(relationshipId: relationshipId),
            lifecycleRow(relationshipId: relationshipId),
          ],
          lifecycleRows(relationshipId: contosoRelationshipUuid),
          lifecycleRows(relationshipId: 'not-a-uuid'),
          lifecycleRows(
            relationshipId: relationshipId,
            retailerStatus: 'INACTIVE',
          ),
          lifecycleRows(
            relationshipId: relationshipId,
            retailerStatus: 'ACTIVE',
            relationshipStatus: 'SUSPENDED',
          ),
          lifecycleRows(relationshipId: relationshipId, statusChanged: 'yes'),
          'a string',
          42,
        ]) {
          writeBody = body;
          final VendorRetailerWriteResult result = await deactivate();

          expect(
            result,
            isA<VendorRetailerWriteUnconfirmed>(),
            reason: 'body $body must be unconfirmed, never a failure',
          );
          expect(result, isNot(isA<VendorRetailerWriteFailure>()));
          expect(result, isNot(isA<VendorRetailerWriteSuccess>()));
        }
      },
    );
  });

  group('the capability probe', () {
    Future<VendorRetailerManageCapability> probe() =>
        buildRepository().manageCapability(vendorOrganizationId);

    test('names the deployed helper and the approved permission', () async {
      await probe();

      expect(calls.single.rpc, 'has_organization_permission');
      expect(calls.single.params, <String, Object?>{
        'target_organization_id': vendorOrganizationId,
        'target_permission_code': 'RETAILERS_MANAGE',
      });
    });

    test('51. true resolves to confirmed', () async {
      capabilityBody = true;
      expect(await probe(), VendorRetailerManageCapability.confirmed);
    });

    test('52. false resolves to denied', () async {
      capabilityBody = false;
      expect(await probe(), VendorRetailerManageCapability.denied);
    });

    test('53. a non-boolean resolves to unavailable, never denied', () async {
      // Coercing null or a string to `false` would assert a definite denial this
      // client has no grounds for.
      for (final Object? body in <Object?>[
        null,
        'true',
        1,
        0,
        <String>[],
        <String, Object?>{'ok': true},
      ]) {
        capabilityBody = body;
        expect(
          await probe(),
          VendorRetailerManageCapability.unavailable,
          reason: 'body $body must be unavailable',
        );
      }
    });

    test(
      '54. a backend or transport failure resolves to unavailable',
      () async {
        for (final Object error in <Object>[
          postgrest('42501'),
          postgrest('XX000'),
          const AuthException('expired'),
          StateError('transport'),
        ]) {
          capabilityThrown = error;
          expect(
            await probe(),
            VendorRetailerManageCapability.unavailable,
            reason: '$error must be unavailable, never denied',
          );
        }
      },
    );

    test('60. the probe is pointed at the organization it was given', () async {
      // The repository sends what it is handed and derives nothing. Which id
      // that is — the session's Vendor, never a Retailer — is the shell's
      // decision, asserted in the flow test.
      await buildRepository().manageCapability(vendorOrganizationId);

      expect(
        calls.single.params['target_organization_id'],
        vendorOrganizationId,
      );
      expect(
        calls.single.params['target_organization_id'],
        isNot(northwindOrganizationUuid),
      );
    });

    test('isConfirmed is positive equality across every member', () {
      expect(VendorRetailerManageCapability.confirmed.isConfirmed, isTrue);
      expect(VendorRetailerManageCapability.denied.isConfirmed, isFalse);
      expect(VendorRetailerManageCapability.unavailable.isConfirmed, isFalse);
      // 58. Exactly one member may ever be confirmed, so a member added later
      // fails closed without this test or the helper being edited.
      expect(
        VendorRetailerManageCapability.values
            .where((VendorRetailerManageCapability c) => c.isConfirmed)
            .toList(),
        <VendorRetailerManageCapability>[
          VendorRetailerManageCapability.confirmed,
        ],
      );
    });
  });

  group('42. no direct table access exists on this path', () {
    test('a write issues the lifecycle RPC and nothing else', () async {
      await deactivate();

      expect(
        calls.map((({String rpc, Map<String, Object?> params}) c) => c.rpc),
        <String>['set_vendor_retailer_status'],
      );
    });

    test('a probe issues the permission RPC and nothing else', () async {
      await buildRepository().manageCapability(vendorOrganizationId);

      expect(
        calls.map((({String rpc, Map<String, Object?> params}) c) => c.rpc),
        <String>['has_organization_permission'],
      );
    });
  });
}
