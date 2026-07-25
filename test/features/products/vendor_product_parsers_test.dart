import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/products/data/models/vendor_product_parsers.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assigned_retailer.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_assignment_status.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_detail.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_status.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_summary.dart';
import 'package:sale_reward/features/retailers/domain/entities/vendor_retailer_status.dart';

import '../../support/vendor_product_fakes.dart';

/// The strict parsers.
///
/// Two rules run through every test below, and both exist because a substituted
/// default is a value the backend never sent, presented as though it had:
///
/// 1. **A required field that is missing, blank or the wrong type fails the
///    read** — it never becomes a default, an empty string, a zero or an
///    `ACTIVE` status.
/// 2. **A nullable field that is genuinely null stays null** — it is never
///    fabricated from another field, and null is never conflated with "a value
///    this build does not recognise".
void main() {
  /// A parse that must be refused.
  void expectRefused(void Function() parse, String because) {
    expect(
      parse,
      throwsA(isA<VendorProductFormatException>()),
      reason: because,
    );
  }

  group('product summary — the ten list columns', () {
    test('a fully populated row parses every field', () {
      final VendorProductSummary product = VendorProductSummaryParser.parse(
        productRow(),
      );

      expect(product.productId, espressoProductUuid);
      expect(product.productCode, 'ESP-1000');
      expect(product.barcode, '5012345678900');
      expect(product.productName, 'Espresso Blend 1kg');
      expect(product.brand, 'Harvest Roasters');
      expect(product.description, 'A dark roast blend for espresso machines.');
      expect(product.status, VendorProductStatus.active);
      expect(product.activeAssignmentCount, 2);
      expect(product.createdAt, DateTime.utc(2026, 4, 18, 9, 15));
      expect(product.updatedAt, DateTime.utc(2026, 6, 2, 14, 30));
    });

    test('the list order is preserved, never re-sorted', () {
      // The SQL orders by `created_at desc, product_id desc` — total, so a
      // second sort here would be a second definition of the catalogue order.
      final List<VendorProductSummary> rows =
          VendorProductSummaryParser.parseList(productRows());

      expect(rows.map((VendorProductSummary p) => p.productCode), <String>[
        'ESP-1000',
        'DEC-2000',
      ]);
    });

    test('an empty body is an empty list, not an error', () {
      expect(VendorProductSummaryParser.parseList(const <Object?>[]), isEmpty);
    });

    test('a summary carries no assignment_count field at all', () {
      // The list does not return one. A nullable count here would collapse
      // "zero assignments" with "never asked for" — which is the whole reason
      // there are two entities.
      final VendorProductSummary product = VendorProductSummaryParser.parse(
        productRow(),
      );

      expect(product.props, hasLength(10));
      expect(product.toString(), isNot(contains('assignmentCount')));
    });

    group('nullable fields stay null', () {
      test('a null barcode is null, never the product code', () {
        final VendorProductSummary product = VendorProductSummaryParser.parse(
          productRow(barcode: null),
        );

        expect(product.barcode, isNull);
        expect(product.productCode, 'ESP-1000');
      });

      test('a null brand is null, never derived from the name', () {
        final VendorProductSummary product = VendorProductSummaryParser.parse(
          productRow(brand: null),
        );

        expect(product.brand, isNull);
      });

      test('a null description is null', () {
        final VendorProductSummary product = VendorProductSummaryParser.parse(
          productRow(description: null),
        );

        expect(product.description, isNull);
      });

      test('all three null at once is a legitimate product', () {
        final VendorProductSummary product = VendorProductSummaryParser.parse(
          productRow(barcode: null, brand: null, description: null),
        );

        expect(product.barcode, isNull);
        expect(product.brand, isNull);
        expect(product.description, isNull);
        expect(product.productName, 'Espresso Blend 1kg');
      });

      test('a blank nullable string normalizes to null', () {
        // So a screen's "is there a barcode?" test cannot be satisfied by
        // whitespace.
        final VendorProductSummary product = VendorProductSummaryParser.parse(
          productRow(barcode: '   ', brand: ''),
        );

        expect(product.barcode, isNull);
        expect(product.brand, isNull);
      });
    });

    group('status', () {
      test('ACTIVE parses to active', () {
        expect(
          VendorProductSummaryParser.parse(productRow(status: 'ACTIVE')).status,
          VendorProductStatus.active,
        );
      });

      test('INACTIVE parses to inactive, and is still returned', () {
        // An inactive product is fully readable and keeps its counts.
        final VendorProductSummary product = VendorProductSummaryParser.parse(
          productRow(status: 'INACTIVE', activeAssignmentCount: 4),
        );

        expect(product.status, VendorProductStatus.inactive);
        expect(product.status.isActive, isFalse);
        expect(product.activeAssignmentCount, 4);
      });

      test('an unknown future token degrades to unknown, never to active', () {
        final VendorProductSummary product = VendorProductSummaryParser.parse(
          productRow(status: 'ARCHIVED'),
        );

        expect(product.status, VendorProductStatus.unknown);
        expect(product.status.isActive, isFalse);
        // The raw token never reaches the entity.
        expect(product.status.code, isEmpty);
      });

      test('a lower-case token is not recognised as ACTIVE', () {
        // The comparison is exact. A case-insensitive match would accept a
        // value the CHECK constraint cannot store.
        expect(
          VendorProductSummaryParser.parse(productRow(status: 'active')).status,
          VendorProductStatus.unknown,
        );
      });
    });

    group('rejections', () {
      test('a missing product_id', () {
        expectRefused(
          () => VendorProductSummaryParser.parse(productRow(productId: null)),
          'a product with no id cannot be addressed',
        );
      });

      test('a malformed product_id', () {
        expectRefused(
          () => VendorProductSummaryParser.parse(
            productRow(productId: 'not-a-uuid'),
          ),
          'a malformed id would put a broken address behind a card',
        );
      });

      test('a missing product_code', () {
        expectRefused(
          () => VendorProductSummaryParser.parse(productRow(productCode: null)),
          'product_code is NOT NULL',
        );
      });

      test('a product_code of the wrong type', () {
        expectRefused(
          () => VendorProductSummaryParser.parse(productRow(productCode: 42)),
          'a text column arriving as a number is a shape this build cannot read',
        );
      });

      test('a blank product_code', () {
        expectRefused(
          () => VendorProductSummaryParser.parse(productRow(productCode: '  ')),
          'the schema normalizes and shape-checks the code; blank is not data',
        );
      });

      test('a missing product_name', () {
        expectRefused(
          () => VendorProductSummaryParser.parse(productRow(productName: null)),
          'product_name is NOT NULL',
        );
      });

      test('a product_name of the wrong type', () {
        expectRefused(
          () => VendorProductSummaryParser.parse(
            productRow(productName: <int>[]),
          ),
          'a list where a name belongs is malformed',
        );
      });

      test('a missing status', () {
        expectRefused(
          () => VendorProductSummaryParser.parse(productRow(status: null)),
          'an absent status must never be read as ACTIVE',
        );
      });

      test('a blank status', () {
        expectRefused(
          () => VendorProductSummaryParser.parse(productRow(status: '')),
          'blank is a required value the response did not supply, not a token',
        );
      });

      test('a malformed active_assignment_count', () {
        expectRefused(
          () => VendorProductSummaryParser.parse(
            productRow(activeAssignmentCount: '2'),
          ),
          'a numeric column arriving as text is a shape this build cannot read',
        );
      });

      test('a negative active_assignment_count', () {
        expectRefused(
          () => VendorProductSummaryParser.parse(
            productRow(activeAssignmentCount: -1),
          ),
          'count(*) cannot be negative; clamping would fabricate a figure',
        );
      });

      test('a missing active_assignment_count', () {
        expectRefused(
          () => VendorProductSummaryParser.parse(
            productRow(activeAssignmentCount: null),
          ),
          'the count is NOT NULL; zero is sent as zero',
        );
      });

      test('a missing created_at', () {
        expectRefused(
          () => VendorProductSummaryParser.parse(productRow(createdAt: null)),
          'created_at is NOT NULL',
        );
      });

      test('a malformed created_at', () {
        expectRefused(
          () => VendorProductSummaryParser.parse(
            productRow(createdAt: 'yesterday'),
          ),
          'an unparseable timestamp is not a date this build may render',
        );
      });

      test('a missing updated_at', () {
        expectRefused(
          () => VendorProductSummaryParser.parse(productRow(updatedAt: null)),
          'updated_at is NOT NULL',
        );
      });

      test('a malformed updated_at', () {
        expectRefused(
          () => VendorProductSummaryParser.parse(
            productRow(updatedAt: 1717171717),
          ),
          'an epoch number is not the timestamptz string the contract sends',
        );
      });

      test('a barcode of the wrong type', () {
        expectRefused(
          () => VendorProductSummaryParser.parse(productRow(barcode: 5012345)),
          'a nullable text column may be null, never a number',
        );
      });

      test('a brand of the wrong type', () {
        expectRefused(
          () => VendorProductSummaryParser.parse(productRow(brand: true)),
          'a nullable text column may be null, never a boolean',
        );
      });

      test('a description of the wrong type', () {
        expectRefused(
          () => VendorProductSummaryParser.parse(
            productRow(description: <String, Object?>{}),
          ),
          'a nullable text column may be null, never an object',
        );
      });

      test('a body that is not a list', () {
        expectRefused(
          () => VendorProductSummaryParser.parseList(<String, Object?>{
            'product_id': espressoProductUuid,
          }),
          'a single object is not the row set this read returns',
        );
      });

      test('a row that is not an object', () {
        expectRefused(
          () => VendorProductSummaryParser.parseList(<Object?>['ESP-1000']),
          'a bare string is not a row',
        );
      });

      test('one malformed row fails the whole list', () {
        // Dropping it would silently shorten a catalogue with no sign that
        // anything was missing.
        expectRefused(
          () => VendorProductSummaryParser.parseList(<Map<String, Object?>>[
            productRow(),
            productRow(productName: null),
          ]),
          'a partial catalogue is worse than an honest retry',
        );
      });
    });

    test('a count arriving as an integral double is accepted', () {
      // JSON has one number type and a transport is entitled to hand back 2.0.
      expect(
        VendorProductSummaryParser.parse(
          productRow(activeAssignmentCount: 2.0),
        ).activeAssignmentCount,
        2,
      );
    });

    test('timestamps are normalized to UTC', () {
      final VendorProductSummary product = VendorProductSummaryParser.parse(
        productRow(createdAt: '2026-04-18T14:15:00+05:00'),
      );

      expect(product.createdAt.isUtc, isTrue);
      expect(product.createdAt, DateTime.utc(2026, 4, 18, 9, 15));
    });
  });

  group('product detail — the list columns plus assignment_count', () {
    test('a single row parses, including the extra count', () {
      final VendorProductDetail? detail = VendorProductDetailParser.parseSingle(
        <Map<String, Object?>>[productDetailRow()],
      );

      expect(detail, isNotNull);
      expect(detail!.productId, espressoProductUuid);
      expect(detail.assignmentCount, 3);
      expect(detail.activeAssignmentCount, 2);
      expect(detail.inactiveAssignmentCount, 1);
      expect(detail.hasNoAssignments, isFalse);
    });

    test('the eleven fields are the ten plus one', () {
      // The relationship the backend pins structurally: every shared column is
      // byte-identical, and `assignment_count` is the only addition.
      final VendorProductDetail detail = VendorProductDetailParser.parse(
        productDetailRow(),
      );
      final VendorProductSummary summary = VendorProductSummaryParser.parse(
        productRow(),
      );

      expect(detail.props, hasLength(summary.props.length + 1));
      expect(detail.productId, summary.productId);
      expect(detail.productCode, summary.productCode);
      expect(detail.barcode, summary.barcode);
      expect(detail.productName, summary.productName);
      expect(detail.brand, summary.brand);
      expect(detail.description, summary.description);
      expect(detail.status, summary.status);
      expect(detail.activeAssignmentCount, summary.activeAssignmentCount);
      expect(detail.createdAt, summary.createdAt);
      expect(detail.updatedAt, summary.updatedAt);
    });

    test('zero rows is null, not an error', () {
      // The backend's answer for an unknown id, another Vendor's id, an id from
      // another table and null alike — one representation for all four.
      expect(VendorProductDetailParser.parseSingle(const <Object?>[]), isNull);
    });

    test('more than one row is refused', () {
      expectRefused(
        () => VendorProductDetailParser.parseSingle(<Map<String, Object?>>[
          productDetailRow(),
          productDetailRow(productId: decafProductUuid),
        ]),
        'the function filters on a primary key and the derived Vendor',
      );
    });

    test('both counts zero is a real answer, never null', () {
      final VendorProductDetail detail = VendorProductDetailParser.parse(
        productDetailRow(assignmentCount: 0, activeAssignmentCount: 0),
      );

      expect(detail.assignmentCount, 0);
      expect(detail.activeAssignmentCount, 0);
      expect(detail.hasNoAssignments, isTrue);
    });

    test(
      'withdrawn-only assignments count in the total but not the active',
      () {
        final VendorProductDetail detail = VendorProductDetailParser.parse(
          productDetailRow(assignmentCount: 4, activeAssignmentCount: 0),
        );

        expect(detail.assignmentCount, 4);
        expect(detail.activeAssignmentCount, 0);
        expect(detail.inactiveAssignmentCount, 4);
        // Never assigned and no longer assigned are different states.
        expect(detail.hasNoAssignments, isFalse);
      },
    );

    test('an inactive product keeps its counts', () {
      // set_vendor_product_status deliberately does not cascade.
      final VendorProductDetail detail = VendorProductDetailParser.parse(
        productDetailRow(
          status: 'INACTIVE',
          assignmentCount: 2,
          activeAssignmentCount: 2,
        ),
      );

      expect(detail.status, VendorProductStatus.inactive);
      expect(detail.assignmentCount, 2);
      expect(detail.activeAssignmentCount, 2);
    });

    test('an unknown product status still parses and is not active', () {
      final VendorProductDetail detail = VendorProductDetailParser.parse(
        productDetailRow(status: 'DISCONTINUED'),
      );

      expect(detail.status, VendorProductStatus.unknown);
      expect(detail.status.isActive, isFalse);
    });

    test('all three nullable fields null is a legitimate product', () {
      final VendorProductDetail detail = VendorProductDetailParser.parse(
        productDetailRow(barcode: null, brand: null, description: null),
      );

      expect(detail.barcode, isNull);
      expect(detail.brand, isNull);
      expect(detail.description, isNull);
    });

    group('rejections', () {
      test('a missing assignment_count', () {
        expectRefused(
          () => VendorProductDetailParser.parse(
            productDetailRow(assignmentCount: null),
          ),
          'the total is NOT NULL; count(*) over an empty set is 0',
        );
      });

      test('a malformed assignment_count', () {
        expectRefused(
          () => VendorProductDetailParser.parse(
            productDetailRow(assignmentCount: 'three'),
          ),
          'a numeric column arriving as text is malformed',
        );
      });

      test('a negative assignment_count', () {
        expectRefused(
          () => VendorProductDetailParser.parse(
            productDetailRow(assignmentCount: -2),
          ),
          'count(*) cannot be negative',
        );
      });

      test('an active count greater than the total', () {
        // Both come from the same lateral aggregate over the same rows, so the
        // backend cannot produce this pair. Rendering "2 assignments, 5
        // currently active" would be worse than an honest retry.
        expectRefused(
          () => VendorProductDetailParser.parse(
            productDetailRow(assignmentCount: 2, activeAssignmentCount: 5),
          ),
          'the active subset can never exceed the total',
        );
      });

      test('equal counts are accepted', () {
        expect(
          VendorProductDetailParser.parse(
            productDetailRow(assignmentCount: 3, activeAssignmentCount: 3),
          ).inactiveAssignmentCount,
          0,
        );
      });

      test('the shared field rules still apply', () {
        expectRefused(
          () => VendorProductDetailParser.parse(
            productDetailRow(productId: 'not-a-uuid'),
          ),
          'the ten common columns are read by the same strict readers',
        );
        expectRefused(
          () => VendorProductDetailParser.parse(
            productDetailRow(activeAssignmentCount: -1),
          ),
          'a negative active count is refused in both parsers',
        );
      });
    });
  });

  group('assigned Retailers', () {
    test('a fully populated row parses every field', () {
      final VendorProductAssignedRetailer row =
          VendorProductAssignedRetailerParser.parse(assignedRetailerRow());

      expect(row.relationshipId, northwindRelationshipId);
      expect(row.retailerOrganizationId, northwindOrgId);
      expect(row.retailerName, 'Northwind Retail');
      expect(row.retailerStatus, VendorRetailerStatus.active);
      expect(row.relationshipStatus, VendorRetailerStatus.active);
      expect(row.assignmentStatus, VendorProductAssignmentStatus.active);
      expect(row.assignedAt, DateTime.utc(2026, 4, 19, 9, 30));
      expect(row.assignmentUpdatedAt, DateTime.utc(2026, 4, 19, 9, 30));
      expect(row.isCrossLinkable, isTrue);
      expect(row.hasNoRelationship, isFalse);
    });

    test('an empty body is an empty list, not an error', () {
      expect(
        VendorProductAssignedRetailerParser.parseList(const <Object?>[]),
        isEmpty,
      );
    });

    test('the backend order is preserved, never re-sorted or grouped', () {
      // `retailer_name, retailer_organization_id`. An inactive row keeps its
      // place in the sequence — grouping active rows first would be a second
      // definition of the order and would put the rendered rows out of step
      // with `assignment_count`.
      final List<VendorProductAssignedRetailer> rows =
          VendorProductAssignedRetailerParser.parseList(<Map<String, Object?>>[
            assignedRetailerRow(
              retailerName: 'Alpha Stores',
              assignmentStatus: 'INACTIVE',
            ),
            assignedRetailerRow(retailerName: 'Beta Mart'),
          ]);

      expect(
        rows.map((VendorProductAssignedRetailer r) => r.retailerName),
        <String>['Alpha Stores', 'Beta Mart'],
      );
      expect(
        rows.first.assignmentStatus,
        VendorProductAssignmentStatus.inactive,
      );
    });

    group('assignment status', () {
      test('ACTIVE parses to active', () {
        expect(
          VendorProductAssignedRetailerParser.parse(
            assignedRetailerRow(assignmentStatus: 'ACTIVE'),
          ).assignmentStatus,
          VendorProductAssignmentStatus.active,
        );
      });

      test('INACTIVE parses to inactive and stays in the list', () {
        final VendorProductAssignedRetailer row =
            VendorProductAssignedRetailerParser.parse(
              assignedRetailerRow(assignmentStatus: 'INACTIVE'),
            );

        expect(row.assignmentStatus, VendorProductAssignmentStatus.inactive);
        expect(row.assignmentStatus.isActive, isFalse);
        // Still a real, addressable Retailer.
        expect(row.retailerName, 'Northwind Retail');
      });

      test('an unknown token degrades to unknown, never to active', () {
        final VendorProductAssignedRetailer row =
            VendorProductAssignedRetailerParser.parse(
              assignedRetailerRow(assignmentStatus: 'PENDING'),
            );

        expect(row.assignmentStatus, VendorProductAssignmentStatus.unknown);
        expect(row.assignmentStatus.isActive, isFalse);
      });
    });

    group('relationship and Retailer status', () {
      for (final String token in <String>[
        'ACTIVE',
        'SUSPENDED',
        'DEACTIVATED',
      ]) {
        test('a $token relationship parses', () {
          final VendorProductAssignedRetailer row =
              VendorProductAssignedRetailerParser.parse(
                assignedRetailerRow(relationshipStatus: token),
              );

          expect(row.relationshipStatus, VendorRetailerStatus.fromCode(token));
          expect(row.relationshipStatus, isNot(VendorRetailerStatus.unknown));
        });

        test('a $token Retailer parses', () {
          final VendorProductAssignedRetailer row =
              VendorProductAssignedRetailerParser.parse(
                assignedRetailerRow(retailerStatus: token),
              );

          expect(row.retailerStatus, VendorRetailerStatus.fromCode(token));
        });
      }

      test('an active assignment against a suspended Retailer is preserved', () {
        // A real, reachable state: neither count consults the Retailer status,
        // and nothing here infers one status from another.
        final VendorProductAssignedRetailer row =
            VendorProductAssignedRetailerParser.parse(
              assignedRetailerRow(
                assignmentStatus: 'ACTIVE',
                retailerStatus: 'SUSPENDED',
                relationshipStatus: 'SUSPENDED',
              ),
            );

        expect(row.assignmentStatus, VendorProductAssignmentStatus.active);
        expect(row.assignmentStatus.isActive, isTrue);
        expect(row.retailerStatus, VendorRetailerStatus.suspended);
        expect(row.relationshipStatus, VendorRetailerStatus.suspended);
        // And it is still cross-linkable: a suspended relationship is still
        // addressable, and the Retailer screen exists to explain it.
        expect(row.isCrossLinkable, isTrue);
      });

      test('an unknown relationship token is unknown, never active', () {
        final VendorProductAssignedRetailer row =
            VendorProductAssignedRetailerParser.parse(
              assignedRetailerRow(relationshipStatus: 'PAUSED'),
            );

        expect(row.relationshipStatus, VendorRetailerStatus.unknown);
        expect(row.relationshipStatus!.isActive, isFalse);
      });

      test('an unknown Retailer token is unknown, never active', () {
        final VendorProductAssignedRetailer row =
            VendorProductAssignedRetailerParser.parse(
              assignedRetailerRow(retailerStatus: 'ARCHIVED'),
            );

        expect(row.retailerStatus, VendorRetailerStatus.unknown);
        expect(row.retailerStatus.isActive, isFalse);
      });
    });

    group('a missing Vendor–Retailer relationship', () {
      test('a null relationship_id is accepted and preserved', () {
        final VendorProductAssignedRetailer row =
            VendorProductAssignedRetailerParser.parse(
              assignedRetailerRow(
                relationshipId: null,
                relationshipStatus: null,
              ),
            );

        expect(row.relationshipId, isNull);
        expect(row.relationshipStatus, isNull);
      });

      test('the row keeps every other field', () {
        // The Retailer's own id, name and status are unaffected — only the
        // relationship row is gone.
        final VendorProductAssignedRetailer row =
            VendorProductAssignedRetailerParser.parse(
              assignedRetailerRow(
                relationshipId: null,
                relationshipStatus: null,
                assignmentStatus: 'INACTIVE',
                retailerStatus: 'DEACTIVATED',
              ),
            );

        expect(row.retailerOrganizationId, northwindOrgId);
        expect(row.retailerName, 'Northwind Retail');
        expect(row.retailerStatus, VendorRetailerStatus.deactivated);
        expect(row.assignmentStatus, VendorProductAssignmentStatus.inactive);
        expect(row.assignedAt, isNotNull);
        expect(row.assignmentUpdatedAt, isNotNull);
      });

      test('it is not cross-linkable', () {
        final VendorProductAssignedRetailer row =
            VendorProductAssignedRetailerParser.parse(
              assignedRetailerRow(
                relationshipId: null,
                relationshipStatus: null,
              ),
            );

        expect(row.isCrossLinkable, isFalse);
        expect(row.hasNoRelationship, isTrue);
      });

      test('the id is never fabricated from the organization id', () {
        final VendorProductAssignedRetailer row =
            VendorProductAssignedRetailerParser.parse(
              assignedRetailerRow(
                relationshipId: null,
                relationshipStatus: null,
              ),
            );

        expect(row.relationshipId, isNot(row.retailerOrganizationId));
        expect(row.relationshipId, isNull);
      });

      test('a null status is null, never unknown', () {
        // "There is no relationship row" and "the relationship has a status we
        // do not recognise" are different claims, and only one of them is true.
        final VendorProductAssignedRetailer row =
            VendorProductAssignedRetailerParser.parse(
              assignedRetailerRow(
                relationshipId: null,
                relationshipStatus: null,
              ),
            );

        expect(row.relationshipStatus, isNull);
        expect(row.relationshipStatus, isNot(VendorRetailerStatus.unknown));
      });

      test('the row is never dropped from a list', () {
        // It is part of `assignment_count`; removing it would put the list and
        // the count in permanent disagreement.
        final List<VendorProductAssignedRetailer> rows =
            VendorProductAssignedRetailerParser.parseList(
              <Map<String, Object?>>[
                assignedRetailerRow(),
                assignedRetailerRow(
                  relationshipId: null,
                  relationshipStatus: null,
                  retailerOrganizationId: orphanedOrgId,
                  retailerName: 'Old Town Grocers',
                ),
              ],
            );

        expect(rows, hasLength(2));
        expect(rows.last.relationshipId, isNull);
        expect(rows.last.retailerName, 'Old Town Grocers');
      });
    });

    group('rejections', () {
      test('a malformed non-null relationship_id', () {
        // Null is fine; a broken address behind a "View Retailer" action is not.
        expectRefused(
          () => VendorProductAssignedRetailerParser.parse(
            assignedRetailerRow(relationshipId: 'not-a-uuid'),
          ),
          'a present relationship id must be a real uuid',
        );
      });

      test('a missing retailer_organization_id', () {
        expectRefused(
          () => VendorProductAssignedRetailerParser.parse(
            assignedRetailerRow(retailerOrganizationId: null),
          ),
          'the organizations join is on a primary key; it is NOT NULL',
        );
      });

      test('a malformed retailer_organization_id', () {
        expectRefused(
          () => VendorProductAssignedRetailerParser.parse(
            assignedRetailerRow(retailerOrganizationId: 'northwind'),
          ),
          'a malformed uuid is a shape this build cannot read',
        );
      });

      test('a missing retailer_name', () {
        expectRefused(
          () => VendorProductAssignedRetailerParser.parse(
            assignedRetailerRow(retailerName: null),
          ),
          'retailer_name is NOT NULL',
        );
      });

      test('a missing retailer_status', () {
        expectRefused(
          () => VendorProductAssignedRetailerParser.parse(
            assignedRetailerRow(retailerStatus: null),
          ),
          'an absent Retailer status must never be read as ACTIVE',
        );
      });

      test('a relationship_status of the wrong type', () {
        expectRefused(
          () => VendorProductAssignedRetailerParser.parse(
            assignedRetailerRow(relationshipStatus: 7),
          ),
          'a nullable status may be null, never a number',
        );
      });

      test('a blank relationship_status', () {
        expectRefused(
          () => VendorProductAssignedRetailerParser.parse(
            assignedRetailerRow(relationshipStatus: '  '),
          ),
          'the column is NOT NULL wherever it exists; blank is not a state',
        );
      });

      test('a missing assignment_status', () {
        // This read is driven FROM the assignment table, so it can never emit a
        // null here — and an absent one must never be read as ACTIVE.
        expectRefused(
          () => VendorProductAssignedRetailerParser.parse(
            assignedRetailerRow(assignmentStatus: null),
          ),
          'assignment_status is NOT NULL in the table and in the contract',
        );
      });

      test('a malformed assigned_at', () {
        expectRefused(
          () => VendorProductAssignedRetailerParser.parse(
            assignedRetailerRow(assignedAt: 'last Tuesday'),
          ),
          'an unparseable timestamp is not a date this build may render',
        );
      });

      test('a missing assigned_at', () {
        expectRefused(
          () => VendorProductAssignedRetailerParser.parse(
            assignedRetailerRow(assignedAt: null),
          ),
          'assigned_at is NOT NULL',
        );
      });

      test('a malformed assignment_updated_at', () {
        expectRefused(
          () => VendorProductAssignedRetailerParser.parse(
            assignedRetailerRow(assignmentUpdatedAt: 0),
          ),
          'an epoch number is not the timestamptz string the contract sends',
        );
      });

      test('one malformed row fails the whole list', () {
        expectRefused(
          () => VendorProductAssignedRetailerParser.parseList(
            <Map<String, Object?>>[
              assignedRetailerRow(),
              assignedRetailerRow(assignmentStatus: null),
            ],
          ),
          'a shortened list would contradict assignment_count',
        );
      });
    });

    test('timestamps are normalized to UTC', () {
      final VendorProductAssignedRetailer row =
          VendorProductAssignedRetailerParser.parse(
            assignedRetailerRow(
              assignedAt: '2026-04-19T14:30:00+05:00',
              assignmentUpdatedAt: '2026-05-30T17:00:00+05:00',
            ),
          );

      expect(row.assignedAt.isUtc, isTrue);
      expect(row.assignedAt, DateTime.utc(2026, 4, 19, 9, 30));
      expect(row.assignmentUpdatedAt, DateTime.utc(2026, 5, 30, 12, 0));
    });
  });

  group('the contract has no image and no category', () {
    test('a summary models no image, media or storage field', () {
      // No such column exists anywhere in the schema, and no bucket holds
      // product media. A field for one would be a promise about nothing.
      final String rendered = VendorProductSummaryParser.parse(
        productRow(),
      ).toString().toLowerCase();

      for (final String forbidden in <String>[
        'image',
        'photo',
        'thumbnail',
        'media',
        'asset',
        'storage',
        'signedurl',
        'category',
      ]) {
        expect(
          rendered.contains(forbidden),
          isFalse,
          reason: 'the summary models "$forbidden"',
        );
      }
    });

    test('a detail models no image, category, price or reward field', () {
      final String rendered = VendorProductDetailParser.parse(
        productDetailRow(),
      ).toString().toLowerCase();

      for (final String forbidden in <String>[
        'image',
        'category',
        'price',
        'reward',
        'incentive',
        'coin',
        'campaign',
        'inventory',
      ]) {
        expect(
          rendered.contains(forbidden),
          isFalse,
          reason: 'the detail models "$forbidden"',
        );
      }
    });

    test('an extra field in the body is ignored, not adopted', () {
      // A future backend column must not silently become client state.
      final Map<String, Object?> row = productRow()
        ..['image_url'] = 'https://example.invalid/p.png'
        ..['category'] = 'Coffee';

      final VendorProductSummary product = VendorProductSummaryParser.parse(
        row,
      );

      expect(product.toString(), isNot(contains('example.invalid')));
      expect(product.toString(), isNot(contains('Coffee')));
      expect(product.props, hasLength(10));
    });
  });

  group('the id-shape guard', () {
    test('accepts a well-formed uuid', () {
      expect(isProductIdShaped(espressoProductUuid), isTrue);
      expect(isProductIdShaped(unknownProductUuid), isTrue);
    });

    test('refuses everything that is not one', () {
      for (final String value in <String>[
        '',
        'not-a-uuid',
        'ESP-1000',
        '7a1b2c3d-4e5f-4061-8273-94a5b6c7d8e', // one character short
        '7a1b2c3d4e5f4061827394a5b6c7d8e9', // no hyphens
        ' $espressoProductUuid ',
      ]) {
        expect(
          isProductIdShaped(value),
          isFalse,
          reason: '"$value" is not a product id',
        );
      }
    });
  });
}
