import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../features/auth/domain/entities/portal_context.dart';
import '../../../features/auth/domain/entities/portal_kind.dart';
import '../../../features/auth/presentation/bloc/session_bloc.dart';
import '../../../features/receipts/domain/repositories/receipt_repository.dart';
import '../../../features/receipts/domain/services/receipt_image_source.dart';
import '../../../features/receipts/presentation/sales_staff/cubit/receipt_history_cubit.dart';
import '../../../features/receipts/presentation/sales_staff/cubit/receipt_submission_cubit.dart';
import '../base/role_shell_scaffold.dart';
import 'bloc/sales_staff_shell_bloc.dart';

/// The Sales Staff application shell.
///
/// The narrowest shell in the product: two destinations, bottom navigation, and
/// nothing borrowed from any other role.
///
/// ## Why the receipt cubits are provided here rather than per page
///
/// Both tabs read the same submission history, and the submit screen refreshes
/// it after every settled attempt. Providing the history cubit once, above both,
/// means there is one list rather than two that can disagree — so the submit
/// screen's "recent submissions" section and the History tab are guaranteed to
/// show the same rows.
///
/// ## Session isolation is enforced, not inferred from the widget lifetime
///
/// The obvious argument is that the router sends every `/sales-staff` route away
/// when the session changes, so the subtree unmounts and takes both cubits with
/// it. That argument is **not sound**, and a test proves it: a user switch
/// emits `SessionInitial` and then `SessionActive` for the new person within a
/// single microtask drain, so no frame ever renders the intermediate state, the
/// route match list never actually leaves `/sales-staff/submit`, and the element
/// — along with the previous person's chosen receipt image — survives.
///
/// [_SessionIsolation] closes that gap by listening to [SessionBloc] directly.
/// A listener runs on every emitted state whether or not a frame was built, so
/// the moment the session stops being *this* person's, both cubits are cleared:
/// the shops, the products, the history and the bytes of any chosen receipt.
/// When a new Sales Staff session settles, both reload from scratch.
class SalesStaffShell extends StatelessWidget {
  const SalesStaffShell({
    super.key,
    required this.child,
    required this.location,
    required this.portalContext,
  });

  final Widget child;
  final String location;
  final PortalContext portalContext;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReceiptHistoryCubit>(
      create: (BuildContext providerContext) =>
          ReceiptHistoryCubit(providerContext.read<ReceiptRepository>())
            ..load(),
      // Nested rather than a sibling inside one MultiBlocProvider: the
      // submission cubit refreshes the history after every settled attempt, so
      // it has to be able to read it while it is being constructed.
      child: Builder(
        builder: (BuildContext historyContext) {
          return BlocProvider<ReceiptSubmissionCubit>(
            create: (BuildContext providerContext) => ReceiptSubmissionCubit(
              repository: providerContext.read<ReceiptRepository>(),
              imageSource: providerContext.read<ReceiptImageSource>(),
              onSubmissionSettled: historyContext
                  .read<ReceiptHistoryCubit>()
                  .refresh,
            )..load(),
            child: BlocProvider<SalesStaffShellBloc>(
              create: (_) => SalesStaffShellBloc(),
              child: _SessionIsolation(
                child: RoleShellScaffold<SalesStaffShellBloc>(
                  location: location,
                  portalContext: portalContext,
                  child: child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Drops every piece of private receipt data the moment the session stops being
/// this person's, and reloads when a new Sales Staff session settles.
///
/// A [BlocListener] rather than a `BlocBuilder`, because the guarantee must not
/// depend on a frame being built: a user switch can emit `SessionInitial` and
/// the next person's `SessionActive` inside one microtask drain, and nothing
/// would ever paint in between.
class _SessionIsolation extends StatelessWidget {
  const _SessionIsolation({required this.child});

  final Widget child;

  static bool _isSalesStaff(SessionState state) =>
      state is SessionActive &&
      state.portalContext.portalKind == PortalKind.salesStaff;

  @override
  Widget build(BuildContext context) {
    return BlocListener<SessionBloc, SessionState>(
      listenWhen: (SessionState previous, SessionState current) =>
          _isSalesStaff(previous) != _isSalesStaff(current),
      listener: (BuildContext context, SessionState state) {
        final ReceiptSubmissionCubit submission = context
            .read<ReceiptSubmissionCubit>();
        final ReceiptHistoryCubit history = context.read<ReceiptHistoryCubit>();

        if (_isSalesStaff(state)) {
          // A new Sales Staff session. Everything is read again from the
          // backend under the new caller's own identity.
          submission.load();
          history.load();
          return;
        }

        submission.clear();
        history.clear();
      },
      child: child,
    );
  }
}
