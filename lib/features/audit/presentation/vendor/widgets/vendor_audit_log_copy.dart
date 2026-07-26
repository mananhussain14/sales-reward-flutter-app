/// Every user-facing sentence this feature renders, in one place.
///
/// Centralised for the same reason the receipt, Retailer, User, Role and Product
/// features centralise theirs: a string that explains a *backend* answer is part
/// of the security boundary, not decoration. The rules these strings obey:
///
/// * **No raw backend text.** No Postgres message, SQLSTATE, table, column,
///   function, policy or permission name appears in any of them. A caller whose
///   role no longer holds the audit read permission sees the same generic
///   wording as a caller who is not signed in.
/// * **`SYSTEM` is never rendered as a bare "System".** [systemActor] is the
///   only wording for it, and it says what the value actually means — that no
///   actor identity remains. "Automated system", "System process", "Deleted
///   user" and "Former user" are all claims the schema cannot support, because
///   an event born without an actor and an event whose actor was deleted are
///   byte-identical here.
/// * **`UNKNOWN` never describes the actor.** [unknownActor] is neutral and
///   final: the actor may belong to another Vendor, and saying so — or saying
///   anything more — is the cross-tenant disclosure the scoped SQL join exists
///   to prevent.
/// * **Nothing claims an outcome.** No string here says an action succeeded or
///   failed. `public.audit_logs` has no outcome column; where an outcome is
///   recorded at all it is part of the action code itself, and it is rendered as
///   that code's own label rather than as a status this screen decided.
/// * **Nothing here names a write.** There is no export, CSV, PDF, delete,
///   clear, retention or filter string, because this milestone performs none of
///   those — and an affordance, even a disabled one, would advertise a
///   capability this screen does not have.
/// * **No count is called a total.** Only pages that have been asked for are
///   loaded, and no total exists in the contract.
/// * **An outage is never a denial**, and a denial never reads as "nothing
///   recorded". Those two live in `SrFailureView`, which this feature reuses
///   rather than rewording.
abstract final class VendorAuditLogCopy {
  // -- the feed --------------------------------------------------------------

  static const String listTitle = 'Audit Logs';

  /// Says what the feed is and, in one clause, what it is not. The scope note is
  /// load-bearing rather than modest: invitation *acceptances* and Retailer
  /// staff events are filed under the **Retailer** organization by the shipped
  /// audit writers, so they are correctly invisible here — and a reader who
  /// assumed this feed was exhaustive would draw the wrong conclusion from their
  /// absence.
  static const String listDescription =
      'Administrative activity recorded for your Vendor organization, newest '
      'first. Events recorded against a Retailer organization are not shown '
      'here.';

  static const String refresh = 'Refresh';
  static const String refreshing = 'Refreshing…';

  static const String loadingList = 'Loading recorded activity';

  static const String emptyTitle = 'No activity recorded yet';

  /// States the absence and stops. It does not suggest doing anything: this
  /// screen cannot record an event, and no mobile screen can.
  static const String emptyBody =
      'This Vendor organization has no recorded administrative activity.';

  static const String staleTitle = 'This activity may be out of date';
  static const String staleBody =
      'We could not check for newer activity just now. Everything already '
      'loaded is still shown.';

  // -- one event -------------------------------------------------------------

  static const String actionLabel = 'Action';
  static const String actorLabel = 'Recorded actor';
  static const String entityLabel = 'Affected item';
  static const String occurredLabel = 'Recorded at';

  /// The neutral wording for `actor_type = 'UNKNOWN'`.
  ///
  /// An actor id is still on the row, but it resolves to no membership of this
  /// Vendor — because the actor belongs to another Vendor, or holds no
  /// membership at all. The two are not distinguished and neither is described.
  static const String unknownActor = 'Unknown actor';

  /// The **only** wording for `actor_type = 'SYSTEM'`.
  ///
  /// The value means "no actor identity remains", and it cannot distinguish an
  /// event written with no actor from an event whose actor was later deleted —
  /// `profiles.id` cascades from `auth.users` and `actor_profile_id` is
  /// `ON DELETE SET NULL`, so the two rows are byte-identical in every emitted
  /// actor field. A bare "System" would be a claim about *who acted* that the
  /// evidence cannot support.
  static const String systemActor = 'System or unavailable actor';

  /// An actor type this build does not recognise. Visible, neutral, and never
  /// folded into one of the three known states.
  static const String unrecognizedActor = 'Actor unavailable';

  /// Shown where the affected thing carries no historical name.
  ///
  /// A real and ordinary state: the name snapshot exists only for the five
  /// entity types the backend whitelists, and only when the stored value is a
  /// JSON string. The row is never hidden for it, and no name is reconstructed.
  static const String entityNameUnavailable = 'Affected item unavailable';

  /// Explains the raw code shown beneath an action this build has no label for.
  static const String unknownActionNote = 'Recorded action code';

  // -- older activity --------------------------------------------------------

  static const String loadMore = 'Load older activity';
  static const String loadingMore = 'Loading older activity…';

  static const String loadMoreFailedTitle = 'Could not load older activity';
  static const String loadMoreFailedBody =
      'Everything already loaded is still shown. Try again to reach further '
      'back.';
  static const String retryLoadMore = 'Try again';

  static const String endOfHistoryTitle =
      'You have reached the earliest '
      'recorded activity';

  /// Says what the end means without implying the record is complete: rows are
  /// retained indefinitely, but only events filed against this Vendor appear.
  static const String endOfHistoryBody =
      'There is nothing older recorded for this Vendor organization.';

  /// Labels the number of rows held. Deliberately "loaded" rather than "total":
  /// only the pages that have been asked for are here, and the contract returns
  /// no total.
  static String loadedCount(int count) =>
      count == 1 ? '1 event loaded' : '$count events loaded';
}
