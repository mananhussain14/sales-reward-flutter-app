import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_edit.dart';
import 'package:sale_reward/features/products/domain/entities/vendor_product_field.dart';
import 'package:sale_reward/features/products/domain/repositories/vendor_product_write_result.dart';
import 'package:sale_reward/features/products/presentation/vendor/cubit/vendor_product_edit_cubit.dart';
import 'package:sale_reward/features/products/presentation/vendor/cubit/vendor_product_write_notice.dart';

import '../../support/vendor_product_fakes.dart';

/// The edit form and its one write.
void main() {
  late FakeVendorProductRepository repository;
  late List<VendorProductWriteNotice> written;

  VendorProductEditCubit build() =>
      VendorProductEditCubit(repository, onProductWritten: written.add);

  setUp(() {
    repository = FakeVendorProductRepository();
    written = <VendorProductWriteNotice>[];
  });

  group('seeding from the canonical product', () {
    test('the four editable values come from the read row', () {
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);

      expect(cubit.state.productId, espressoProductUuid);
      expect(cubit.state.values.productName, 'Espresso Blend 1kg');
      expect(cubit.state.values.barcode, '5012345678900');
      expect(cubit.state.values.brand, 'Harvest Roasters');
      expect(
        cubit.state.values.description,
        'A dark roast blend for espresso machines.',
      );
      expect(cubit.state.phase, VendorProductEditPhase.editing);
      expect(cubit.state.isSeeded, isTrue);
    });

    test('the product code is held apart from the editable values', () {
      // Read-only context: it is on screen so a person knows which product they are
      // changing, and there is nowhere in the editable set for it to be submitted
      // from.
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);

      expect(cubit.state.productCode, 'ESP-1000');
      expect(cubit.state.values.productCode, isEmpty);
    });

    test('a null optional seeds an empty control, not a placeholder phrase', () {
      // "Not recorded" is how a null is rendered on the detail screen; it must never
      // become a value in a form that is then saved back.
      final VendorProductEditCubit cubit = build()..seed(decafDetail);

      expect(cubit.state.values.barcode, isEmpty);
      expect(cubit.state.values.brand, isEmpty);
      expect(cubit.state.values.description, isEmpty);
      expect(cubit.state.values.barcode, isNot('Not recorded'));
    });

    test('an inactive product is editable, and no status is seeded', () {
      // An INACTIVE product stays fully editable; the edit RPC never writes status.
      final VendorProductEditCubit cubit = build()..seed(retiredDetail);

      expect(cubit.state.canSubmit, isTrue);
      expect(cubit.state.productCode, 'RET-3000');
    });

    test('re-seeding the same product does not discard typed edits', () {
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      cubit.productNameChanged('Half-typed nam');

      cubit.seed(espressoDetail);

      expect(cubit.state.values.productName, 'Half-typed nam');
    });

    test('seeding a different product starts a fresh form', () {
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      cubit.productNameChanged('Half-typed');

      cubit.seed(decafDetail);

      expect(cubit.state.productId, decafProductUuid);
      expect(cubit.state.values.productName, 'Decaf Ground 500g');
      expect(cubit.state.productCode, 'DEC-2000');
    });

    test('the same product re-seeds after clear()', () {
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      cubit.clear();
      expect(cubit.state.isSeeded, isFalse);

      cubit.seed(espressoDetail);
      expect(cubit.state.values.productName, 'Espresso Blend 1kg');
    });

    test('nothing is written on seeding', () {
      build().seed(espressoDetail);
      expect(repository.submittedEdits, isEmpty);
    });
  });

  group('validation', () {
    test('an emptied name is refused and nothing is sent', () async {
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      cubit.productNameChanged('   ');
      await cubit.submit();

      expect(repository.submittedEdits, isEmpty);
      expect(
        cubit.state.fieldErrors,
        containsPair(VendorProductField.productName, 'Enter a product name.'),
      );
      expect(cubit.state.phase, VendorProductEditPhase.editing);
    });

    test('a bad barcode is refused and nothing is sent', () async {
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      cubit.barcodeChanged('12345');
      await cubit.submit();

      expect(repository.submittedEdits, isEmpty);
      expect(cubit.state.fieldErrors, contains(VendorProductField.barcode));
    });

    test('the product code is never validated, whatever it holds', () async {
      // It cannot be sent, so a rule about it would have no subject — and any
      // message would describe a field nobody can change.
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      await cubit.submit();

      expect(
        cubit.state.fieldErrors.containsKey(VendorProductField.productCode),
        isFalse,
      );
      expect(repository.submittedEdits.length, 1);
    });

    test('nothing is submitted before a product is seeded', () async {
      final VendorProductEditCubit cubit = build();
      await cubit.submit();
      expect(repository.submittedEdits, isEmpty);
    });
  });

  group('a valid save', () {
    test('sends the id and the four normalized values', () async {
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      cubit
        ..productNameChanged('  Espresso   Blend 1kg (new)  ')
        ..barcodeChanged(' 501 234-567-8917 ')
        ..brandChanged('  Harvest  Roasters ')
        ..descriptionChanged('  Two  spaces\n\nkept  ');
      await cubit.submit();

      expect(repository.submittedEdits.length, 1);
      final ({String productId, VendorProductEdit edit}) sent =
          repository.submittedEdits.single;

      expect(sent.productId, espressoProductUuid);
      expect(sent.edit.productName, 'Espresso Blend 1kg (new)');
      expect(sent.edit.barcode, '5012345678917');
      expect(sent.edit.brand, 'Harvest Roasters');
      // Trim only, so the internal double space and the blank line survive.
      expect(sent.edit.description, 'Two  spaces\n\nkept');
    });

    test('the product code is never part of the request', () async {
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      await cubit.submit();

      final VendorProductEdit edit = repository.submittedEdits.single.edit;
      // The type has no field for it, and none of the four carries it.
      expect(edit.productName, isNot('ESP-1000'));
      expect(edit.barcode, isNot('ESP-1000'));
      expect(edit.brand, isNot('ESP-1000'));
      expect(edit.description, isNot('ESP-1000'));
    });

    test('no status value is part of the request either', () async {
      final VendorProductEditCubit cubit = build()..seed(retiredDetail);
      await cubit.submit();

      final VendorProductEdit edit = repository.submittedEdits.single.edit;
      for (final String? value in <String?>[
        edit.productName,
        edit.barcode,
        edit.brand,
        edit.description,
      ]) {
        expect(value, isNot('ACTIVE'));
        expect(value, isNot('INACTIVE'));
      }
    });

    test('cleared optionals travel as null', () async {
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      cubit
        ..barcodeChanged('')
        ..brandChanged('  ')
        ..descriptionChanged('\n\n');
      await cubit.submit();

      final VendorProductEdit edit = repository.submittedEdits.single.edit;
      expect(edit.barcode, isNull);
      expect(edit.brand, isNull);
      expect(edit.description, isNull);
      // The required value is untouched.
      expect(edit.productName, 'Espresso Blend 1kg');
    });

    test('all four values are sent even when only one changed', () async {
      // The RPC writes all four, so an omitted one would clear a stored value
      // nobody asked to clear. This is a whole-record update, not a patch.
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      cubit.productNameChanged('Renamed');
      await cubit.submit();

      final VendorProductEdit edit = repository.submittedEdits.single.edit;
      expect(edit.productName, 'Renamed');
      expect(edit.barcode, '5012345678900');
      expect(edit.brand, 'Harvest Roasters');
      expect(edit.description, 'A dark roast blend for espresso machines.');
    });

    test('it reaches `saved` and asks for the canonical re-read', () async {
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      cubit.productNameChanged('Renamed');
      await cubit.submit();

      expect(cubit.state.phase, VendorProductEditPhase.saved);
      expect(cubit.state.failure, isNull);
      expect(written, <VendorProductWriteNotice>[
        VendorProductWriteNotice.updated,
      ]);
    });

    test('a save that changed nothing is a plain success', () async {
      // A no-op is a silent success in SQL, deliberately indistinguishable from a
      // real change, so nothing here tries to tell them apart.
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      await cubit.submit();

      expect(repository.submittedEdits.length, 1);
      expect(cubit.state.phase, VendorProductEditPhase.saved);
      expect(written, <VendorProductWriteNotice>[
        VendorProductWriteNotice.updated,
      ]);
    });

    test('a whitespace-only difference is submitted and succeeds', () async {
      // The backend normalizes first, so this is a no-op there too — and Save is
      // never disabled on the strength of a local comparison, which is the one place
      // a normalization difference could cost somebody their change.
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      cubit.productNameChanged('  Espresso   Blend 1kg  ');
      expect(cubit.state.canSubmit, isTrue);
      await cubit.submit();

      expect(
        repository.submittedEdits.single.edit.productName,
        'Espresso Blend 1kg',
      );
      expect(cubit.state.phase, VendorProductEditPhase.saved);
    });
  });

  group('duplicate submission is impossible', () {
    test('a second call while one is in flight is a no-op', () async {
      repository.manualUpdate = true;
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);

      final Future<void> first = cubit.submit();
      expect(cubit.state.isSubmitting, isTrue);
      expect(cubit.state.canSubmit, isFalse);

      await cubit.submit();
      await cubit.submit();
      expect(repository.pendingUpdateCount, 1);

      repository.completeUpdate();
      await first;
      expect(repository.submittedEdits.length, 1);
      expect(written.length, 1);
    });

    test('a submission after a save is a no-op', () async {
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      await cubit.submit();
      await cubit.submit();

      expect(repository.submittedEdits.length, 1);
      expect(written.length, 1);
    });

    test('editing is ignored once a save has settled', () async {
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      await cubit.submit();

      cubit.productNameChanged('Too late');
      expect(cubit.state.values.productName, isNot('Too late'));
    });
  });

  group('refusals', () {
    test('a duplicate barcode lands on the barcode field', () async {
      repository.updateResult = const VendorProductWriteFailure<void>(
        DuplicateFailure(field: 'barcode'),
      );
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      cubit.barcodeChanged('5012345678917');
      await cubit.submit();

      expect(
        cubit.state.fieldErrors,
        containsPair(
          VendorProductField.barcode,
          'A product with this barcode already exists.',
        ),
      );
      expect(cubit.state.phase, VendorProductEditPhase.editing);
      expect(cubit.state.canSubmit, isTrue);
      // Nothing was written, so no re-read is requested.
      expect(written, isEmpty);
    });

    test('the typed values survive a refusal', () async {
      // A refused edit rolls back completely — including a name change that
      // accompanied a duplicate barcode — so another attempt costs nothing.
      repository.updateResult = const VendorProductWriteFailure<void>(
        DuplicateFailure(field: 'barcode'),
      );
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      cubit
        ..productNameChanged('Renamed')
        ..barcodeChanged('5012345678917');
      await cubit.submit();

      expect(cubit.state.values.productName, 'Renamed');
      expect(cubit.state.values.barcode, '5012345678917');
      expect(cubit.state.productCode, 'ESP-1000');
    });

    test('a denial is a form-level failure naming no permission', () async {
      repository.updateResult = const VendorProductWriteFailure<void>(
        DeniedFailure(),
      );
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      await cubit.submit();

      expect(cubit.state.failure, const DeniedFailure());
      expect(cubit.state.fieldErrors, isEmpty);
      expect(written, isEmpty);
    });

    test('an unknown or foreign product reads as the same denial', () async {
      // Byte-identical on the backend, and this client does not tell them apart.
      repository.updateResult = const VendorProductWriteFailure<void>(
        DeniedFailure(),
      );
      final VendorProductEditCubit cubit = build()..seed(unassignedDetail);
      await cubit.submit();

      expect(cubit.state.failure, const DeniedFailure());
    });

    test('a transport failure is retryable', () async {
      repository.updateResult = const VendorProductWriteFailure<void>(
        UnavailableFailure(),
      );
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      await cubit.submit();

      expect(cubit.state.failure, const UnavailableFailure());
      expect(cubit.state.canSubmit, isTrue);
    });

    test(
      'an invalid value the backend refused is a generic form failure',
      () async {
        repository.updateResult = const VendorProductWriteFailure<void>(
          InvalidFailure(),
        );
        final VendorProductEditCubit cubit = build()..seed(espressoDetail);
        await cubit.submit();

        expect(cubit.state.failure, const InvalidFailure());
        expect(cubit.state.fieldErrors, isEmpty);
      },
    );

    test('no refusal requests a canonical re-read', () async {
      for (final Failure failure in <Failure>[
        const DeniedFailure(),
        const UnavailableFailure(),
        const InvalidFailure(),
        const UnauthenticatedFailure(),
      ]) {
        repository = FakeVendorProductRepository()
          ..updateResult = VendorProductWriteFailure<void>(failure);
        written = <VendorProductWriteNotice>[];

        final VendorProductEditCubit cubit = build()..seed(espressoDetail);
        await cubit.submit();

        expect(written, isEmpty);
        expect(cubit.state.phase, VendorProductEditPhase.editing);
      }
    });
  });

  group('a save that landed with an unreadable answer', () {
    test('it is a success, with its own notice', () async {
      repository.updateResult = const VendorProductWriteUnconfirmed<void>();
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      await cubit.submit();

      // Never a failure: a 2xx means the row and its audit row are committed.
      expect(cubit.state.phase, VendorProductEditPhase.saved);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.fieldErrors, isEmpty);
      expect(written, <VendorProductWriteNotice>[
        VendorProductWriteNotice.updateUnconfirmed,
      ]);
    });

    test('the canonical re-read is still requested', () async {
      // It is the authority on what the product now looks like, which is the whole
      // point of not claiming a save this client cannot vouch for.
      repository.updateResult = const VendorProductWriteUnconfirmed<void>();
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      await cubit.submit();

      expect(written.length, 1);
    });
  });

  group('a stale answer cannot cross a session', () {
    test('a save that lands after clear() is dropped', () async {
      repository.manualUpdate = true;
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);

      final Future<void> pending = cubit.submit();
      cubit.clear();

      repository.completeUpdate();
      await pending;

      expect(cubit.state.phase, VendorProductEditPhase.initial);
      expect(cubit.state.isSeeded, isFalse);
      // No acknowledgement, and no re-read, into the new session.
      expect(written, isEmpty);
    });

    test('a refusal that lands after clear() is dropped', () async {
      repository.manualUpdate = true;
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);

      final Future<void> pending = cubit.submit();
      cubit.clear();
      repository.completeUpdate(
        const VendorProductWriteFailure<void>(
          DuplicateFailure(field: 'barcode'),
        ),
      );
      await pending;

      expect(cubit.state.fieldErrors, isEmpty);
      expect(cubit.state.failure, isNull);
    });

    test('a save that lands after a re-seed is dropped', () async {
      // The same guard covers a second product being opened mid-flight.
      repository.manualUpdate = true;
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      final Future<void> pending = cubit.submit();

      cubit.clear();
      cubit.seed(decafDetail);

      repository.completeUpdate();
      await pending;

      expect(cubit.state.productId, decafProductUuid);
      expect(cubit.state.phase, VendorProductEditPhase.editing);
      expect(written, isEmpty);
    });
  });

  group('clearing on a session change', () {
    test('every piece of form state goes', () async {
      repository.updateResult = const VendorProductWriteFailure<void>(
        DuplicateFailure(field: 'barcode'),
      );
      final VendorProductEditCubit cubit = build()..seed(espressoDetail);
      cubit.productNameChanged('Renamed');
      await cubit.submit();
      expect(cubit.state.fieldErrors, isNotEmpty);

      cubit.clear();

      expect(cubit.state.productId, isNull);
      expect(cubit.state.productCode, isEmpty);
      expect(cubit.state.values.productName, isEmpty);
      expect(cubit.state.values.barcode, isEmpty);
      expect(cubit.state.values.brand, isEmpty);
      expect(cubit.state.values.description, isEmpty);
      expect(cubit.state.phase, VendorProductEditPhase.initial);
      expect(cubit.state.fieldErrors, isEmpty);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.canSubmit, isFalse);
    });
  });
}
