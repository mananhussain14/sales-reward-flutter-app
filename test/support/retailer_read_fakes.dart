import 'dart:async';

import 'package:sale_reward/features/products/domain/entities/retailer_assigned_product.dart';
import 'package:sale_reward/features/products/domain/repositories/retailer_product_repository.dart';
import 'package:sale_reward/features/shops/domain/entities/retailer_shop.dart';
import 'package:sale_reward/features/shops/domain/repositories/retailer_shop_repository.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_invitation.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_member.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_staff_repository.dart';

/// Completion plumbing shared by the three fakes.
///
/// Hand-written rather than mocked because these tests care about *how many
/// times* each contract was asked for as much as what came back: [callCount] is
/// how a test proves a duplicate refresh is suppressed, that opening one tab
/// does not read another, that a session change reloads exactly once, and that
/// an identical re-emitted session reloads not at all.
///
/// [manual] makes a call stay pending until completed by hand, so "a second
/// refresh while one is in flight" and "a stale answer arriving after a session
/// change" are deterministic rather than a sleep-and-hope. [completeAt] can
/// complete out of order, which is the stale-response race the request tokens
/// exist to close.
class _Pending<T> {
  final List<Completer<T>> _queue = <Completer<T>>[];

  int get length => _queue.length;

  Future<T> add() {
    final Completer<T> completer = Completer<T>();
    _queue.add(completer);
    return completer.future;
  }

  void completeAt(int index, T value) => _queue.removeAt(index).complete(value);
}

/// A hand-written [RetailerShopRepository] fake.
///
/// There is nothing to record about *what was sent*, because nothing is ever
/// sent — the contract takes zero arguments, which is why this fake has no
/// captured-parameter list at all. That absence is itself the shape of the
/// contract: a future edit adding a parameter would have to change this file to
/// compile.
class FakeRetailerShopRepository implements RetailerShopRepository {
  RetailerShopsResult? result;
  List<RetailerShop> nextShops = exampleShops;
  int callCount = 0;
  bool manual = false;

  final _Pending<RetailerShopsResult> _pending =
      _Pending<RetailerShopsResult>();

  int get pendingCount => _pending.length;

  void complete([RetailerShopsResult? override]) => completeAt(0, override);

  void completeAt(int index, [RetailerShopsResult? override]) {
    _pending.completeAt(
      index,
      override ?? result ?? RetailerShopsLoaded(nextShops),
    );
  }

  @override
  Future<RetailerShopsResult> shops() {
    callCount++;
    if (manual) {
      return _pending.add();
    }
    return Future<RetailerShopsResult>.value(
      result ?? RetailerShopsLoaded(nextShops),
    );
  }
}

/// A hand-written [RetailerStaffRepository] fake.
///
/// The two reads are counted and scripted **separately**, which is what lets a
/// test drive the partial-success case the screen must never describe as
/// "everything failed".
class FakeRetailerStaffRepository implements RetailerStaffRepository {
  RetailerStaffResult? rosterResult;
  RetailerInvitationsResult? invitationsResult;

  List<RetailerStaffMember> nextMembers = exampleStaff;
  List<RetailerStaffInvitation> nextInvitations = exampleInvitations;

  int memberCallCount = 0;
  int invitationCallCount = 0;
  bool manual = false;

  final _Pending<RetailerStaffResult> _members =
      _Pending<RetailerStaffResult>();
  final _Pending<RetailerInvitationsResult> _invites =
      _Pending<RetailerInvitationsResult>();

  int get pendingMemberCount => _members.length;
  int get pendingInvitationCount => _invites.length;

  void completeMembers([RetailerStaffResult? override]) =>
      completeMembersAt(0, override);

  void completeMembersAt(int index, [RetailerStaffResult? override]) {
    _members.completeAt(
      index,
      override ?? rosterResult ?? RetailerStaffLoaded(nextMembers),
    );
  }

