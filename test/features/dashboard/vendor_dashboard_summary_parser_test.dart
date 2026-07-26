import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/dashboard/data/models/vendor_dashboard_summary_parser.dart';
import 'package:sale_reward/features/dashboard/domain/entities/vendor_dashboard_summary.dart';

import '../../support/vendor_dashboard_fakes.dart';

/// The parser is the boundary between "what the backend said" and "what the
/// screen believes".
///
/// Every rejection below is a rejection rather than a repair, and each repair it
/// declines to make would be a specific lie:
///
/// * a missing or malformed count substituted with `0` would tell a Vendor they
///   have no members, or that nothing has ever happened in their organization;
/// * a negative count clamped to `0` would state a figure `count(*)` cannot
///   produce;
/// * a count above the exactly-representable range rendered anyway would show a
///   different number on Flutter web than on the VM and than on the web app;
/// * a two-row answer reduced to its first row would render figures whose
///   provenance this build cannot explain;
/// * a zero-row answer treated as an empty summary would render four zeros the
///   backend never sent.
void main() {
  VendorDashboardSummary parseRow(Map<String, Object?> row) =>
      VendorDashboardSummaryParser.parse(dashboardSummaryBody(row));

  Matcher throwsFormat() => throwsA(isA<VendorDashboardFormatException>());

  group('a well-formed summary', () {
    test('carries the four counts in the contract fields', () {
      final VendorDashboardSummary summary = parseRow(dashboardSummaryRow());

      expect(summary.activeMemberCount, 7);
      expect(summary.catalogActiveRoleCount, 6);
      expect(summary.catalogPermissionCount, 18);
      expect(summary.auditEventCount, 1204);
    });

    test('the four fields are not interchanged', () {
      // Four distinct values, so a transposed pair cannot pass.
      final VendorDashboardSummary summary = parseRow(
        dashboardSummaryRow(
          activeMemberCount: 1,
          catalogActiveRoleCount: 2,
          catalogPermissionCount: 3,
          auditEventCount: 4,
        ),
      );

      expect(summary.activeMemberCount, 1);
      expect(summary.catalogActiveRoleCount, 2);
      expect(summary.catalogPermissionCount, 3);
      expect(summary.auditEventCount, 4);
    });

    test('zero is a real count for every field', () {
      // The reachable shape for a brand-new Vendor is zeros on the two tenant
      // counts beside non-zero catalogue counts, but all four are permitted.
      final VendorDashboardSummary summary = parseRow(
        dashboardSummaryRow(
          activeMemberCount: 0,
          catalogActiveRoleCount: 0,
          catalogPermissionCount: 0,
          auditEventCount: 0,
        ),
      );

      expect(summary, allZeroDashboardSummary);
    });

    test('an authorized Vendor with no tenant data parses normally', () {
      final VendorDashboardSummary summary = parseRow(
        dashboardSummaryRow(activeMemberCount: 0, auditEventCount: 0),
      );

      expect(summary.activeMemberCount, 0);
      expect(summary.auditEventCount, 0);
      // The catalogue counts are global and stay non-zero — which is precisely
      // why "all four are zero" must never be how a denial is represented.
      expect(summary.catalogActiveRoleCount, greaterThan(0));
      expect(summary.catalogPermissionCount, greaterThan(0));
    });

    test('a large count inside the exact integer range is kept exactly', () {
      final VendorDashboardSummary summary = parseRow(
        dashboardSummaryRow(auditEventCount: maxSafeVendorDashboardCount),
      );

      expect(summary.auditEventCount, maxSafeVendorDashboardCount);
      // Not rounded, not truncated, not passed through a double.
      expect(summary.auditEventCount, 9007199254740991);
    });

    test('a several-million audit total is kept exactly', () {
      final VendorDashboardSummary summary = parseRow(
        dashboardSummaryRow(auditEventCount: 4294967296),
      );

      expect(summary.auditEventCount, 4294967296);
    });

    test('unknown extra keys are ignored rather than rejected', () {
      // Forward compatibility: the backend increments nothing for an added
      // column, so a future field must not break this build.
      final VendorDashboardSummary summary = parseRow(<String, Object?>{
        ...dashboardSummaryRow(),
        'something_added_later': 42,
      });

      expect(summary, exampleDashboardSummary);
    });
  });

  group('the row count is checked, not assumed', () {
    test('zero rows is malformed, never an empty summary', () {
      // Structurally unreachable for an authorized caller — the function body is
      // a select with no from-clause — so an empty list means this build and the
      // deployed function disagree.
      expect(
        () => VendorDashboardSummaryParser.parse(<Object?>[]),
        throwsFormat(),
      );
    });

    test('two rows is malformed, and the first is not taken', () {
      expect(
        () => VendorDashboardSummaryParser.parse(<Object?>[
          dashboardSummaryRow(),
          dashboardSummaryRow(activeMemberCount: 99),
        ]),
        throwsFormat(),
      );
    });

    test('a body that is not a list is malformed', () {
      expect(
        () => VendorDashboardSummaryParser.parse(dashboardSummaryRow()),
        throwsFormat(),
      );
    });

    test('a null body is malformed', () {
      expect(() => VendorDashboardSummaryParser.parse(null), throwsFormat());
    });

    test('a row that is not an object is malformed', () {
      expect(
        () => VendorDashboardSummaryParser.parse(<Object?>[7]),
        throwsFormat(),
      );
    });
  });

  group('every count is required', () {
    for (final String field in <String>[
      'active_member_count',
      'catalog_active_role_count',
      'catalog_permission_count',
      'audit_event_count',
    ]) {
      test('a missing $field fails the whole summary', () {
        final Map<String, Object?> row = dashboardSummaryRow()..remove(field);

        expect(
          () => VendorDashboardSummaryParser.parse(<Object?>[row]),
          throwsFormat(),
        );
      });

      test('a null $field fails the whole summary', () {
        // NOT NULL in the contract. A null is not "none".
        final Map<String, Object?> row = dashboardSummaryRow();
        row[field] = null;

        expect(
          () => VendorDashboardSummaryParser.parse(<Object?>[row]),
          throwsFormat(),
        );
      });

      test('a negative $field is refused rather than clamped', () {
        final Map<String, Object?> row = dashboardSummaryRow();
        row[field] = -1;

        expect(
          () => VendorDashboardSummaryParser.parse(<Object?>[row]),
          throwsFormat(),
        );
      });

      test('a $field arriving as text is refused', () {
        final Map<String, Object?> row = dashboardSummaryRow();
        row[field] = '7';

        expect(
          () => VendorDashboardSummaryParser.parse(<Object?>[row]),
          throwsFormat(),
        );
      });

      test('a fractional $field is refused', () {
        final Map<String, Object?> row = dashboardSummaryRow();
        row[field] = 7.5;

        expect(
          () => VendorDashboardSummaryParser.parse(<Object?>[row]),
          throwsFormat(),
        );
      });

      test('a boolean $field is refused', () {
        final Map<String, Object?> row = dashboardSummaryRow();
        row[field] = true;

        expect(
          () => VendorDashboardSummaryParser.parse(<Object?>[row]),
          throwsFormat(),
        );
      });

      test('a $field beyond the exact integer range is refused', () {
        final Map<String, Object?> row = dashboardSummaryRow();
        row[field] = maxSafeVendorDashboardCount + 1;

        expect(
          () => VendorDashboardSummaryParser.parse(<Object?>[row]),
          throwsFormat(),
        );
      });
    }

    test('a malformed fourth field fails the first three too', () {
      // The four counts are one snapshot. There is no partial summary to emit,
      // and no path here that could construct one.
      final Map<String, Object?> row = dashboardSummaryRow();
      row['audit_event_count'] = 'lots';

      expect(
        () => VendorDashboardSummaryParser.parse(<Object?>[row]),
        throwsFormat(),
      );
    });
  });

  group('the entity carries counts and nothing else', () {
    test('there is no organization name or id anywhere on it', () {
      // The summary RPC returns counts only. The organization name comes from
      // the trusted session context, and nothing here could hold a second copy.
      final String source = exampleDashboardSummary.props.join(',');

      expect(exampleDashboardSummary.props, hasLength(4));
      expect(
        exampleDashboardSummary.props.every((Object? p) => p is int),
        isTrue,
      );
      expect(source, isNot(contains('-')));
    });

    test('equality is by the four counts', () {
      expect(
        parseRow(dashboardSummaryRow()),
        const VendorDashboardSummary(
          activeMemberCount: 7,
          catalogActiveRoleCount: 6,
          catalogPermissionCount: 18,
          auditEventCount: 1204,
        ),
      );
      expect(
        parseRow(dashboardSummaryRow(activeMemberCount: 8)),
        isNot(exampleDashboardSummary),
      );
    });
  });

  group('the exception itself leaks nothing', () {
    test('its reason names a field, never a value from the response', () {
      // A reason that echoed the offending value would put backend content into
      // a developer log — and, one careless edit later, onto a screen.
      Object? caught;
      try {
        final Map<String, Object?> row = dashboardSummaryRow();
        row['active_member_count'] = 'Northwind Trading';
        VendorDashboardSummaryParser.parse(<Object?>[row]);
      } on VendorDashboardFormatException catch (error) {
        caught = error;
      }

      expect(caught, isA<VendorDashboardFormatException>());
      expect(
        (caught! as VendorDashboardFormatException).reason,
        isNot(contains('Northwind')),
      );
      expect(caught.toString(), isNot(contains('Northwind')));
    });
  });
}
