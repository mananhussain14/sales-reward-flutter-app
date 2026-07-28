import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/staff/data/models/retailer_staff_invitation_request_body.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_invitation_request.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_invitation_role.dart';

import '../../support/retailer_invite_staff_fakes.dart';

/// The request model and its wire encoding.
///
/// Two claims are defended here, and the second is a security property rather
/// than a convenience:
///
/// 1. **What is sent is canonical.** Trimmed names, a trimmed and lower-cased
///    address, lower-cased and sorted shop ids — the same normalization the
///    deployed contract performs, so the value validated is the value sent.
/// 2. **Exactly five keys leave the device.** The Edge Function *rejects* an
///    unknown top-level key rather than ignoring it, so a sixth field would not
///    degrade gracefully — it would break every send. More to the point, there
///    is no field here for an organization id, an actor id, a membership id, an
///    invitation id, a token or a token hash, and there is nowhere to put one.
void main() {
  RetailerStaffInvitationRequest requireValid(
    RetailerStaffInvitationInput input,
  ) {
    expect(input, isA<RetailerStaffInvitationValid>());
    return (input as RetailerStaffInvitationValid).request;
  }

  Map<RetailerStaffInvitationField, RetailerStaffInvitationProblem>
  requireInvalid(RetailerStaffInvitationInput input) {
    expect(input, isA<RetailerStaffInvitationInvalid>());
    return (input as RetailerStaffInvitationInvalid).problems;
  }

  RetailerStaffInvitationInput validate({
    String firstName = 'Priya',
    String lastName = 'Raman',
    String email = 'priya@example.com',
    RetailerStaffInvitationRole? role = RetailerStaffInvitationRole.salesStaff,
    List<String> shopIds = const <String>[northwindMarinaId],
  }) {
    return RetailerStaffInvitationRequest.validated(
      firstName: firstName,
      lastName: lastName,
      email: email,
      role: role,
      shopIds: shopIds,
    );
  }

  group('a valid Retailer Manager request', () {
    test('carries no shops and serializes shopIds as an empty array', () {
      final RetailerStaffInvitationRequest request = requireValid(
        validate(
          role: RetailerStaffInvitationRole.retailerManager,
          shopIds: const <String>[],
        ),
      );

      expect(request.role, RetailerStaffInvitationRole.retailerManager);
      expect(request.shopIds, isEmpty);

      final Map<String, Object?> body = encodeRetailerStaffInvitationRequest(
        request,
      );
      // Present and empty, never absent: an absent array and an empty one would
      // otherwise be the same request, and "I chose no shops" must not be
      // expressible as "I forgot the field".
      expect(body.containsKey('shopIds'), isTrue);
      expect(body['shopIds'], isEmpty);
      expect(body['roleCode'], 'RETAILER_MANAGER');
    });
  });

  group('a valid Sales Staff request', () {
    test('serializes the selected shop ids', () {
      final RetailerStaffInvitationRequest request = requireValid(
        validate(shopIds: <String>[northwindMarinaId, northwindDowntownId]),
      );

      final Map<String, Object?> body = encodeRetailerStaffInvitationRequest(
        request,
      );
      expect(body['roleCode'], 'SALES_STAFF');
      expect(
        body['shopIds'],
        // Sorted, so two selections of the same shops produce the same request
        // whatever order the boxes were ticked in.
        <String>[northwindMarinaId, northwindDowntownId]..sort(),
      );
    });

    test('lower-cases and sorts the ids', () {
      final RetailerStaffInvitationRequest request = requireValid(
        validate(
          shopIds: <String>[
            northwindWarehouseId.toUpperCase(),
            ' ${northwindMarinaId.toUpperCase()} ',
          ],
        ),
      );

      expect(request.shopIds, <String>[
        northwindMarinaId,
        northwindWarehouseId,
      ]);
    });
  });

  group('the encoded body', () {
    test('has exactly five keys, and they are the contract\'s', () {
      final Map<String, Object?> body = encodeRetailerStaffInvitationRequest(
        requireValid(validate()),
      );

      expect(body.keys, hasLength(5));
      expect(body.keys.toSet(), retailerStaffInvitationRequestFields.toSet());
    });

    test('carries no identity, tenant, invitation or token field', () {
      final Map<String, Object?> body = encodeRetailerStaffInvitationRequest(
        requireValid(validate()),
      );

      for (final String forbidden in <String>[
        'retailerId',
        'retailer_organization_id',
        'retailerOrganizationId',
        'organizationId',
        'organization_id',
        'tenantId',
        'actorId',
        'userId',
        'user_id',
        'authUserId',
        'profileId',
        'membershipId',
        'membership_id',
        'invitationId',
        'invitation_id',
        'token',
        'tokenHash',
        'token_hash',
        'expiresAt',
        'normalizedEmail',
        'state',
        'audit',
        'permission',
        'apiKey',
        'serviceKey',
      ]) {
        expect(body.containsKey(forbidden), isFalse, reason: forbidden);
      }
    });

    test('is exactly what was validated, with nothing re-normalized', () {
      final Map<String, Object?> body = encodeRetailerStaffInvitationRequest(
        requireValid(
          validate(
            firstName: '  Priya  ',
            lastName: '  Raman ',
            email: '  PRIYA@Example.COM ',
          ),
        ),
      );

      // Names are trimmed but never case-folded: a person's name is theirs.
      expect(body['firstName'], 'Priya');
      expect(body['lastName'], 'Raman');
      // The address is trimmed AND lower-cased, matching the database's
      // canonical-email constraint.
      expect(body['email'], 'priya@example.com');
    });
  });

  group('validation refuses what the contract would refuse', () {
    test('a missing role is reported on the role control', () {
      final Map<RetailerStaffInvitationField, RetailerStaffInvitationProblem>
      problems = requireInvalid(validate(role: null));

      expect(
        problems[RetailerStaffInvitationField.role],
        RetailerStaffInvitationProblem.missing,
      );
    });

    test('a duplicate shop id is refused rather than de-duplicated', () {
      // The Edge Function refuses one too. The database would collapse it
      // silently, so a client that sent one would have a defect that never
      // surfaced.
      final Map<RetailerStaffInvitationField, RetailerStaffInvitationProblem>
      problems = requireInvalid(
        validate(
          shopIds: <String>[northwindMarinaId, northwindMarinaId.toUpperCase()],
        ),
      );

      expect(
        problems[RetailerStaffInvitationField.shops],
        RetailerStaffInvitationProblem.duplicateShops,
      );
    });

    test('a Retailer Manager carrying shops is refused locally', () {
      final Map<RetailerStaffInvitationField, RetailerStaffInvitationProblem>
      problems = requireInvalid(
        validate(
          role: RetailerStaffInvitationRole.retailerManager,
          shopIds: const <String>[northwindMarinaId],
        ),
      );

      expect(
        problems[RetailerStaffInvitationField.shops],
        RetailerStaffInvitationProblem.shopsNotAllowed,
      );
    });

    test('Sales Staff without a shop is refused locally', () {
      final Map<RetailerStaffInvitationField, RetailerStaffInvitationProblem>
      problems = requireInvalid(validate(shopIds: const <String>[]));

      expect(
        problems[RetailerStaffInvitationField.shops],
        RetailerStaffInvitationProblem.shopsRequired,
      );
    });

    test('a shop id that is not shaped like a uuid is refused', () {
      // It cannot have come from the assignable-shops read, so this is a defect
      // rather than a person's mistake — and it must never be forwarded.
      final Map<RetailerStaffInvitationField, RetailerStaffInvitationProblem>
      problems = requireInvalid(
        validate(shopIds: const <String>['Northwind Marina']),
      );

      expect(
        problems[RetailerStaffInvitationField.shops],
        RetailerStaffInvitationProblem.malformed,
      );
    });

    test('too many shops are refused', () {
      final List<String> many = List<String>.generate(
        maxInvitationShopSelection + 1,
        (int i) => '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
      );

      expect(
        requireInvalid(
          validate(shopIds: many),
        )[RetailerStaffInvitationField.shops],
        RetailerStaffInvitationProblem.tooManyShops,
      );
    });

    for (final (
          String name,
          String value,
          RetailerStaffInvitationProblem problem,
        )
        in <(String, String, RetailerStaffInvitationProblem)>[
          ('blank', '   ', RetailerStaffInvitationProblem.missing),
          ('empty', '', RetailerStaffInvitationProblem.missing),
        ]) {
      test('a $name first name is refused', () {
        expect(
          requireInvalid(
            validate(firstName: value),
          )[RetailerStaffInvitationField.firstName],
          problem,
        );
      });

      test('a $name last name is refused', () {
        expect(
          requireInvalid(
            validate(lastName: value),
          )[RetailerStaffInvitationField.lastName],
          problem,
        );
      });

      test('a $name email is refused', () {
        expect(
          requireInvalid(
            validate(email: value),
          )[RetailerStaffInvitationField.email],
          problem,
        );
      });
    }

    test('an over-long name is refused', () {
      expect(
        requireInvalid(
          validate(firstName: 'a' * (maxInvitationNameLength + 1)),
        )[RetailerStaffInvitationField.firstName],
        RetailerStaffInvitationProblem.tooLong,
      );
    });

    test('an over-long email is refused', () {
      final String local = 'a' * (maxInvitationEmailLength - 11);
      expect(
        requireInvalid(
          validate(email: '$local@example.com'),
        )[RetailerStaffInvitationField.email],
        RetailerStaffInvitationProblem.tooLong,
      );
    });

    for (final String malformed in <String>[
      'priya',
      'priya@',
      '@example.com',
      'priya@example',
      'priya example@test.com',
    ]) {
      test('"$malformed" is not a valid address', () {
        expect(
          requireInvalid(
            validate(email: malformed),
          )[RetailerStaffInvitationField.email],
          RetailerStaffInvitationProblem.malformed,
        );
      });
    }

    test('every offending field is reported at once', () {
      // So a person fixes one form rather than one field per attempt.
      final Map<RetailerStaffInvitationField, RetailerStaffInvitationProblem>
      problems = requireInvalid(
        validate(
          firstName: '',
          lastName: '',
          email: 'nope',
          role: null,
          shopIds: const <String>[],
        ),
      );

      expect(problems.keys.toSet(), <RetailerStaffInvitationField>{
        RetailerStaffInvitationField.firstName,
        RetailerStaffInvitationField.lastName,
        RetailerStaffInvitationField.email,
        RetailerStaffInvitationField.role,
      });
    });
  });

  group('the role vocabulary', () {
    test('is exactly the two codes the contract accepts', () {
      expect(
        RetailerStaffInvitationRole.values
            .map((RetailerStaffInvitationRole role) => role.code)
            .toList(),
        <String>['RETAILER_MANAGER', 'SALES_STAFF'],
      );
    });

    test('only Sales Staff carries shops', () {
      expect(RetailerStaffInvitationRole.salesStaff.carriesShops, isTrue);
      expect(RetailerStaffInvitationRole.retailerManager.carriesShops, isFalse);
    });
  });
}