  void completeInvitations([RetailerInvitationsResult? override]) =>
      completeInvitationsAt(0, override);

  void completeInvitationsAt(int index, [RetailerInvitationsResult? override]) {
    _invites.completeAt(
      index,
      override ??
          invitationsResult ??
          RetailerInvitationsLoaded(nextInvitations),
    );
  }

  @override
  Future<RetailerStaffResult> members() {
    memberCallCount++;
    if (manual) {
      return _members.add();
    }
    return Future<RetailerStaffResult>.value(
      rosterResult ?? RetailerStaffLoaded(nextMembers),
    );
  }

  @override
  Future<RetailerInvitationsResult> invitations() {
    invitationCallCount++;
    if (manual) {
      return _invites.add();
    }
    return Future<RetailerInvitationsResult>.value(
      invitationsResult ?? RetailerInvitationsLoaded(nextInvitations),
    );
  }
}

/// A hand-written [RetailerProductRepository] fake.
class FakeRetailerProductRepository implements RetailerProductRepository {
  RetailerProductsResult? result;
  List<RetailerAssignedProduct> nextProducts = exampleAssignedProducts;
  int callCount = 0;
  bool manual = false;

  final _Pending<RetailerProductsResult> _pending =
      _Pending<RetailerProductsResult>();

  int get pendingCount => _pending.length;

  void complete([RetailerProductsResult? override]) => completeAt(0, override);

  void completeAt(int index, [RetailerProductsResult? override]) {
    _pending.completeAt(
      index,
      override ?? result ?? RetailerProductsLoaded(nextProducts),
    );
  }

  @override
  Future<RetailerProductsResult> products() {
    callCount++;
    if (manual) {
      return _pending.add();
    }
    return Future<RetailerProductsResult>.value(
      result ?? RetailerProductsLoaded(nextProducts),
    );
  }
}

// ---------------------------------------------------------------------------
// Fixtures
//
// Invented data. Nothing here is a real organization, person, address or product
// from any environment. Values are deliberately distinct across the two
// "Retailer" sets so a session-isolation test can assert "A's data is gone" on
// any field rather than on a single lucky one.
// ---------------------------------------------------------------------------

/// An ordinary estate: one of each status, and one shop recorded with a name
/// alone — all three optional columns are nullable in the schema.
final List<RetailerShop> exampleShops = <RetailerShop>[
  const RetailerShop(
    name: 'Northwind Marina',
    code: 'NW-01',
    city: 'Dubai',
    countryCode: 'AE',
    status: RetailerShopStatus.active,
  ),
  const RetailerShop(
    name: 'Northwind Downtown',
    code: 'NW-02',
    city: 'Abu Dhabi',
    countryCode: 'AE',
    status: RetailerShopStatus.suspended,
  ),
  const RetailerShop(
    name: 'Northwind Warehouse',
    code: null,
    city: null,
    countryCode: null,
    status: RetailerShopStatus.deactivated,
  ),
];

/// A second Retailer's estate. Shares no value with [exampleShops].
final List<RetailerShop> otherShops = <RetailerShop>[
  const RetailerShop(
    name: 'Southgate Central',
    code: 'SG-11',
    city: 'Riyadh',
    countryCode: 'SA',
    status: RetailerShopStatus.active,
  ),
];

/// Membership ids for the roster fixtures.
///
/// Invented. No value here belongs to any environment; each is a well-formed
/// uuid chosen so a test asserting on one is obviously reading a fixture, and so
/// a leak test can search for a literal that could only have come from here.
const String aminaMembershipId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
const String priyaMembershipId = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
const String tomMembershipId = 'cccccccc-3333-4333-8333-cccccccccccc';
const String noorMembershipId = 'dddddddd-4444-4444-8444-dddddddddddd';

/// A second Retailer's membership id. Shares no value with the set above.
const String khalidMembershipId = 'eeeeeeee-5555-4555-8555-eeeeeeeeeeee';

