import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/errors/failure.dart';
import '../../../domain/entities/receipt_submission.dart';
import '../../../domain/repositories/receipt_repository.dart';
import '../../../domain/repositories/receipt_result.dart';

part 'receipt_history_state.dart';

/// The caller's own receipt submissions.
///
/// Backed by exactly one call to `public.list_my_receipt_submissions()`, which
/// takes **zero arguments** and filters on both `submitted_by_profile_id =
/// auth.uid()` and the resolved Retailer. There is no page parameter, no filter
/// and no id to pass — so nothing in this app can widen what comes back.
///
/// ## Why it lives beside the submit screen rather than inside it
///
/// The history is what settles an unconfirmed submission. After a transport
/// failure the client cannot know whether the receipt landed, and the *only*
/// honest way to find out is to ask the backend what exists. Keeping the list in
/// its own cubit, shared by both tabs, means that answer is one refresh away
/// from either screen and is never a second, divergent copy.
final class ReceiptHistoryCubit extends Cubit<ReceiptHistoryState> {
  ReceiptHistoryCubit(this._repository) : super(const ReceiptHistoryState());

  final ReceiptRepository _repository;

  /// Reads the history, showing the full loading state.
  Future<void> load() => _fetch(showLoading: true);

  /// Re-reads the history in place.
  ///
  /// Deliberately does not blank the list: a refresh after a submission should
  /// add a row, not make the screen flash empty and fill in again.
  Future<void> refresh() => _fetch(showLoading: state.submissions.isEmpty);

  Future<void> _fetch({required bool showLoading}) async {
    if (state.isRefreshing) {
      return;
    }

    emit(
      state.copyWith(
        phase: showLoading
            ? ReceiptHistoryPhase.loading
            : ReceiptHistoryPhase.ready,
        isRefreshing: true,
        clearFailure: true,
      ),
    );

    final ReceiptResult<List<ReceiptSubmission>> result = await _repository
        .submissions();

    if (isClosed) {
      return;
    }

    switch (result) {
      case ReceiptReadSuccess<List<ReceiptSubmission>>(
        :final List<ReceiptSubmission> value,
      ):
        emit(
          ReceiptHistoryState(
            phase: ReceiptHistoryPhase.ready,
            submissions: value,
          ),
        );

      case ReceiptReadFailure<List<ReceiptSubmission>>(:final Failure failure):
        emit(
          state.copyWith(
            phase: ReceiptHistoryPhase.failed,
            failure: failure,
            isRefreshing: false,
            // The rows already on screen are still the last thing the backend
            // said. Discarding them because a refresh failed would replace real
            // history with an empty list.
          ),
        );
    }
  }

  /// Drops every submission held in memory.
  ///
  /// Called when the signed-in person changes, so one person's receipt history
  /// can never be visible to the next.
  void clear() => emit(const ReceiptHistoryState());
}
