import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/audit/data/models/vendor_audit_log_parsers.dart';
import 'package:sale_reward/features/audit/domain/entities/vendor_audit_actor_type.dart';
import 'package:sale_reward/features/audit/domain/entities/vendor_audit_log_entry.dart';

import '../../support/vendor_audit_log_fakes.dart';

/// The parser is the boundary between a JSON body and everything downstream.
///
/// Two rules run through every case below, and each is a security property
/// rather than a style:
///
/// 1. **Nothing is defaulted.** A missing, blank or wrongly-typed required field
///    throws rather than becoming a value the backend never sent — which is how
///    a malformed response becomes a fabricated audit event.
/// 2. **`actor_display_name` is non-null if and only if `actor_type` is
///    `USER`.** The backend asserts this over the whole page; this client
///    enforces it again per row, so no screen has to re-derive it and no name
///    can be attached to an actor the backend declined to name.
void main() {
  group('a valid row', () {
    test('a USER event carries its name and its whitelisted entity name', () {
      final VendorAuditLogEntry entry = VendorAuditLogEntryParser.parse(
        auditLogRow(),
      );

      expect(entry.auditLogId, createdProductAuditId);
      expect(entry.occurredAt, DateTime.utc(2026, 7, 26, 9, 5));
      expect(entry.actionCode, 'PRODUCT_CREATED');
      expect(entry.entityType, 'VENDOR_PRODUCT');
      expect(entry.entityDisplayName, 'Espresso Beans');
      expect(entry.actorType, VendorAuditActorType.user);
      expect(entry.actorDisplayName, 'Ada Vendor');
    });

    test('a SYSTEM event has no name, and that is not an error', () {
      final VendorAuditLogEntry entry = VendorAuditLogEntryParser.parse(
        auditLogRow(actorType: 'SYSTEM', actorDisplayName: null),
      );

      expect(entry.actorType, VendorAuditActorType.system);
      expect(entry.actorDisplayName, isNull);
      // The row survives in full. An audit log that dropped records whose actor
      // context is incomplete would not be an audit log.
      expect(entry.actionCode, 'PRODUCT_CREATED');
      expect(entry.entityDisplayName, 'Espresso Beans');
    });

    test('an UNKNOWN event has no name either', () {
      final VendorAuditLogEntry entry = VendorAuditLogEntryParser.parse(
        auditLogRow(actorType: 'UNKNOWN', actorDisplayName: null),
      );

      expect(entry.actorType, VendorAuditActorType.unknown);
      expect(entry.actorDisplayName, isNull);
    });

    test('the page keeps the backend order', () {
      final List<VendorAuditLogEntry> page =
          VendorAuditLogEntryParser.parseList(auditLogRows());

      expect(page, hasLength(2));
      expect(page.first.auditLogId, createdProductAuditId);
      expect(page.last.auditLogId, statusChangedAuditId);
      // Newest first, as the SQL ordered them. Nothing re-sorts.
      expect(page.first.occurredAt.isAfter(page.last.occurredAt), isTrue);
    });

    test('an empty page is a page, not a failure', () {
      expect(VendorAuditLogEntryParser.parseList(const <Object?>[]), isEmpty);
    });
  });

  group('the actor biconditional', () {
    test('USER with a null name is rejected', () {
      // Rendering an attributed action as unattributed would quietly erase the
      // one fact the row exists to record.
      expect(
        () => VendorAuditLogEntryParser.parse(
          auditLogRow(actorType: 'USER', actorDisplayName: null),
        ),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });

    test('SYSTEM with a name is rejected', () {
      expect(
        () => VendorAuditLogEntryParser.parse(
          auditLogRow(actorType: 'SYSTEM', actorDisplayName: 'Ada Vendor'),
        ),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });

    test('UNKNOWN with a name is rejected', () {
      // For UNKNOWN the actor may belong to ANOTHER Vendor, so accepting a name
      // here would be exactly the cross-tenant disclosure the scoped SQL join
      // exists to prevent.
      expect(
        () => VendorAuditLogEntryParser.parse(
          auditLogRow(actorType: 'UNKNOWN', actorDisplayName: 'Someone Else'),
        ),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });

    test('a USER name that is only whitespace is rejected', () {
      expect(
        () => VendorAuditLogEntryParser.parse(
          auditLogRow(actorDisplayName: '   '),
        ),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });
  });

  group('forward compatibility', () {
    test('an unknown actor type is kept, neutral, and never USER', () {
      final VendorAuditLogEntry entry = VendorAuditLogEntryParser.parse(
        auditLogRow(actorType: 'DELEGATED_SERVICE', actorDisplayName: null),
      );

      expect(entry.actorType, VendorAuditActorType.unrecognized);
      expect(entry.actorType, isNot(VendorAuditActorType.user));
      expect(entry.actorType, isNot(VendorAuditActorType.system));
      expect(entry.actorType, isNot(VendorAuditActorType.unknown));
      expect(entry.actorType.carriesName, isFalse);
      expect(entry.actorDisplayName, isNull);
    });

    test('an unknown actor type carrying a name is rejected', () {
      // A name is meaningful only against a known attribution rule, and this
      // build has none for a token it does not know.
      expect(
        () => VendorAuditLogEntryParser.parse(
          auditLogRow(actorType: 'DELEGATED_SERVICE', actorDisplayName: 'X'),
        ),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });

    test('an unknown action code is preserved verbatim', () {
      final VendorAuditLogEntry entry = VendorAuditLogEntryParser.parse(
        auditLogRow(actionCode: 'SOMETHING_NOT_YET_INVENTED'),
      );

      // Never dropped, never coerced to a known code, never inferred from the
      // entity type beside it.
      expect(entry.actionCode, 'SOMETHING_NOT_YET_INVENTED');
      expect(entry.entityType, 'VENDOR_PRODUCT');
    });

    test('an unknown entity type is preserved verbatim', () {
      final VendorAuditLogEntry entry = VendorAuditLogEntryParser.parse(
        auditLogRow(entityType: 'FUTURE_ENTITY', entityDisplayName: null),
      );

      expect(entry.entityType, 'FUTURE_ENTITY');
      expect(entry.entityDisplayName, isNull);
    });
  });

  group('the entity name snapshot', () {
    test('null is accepted and preserved', () {
      // Reachable through an unknown entity type, a missing key, a blank value
      // and a non-string value alike. It is never an error and never a reason to
      // hide the row.
      final VendorAuditLogEntry entry = VendorAuditLogEntryParser.parse(
        auditLogRow(entityDisplayName: null),
      );

      expect(entry.entityDisplayName, isNull);
      expect(entry.hasEntityDisplayName, isFalse);
      expect(entry.auditLogId, createdProductAuditId);
    });

    test('an absent key reads as null rather than throwing', () {
      final Map<String, Object?> row = auditLogRow()
        ..remove('entity_display_name');

      expect(VendorAuditLogEntryParser.parse(row).entityDisplayName, isNull);
    });

    test('a blank snapshot reads as unavailable, not as an empty name', () {
      expect(
        VendorAuditLogEntryParser.parse(
          auditLogRow(entityDisplayName: '   '),
        ).entityDisplayName,
        isNull,
      );
    });

    test('a non-text snapshot is malformed rather than close enough', () {
      expect(
        () =>
            VendorAuditLogEntryParser.parse(auditLogRow(entityDisplayName: 42)),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });

    test('a historical name is kept exactly as sent', () {
      // The snapshot is what the thing was called at the moment of the event —
      // not what it is called now, and not evidence that it still exists.
      final VendorAuditLogEntry entry = VendorAuditLogEntryParser.parse(
        auditLogRow(entityDisplayName: 'Old Name Before Rename'),
      );

      expect(entry.entityDisplayName, 'Old Name Before Rename');
    });
  });

  group('required fields', () {
    for (final String field in <String>[
      'audit_log_id',
      'occurred_at',
      'action_code',
      'entity_type',
      'actor_type',
    ]) {
      test('a missing $field throws', () {
        final Map<String, Object?> row = auditLogRow()..remove(field);

        expect(
          () => VendorAuditLogEntryParser.parse(row),
          throwsA(isA<VendorAuditLogFormatException>()),
        );
      });

      test('a null $field throws', () {
        final Map<String, Object?> row = auditLogRow();
        row[field] = null;

        expect(
          () => VendorAuditLogEntryParser.parse(row),
          throwsA(isA<VendorAuditLogFormatException>()),
        );
      });
    }

    test('a blank action_code throws', () {
      expect(
        () => VendorAuditLogEntryParser.parse(auditLogRow(actionCode: '  ')),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });

    test('a blank entity_type throws', () {
      expect(
        () => VendorAuditLogEntryParser.parse(auditLogRow(entityType: '')),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });

    test('a blank actor_type throws', () {
      // Emphatically not read as SYSTEM: a missing value and "no actor identity
      // remains" are different claims.
      expect(
        () => VendorAuditLogEntryParser.parse(auditLogRow(actorType: '  ')),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });
  });

  group('wrong field types', () {
    test('a non-text action_code throws', () {
      expect(
        () => VendorAuditLogEntryParser.parse(auditLogRow(actionCode: 7)),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });

    test('a non-text entity_type throws', () {
      expect(
        () => VendorAuditLogEntryParser.parse(auditLogRow(entityType: true)),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });

    test('a non-text actor_type throws', () {
      expect(
        () => VendorAuditLogEntryParser.parse(auditLogRow(actorType: 1)),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });

    test('a non-text actor_display_name throws', () {
      expect(
        () =>
            VendorAuditLogEntryParser.parse(auditLogRow(actorDisplayName: 99)),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });

    test('a numeric occurred_at throws', () {
      expect(
        () => VendorAuditLogEntryParser.parse(
          auditLogRow(occurredAt: 1785000000),
        ),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });
  });

  group('malformed identifiers and timestamps', () {
    test('a malformed audit_log_id throws', () {
      // It is half the keyset cursor. A malformed one would be put straight back
      // into a `uuid` parameter on the next page, where it raises a cast error
      // dressed as a database outage.
      expect(
        () => VendorAuditLogEntryParser.parse(auditLogRow(auditLogId: 'nope')),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });

    test('a truncated uuid throws', () {
      expect(
        () => VendorAuditLogEntryParser.parse(
          auditLogRow(auditLogId: 'a1b2c3d4-e5f6-4071-8283'),
        ),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });

    test('a malformed occurred_at throws', () {
      expect(
        () => VendorAuditLogEntryParser.parse(
          auditLogRow(occurredAt: 'the other day'),
        ),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });

    test('a timestamp is normalized to UTC', () {
      // So the cursor is sent in one representation whatever the device's zone,
      // and the only place a zone is applied is where a value is formatted.
      final VendorAuditLogEntry entry = VendorAuditLogEntryParser.parse(
        auditLogRow(occurredAt: '2026-07-26T11:05:00+02:00'),
      );

      expect(entry.occurredAt.isUtc, isTrue);
      expect(entry.occurredAt, DateTime.utc(2026, 7, 26, 9, 5));
    });

    test('one malformed row fails the whole page', () {
      // Dropping it would silently shorten a history — and because the cursor
      // comes from the LAST row, a dropped tail row would move the next page's
      // boundary and skip real events.
      expect(
        () => VendorAuditLogEntryParser.parseList(<Object?>[
          auditLogRow(),
          auditLogRow(auditLogId: 'not-a-uuid'),
        ]),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });

    test('a body that is not a list throws', () {
      expect(
        () => VendorAuditLogEntryParser.parseList(<String, Object?>{}),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });

    test('a row that is not an object throws', () {
      expect(
        () => VendorAuditLogEntryParser.parseList(<Object?>['nope']),
        throwsA(isA<VendorAuditLogFormatException>()),
      );
    });
  });

  group('the withheld columns are genuinely absent', () {
    test('the parsed entity exposes no metadata, id, IP or user agent', () {
      // A body carrying them — which the deployed function never sends — must
      // not put any of them on the entity. There is nowhere for them to go, and
      // this asserts that stays true.
      final Map<String, Object?> hostile = auditLogRow();
      hostile['metadata'] = <String, Object?>{
        'email': 'someone@example.com',
        'token_hash': 'deadbeef',
      };
      hostile['entity_id'] = 'some-entity';
      hostile['actor_profile_id'] = createdProductAuditId;
      hostile['ip_address'] = '203.0.113.7';
      hostile['user_agent'] = 'Mozilla/5.0';

      final VendorAuditLogEntry entry = VendorAuditLogEntryParser.parse(
        hostile,
      );

      // Equatable's props are exactly the seven contract fields, so a value that
      // survived would have to have been added to the entity to show up here.
      expect(entry.props, hasLength(7));
      expect(
        entry.props.whereType<String>().join(' '),
        isNot(contains('someone@example.com')),
      );
      expect(
        entry.props.whereType<String>().join(' '),
        isNot(contains('203.0.113.7')),
      );
      expect(
        entry.props.whereType<String>().join(' '),
        isNot(contains('Mozilla')),
      );
      expect(
        entry.props.whereType<String>().join(' '),
        isNot(contains('deadbeef')),
      );
    });
  });

  group('the id-shape guard', () {
    test('accepts a well-formed uuid and refuses everything else', () {
      expect(isAuditLogIdShaped(createdProductAuditId), isTrue);
      expect(isAuditLogIdShaped(''), isFalse);
      expect(isAuditLogIdShaped('1'), isFalse);
      expect(isAuditLogIdShaped('$createdProductAuditId '), isFalse);
    });
  });
}
