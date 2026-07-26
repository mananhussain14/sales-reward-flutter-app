import 'vendor_product_status.dart';

/// A status a caller may **request** for a product.
///
/// Two members, because `public.set_vendor_product_status(uuid, text)` accepts
/// exactly two tokens after `upper(btrim(...))` and answers anything else with
/// its own safe message. This is deliberately **not**
/// [VendorProductStatus], which has a third member — [VendorProductStatus.unknown],
/// the forward-compatibility case for a token a *response* carried that this
/// build does not recognise. Sending `unknown` would be sending the empty string,
/// and a type that makes it expressible is a type that eventually sends it.
///
/// So the request vocabulary and the response vocabulary are separate types, and
/// the only way to obtain a request is [forCurrent] — from a status the backend
/// actually returned.
enum VendorProductStatusChange {
  /// `INACTIVE → ACTIVE`.
  activate('ACTIVE'),

  /// `ACTIVE → INACTIVE`. **Not a deletion**: the row, its `created_at` and
  /// every assignment row survive, and the product stays listed and editable.
  deactivate('INACTIVE');

  const VendorProductStatusChange(this.code);

  /// The exact token the RPC's `in ('ACTIVE','INACTIVE')` test accepts.
  ///
  /// The only place in this feature outside the response enums where either
  /// literal is written, which is what keeps a status value from being assembled
  /// anywhere a screen could reach.
  final String code;

  /// The change offered for a product currently in [status], or null when none
  /// is.
  ///
  /// Null for [VendorProductStatus.unknown] on purpose. A token this build does
  /// not recognise is a status whose opposite this build cannot name: offering
  /// "Deactivate" for it would be guessing that an unfamiliar status is a live
  /// one, and offering "Activate" would be guessing the reverse. The screen shows
  /// no status action at all, and says so.
  static VendorProductStatusChange? forCurrent(VendorProductStatus status) =>
      switch (status) {
        VendorProductStatus.active => deactivate,
        VendorProductStatus.inactive => activate,
        VendorProductStatus.unknown => null,
      };
}
