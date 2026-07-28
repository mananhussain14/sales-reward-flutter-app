import 'dart:async';

import 'package:sale_reward/features/staff/domain/entities/retailer_assignable_shop.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_invitation_outcome.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_invitation_request.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_staff_invitation_repository.dart';

/// Completion plumbing, shared with the read fakes' `_Pending` in spirit.
///
/// Hand-written rather than mocked because these tests care about *what was
/// sent* and *how many times* as much as what came back: [sentRequests] is how a
/// test proves a double tap produced one invitation and not two, and that a
/// Manager request carried no shops.
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

/// A hand-written [RetailerStaffInvitationRepository] fake.
///
/// [sentRequests] records the **domain** request rather than an encoded body,
/// because that is what the interface takes; the encoding is pinned separately
/// by the request-body test. There is still nothing to record for
/// [assignableShops], because the contract takes zero arguments — an absence
/// that is itself the shape of the contract, since adding a parameter would have
/// to change this file to compile.
class FakeRetailerStaffInvitationRepository
    implements RetailerStaffInvitationRepository {
  RetailerAssignableShopsResult? shopsResult;
  List<RetailerAssignableShop> nextShops = exampleAssignableShops;

  RetailerStaffInvitationSendResult? sendResult;

  int shopCallCount = 0;
  int sendCallCount = 0;

  /// Every request handed to [send], in order.
  final List<RetailerStaffInvitationRequest> sentRequests =
      <RetailerStaffInvitationRequest>[];

  bool manualShops = false;
  bool manualSend = false;

  final _Pending<RetailerAssignableShopsResult> _shops =
      _Pending<RetailerAssignableShopsResult>();
  final _Pending<RetailerStaffInvitationSendResult> _sends =
      _Pending<RetailerStaffInvitationSendResult>();

  int get pendingShopCount => _shops.length;
  int get pendingSendCount => _sends.length;

  void completeShops([RetailerAssignableShopsResult? override]) =>
      completeShopsAt(0, override);

  void completeShopsAt(int index, [RetailerAssignableShopsResult? override]) {
    _shops.completeAt(
      index,
      override ?? shopsResult ?? RetailerAssignableShopsLoaded(nextShops),
    );
  }

  void completeSend([RetailerStaffInvitationSendResult? override]) =>
      completeSendAt(0, override);

  void completeSendAt(
    int index, [
    RetailerStaffInvitationSendResult? override,
  ]) {
    _sends.completeAt(index, override ?? sendResult ?? sentAnswer);
  }

  @override
  Future<RetailerAssignableShopsResult> assignableShops() {
    shopCallCount++;
    if (manualShops) {
      return _shops.add();
    }
    return Future<RetailerAssignableShopsResult>.value(
      shopsResult ?? RetailerAssignableShopsLoaded(nextShops),
    );
  }

  @override
  Future<RetailerStaffInvitationSendResult> send(
    RetailerStaffInvitationRequest request,
  ) {
    sendCallCount++;
    sentRequests.add(request);
    if (manualSend) {
      return _sends.add();
    }
    return Future<RetailerStaffInvitationSendResult>.value(
      sendResult ?? sentAnswer,
    );
  }
}

// ---------------------------------------------------------------------------
// Fixtures
//
// Invented data. No shop id here belongs to any environment; each is a
// well-formed uuid chosen so a test asserting on one is obviously reading a
// fixture.
// ---------------------------------------------------------------------------

const String northwindMarinaId = '11111111-1111-4111-8111-111111111111';
const String northwindDowntownId = '22222222-2222-4222-8222-222222222222';
const String northwindWarehouseId = '33333333-3333-4333-8333-333333333333';

/// A second Retailer's shop. Shares no value with the set below, so a
/// session-isolation test can assert "A's estate is gone" on any field.
const String southgateCentralId = '44444444-4444-4444-8444-444444444444';

/// An ordinary picker: two fully-recorded shops and one with a name alone —
/// both optional columns on this contract are nullable.
final List<RetailerAssignableShop> exampleAssignableShops =
    <RetailerAssignableShop>[
      const RetailerAssignableShop(
        id: northwindDowntownId,
        name: 'Northwind Downtown',
        code: 'NW-02',
        city: 'Abu Dhabi',
      ),
      const RetailerAssignableShop(
        id: northwindMarinaId,
        name: 'Northwind Marina',
        code: 'NW-01',
        city: 'Dubai',
      ),
      const RetailerAssignableShop(
        id: northwindWarehouseId,
        name: 'Northwind Warehouse',
        code: null,
        city: null,
      ),
    ];

/// A second Retailer's assignable shops.
final List<RetailerAssignableShop> otherAssignableShops =
    <RetailerAssignableShop>[
      const RetailerAssignableShop(
        id: southgateCentralId,
        name: 'Southgate Central',
        code: 'SG-11',
        city: 'Riyadh',
      ),
    ];

const RetailerStaffInvitationSendResult sentAnswer =
    RetailerStaffInvitationAnswered(
      outcome: RetailerStaffInvitationOutcome.sent,
      code: RetailerStaffInvitationCode.sent,
    );

const RetailerStaffInvitationSendResult resentAnswer =
    RetailerStaffInvitationAnswered(
      outcome: RetailerStaffInvitationOutcome.resent,
      code: RetailerStaffInvitationCode.resent,
    );

/// The HTTP 202 partial success.
const RetailerStaffInvitationSendResult unconfirmedAnswer =
    RetailerStaffInvitationAnswered(
      outcome: RetailerStaffInvitationOutcome.deliveryAcceptedStatusUnconfirmed,
      code: RetailerStaffInvitationCode.deliveryAcceptedStatusUnconfirmed,
    );

const RetailerStaffInvitationSendResult deliveryFailedAnswer =
    RetailerStaffInvitationAnswered(
      outcome: RetailerStaffInvitationOutcome.deliveryFailed,
      code: RetailerStaffInvitationCode.deliveryFailed,
    );

/// A `NOT_SENT` answer with an arbitrary stable code.
RetailerStaffInvitationSendResult notSentAnswer(
  RetailerStaffInvitationCode code,
) => RetailerStaffInvitationAnswered(
  outcome: RetailerStaffInvitationOutcome.notSent,
  code: code,
);
