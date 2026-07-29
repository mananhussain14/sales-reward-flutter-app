@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-safety assertions for the self-only lifecycle diagnostic.
///
/// These read the source rather than exercise it, which makes them the cheapest
/// guard against the boundary eroding under deadline pressure — the kind of
/// regression a behavioural test cannot see, because the code that erodes it
/// usually still works.
///
/// The property they defend, stated once: **the diagnostic can express no
/// question about anybody but the caller, and can grant nothing.** The deployed
/// function takes zero arguments, derives its subject solely from `auth.uid()`,
/// and returns one word from a closed vocabulary. Every assertion below is some
/// form of "and nothing here tries to do more".
void main() {
  late List<File> sources;

  /// The one file permitted to name the RPC.
  late File dataSourceFile;
  late String dataSource;

  /// The one file permitted to hold the wire vocabulary.
  late File parserFile;

  /// The one file permitted to hold the approved copy.
  late File copyFile;

  late File cubitFile;
  late File pageFile;

  /// Every `lib/` source except the three approved diagnostic files.
  late List<File> nonDiagnosticSources;

  /// The file's executable lines only.
  ///
  /// Every check below is about what the code *does*. The doc comments in this
  /// feature deliberately discuss the things the code must not do — "no direct
  /// table read", "no service-role client", "no polling" — and a scan that could
  /// not tell the two apart would either fail on its own documentation or force
  /// the documentation to stop naming what it protects against.
  String code(File file) => file
      .readAsLinesSync()
      .where((String line) {
        final String trimmed = line.trimLeft();
        return !trimmed.startsWith('//') && !trimmed.startsWith('*');
      })
      .join('\n');

  File findSource(String suffix) =>
      sources.firstWhere((File f) => f.path.endsWith(suffix));

  setUpAll(() {
    sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();

    dataSourceFile = findSource('lifecycle_access_rpc_data_source.dart');
    dataSource = code(dataSourceFile);
    parserFile = findSource('lifecycle_access_parser.dart');
    copyFile = findSource('lifecycle_access_copy.dart');
    cubitFile = findSource('lifecycle_access_cubit.dart');
    pageFile = findSource('access_denied_page.dart');

    nonDiagnosticSources = sources
        .where(
          (File f) =>
              f.path != dataSourceFile.path &&
              f.path != parserFile.path &&
              f.path != copyFile.path,
        )
        .toList();
  });

  test('the scan is non-vacuous', () {
    expect(sources.length, greaterThan(100));
    expect(nonDiagnosticSources.length, greaterThan(100));
    expect(nonDiagnosticSources.length, sources.length - 3);
    expect(code(dataSourceFile), isNotEmpty);
    expect(code(cubitFile), isNotEmpty);
    expect(code(pageFile), isNotEmpty);
  });

  group('the RPC is named once, exactly', () {
    test('only the data source names it, anywhere in lib/', () {
      // Scanned over the WHOLE of lib/, not just the auth feature: a call site
      // added in another feature would escape a feature-scoped guard.
      _expectAbsent(nonDiagnosticSources, <String>[
        'get_my_lifecycle_access_state',
      ], allowInComments: true);
    });

    test('the data source names it exactly once, in one constant', () {
      final int occurrences = 'get_my_lifecycle_access_state'
          .allMatches(dataSource)
          .length;
      expect(occurrences, 1);
      expect(
        dataSource.contains(
          "const String getMyLifecycleAccessStateRpc = "
          "'get_my_lifecycle_access_state'",
        ),
        isTrue,
      );
    });

    test('the call passes zero arguments', () {
      // The exact invocation, and nothing else.
      expect(
        dataSource.contains(
          'client.rpc<Object?>(getMyLifecycleAccessStateRpc)',
        ),
        isTrue,
      );
      // No params object in any form.
      expect(dataSource.contains('params'), isFalse);
      expect(dataSource.contains('{}'), isFalse);
    });

    test('the invoker typedef takes no parameters', () {
      expect(
        dataSource.contains(
          'typedef LifecycleAccessInvoker = Future<Object?> Function();',
        ),
        isTrue,
      );
    });

    test('no identity argument is expressible anywhere on the path', () {
      for (final File file in <File>[dataSourceFile, cubitFile]) {
        final String src = code(file);
        for (final String needle in <String>[
          'userId',
          'user_id',
          'organizationId',
          'organization_id',
          'membershipId',
          'membership_id',
          'profileId',
          'profile_id',
          'roleCode',
          'role_code',
          'portalKind',
          'portal_kind',
        ]) {
          expect(
            src.contains(needle),
            isFalse,
            reason: '${file.path} must not name $needle',
          );
        }
      }
    });
  });

  group('no other backend surface is touched', () {
    test('there is no direct table read or write on the diagnostic path', () {
      for (final File file in <File>[
        dataSourceFile,
        parserFile,
        cubitFile,
        findSource('supabase_lifecycle_access_repository.dart'),
      ]) {
        final String src = code(file);
        expect(src.contains('.from('), isFalse, reason: file.path);
        expect(src.contains('.insert('), isFalse, reason: file.path);
        expect(src.contains('.update('), isFalse, reason: file.path);
        expect(src.contains('.upsert('), isFalse, reason: file.path);
        expect(src.contains('.delete('), isFalse, reason: file.path);
      }
    });

    test('no service-role or admin client is used', () {
      for (final File file in sources) {
        final String src = code(file);
        expect(src.contains('serviceRole'), isFalse, reason: file.path);
        expect(src.contains('service_role'), isFalse, reason: file.path);
        expect(src.contains('auth.admin'), isFalse, reason: file.path);
        expect(src.contains('GoTrueAdminApi'), isFalse, reason: file.path);
      }
    });

    test('the shared error mapper and SQLSTATE table are not imported', () {
      for (final File file in <File>[
        dataSourceFile,
        parserFile,
        cubitFile,
        findSource('supabase_lifecycle_access_repository.dart'),
      ]) {
        final String src = code(file);
        expect(src.contains('mapSupabaseError'), isFalse, reason: file.path);
        expect(src.contains('failure_mapper'), isFalse, reason: file.path);
        expect(src.contains('sql_state'), isFalse, reason: file.path);
        expect(src.contains('SqlState'), isFalse, reason: file.path);
        expect(src.contains('42501'), isFalse, reason: file.path);
      }
    });

    test('no backend error text is ever read', () {
      for (final File file in <File>[
        cubitFile,
        findSource('supabase_lifecycle_access_repository.dart'),
      ]) {
        final String src = code(file);
        expect(src.contains('.message'), isFalse, reason: file.path);
        expect(src.contains('.details'), isFalse, reason: file.path);
        expect(src.contains('.hint'), isFalse, reason: file.path);
        expect(src.contains('.code'), isFalse, reason: file.path);
      }
    });
  });

  group('nothing polls, retries or signs anybody out', () {
    test('no timer, periodic stream or delayed retry on the path', () {
      for (final File file in <File>[
        dataSourceFile,
        parserFile,
        cubitFile,
        pageFile,
        findSource('supabase_lifecycle_access_repository.dart'),
        findSource('sr_lifecycle_notice_view.dart'),
      ]) {
        final String src = code(file);
        expect(src.contains('Timer'), isFalse, reason: file.path);
        expect(src.contains('Stream.periodic'), isFalse, reason: file.path);
        expect(src.contains('Future.delayed'), isFalse, reason: file.path);
        expect(src.contains('retry'), isFalse, reason: file.path);
      }
    });

    test('the diagnostic never signs the user out', () {
      for (final File file in <File>[
        dataSourceFile,
        parserFile,
        cubitFile,
        findSource('supabase_lifecycle_access_repository.dart'),
      ]) {
        expect(code(file).contains('signOut'), isFalse, reason: file.path);
      }
    });

    test('the cubit holds no router, navigator or context', () {
      final String src = code(cubitFile);
      for (final String needle in <String>[
        'GoRouter',
        'Navigator',
        'BuildContext',
        'context.go',
        'context.push',
        'AppRoutes',
      ]) {
        expect(src.contains(needle), isFalse, reason: 'cubit must not $needle');
      }
    });

    test('the cubit subscribes to nothing', () {
      final String src = code(cubitFile);
      expect(src.contains('.listen('), isFalse);
      expect(src.contains('StreamSubscription'), isFalse);
      expect(src.contains('.changes'), isFalse);
      expect(src.contains('SessionBloc'), isFalse);
    });
  });

  group('the wire vocabulary cannot reach a screen', () {
    test('only the parser names the diagnostic-specific codes', () {
      final List<File> outsideParser = sources
          .where((File f) => f.path != parserFile.path)
          .toList();
      expect(outsideParser.length, sources.length - 1);

      // `'ACTIVE'` is deliberately NOT in this list. It is a shared status
      // literal across products, roles, shops, users and memberships, so
      // asserting its exclusivity would fail on a dozen unrelated features
      // without protecting anything: on its own it discloses no lifecycle
      // diagnosis. The five codes below exist nowhere else in the product and
      // are the ones whose leakage would name a cause.
      _expectAbsent(outsideParser, <String>[
        'ORGANIZATION_INACTIVE',
        'MEMBERSHIP_INACTIVE',
        'PROFILE_INACTIVE',
        'NO_SUPPORTED_ACCESS',
        'AMBIGUOUS',
      ], allowInComments: true);
    });

    test('the domain enum exposes no wire code', () {
      final String src = code(findSource('lifecycle_access_state.dart'));
      expect(src.contains('ORGANIZATION_INACTIVE'), isFalse);
      expect(src.contains('code'), isFalse);
    });

    test('no widget interpolates a diagnostic state into text', () {
      for (final File file in <File>[
        pageFile,
        findSource('sr_lifecycle_notice_view.dart'),
        findSource('sr_access_denied_view.dart'),
      ]) {
        final String src = code(file);
        expect(src.contains(r'${state'), isFalse, reason: file.path);
        expect(src.contains(r'$state'), isFalse, reason: file.path);
        expect(src.contains('.name'), isFalse, reason: file.path);
        expect(src.contains('toString()'), isFalse, reason: file.path);
      }
    });

    test('the approved copy lives in exactly one module', () {
      final List<File> outsideCopy = sources
          .where((File f) => f.path != copyFile.path)
          .toList();

      for (final File file in outsideCopy) {
        final String src = code(file);
        expect(
          src.contains('This Retailer is currently inactive'),
          isFalse,
          reason: file.path,
        );
        expect(
          src.contains('Your access to this Retailer is inactive'),
          isFalse,
          reason: file.path,
        );
        expect(
          src.contains('Your SalesReward account is currently inactive'),
          isFalse,
          reason: file.path,
        );
        expect(
          src.contains('More than one Retailer context is available'),
          isFalse,
          reason: file.path,
        );
      }
    });

    test('no preservation reassurance was added to the denied surfaces', () {
      // Technically true statements that are NOT part of the approved copy, and
      // "sign in again", which the approved flow deliberately never says
      // because reactivation does not require it.
      //
      // Scoped to the access-denied surfaces rather than all of lib/: the
      // account sheet has said "sign in again" since long before this feature,
      // in a context where it is correct, and a repository-wide scan would
      // fail on it while protecting nothing here.
      for (final File file in <File>[
        pageFile,
        copyFile,
        findSource('sr_lifecycle_notice_view.dart'),
        findSource('sr_access_denied_view.dart'),
      ]) {
        final String src = code(file);
        for (final String needle in <String>[
          'users remain',
          'roles remain',
          'Shops remain',
          'assignments remain',
          'receipts remain',
          'history remains',
          'sign in again',
        ]) {
          expect(src.contains(needle), isFalse, reason: '${file.path} $needle');
        }
      }
    });
  });

  group('the diagnostic is confined to the signed-in denied flow', () {
    test('only the access-denied page constructs the cubit', () {
      final Iterable<File> constructors = sources.where(
        (File f) =>
            f.path != cubitFile.path &&
            code(f).contains('LifecycleAccessCubit('),
      );

      expect(constructors.map((File f) => f.path), <String>[
        'lib/features/auth/presentation/pages/access_denied_page.dart',
      ]);
    });

    test('no shell or feature reads the diagnostic repository', () {
      final Iterable<File> readers = sources.where(
        (File f) =>
            !f.path.contains('/features/auth/') &&
            !f.path.contains('/app/di/') &&
            !f.path.contains('/app/app.dart') &&
            code(f).contains('LifecycleAccessRepository'),
      );

      expect(readers.map((File f) => f.path), isEmpty);
    });

    test('no shell mounts the notice view', () {
      final Iterable<File> mounts = sources.where(
        (File f) =>
            f.path.contains('/app/shells/') &&
            code(f).contains('SrLifecycleNoticeView'),
      );

      expect(mounts.map((File f) => f.path), isEmpty);
    });

    test('the cubit is never registered in the service locator', () {
      final String injector = code(findSource('app/di/injector.dart'));
      expect(injector.contains('LifecycleAccessCubit'), isFalse);
      // The repository, by contrast, is registered — that is the supported way
      // for the page to obtain it.
      expect(injector.contains('LifecycleAccessRepository'), isTrue);
    });
  });

  group('the lifecycle write features are untouched', () {
    test('no diagnostic file names a lifecycle write RPC', () {
      for (final File file in <File>[
        dataSourceFile,
        parserFile,
        copyFile,
        cubitFile,
        findSource('supabase_lifecycle_access_repository.dart'),
      ]) {
        final String src = code(file);
        expect(
          src.contains('set_retailer_staff_membership_status'),
          isFalse,
          reason: file.path,
        );
        expect(
          src.contains('set_vendor_retailer_status'),
          isFalse,
          reason: file.path,
        );
      }
    });

    test('each lifecycle write RPC still has exactly one call site', () {
      for (final String rpc in <String>[
        'set_retailer_staff_membership_status',
        'set_vendor_retailer_status',
      ]) {
        final Iterable<File> callers = sources.where(
          (File f) => code(f).contains("'$rpc'"),
        );
        expect(
          callers.length,
          1,
          reason: '$rpc must keep exactly one call site',
        );
      }
    });
  });

  group('no backend artefact and no Android-specific work', () {
    test('there is no migration, Edge Function or SQL file', () {
      for (final String path in <String>[
        'supabase',
        'migrations',
        'functions',
      ]) {
        expect(Directory(path).existsSync(), isFalse);
      }

      final Iterable<File> sqlFiles = Directory('.')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (File f) =>
                f.path.endsWith('.sql') &&
                !f.path.contains('/build/') &&
                !f.path.contains('/.dart_tool/'),
          );

      expect(sqlFiles.map((File f) => f.path), isEmpty);
    });

    test('no diagnostic file carries platform-specific code', () {
      for (final File file in <File>[
        dataSourceFile,
        parserFile,
        copyFile,
        cubitFile,
        pageFile,
        findSource('sr_lifecycle_notice_view.dart'),
      ]) {
        final String src = code(file);
        expect(src.contains('Platform.'), isFalse, reason: file.path);
        expect(src.contains('MethodChannel'), isFalse, reason: file.path);
        expect(src.contains('dart:io'), isFalse, reason: file.path);
      }
    });
  });
}

/// Fails if any [needle] appears in executable source.
void _expectAbsent(
  List<File> sources,
  List<String> needles, {
  bool allowInComments = false,
}) {
  final List<String> hits = <String>[];

  for (final File file in sources) {
    final List<String> lines = file.readAsLinesSync();

    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      final String trimmed = line.trimLeft();

      if (allowInComments &&
          (trimmed.startsWith('//') ||
              trimmed.startsWith('*') ||
              trimmed.startsWith('///'))) {
        continue;
      }

      for (final String needle in needles) {
        if (line.contains(needle)) {
          hits.add('${file.path}:${i + 1} → $needle');
        }
      }
    }
  }

  expect(hits, isEmpty, reason: 'forbidden references:\n${hits.join('\n')}');
}
