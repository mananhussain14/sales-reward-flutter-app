import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_product.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_product_selection.dart';
import 'package:sale_reward/features/receipts/domain/entities/selected_receipt_product.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_result.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/cubit/receipt_product_selection_cubit.dart';

import '../../support/receipt_fakes.dart';

void main() {
  late FakeReceiptRepository repository;

  ReceiptProductSelectionCubit build() =>
      ReceiptProductSelectionCubit(repository);

  /// A catalogue row that is not `productA`/`productB`, for the bulk cases.
  ReceiptProduct bulk(int i) => ReceiptProduct(
    productId: '${i.toString().padLeft(8, '0')}-0000-0000-0000-000000000000',
    productCode: 'BULK-$i',
    productName: 'Bulk product $i',
  );

  setUp(() {
    repository = FakeReceiptRepository();
  });

  group('1–3. catalogue phases', () {
    test('1. starts in initial and reads nothing until asked', () {
      final ReceiptProductSelectionCubit cubit = build();

      expect(cubit.state.phase, ReceiptProductSelectionPhase.initial);
      expect(cubit.state.catalogue, isEmpty);
      expect(repository.receiptProductsCallCount, 0);
    });

    test('2. loads the catalogue with zero arguments', () async {
      final ReceiptProductSelectionCubit cubit = build();

      await cubit.loadCatalogue();

      expect(cubit.state.phase, ReceiptProductSelectionPhase.ready);
      expect(cubit.state.catalogue, <ReceiptProduct>[productA, productB]);
      expect(repository.receiptProductsCallCount, 1);
    });

    test('3. a failed read is its own phase and keeps the selection', () async {
      final ReceiptProductSelectionCubit cubit = build();
      await cubit.loadCatalogue();
      cubit.select(productA);

      repository.productsResult =
          const ReceiptReadFailure<List<ReceiptProduct>>(UnavailableFailure());
      await cubit.loadCatalogue();

      expect(cubit.state.phase, ReceiptProductSelectionPhase.failed);
      expect(cubit.state.failure, isA<UnavailableFailure>());
      // The read failed; the products already chosen are still chosen.
      expect(cubit.state.selectedCount, 1);
    });

    test('an empty catalogue is a real answer, not a failure', () async {
      repository.productsResult =
          const ReceiptReadSuccess<List<ReceiptProduct>>(<ReceiptProduct>[]);
      final ReceiptProductSelectionCubit cubit = build();

      await cubit.loadCatalogue();

      expect(cubit.state.phase, ReceiptProductSelectionPhase.ready);
      expect(cubit.state.isCatalogueEmpty, isTrue);
      expect(cubit.state.hasFailed, isFalse);
    });

    test('a concurrent load does not issue a second read', () async {
      final ReceiptProductSelectionCubit cubit = build();

      await Future.wait(<Future<void>>[
        cubit.loadCatalogue(),
        cubit.loadCatalogue(),
      ]);

      expect(repository.receiptProductsCallCount, 1);
    });
  });

  group('4–9. local search', () {
    late ReceiptProductSelectionCubit cubit;

    setUp(() async {
      cubit = build();
      await cubit.loadCatalogue();
    });

    test('4. matches on product name', () {
      cubit.search('chocolate');
      expect(cubit.state.visibleCatalogue, <ReceiptProduct>[productA]);
    });

    test('5. matches on product code', () {
      cubit.search('SKU-100');
      expect(cubit.state.visibleCatalogue, <ReceiptProduct>[productA]);
    });

    test('6. matches on barcode', () {
      cubit.search('01234567');
      expect(cubit.state.visibleCatalogue, <ReceiptProduct>[productA]);
    });

    test('7. matching is case-insensitive', () {
      cubit.search('CHOCOLATE');
      expect(cubit.state.visibleCatalogue, <ReceiptProduct>[productA]);
    });

    test('8. surrounding whitespace is ignored', () {
      cubit.search('   chocolate   ');
      expect(cubit.state.visibleCatalogue, <ReceiptProduct>[productA]);
      // The raw text is preserved, so the field never fights the typist.
      expect(cubit.state.query, '   chocolate   ');
    });

    test('9. a search that matches nothing is its own state', () {
      cubit.search('nothing-matches-this');

      expect(cubit.state.visibleCatalogue, isEmpty);
      expect(cubit.state.hasNoSearchResults, isTrue);
      // Distinct from an empty catalogue: the remedy is different.
      expect(cubit.state.isCatalogueEmpty, isFalse);
    });

    test('searching never touches the network', () {
      final int before = repository.receiptProductsCallCount;
      cubit.search('a');
      cubit.search('ab');
      cubit.search('abc');
      expect(repository.receiptProductsCallCount, before);
    });
  });

  group('10–14. selecting, refusing and removing', () {
    late ReceiptProductSelectionCubit cubit;

    setUp(() async {
      cubit = build();
      await cubit.loadCatalogue();
    });

    test('10. selects one product at quantity 1', () {
      cubit.select(productA);

      expect(cubit.state.selectedCount, 1);
      expect(cubit.state.selectedProducts.single.productId, productAUuid);
      expect(cubit.state.selectedProducts.single.quantity, 1);
      expect(cubit.state.isSelected(productAUuid), isTrue);
    });

    test('11. a duplicate selection adds no second line', () {
      cubit.select(productA);
      cubit.select(productA);

      expect(cubit.state.selectedCount, 1);
      expect(cubit.state.notice, ReceiptProductSelectionNotice.alreadySelected);
      expect(cubit.state.noticeProductId, productAUuid);
    });

    test('12. a duplicate selection does not change the quantity', () {
      cubit.select(productA);
      cubit.increment(productAUuid);
      cubit.increment(productAUuid);
      expect(cubit.state.selectedProducts.single.quantity, 3);

      cubit.select(productA);

      // Silently adding one here would submit a number nobody typed.
      expect(cubit.state.selectedProducts.single.quantity, 3);
    });

    test('13. a duplicate selection preserves ordering', () {
      cubit.select(productA);
      cubit.select(productB);
      cubit.select(productA);

      expect(
        cubit.state.selectedProducts
            .map((SelectedReceiptProduct p) => p.productId)
            .toList(),
        <String>[productAUuid, productBUuid],
      );
    });

    test('14. removes a selected product', () {
      cubit.select(productA);
      cubit.select(productB);

      cubit.remove(productAUuid);

      expect(cubit.state.selectedCount, 1);
      expect(cubit.state.selectedProducts.single.productId, productBUuid);
      expect(cubit.state.isSelected(productAUuid), isFalse);
    });
  });

  group('15–18. quantity bounds', () {
    late ReceiptProductSelectionCubit cubit;

    setUp(() async {
      cubit = build();
      await cubit.loadCatalogue();
      cubit.select(productA);
    });

    test('15. increments', () {
      cubit.increment(productAUuid);
      expect(cubit.state.selectedProducts.single.quantity, 2);
    });

    test('16. decrements', () {
      cubit.increment(productAUuid);
      cubit.decrement(productAUuid);
      expect(cubit.state.selectedProducts.single.quantity, 1);
    });

    test('17. cannot fall below 1', () {
      cubit.decrement(productAUuid);
      cubit.decrement(productAUuid);

      expect(cubit.state.selectedProducts.single.quantity, 1);
      // Decrementing never removes a line: that is a separate, explicit act.
      expect(cubit.state.selectedCount, 1);
    });

    test('18. cannot exceed 100', () {
      cubit.setQuantity(productAUuid, maxReceiptProductQuantity);
      cubit.increment(productAUuid);

      expect(cubit.state.selectedProducts.single.quantity, 100);
    });

    test('an out-of-range direct quantity is ignored, never clamped', () {
      cubit.setQuantity(productAUuid, 250);
      expect(cubit.state.selectedProducts.single.quantity, 1);

      cubit.setQuantity(productAUuid, 0);
      expect(cubit.state.selectedProducts.single.quantity, 1);
    });

    test('quantity stays an int', () {
      cubit.increment(productAUuid);
      expect(cubit.state.selectedProducts.single.quantity, isA<int>());
    });
  });

  group('19–20. the fifty-line ceiling', () {
    test('19. fifty products can be selected', () async {
      final List<ReceiptProduct> many = List<ReceiptProduct>.generate(
        maxReceiptProductLines,
        bulk,
      );
      repository.productsResult = ReceiptReadSuccess<List<ReceiptProduct>>(
        many,
      );
      final ReceiptProductSelectionCubit cubit = build();
      await cubit.loadCatalogue();

      for (final ReceiptProduct product in many) {
        cubit.select(product);
      }

      expect(cubit.state.selectedCount, 50);
      expect(cubit.state.isFull, isTrue);
      expect(cubit.state.problem, isNull);
    });

    test('20. the fifty-first is refused and nothing is evicted', () async {
      final List<ReceiptProduct> many = List<ReceiptProduct>.generate(
        maxReceiptProductLines + 1,
        bulk,
      );
      repository.productsResult = ReceiptReadSuccess<List<ReceiptProduct>>(
        many,
      );
      final ReceiptProductSelectionCubit cubit = build();
      await cubit.loadCatalogue();

      for (final ReceiptProduct product in many) {
        cubit.select(product);
      }

      expect(cubit.state.selectedCount, 50);
      expect(cubit.state.notice, ReceiptProductSelectionNotice.limitReached);
      // The first fifty are untouched, in order.
      expect(
        cubit.state.selectedProducts.first.productId,
        many.first.productId,
      );
      expect(cubit.state.selectedProducts.last.productId, many[49].productId);
    });
  });

  group('21–24. ordering and the catalogue door', () {
    late ReceiptProductSelectionCubit cubit;

    setUp(() async {
      cubit = build();
      await cubit.loadCatalogue();
    });

    test('21. a search change never removes a selected product', () {
      cubit.select(productA);
      cubit.select(productB);

      cubit.search('nothing-matches-this');

      expect(cubit.state.visibleCatalogue, isEmpty);
      expect(cubit.state.selectedCount, 2);
    });

    test('22. a quantity change does not reorder', () {
      cubit.select(productA);
      cubit.select(productB);

      cubit.increment(productAUuid);
      cubit.increment(productBUuid);
      cubit.decrement(productAUuid);

      expect(
        cubit.state.selectedProducts
            .map((SelectedReceiptProduct p) => p.productId)
            .toList(),
        <String>[productAUuid, productBUuid],
      );
    });

    test('23. removal preserves the relative order of the rest', () async {
      final List<ReceiptProduct> three = <ReceiptProduct>[
        bulk(1),
        bulk(2),
        bulk(3),
      ];
      repository.productsResult = ReceiptReadSuccess<List<ReceiptProduct>>(
        three,
      );
      final ReceiptProductSelectionCubit fresh = build();
      await fresh.loadCatalogue();
      for (final ReceiptProduct p in three) {
        fresh.select(p);
      }

      fresh.remove(three[1].productId);

      expect(
        fresh.state.selectedProducts
            .map((SelectedReceiptProduct p) => p.productId)
            .toList(),
        <String>[three.first.productId, three.last.productId],
      );
    });

    test(
      '24. the cubit exposes no way to select anything but a catalogue row',
      () {
        // `select` takes a ReceiptProduct, which only the catalogue read
        // produces. There is no method accepting an id, a name or free text —
        // so an unauthorized product cannot be expressed here at all.
        cubit.remove('99999999-9999-9999-9999-999999999999');
        cubit.increment('99999999-9999-9999-9999-999999999999');
        cubit.setQuantity('99999999-9999-9999-9999-999999999999', 5);

        expect(cubit.state.selectedCount, 0);
      },
    );
  });

  group('validation and the read-only capability', () {
    test('an empty selection is not submittable', () async {
      final ReceiptProductSelectionCubit cubit = build();
      await cubit.loadCatalogue();

      expect(
        cubit.state.problem,
        ReceiptProductSelectionProblem.noProductsSelected,
      );
      expect(cubit.state.isSubmittable, isFalse);
    });

    test('one product makes it submittable', () async {
      final ReceiptProductSelectionCubit cubit = build();
      await cubit.loadCatalogue();
      cubit.select(productA);

      expect(cubit.state.problem, isNull);
      expect(cubit.state.isSubmittable, isTrue);
    });

    test('read-only freezes every mutation', () async {
      final ReceiptProductSelectionCubit cubit = build();
      await cubit.loadCatalogue();
      cubit.select(productA);
      cubit.setReadOnly(readOnly: true);

      cubit.select(productB);
      cubit.increment(productAUuid);
      cubit.decrement(productAUuid);
      cubit.setQuantity(productAUuid, 9);
      cubit.remove(productAUuid);

      expect(cubit.state.selectedCount, 1);
      expect(cubit.state.selectedProducts.single.quantity, 1);
      expect(cubit.state.isSubmittable, isFalse);
    });

    test('a notice can be dismissed once shown', () async {
      final ReceiptProductSelectionCubit cubit = build();
      await cubit.loadCatalogue();
      cubit.select(productA);
      cubit.select(productA);
      expect(cubit.state.notice, isNotNull);

      cubit.dismissNotice();

      expect(cubit.state.notice, isNull);
      expect(cubit.state.noticeProductId, isNull);
    });
  });
}
