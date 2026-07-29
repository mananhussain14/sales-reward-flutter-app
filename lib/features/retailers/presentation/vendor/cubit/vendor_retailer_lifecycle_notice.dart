/// A lifecycle write a Retailer screen has just performed, so it can be
/// acknowledged.
///
/// Presentation state, shared by the lifecycle cubit and the detail cubit, and
/// declared in its own file so neither has to import the other's library to name
/// it.
///
/// A **statement about the past** rather than a status: nothing here decides
/// what a Retailer currently looks like, which is the re-read detail row's job
/// alone. Every member is chosen from the status the *database confirmed*, never
/// from the status that was requested.
enum VendorRetailerLifecycleNotice {
  /// The database confirmed both rows now hold `SUSPENDED`.
  ///
  /// Covers the idempotent no-op too — a Retailer that was already inactive
  /// writes nothing, records no audit row and moves no `updated_at`, and the RPC
  /// reports `status_changed = false`. That case gets its own member below,
  /// because "you did that" and "somebody already had" are different things to
  /// an administrator.
  deactivated,

  /// The database confirmed both rows now hold `ACTIVE`.
  reactivated,

  /// The Retailer was already inactive; this call changed nothing.
  ///
  /// Presented as an outcome rather than an error: nothing went wrong, and
  /// nothing was written. Most often it means a second administrator got there
  /// first.
  alreadyInactive,

  /// The Retailer was already active; this call changed nothing.
  alreadyActive,

  /// The RPC answered without an error — so the transaction **committed** — but
  /// with a body this build could not trust.
  ///
  /// One member for both directions, because the direction is precisely what
  /// could not be established. It never says the change was lost, and nothing
  /// retries it: the canonical detail is re-read, and that is the only authority
  /// on what the two rows now hold.
  unconfirmed,
}
