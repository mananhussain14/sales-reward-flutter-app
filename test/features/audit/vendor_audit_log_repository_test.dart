import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/core/result/read_result.dart';
import 'package:sale_reward/features/audit/data/datasources/vendor_audit_log_rpc_data_source.dart';
import 'package:sale_reward/features/audit/data/repositories/supabase_vendor_audit_log_repository.dart';
import 'package:sale_reward/features/audit/domain/entities/vendor_audit_log_entry.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/vendor_audit_log_fakes.dart';

/// The data layer's contract with the backend.
///
/// Four properties are asserted over and over, because each is a security
/// boundary rather than a convenience:
///
/// 1. **Exactly three parameters travel, and they are a page size and a two-part
///    cursor.** No auth user id, profile id, membership id, organization or
///    tenant, role, permission, actor, entity, offset or page number.
/// 2. **The cursor is whole or absent.** Both halves come from the same row, and
///    a half cursor — which the backend refuses with `22023` — cannot be
///    expressed.
/// 3. **The page size is a fixed 50**, which is inside the backend's `1 … 100`
///    range, so this client can never provoke the out-of-range refusal whose
///    natural misreading is "I have reached the end of the history".
/// 4. **A thrown call is classified by SQLSTATE, and an unreadable body is an
///    outage** — never a denial, and never a fabricated empty history.
void main() {
  late List<Map<String, Object?>> sentParams;
  Object? body = auditLogRows();
  Object? thrown;

  setUp(() {
    sentParams = <Map<String, Object?>>[];
    body = auditLogRows();
    thrown = null;
  });

  SupabaseVendorAuditLogRepository buildRepository() {
    return SupabaseVendorAuditLogRepository(
      rpc: VendorAuditLogRpcDataSource(
        auditLogs:
            ({
              required int limit,
              required String? beforeOccurredAt,
              required String? beforeAuditLogId,
            }) async {
              sentParams.add(<String, Object?>{
                auditLimitParameter: limit,
                auditBeforeOccurredAtParameter: beforeOccurredAt,
                auditBeforeAuditLogIdParameter: beforeAuditLogId,
              });
              if (thrown != null) throw thrown!;
              return body;
            },
      ),
    );
  }

  PostgrestException postgrest(String code) => PostgrestException(
    message: 'backend detail that must not escape',
    code: code,
  );

  group('the RPC contract', () {
    test('the first page sends limit 50 and both cursor halves null', () async {
      await buildRepository().auditLogs();

      expect(sentParams, hasLength(1));
      expect(sentParams.single, <String, Object?>{
        'p_limit': 50,
        'p_before_occurred_at': null,
        'p_before_audit_log_id': null,
      });
    });

    test(
      'an older page sends the final row timestamp and that row id',
      () async {
        await buildRepository().auditLogs(
          before: (
            occurredAt: DateTime.utc(2026, 7, 24, 6, 30),
            auditLogId: futureActionAuditId,
          ),
        );

        expect(sentParams.single, <String, Object?>{
          'p_limit': 50,
          'p_before_occurred_at': '2026-07-24T06:30:00.000Z',
          'p_before_audit_log_id': futureActionAuditId,
        });
      },
    );

    test('a local-zone cursor is sent as the same UTC instant', () async {
      // The position must not move with the device's clock settings.
      final DateTime utc = DateTime.utc(2026, 7, 24, 6, 30);
      await buildRepository().auditLogs(
        before: (occurredAt: utc.toLocal(), auditLogId: futureActionAuditId),
      );

      expect(
        sentParams.single[auditBeforeOccurredAtParameter],
        '2026-07-24T06:30:00.000Z',
      );
    });

    test('exactly three parameter names are ever sent', () async {
      final SupabaseVendorAuditLogRepository repository = buildRepository();
      await repository.auditLogs();
      await repository.auditLogs(
        before: (
          occurredAt: DateTime.utc(2026, 7, 24),
          auditLogId: futureActionAuditId,
        ),
      );

      for (final Map<String, Object?> params in sentParams) {
        expect(params.keys.toSet(), <String>{
          'p_limit',
          'p_before_occurred_at',
          'p_before_audit_log_id',
        });
      }
    });

    test('no identity, tenant, role, permission or offset argument', () async {
      final SupabaseVendorAuditLogRepository repository = buildRepository();
      await repository.auditLogs();
      await repository.auditLogs(
        before: (
          occurredAt: DateTime.utc(2026, 7, 24),
          auditLogId: futureActionAuditId,
        ),
      );

      final Set<String> keys = sentParams
          .expand((Map<String, Object?> p) => p.keys)
          .toSet();

      for (final String forbidden in <String>[
        'p_user_id',
        'p_auth_user_id',
        'p_profile_id',
        'p_membership_id',
        'p_organization_id',
        'p_vendor_organization_id',
        'p_tenant_id',
        'p_role_code',
        'p_permission_code',
        'p_actor_profile_id',
        'p_actor',
        'p_entity_type',
        'p_entity_id',
        'p_action',
        'p_offset',
        'p_page',
        'p_search',
      ]) {
        expect(
          keys.contains(forbidden),
          isFalse,
          reason: 'the audit RPC must pass no $forbidden argument',
        );
      }
    });

    test('the page size is always the fixed 50, never anything else', () async {
      final SupabaseVendorAuditLogRepository repository = buildRepository();
      await repository.auditLogs();
      await repository.auditLogs(
        before: (
          occurredAt: DateTime.utc(2026, 7, 24),
          auditLogId: futureActionAuditId,
        ),
      );

      for (final Map<String, Object?> params in sentParams) {
        expect(params[auditLimitParameter], vendorAuditLogPageSize);
        expect(params[auditLimitParameter], 50);
      }
      // Inside the backend's honoured range at both ends, so `22023` is
      // unreachable from this client.
      expect(vendorAuditLogPageSize, greaterThanOrEqualTo(1));
      expect(vendorAuditLogPageSize, lessThanOrEqualTo(100));
    });

    test('the cursor cannot be half-supplied', () async {
      // The type is a record of two non-nullable fields, so a half cursor is
      // unrepresentable rather than merely discouraged. Both keys are null
      // together, or neither is.
      final SupabaseVendorAuditLogRepository repository = buildRepository();
      await repository.auditLogs();
      await repository.auditLogs(
        before: (
          occurredAt: DateTime.utc(2026, 7, 24),
          auditLogId: futureActionAuditId,
        ),
      );

      for (final Map<String, Object?> params in sentParams) {
        final bool timestampNull =
            params[auditBeforeOccurredAtParameter] == null;
        final bool idNull = params[auditBeforeAuditLogIdParameter] == null;
        expect(timestampNull, idNull);
      }
    });

    test('only the one deployed function is named', () {
      final File source = File(
        'lib/features/audit/data/datasources/'
        'vendor_audit_log_rpc_data_source.dart',
      );
      final RegExp rpcNames = RegExp(r"const String \w+Rpc =\s*'([^']+)'");
      final List<String> names = rpcNames
          .allMatches(source.readAsStringSync())
          .map((RegExpMatch m) => m.group(1)!)
          .toList();

      expect(names, <String>['list_vendor_audit_logs']);
    });
  });

  group('success', () {
    test('a page is parsed into entities in the backend order', () async {
      final ReadResult<List<VendorAuditLogEntry>> result =
          await buildRepository().auditLogs();

      expect(result, isA<ReadSuccess<List<VendorAuditLogEntry>>>());
      final List<VendorAuditLogEntry> rows =
          (result as ReadSuccess<List<VendorAuditLogEntry>>).value;
      expect(rows, hasLength(2));
      expect(rows.first.auditLogId, createdProductAuditId);
      expect(rows.last.auditLogId, statusChangedAuditId);
    });

    test('an empty page is a success, never a failure', () async {
      // The backend returns `[]` both for a Vendor with no history and for a
      // cursor past the oldest row. Turning either into an outage would tell a
      // user something failed when the database answered perfectly.
      body = <Object?>[];

      final ReadResult<List<VendorAuditLogEntry>> result =
          await buildRepository().auditLogs();

      expect(result, isA<ReadSuccess<List<VendorAuditLogEntry>>>());
      expect((result as ReadSuccess<List<VendorAuditLogEntry>>).value, isEmpty);
    });
  });

  group('failure classification', () {
    test('42501 is a denial, and carries no backend text', () async {
      thrown = postgrest('42501');

      final ReadResult<List<VendorAuditLogEntry>> result =
          await buildRepository().auditLogs();

      expect(result, isA<ReadFailure<List<VendorAuditLogEntry>>>());
      expect(
        (result as ReadFailure<List<VendorAuditLogEntry>>).failure,
        isA<DeniedFailure>(),
      );
      // The discriminant carries no fields at all, so no message, permission
      // code or object name can ride along.
      expect(result.failure.props, isEmpty);
    });

    test('22023 stays an operational failure, not a denial', () async {
      // Unreachable from this client — the page size is fixed and the cursor
      // cannot be half-supplied — so arriving at it would mean this build and
      // the deployed function disagree about the contract. That is an outage the
      // user can retry past, never a statement about their access.
      thrown = postgrest('22023');

      final ReadResult<List<VendorAuditLogEntry>> result =
          await buildRepository().auditLogs();

      final Failure failure =
          (result as ReadFailure<List<VendorAuditLogEntry>>).failure;
      expect(failure, isA<UnavailableFailure>());
      expect(failure, isNot(isA<DeniedFailure>()));
    });

    test('a transport failure is an outage, never a denial', () async {
      thrown = const SocketException('no route to host');

      final ReadResult<List<VendorAuditLogEntry>> result =
          await buildRepository().auditLogs();

      final Failure failure =
          (result as ReadFailure<List<VendorAuditLogEntry>>).failure;
      expect(failure, isA<UnavailableFailure>());
      expect(failure, isNot(isA<DeniedFailure>()));
    });

    test('an expired session is unauthenticated, not denied', () async {
      thrown = const AuthException('jwt expired');

      final ReadResult<List<VendorAuditLogEntry>> result =
          await buildRepository().auditLogs();

      expect(
        (result as ReadFailure<List<VendorAuditLogEntry>>).failure,
        isA<UnauthenticatedFailure>(),
      );
    });

    test('a malformed body is an outage, never an empty history', () async {
      // Fabricating `[]` would tell a Vendor that nothing has ever happened in
      // their organization when the response simply could not be understood.
      body = <Object?>[auditLogRow(actorType: 'USER', actorDisplayName: null)];

      final ReadResult<List<VendorAuditLogEntry>> result =
          await buildRepository().auditLogs();

      expect(result, isA<ReadFailure<List<VendorAuditLogEntry>>>());
      expect(
        (result as ReadFailure<List<VendorAuditLogEntry>>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('a body that is not a list is an outage', () async {
      body = <String, Object?>{'rows': 0};

      final ReadResult<List<VendorAuditLogEntry>> result =
          await buildRepository().auditLogs();

      expect(
        (result as ReadFailure<List<VendorAuditLogEntry>>).failure,
        isA<UnavailableFailure>(),
      );
    });

    test('a denial on an older page does not become an empty page', () async {
      thrown = postgrest('42501');

      final ReadResult<List<VendorAuditLogEntry>> result =
          await buildRepository().auditLogs(
            before: (
              occurredAt: DateTime.utc(2026, 7, 24),
              auditLogId: futureActionAuditId,
            ),
          );

      expect(result, isA<ReadFailure<List<VendorAuditLogEntry>>>());
      expect(
        (result as ReadFailure<List<VendorAuditLogEntry>>).failure,
        isA<DeniedFailure>(),
      );
    });
  });

  group('no table is read and no key is held', () {
    test('the data source performs exactly one RPC and no query', () {
      final String source =
          File(
                'lib/features/audit/data/datasources/'
                'vendor_audit_log_rpc_data_source.dart',
              )
              .readAsLinesSync()
              .where((String line) {
                final String trimmed = line.trimLeft();
                return !trimmed.startsWith('//') && !trimmed.startsWith('*');
              })
              .join('\n');

      for (final String forbidden in <String>[
        '.from(',
        '.select(',
        '.eq(',
        '.insert(',
        '.update(',
        '.delete(',
        'service_role',
        'serviceRoleKey',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason: 'the audit data source must not contain $forbidden',
        );
      }
      expect(source.contains('client.rpc<Object?>('), isTrue);
    });
  });
}
