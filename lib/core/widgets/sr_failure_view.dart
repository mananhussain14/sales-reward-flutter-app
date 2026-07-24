import 'package:flutter/material.dart';

import '../design/design.dart';
import '../errors/failure.dart';
import 'sr_button.dart';
import 'sr_empty_state.dart';

/// The shared failure state.
///
/// Turns a [Failure] into copy, a tone, and (where it helps) a retry — and does
/// nothing else. Three properties inherited from the web layer make this widget
/// the right place for that translation:
///
/// * **The wording is fixed here, per discriminant.** No caller can accidentally
///   render a backend message, because no backend message reaches this widget.
/// * **A denial never reads as "not found".** `42501` is deliberately overloaded
///   in SQL so that it is not an existence oracle; splitting it into friendlier
///   sub-cases in the UI would undo that.
/// * **An outage never reads as a denial.** [UnavailableFailure] offers a retry
///   and says nothing about permission.
///
/// [DeniedFailure] renders here as an inline state for a failed operation. A
/// caller whose *entire screen* is refused should use `SrAccessDeniedView`,
/// which is the full-screen equivalent with a sign-out affordance.
class SrFailureView extends StatelessWidget {
  const SrFailureView({super.key, required this.failure, this.onRetry});

  final Failure failure;

  /// Shown only where retrying could plausibly change the answer.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final _FailureCopy copy = _copyFor(failure);

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

  static _FailureCopy _copyFor(Failure failure) => switch (failure) {
    DeniedFailure() => const _FailureCopy(
      icon: Icons.shield_outlined,
      tone: SrTone.amber,
      title: 'Not available to this account',
      // Says nothing about whether the target exists. Matches the web's
      // single generic denial for every 42501.
      description:
          'This account does not have access to this action. If you think that '
          'is wrong, contact whoever manages your access.',
      retryable: false,
    ),
    UnauthenticatedFailure() => const _FailureCopy(
      icon: Icons.lock_outline_rounded,
      tone: SrTone.slate,
      title: 'Your session has ended',
      description: 'Sign in again to continue.',
      retryable: false,
    ),
    DuplicateFailure() => const _FailureCopy(
      icon: Icons.content_copy_outlined,
      tone: SrTone.amber,
      title: 'That already exists',
      description: 'Change the details and try again.',
      retryable: false,
    ),
    InvalidFailure() => const _FailureCopy(
      icon: Icons.error_outline_rounded,
      tone: SrTone.amber,
      title: 'Check the details',
      description: 'Something in this request was rejected. Review and resend.',
      retryable: false,
    ),
    NotReadyFailure() => const _FailureCopy(
      icon: Icons.pause_circle_outline_rounded,
      tone: SrTone.slate,
      title: 'Not ready yet',
      description:
          'This cannot be completed while the related record is inactive.',
      retryable: false,
    ),
    UnavailableFailure() => const _FailureCopy(
      icon: Icons.cloud_off_rounded,
      tone: SrTone.slate,
      title: 'Could not load this',
      // Deliberately reason-free, and deliberately not a denial.
      description: 'Check your connection and try again.',
      retryable: true,
    ),
    NotImplementedFailure() => const _FailureCopy(
      icon: Icons.construction_rounded,
      tone: SrTone.indigo,
      title: 'Not built yet',
      description: 'This part of the app is not connected to the backend yet.',
      retryable: false,
    ),
  };
}

class _FailureCopy {
  const _FailureCopy({
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
