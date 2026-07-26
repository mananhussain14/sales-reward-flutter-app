import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_draft.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_field.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_input.dart';
import 'package:sale_reward/features/products/domain/repositories/vendor_product_write_result.dart';
import 'package:sale_reward/features/products/presentation/vendor/cubit/vendor_product_create_cubit.dart';

import '../../support/vendor_product_fakes.dart';

/// The create form and its one write.
void main() {
  late FakeVendorProductRepository repository;
  late List<String> createdIds;
  late int catalogueStaleCalls;

  VendorProductCreateCubit build() => VendorProductCreateCubit(
    repository,
    onProductCreated: createdIds.add,
    onCatalogueStale: () => catalogueStaleCalls++,
  );

  setUp(() {
    repository = FakeVendorProductRepository();
    createdIds = <String>[];
    catalogueStaleCalls = 0;
  });

  /// Fills the form with a valid product.
  void fill(
    VendorProductCreateCubit cubit, {
    String code = 'esp-1000',
    String name = '  Espresso   Blend 1kg  ',
    String barcode = ' 501 234-567-8900 ',
    String brand = '  Harvest  Roasters ',
    String description = '  A dark roast blend.\n\nBest with milk.  ',
  }) {
    cubit
      ..productCodeChanged(code)
      ..productNameChanged(name)
      ..barcodeChanged(barcode)
      ..brandChanged(brand)
      ..descriptionChanged(description);
  }

  group('the initial form', () {
    test('is blank, editable and submittable', () {
      final VendorProductCreateCubit cubit = build();

      expect(cubit.state.values, const VendorProductFormValues());
      expect(cubit.state.phase, VendorProductCreatePhase.editing);
      expect(cubit.state.fieldErrors, isEmpty);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.createdProductId, isNull);
      expect(cubit.state.canSubmit, isTrue);
    });

    test('nothing is read or written before a submission', () {
      build();
      expect(repository.callLog, isEmpty);
    });
  });

  group('editing', () {
    test('each field is recorded exactly as typed', () {
      final VendorProductCreateCubit cubit = build();
      fill(cubit);

      // Raw, not normalized: text is never rewritten under the cursor.
      expect(cubit.state.values.productCode, 'esp-1000');
      expect(cubit.state.values.productName, '  Espresso   Blend 1kg  ');
      expect(cubit.state.values.barcode, ' 501 234-567-8900 ');
      expect(cubit.state.values.brand, '  Harvest  Roasters ');
      expect(
        cubit.state.values.description,
        '  A dark roast blend.\n\nBest with milk.  ',
      );
    });

    test('editing a field clears that field\'s message', () async {
      final VendorProductCreateCubit cubit = build();
      await cubit.submit();
      expect(cubit.state.fieldErrors, contains(VendorProductField.productCode));

      cubit.productCodeChanged('ESP-1000');
      expect(
        cubit.state.fieldErrors.containsKey(VendorProductField.productCode),
        isFalse,
      );
      // The other message is untouched — it still describes its own field.
      expect(cubit.state.fieldErrors, contains(VendorProductField.productName));
    });

    test('editing clears a form-level failure', () async {
      repository.createResult = const VendorProductWriteFailure<String>(
        UnavailableFailure(),
      );
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      await cubit.submit();
      expect(cubit.state.failure, const UnavailableFailure());

      cubit.productNameChanged('Something else');
      expect(cubit.state.failure, isNull);
    });

    test('editing is ignored once a create has settled', () async {
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      await cubit.submit();
      expect(cubit.state.phase, VendorProductCreatePhase.created);

      cubit.productNameChanged('Too late');
      expect(cubit.state.values.productName, isNot('Too late'));
    });
  });

  group('client-side validation stops a doomed submission', () {
    test(
      'an empty form reports both required fields and sends nothing',
      () async {
        final VendorProductCreateCubit cubit = build();
        await cubit.submit();

        expect(repository.submittedDrafts, isEmpty);
        expect(cubit.state.fieldErrors.keys, <VendorProductField>{
          VendorProductField.productCode,
          VendorProductField.productName,
        });
        expect(cubit.state.phase, VendorProductCreatePhase.editing);
      },
    );

    test('a whitespace-only required field is the same omission', () async {
      final VendorProductCreateCubit cubit = build();
      fill(cubit, code: '   ', name: '\t\n');
      await cubit.submit();

      expect(repository.submittedDrafts, isEmpty);
      expect(cubit.state.fieldErrors.keys, <VendorProductField>{
        VendorProductField.productCode,
        VendorProductField.productName,
      });
    });

    test('a bad barcode is reported and nothing is sent', () async {
      final VendorProductCreateCubit cubit = build();
      fill(cubit, barcode: '123');
      await cubit.submit();

      expect(repository.submittedDrafts, isEmpty);
      expect(cubit.state.fieldErrors.keys, <VendorProductField>{
        VendorProductField.barcode,
      });
    });

    test('an over-long value is reported and nothing is sent', () async {
      final VendorProductCreateCubit cubit = build();
      fill(cubit, description: 'x' * 2001);
      await cubit.submit();

      expect(repository.submittedDrafts, isEmpty);
      expect(cubit.state.fieldErrors, contains(VendorProductField.description));
    });

    test('a refused submission adopts the normalized values', () async {
      // So a length or shape message describes the string it was computed from,
      // which is what the web echoes back for the same reason.
      final VendorProductCreateCubit cubit = build();
      fill(cubit, code: '   ');
      await cubit.submit();

      expect(cubit.state.values.productName, 'Espresso Blend 1kg');
      expect(cubit.state.values.barcode, '5012345678900');
      expect(cubit.state.values.brand, 'Harvest Roasters');
    });

    test('the first invalid field is reported in reading order', () async {
      final VendorProductCreateCubit cubit = build();
      fill(cubit, code: '', barcode: '1');
      await cubit.submit();

      expect(cubit.state.firstInvalidField, VendorProductField.productCode);

      cubit.productCodeChanged('ESP-1000');
      await cubit.submit();
      expect(cubit.state.firstInvalidField, VendorProductField.barcode);
    });

    test('the form is still submittable after a refusal', () async {
      final VendorProductCreateCubit cubit = build();
      await cubit.submit();
      expect(cubit.state.canSubmit, isTrue);
    });
  });

  group('a valid submission', () {
    test('sends the five normalized values and nothing else', () async {
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      await cubit.submit();

      expect(repository.submittedDrafts.length, 1);
      final VendorProductDraft draft = repository.submittedDrafts.single;

      // Normalized by the rules the deployed function applies again.
      expect(draft.productCode, 'ESP-1000');
      expect(draft.productName, 'Espresso Blend 1kg');
      expect(draft.barcode, '5012345678900');
      expect(draft.brand, 'Harvest Roasters');
      // Trim only: the blank line is the author's.
      expect(draft.description, 'A dark roast blend.\n\nBest with milk.');
    });

    test('emptied optionals travel as null, never as empty strings', () async {
      final VendorProductCreateCubit cubit = build();
      fill(cubit, barcode: '  ', brand: '', description: '\n');
      await cubit.submit();

      final VendorProductDraft draft = repository.submittedDrafts.single;
      expect(draft.barcode, isNull);
      expect(draft.brand, isNull);
      expect(draft.description, isNull);
    });

    test('no status, organization or assignment value is carried', () async {
      // The draft type has nowhere to put one, so this is the type restated as a
      // behavioural assertion rather than a second check of the same thing.
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      await cubit.submit();

      final VendorProductDraft draft = repository.submittedDrafts.single;
      expect(draft.productCode, isNot('ACTIVE'));
      expect(
        <Object?>[
          draft.productCode,
          draft.productName,
          draft.barcode,
          draft.brand,
          draft.description,
        ].length,
        5,
        reason: 'a draft has exactly five values',
      );
    });

    test('it reaches `created` with the returned id', () async {
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      await cubit.submit();

      expect(cubit.state.phase, VendorProductCreatePhase.created);
      expect(cubit.state.createdProductId, createdProductUuid);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.fieldErrors, isEmpty);
    });

    test('the catalogue and the canonical read are both requested', () async {
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      await cubit.submit();

      // One callback, carrying the id — the shell wires it to the detail cubit's
      // canonical read and to the catalogue's refresh.
      expect(createdIds, <String>[createdProductUuid]);
      expect(catalogueStaleCalls, 0);
    });

    test('nothing is built from the form as a product', () async {
      // The write returns a uuid and nothing else, so there is nothing on this state
      // that could be mistaken for a stored product.
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      await cubit.submit();

      expect(cubit.state.createdProductId, isA<String>());
      expect(cubit.state.props.whereType<Failure>(), isEmpty);
    });
  });

  group('duplicate submission is impossible', () {
    test('a second call while one is in flight is a no-op', () async {
      repository.manualCreate = true;
      final VendorProductCreateCubit cubit = build();
      fill(cubit);

      final Future<void> first = cubit.submit();
      expect(cubit.state.isSubmitting, isTrue);
      expect(cubit.state.canSubmit, isFalse);

      await cubit.submit();
      await cubit.submit();
      expect(repository.pendingCreateCount, 1);

      repository.completeCreate();
      await first;
      expect(repository.submittedDrafts.length, 1);
    });

    test('a submission after success is a no-op', () async {
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      await cubit.submit();

      await cubit.submit();
      await cubit.submit();

      expect(repository.submittedDrafts.length, 1);
      expect(createdIds.length, 1);
    });

    test('a submission after an UNCONFIRMED create is a no-op', () async {
      // The strongest case: the product exists and its id is unknown, so a second
      // create would either duplicate it or be refused as a duplicate code.
      repository.createResult = const VendorProductWriteUnconfirmed<String>();
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      await cubit.submit();
      expect(cubit.state.phase, VendorProductCreatePhase.unconfirmed);
      expect(cubit.state.canSubmit, isFalse);

      await cubit.submit();
      expect(repository.submittedDrafts.length, 1);
    });
  });

  group('refusals', () {
    test('a duplicate code lands on the code field', () async {
      repository.createResult = const VendorProductWriteFailure<String>(
        DuplicateFailure(field: 'productCode'),
      );
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      await cubit.submit();

      expect(
        cubit.state.fieldErrors,
        containsPair(
          VendorProductField.productCode,
          'A product with this code already exists.',
        ),
      );
      expect(cubit.state.failure, isNull);
      expect(cubit.state.phase, VendorProductCreatePhase.editing);
      expect(cubit.state.canSubmit, isTrue);
    });

    test('a duplicate barcode lands on the barcode field', () async {
      repository.createResult = const VendorProductWriteFailure<String>(
        DuplicateFailure(field: 'barcode'),
      );
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      await cubit.submit();

      expect(
        cubit.state.fieldErrors,
        containsPair(
          VendorProductField.barcode,
          'A product with this barcode already exists.',
        ),
      );
      expect(
        cubit.state.fieldErrors.containsKey(VendorProductField.productCode),
        isFalse,
      );
    });

    test('an unattributed duplicate becomes a form-level failure', () async {
      repository.createResult = const VendorProductWriteFailure<String>(
        DuplicateFailure(),
      );
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      await cubit.submit();

      expect(cubit.state.fieldErrors, isEmpty);
      expect(cubit.state.failure, const DuplicateFailure());
    });

    test('a denial is a form-level failure and names no permission', () async {
      repository.createResult = const VendorProductWriteFailure<String>(
        DeniedFailure(),
      );
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      await cubit.submit();

      expect(cubit.state.failure, const DeniedFailure());
      expect(cubit.state.phase, VendorProductCreatePhase.editing);
      // The typed values survive, so another attempt costs nothing.
      expect(cubit.state.values.productName, 'Espresso Blend 1kg');
    });

    test('a transport failure is retryable and never a denial', () async {
      repository.createResult = const VendorProductWriteFailure<String>(
        UnavailableFailure(),
      );
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      await cubit.submit();

      expect(cubit.state.failure, const UnavailableFailure());
      expect(cubit.state.canSubmit, isTrue);
    });

    test('an expired session is reported as such', () async {
      repository.createResult = const VendorProductWriteFailure<String>(
        UnauthenticatedFailure(),
      );
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      await cubit.submit();

      expect(cubit.state.failure, const UnauthenticatedFailure());
    });

    test('no refusal reports a created product', () async {
      for (final Failure failure in <Failure>[
        const DeniedFailure(),
        const UnavailableFailure(),
        const InvalidFailure(),
        const UnauthenticatedFailure(),
        const DuplicateFailure(field: 'barcode'),
      ]) {
        repository = FakeVendorProductRepository()
          ..createResult = VendorProductWriteFailure<String>(failure);
        createdIds = <String>[];
        catalogueStaleCalls = 0;

        final VendorProductCreateCubit cubit = build();
        fill(cubit);
        await cubit.submit();

        expect(cubit.state.createdProductId, isNull);
        expect(cubit.state.phase, VendorProductCreatePhase.editing);
        expect(createdIds, isEmpty);
        expect(catalogueStaleCalls, 0);
      }
    });
  });

  group('a create that succeeded whose id could not be read', () {
    test('it is never reported as a failure', () async {
      repository.createResult = const VendorProductWriteUnconfirmed<String>();
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      await cubit.submit();

      expect(cubit.state.phase, VendorProductCreatePhase.unconfirmed);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.fieldErrors, isEmpty);
    });

    test(
      'the catalogue is refreshed, and no product is navigated to',
      () async {
        repository.createResult = const VendorProductWriteUnconfirmed<String>();
        final VendorProductCreateCubit cubit = build();
        fill(cubit);
        await cubit.submit();

        expect(catalogueStaleCalls, 1);
        // No id, so nothing to open — and nothing invented to open instead.
        expect(createdIds, isEmpty);
        expect(cubit.state.createdProductId, isNull);
      },
    );
  });

  group('a mutation that succeeded and a follow-up read that did not', () {
    test('the create is still reported as a success', () async {
      // The canonical read after a create belongs to the detail cubit, so a failed
      // one cannot reach back into this state. Asserted here because it is the
      // property that matters: nothing about a create's own outcome depends on the
      // read that follows it.
      repository
        ..detailResult = unavailableProductRead()
        ..createResult = const VendorProductWriteSuccess<String>(
          createdProductUuid,
        );

      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      await cubit.submit();

      expect(cubit.state.phase, VendorProductCreatePhase.created);
      expect(cubit.state.createdProductId, createdProductUuid);
      expect(cubit.state.failure, isNull);
      // And the canonical read was still asked for.
      expect(createdIds, <String>[createdProductUuid]);
    });
  });

  group('a stale answer cannot cross a session', () {
    test('a create that lands after clear() is dropped', () async {
      repository.manualCreate = true;
      final VendorProductCreateCubit cubit = build();
      fill(cubit);

      final Future<void> pending = cubit.submit();
      expect(cubit.state.isSubmitting, isTrue);

      // The signed-in person changes.
      cubit.clear();
      expect(cubit.state, const VendorProductCreateState());

      repository.completeCreate();
      await pending;

      // The previous Vendor's create neither repopulated the form nor navigated
      // this session to their product.
      expect(cubit.state.phase, VendorProductCreatePhase.editing);
      expect(cubit.state.createdProductId, isNull);
      expect(cubit.state.values, const VendorProductFormValues());
      expect(createdIds, isEmpty);
    });

    test('a refusal that lands after clear() is dropped too', () async {
      repository.manualCreate = true;
      final VendorProductCreateCubit cubit = build();
      fill(cubit);

      final Future<void> pending = cubit.submit();
      cubit.clear();
      repository.completeCreate(
        const VendorProductWriteFailure<String>(
          DuplicateFailure(field: 'productCode'),
        ),
      );
      await pending;

      // No duplicate reported against the previous Vendor's catalogue.
      expect(cubit.state.fieldErrors, isEmpty);
      expect(cubit.state.failure, isNull);
    });

    test('an UNCONFIRMED answer after clear() is dropped', () async {
      repository.manualCreate = true;
      final VendorProductCreateCubit cubit = build();
      fill(cubit);

      final Future<void> pending = cubit.submit();
      cubit.clear();
      repository.completeCreate(const VendorProductWriteUnconfirmed<String>());
      await pending;

      expect(cubit.state.phase, VendorProductCreatePhase.editing);
      expect(catalogueStaleCalls, 0);
    });
  });

  group('clearing on a session change', () {
    test('every piece of form state goes', () async {
      repository.createResult = const VendorProductWriteFailure<String>(
        DuplicateFailure(field: 'productCode'),
      );
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      await cubit.submit();

      expect(cubit.state.fieldErrors, isNotEmpty);

      cubit.clear();

      expect(cubit.state.values, const VendorProductFormValues());
      expect(cubit.state.values.productCode, isEmpty);
      expect(cubit.state.values.description, isEmpty);
      expect(cubit.state.phase, VendorProductCreatePhase.editing);
      expect(cubit.state.fieldErrors, isEmpty);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.createdProductId, isNull);
    });

    test('a created id is cleared, so no navigation can be replayed', () async {
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      await cubit.submit();
      expect(cubit.state.createdProductId, createdProductUuid);

      cubit.clear();
      expect(cubit.state.createdProductId, isNull);
    });
  });

  group('start()', () {
    test('it returns to a blank form', () async {
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      cubit.start();

      expect(cubit.state, const VendorProductCreateState());
    });

    test('it refuses to discard a submission already in flight', () async {
      repository.manualCreate = true;
      final VendorProductCreateCubit cubit = build();
      fill(cubit);
      final Future<void> pending = cubit.submit();

      cubit.start();
      expect(cubit.state.isSubmitting, isTrue);

      repository.completeCreate();
      await pending;
      expect(cubit.state.createdProductId, createdProductUuid);
    });
  });
}
