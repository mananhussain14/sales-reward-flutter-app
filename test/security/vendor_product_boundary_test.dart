@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-safety assertions for the Vendor Product read **and write** boundary.
///
/// The companion to `no_secrets_test.dart`, `receipt_boundary_test.dart`,
/// `vendor_retailer_boundary_test.dart`, `vendor_user_boundary_test.dart` and
/// `vendor_role_boundary_test.dart`. These read the source rather than exercise
/// it, which makes them the cheapest guard against the boundary eroding under
/// deadline pressure — the kind of regression a behavioural test cannot see,
/// because the code that erodes it usually still works.
///
/// The properties defended, stated once each:
///
/// * **The client never decides which Vendor it is.** All six deployed functions
///   derive the Vendor from `auth.uid()`, and every product id is matched on both
///   its own value and that derived Vendor. No call carries an organization,
///   tenant, auth-user, profile, membership, actor, role, permission or
///   audit-metadata argument, because none of them has a parameter for one.
/// * **The client never touches a protected table.** `vendor_products` and
///   `vendor_product_retailer_assignments` are default-deny with **zero** RLS
///   policies and no privilege for `authenticated`; RPC is the only way in, by
///   design. `audit_logs` is written by the RPCs themselves, in the same
///   transaction, and never from here.
/// * **The write surface is exactly three operations.** Create, edit and status.
///   No deletion — none exists in the schema — and no assignment write, which is a
///   separate milestone on a separate permission, so the assigned-Retailer section
///   stays read-only.
/// * **The immutable stays immutable.** The product code is absent from the edit
///   request type and from the edit payload; a status is absent from both the
///   create and the edit payload.
/// * **A barcode is text.** Never parsed, never a number — a leading zero and a
///   14-digit GTIN both survive only as text.
/// * **No backend text is rendered.** The two pinned duplicate literals are matched
///   in exactly one file, to derive a form-field key, and no presentation source
///   reaches for an error's message under any spelling.
/// * **The client never invents a product image or a category**, because no such
///   column, bucket or storage call exists anywhere in the product.
/// * **The client never infers one status from another** — assignment,
///   relationship, Retailer and product statuses are four separate facts.
/// * **The client never navigates by a Retailer organization id.** Cross-linking
///   uses `relationship_id` alone, and a null one is simply not navigable.
void main() {
  late List<File> sources;
  late List<File> productSources;
  late String rpcDataSource;
  late String writeDataSource;

  /// The file's executable lines only.
  ///
  /// Every check below is about what the code *does*. The doc comments in this
  /// feature deliberately discuss the things the code must not do — "there is no
  /// image column", "never `retailer_organization_id` as a selector", "no
  /// `withdrawn_at` exists" — and a scan that could not tell the two apart would
  /// either fail on its own documentation or force the documentation to stop
  /// naming what it is protecting against.
  String code(File file) => file
      .readAsLinesSync()
      .where((String line) {
        final String trimmed = line.trimLeft();
        return !trimmed.startsWith('//') && !trimmed.startsWith('*');
      })
      .join('\n');

  setUpAll(() {
    sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();
    productSources = sources
        .where((File f) => f.path.contains('/features/products/'))
        .toList();
    rpcDataSource = code(
      sources.firstWhere(
        (File f) => f.path.endsWith('/vendor_product_rpc_data_source.dart'),
      ),
    );
    writeDataSource = code(
      sources.firstWhere(
        (File f) =>
            f.path.endsWith('/vendor_product_write_rpc_data_source.dart'),
      ),
    );
  });

  test('the feature is non-empty (the scan would pass vacuously)', () {
    expect(productSources, isNotEmpty);
    expect(productSources.length, greaterThan(10));
  });

  group('no privileged key reaches the device', () {
    test('no source names a service-role or secret key', () {
      _expectAbsent(productSources, <String>[
        'SUPABASE_SERVICE_ROLE_KEY',
        'service_role',
        'serviceRoleKey',
        'sb_secret_',
        'SERVICE_KEY',
      ]);
    });

    test('no source reads an environment value of its own', () {
      for (final File file in productSources) {
        final String src = code(file);
        expect(src.contains('String.fromEnvironment'), isFalse);
        expect(src.contains('Platform.environment'), isFalse);
      }
    });

    test('no source hardcodes a credential', () {
      _expectAbsent(productSources, <String>[
        'Bearer sb_',
        'Bearer ey',
        "password: '",
        'apikey',
      ]);
    });

    test('dart_defines.json is ignored and not tracked by git', () {
      // The publishable key is supplied at build time and the file stays local.
      // A committed defines file is how a private value starts travelling with
      // the repository. It may exist on a developer's machine; it may not be in
      // the index.
      expect(
        File('.gitignore').readAsStringSync().contains('dart_defines.json'),
        isTrue,
      );

      final ProcessResult tracked = Process.runSync('git', <String>[
        'ls-files',
        'dart_defines.json',
      ]);
      expect((tracked.stdout as String).trim(), isEmpty);
    });
  });

  group('the RPC contract', () {
    test('p_product_id is the only parameter name in the READ source', () {
      final RegExp params = RegExp(r"'(p_[a-z_]+)'");
      final Set<String> named = params
          .allMatches(rpcDataSource)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();

      expect(named, <String>{'p_product_id'});
    });

    test('only the three deployed functions are named', () {
      final RegExp rpcNames = RegExp(r"const String \w+Rpc =\s*'([^']+)'");
      final List<String> names = rpcNames
          .allMatches(rpcDataSource)
          .map((RegExpMatch m) => m.group(1)!)
          .toList();

      expect(names, <String>[
        'list_vendor_products',
        'get_vendor_product_detail',
        'list_vendor_product_assigned_retailers',
      ]);
    });

    test('the catalogue invoker takes no arguments at all', () {
      // The typedef is the security property: with no parameter there is no
      // parameter to get wrong, and a future edit that adds one has to change
      // this line.
      expect(
        rpcDataSource,
        contains(
          'typedef VendorProductListInvoker = Future<Object?> Function();',
        ),
      );
    });

    test('no identity, tenant, status or permission argument', () {
      for (final String forbidden in <String>[
        'user_id',
        'p_user',
        'auth_user_id',
        'profile_id',
        'p_profile',
        'membership_id',
        'p_membership',
        'p_vendor',
        'vendor_organization_id',
        'organization_id',
        'p_organization',
        'p_retailer',
        'p_relationship',
        'p_status',
        'p_assignment_status',
        'role_code',
        'permission_code',
        'p_permission',
        'p_search',
        'p_limit',
        'p_offset',
        "'email'",
        'access_token',
        'tenant',
      ]) {
        expect(
          rpcDataSource.contains(forbidden),
          isFalse,
          reason: 'the Vendor Product RPCs must pass no $forbidden argument',
        );
      }
    });

    test('the selector is the product id, never the code, name or barcode', () {
      // The product code is unique PER VENDOR, not globally, so it could not
      // name one row without a tenant beside it — which is exactly the input
      // this contract refuses.
      expect(rpcDataSource.contains('productId'), isTrue);
      for (final File file in productSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'byProductCode',
          'productCodeSelector',
          'byBarcode',
          'byProductName',
          'productIndex',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} names $forbidden',
          );
        }
      }
    });

    test('the shipped editor matrix read is never called', () {
      // list_vendor_product_retailer_assignments() requires the permission to
      // CHANGE assignments, returns every managed Retailer including
      // never-assigned ones with a NULL status, and carries no relationship id.
      // It is the web's, and it is deliberately untouched.
      _expectAbsent(productSources, <String>[
        'list_vendor_product_retailer_assignments',
      ], allowInComments: true);
    });
  });

  group('no table is read directly', () {
    test('no source queries a product, assignment, Retailer or org table', () {
      // Both product tables have RLS enabled with ZERO policies and no
      // privilege for `anon` or `authenticated`, so a direct read would not
      // merely be poor layering — it would not work. The assignment aggregation
      // and the Retailer join happen in SQL, and reassembling them in a second
      // client would be a second definition of "which Retailers hold this".
      //
      // Table names are matched as *quoted literals*: the RPC names this
      // feature legitimately calls contain "product" as a substring.
      _expectAbsent(productSources, <String>[
        '.from(',
        "'vendor_products'",
        "'vendor_product_retailer_assignments'",
        "'vendor_retailers'",
        "'organizations'",
        "'profiles'",
        '.select(',
        '.eq(',
        '.in_(',
        '.maybeSingle(',
      ], allowInComments: true);
    });

    test('nothing anywhere touches auth.users', () {
      _expectAbsent(productSources, <String>[
        'auth.users',
        'auth_users',
        'authUsers',
        '.admin.',
        'getUserById',
        'listUsers',
      ], allowInComments: true);
    });
  });

  group('there is no product image, and no image system is implied', () {
    test('no source touches Storage or a signed URL', () {
      // The audit searched the whole backend: no image column, no product
      // bucket, no storage call, and no image on either web product page.
      // Building one here would be introducing an image system to decorate a
      // screen.
      _expectAbsent(productSources, <String>[
        'storage.from(',
        'uploadBinary(',
        'createSignedUrl',
        'getPublicUrl',
        'signedUrl',
      ], allowInComments: true);
    });

    test('no source models an image, media or asset field', () {
      _expectAbsent(productSources, <String>[
        'imageUrl',
        'image_url',
        'imagePath',
        'thumbnailUrl',
        'thumbnail_url',
        'photoUrl',
        'photo_url',
        'mediaUrl',
        'assetUrl',
        'productImage',
        'product_image',
      ], allowInComments: true);
    });

    test('no widget renders an image or reserves space for one', () {
      // Not even a grey placeholder frame: a fallback glyph in an image-shaped
      // box would advertise an image system that would then have to be built to
      // explain itself.
      final Iterable<File> presentation = productSources.where(
        (File f) => f.path.contains('/presentation/'),
      );
      expect(presentation, isNotEmpty);

      for (final File file in presentation) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'Image(',
          'Image.network',
          'Image.asset',
          'NetworkImage',
          'FadeInImage',
          'CachedNetworkImage',
          'DecorationImage',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} renders $forbidden',
          );
        }
      }
    });

    test('no source invents a category, price or reward field', () {
      // No category column exists; no price, incentive, campaign, reward, coin
      // or payout column exists anywhere in this schema.
      _expectAbsent(productSources, <String>[
        'categoryName',
        'category_name',
        'productCategory',
        'product_category',
        'unitPrice',
        'unit_price',
        'rewardValue',
        'reward_value',
        'incentive',
        'coinValue',
        'payout',
        'stockLevel',
        'stockCount',
        'inventoryCount',
        'quantityOnHand',
      ], allowInComments: true);
    });
  });

  group('no authorization is decided on the client', () {
    test('no source names a permission or role code', () {
      // The assignment companion requires PRODUCTS_READ *and* RETAILERS_READ.
      // That split is enforced in SQL; this client neither knows nor sends
      // either code, and a denial is one generic answer.
      _expectAbsent(productSources, <String>[
        'PRODUCTS_READ',
        'PRODUCTS_MANAGE',
        'RETAILERS_READ',
        'PRODUCT_RETAILER_ASSIGN',
        'VENDOR_SUPER_ADMIN',
        'RETAILER_OWNER',
        'SALES_STAFF',
      ], allowInComments: true);
    });

    test('no source names a backend function, policy or SQLSTATE', () {
      _expectAbsent(productSources, <String>[
        'has_organization_permission',
        'get_vendor_super_admin_context',
        'SQLSTATE',
        '42501',
        '22P02',
        '55000',
      ], allowInComments: true);
    });

    test('no source hardcodes an organization or product identifier', () {
      final RegExp uuidLiteral = RegExp(
        r"'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
        r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'",
      );

      for (final File file in productSources) {
        expect(
          uuidLiteral.hasMatch(code(file)),
          isFalse,
          reason: '${file.path} hardcodes an identifier',
        );
      }
    });

    test('no source infers authority from an email, token or metadata', () {
      for (final File file in productSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'userMetadata',
          'appMetadata',
          'user_metadata',
          'app_metadata',
          'SharedPreferences',
          '.decodeJwt',
          'jwtDecode',
          "endsWith('@",
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} infers authority from $forbidden',
          );
        }
      }
    });

    test('the Vendor authorization resolver is not duplicated', () {
      // Whether this caller is a Vendor Super Admin — and which Vendor they
      // are — is resolved once, in SQL. A second resolver here would be a
      // second definition free to drift.
      for (final File file in productSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'resolveVendor',
          'vendorContext',
          'organizationId',
          'isVendorSuperAdmin',
          'ownsProduct',
          'isOwnProduct',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} reimplements Vendor resolution or ownership',
          );
        }
      }
    });

    test('a portal kind is read for its label and for nothing else', () {
      // The role's display name is a legitimate use — it is the page-header
      // eyebrow — but a *comparison* would be the client deciding whether a read
      // is permitted, which the database decides again on every call.
      final RegExp anyUse = RegExp(r'PortalKind\.\w+(\.\w+)?');

      for (final File file in productSources) {
        for (final RegExpMatch match in anyUse.allMatches(code(file))) {
          expect(
            match.group(0),
            'PortalKind.vendorSuperAdmin.displayName',
            reason:
                '${file.path} uses a portal kind for something other than its '
                'label',
          );
        }
      }
    });

    test('no route or affordance is gated on product data', () {
      // A product's status, its counts and its dates are display data. Nothing
      // may branch a route or an authorization decision on any of them.
      for (final File file in productSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'canView',
          'canOpen',
          'isAuthorized',
          'hasAccess',
          'allowIfActive',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} computes access from product data',
          );
        }
      }
    });
  });

  group('statuses are four separate facts', () {
    test('an unknown product status is never mapped to active', () {
      final File statusFile = productSources.firstWhere(
        (File f) => f.path.endsWith('/vendor_product_status.dart'),
      );
      final String src = code(statusFile);

      // A positive test against `active`, so no future token can reach it by
      // failing to match something else.
      expect(src.contains('isActive => this == active'), isTrue);
      expect(src.contains('!= inactive'), isFalse);
    });

    test('an unknown assignment status is never mapped to active', () {
      final File statusFile = productSources.firstWhere(
        (File f) => f.path.endsWith('/vendor_product_assignment_status.dart'),
      );
      final String src = code(statusFile);

      expect(src.contains('isActive => this == active'), isTrue);
      expect(src.contains('!= inactive'), isFalse);
    });

    test('no source derives one status from another', () {
      // An ACTIVE assignment against a SUSPENDED relationship or a SUSPENDED
      // Retailer is a real, reachable state. Deriving either from the other
      // would render it as a contradiction the backend never sent.
      for (final File file in productSources) {
        final String src = code(file);
        // A single `=` and never `==`: comparing a status to group rows for
        // display is fine, and the detail state does exactly that. Assigning
        // one — computing a status rather than reading it — is the defect.
        for (final String field in <String>[
          'assignmentStatus',
          'relationshipStatus',
          'retailerStatus',
        ]) {
          expect(
            RegExp('$field\\s*=(?!=)').hasMatch(src),
            isFalse,
            reason: '${file.path} assigns a derived $field',
          );
        }
        for (final String forbidden in <String>[
          'effectiveStatus',
          'derivedStatus',
          'resolveStatus',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} derives a status',
          );
        }
      }
    });

    test('no source reads a status out of a date', () {
      // There is no `withdrawn_at` column, so none is invented, and
      // `assignment_updated_at` is never compared to decide a state.
      _expectAbsent(productSources, <String>[
        'withdrawnAt',
        'withdrawn_at',
        'isWithdrawn',
        'wasWithdrawnOn',
      ], allowInComments: true);
    });

    test('a status literal is never written outside the domain enums', () {
      // The tokens may be *recognised* — that is what the enums do — but never
      // assembled into a value the client sends or displays raw.
      final Iterable<File> outsideDomain = productSources.where(
        (File f) => !f.path.contains('/domain/entities/'),
      );

      for (final File file in outsideDomain) {
        final String src = code(file);
        for (final String token in <String>[
          "'ACTIVE'",
          "'INACTIVE'",
          "'SUSPENDED'",
          "'DEACTIVATED'",
        ]) {
          expect(
            src.contains(token),
            isFalse,
            reason: '${file.path} writes a backend status literal',
          );
        }
      }
    });
  });

  group('cross-linking uses the relationship id alone', () {
    test('the Retailer organization id is never a route selector', () {
      // It names a tenant some other Vendor may also manage, and the shipped
      // Retailer screens do not accept it. Using it would address a screen with
      // a key from the wrong address space.
      for (final File file in productSources) {
        final String src = code(file);
        expect(
          RegExp(
            r'retailerDetailPath\(\s*[a-zA-Z.]*retailerOrganizationId',
          ).hasMatch(src),
          isFalse,
          reason: '${file.path} navigates by the organization id',
        );
        expect(
          src.contains('organizationDetailPath'),
          isFalse,
          reason: '${file.path} invents an organization route',
        );
      }
    });

    test('a null relationship id is never repaired or substituted', () {
      for (final File file in productSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'relationshipId ??',
          'relationshipId!.isEmpty',
          'relationshipId ?? retailerOrganizationId',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} fabricates a relationship id',
          );
        }
      }
    });

    test('linkability is decided by the id, never by a status', () {
      final File entity = productSources.firstWhere(
        (File f) => f.path.endsWith('/vendor_product_assigned_retailer.dart'),
      );
      final String src = code(entity);

      expect(src.contains('isCrossLinkable => relationshipId != null'), isTrue);
      // A suspended or deactivated relationship is still addressable, and the
      // Retailer detail screen exists precisely to explain such a state.
      expect(
        RegExp(r'isCrossLinkable[^\n]*Status').hasMatch(src),
        isFalse,
        reason: 'linkability must not consult any status',
      );
    });

    test('no assignment row is filtered out of the list', () {
      // The list length is `assignment_count` by construction. A client that
      // dropped a row — an inactive one, or one with no relationship — would put
      // the list and the count in permanent, unexplainable disagreement.
      for (final File file in productSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'hideInactive',
          'onlyActive',
          'skipUnlinked',
          'dropOrphan',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} filters the assignment list',
          );
        }
      }
    });
  });

  group('the write boundary is exactly three product operations', () {
    test('only the three deployed write functions are named', () {
      final RegExp rpcNames = RegExp(r"const String \w+Rpc =\s*'([^']+)'");
      final List<String> names = rpcNames
          .allMatches(writeDataSource)
          .map((RegExpMatch m) => m.group(1)!)
          .toList();

      expect(names, <String>[
        'create_vendor_product',
        'update_vendor_product',
        'set_vendor_product_status',
      ]);
    });

    test('exactly seven parameter names, and no eighth', () {
      final RegExp params = RegExp(r"'(p_[a-z_]+)'");
      final Set<String> named = params
          .allMatches(writeDataSource)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();

      expect(named, <String>{
        'p_product_code',
        'p_product_name',
        'p_barcode',
        'p_brand',
        'p_description',
        'p_product_id',
        'p_status',
      });
    });

    test('create sends five product fields and no organization', () {
      // The whole payload, read off the invoker's own parameter list. There is no
      // organization id to send: the function derives the Vendor from auth.uid()
      // and has no parameter to nominate one.
      final String create = _bodyOf(
        writeDataSource,
        'VendorProductCreateInvoker supabaseVendorProductCreateInvoker',
      );

      for (final String expected in <String>[
        'productCodeParameter: productCode',
        'productNameParameter: productName',
        'barcodeParameter: barcode',
        'brandParameter: brand',
        'descriptionParameter: description',
      ]) {
        expect(create, contains(expected));
      }
      // No initial status, and no product id — a create addresses nothing.
      expect(create.contains('statusParameter'), isFalse);
      expect(create.contains('writeProductIdParameter'), isFalse);
    });

    test('edit sends the id and four fields — no code, no status', () {
      final String update = _bodyOf(
        writeDataSource,
        'VendorProductUpdateInvoker supabaseVendorProductUpdateInvoker',
      );

      for (final String expected in <String>[
        'writeProductIdParameter: productId',
        'productNameParameter: productName',
        'barcodeParameter: barcode',
        'brandParameter: brand',
        'descriptionParameter: description',
      ]) {
        expect(update, contains(expected));
      }
      // The two that make this contract what it is.
      expect(
        update.contains('productCodeParameter'),
        isFalse,
        reason: 'the product code is immutable and is not an edit parameter',
      );
      expect(
        update.contains('statusParameter'),
        isFalse,
        reason: 'an edit never writes a status',
      );
    });

    test('status sends the id and a status, and nothing else', () {
      final String status = _bodyOf(
        writeDataSource,
        'VendorProductStatusInvoker supabaseVendorProductStatusInvoker',
      );

      expect(status, contains('writeProductIdParameter: productId'));
      expect(status, contains('statusParameter: status'));
      for (final String forbidden in <String>[
        'productCodeParameter',
        'productNameParameter',
        'barcodeParameter',
        'brandParameter',
        'descriptionParameter',
      ]) {
        expect(status.contains(forbidden), isFalse);
      }
    });

    test('no identity, tenant, actor or permission argument', () {
      for (final String forbidden in <String>[
        'user_id',
        'p_user',
        'auth_user_id',
        'profile_id',
        'p_profile',
        'membership_id',
        'p_membership',
        'p_vendor',
        'vendor_organization_id',
        'organization_id',
        'p_organization',
        'p_owner',
        'p_created_by',
        'p_actor',
        'p_metadata',
        'p_audit',
        'p_retailer',
        'p_relationship',
        'p_assignment',
        'role_code',
        'permission_code',
        'p_permission',
        'p_price',
        'p_stock',
        'p_image',
        'p_reward',
        'p_campaign',
        'access_token',
        'tenant',
      ]) {
        expect(
          writeDataSource.contains(forbidden),
          isFalse,
          reason: 'the Vendor Product writes must pass no $forbidden argument',
        );
      }
    });

    test('no delete or assignment write is named anywhere', () {
      // Both assignment functions and any deletion. They are either a separate
      // milestone on a separate permission, or they do not exist in the schema at
      // all; naming one here is what a future edit would have to do, and it would
      // have to change this test.
      _expectAbsent(productSources, <String>[
        'delete_vendor_product',
        'assign_vendor_product_to_retailer',
        'unassign_vendor_product_from_retailer',
        'activate_product',
        'deactivate_product',
      ], allowInComments: true);
    });

    test('no source performs a table mutation on the client', () {
      // `audit_logs` included: every write RPC inserts its own audit row inside the
      // same transaction, and a client that added one would be recording an event
      // it cannot attest to.
      _expectAbsent(productSources, <String>[
        '.insert(',
        '.update(',
        '.upsert(',
        '.delete(',
        "'audit_logs'",
        'auditLogs.insert',
      ], allowInComments: true);
    });

    test('the repository interface exposes three reads and three writes', () {
      final File repository = productSources.firstWhere(
        (File f) => f.path.endsWith('/vendor_product_repository.dart'),
      );
      final String src = code(repository);

      final RegExp reads = RegExp(r'Future<ReadResult<[^>]+>*>?\s+(\w+)\(');
      expect(
        reads.allMatches(src).map((RegExpMatch m) => m.group(1)!).toSet(),
        <String>{'products', 'productDetail', 'assignedRetailers'},
      );

      final RegExp writes = RegExp(
        r'Future<VendorProductWriteResult<[^>]+>>\s+(\w+)\(',
      );
      expect(
        writes.allMatches(src).map((RegExpMatch m) => m.group(1)!).toSet(),
        <String>{'createProduct', 'updateProduct', 'setProductStatus'},
        reason:
            'exactly three writes, so no delete or assignment method can appear '
            'without changing this file',
      );

      // No fourth spelling of a mutation, whatever its return type.
      for (final String forbidden in <String>[
        'deleteProduct',
        'removeProduct',
        'archiveProduct',
        'assignRetailer',
        'unassignRetailer',
        'withdrawFromRetailer',
        'setAssignmentStatus',
        'uploadProductImage',
      ]) {
        expect(
          src.contains(forbidden),
          isFalse,
          reason: 'the repository declares $forbidden',
        );
      }
    });

    test('the edit request type has no code and no status field', () {
      // The type is the enforcement: a request object with no product-code field
      // cannot send one, whatever a caller intends.
      final String src = code(
        productSources.firstWhere(
          (File f) => f.path.endsWith('/vendor_product_edit.dart'),
        ),
      );

      for (final String field in <String>[
        'productCode',
        'status',
        'organizationId',
        'vendorId',
        'createdBy',
      ]) {
        expect(
          src.contains('this.$field'),
          isFalse,
          reason: 'VendorProductEdit carries a $field field',
        );
      }
      for (final String field in <String>[
        'productName',
        'barcode',
        'brand',
        'description',
      ]) {
        expect(src, contains('this.$field'));
      }
    });

    test('the create request type has no status and no tenant field', () {
      final String src = code(
        productSources.firstWhere(
          (File f) => f.path.endsWith('/vendor_product_draft.dart'),
        ),
      );

      for (final String field in <String>[
        'status',
        'organizationId',
        'vendorId',
        'createdBy',
        'profileId',
        'price',
        'stock',
        'imageUrl',
        'rewardValue',
      ]) {
        expect(
          src.contains('this.$field'),
          isFalse,
          reason: 'VendorProductDraft carries a $field field',
        );
      }
    });

    test('a barcode is text everywhere, and never a number', () {
      // `int` would drop a leading zero and `double` cannot hold a 14-digit GTIN
      // exactly, so either would silently change what a barcode means.
      for (final File file in productSources) {
        final String src = code(file);
        for (final RegExp pattern in <RegExp>[
          RegExp(r'int\??\s+barcode'),
          RegExp(r'double\??\s+barcode'),
          RegExp(r'num\??\s+barcode'),
          RegExp(r'int\.parse\(\s*\w*[Bb]arcode'),
          RegExp(r'int\.tryParse\(\s*\w*[Bb]arcode'),
          RegExp(r'double\.parse\(\s*\w*[Bb]arcode'),
        ]) {
          expect(
            pattern.hasMatch(src),
            isFalse,
            reason: '${file.path} treats a barcode as a number',
          );
        }
      }
    });

    test('a status is never assembled outside the two enums', () {
      // The request enum is the only place either token is written, and it holds
      // exactly two members — so the response enum's forward-compatibility
      // `unknown` can never reach the wire.
      final String src = code(
        productSources.firstWhere(
          (File f) => f.path.endsWith('/vendor_product_status_change.dart'),
        ),
      );
      expect(src, contains("activate('ACTIVE')"));
      expect(src, contains("deactivate('INACTIVE')"));
      expect(
        src.contains("'DELETED'") || src.contains("'ARCHIVED'"),
        isFalse,
        reason: 'neither is a status in this schema',
      );
    });

    test('the duplicate-literal dependency lives in exactly one file', () {
      // The deployed contract discriminates a duplicate product code from a
      // duplicate barcode by one of two fixed message literals and by nothing else.
      // Matching them is unavoidable; matching them in more than one place is not.
      final Iterable<File> matchers = productSources.where(
        (File f) => code(f).contains('already exists'),
      );

      expect(matchers.map((File f) => f.path.split('/').last).toSet(), <String>{
        // Where the two backend literals are matched, to derive a field key.
        'vendor_product_write_parsers.dart',
        // Where this application's OWN sentences for those field keys live. Neither
        // is a backend string.
        'vendor_product_input.dart',
        // The screen wording for a duplicate the backend did not attribute.
        'vendor_product_copy.dart',
      });
    });

    test('no backend message text is rendered', () {
      // A presentation file may not read an error's message under any spelling.
      final Iterable<File> presentation = productSources.where(
        (File f) => f.path.contains('/presentation/'),
      );
      expect(presentation, isNotEmpty);

      for (final File file in presentation) {
        final String src = code(file);
        for (final String forbidden in <String>[
          '.message',
          'error.toString',
          'PostgrestException',
          'AuthException',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} reaches for backend error text',
          );
        }
      }
    });
  });

  group('layering', () {
    test('presentation never touches Supabase or HTTP directly', () {
      final Iterable<File> presentation = productSources.where(
        (File f) => f.path.contains('/presentation/'),
      );
      expect(presentation, isNotEmpty);

      for (final File file in presentation) {
        final String src = code(file);
        expect(
          src.contains('Supabase.instance'),
          isFalse,
          reason: '${file.path} reaches Supabase directly',
        );
        expect(
          src.contains('package:supabase_flutter'),
          isFalse,
          reason: '${file.path} imports the Supabase SDK',
        );
        expect(
          src.contains('package:http'),
          isFalse,
          reason: '${file.path} performs its own HTTP',
        );
      }
    });

    test('the domain layer depends on no SDK or transport package', () {
      final Iterable<File> domain = productSources.where(
        (File f) => f.path.contains('/domain/'),
      );
      expect(domain, isNotEmpty);

      for (final File file in domain) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'package:supabase_flutter',
          'package:http',
          'package:flutter/',
          'dart:io',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} imports $forbidden',
          );
        }
      }
    });

    test('no BLoC state holds a raw backend map', () {
      final Iterable<File> cubits = productSources.where(
        (File f) => f.path.contains('/cubit/'),
      );
      expect(cubits, isNotEmpty);

      for (final File file in cubits) {
        final String src = code(file);
        expect(
          src.contains('Map<String, Object?>'),
          isFalse,
          reason: '${file.path} holds a raw SDK map',
        );
        expect(
          src.contains('Map<String, dynamic>'),
          isFalse,
          reason: '${file.path} holds a raw SDK map',
        );
        expect(
          RegExp(r'\bdynamic\b').hasMatch(src),
          isFalse,
          reason: '${file.path} holds an untyped value',
        );
      }
    });

    test('only the data layer names an RPC', () {
      final Iterable<File> offenders = productSources.where((File f) {
        if (f.path.contains('/data/')) return false;
        final String src = code(f);
        return src.contains('list_vendor_products') ||
            src.contains('get_vendor_product_detail') ||
            src.contains('list_vendor_product_assigned_retailers');
      });

      expect(
        offenders.map((File f) => f.path),
        isEmpty,
        reason: 'RPC names belong in the data layer alone',
      );
    });
  });

  group('nothing fake is rendered', () {
    test('no source invents a product, a code or a count', () {
      for (final File file in productSources) {
        final String src = code(file);
        for (final String forbidden in <String>[
          'Example Product',
          'Sample Product',
          'Lorem',
          'mockProduct',
          'sampleProduct',
          'fakeProduct',
          'Coming soon',
          'placeholderProduct',
          'demoBarcode',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '${file.path} contains fabricated data',
          );
        }
      }
    });

    test('a nullable field is never given a fabricated fallback', () {
      // A barcode invented from the product code, or a brand from the name,
      // would be a value the backend never sent, presented as though it had.
      for (final File file in productSources) {
        final String src = code(file);
        for (final RegExp pattern in <RegExp>[
          RegExp(r'barcode\s*\?\?\s*product'),
          RegExp(r'brand\s*\?\?\s*product'),
          RegExp(r'description\s*\?\?\s*product'),
        ]) {
          expect(
            pattern.hasMatch(src),
            isFalse,
            reason: '${file.path} fabricates a nullable field',
          );
        }
      }
    });

    test('the neutral placeholder exists only in presentation', () {
      // "Not recorded" is a rendering of null, never a value stored on an
      // entity or compared against.
      final Iterable<File> nonPresentation = productSources.where(
        (File f) => !f.path.contains('/presentation/'),
      );

      for (final File file in nonPresentation) {
        expect(
          code(file).contains('Not recorded'),
          isFalse,
          reason: '${file.path} stores a presentation placeholder',
        );
      }
    });

    test('an inactive assignment is never called currently assigned', () {
      final File copy = productSources.firstWhere(
        (File f) => f.path.endsWith('/vendor_product_copy.dart'),
      );
      // Executable source only: this file's doc comment states the very rule
      // it enforces, and a scan that could not tell the two apart would force
      // the documentation to stop naming what it protects against.
      final String src = code(copy);

      // `assignment_count` includes withdrawn rows, so this phrase would be
      // false about the number the backend actually sent.
      expect(src.contains('Retailers currently assigned'), isFalse);
    });
  });
}

/// The source of the function or getter whose declaration starts with [signature],
/// up to its closing brace.
///
/// Used so a payload assertion reads one invoker's own body rather than the whole
/// file: with three invokers in one place, a `contains` over the file would pass
/// because *some* invoker sends a parameter, which is exactly the mistake these
/// tests exist to catch.
String _bodyOf(String source, String signature) {
  final int start = source.indexOf(signature);
  expect(
    start,
    greaterThanOrEqualTo(0),
    reason: 'no declaration for $signature',
  );

  int depth = 0;
  bool opened = false;
  for (int i = start; i < source.length; i++) {
    if (source[i] == '{') {
      depth++;
      opened = true;
    } else if (source[i] == '}') {
      depth--;
      if (opened && depth == 0) {
        return source.substring(start, i + 1);
      }
    }
  }
  fail('unterminated declaration for $signature');
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

  expect(hits, isEmpty, reason: 'forbidden reference(s):\n${hits.join('\n')}');
}