/// An Owner's roster: every membership status the Owner view can contain, a
/// member with two shops, and members with none (an Owner and a Manager hold no
/// shop rows at all).
///
/// The shop ids here are the same literals the assignable-shop fixtures use, so
/// a preselection test exercises a real intersection rather than two disjoint
/// sets that would pass by accident.
final List<RetailerStaffMember> exampleStaff = <RetailerStaffMember>[
  RetailerStaffMember(
    membershipId: aminaMembershipId,
    firstName: 'Amina',
    lastName: 'Farouk',
    roleCode: 'RETAILER_OWNER',
    roleName: 'Retailer Owner',
    status: RetailerMemberStatus.active,
    shopIds: const <String>[],
    shopNames: const <String>[],
    joinedAt: DateTime.utc(2026, 3, 2),
    createdAt: DateTime.utc(2026, 3, 1),
  ),
  RetailerStaffMember(
    membershipId: priyaMembershipId,
    firstName: 'Priya',
    lastName: 'Raman',
    roleCode: 'SALES_STAFF',
    roleName: 'Sales Staff',
    status: RetailerMemberStatus.active,
    shopIds: const <String>[
      '22222222-2222-4222-8222-222222222222',
      '11111111-1111-4111-8111-111111111111',
    ],
    shopNames: const <String>['Northwind Downtown', 'Northwind Marina'],
    joinedAt: DateTime.utc(2026, 4, 12),
    createdAt: DateTime.utc(2026, 4, 10),
  ),
  RetailerStaffMember(
    membershipId: tomMembershipId,
    firstName: 'Tom',
    lastName: 'Byrne',
    roleCode: 'SALES_STAFF',
    roleName: 'Sales Staff',
    status: RetailerMemberStatus.suspended,
    shopIds: const <String>['11111111-1111-4111-8111-111111111111'],
    shopNames: const <String>['Northwind Marina'],
    // Never accepted, so no joining date. Rendered as an absence and never as
    // `created_at`.
    joinedAt: null,
    createdAt: DateTime.utc(2026, 5, 1),
  ),
  // Active Sales Staff who *has* accepted but holds no ACTIVE shop today —
  // the shape that proves the editor opens from an empty preselection rather
  // than refusing to open at all.
  RetailerStaffMember(
    membershipId: noorMembershipId,
    firstName: 'Noor',
    lastName: 'Aziz',
    roleCode: 'SALES_STAFF',
    roleName: 'Sales Staff',
    status: RetailerMemberStatus.active,
    shopIds: const <String>[],
    shopNames: const <String>[],
    joinedAt: DateTime.utc(2026, 6, 20),
    createdAt: DateTime.utc(2026, 6, 18),
  ),
];

/// The Manager's view of the same organization: the ACTIVE subset only, which is
/// what `and (v_can_manage or m.status = 'ACTIVE')` produces for them.
final List<RetailerStaffMember> managerVisibleStaff = exampleStaff
    .where((RetailerStaffMember m) => m.status.isActive)
    .toList();

/// A second Retailer's roster.
final List<RetailerStaffMember> otherStaff = <RetailerStaffMember>[
  RetailerStaffMember(
    membershipId: khalidMembershipId,
    firstName: 'Khalid',
    lastName: 'Nasser',
    roleCode: 'RETAILER_OWNER',
    roleName: 'Retailer Owner',
    status: RetailerMemberStatus.active,
    shopIds: const <String>[],
    shopNames: const <String>[],
    joinedAt: DateTime.utc(2026, 1, 9),
    createdAt: DateTime.utc(2026, 1, 8),
  ),
];

