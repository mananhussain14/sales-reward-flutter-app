import '../../domain/entities/receipt_product_selection.dart';
import '../../domain/entities/selected_receipt_product.dart';

/// The **two** keys one `p_lines` element may carry, named exactly once each.
///
/// There is deliberately no constant here for a product name, product code,
/// barcode, brand, status, line number, Vendor id, Retailer id, shop id, staff
/// id, actor id, campaign field or reward field. The absence of a name is what
/// makes one impossible to express at this boundary — the same reason
/// `receipt_confirmation_request_body.dart` names exactly ten parameters and no
/// eleventh.
const String productLineIdKey = 'product_id';
const String productLineQuantityKey = 'quantity';

/// Every key this client is permitted to emit inside a product line.
///
/// Exported so a test can assert the whole vocabulary at once rather than
/// whichever subset a particular selection happened to produce.
const Set<String> receiptProductLineKeys = <String>{
  productLineIdKey,
  productLineQuantityKey,
};

/// Encodes a selection into the JSON array `p_lines` expects.
///
/// ```json
/// [ { "product_id": "…", "quantity": 2 } ]
/// ```
///
/// ## Order is the line numbering
///
/// The database derives `line_number` from array position, so this preserves
/// [ReceiptProductSelection.products] order exactly and sorts nothing. A
/// reordered array is a different proposal, and the RPC answers `CONFLICT` for
/// one — which is correct, not a bug to smooth over here.
///
/// ## The quantity stays a JSON integer
///
/// `jsonb_typeof(elem -> 'quantity') <> 'number'` is refused, and so is a value
/// with a fractional part. An `int` is emitted, never a `double` and never a
/// string, so neither refusal can be reached from this client.
///
/// ## No snapshot text is emitted
///
/// [SelectedReceiptProduct] carries a name, code, barcode and brand for the
/// person reading the list. None of them appears below. The database copies
/// every snapshot out of `vendor_products` itself and refuses a row whose
/// snapshot does not match, so a client-supplied one could not survive even if
/// it were sent.
List<Map<String, Object>> buildReceiptProductLines(
  ReceiptProductSelection selection,
) {
  return selection.products
      .map(
        (SelectedReceiptProduct product) => <String, Object>{
          productLineIdKey: product.productId,
          productLineQuantityKey: product.quantity,
        },
      )
      .toList(growable: false);
}
