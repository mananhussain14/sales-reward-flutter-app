/// A write a product screen has just performed, so it can be acknowledged.
///
/// Presentation state, shared by the three write cubits and the detail cubit, and
/// declared in its own file so none of them has to import another's library to
/// name it.
///
/// A *statement about the past* rather than a status: nothing here decides what a
/// product currently looks like, which is the re-read product row's job alone.
///
/// The `unconfirmed` members exist because the two `void` writes can, in
/// principle, answer with a body this build cannot read — and a 2xx from either of
/// them means the transaction already committed. The honest sentence for that is
/// "this may have been applied; here is what the product looks like now", which is
/// what the canonical re-read then answers. It is emphatically not "the save
/// failed": that would be false, and it would invite somebody to write twice.
enum VendorProductWriteNotice {
  /// `create_vendor_product` returned this product's id.
  created,

  /// `update_vendor_product` succeeded.
  ///
  /// Covers a backend **no-op** too. An edit in which no value differs from what
  /// is stored — including a difference that is only whitespace, because
  /// normalization runs first — writes nothing, moves no `updated_at` and records
  /// no audit row, and succeeds silently. The contract makes that deliberately
  /// indistinguishable from a real change so that a client never has to tell
  /// "nothing changed" apart from "the write failed", and this notice preserves
  /// that: its wording is true either way.
  updated,

  /// `set_vendor_product_status` succeeded, including the idempotent same-status
  /// case, which is a no-op for the same reasons.
  statusChanged,

  /// An edit answered 2xx with a body this build could not read.
  updateUnconfirmed,

  /// A status change answered 2xx with a body this build could not read.
  statusUnconfirmed,
}
