import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/parsing/rpc_row.dart';
import 'package:sale_reward/features/staff/data/models/retailer_assignable_shop_parser.dart';
import 'package:sale_reward/features/staff/data/models/retailer_staff_invitation_response_parser.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_assignable_shop.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_invitation_outcome.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_staff_invitation_repository.dart';

import '../../support/retailer_invite_staff_fakes.dart';

/// The two parsers on the invitation path: the assignable-shops rows, and the
/// Edge Function's reply.
void main() {
  group('list_retailer_staff_assignable_shops()', () {
    Map<String, Object?> row({
      Object? shopId = northwindMarinaId,
      Object? shopName = 'Northwind Marina',
      Object? shopCode = 'NW-01',
      Object? city = 'Dubai',
      Map<String, Object?> extra = const <String, Object?>{},
    }) {
      return <String, Object?>{
        'shop_id': shopId,
        'shop_name': shopName,
        'shop_code': shopCode,
        'city': city,
        ...extra,
      };
    }

    test('parses the deployed four columns', () {
      final List<RetailerAssignableShop> shops =
          RetailerAssignableShopParser.parse(<Object?>[row()]);

      expect(shops, hasLength(1));
      expect(shops.single.id, northwindMarinaId);
      expect(shops.single.name, 'Northwind Marina');
      expect(shops.single.code, 'NW-01');
      expect(shops.single.city, 'Dubai');
    });

    test('zero rows is a real answer, not a refusal', () {
      // A refused caller raises `42501`, which the repository turns into
      // `denied`. An empty array genuinely means "no ACTIVE shops".
      expect(RetailerAssignableShopParser.parse(<Object?>[]), isEmpty);
    });

    test('a null shop_code or city means "not recorded"', () {
      final RetailerAssignableShop shop = RetailerAssignableShopParser.parseRow(
        row(shopCode: null, city: null),
      );

      expect(shop.code, isNull);
      expect(shop.city, isNull);
      expect(shop.name, 'Northwind Marina');
    });

    test('an unexpected extra key is ignored', () {
      // The contract is additive; a new column must not break an old client.
      final RetailerAssignableShop shop = RetailerAssignableShopParser.parseRow(
        row(
          extra: const <String, Object?>{
            'shop_status': 'ACTIVE',
            'country_code': 'AE',
            'retailer_organization_id': 'ignored',
          },
        ),
      );

      expect(shop.id, northwindMarinaId);
    });

    test(
      'an id is lower-cased so it matches what the contract canonicalizes',
      () {
        final RetailerAssignableShop shop =
            RetailerAssignableShopParser.parseRow(
              row(shopId: northwindMarinaId.toUpperCase()),
            );

        expect(shop.id, northwindMarinaId);
      },
    );

    test('a malformed shop_id fails the read', () {
      // It would be sent back as an element of `shopIds`, so forwarding it would
      // turn a readable local refusal into an opaque INVALID_REQUEST.
      expect(
        () => RetailerAssignableShopParser.parseRow(row(shopId: 'not-a-uuid')),
        throwsA(isA<RpcFormatException>()),
      );
    });

    for (final (String name, Map<String, Object?> bad)
        in <(String, Map<String, Object?>)>[
          ('a missing shop_id', <String, Object?>{'shop_name': 'X'}),
          (
            'a null shop_id',
            <String, Object?>{'shop_id': null, 'shop_name': 'X'},
          ),
          (
            'a non-string shop_id',
            <String, Object?>{'shop_id': 7, 'shop_name': 'X'},
          ),
        ]) {
      test('$name fails the read', () {
        expect(
          () => RetailerAssignableShopParser.parseRow(bad),
          throwsA(isA<RpcFormatException>()),
        );
      });
    }

    for (final (String name, Object? value) in <(String, Object?)>[
      ('missing', null),
      ('blank', '   '),
      ('non-string', 42),
    ]) {
      test('a $name shop_name fails the read', () {
        expect(
          () => RetailerAssignableShopParser.parseRow(row(shopName: value)),
          throwsA(isA<RpcFormatException>()),
        );
      });
    }

    test('a non-string shop_code fails the read', () {
      expect(
        () => RetailerAssignableShopParser.parseRow(row(shopCode: 12)),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a duplicate id across rows fails the whole read', () {
      // The id is the primary key, so two rows sharing one is evidence the
      // response is not this contract — and a picker built from it could submit
      // the same shop twice, which the function refuses outright.
      expect(
        () => RetailerAssignableShopParser.parse(<Object?>[
          row(),
          row(shopName: 'Another name', shopCode: 'NW-99'),
        ]),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('two distinct shops that look alike are both kept', () {
      final List<RetailerAssignableShop> shops =
          RetailerAssignableShopParser.parse(<Object?>[
            row(shopId: northwindMarinaId, shopCode: null),
            row(shopId: northwindDowntownId, shopCode: null),
          ]);

      expect(shops, hasLength(2));
    });

    test('a body that is not a list fails the read', () {
      expect(
        () => RetailerAssignableShopParser.parse(<String, Object?>{}),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a row that is not an object fails the read', () {
      expect(
        () => RetailerAssignableShopParser.parse(<Object?>['nope']),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('the backend order is preserved, never re-sorted', () {
      final List<RetailerAssignableShop> shops =
          RetailerAssignableShopParser.parse(<Object?>[
            row(shopId: northwindWarehouseId, shopName: 'Zulu'),
            row(shopId: northwindMarinaId, shopName: 'Alpha'),
          ]);

      expect(shops.map((RetailerAssignableShop s) => s.name).toList(), <String>[
        'Zulu',
        'Alpha',
      ]);
    });
  });

  group('the Edge Function reply', () {
    Map<String, Object?> reply({
      Object? version = 1,
      Object? outcome = 'SENT',
      Object? code = 'SENT',
      Map<String, Object?> extra = const <String, Object?>{},
    }) {
      return <String, Object?>{
        'version': version,
        'outcome': outcome,
        'code': code,
        ...extra,
      };
    }

    RetailerStaffInvitationSendResult map({int status = 200, Object? body}) =>
        mapRetailerStaffInvitationReply(status: status, body: body);

    RetailerStaffInvitationAnswered requireAnswered(
      RetailerStaffInvitationSendResult result,
    ) {
      expect(result, isA<RetailerStaffInvitationAnswered>());
      return result as RetailerStaffInvitationAnswered;
    }

    RetailerStaffInvitationTransportProblem requireUnanswered(
      RetailerStaffInvitationSendResult result,
    ) {
      expect(result, isA<RetailerStaffInvitationUnanswered>());
      return (result as RetailerStaffInvitationUnanswered).problem;
    }

    for (final (
          String token,
          int status,
          RetailerStaffInvitationOutcome outcome,
          RetailerStaffInvitationCode code,
        )
        in <
          (
            String,
            int,
            RetailerStaffInvitationOutcome,
            RetailerStaffInvitationCode,
          )
        >[
          (
            'SENT',
            200,
            RetailerStaffInvitationOutcome.sent,
            RetailerStaffInvitationCode.sent,
          ),
          (
            'RESENT',
            200,
            RetailerStaffInvitationOutcome.resent,
            RetailerStaffInvitationCode.resent,
          ),
          (
            'DELIVERY_ACCEPTED_STATUS_UNCONFIRMED',
            202,
            RetailerStaffInvitationOutcome.deliveryAcceptedStatusUnconfirmed,
            RetailerStaffInvitationCode.deliveryAcceptedStatusUnconfirmed,
          ),
          (
            'DELIVERY_FAILED',
            502,
            RetailerStaffInvitationOutcome.deliveryFailed,
            RetailerStaffInvitationCode.deliveryFailed,
          ),
        ]) {
      test('$token is read at its deployed HTTP status', () {
        final RetailerStaffInvitationAnswered answered = requireAnswered(
          map(
            status: status,
            body: reply(outcome: token, code: token),
          ),
        );

        expect(answered.outcome, outcome);
        expect(answered.code, code);
        // The four codes that mean the message reached the provider.
        expect(answered.outcome.reachedProvider, isTrue);
      });
    }

    for (final (String code, int status) in <(String, int)>[
      ('METHOD_NOT_ALLOWED', 405),
      ('INVALID_REQUEST', 400),
      ('INVALID_ROLE_SHOP_COMBINATION', 422),
      ('AUTH_REQUIRED', 401),
      ('ACCESS_DENIED', 403),
      ('INVITATION_CONFLICT', 409),
      ('RETAILER_INACTIVE', 422),
      ('FEATURE_DISABLED', 503),
      ('NOT_CONFIGURED', 503),
      ('INTERNAL_ERROR', 500),
    ]) {
      test('NOT_SENT / $code is read at its deployed HTTP status', () {
        final RetailerStaffInvitationAnswered answered = requireAnswered(
          map(
            status: status,
            body: reply(outcome: 'NOT_SENT', code: code),
          ),
        );

        expect(answered.outcome, RetailerStaffInvitationOutcome.notSent);
        expect(answered.code.token, code);
        expect(answered.outcome.reachedProvider, isFalse);
      });
    }

    test('there is no RATE_LIMITED code, because no rate limiter exists', () {
      expect(
        RetailerStaffInvitationCode.values.map(
          (RetailerStaffInvitationCode c) => c.token,
        ),
        isNot(contains('RATE_LIMITED')),
      );
    });

    test('an unknown code degrades to the recognised outcome', () {
      // Adding a code to an existing outcome is explicitly NOT breaking, so a
      // client must fall back to the outcome's generic case.
      final RetailerStaffInvitationAnswered answered = requireAnswered(
        map(
          status: 400,
          body: reply(outcome: 'NOT_SENT', code: 'SOMETHING_NEW'),
        ),
      );

      expect(answered.outcome, RetailerStaffInvitationOutcome.notSent);
      expect(answered.code, RetailerStaffInvitationCode.unrecognized);
      // The unrecognised member carries no token, so no backend string travels
      // past the parser.
      expect(answered.code.token, isEmpty);
    });

    test('a missing code degrades the same way', () {
      final RetailerStaffInvitationAnswered answered = requireAnswered(
        map(
          status: 400,
          body: <String, Object?>{'version': 1, 'outcome': 'NOT_SENT'},
        ),
      );

      expect(answered.outcome, RetailerStaffInvitationOutcome.notSent);
      expect(answered.code, RetailerStaffInvitationCode.unrecognized);
    });

    test('a code belonging to another outcome is treated as unknown', () {
      // The two disagreeing is drift. The outcome is the field the contract
      // calls safety-critical, so it wins.
      final RetailerStaffInvitationAnswered answered = requireAnswered(
        map(
          body: reply(outcome: 'NOT_SENT', code: 'SENT'),
        ),
      );

      expect(answered.outcome, RetailerStaffInvitationOutcome.notSent);
      expect(answered.code, RetailerStaffInvitationCode.unrecognized);
    });

    test('unexpected additional fields are ignored safely', () {
      final RetailerStaffInvitationAnswered answered = requireAnswered(
        map(
          body: reply(
            extra: const <String, Object?>{
              'invitation_id': 'must-not-be-read',
              'token': 'must-not-be-read',
              'message': 'must-not-be-read',
            },
          ),
        ),
      );

      expect(answered.outcome, RetailerStaffInvitationOutcome.sent);
      // The result type has no field any of those could occupy.
      expect(answered.code, RetailerStaffInvitationCode.sent);
    });

    for (final (String name, Object? version) in <(String, Object?)>[
      ('2', 2),
      ('0', 0),
      ('a string "1"', '1'),
      ('a boolean', true),
      ('absent', null),
    ]) {
      test('a version of $name is refused', () {
        expect(
          requireUnanswered(map(body: reply(version: version))),
          RetailerStaffInvitationTransportProblem.malformed,
        );
      });
    }

    test('a numeric 1 in either representation is accepted', () {
      expect(
        requireAnswered(map(body: reply(version: 1.0))).outcome,
        RetailerStaffInvitationOutcome.sent,
      );
    });

    for (final (String name, Object? outcome) in <(String, Object?)>[
      ('missing', null),
      ('unknown', 'PROBABLY_SENT'),
      ('non-string', 3),
    ]) {
      test('a $name outcome fails the whole response', () {
        // Unlike a code, an unreadable outcome leaves the one safety-critical
        // question unanswered, so there is no safe degradation.
        expect(
          requireUnanswered(map(body: reply(outcome: outcome))),
          RetailerStaffInvitationTransportProblem.malformed,
        );
      });
    }

    for (final (String name, Object? body) in <(String, Object?)>[
      ('a null body', null),
      ('a string body', 'Bad Gateway'),
      ('a list body', <Object?>[]),
      ('an empty string', ''),
    ]) {
      test('$name is refused', () {
        expect(
          requireUnanswered(map(status: 502, body: body)),
          RetailerStaffInvitationTransportProblem.malformed,
        );
      });
    }

    test('a bare 401 with no contract body means the session ended', () {
      // The API gateway refuses before the function runs, in its own
      // vocabulary. "Sign in again" is actionable; "the service said something
      // odd" is not.
      expect(
        requireUnanswered(
          map(
            status: 401,
            body: const <String, Object?>{'message': 'Invalid JWT'},
          ),
        ),
        RetailerStaffInvitationTransportProblem.signedOut,
      );
    });

    test('a 401 that IS a contract response is read as AUTH_REQUIRED', () {
      final RetailerStaffInvitationAnswered answered = requireAnswered(
        map(
          status: 401,
          body: reply(outcome: 'NOT_SENT', code: 'AUTH_REQUIRED'),
        ),
      );

      expect(answered.code, RetailerStaffInvitationCode.authRequired);
    });
  });
}
