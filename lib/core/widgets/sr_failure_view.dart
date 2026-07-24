import 'package:flutter/material.dart';

import '../design/design.dart';
import '../errors/failure.dart';
import 'sr_button.dart';
import 'sr_empty_state.dart';

/// The shared failure state.
///
/// Turns a [Failure] into copy, a tone and — only where retrying could change
/// the answer — a retry. It does nothing else, and it is the only place that
/// translation happens.
///
/// Three properties are inherited from the web layer and are the reason this is
/// centralised:
///
/// * **The wording is fixed here, per discriminant.** No caller can render a
///   backend message, because no backend message ever reaches this widget.
/// * **A denial never reads as "not found".** `42501` is deliberately
///   overloaded in SQL so it is not an existence oracle; splitting it into
///   friendlier sub-cases would undo that.
/// * **An outage never reads as a denial.** [UnavailableFailure] offers a retry
///   and says nothing about permission. The role-flow map calls this out
///   directly: telling a user they lack access when the database was merely
///   unreachable is both wrong and alarming.
///
/// A whole screen that is refused should use `SrAccessDeniedView` instead — the
/// full-screen surface with a sign-out affordance.
class SrFailureView extends StatelessWidget {
  const SrFailureView({super.key, required this.failure, this.onRetry});

  final Failure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final SrFailureCopy copy = copyFor(failure);

    return SrEmptyState(
      icon: copy.icon,
      tone: copy.tone,
      title: copy.title,
      description: copy.description,
      action: copy.retryable && onRetry != null
          ? SrButton(
              label: 'Try again',
              variant: SrButtonVariant.outline,
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            )
          : null,
    );
  }

  /// The copy for [failure]. Exposed so tests can assert the mapping directly.
  static SrFailureCopy copyFor(Failure failure) => switch (failure) {
    DeniedFailure() => const SrFailureCopy(
      icon: Icons.shield_outlined,
      tone: SrTone.amber,
      title: 'Not available to this account',
      // Says nothing about whether the target exists, matching the web's single
      // generic denial for every 42501.
      description:
          'This account does not have access to this action. If you think that '
          'is wrong, contact whoever manages your access.',
      retryable: false,
    ),
    UnauthenticatedFailure() => const SrFailureCopy(
      icon: Icons.lock_outline_rounded,
      tone: SrTone.slate,
      title: 'Your session has ended',
      description: 'Sign in again to continue.',
      retryable: false,
    ),
    DuplicateFailure() => const SrFailureCopy(
      icon: Icons.copy_all_outlined,
      tone: SrTone.amber,
      title: 'That already exists',
      description: 'Change the details and try again.',
      retryable: false,
    ),
    InvalidFailure() => const SrFailureCopy(
      icon: Icons.error_outline_rounded,
      tone: SrTone.amber,
      title: 'Check the details',
      description: 'Something in this request was rejected. Review and resend.',
      retryable: false,
    ),
    NotReadyFailure() => const SrFailureCopy(
      icon: Icons.pause_circle_outline_rounded,
      tone: SrTone.slate,
      title: 'Not ready yet',
      description:
          'This cannot be completed while the related record is inactive.',
      retryable: false,
    ),
    UnavailableFailure() => const SrFailureCopy(
      icon: Icons.cloud_off_rounded,
      tone: SrTone.slate,
      title: 'Could not load this',
      // Deliberately reason-free, and deliberately not a denial.
      description: 'Check your connection and try again.',
      retryable: true,
    ),
    NotImplementedFailure() => const SrFailureCopy(
      icon: Icons.construction_rounded,
      tone: SrTone.indigo,
      title: 'Not built yet',
      description: 'This part of the app is not connected to the backend yet.',
      retryable: false,
    ),
  };
}

/// The fixed copy for one failure discriminant.
class SrFailureCopy {
  const SrFailureCopy({
    required this.icon,
    required this.tone,
    required this.title,
    required this.description,
    required this.retryable,
  });

  final IconData icon;
  final SrTone tone;
  final String title;
  final String description;
  final bool retryable;
}
