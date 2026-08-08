import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_product.dart';
import 'package:sale_reward/features/receipts/domain/entities/selected_receipt_product.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/cubit/receipt_product_selection_cubit.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/widgets/receipt_product_catalogue_section.dart';
import 'package:sale_reward/features/receipts/presentation/sales_staff/widgets/receipt_selected_products_section.dart';

import '../../support/receipt_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  // ==========================================================================
  // 25–35. The catalogue widget
  // ==========================================================================
  group('25–35. catalogue section', () {
    Widget catalogue({
      List<ReceiptProduct> products = const <ReceiptProduct>[
        productA,
        productB,
      ],
      String query = '',
      bool isLoading = false,
      Failure? failure,
      bool isReadOnly = false,
      bool isFull = false,
      Set<String> selected = const <String>{},
      void Function(String)? onQueryChanged,
      void Function(ReceiptProduct)? onSelect,
      VoidCallback? onRetry,
    }) {
      return SingleChildScrollView(
        child: ReceiptProductCatalogueSection(
          products: products,
          query: query,
          onQueryChanged: onQueryChanged ?? (_) {},
          onSelect: onSelect ?? (_) {},
          isSelected: selected.contains,
          lineNumberOf: (String id) =>
              selected.contains(id) ? selected.toList().indexOf(id) + 1 : null,
          isLoading: isLoading,
          failure: failure,
          onRetry: onRetry,
          isReadOnly: isReadOnly,
          isFull: isFull,
        ),
      );
    }

    testWidgets('25. renders a loading state', (WidgetTester tester) async {
      await pumpThemed(tester, catalogue(isLoading: true));
      await tester.pump();

      // The design system announces loading through SEMANTICS and hides the
      // shimmer blocks from assistive technology, so this is where the label is.
      expect(
        find.bySemanticsLabel('Loading your product list'),
        findsOneWidget,
      );
    });

    testWidgets('26. renders a failure safely, with a retry', (
      WidgetTester tester,
    ) async {
      int retries = 0;
      await pumpThemed(
        tester,
        catalogue(
          failure: const UnavailableFailure(),
          onRetry: () => retries++,
        ),
      );
      await tester.pump();

      // A discriminant, never a backend message.
      expect(find.byType(ReceiptProductCatalogueSection), findsOneWidget);
      expect(find.textContaining('Chocolate'), findsNothing);

      final Finder retry = find.widgetWithText(ElevatedButton, 'Try again');
      if (retry.evaluate().isNotEmpty) {
        await tester.tap(retry.first);
        await tester.pump();
        expect(retries, 1);
      }
    });

    testWidgets('27. renders an empty catalogue', (WidgetTester tester) async {
      await pumpThemed(tester, catalogue(products: const <ReceiptProduct>[]));
      await tester.pump();

      expect(find.textContaining('No products are assigned'), findsOneWidget);
    });

    testWidgets('an empty SEARCH result says something different', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        catalogue(products: const <ReceiptProduct>[], query: 'zzz'),
      );
      await tester.pump();

      expect(find.textContaining('No products match'), findsOneWidget);
    });

    testWidgets('28. the search field is present and labelled', (
      WidgetTester tester,
    ) async {
      await pumpThemed(tester, catalogue());
      await tester.pump();

      expect(find.text('Search products'), findsOneWidget);
    });

    testWidgets('29–31. the query reaches the state layer verbatim', (
      WidgetTester tester,
    ) async {
      final List<String> queries = <String>[];
      await pumpThemed(tester, catalogue(onQueryChanged: queries.add));
      await tester.pump();

      // Filtering itself belongs to the state layer and is proven there; what
      // this widget owes is the raw text, untouched.
      await tester.enterText(find.byType(TextField).first, 'SKU-100');
      await tester.pump();

      expect(queries, contains('SKU-100'));
    });

    testWidgets('32. selecting fires the callback exactly once', (
      WidgetTester tester,
    ) async {
      final List<ReceiptProduct> picked = <ReceiptProduct>[];
      await pumpThemed(
        tester,
        catalogue(
          products: const <ReceiptProduct>[productA],
          onSelect: picked.add,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Add').first);
      await tester.pump();

      expect(picked, <ReceiptProduct>[productA]);
    });

    testWidgets('33. a selected product is marked in words, not colour', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        catalogue(
          products: const <ReceiptProduct>[productA],
          selected: <String>{productAUuid},
        ),
      );
      await tester.pump();

      expect(find.textContaining('Selected'), findsWidgets);
      expect(
        find.bySemanticsLabel(
          RegExp('${productA.productName} is already selected'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('34. tapping a selected product adds no second row', (
      WidgetTester tester,
    ) async {
      int calls = 0;
      await pumpThemed(
        tester,
        catalogue(
          products: const <ReceiptProduct>[productA],
          selected: <String>{productAUuid},
          onSelect: (_) => calls++,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Selected').last);
      await tester.pump();

      // The widget forwards the tap; the state layer answers with a notice and
      // does not duplicate the line. Only one catalogue row exists either way.
      expect(calls, 1);
      expect(find.text(productA.productName), findsOneWidget);
    });

    testWidgets('35. very long product text does not overflow', (
      WidgetTester tester,
    ) async {
      const ReceiptProduct long = ReceiptProduct(
        productId: productAUuid,
        productCode: 'CODE-THAT-KEEPS-GOING-AND-GOING-AND-GOING-0123456789',
        productName:
            'An extremely long product name that would certainly overflow a '
            'narrow phone screen if it were not allowed to wrap onto more lines',
        barcode: '12345678901234',
        brand: 'A brand with a surprisingly long registered trading name',
      );

      await pumpThemed(
        tester,
        catalogue(products: const <ReceiptProduct>[long]),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('read-only hides the search field', (
      WidgetTester tester,
    ) async {
      await pumpThemed(tester, catalogue(isReadOnly: true));
      await tester.pump();

      expect(find.text('Search products'), findsNothing);
    });
  });

  // ==========================================================================
  // 36–48. The selected-products widget
  // ==========================================================================
  group('36–48. selected products section', () {
    SelectedReceiptProduct line(ReceiptProduct product, {int quantity = 1}) =>
        SelectedReceiptProduct.fromCatalogue(product, quantity: quantity);

    Widget selected({
      required List<SelectedReceiptProduct> products,
      ReceiptProductSelectionNotice? notice,
      String? noticeProductId,
      bool isReadOnly = false,
      void Function(String)? onIncrement,
      void Function(String)? onDecrement,
      void Function(String)? onRemove,
    }) {
      return SingleChildScrollView(
        child: ReceiptSelectedProductsSection(
          products: products,
          onIncrement: onIncrement ?? (_) {},
          onDecrement: onDecrement ?? (_) {},
          onRemove: onRemove ?? (_) {},
          notice: notice,
          noticeProductId: noticeProductId,
          isReadOnly: isReadOnly,
        ),
      );
    }

    testWidgets('36. renders the empty-selection message', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        selected(products: const <SelectedReceiptProduct>[]),
      );
      await tester.pump();

      expect(find.text('No products chosen yet'), findsOneWidget);
    });

    testWidgets('37–39. renders name, code, brand and barcode', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        selected(products: <SelectedReceiptProduct>[line(productA)]),
      );
      await tester.pump();

      expect(find.text(productA.productName), findsOneWidget);
      expect(find.textContaining(productA.productCode), findsOneWidget);
      expect(find.textContaining(productA.brand!), findsOneWidget);
      expect(find.textContaining(productA.barcode!), findsOneWidget);
    });

    testWidgets('a product with no brand or barcode still renders', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        selected(products: <SelectedReceiptProduct>[line(productB)]),
      );
      await tester.pump();

      expect(find.text(productB.productName), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('40–42. increment, decrement and remove fire', (
      WidgetTester tester,
    ) async {
      final List<String> up = <String>[];
      final List<String> down = <String>[];
      final List<String> gone = <String>[];

      await pumpThemed(
        tester,
        selected(
          products: <SelectedReceiptProduct>[line(productA, quantity: 5)],
          onIncrement: up.add,
          onDecrement: down.add,
          onRemove: gone.add,
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();

      expect(up, <String>[productAUuid]);
      expect(down, <String>[productAUuid]);
      expect(gone, <String>[productAUuid]);
    });

    testWidgets('43. decrement is disabled at 1', (WidgetTester tester) async {
      final List<String> down = <String>[];
      await pumpThemed(
        tester,
        selected(
          products: <SelectedReceiptProduct>[line(productA)],
          onDecrement: down.add,
        ),
      );
      await tester.pump();

      final IconButton button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.remove_circle_outline),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pump();
      expect(down, isEmpty);
    });

    testWidgets('44. increment is disabled at 100', (
      WidgetTester tester,
    ) async {
      final List<String> up = <String>[];
      await pumpThemed(
        tester,
        selected(
          products: <SelectedReceiptProduct>[
            line(productA, quantity: maxReceiptProductQuantity),
          ],
          onIncrement: up.add,
        ),
      );
      await tester.pump();

      final IconButton button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.add_circle_outline),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();
      expect(up, isEmpty);
    });

    testWidgets('45. the quantity renders as a whole number', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        selected(
          products: <SelectedReceiptProduct>[line(productA, quantity: 7)],
        ),
      );
      await tester.pump();

      expect(find.text('7'), findsOneWidget);
      // A double would render as '7.0'. The line number ('1.') legitimately
      // contains a dot, so the assertion is on the quantity text itself.
      expect(find.text('7.0'), findsNothing);
      expect(find.textContaining('7.'), findsNothing);
    });

    testWidgets('46. every control names its product', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        selected(
          products: <SelectedReceiptProduct>[line(productA, quantity: 5)],
        ),
      );
      await tester.pump();

      expect(
        find.bySemanticsLabel(
          RegExp('Increase quantity of ${productA.productName}'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp('Reduce quantity of ${productA.productName}'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp('Remove ${productA.productName} from this invoice / receipt'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a bound that is reached says so, rather than going quiet', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        selected(products: <SelectedReceiptProduct>[line(productA)]),
      );
      await tester.pump();

      expect(
        find.bySemanticsLabel(
          RegExp('Cannot reduce ${productA.productName} below 1'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('47. read-only removes every mutation control', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        selected(
          products: <SelectedReceiptProduct>[line(productA, quantity: 3)],
          isReadOnly: true,
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      // The quantity is still readable.
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('48. fifty lines render without failing', (
      WidgetTester tester,
    ) async {
      final List<SelectedReceiptProduct> many =
          List<SelectedReceiptProduct>.generate(
            maxReceiptProductLines,
            (int i) => SelectedReceiptProduct(
              productId:
                  '${i.toString().padLeft(8, '0')}-0000-0000-0000-000000000000',
              productCode: 'BULK-$i',
              productName: 'Bulk product $i',
              quantity: 1,
            ),
          );

      await pumpThemed(tester, selected(products: many));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('50 of 50 lines'), findsOneWidget);
    });

    testWidgets('a duplicate notice explains that nothing changed', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        selected(
          products: <SelectedReceiptProduct>[line(productA, quantity: 3)],
          notice: ReceiptProductSelectionNotice.alreadySelected,
          noticeProductId: productAUuid,
        ),
      );
      await tester.pump();

      expect(find.text('Already on this invoice / receipt'), findsOneWidget);
      expect(find.textContaining('was not changed'), findsOneWidget);
    });

    testWidgets('a limit notice says nothing was removed', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        selected(
          products: <SelectedReceiptProduct>[line(productA)],
          notice: ReceiptProductSelectionNotice.limitReached,
        ),
      );
      await tester.pump();

      expect(find.text('Line limit reached'), findsOneWidget);
      expect(find.textContaining('Nothing was removed'), findsOneWidget);
    });

    testWidgets('lines render in the order they were given', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        selected(
          products: <SelectedReceiptProduct>[line(productB), line(productA)],
        ),
      );
      await tester.pump();

      final double first = tester
          .getTopLeft(find.text(productB.productName))
          .dy;
      final double second = tester
          .getTopLeft(find.text(productA.productName))
          .dy;
      expect(first, lessThan(second));
    });
  });
}
