import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/features/receipts/domain/entities/extracted_value.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_civil_date.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_civil_time.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_entry_mode.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_field.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_input.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_outcome.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_confirmation_result.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_currency_minor_unit.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_line_item.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_problem.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_request_outcome.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_request_result.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_status.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_extraction_warning_code.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_image_preview.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_extraction_result.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/cubit/receipt_review_cubit.dart';

import '../../support/receipt_review_fakes.dart';

/// The review state machine, over fakes and a controllable clock.
///
/// The delay is injected and completes immediately, so a `QUEUED → PROCESSING →
/// SUCCEEDED` sequence runs in microtasks rather than in three real seconds.
/// Nothing here touches a socket, a timer or a platform channel.
void main() {
  Future<void> instant(Duration duration) async {}

  /// Drains the microtask and event queues until the poll loop has finished.
  ///
  /// The loop is deliberately not awaited by `start()` — a screen must render
  /// while an attempt is in flight, not block on it — so a test that wants to
  /// observe the loop's end has to let the queue empty first.
  Future<void> settle([int turns = 400]) async {
    for (int i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  ReceiptReviewCubit build(
    FakeReceiptExtractionRepository repository, {
    int maxPolls = 40,
  }) {
    return ReceiptReviewCubit(
      repository: repository,
      submissionId: reviewSubmissionId,
      maxPolls: maxPolls,
      delay: instant,
    );
  }

  group('opening the review', () {
    test('asks for an extraction exactly once, for that receipt only', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      // A rebuilt element calls start() again. It must not consume a second of
      // the three attempts this receipt gets in its lifetime.
      await cubit.start();
      await cubit.start();

      expect(repository.requestedIds, <String>[reviewSubmissionId]);
      await cubit.close();
    });

    test(
      'an id that cannot be a receipt id costs no round trip at all',
      () async {
        final FakeReceiptExtractionRepository repository =
            FakeReceiptExtractionRepository();
        final ReceiptReviewCubit cubit = ReceiptReviewCubit(
          repository: repository,
          submissionId: 'not-a-uuid',
          delay: instant,
        );

        await cubit.start();

        // Above all, the MUTATING call was never made.
        expect(repository.requestedIds, isEmpty);
        expect(repository.previewIds, isEmpty);
        expect(cubit.state.phase, ReceiptReviewPhase.blocked);
        // The same answer every unreadable receipt gets — never a distinguishable
        // one, which would confirm what does and does not exist.
        expect(cubit.state.problem, isA<ExtractionNotFoundProblem>());
        await cubit.close();
      },
    );

    test('a stored reading is ready to review', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();

      expect(cubit.state.phase, ReceiptReviewPhase.succeeded);
      expect(cubit.state.hasReading, isTrue);
      expect(cubit.state.canEdit, isTrue);
      expect(cubit.state.lineItems, hasLength(2));
      await cubit.close();
    });
  });

  group('polling', () {
    test('runs QUEUED → PROCESSING → SUCCEEDED and then stops', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            requestResults:
                <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                  ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                    requestResult(
                      outcome: ReceiptExtractionRequestOutcome.queued,
                      extraction: openExtraction(),
                    ),
                  ),
                ],
            extractionResults: <ReceiptExtractionResult<ReceiptExtraction>>[
              ReceiptExtractionSuccess<ReceiptExtraction>(
                openExtraction(status: ReceiptExtractionStatus.processing),
              ),
              ReceiptExtractionSuccess<ReceiptExtraction>(
                succeededExtraction(),
              ),
            ],
          );
      final ReceiptReviewCubit cubit = build(repository);
      final List<ReceiptReviewPhase> seen = <ReceiptReviewPhase>[];
      final void Function() stop = cubit.stream
          .listen((ReceiptReviewState state) => seen.add(state.phase))
          .cancel
          .call;

      await cubit.start();
      await settle();

      expect(cubit.state.phase, ReceiptReviewPhase.succeeded);
      expect(seen, contains(ReceiptReviewPhase.queued));
      expect(seen, contains(ReceiptReviewPhase.processing));

      // The loop stopped at the terminal state: the two scripted reads are the
      // only reads, and the third answer (which repeats) was never asked for.
      final int reads = repository.extractionIds.length;
      await settle(20);
      expect(repository.extractionIds.length, reads);
      expect(reads, 2);

      stop();
      await cubit.close();
    });

    test('stops when the cubit closes', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            requestResults:
                <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                  ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                    requestResult(
                      outcome: ReceiptExtractionRequestOutcome.queued,
                      extraction: openExtraction(),
                    ),
                  ),
                ],
            // Never leaves the open state, so only closing can end the loop.
            extractionResults: <ReceiptExtractionResult<ReceiptExtraction>>[
              ReceiptExtractionSuccess<ReceiptExtraction>(openExtraction()),
            ],
          );
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await cubit.close();
      final int reads = repository.extractionIds.length;
      await settle(50);

      expect(repository.extractionIds.length, reads);
    });

    test(
      'is bounded, and offers an explicit check instead of looping on',
      () async {
        final FakeReceiptExtractionRepository repository =
            FakeReceiptExtractionRepository(
              requestResults:
                  <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                    ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                      requestResult(
                        outcome: ReceiptExtractionRequestOutcome.queued,
                        extraction: openExtraction(),
                      ),
                    ),
                  ],
              extractionResults: <ReceiptExtractionResult<ReceiptExtraction>>[
                ReceiptExtractionSuccess<ReceiptExtraction>(openExtraction()),
              ],
            );
        final ReceiptReviewCubit cubit = build(repository, maxPolls: 3);

        await cubit.start();
        await settle();

        expect(repository.extractionIds, hasLength(3));
        expect(cubit.state.pollBudgetSpent, isTrue);
        expect(cubit.state.isAwaitingExtraction, isTrue);
        await cubit.close();
      },
    );

    test('never runs two loops at once', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            requestResults:
                <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                  ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                    requestResult(
                      outcome: ReceiptExtractionRequestOutcome.queued,
                      extraction: openExtraction(),
                    ),
                  ),
                ],
            extractionResults: <ReceiptExtractionResult<ReceiptExtraction>>[
              ReceiptExtractionSuccess<ReceiptExtraction>(openExtraction()),
            ],
          );
      final ReceiptReviewCubit cubit = build(repository, maxPolls: 4);

      // Resuming the app while a loop is already running must not start a
      // second: two loops would double the request rate and halve the bound.
      cubit.setAppActive(true);
      await cubit.start();
      cubit.setAppActive(true);
      await settle();

      expect(repository.extractionIds, hasLength(4));
      await cubit.close();
    });

    test('pauses while the app is not in the foreground', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            requestResults:
                <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                  ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                    requestResult(
                      outcome: ReceiptExtractionRequestOutcome.queued,
                      extraction: openExtraction(),
                    ),
                  ),
                ],
            extractionResults: <ReceiptExtractionResult<ReceiptExtraction>>[
              ReceiptExtractionSuccess<ReceiptExtraction>(openExtraction()),
            ],
          );
      final ReceiptReviewCubit cubit = build(repository, maxPolls: 2);

      cubit.setAppActive(false);
      await cubit.start();

      expect(repository.extractionIds, isEmpty);

      cubit.setAppActive(true);
      await settle();
      expect(repository.extractionIds, isNotEmpty);
      await cubit.close();
    });

    test('never polls a status this build does not recognise', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            requestResults:
                <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                  ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                    requestResult(
                      outcome: ReceiptExtractionRequestOutcome.queued,
                      extraction: openExtraction(
                        status: ReceiptExtractionStatus.unknown,
                      ),
                    ),
                  ),
                ],
          );
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();

      expect(cubit.state.isAwaitingExtraction, isFalse);
      expect(repository.extractionIds, isEmpty);
      await cubit.close();
    });
  });

  group('failure and retry', () {
    test(
      'a failed attempt offers a retry only when the backend allows it',
      () async {
        final FakeReceiptExtractionRepository repository =
            FakeReceiptExtractionRepository(
              requestResults:
                  <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                    ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                      requestResult(
                        outcome: ReceiptExtractionRequestOutcome.succeeded,
                        extraction: failedExtraction(),
                      ),
                    ),
                  ],
            );
        final ReceiptReviewCubit cubit = build(repository);

        await cubit.start();

        expect(cubit.state.phase, ReceiptReviewPhase.failed);
        expect(cubit.state.canRetry, isTrue);
        expect(cubit.state.canEdit, isTrue);

        await cubit.retryExtraction();
        expect(repository.requestedIds, hasLength(2));
        await cubit.close();
      },
    );

    test('retry_allowed false hides the retry even with attempts left', () async {
      // The counters are facts about persisted rows. Offering a retry from them
      // would offer it while the provider was switched off.
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            requestResults:
                <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                  ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                    requestResult(
                      outcome: ReceiptExtractionRequestOutcome.succeeded,
                      extraction: failedExtraction(retryAllowed: false),
                    ),
                  ),
                ],
          );
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();

      expect(cubit.state.attemptsRemaining, greaterThan(0));
      expect(cubit.state.canRetry, isFalse);

      // Even called directly, it refuses.
      await cubit.retryExtraction();
      expect(repository.requestedIds, hasLength(1));
      await cubit.close();
    });

    test('an exhausted receipt keeps manual confirmation open', () async {
      final FakeReceiptExtractionRepository
      repository = FakeReceiptExtractionRepository(
        requestResults:
            <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
              const ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                ReceiptExtractionRequestResult(
                  outcome: ReceiptExtractionRequestOutcome.exhausted,
                  attemptsUsed: 3,
                  attemptsRemaining: 0,
                  retryAllowed: false,
                  manualConfirmationAllowed: true,
                ),
              ),
            ],
      );
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();

      expect(cubit.state.phase, ReceiptReviewPhase.exhausted);
      expect(cubit.state.canRetry, isFalse);
      expect(cubit.state.canEdit, isTrue);
      expect(cubit.state.attemptsRemaining, 0);
      await cubit.close();
    });

    test(
      'an unavailable runtime is a state, not a transport failure',
      () async {
        final FakeReceiptExtractionRepository
        repository = FakeReceiptExtractionRepository(
          requestResults:
              <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                const ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                  ReceiptExtractionRequestResult(
                    outcome:
                        ReceiptExtractionRequestOutcome.extractionUnavailable,
                    attemptsUsed: 0,
                    attemptsRemaining: 3,
                    retryAllowed: false,
                    manualConfirmationAllowed: true,
                  ),
                ),
              ],
        );
        final ReceiptReviewCubit cubit = build(repository);

        await cubit.start();

        expect(cubit.state.phase, ReceiptReviewPhase.unavailable);
        expect(cubit.state.problem, isNull);
        expect(cubit.state.canEdit, isTrue);
        expect(cubit.state.canRetry, isFalse);
        await cubit.close();
      },
    );

    test(
      'manual confirmation stays shut while an attempt is in flight',
      () async {
        final FakeReceiptExtractionRepository repository =
            FakeReceiptExtractionRepository(
              requestResults:
                  <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                    ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                      requestResult(
                        outcome: ReceiptExtractionRequestOutcome.queued,
                        manualConfirmationAllowed: false,
                        extraction: openExtraction(),
                      ),
                    ),
                  ],
              extractionResults: <ReceiptExtractionResult<ReceiptExtraction>>[
                ReceiptExtractionSuccess<ReceiptExtraction>(openExtraction()),
              ],
            );
        final ReceiptReviewCubit cubit = build(repository, maxPolls: 1);

        await cubit.start();
        await settle();

        expect(cubit.state.canEdit, isFalse);
        await cubit.close();
      },
    );

    test('a transport fault is never resent on its own', () async {
      final RefusingReceiptExtractionRepository repository =
          RefusingReceiptExtractionRepository(const ExtractionNetworkProblem());
      final ReceiptReviewCubit cubit = ReceiptReviewCubit(
        repository: repository,
        submissionId: reviewSubmissionId,
        delay: instant,
      );

      await cubit.start();

      expect(cubit.state.phase, ReceiptReviewPhase.unreachable);
      expect(cubit.state.problem, isA<ExtractionNetworkProblem>());
      await cubit.close();
    });

    test('a refusal that retrying cannot fix is terminal', () async {
      for (final ReceiptExtractionProblem problem in <ReceiptExtractionProblem>[
        const ExtractionForbiddenProblem(),
        const ExtractionNotFoundProblem(),
        const ExtractionUnauthenticatedProblem(),
      ]) {
        final ReceiptReviewCubit cubit = ReceiptReviewCubit(
          repository: RefusingReceiptExtractionRepository(problem),
          submissionId: reviewSubmissionId,
          delay: instant,
        );
        await cubit.start();
        expect(
          cubit.state.phase,
          ReceiptReviewPhase.blocked,
          reason: '$problem',
        );
        expect(cubit.state.canEdit, isFalse);
        await cubit.close();
      }
    });
  });

  group('the image preview', () {
    test('is minted on open and held only in memory', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();

      expect(repository.previewIds, <String>[reviewSubmissionId]);
      expect(cubit.state.previewPhase, ReceiptPreviewPhase.ready);
      expect(cubit.state.previewRevision, 1);
      await cubit.close();
    });

    test(
      'a re-mint changes the state even though the URL is not compared',
      () async {
        // The regression this test exists for: two capabilities minted a minute
        // apart carry the same expiry, and ReceiptImagePreview's equality reads
        // only the expiry — so without the revision counter the second emit would
        // be swallowed as a duplicate and the screen would keep a dead URL.
        final FakeReceiptExtractionRepository repository =
            FakeReceiptExtractionRepository();
        final ReceiptReviewCubit cubit = build(repository);

        await cubit.start();
        final ReceiptReviewState first = cubit.state;

        await cubit.loadPreview();
        final ReceiptReviewState second = cubit.state;

        expect(second.preview!.url, isNot(first.preview!.url));
        // The two previews really are equal — which is the whole problem.
        expect(second.preview, equals(first.preview));
        // And the two states are not, which is the whole fix.
        expect(second, isNot(equals(first)));
        expect(second.previewRevision, 2);
        await cubit.close();
      },
    );

    test('the URL is in no prop, and in no toString', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      final String url = cubit.state.preview!.url;

      expect(url, isNotEmpty);
      expect(cubit.state.props, isNot(contains(cubit.state.preview)));
      expect(cubit.state.toString(), isNot(contains(url)));
      expect(cubit.state.preview.toString(), isNot(contains(url)));
      await cubit.close();
    });

    test('is dropped when the screen leaves', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      expect(cubit.state.preview, isNotNull);

      cubit.forgetPreview();

      expect(cubit.state.preview, isNull);
      expect(cubit.state.previewPhase, ReceiptPreviewPhase.idle);
      await cubit.close();
    });

    test('a preview failure degrades that panel and nothing else', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            previewResults: <ReceiptExtractionResult<ReceiptImagePreview>>[
              const ReceiptExtractionFailed<ReceiptImagePreview>(
                ExtractionServiceUnavailableProblem(),
              ),
            ],
          );
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();

      expect(cubit.state.previewPhase, ReceiptPreviewPhase.failed);
      expect(cubit.state.preview, isNull);
      // The review itself is unaffected.
      expect(cubit.state.phase, ReceiptReviewPhase.succeeded);
      expect(cubit.state.canEdit, isTrue);
      await cubit.close();
    });
  });

  group('the form', () {
    test('is seeded from the reading, in major units', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      final ReceiptReviewDraft draft = cubit.state.draft;

      expect(draft.transactionDate, const ReceiptCivilDate(2026, 7, 25));
      expect(draft.transactionTime, const ReceiptCivilTime(9, 24));
      expect(draft.currencyCode, 'AED');
      expect(draft.merchantName, 'Marina Pharmacy');
      expect(draft.totalText, '125.50');
      expect(draft.subtotalText, '119.52');
      expect(draft.taxText, '5.98');
      await cubit.close();
    });

    test('a value the provider could not resolve is left blank', () async {
      // Source text present, value null — the case the reviewer most needs to
      // see. Pre-filling a zero here would invite them to confirm a total the
      // receipt never carried.
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            requestResults:
                <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                  ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                    requestResult(
                      extraction: succeededExtraction(
                        total: const ExtractedValue<int>(
                          sourceText: '1.234,56',
                        ),
                      ),
                    ),
                  ),
                ],
          );
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();

      expect(cubit.state.draft.totalText, isEmpty);
      expect(cubit.state.extraction!.total.sourceText, '1.234,56');
      expect(cubit.state.extraction!.total.needsAttention, isTrue);
      await cubit.close();
    });

    test('a field absent from the receipt is distinguishable from one that '
        'was printed but unreadable', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            requestResults:
                <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                  ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                    requestResult(
                      extraction: succeededExtraction(
                        merchantName: const ExtractedValue<String>(),
                      ),
                    ),
                  ),
                ],
          );
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();

      expect(cubit.state.extraction!.merchantName.isAbsent, isTrue);
      expect(cubit.state.extraction!.merchantName.needsAttention, isFalse);
      // Confidence and source text are independently nullable, and neither is
      // invented when the other is missing.
      expect(cubit.state.extraction!.merchantName.confidence, isNull);
      await cubit.close();
    });

    test(
      'a poll landing mid-edit does not overwrite what is being typed',
      () async {
        final FakeReceiptExtractionRepository repository =
            FakeReceiptExtractionRepository();
        final ReceiptReviewCubit cubit = build(repository);

        await cubit.start();
        cubit.setTotal('99.00');
        await cubit.checkAgain();

        expect(cubit.state.draft.totalText, '99.00');
        await cubit.close();
      },
    );

    test(
      'an empty required field is refused before anything is sent',
      () async {
        final FakeReceiptExtractionRepository repository =
            FakeReceiptExtractionRepository();
        final ReceiptReviewCubit cubit = build(repository);

        await cubit.start();
        cubit.setTotal('');
        cubit.setCurrencyCode('');
        await cubit.confirm();

        expect(
          cubit.state.fieldProblems[ReceiptReviewField.total],
          ReceiptReviewFieldProblem.missing,
        );
        expect(
          cubit.state.fieldProblems[ReceiptReviewField.currencyCode],
          ReceiptReviewFieldProblem.missing,
        );
        expect(repository.confirmInputs, isEmpty);
        await cubit.close();
      },
    );

    test('every other validation failure also stops the call', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      final ReceiptReviewCubit cubit = build(repository);
      await cubit.start();

      cubit.setCurrencyCode('AE');
      await cubit.confirm();
      expect(
        cubit.state.fieldProblems[ReceiptReviewField.currencyCode],
        ReceiptReviewFieldProblem.invalidCurrency,
      );

      cubit.setCurrencyCode('AED');
      cubit.setTotal('12.345');
      await cubit.confirm();
      expect(
        cubit.state.fieldProblems[ReceiptReviewField.total],
        ReceiptReviewFieldProblem.tooPrecise,
      );

      cubit.setTotal('99999999999999');
      await cubit.confirm();
      expect(
        cubit.state.fieldProblems[ReceiptReviewField.total],
        ReceiptReviewFieldProblem.outOfRange,
      );

      cubit.setTotal('abc');
      await cubit.confirm();
      expect(
        cubit.state.fieldProblems[ReceiptReviewField.total],
        ReceiptReviewFieldProblem.notANumber,
      );

      cubit.setTotal('10.00');
      cubit.setTransactionDate(const ReceiptCivilDate(1999, 12, 31));
      await cubit.confirm();
      expect(
        cubit.state.fieldProblems[ReceiptReviewField.transactionDate],
        ReceiptReviewFieldProblem.dateTooEarly,
      );

      cubit.setTransactionDate(const ReceiptCivilDate(2026, 7, 25));
      cubit.setMerchantName('x' * 256);
      await cubit.confirm();
      expect(
        cubit.state.fieldProblems[ReceiptReviewField.merchantName],
        ReceiptReviewFieldProblem.tooLong,
      );

      expect(repository.confirmInputs, isEmpty);
      await cubit.close();
    });

    test('editing a field clears that field\'s error and no other', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      cubit.setTotal('');
      cubit.setCurrencyCode('');
      await cubit.confirm();
      expect(cubit.state.fieldProblems, hasLength(2));

      cubit.setTotal('10.00');
      expect(
        cubit.state.fieldProblems.containsKey(ReceiptReviewField.total),
        isFalse,
      );
      expect(
        cubit.state.fieldProblems.containsKey(ReceiptReviewField.currencyCode),
        isTrue,
      );
      await cubit.close();
    });
  });

  group('confirming', () {
    test('sends integer minor units and the eight values, once', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      cubit.setTotal('125.50');
      cubit.setSubtotal('119.52');
      cubit.setTax('5.98');
      await cubit.confirm();

      expect(repository.confirmInputs, hasLength(1));
      final ReceiptConfirmationInput sent = repository.confirmInputs.single;
      expect(sent.submissionId, reviewSubmissionId);
      expect(sent.totalMinor, 12550);
      expect(sent.subtotalMinor, 11952);
      expect(sent.taxTotalMinor, 598);
      expect(sent.totalMinor, isA<int>());
      expect(sent.currencyCode, 'AED');
      expect(sent.transactionDate, const ReceiptCivilDate(2026, 7, 25));
      expect(sent.transactionTime, const ReceiptCivilTime(9, 24));
      expect(sent.merchantName, 'Marina Pharmacy');
      expect(sent.documentNumber, 'INV-2026/004512');
      await cubit.close();
    });

    test('an omitted optional amount is null and never zero', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      cubit.setSubtotal('');
      cubit.setTax('');
      await cubit.confirm();

      final ReceiptConfirmationInput sent = repository.confirmInputs.single;
      expect(sent.subtotalMinor, isNull);
      expect(sent.taxTotalMinor, isNull);
      await cubit.close();
    });

    test('an explicit zero tax stays zero', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      cubit.setTax('0');
      await cubit.confirm();

      expect(repository.confirmInputs.single.taxTotalMinor, 0);
      await cubit.close();
    });

    test('the confirmed state is settled and no longer editable', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await cubit.confirm();

      expect(cubit.state.phase, ReceiptReviewPhase.confirmed);
      expect(cubit.state.isSettled, isTrue);
      expect(cubit.state.canEdit, isFalse);
      expect(cubit.state.canConfirm, isFalse);
      expect(cubit.state.canRetry, isFalse);
      expect(cubit.state.confirmation, isNotNull);
      await cubit.close();
    });

    test('an immutable confirmation refuses further edits', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await cubit.confirm();
      final ReceiptReviewDraft before = cubit.state.draft;

      cubit.setTotal('1.00');
      cubit.setMerchantName('Something else');

      expect(cubit.state.draft, before);
      await cubit.close();
    });

    test('a second confirm is refused, never sent twice', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await Future.wait(<Future<void>>[
        cubit.confirm(),
        cubit.confirm(),
        cubit.confirm(),
      ]);

      expect(repository.confirmInputs, hasLength(1));
      await cubit.close();
    });

    test('the backend decides the entry mode and the changed fields', () async {
      final FakeReceiptExtractionRepository
      repository = FakeReceiptExtractionRepository(
        confirmResults: <ReceiptExtractionResult<ReceiptConfirmationResult>>[
          const ReceiptExtractionSuccess<ReceiptConfirmationResult>(
            ReceiptConfirmationResult(
              outcome: ReceiptConfirmationOutcome.confirmed,
              confirmationId: reviewConfirmationId,
              entryMode: ReceiptConfirmationEntryMode.mixed,
              changedFields: <ReceiptConfirmationField>[
                ReceiptConfirmationField.totalMinor,
              ],
            ),
          ),
        ],
        confirmationResults: <ReceiptExtractionResult<ReceiptConfirmation?>>[
          ReceiptExtractionSuccess<ReceiptConfirmation?>(
            storedConfirmation(
              entryMode: ReceiptConfirmationEntryMode.mixed,
              changedFields: <ReceiptConfirmationField>[
                ReceiptConfirmationField.totalMinor,
              ],
            ),
          ),
        ],
      );
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      cubit.setTotal('99.00');
      await cubit.confirm();

      expect(
        cubit.state.confirmation!.entryMode,
        ReceiptConfirmationEntryMode.mixed,
      );
      expect(
        cubit.state.confirmation!.changedFields,
        <ReceiptConfirmationField>[ReceiptConfirmationField.totalMinor],
      );
      await cubit.close();
    });

    test(
      'a duplicate confirmation returns the stored row, not a refusal',
      () async {
        final FakeReceiptExtractionRepository repository =
            FakeReceiptExtractionRepository(
              confirmResults:
                  <ReceiptExtractionResult<ReceiptConfirmationResult>>[
                    const ReceiptExtractionSuccess<ReceiptConfirmationResult>(
                      ReceiptConfirmationResult(
                        outcome: ReceiptConfirmationOutcome.alreadyConfirmed,
                        confirmationId: reviewConfirmationId,
                        entryMode: ReceiptConfirmationEntryMode.extracted,
                        changedFields: <ReceiptConfirmationField>[],
                      ),
                    ),
                  ],
            );
        final ReceiptReviewCubit cubit = build(repository);

        await cubit.start();
        await cubit.confirm();

        expect(cubit.state.phase, ReceiptReviewPhase.confirmed);
        expect(cubit.state.problem, isNull);
        await cubit.close();
      },
    );

    test(
      'a blocked confirmation writes nothing and keeps the typed values',
      () async {
        final FakeReceiptExtractionRepository
        repository = FakeReceiptExtractionRepository(
          confirmResults: <ReceiptExtractionResult<ReceiptConfirmationResult>>[
            const ReceiptExtractionSuccess<ReceiptConfirmationResult>(
              ReceiptConfirmationResult(
                outcome: ReceiptConfirmationOutcome.extractionInProgress,
                changedFields: <ReceiptConfirmationField>[],
              ),
            ),
          ],
        );
        final ReceiptReviewCubit cubit = build(repository);

        await cubit.start();
        cubit.setTotal('77.00');
        await cubit.confirm();

        expect(cubit.state.phase, isNot(ReceiptReviewPhase.confirmed));
        expect(cubit.state.confirmBlockedByExtraction, isTrue);
        expect(cubit.state.draft.totalText, '77.00');
        await cubit.close();
      },
    );

    test('an unknown outcome is never read as confirmed', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            confirmResults:
                <ReceiptExtractionResult<ReceiptConfirmationResult>>[
                  const ReceiptExtractionSuccess<ReceiptConfirmationResult>(
                    ReceiptConfirmationResult(
                      outcome: ReceiptConfirmationOutcome.unknown,
                      changedFields: <ReceiptConfirmationField>[],
                    ),
                  ),
                ],
          );
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await cubit.confirm();

      expect(cubit.state.phase, isNot(ReceiptReviewPhase.confirmed));
      expect(cubit.state.isSettled, isFalse);
      expect(cubit.state.problem, isA<ExtractionMalformedResponseProblem>());
      await cubit.close();
    });

    test('a failed confirmation keeps the form and is never resent', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            confirmResults:
                <ReceiptExtractionResult<ReceiptConfirmationResult>>[
                  const ReceiptExtractionFailed<ReceiptConfirmationResult>(
                    ExtractionNetworkProblem(),
                  ),
                ],
          );
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      cubit.setTotal('55.00');
      await cubit.confirm();

      expect(cubit.state.phase, ReceiptReviewPhase.succeeded);
      expect(cubit.state.problem, isA<ExtractionNetworkProblem>());
      expect(cubit.state.draft.totalText, '55.00');
      expect(repository.confirmInputs, hasLength(1));
      await cubit.close();
    });
  });

  group('an already confirmed receipt', () {
    test('opens straight into the settled state', () async {
      final FakeReceiptExtractionRepository
      repository = FakeReceiptExtractionRepository(
        requestResults:
            <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
              const ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                ReceiptExtractionRequestResult(
                  outcome: ReceiptExtractionRequestOutcome.alreadyConfirmed,
                  attemptsUsed: 0,
                  attemptsRemaining: 3,
                  retryAllowed: false,
                  manualConfirmationAllowed: false,
                ),
              ),
            ],
      );
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();

      expect(cubit.state.phase, ReceiptReviewPhase.confirmed);
      expect(cubit.state.confirmation, isNotNull);
      expect(cubit.state.canEdit, isFalse);
      expect(repository.confirmInputs, isEmpty);
      await cubit.close();
    });
  });

  group('the reading itself', () {
    test(
      'warnings arrive as codes and are neither dropped nor blocking',
      () async {
        final FakeReceiptExtractionRepository repository =
            FakeReceiptExtractionRepository(
              requestResults:
                  <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                    ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                      requestResult(
                        extraction: succeededExtraction(
                          warningCodes: const <ReceiptExtractionWarningCode>[
                            ReceiptExtractionWarningCode.lowConfidenceTotal,
                            ReceiptExtractionWarningCode.unknown,
                          ],
                        ),
                      ),
                    ),
                  ],
            );
        final ReceiptReviewCubit cubit = build(repository);

        await cubit.start();

        expect(cubit.state.extraction!.warningCodes, hasLength(2));
        expect(cubit.state.canConfirm, isTrue);
        await cubit.close();
      },
    );

    test('line items are read in the backend order and gate nothing', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();

      expect(
        cubit.state.lineItems.map(
          (ReceiptExtractionLineItem item) => item.lineNumber,
        ),
        <int>[1, 2],
      );
      await cubit.close();
    });

    test('a line-item read failure degrades only that section', () async {
      final FakeReceiptExtractionRepository
      repository = FakeReceiptExtractionRepository(
        lineItemResults:
            <ReceiptExtractionResult<List<ReceiptExtractionLineItem>>>[
              const ReceiptExtractionFailed<List<ReceiptExtractionLineItem>>(
                ExtractionServiceUnavailableProblem(),
              ),
            ],
      );
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();

      expect(cubit.state.lineItems, isEmpty);
      expect(cubit.state.phase, ReceiptReviewPhase.succeeded);
      expect(cubit.state.problem, isNull);
      await cubit.close();
    });
  });

  // -------------------------------------------------------------------------
  // The currency's decimal width
  //
  // The blocking defect this correction removed was a hard-coded two. These
  // assertions are the shape of what replaced it: a width is asked for, is bound
  // to the code it was asked about, and is never invented.
  // -------------------------------------------------------------------------
  group('resolving the currency width', () {
    test(
      'an extracted EUR width of 2 is used immediately, with no lookup',
      () async {
        final FakeReceiptExtractionRepository repository =
            FakeReceiptExtractionRepository(
              requestResults:
                  <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                    ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                      requestResult(
                        extraction: succeededExtraction(currencyMinorUnit: 2),
                      ),
                    ),
                  ],
            );
        final ReceiptReviewCubit cubit = build(repository);

        await cubit.start();
        await settle(5);

        expect(cubit.state.currency.phase, ReceiptCurrencyPhase.resolved);
        expect(cubit.state.resolvedMinorUnit, 2);
        // The backend already joined it when it stored the attempt. A round trip
        // here would buy nothing.
        expect(repository.currencyCodes, isEmpty);
        await cubit.close();
      },
    );

    test('an extracted JPY width of 0 is used immediately too', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            requestResults:
                <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                  ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                    requestResult(
                      extraction: succeededExtraction(currencyMinorUnit: 0),
                    ),
                  ),
                ],
          );
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);

      // Zero is a width like any other, and specifically not "no width".
      expect(cubit.state.resolvedMinorUnit, 0);
      expect(repository.currencyCodes, isEmpty);
      await cubit.close();
    });

    test('an extraction with a null width triggers the lookup', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            requestResults:
                <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                  ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                    requestResult(
                      extraction: succeededExtraction(currencyMinorUnit: null),
                    ),
                  ),
                ],
          );
      repository.currencyResults['AED'] = currencyWidth('AED', 2);
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);

      expect(repository.currencyCodes, <String>['AED']);
      expect(cubit.state.resolvedMinorUnit, 2);
      await cubit.close();
    });

    test(
      'the amounts stay empty until a width exists, then arrive scaled',
      () async {
        final FakeReceiptExtractionRepository repository =
            FakeReceiptExtractionRepository(
              requestResults:
                  <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                    ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                      requestResult(
                        extraction: succeededExtraction(
                          currencyMinorUnit: null,
                        ),
                      ),
                    ),
                  ],
            );
        repository.currencyGates['AED'] =
            Completer<ReceiptExtractionResult<ReceiptCurrencyMinorUnit?>>();
        final ReceiptReviewCubit cubit = build(repository);

        await cubit.start();
        await settle(5);

        // 12550 minor units of an unknown width is not "125.50". Rendering it as
        // such is exactly the guess this correction removes.
        expect(cubit.state.draft.totalText, isEmpty);
        expect(cubit.state.resolvedMinorUnit, isNull);

        repository.currencyGates['AED']!.complete(currencyWidth('AED', 2));
        await settle(5);

        expect(cubit.state.draft.totalText, '125.50');
        expect(cubit.state.draft.subtotalText, '119.52');
        expect(cubit.state.draft.taxText, '5.98');
        await cubit.close();
      },
    );

    test(
      'a manual confirmation resolves the typed code before anything else',
      () async {
        final FakeReceiptExtractionRepository repository =
            FakeReceiptExtractionRepository(
              requestResults:
                  <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                    ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                      requestResult(
                        outcome: ReceiptExtractionRequestOutcome.exhausted,
                        manualConfirmationAllowed: true,
                      ),
                    ),
                  ],
            );
        repository.currencyResults['JPY'] = currencyWidth('JPY', 0);
        final ReceiptReviewCubit cubit = build(repository);

        await cubit.start();
        await settle(5);

        // No reading at all, so there is no width to inherit and nothing to
        // assume. Confirmation is closed until the lookup answers.
        expect(cubit.state.resolvedMinorUnit, isNull);
        expect(cubit.state.canConfirm, isFalse);

        cubit.setCurrencyCode('JPY');
        await settle(5);

        expect(repository.currencyCodes, <String>['JPY']);
        expect(cubit.state.resolvedMinorUnit, 0);
        await cubit.close();
      },
    );

    test('EUR to JPY invalidates 2 and resolves 0', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      repository.currencyResults['JPY'] = currencyWidth('JPY', 0);
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);
      expect(cubit.state.resolvedMinorUnit, 2);

      cubit.setCurrencyCode('JPY');

      // Invalidation is structural and immediate: the width is bound to AED and
      // the code is now JPY, so there is nothing to carry over even for the one
      // frame before the lookup answers.
      expect(cubit.state.resolvedMinorUnit, isNull);
      expect(cubit.state.canConfirm, isFalse);

      await settle(5);
      expect(cubit.state.resolvedMinorUnit, 0);
      await cubit.close();
    });

    test('EUR to KWD invalidates 2 and resolves 3', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      repository.currencyResults['KWD'] = currencyWidth('KWD', 3);
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);
      expect(cubit.state.resolvedMinorUnit, 2);

      cubit.setCurrencyCode('KWD');
      await settle(5);

      expect(cubit.state.resolvedMinorUnit, 3);
      await cubit.close();
    });

    test('changing the currency never rewrites the typed amount', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      repository.currencyResults['JPY'] = currencyWidth('JPY', 0);
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);
      cubit.setTotal('12.34');

      cubit.setCurrencyCode('JPY');
      await settle(5);

      // The digits somebody typed stay exactly as typed. Re-scaling `12.34`
      // into `1234` on their behalf would assert we knew which the paper said.
      expect(cubit.state.draft.totalText, '12.34');
      await cubit.close();
    });

    test('an unsupported code blocks confirmation and says so', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);

      cubit.setCurrencyCode('ZZZ');
      await settle(5);

      expect(cubit.state.currency.phase, ReceiptCurrencyPhase.unsupported);
      expect(cubit.state.resolvedMinorUnit, isNull);
      expect(cubit.state.canConfirm, isFalse);
      expect(
        cubit.state.currencyProblem,
        ReceiptReviewFieldProblem.unsupportedCurrency,
      );
      // Asking again would give the same answer, so it is not offered.
      expect(cubit.state.canResolveCurrency, isFalse);

      await cubit.confirm();
      expect(repository.confirmInputs, isEmpty);
      await cubit.close();
    });

    test(
      'a lookup failure keeps the draft and offers an explicit retry',
      () async {
        final FakeReceiptExtractionRepository repository =
            FakeReceiptExtractionRepository();
        repository.currencyResults['KWD'] =
            const ReceiptExtractionFailed<ReceiptCurrencyMinorUnit?>(
              ExtractionNetworkProblem(),
            );
        final ReceiptReviewCubit cubit = build(repository);

        await cubit.start();
        await settle(5);
        cubit.setMerchantName('Marina Pharmacy');
        cubit.setTotal('55.00');

        cubit.setCurrencyCode('KWD');
        await settle(5);

        expect(cubit.state.currency.phase, ReceiptCurrencyPhase.failed);
        expect(cubit.state.currency.problem, isA<ExtractionNetworkProblem>());
        // Nothing typed is lost, and the screen is not blocked.
        expect(cubit.state.draft.totalText, '55.00');
        expect(cubit.state.draft.merchantName, 'Marina Pharmacy');
        expect(cubit.state.canConfirm, isFalse);
        expect(cubit.state.canResolveCurrency, isTrue);
        await cubit.close();
      },
    );

    test('an explicit retry of the lookup succeeds', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      repository.currencyResults['KWD'] =
          const ReceiptExtractionFailed<ReceiptCurrencyMinorUnit?>(
            ExtractionNetworkProblem(),
          );
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);
      cubit.setCurrencyCode('KWD');
      await settle(5);
      expect(cubit.state.currency.phase, ReceiptCurrencyPhase.failed);

      repository.currencyResults['KWD'] = currencyWidth('KWD', 3);
      await cubit.resolveCurrency();
      await settle(5);

      expect(cubit.state.resolvedMinorUnit, 3);
      expect(repository.currencyCodes, <String>['KWD', 'KWD']);
      await cubit.close();
    });

    test('a rebuild or an unrelated edit costs no second lookup', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            requestResults:
                <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                  ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                    requestResult(
                      extraction: succeededExtraction(currencyMinorUnit: null),
                    ),
                  ),
                ],
          );
      repository.currencyResults['AED'] = currencyWidth('AED', 2);
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);
      expect(repository.currencyCodes, hasLength(1));

      // A rebuild calls `start()` again; a person edits three other fields; the
      // currency text is re-emitted unchanged by the controller sync.
      await cubit.start();
      cubit.setMerchantName('Marina');
      cubit.setTotal('1.00');
      cubit.setCurrencyCode('AED');
      cubit.setCurrencyCode('AED');
      await settle(5);

      expect(repository.currencyCodes, hasLength(1));
      await cubit.close();
    });

    test('a half-typed code claims nothing and asks nothing', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);

      cubit.setCurrencyCode('J');
      await settle(5);
      expect(cubit.state.currency.phase, ReceiptCurrencyPhase.unresolved);
      expect(cubit.state.resolvedMinorUnit, isNull);

      cubit.setCurrencyCode('JP');
      await settle(5);
      expect(cubit.state.resolvedMinorUnit, isNull);

      // A lookup per character would be noise, and a width that flickered while
      // somebody typed would be worse than none.
      expect(repository.currencyCodes, isEmpty);
      await cubit.close();
    });

    test('a resolved width belongs to its code and to no other', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);

      expect(cubit.state.currency.minorUnitFor('AED'), 2);
      expect(cubit.state.currency.minorUnitFor('JPY'), isNull);
      expect(cubit.state.currency.minorUnitFor('aed'), isNull);
      await cubit.close();
    });
  });

  group('a late lookup answer can never settle the wrong currency', () {
    test('a JPY answer arriving after KWD is typed is discarded', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      repository.currencyGates['JPY'] =
          Completer<ReceiptExtractionResult<ReceiptCurrencyMinorUnit?>>();
      repository.currencyResults['KWD'] = currencyWidth('KWD', 3);
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);

      // 1. JPY is typed and its lookup starts.
      cubit.setCurrencyCode('JPY');
      await settle(5);
      expect(cubit.state.currency.phase, ReceiptCurrencyPhase.resolving);

      // 2. The person changes their mind before it answers.
      cubit.setCurrencyCode('KWD');
      await settle(5);
      expect(cubit.state.resolvedMinorUnit, 3);

      // 3. JPY answers late.
      repository.currencyGates['JPY']!.complete(currencyWidth('JPY', 0));
      await settle(10);

      // Zero decimals on a three-decimal currency would mis-scale every amount
      // by a thousand, into a row nobody can correct.
      expect(cubit.state.resolvedMinorUnit, 3);
      expect(cubit.state.currency.resolvedCode, 'KWD');
      await cubit.close();
    });

    test(
      'a late answer cannot resurrect a width for a cleared field',
      () async {
        final FakeReceiptExtractionRepository repository =
            FakeReceiptExtractionRepository();
        repository.currencyGates['JPY'] =
            Completer<ReceiptExtractionResult<ReceiptCurrencyMinorUnit?>>();
        final ReceiptReviewCubit cubit = build(repository);

        await cubit.start();
        await settle(5);
        cubit.setCurrencyCode('JPY');
        await settle(5);

        cubit.setCurrencyCode('');
        await settle(5);

        repository.currencyGates['JPY']!.complete(currencyWidth('JPY', 0));
        await settle(10);

        expect(cubit.state.resolvedMinorUnit, isNull);
        expect(cubit.state.currency.phase, ReceiptCurrencyPhase.unresolved);
        await cubit.close();
      },
    );

    test(
      'an answer about a different code than was asked is refused',
      () async {
        final FakeReceiptExtractionRepository repository =
            FakeReceiptExtractionRepository();
        repository.currencyResults['KWD'] = currencyWidth('JPY', 0);
        final ReceiptReviewCubit cubit = build(repository);

        await cubit.start();
        await settle(5);
        cubit.setCurrencyCode('KWD');
        await settle(5);

        expect(cubit.state.currency.phase, ReceiptCurrencyPhase.failed);
        expect(
          cubit.state.currency.problem,
          isA<ExtractionMalformedResponseProblem>(),
        );
        expect(cubit.state.resolvedMinorUnit, isNull);
        await cubit.close();
      },
    );

    test('changing the currency does not disturb extraction polling', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            requestResults:
                <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                  ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                    requestResult(
                      outcome: ReceiptExtractionRequestOutcome.exhausted,
                      manualConfirmationAllowed: true,
                    ),
                  ),
                ],
          );
      repository.currencyResults['JPY'] = currencyWidth('JPY', 0);
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);
      final int readsBefore = repository.extractionIds.length;

      cubit.setCurrencyCode('JPY');
      await settle(10);

      expect(repository.extractionIds, hasLength(readsBefore));
      expect(repository.requestedIds, hasLength(1));
      await cubit.close();
    });
  });

  group('confirming with a resolved width', () {
    test('the declared width is the one the amounts were built with', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            requestResults:
                <ReceiptExtractionResult<ReceiptExtractionRequestResult>>[
                  ReceiptExtractionSuccess<ReceiptExtractionRequestResult>(
                    requestResult(
                      outcome: ReceiptExtractionRequestOutcome.exhausted,
                      manualConfirmationAllowed: true,
                    ),
                  ),
                ],
          );
      repository.currencyResults['JPY'] = currencyWidth('JPY', 0);
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);
      cubit.setTransactionDate(const ReceiptCivilDate(2026, 7, 25));
      cubit.setCurrencyCode('JPY');
      await settle(5);
      cubit.setTotal('1000');

      await cubit.confirm();

      final ReceiptConfirmationInput input = repository.confirmInputs.single;
      // ¥1000, and the request says which of ¥1000 and ¥10.00 it means.
      expect(input.currencyCode, 'JPY');
      expect(input.currencyMinorUnit, 0);
      expect(input.totalMinor, 1000);
      await cubit.close();
    });

    test('a KWD confirmation carries three decimals', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      repository.currencyResults['KWD'] = currencyWidth('KWD', 3);
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);
      cubit.setCurrencyCode('KWD');
      await settle(5);
      cubit.setTotal('1.234');

      await cubit.confirm();

      final ReceiptConfirmationInput input = repository.confirmInputs.single;
      expect(input.currencyMinorUnit, 3);
      expect(input.totalMinor, 1234);
      await cubit.close();
    });

    test('nothing is confirmed before the width is resolved', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository();
      repository.currencyGates['JPY'] =
          Completer<ReceiptExtractionResult<ReceiptCurrencyMinorUnit?>>();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);
      cubit.setCurrencyCode('JPY');
      await settle(5);

      expect(cubit.state.canConfirm, isFalse);
      await cubit.confirm();
      expect(repository.confirmInputs, isEmpty);

      repository.currencyGates['JPY']!.complete(currencyWidth('JPY', 0));
      await settle(5);
      cubit.setTotal('1000');
      // The AED figures seeded with two decimals are not valid yen, and the
      // form says so rather than truncating them — so the reviewer clears them,
      // exactly as they would on the shop floor.
      cubit.setSubtotal('');
      cubit.setTax('');

      expect(cubit.state.canConfirm, isTrue);
      await cubit.confirm();
      expect(repository.confirmInputs, hasLength(1));
      expect(repository.confirmInputs.single.currencyMinorUnit, 0);
      await cubit.close();
    });
  });

  group('SQLSTATE 22023 — the declared width was refused', () {
    FakeReceiptExtractionRepository mismatching() {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            confirmResults:
                <ReceiptExtractionResult<ReceiptConfirmationResult>>[
                  const ReceiptExtractionFailed<ReceiptConfirmationResult>(
                    ExtractionCurrencyScaleMismatchProblem(),
                  ),
                ],
          );
      return repository;
    }

    test('the resolved width is invalidated and confirmation closes', () async {
      final FakeReceiptExtractionRepository repository = mismatching();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);
      expect(cubit.state.resolvedMinorUnit, 2);

      await cubit.confirm();
      await settle(5);

      expect(
        cubit.state.problem,
        isA<ExtractionCurrencyScaleMismatchProblem>(),
      );
      expect(cubit.state.currency.phase, ReceiptCurrencyPhase.unresolved);
      expect(cubit.state.resolvedMinorUnit, isNull);
      expect(cubit.state.canConfirm, isFalse);
      await cubit.close();
    });

    test('the confirmation is not resent automatically', () async {
      final FakeReceiptExtractionRepository repository = mismatching();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);
      await cubit.confirm();
      await settle(20);

      // A confirmation is immutable. A resend that guessed the same width again
      // would either fail identically or succeed against a width that had
      // meanwhile changed.
      expect(repository.confirmInputs, hasLength(1));
      await cubit.close();
    });

    test('the typed receipt values are preserved', () async {
      final FakeReceiptExtractionRepository repository = mismatching();
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);
      cubit.setTotal('55.00');
      cubit.setMerchantName('Marina Pharmacy');
      cubit.setDocumentNumber('INV-1');

      await cubit.confirm();
      await settle(5);

      expect(cubit.state.draft.totalText, '55.00');
      expect(cubit.state.draft.merchantName, 'Marina Pharmacy');
      expect(cubit.state.draft.documentNumber, 'INV-1');
      expect(cubit.state.phase, ReceiptReviewPhase.succeeded);
      await cubit.close();
    });

    test('the width must be established again, from the backend', () async {
      final FakeReceiptExtractionRepository repository = mismatching();
      repository.currencyResults['AED'] = currencyWidth('AED', 3);
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);
      await cubit.confirm();
      await settle(5);

      expect(cubit.state.canResolveCurrency, isTrue);
      await cubit.resolveCurrency();
      await settle(5);

      // The reading's own `currency_minor_unit` said 2 and the backend has just
      // refused it, so the shortcut is not taken again: the lookup is asked,
      // and its answer is the one adopted.
      expect(repository.currencyCodes, <String>['AED']);
      expect(cubit.state.resolvedMinorUnit, 3);
      await cubit.close();
    });

    test('a second confirmation carries the re-resolved width', () async {
      final FakeReceiptExtractionRepository repository = mismatching();
      repository.currencyResults['AED'] = currencyWidth('AED', 3);
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);
      await cubit.confirm();
      await settle(5);
      await cubit.resolveCurrency();
      await settle(5);

      cubit.setTotal('1.234');
      await cubit.confirm();
      await settle(5);

      expect(repository.confirmInputs, hasLength(2));
      expect(repository.confirmInputs.last.currencyMinorUnit, 3);
      expect(repository.confirmInputs.last.totalMinor, 1234);
      await cubit.close();
    });

    test('another confirmation problem leaves the width alone', () async {
      final FakeReceiptExtractionRepository repository =
          FakeReceiptExtractionRepository(
            confirmResults:
                <ReceiptExtractionResult<ReceiptConfirmationResult>>[
                  const ReceiptExtractionFailed<ReceiptConfirmationResult>(
                    ExtractionNetworkProblem(),
                  ),
                ],
          );
      final ReceiptReviewCubit cubit = build(repository);

      await cubit.start();
      await settle(5);
      await cubit.confirm();
      await settle(5);

      // A dropped connection says nothing about the scale.
      expect(cubit.state.resolvedMinorUnit, 2);
      await cubit.close();
    });
  });
}
