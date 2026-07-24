import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_submission.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_result.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/cubit/receipt_history_cubit.dart';

import '../../support/receipt_fakes.dart';

void main() {
  late FakeReceiptRepository repository;

  ReceiptHistoryCubit build() => ReceiptHistoryCubit(repository);

  ReceiptSubmission rowWithId(String id) => ReceiptSubmission(
    submissionId: id,
    shopName: 'Marina Mall',
    status: submittedRow.status,
    originalFileName: 'receipt.png',
    mimeType: 'image/png',
    fileSizeBytes: 100,
    createdAt: DateTime.utc(2026, 7, 25),
  );

  setUp(() {
    repository = FakeReceiptRepository();
  });

  test('starts empty and reads nothing until asked', () {
    final ReceiptHistoryCubit cubit = build();

    expect(cubit.state.phase, ReceiptHistoryPhase.initial);
    expect(repository.submissionsCallCount, 0);
  });

  test('loads with zero arguments', () async {
    repository.submissionsResult = ReceiptReadSuccess<List<ReceiptSubmission>>(
      <ReceiptSubmission>[submittedRow],
    );

    final ReceiptHistoryCubit cubit = build();
    await cubit.load();

    expect(repository.submissionsCallCount, 1);
    expect(cubit.state.phase, ReceiptHistoryPhase.ready);
    expect(cubit.state.submissions, <ReceiptSubmission>[submittedRow]);
    expect(cubit.state.isRefreshing, isFalse);
  });

  test('an empty history is a real answer, not a failure', () async {
    final ReceiptHistoryCubit cubit = build();
    await cubit.load();

    expect(cubit.state.phase, ReceiptHistoryPhase.ready);
    expect(cubit.state.isEmpty, isTrue);
    expect(cubit.state.failure, isNull);
  });

  test('a failure is classified, never rendered as an empty list', () async {
    repository.submissionsResult = unavailableRead<List<ReceiptSubmission>>();

    final ReceiptHistoryCubit cubit = build();
    await cubit.load();

    expect(cubit.state.phase, ReceiptHistoryPhase.failed);
    expect(cubit.state.failure, isA<UnavailableFailure>());
    expect(cubit.state.isEmpty, isFalse);
  });

  test('a denial stays a denial', () async {
    repository.submissionsResult = deniedRead<List<ReceiptSubmission>>();

    final ReceiptHistoryCubit cubit = build();
    await cubit.load();

    expect(cubit.state.failure, isA<DeniedFailure>());
  });

  test('a refresh replaces the rows with what the backend now says', () async {
    repository.submissionsResult = ReceiptReadSuccess<List<ReceiptSubmission>>(
      <ReceiptSubmission>[submittedRow],
    );
    final ReceiptHistoryCubit cubit = build();
    await cubit.load();

    repository.submissionsResult = ReceiptReadSuccess<List<ReceiptSubmission>>(
      <ReceiptSubmission>[
        submittedRow,
        rowWithId('11111111-1111-1111-1111-111111111111'),
      ],
    );
    await cubit.refresh();

    expect(repository.submissionsCallCount, 2);
    expect(cubit.state.submissions, hasLength(2));
  });

  test('a failed refresh keeps the rows already on screen', () async {
    repository.submissionsResult = ReceiptReadSuccess<List<ReceiptSubmission>>(
      <ReceiptSubmission>[submittedRow],
    );
    final ReceiptHistoryCubit cubit = build();
    await cubit.load();

    repository.submissionsResult = unavailableRead<List<ReceiptSubmission>>();
    await cubit.refresh();

    // The rows are still the last thing the backend actually said. Blanking
    // them because a refresh failed would replace real history with nothing.
    expect(cubit.state.submissions, <ReceiptSubmission>[submittedRow]);
    expect(cubit.state.phase, ReceiptHistoryPhase.failed);
  });

  test(
    'take returns the newest few, in the order the RPC returned them',
    () async {
      repository.submissionsResult =
          ReceiptReadSuccess<List<ReceiptSubmission>>(<ReceiptSubmission>[
            submittedRow,
            rowWithId('11111111-1111-1111-1111-111111111111'),
            rowWithId('22222222-2222-2222-2222-222222222222'),
            rowWithId('33333333-3333-3333-3333-333333333333'),
          ]);
      final ReceiptHistoryCubit cubit = build();
      await cubit.load();

      expect(cubit.state.take(3), hasLength(3));
      expect(cubit.state.take(3).first, submittedRow);
      expect(cubit.state.take(10), hasLength(4));
    },
  );

  test('clear drops the whole list', () async {
    repository.submissionsResult = ReceiptReadSuccess<List<ReceiptSubmission>>(
      <ReceiptSubmission>[submittedRow],
    );
    final ReceiptHistoryCubit cubit = build();
    await cubit.load();

    cubit.clear();

    expect(cubit.state.submissions, isEmpty);
    expect(cubit.state.phase, ReceiptHistoryPhase.initial);
  });
}
