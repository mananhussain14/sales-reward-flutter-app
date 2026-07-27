import '../../../../core/parsing/rpc_row.dart';
import '../../domain/entities/retailer_assigned_product.dart';

/// Parses `list_retailer_assigned_products()`.
///
/// ## The whole list, or none of it
///
/// One malformed row fails the read. Skipping bad rows would silently
/// under-report what a Retailer is entitled to stock, and a catalogue quietly
/// short by one product is worse than one that honestly failed to load.
///
/// ## Which malformations are rejected, and which are tolerated
///
/// Rejected:
///
/// * a body that is not a list, or a row that is not an object;
/// * a missing, null, blank or non-string `product_code` or `product_name`;
/// * a missing, null, blank or non-string `assignment_status`;
/// * a **non-string** `barcode`, `brand` or `description` — a numeric barcode is
///   the realistic case, and it is refused rather than stringified, because a
///   number that has been through a JSON parser has already lost its leading
///   zeros and a GTIN with a leading zero is a different barcode.
///
/// Tolerated:
///
/// * an **empty list** → nothing currently assigned. A real answer.
/// * an **unrecognized extra key** → ignored; the contract is additive.
/// * a **null `barcode`, `brand` or `description`** → null. All three are
///   nullable in the schema, so null means "not recorded".
/// * an **unexpected `assignment_status` token** → carried through. The contract
///   guarantees `'ACTIVE'` for every row it can return, but the value is display
///   data rather than a gate, and nothing in this feature branches on it — so an
///   unfamiliar token is not worth failing a catalogue over. It is validated as
///   *present and a string*, which is the part that would indicate a genuinely
///   different response shape.
/// * **duplicate products** → kept, both of them. The backend's `order by
///   vp.product_name, vp.product_code, vp.id` can legitimately place two
///   products with the same name and code adjacent when they are distinct rows
///   in the Vendor's catalogue. Deduplicating on display fields would hide a
///   real product, and because this client deliberately does not carry
///   `product_id` there is no key on which a genuine duplicate could be told
///   from two similar products. The list shows exactly what the backend
///   returned, in the backend's own order.
abstract final class RetailerAssignedProductParser {
  static List<RetailerAssignedProduct> parse(Object? raw) {
    return RpcRow.asRows(
      raw,
      'assigned products',
    ).map(RetailerAssignedProductParser.parseRow).toList(growable: false);
  }

  static RetailerAssignedProduct parseRow(Map<String, Object?> row) {
    return RetailerAssignedProduct(
      productCode: RpcRow.requiredString(row['product_code'], 'product_code'),
      productName: RpcRow.requiredString(row['product_name'], 'product_name'),
      barcode: RpcRow.optionalString(row['barcode'], 'barcode'),
      brand: RpcRow.optionalString(row['brand'], 'brand'),
      description: RpcRow.optionalString(row['description'], 'description'),
      assignmentStatus: RpcRow.requiredString(
        row['assignment_status'],
        'assignment_status',
      ),
      // No product_id. The contract returns one; nothing here holds it, so no
      // UUID can reach state or a screen.
    );
  }
}
