import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/parsing/rpc_row.dart';
import 'package:sale_reward/features/auth/data/models/lifecycle_access_parser.dart';
import 'package:sale_reward/features/auth/domain/entities/lifecycle_access_state.dart';

/// The documented body shape: a one-element list of row maps.
List<Object?> body(Object? accessState) => <Object?>[
  <String, Object?>{'access_state': accessState},
];

void main() {
  group('the six supported states', () {
    test('ACTIVE', () {
      expect(
        LifecycleAccessParser.parse(body('ACTIVE')),
        LifecycleAccessState.active,
      );
    });

    test('ORGANIZATION_INACTIVE', () {
      expect(
        LifecycleAccessParser.parse(body('ORGANIZATION_INACTIVE')),
        LifecycleAccessState.organizationInactive,
      );
    });

    test('MEMBERSHIP_INACTIVE', () {
      expect(
        LifecycleAccessParser.parse(body('MEMBERSHIP_INACTIVE')),
        LifecycleAccessState.membershipInactive,
      );
    });

    test('PROFILE_INACTIVE', () {
      expect(
        LifecycleAccessParser.parse(body('PROFILE_INACTIVE')),
        LifecycleAccessState.profileInactive,
      );
    });

    test('NO_SUPPORTED_ACCESS', () {
      expect(
        LifecycleAccessParser.parse(body('NO_SUPPORTED_ACCESS')),
        LifecycleAccessState.noSupportedAccess,
      );
    });

    test('AMBIGUOUS', () {
      expect(
        LifecycleAccessParser.parse(body('AMBIGUOUS')),
        LifecycleAccessState.ambiguous,
      );
    });

    test('every enum member is reachable from some wire code', () {
      // Non-vacuity: a member added without a code would otherwise be
      // unreachable and silently untested.
      final Set<LifecycleAccessState> parsed = <String>[
        'ACTIVE',
        'ORGANIZATION_INACTIVE',
        'MEMBERSHIP_INACTIVE',
        'PROFILE_INACTIVE',
        'NO_SUPPORTED_ACCESS',
        'AMBIGUOUS',
      ].map((String code) => LifecycleAccessParser.parse(body(code))).toSet();

      expect(parsed, LifecycleAccessState.values.toSet());
    });
  });

  group('the root must be a list of exactly one row', () {
    test('a null root is refused', () {
      expect(
        () => LifecycleAccessParser.parse(null),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a string root is refused', () {
      expect(
        () => LifecycleAccessParser.parse('ACTIVE'),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a numeric root is refused', () {
      expect(
        () => LifecycleAccessParser.parse(1),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a bare map root is refused, unlike the Web parser', () {
      // The deployed TypeScript client accepts `{access_state: 'ACTIVE'}` by
      // falling back to the object itself. Flutter does not — see the parser's
      // header for why the divergence is deliberate.
      expect(
        () => LifecycleAccessParser.parse(<String, Object?>{
          'access_state': 'ACTIVE',
        }),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('an empty list is refused rather than defaulted', () {
      expect(
        () => LifecycleAccessParser.parse(<Object?>[]),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('two rows are refused, even when both agree', () {
      expect(
        () => LifecycleAccessParser.parse(<Object?>[
          <String, Object?>{'access_state': 'ACTIVE'},
          <String, Object?>{'access_state': 'ACTIVE'},
        ]),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a non-map row is refused', () {
      expect(
        () => LifecycleAccessParser.parse(<Object?>['ACTIVE']),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a null row is refused', () {
      expect(
        () => LifecycleAccessParser.parse(<Object?>[null]),
        throwsA(isA<RpcFormatException>()),
      );
    });
  });

  group('the access_state field', () {
    test('a missing key is refused', () {
      expect(
        () => LifecycleAccessParser.parse(<Object?>[<String, Object?>{}]),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a null value is refused', () {
      expect(
        () => LifecycleAccessParser.parse(body(null)),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a numeric value is refused', () {
      expect(
        () => LifecycleAccessParser.parse(body(1)),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a boolean value is refused', () {
      expect(
        () => LifecycleAccessParser.parse(body(true)),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a list value is refused', () {
      expect(
        () => LifecycleAccessParser.parse(body(<Object?>['ACTIVE'])),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a map value is refused', () {
      expect(
        () => LifecycleAccessParser.parse(
          body(<String, Object?>{'value': 'ACTIVE'}),
        ),
        throwsA(isA<RpcFormatException>()),
      );
    });
  });

  group('nothing is normalized', () {
    test('an empty string is refused', () {
      expect(
        () => LifecycleAccessParser.parse(body('')),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a whitespace-only value is refused', () {
      expect(
        () => LifecycleAccessParser.parse(body('   ')),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a lower-case value is refused', () {
      expect(
        () => LifecycleAccessParser.parse(body('active')),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a mixed-case value is refused', () {
      expect(
        () => LifecycleAccessParser.parse(body('Organization_Inactive')),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a leading space is refused', () {
      expect(
        () => LifecycleAccessParser.parse(body(' ACTIVE')),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a trailing space is refused', () {
      expect(
        () => LifecycleAccessParser.parse(body('ACTIVE ')),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('a newline-suffixed value is refused', () {
      expect(
        () => LifecycleAccessParser.parse(body('ACTIVE\n')),
        throwsA(isA<RpcFormatException>()),
      );
    });

    test('an unknown state from a future migration is refused', () {
      expect(
        () => LifecycleAccessParser.parse(body('SOMETHING_NEW')),
        throwsA(isA<RpcFormatException>()),
      );
    });
  });

  group('forward compatibility', () {
    test('extra keys on the row are ignored', () {
      final List<Object?> raw = <Object?>[
        <String, Object?>{
          'access_state': 'MEMBERSHIP_INACTIVE',
          'context_version': 2,
          'something_added_later': null,
        },
      ];

      expect(
        LifecycleAccessParser.parse(raw),
        LifecycleAccessState.membershipInactive,
      );
    });

    test(
      'non-string row keys are coerced by RpcRow without losing the field',
      () {
        // PostgREST always sends string keys; this proves the shared helper's
        // key-stringifying does not drop the column on a dynamic map.
        final List<Object?> raw = <Object?>[
          <Object?, Object?>{'access_state': 'AMBIGUOUS'},
        ];

        expect(
          LifecycleAccessParser.parse(raw),
          LifecycleAccessState.ambiguous,
        );
      },
    );
  });
}
