import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/retailer_read_problem.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_assignable_shop.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_invitation_outcome.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_invitation_request.dart';
import 'package:sale_reward/features/staff/domain/entities/retailer_staff_invitation_role.dart';
import 'package:sale_reward/features/staff/domain/repositories/retailer_staff_invitation_repository.dart';
import 'package:sale_reward/features/staff/presentation/retailer/cubit/retailer_invite_staff_cubit.dart';

import '../../support/retailer_invite_staff_fakes.dart';

/// The Invite Staff cubit.
///
/// The behaviours worth breaking a build over: one send per submission, no
/// automatic retry anywhere, an unresolved answer that never claims failure, a
/// history reread that never restates the send, and a session change that drops
/// everything including answers already in flight.
void main() {
  late FakeRetailerStaffInvitationRepository repository;
  late int rereadCalls;
  late bool rereadSucceeds;
  late Completer<bool>? manualReread;

  RetailerInviteStaffCubit build() {
    return RetailerInviteStaffCubit(
      repository,
      rereadHistory: () {
        rereadCalls++;
        if (manualReread != null) {
          return manualReread!.future;
        }
        return Future<bool>.value(rereadSucceeds);
      },
    );
  }

  setUp(() {
    repository = FakeRetailerStaffInvitationRepository();
    rereadCalls = 0;
    rereadSucceeds = true;
    manualReread = null;
  });

  /// Fills a valid Sales Staff form with the shop options already loaded.
  Future<void> fillSalesStaff(RetailerInviteStaffCubit cubit) async {
    cubit
      ..firstNameChanged('Priya')
      ..lastNameChanged('Raman')
      ..emailChanged('priya@example.com')
      ..roleChanged(RetailerStaffInvitationRole.salesStaff);
    await Future<void>.delayed(Duration.zero);
    cubit.shopSelectionToggled(northwindMarinaId);
  }

  void fillManager(RetailerInviteStaffCubit cubit) {
    cubit
      ..firstNameChanged('Marco')
      ..lastNameChanged('Silva')
      ..emailChanged('marco@example.com')
      ..roleChanged(RetailerStaffInvitationRole.retailerManager);
  }

  group('initial state', () {
    test('is empty, with no role chosen and nothing read', () {
      final RetailerInviteStaffCubit cubit = build();

      expect(cubit.state.firstName, isEmpty);
      expect(cubit.state.lastName, isEmpty);
      expect(cubit.state.email, isEmpty);
      // No default role: picking one for somebody is picking what a colleague
      // will be able to do.
      expect(cubit.state.role, isNull);
      expect(cubit.state.selectedShopIds, isEmpty);
      expect(cubit.state.shopsPhase, RetailerInviteShopsPhase.initial);
      expect(cubit.state.shops, isNull);
      expect(cubit.state.notice, isNull);
      expect(cubit.state.isSubmitting, isFalse);
      expect(repository.shopCallCount, 0);
      expect(repository.sendCallCount, 0);
    });
  });

  group('shop options', () {
    test('are not read until Sales Staff is chosen', () async {
      final RetailerInviteStaffCubit cubit = build();

      cubit.roleChanged(RetailerStaffInvitationRole.retailerManager);
      await Future<void>.delayed(Duration.zero);

      expect(repository.shopCallCount, 0);
      expect(cubit.state.showsShopPicker, isFalse);
    });

    test('are read once when Sales Staff is chosen', () async {
      final RetailerInviteStaffCubit cubit = build();

      cubit.roleChanged(RetailerStaffInvitationRole.salesStaff);
      await Future<void>.delayed(Duration.zero);

      expect(repository.shopCallCount, 1);
      expect(cubit.state.shopsPhase, RetailerInviteShopsPhase.ready);
      expect(cubit.state.shops, hasLength(3));
      expect(cubit.state.showsShopPicker, isTrue);
    });

    test('a successful list survives switching roles back and forth', () async {
      final RetailerInviteStaffCubit cubit = build();

      cubit.roleChanged(RetailerStaffInvitationRole.salesStaff);
      await Future<void>.delayed(Duration.zero);
      cubit.roleChanged(RetailerStaffInvitationRole.retailerManager);
      cubit.roleChanged(RetailerStaffInvitationRole.salesStaff);
      await Future<void>.delayed(Duration.zero);

      // The estate belongs to the Retailer rather than to the role, so a second
      // read would be a request whose answer cannot have changed.
      expect(repository.shopCallCount, 1);
      expect(cubit.state.shops, hasLength(3));
    });

    test('a failed list is retried on the next switch back', () async {
      repository.shopsResult = const RetailerAssignableShopsFailed(
        RetailerReadProblem.timeout,
      );
      final RetailerInviteStaffCubit cubit = build();

      cubit.roleChanged(RetailerStaffInvitationRole.salesStaff);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.hasShopsFailed, isTrue);

      cubit.roleChanged(RetailerStaffInvitationRole.retailerManager);
      cubit.roleChanged(RetailerStaffInvitationRole.salesStaff);
      await Future<void>.delayed(Duration.zero);

      expect(repository.shopCallCount, 2);
    });

    test('a denial is not shown as an empty estate', () async {
      repository.shopsResult = const RetailerAssignableShopsFailed(
        RetailerReadProblem.denied,
      );
      final RetailerInviteStaffCubit cubit = build();

      cubit.roleChanged(RetailerStaffInvitationRole.salesStaff);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.hasShopsFailed, isTrue);
      expect(cubit.state.isShopsEmpty, isFalse);
      expect(cubit.state.shopsProblem, RetailerReadProblem.denied);
    });

    test('zero rows is a real, empty answer', () async {
      repository.nextShops = const <RetailerAssignableShop>[];
      final RetailerInviteStaffCubit cubit = build();

      cubit.roleChanged(RetailerStaffInvitationRole.salesStaff);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.isShopsEmpty, isTrue);
      expect(cubit.state.hasShopsFailed, isFalse);
    });

    test('a tick the newest response no longer offers is dropped', () async {
      final RetailerInviteStaffCubit cubit = build();

      cubit.roleChanged(RetailerStaffInvitationRole.salesStaff);
      await Future<void>.delayed(Duration.zero);
      cubit.shopSelectionToggled(northwindMarinaId);
      expect(cubit.state.selectedShopIds, contains(northwindMarinaId));

      repository.nextShops = <RetailerAssignableShop>[
        exampleAssignableShops.first,
      ];
      await cubit.loadAssignableShops();

      expect(cubit.state.selectedShopIds, isEmpty);
    });

    test('a duplicate load while one is in flight is suppressed', () async {
      repository.manualShops = true;
      final RetailerInviteStaffCubit cubit = build();

      unawaited(cubit.loadAssignableShops());
      unawaited(cubit.loadAssignableShops());
      await Future<void>.delayed(Duration.zero);

      expect(repository.shopCallCount, 1);
      repository.completeShops();
    });
  });

  group('selection', () {
    test('toggling adds and removes by id', () async {
      final RetailerInviteStaffCubit cubit = build();
      cubit.roleChanged(RetailerStaffInvitationRole.salesStaff);
      await Future<void>.delayed(Duration.zero);

      cubit.shopSelectionToggled(northwindMarinaId);
      expect(cubit.state.selectedShopIds, <String>{northwindMarinaId});

      cubit.shopSelectionToggled(northwindMarinaId);
      expect(cubit.state.selectedShopIds, isEmpty);
    });

    test('a Manager submits nothing however many shops are ticked', () async {
      final RetailerInviteStaffCubit cubit = build();
      cubit.roleChanged(RetailerStaffInvitationRole.salesStaff);
      await Future<void>.delayed(Duration.zero);
      cubit.shopSelectionToggled(northwindMarinaId);

      cubit.roleChanged(RetailerStaffInvitationRole.retailerManager);

      // The tick survives so switching back restores it, and is still not
      // submittable — the two facts the contract needs kept apart.
      expect(cubit.state.selectedShopIds, contains(northwindMarinaId));
      expect(cubit.state.submittableShopIds, isEmpty);
    });

    test('only ids the backend returned are submittable', () async {
      final RetailerInviteStaffCubit cubit = build();
      cubit.roleChanged(RetailerStaffInvitationRole.salesStaff);
      await Future<void>.delayed(Duration.zero);

      cubit.shopSelectionToggled(southgateCentralId); // another Retailer's shop

      expect(cubit.state.submittableShopIds, isEmpty);
    });
  });

  group('local validation', () {
    test('refuses Sales Staff with no shop and sends nothing', () async {
      final RetailerInviteStaffCubit cubit = build();
      cubit
        ..firstNameChanged('Priya')
        ..lastNameChanged('Raman')
        ..emailChanged('priya@example.com')
        ..roleChanged(RetailerStaffInvitationRole.salesStaff);
      await Future<void>.delayed(Duration.zero);

      await cubit.submit();

      expect(repository.sendCallCount, 0);
      expect(cubit.state.notice, RetailerInviteStaffNotice.checkTheForm);
      expect(
        cubit.state.problemFor(RetailerStaffInvitationField.shops),
        RetailerStaffInvitationProblem.shopsRequired,
      );
    });

    test('refuses a missing role and sends nothing', () async {
      final RetailerInviteStaffCubit cubit = build();
      cubit
        ..firstNameChanged('Priya')
        ..lastNameChanged('Raman')
        ..emailChanged('priya@example.com');

      await cubit.submit();

      expect(repository.sendCallCount, 0);
      expect(
        cubit.state.problemFor(RetailerStaffInvitationField.role),
        RetailerStaffInvitationProblem.missing,
      );
    });

    test('a message clears as soon as its field is corrected', () async {
      final RetailerInviteStaffCubit cubit = build();
      await cubit.submit();
      expect(
        cubit.state.problemFor(RetailerStaffInvitationField.email),
        isNotNull,
      );

      cubit.emailChanged('priya@example.com');

      expect(
        cubit.state.problemFor(RetailerStaffInvitationField.email),
        isNull,
      );
      // The stale form-level notice goes with it — it described a submission
      // that is no longer the one on screen.
      expect(cubit.state.notice, isNull);
    });
  });

  group('submission', () {
    test('SENT clears the form, keeps the notice and re-reads history', () async {
      final RetailerInviteStaffCubit cubit = build();
      await fillSalesStaff(cubit);

      await cubit.submit();

      expect(repository.sendCallCount, 1);
      expect(cubit.state.notice, RetailerInviteStaffNotice.sent);
      expect(cubit.state.firstName, isEmpty);
      expect(cubit.state.lastName, isEmpty);
      expect(cubit.state.email, isEmpty);
      expect(cubit.state.role, isNull);
      expect(cubit.state.selectedShopIds, isEmpty);
      expect(cubit.state.isSubmitting, isFalse);
      expect(rereadCalls, 1);
      // The options survive the reset: re-reading the estate would be a request
      // whose answer cannot have changed.
      expect(cubit.state.shops, hasLength(3));
      expect(cubit.state.historyRereadFailed, isFalse);
    });

    test('the request carries exactly what was on the form', () async {
      final RetailerInviteStaffCubit cubit = build();
      await fillSalesStaff(cubit);

      await cubit.submit();

      final RetailerStaffInvitationRequest sent =
          repository.sentRequests.single;
      expect(sent.firstName, 'Priya');
      expect(sent.lastName, 'Raman');
      expect(sent.email, 'priya@example.com');
      expect(sent.role, RetailerStaffInvitationRole.salesStaff);
      expect(sent.shopIds, <String>[northwindMarinaId]);
    });

    test('a Manager submission carries no shops', () async {
      final RetailerInviteStaffCubit cubit = build();
      cubit.roleChanged(RetailerStaffInvitationRole.salesStaff);
      await Future<void>.delayed(Duration.zero);
      cubit.shopSelectionToggled(northwindMarinaId);
      fillManager(cubit);

      await cubit.submit();

      expect(repository.sentRequests.single.shopIds, isEmpty);
      expect(
        repository.sentRequests.single.role,
        RetailerStaffInvitationRole.retailerManager,
      );
    });

    test('RESENT is a success that names the rotated link', () async {
      repository.sendResult = resentAnswer;
      final RetailerInviteStaffCubit cubit = build();
      fillManager(cubit);

      await cubit.submit();

      expect(cubit.state.notice, RetailerInviteStaffNotice.resent);
      expect(cubit.state.notice!.isSuccess, isTrue);
      expect(cubit.state.firstName, isEmpty);
      expect(rereadCalls, 1);
    });

    test(
      'the 202 partial success never claims failure and never resends',
      () async {
        repository.sendResult = unconfirmedAnswer;
        final RetailerInviteStaffCubit cubit = build();
        fillManager(cubit);

        await cubit.submit();

        expect(
          cubit.state.notice,
          RetailerInviteStaffNotice.deliveryUnconfirmed,
        );
        expect(cubit.state.notice!.isUnresolved, isTrue);
        expect(cubit.state.notice!.isSuccess, isFalse);
        // Exactly one write, and the form is emptied rather than left armed.
        expect(repository.sendCallCount, 1);
        expect(cubit.state.firstName, isEmpty);
        // The history is the only authority on what actually exists.
        expect(rereadCalls, 1);
      },
    );

    test('a definite delivery failure keeps every entered value', () async {
      repository.sendResult = deliveryFailedAnswer;
      final RetailerInviteStaffCubit cubit = build();
      fillManager(cubit);

      await cubit.submit();

      expect(cubit.state.notice, RetailerInviteStaffNotice.deliveryFailed);
      expect(cubit.state.notice!.preservesForm, isTrue);
      expect(cubit.state.firstName, 'Marco');
      expect(cubit.state.email, 'marco@example.com');
      expect(cubit.state.role, RetailerStaffInvitationRole.retailerManager);
      expect(cubit.state.isSubmitting, isFalse);
      // The invitation exists and its recorded failure is a row on the history.
      expect(rereadCalls, 1);
      // Nothing tried again on its own.
      expect(repository.sendCallCount, 1);
    });

    for (final (
          RetailerStaffInvitationCode code,
          RetailerInviteStaffNotice notice,
        )
        in <(RetailerStaffInvitationCode, RetailerInviteStaffNotice)>[
          (
            RetailerStaffInvitationCode.invalidRequest,
            RetailerInviteStaffNotice.invalidRequest,
          ),
          (
            RetailerStaffInvitationCode.invalidRoleShopCombination,
            RetailerInviteStaffNotice.invalidRoleShopCombination,
          ),
          (
            RetailerStaffInvitationCode.authRequired,
            RetailerInviteStaffNotice.signedOut,
          ),
          (
            RetailerStaffInvitationCode.accessDenied,
            RetailerInviteStaffNotice.accessDenied,
          ),
          (
            RetailerStaffInvitationCode.invitationConflict,
            RetailerInviteStaffNotice.invitationConflict,
          ),
          (
            RetailerStaffInvitationCode.retailerInactive,
            RetailerInviteStaffNotice.retailerInactive,
          ),
          (
            RetailerStaffInvitationCode.featureDisabled,
            RetailerInviteStaffNotice.featureDisabled,
          ),
          (
            RetailerStaffInvitationCode.notConfigured,
            RetailerInviteStaffNotice.notConfigured,
          ),
          (
            RetailerStaffInvitationCode.internalError,
            RetailerInviteStaffNotice.serviceFault,
          ),
          (
            RetailerStaffInvitationCode.methodNotAllowed,
            RetailerInviteStaffNotice.serviceFault,
          ),
          (
            // A NOT_SENT token this build has never seen: the generic case for
            // the recognised outcome.
            RetailerStaffInvitationCode.unrecognized,
            RetailerInviteStaffNotice.invalidRequest,
          ),
        ]) {
      test('${code.name} maps to its own notice and keeps the form', () async {
        repository.sendResult = notSentAnswer(code);
        final RetailerInviteStaffCubit cubit = build();
        fillManager(cubit);

        await cubit.submit();

        expect(cubit.state.notice, notice);
        expect(cubit.state.firstName, 'Marco');
        // Nothing reached the provider, so there is nothing new to re-read.
        expect(rereadCalls, 0);
      });
    }

    for (final (
          RetailerStaffInvitationTransportProblem problem,
          RetailerInviteStaffNotice notice,
          bool rereads,
          bool keepsForm,
        )
        in <
          (
            RetailerStaffInvitationTransportProblem,
            RetailerInviteStaffNotice,
            bool,
            bool,
          )
        >[
          (
            RetailerStaffInvitationTransportProblem.network,
            RetailerInviteStaffNotice.network,
            false,
            true,
          ),
          (
            RetailerStaffInvitationTransportProblem.signedOut,
            RetailerInviteStaffNotice.signedOut,
            false,
            true,
          ),
          (
            RetailerStaffInvitationTransportProblem.timeout,
            RetailerInviteStaffNotice.timedOut,
            true,
            false,
          ),
          (
            RetailerStaffInvitationTransportProblem.malformed,
            RetailerInviteStaffNotice.unreadableAnswer,
            true,
            false,
          ),
          (
            RetailerStaffInvitationTransportProblem.unexpected,
            RetailerInviteStaffNotice.unexpected,
            true,
            false,
          ),
        ]) {
      test(
        '${problem.name} is distinguished from every other failure',
        () async {
          repository.sendResult = RetailerStaffInvitationUnanswered(problem);
          final RetailerInviteStaffCubit cubit = build();
          fillManager(cubit);

          await cubit.submit();

          expect(cubit.state.notice, notice);
          expect(rereadCalls, rereads ? 1 : 0);
          expect(cubit.state.firstName, keepsForm ? 'Marco' : isEmpty);
          // Never twice, whatever went wrong.
          expect(repository.sendCallCount, 1);
        },
      );
    }

    test('a second submit while one is in flight is suppressed', () async {
      repository.manualSend = true;
      final RetailerInviteStaffCubit cubit = build();
      fillManager(cubit);

      unawaited(cubit.submit());
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isSubmitting, isTrue);

      unawaited(cubit.submit());
      unawaited(cubit.submit());
      await Future<void>.delayed(Duration.zero);

      // One invitation, not three.
      expect(repository.sendCallCount, 1);

      repository.completeSend();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.notice, RetailerInviteStaffNotice.sent);
    });

    test('typing is ignored while a submission is in flight', () async {
      repository.manualSend = true;
      final RetailerInviteStaffCubit cubit = build();
      fillManager(cubit);

      unawaited(cubit.submit());
      await Future<void>.delayed(Duration.zero);

      cubit.firstNameChanged('Someone else');

      expect(cubit.state.firstName, 'Marco');
      repository.completeSend();
    });
  });

  group('the canonical reread', () {
    test('a failed reread never restates the send as a failure', () async {
      rereadSucceeds = false;
      final RetailerInviteStaffCubit cubit = build();
      fillManager(cubit);

      await cubit.submit();

      // The send's own notice stands, unchanged.
      expect(cubit.state.notice, RetailerInviteStaffNotice.sent);
      expect(cubit.state.notice!.isSuccess, isTrue);
      // And the stale history is reported separately.
      expect(cubit.state.historyRereadFailed, isTrue);
      // Nothing was sent again to resolve it.
      expect(repository.sendCallCount, 1);
    });

    test('a successful reread leaves no stale-history notice', () async {
      final RetailerInviteStaffCubit cubit = build();
      fillManager(cubit);

      await cubit.submit();

      expect(cubit.state.historyRereadFailed, isFalse);
    });

    test('a reread landing after a session change is ignored', () async {
      manualReread = Completer<bool>();
      final RetailerInviteStaffCubit cubit = build();
      fillManager(cubit);

      unawaited(cubit.submit());
      await Future<void>.delayed(Duration.zero);
      expect(rereadCalls, 1);

      cubit.clear();
      manualReread!.complete(false);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.historyRereadFailed, isFalse);
      expect(cubit.state.notice, isNull);
    });
  });

  group('session isolation', () {
    test('clear drops every value, the options and the result', () async {
      final RetailerInviteStaffCubit cubit = build();
      await fillSalesStaff(cubit);
      await cubit.submit();

      cubit.clear();

      expect(cubit.state.firstName, isEmpty);
      expect(cubit.state.lastName, isEmpty);
      expect(cubit.state.email, isEmpty);
      expect(cubit.state.shops, isNull);
      expect(cubit.state.shopsPhase, RetailerInviteShopsPhase.initial);
      expect(cubit.state.shopsProblem, isNull);
      expect(cubit.state.notice, isNull);
      expect(cubit.state.historyRereadFailed, isFalse);
      expect(cubit.state.fieldProblems, isEmpty);
      expect(cubit.state.selectedShopIds, isEmpty);
      expect(cubit.state.role, isNull);
      expect(cubit.state.isSubmitting, isFalse);
    });

    test('clear advances the form revision so the controllers follow', () {
      // The text boxes live in the widget and resync only when this changes.
      final RetailerInviteStaffCubit cubit = build();
      final int before = cubit.state.formRevision;

      cubit.clear();

      expect(cubit.state.formRevision, greaterThan(before));
    });

    test('clear advances the request token', () async {
      final RetailerInviteStaffCubit cubit = build();
      final int before = cubit.requestToken;

      cubit.clear();

      expect(cubit.requestToken, greaterThan(before));
    });

    test('a send answered after a session change cannot land', () async {
      repository.manualSend = true;
      final RetailerInviteStaffCubit cubit = build();
      fillManager(cubit);

      unawaited(cubit.submit());
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isSubmitting, isTrue);

      // The session ends while the write is in flight.
      cubit.clear();
      expect(cubit.state.isSubmitting, isFalse);

      repository.completeSend();
      await Future<void>.delayed(Duration.zero);

      // No previous session's success on the new session's screen.
      expect(cubit.state.notice, isNull);
      expect(cubit.state.firstName, isEmpty);
      expect(cubit.state.role, isNull);
      // And no reread issued on the new identity's behalf either.
      expect(rereadCalls, 0);
    });

    test('a shop read answered after a session change cannot land', () async {
      repository.manualShops = true;
      final RetailerInviteStaffCubit cubit = build();

      cubit.roleChanged(RetailerStaffInvitationRole.salesStaff);
      await Future<void>.delayed(Duration.zero);

      cubit.clear();
      repository.completeShops(
        RetailerAssignableShopsLoaded(otherAssignableShops),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.shops, isNull);
      expect(cubit.state.shopsPhase, RetailerInviteShopsPhase.initial);
    });

    test('one Retailer\'s estate never reaches the next session', () async {
      repository.manualShops = true;
      final RetailerInviteStaffCubit cubit = build();

      cubit.roleChanged(RetailerStaffInvitationRole.salesStaff);
      await Future<void>.delayed(Duration.zero);
      repository.completeShops();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.shops, hasLength(3));

      cubit.clear();

      // Retailer B signs in and chooses Sales Staff.
      repository.nextShops = otherAssignableShops;
      cubit.roleChanged(RetailerStaffInvitationRole.salesStaff);
      await Future<void>.delayed(Duration.zero);
      repository.completeShopsAt(repository.pendingShopCount - 1);
      await Future<void>.delayed(Duration.zero);

      expect(
        cubit.state.shops!.map((RetailerAssignableShop s) => s.id).toList(),
        <String>[southgateCentralId],
      );
    });
  });
}