/// One invitation per derived state, including both fallbacks.
final List<RetailerStaffInvitation> exampleInvitations =
    <RetailerStaffInvitation>[
      RetailerStaffInvitation(
        firstName: 'Lena',
        lastName: 'Osei',
        email: 'lena@example.com',
        roleCode: 'SALES_STAFF',
        state: RetailerInvitationState.pending,
        hasDeliveryFailure: false,
        createdAt: DateTime.utc(2026, 6, 1),
        sentAt: DateTime.utc(2026, 6, 1),
        acceptedAt: null,
        revokedAt: null,
        expiresAt: DateTime.utc(2026, 7, 1),
      ),
      RetailerStaffInvitation(
        firstName: 'Marco',
        lastName: 'Silva',
        email: 'marco@example.com',
        roleCode: 'RETAILER_MANAGER',
        state: RetailerInvitationState.deliveryFailed,
        hasDeliveryFailure: true,
        createdAt: DateTime.utc(2026, 6, 3),
        sentAt: DateTime.utc(2026, 6, 3),
        acceptedAt: null,
        revokedAt: null,
        expiresAt: DateTime.utc(2026, 7, 3),
      ),
      RetailerStaffInvitation(
        firstName: 'Sara',
        lastName: 'Haddad',
        email: 'sara@example.com',
        roleCode: 'SALES_STAFF',
        state: RetailerInvitationState.accepted,
        hasDeliveryFailure: false,
        createdAt: DateTime.utc(2026, 5, 2),
        sentAt: DateTime.utc(2026, 5, 2),
        acceptedAt: DateTime.utc(2026, 5, 4),
        revokedAt: null,
        expiresAt: DateTime.utc(2026, 6, 2),
      ),
      RetailerStaffInvitation(
        firstName: 'Dan',
        lastName: 'Whitfield',
        email: 'dan@example.com',
        roleCode: 'SALES_STAFF',
        // The backend's CASE produced NULL — a real, reachable value.
        state: RetailerInvitationState.indeterminate,
        hasDeliveryFailure: false,
        createdAt: DateTime.utc(2026, 6, 10),
        sentAt: DateTime.utc(2026, 6, 10),
        acceptedAt: null,
        revokedAt: null,
        expiresAt: DateTime.utc(2026, 7, 10),
      ),
    ];

/// A second Retailer's invitation history.
final List<RetailerStaffInvitation> otherInvitations =
    <RetailerStaffInvitation>[
      RetailerStaffInvitation(
        firstName: 'Yusuf',
        lastName: 'Karim',
        email: 'yusuf@example.com',
        roleCode: 'SALES_STAFF',
        state: RetailerInvitationState.revoked,
        hasDeliveryFailure: false,
        createdAt: DateTime.utc(2026, 2, 1),
        sentAt: DateTime.utc(2026, 2, 1),
        acceptedAt: null,
        revokedAt: DateTime.utc(2026, 2, 5),
        expiresAt: DateTime.utc(2026, 3, 1),
      ),
    ];

/// An assigned catalogue: one fully-populated product and one recorded with only
/// the two required columns.
final List<RetailerAssignedProduct> exampleAssignedProducts =
    <RetailerAssignedProduct>[
      const RetailerAssignedProduct(
        productCode: 'ESP-1000',
        productName: 'Espresso Blend 1kg',
        barcode: '5012345678900',
        brand: 'Aurora',
        description: 'A dark roast blend for espresso machines.',
        assignmentStatus: 'ACTIVE',
      ),
      const RetailerAssignedProduct(
        productCode: 'TEA-2000',
        productName: 'Green Tea 500g',
        barcode: null,
        brand: null,
        description: null,
        assignmentStatus: 'ACTIVE',
      ),
    ];

/// A second Retailer's assigned catalogue.
final List<RetailerAssignedProduct> otherAssignedProducts =
    <RetailerAssignedProduct>[
      const RetailerAssignedProduct(
        productCode: 'CHO-3000',
        productName: 'Dark Chocolate 200g',
        barcode: '5099887766554',
        brand: 'Cacao Norte',
        description: null,
        assignmentStatus: 'ACTIVE',
      ),
    ];
