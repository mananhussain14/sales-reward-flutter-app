import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../domain/entities/vendor_product_field.dart';
import 'vendor_product_parsers.dart';

/// Reads the id `create_vendor_product` returned.
///
/// ## The real Supabase response shape for a scalar-returning function
///
/// PostgREST answers a `returns uuid` function with the bare scalar as JSON — a
/// JSON **string** — so `client.rpc<Object?>(...)` resolves to a Dart `String`
/// carrying the uuid. It is not wrapped in a list and not wrapped in an object;
/// the `PostgrestList` / `PostgrestMap` coercions inside the SDK apply only when
/// the caller asked for those types, and this feature asks for `Object?`.
///
/// ## Everything else is refused, and refused *safely*
///
/// `null`, `''`, a value that is not a `String`, a `List`, a `Map`, and a string
/// that is not 8-4-4-4-12 hexadecimal all throw
/// [VendorProductFormatException] — the same exception the read parsers throw, so
/// there is one unreadable-response concept in this feature rather than two.
///
/// **The offending value is never put in the message.** A create body is not
/// user data, but the rule that a parser's reason names only *field names* is what
/// makes those reasons safe to log, and one exception carrying a value would end
/// that. The reason here is a fixed string.
///
/// A throw from this function does **not** mean the write failed. The function
/// raises on every refusal and rolls back, so a 2xx means the product and its
/// audit row are committed; an unreadable id means the product exists and cannot
/// be addressed. That is why the repository turns this into
/// `VendorProductWriteUnconfirmed` and never into a failure, and why nothing
/// retries it.
String parseCreatedProductId(Object? raw) {
  if (raw is! String) {
    throw const VendorProductFormatException(
      'created product id is not a scalar string',
    );
  }
  if (!isProductIdShaped(raw)) {
    throw const VendorProductFormatException(
      'created product id is not a UUID',
    );
  }
  return raw;
}

/// Whether [raw] is the body a `returns void` RPC produces.
///
/// ## The real Supabase response shape for a void function
///
/// PostgREST answers `returns void` with an empty body, and the SDK maps an empty
/// body to `null`. So `null` is the established successful shape, and it is the
/// only one this build was written against.
///
/// ## Why an unexpected body is never a failure
///
/// This returns a `bool` rather than throwing, and that is the single most
/// important safety decision in this file.
///
/// `update_vendor_product` and `set_vendor_product_status` raise on **every**
/// refusal — unauthorized caller, unknown id, foreign id, invalid value, duplicate
/// barcode — and a raise rolls the whole function back. A 2xx therefore means the
/// row and its audit row are already committed. If a future backend change made
/// one of them return a payload, treating that payload as a failure would tell a
/// Vendor their change was not saved *after it had been saved*, and offer them a
/// retry for work already done. An unexpected shape is a reason to distrust the
/// body, never a reason to distrust the transaction.
///
/// So a `false` becomes `VendorProductWriteUnconfirmed` — the change may well have
/// been applied, the canonical detail is re-read to find out, and nothing claims a
/// save it cannot vouch for.
bool isVoidWriteResponse(Object? raw) => raw == null;

/// Classifies a thrown Vendor Product write error.
///
/// Delegates the whole SQLSTATE decision to [mapSupabaseError], which is the one
/// place in the application that inspects a backend error object. This function
/// adds exactly one thing on top: for a `23505` **only**, which field the
/// duplicate belongs to.
///
/// ## Why a message substring is read here, and only here
///
/// The deployed contract's own words: the duplicate branch is *"the one place a
/// database message is carried forward, and only from this repository's own two
/// fixed literals"*. `create_vendor_product` and `update_vendor_product` raise
/// their own `raise exception` messages for the two per-Vendor unique indexes, and
/// those two literals are the **only** discriminator between "that product code is
/// taken" and "that barcode is taken". There is no separate SQLSTATE, no error
/// code and no field name in the response; the backend's static test suite pins
/// both strings, and the web's `classifyWriteError` matches the same two.
///
/// So this client matches them too, and confines the dependency to these few
/// lines:
///
/// * the match is a `contains` against a literal defined in this file, never a
///   parse of the backend's wording;
/// * an **unrecognized** duplicate message degrades to a duplicate with no field
///   hint, exactly as the web's does, rather than being echoed or guessed at;
/// * **the message itself never travels onward.** What leaves here is
///   `DuplicateFailure(field: …)` — a client-side form-field key — and the
///   screen's own sentence is chosen from it. No Postgres text, table name,
///   constraint name or SQLSTATE reaches a widget.
///
/// Both literals are safe to act on precisely because the two unique indexes are
/// scoped **per Vendor**: neither can describe another Vendor's catalogue, and the
/// same code and the same barcode may legitimately exist under a different Vendor.
///
/// Everything that is not a duplicate is returned exactly as [mapSupabaseError]
/// classified it: `42501` → one generic [DeniedFailure] covering an unauthorized
/// caller, an unknown product and a foreign product alike; `23514` → a generic
/// [InvalidFailure] with **no** field, because the backend's five validation
/// messages are English prose this client does not parse and its own client-side
/// validation has already reported anything a person can act on; an
/// `AuthException` → [UnauthenticatedFailure]; anything else, including every
/// transport fault, → [UnavailableFailure].
Failure mapVendorProductWriteError(Object error) {
  final Failure failure = mapSupabaseError(error);
  if (failure is! DuplicateFailure) {
    return failure;
  }

  final String message = error is PostgrestException ? error.message : '';
  if (message.contains(_duplicateProductCodeLiteral)) {
    return DuplicateFailure(field: VendorProductField.productCode.key);
  }
  if (message.contains(_duplicateBarcodeLiteral)) {
    return DuplicateFailure(field: VendorProductField.barcode.key);
  }
  // A duplicate this build cannot attribute. Reported as a duplicate with no
  // field, so the form says something true without pointing at the wrong input.
  return const DuplicateFailure();
}

/// The two literals `20260727210000` raises, restated here and nowhere else.
///
/// Pinned by `lib/products/vendor-product-writes-contract.test.ts` on the backend
/// side and by this feature's repository tests on this side, so a change to either
/// wording breaks a test rather than silently turning a barcode conflict into an
/// unattributed one.
const String _duplicateProductCodeLiteral =
    'A product with that code already exists';
const String _duplicateBarcodeLiteral =
    'A product with that barcode already exists';
