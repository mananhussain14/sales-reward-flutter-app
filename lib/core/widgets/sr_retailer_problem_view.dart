import 'package:flutter/material.dart';

import '../design/design.dart';
import '../errors/retailer_read_problem.dart';
import 'sr_button.dart';
import 'sr_empty_state.dart';

/// The fixed copy for one [RetailerReadProblem].
final class RetailerProblemCopy {
  const RetailerProblemCopy({
    required this.title,
    required this.body,
    required this.icon,
    required this.tone,
    required this.retryable,
  });

  final String title;
  final String body;
  final IconData icon;
  final SrTone tone;

  /// Whether a second identical call could produce a different answer.
  final bool retryable;
}

/// The shared Retailer read-failure state.
///
/// Turns a [RetailerReadProblem] into copy, a tone and — only where retrying
/// could change the answer — a retry. It does nothing else, and it is the only
/// place that translation happens for the Retailer portal.
///
/// Four properties are the reason this is centralised:
///
/// * **The wording is fixed here, per discriminant.** No caller can render a
///   backend message, because no backend message ever reaches this widget. A
///   SQLSTATE, a PostgREST body, a stack trace, a token or a UUID has no path to
///   the screen through it.
/// * **A denial never reads as "not found".** `42501` is deliberately overloaded
///   in SQL so it is not an existence oracle; splitting it into friendlier
///   sub-cases would undo that.
/// * **An outage never reads as a denial**, and a denial never offers a retry
///   that could not possibly work.
/// * **Only the two connection-shaped problems mention the connection.** Telling
///   someone to check a connection that is working sends them to fix something
///   that was never broken — the whole reason this taxonomy exists rather than
///   the shared `Failure` union.
class SrRetailerProblemView extends StatelessWidget {
  const SrRetailerProblemView({super.key, required this.problem, this.onRetry});

  final RetailerReadProblem problem;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final RetailerProblemCopy copy = copyFor(problem);

    return SrEmptyState(
      icon: copy.icon,
      tone: copy.tone,
      title: copy.title,
      description: copy.body,
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

  /// The copy for [problem]. Exposed so tests can assert the mapping directly.
  ///
  /// The mapping is **one-to-one and total**, so widening the problem domain
  /// later cannot quietly collapse a new reason into an existing message.
  static RetailerProblemCopy copyFor(
    RetailerReadProblem problem,
  ) => switch (problem) {
    RetailerReadProblem.denied => const RetailerProblemCopy(
      title: 'Not available to this account',
      // Says nothing about whether anything exists, preserving the backend's
      // single generic denial.
      body:
          'This account does not have access to this part of the Retailer '
          'portal. If you think that is wrong, contact whoever manages '
          'your access.',
      icon: Icons.shield_outlined,
      tone: SrTone.amber,
      retryable: false,
    ),
    RetailerReadProblem.signedOut => const RetailerProblemCopy(
      title: 'Your session has ended',
      body: 'Sign in again to continue.',
      icon: Icons.lock_outline_rounded,
      tone: SrTone.slate,
      retryable: false,
    ),
    RetailerReadProblem.malformed => const RetailerProblemCopy(
      title: 'Could not read this',
      // Never "you have none of these". An unreadable answer is not an empty
      // one.
      body:
          'SalesReward sent something this version of the app could not '
          'read. Updating the app may help.',
      icon: Icons.report_gmailerrorred_rounded,
      tone: SrTone.amber,
      retryable: true,
    ),
    RetailerReadProblem.network => const RetailerProblemCopy(
      title: 'Could not reach SalesReward',
      body: 'Check your connection and try again.',
      icon: Icons.cloud_off_rounded,
      tone: SrTone.slate,
      retryable: true,
    ),
    RetailerReadProblem.timeout => const RetailerProblemCopy(
      title: 'This took too long',
      body: 'Loading timed out. Check your connection and try again.',
      icon: Icons.hourglass_empty_rounded,
      tone: SrTone.slate,
      retryable: true,
    ),
    RetailerReadProblem.unexpected => const RetailerProblemCopy(
      title: 'Something went wrong',
      // Deliberately says nothing about the network: an unrecognised fault
      // is a bug in this app or the SDK, not a statement about the user's
      // connection.
      body: 'This could not be loaded. Try again.',
      icon: Icons.error_outline_rounded,
      tone: SrTone.amber,
      retryable: true,
    ),
  };
}
