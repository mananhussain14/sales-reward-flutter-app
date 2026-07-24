part of 'receipt_history_cubit.dart';

/// Where the history read has reached.
enum ReceiptHistoryPhase {
  /// Nothing has been read yet.
  initial,

  /// The first read is in flight.
  loading,

  /// A list is on screen. It may be empty — which is a real answer, not a
  /// failure, and certainly not a denial.
  ready,

  /// The read did not produce an answer.
  failed,
}

/// The submission history.
final class ReceiptHistoryState extends Equatable {
  const ReceiptHistoryState({
    this.phase = ReceiptHistoryPhase.initial,
    this.submissions = const <ReceiptSubmission>[],
    this.failure,
    this.isRefreshing = false,
  });

  final ReceiptHistoryPhase phase;

  /// Newest first — the RPC orders by `created_at desc, id desc`, and this list
  /// preserves that order rather than re-sorting it.
  final List<ReceiptSubmission> submissions;

  /// Why the read failed. A discriminant; never the backend's own message.
  final Failure? failure;

  /// True while a read is in flight, including a silent refresh over an
  /// already-populated list.
  final bool isRefreshing;

  /// A real, successful "you have not submitted anything yet".
  bool get isEmpty => phase == ReceiptHistoryPhase.ready && submissions.isEmpty;

  /// The newest few, for the compact section on the submit screen.
  List<ReceiptSubmission> take(int count) =>
      submissions.take(count).toList(growable: false);

  ReceiptHistoryState copyWith({
    ReceiptHistoryPhase? phase,
    List<ReceiptSubmission>? submissions,
    Failure? failure,
    bool clearFailure = false,
    bool? isRefreshing,
  }) {
    return ReceiptHistoryState(
      phase: phase ?? this.phase,
      submissions: submissions ?? this.submissions,
      failure: clearFailure ? null : (failure ?? this.failure),
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    phase,
    submissions,
    failure,
    isRefreshing,
  ];
}
