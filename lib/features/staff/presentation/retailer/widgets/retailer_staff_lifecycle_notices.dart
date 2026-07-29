import 'package:flutter/material.dart';

import '../../../../../core/widgets/widgets.dart';
import '../../../domain/repositories/retailer_staff_lifecycle_repository.dart';
import '../cubit/retailer_staff_lifecycle_cubit.dart';
import 'retailer_staff_lifecycle_copy.dart';

/// The acknowledgement for a committed lifecycle change, shown beside the card
/// it changed.
///
/// Every wording is chosen from the status the **database confirmed**, never from
/// the one that was requested — and the two no-op members say plainly that
/// nothing was written, because "you did that" and "somebody already had" are
/// different things to an Owner and collapsing them would claim an event that
/// never happened.
///
/// The `unconfirmed` notice is a success in a quieter voice. No error means the
/// transaction committed, so it never says the change was lost; it says it could
/// not be confirmed from the response and points at the canonical roster, which
/// is the authority either way. It deliberately offers no retry.
class RetailerStaffLifecycleNoticeAlert extends StatelessWidget {
  const RetailerStaffLifecycleNoticeAlert({super.key, required this.notice});

  final RetailerStaffLifecycleNotice notice;

  @override
  Widget build(BuildContext context) {
    final SrAlertTone tone = switch (notice) {
      RetailerStaffLifecycleNotice.deactivated ||
      RetailerStaffLifecycleNotice.reactivated => SrAlertTone.success,
      RetailerStaffLifecycleNotice.alreadyInactive ||
      RetailerStaffLifecycleNotice.alreadyActive ||
      RetailerStaffLifecycleNotice.unconfirmed => SrAlertTone.info,
    };

    return SrAlert(
      tone: tone,
      title: RetailerStaffLifecycleCopy.noticeTitle(notice),
      message: RetailerStaffLifecycleCopy.noticeBody(notice),
    );
  }
}

/// A lifecycle refusal, worded from the discriminant alone.
///
/// Every sentence comes from [RetailerStaffLifecycleCopy]. **No backend text
/// reaches this widget**: it is handed a
/// [RetailerStaffLifecycleProblem], which is an enum with no field a Postgres
/// message, table name, constraint name, function name, role code, permission
/// code, SQLSTATE or identifier could occupy.
///
/// The mapping is deliberately coarse where the backend is coarse.
/// [RetailerStaffLifecycleProblem.denied] is **one** wording for eleven causes —
/// among them an Owner target, a self target, a multi-role target, an invited or
/// suspended target, and another Retailer's membership. SQL refuses all of them
/// with the same code and the same message, precisely so that sweeping membership
/// ids reveals neither which exist nor whose they are, and a client that told them
/// apart would hand that oracle back.
///
/// [RetailerStaffLifecycleProblem.timeout] and
/// [RetailerStaffLifecycleProblem.unexpected] are the two genuinely unresolved
/// outcomes: the write may have committed after this device stopped waiting. Both
/// say so and point at the roster rather than at the button, and nothing retries.
class RetailerStaffLifecycleProblemAlert extends StatelessWidget {
  const RetailerStaffLifecycleProblemAlert({super.key, required this.problem});

  final RetailerStaffLifecycleProblem problem;

  @override
  Widget build(BuildContext context) {
    // The two unresolved outcomes are a warning rather than an error: nothing is
    // known to have failed, and colouring them as a failure would tell an Owner
    // the change did not happen when it may well have.
    final SrAlertTone tone = switch (problem) {
      RetailerStaffLifecycleProblem.timeout ||
      RetailerStaffLifecycleProblem.unexpected => SrAlertTone.warning,
      RetailerStaffLifecycleProblem.denied ||
      RetailerStaffLifecycleProblem.invalidStatus ||
      RetailerStaffLifecycleProblem.retailerUnavailable ||
      RetailerStaffLifecycleProblem.malformedRequest ||
      RetailerStaffLifecycleProblem.signedOut ||
      RetailerStaffLifecycleProblem.network => SrAlertTone.error,
    };

    return SrAlert(
      tone: tone,
      title: RetailerStaffLifecycleCopy.problemTitle(problem),
      message: RetailerStaffLifecycleCopy.problemBody(problem),
    );
  }
}
