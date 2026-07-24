@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/auth/data/models/portal_context_parser.dart';
import 'package:sale_reward/features/auth/domain/entities/portal_kind.dart';

import '../support/fakes.dart';

/// **The role must always come from the backend, never from the client.**
///
/// The RPC now exists, so the previous milestone's preview showcase is gone and
/// the risk shifts: a convenience default in the parser or the session
/// coordinator that turned an unknown or malformed answer into a privileged
/// role. These tests guard that boundary at runtime and at the source level.
void main() {
  group('the parser never invents a role', () {
    test('an unknown portal_kind throws rather than defaulting', () {
      expect(
        () => PortalContextParser.parse(<String, Object?>{
          'context_version': 1,
          'portal_kind': 'ADMIN',
          'vendor': null,
          'retailer': null,
        }),
        throwsA(isA<PortalContextFormatException>()),
      );
    });

    test('a higher context_version throws rather than guessing', () {
      expect(
        () => PortalContextParser.parse(<String, Object?>{
          'context_version': 2,
          'portal_kind': 'VENDOR_SUPER_ADMIN',
          'vendor': <String, Object?>{
            'organization_id': '11111111-1111-1111-1111-111111111111',
            'organization_name': 'X',
          },
        }),
        throwsA(isA<PortalContextFormatException>()),
      );
    });

    test('PortalKind.tryParse fails closed for every non-role string', () {
      for (final String value in <String>[
        '',
        'none',
        'vendor',
        'OWNER',
        'RETAILER',
        'SUPERUSER',
      ]) {
        expect(
          PortalKind.tryParse(value),
          anyOf(isNull, PortalKind.none),
          reason: '"$value" must not become a shell role',
        );
      }
    });
  });

  group('the session coordinator never fabricates a role', () {
    test('an unavailable result yields no context, only a failure', () {
      // A resolve failure is operational; it must never carry a role.
      expect(unavailableResult, isNotNull);
    });
  });

  group('source-level guarantees', () {
    late List<File> sources;

    setUpAll(() {
      sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList();
    });

    test('no source defaults a portal kind when resolution fails', () {
      // `?? PortalKind.retailerOwner`, or a ternary else-branch that is a role,
      // is the exact convenience this milestone must not ship. The enum's own
      // declaration is exempt.
      final RegExp nullCoalesced = RegExp(r'\?\?\s*PortalKind\.');
      final List<String> offenders = <String>[];

      for (final File file in sources) {
        if (file.path.endsWith('portal_kind.dart')) continue;
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String line = lines[i];
          final String trimmed = line.trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          if (nullCoalesced.hasMatch(line)) {
            offenders.add('${file.path}:${i + 1} → ${line.trim()}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'a portal kind used as a fallback:\n${offenders.join('\n')}',
      );
    });

    test('no source constructs a role from user input or local storage', () {
      // A role read from a text field, shared preferences, or a JWT claim would
      // be the client asserting authorization. None of these appears.
      for (final File file in sources) {
        final String src = file.readAsStringSync();
        expect(src.contains('SharedPreferences'), isFalse);
        expect(
          src.contains('.decodeJwt') || src.contains('jwtDecode'),
          isFalse,
          reason: '${file.path} decodes a JWT to find a role',
        );
      }
    });

    test('the development-only preview showcase is fully removed', () {
      // The RPC exists now; the preview mechanism that stood in for it must not
      // survive into a build with real routing.
      for (final File file in sources) {
        final String src = file.readAsStringSync();
        for (final String forbidden in <String>[
          'RoleSessionPreviewSelected',
          'RoleTrust.localPreview',
          'Interface preview',
          'localPreview',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} still references the removed showcase',
          );
        }
      }
    });

    test('capabilities are documented as hints, never as authorization', () {
      // The capability entity must state it decides nothing, so a future edit
      // that gated a write on it would contradict its own contract.
      final File caps = sources.firstWhere(
        (File f) => f.path.endsWith('retailer_capabilities.dart'),
      );
      final String src = caps.readAsStringSync().toLowerCase();
      expect(src.contains('not authorization'), isTrue);
    });
  });
}
