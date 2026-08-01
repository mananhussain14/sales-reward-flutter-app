import 'package:equatable/equatable.dart';

/// When a campaign runs.
///
/// ## The instant and the zone are two different facts, and stay two fields
///
/// `campaign_versions.starts_at` and `ends_at` are `timestamptz` — absolute
/// instants, parsed to UTC by `RpcRow` like every other timestamp in this
/// application. `timezone_name` is an **IANA identifier** the Vendor chose when
/// authoring the campaign, stored in a separate `text` column and validated
/// server-side against `pg_catalog.pg_timezone_names` by trigger.
///
/// They are kept apart deliberately. Folding the zone into the instant would
/// produce a `DateTime` that is neither: not the absolute moment the backend
/// sent, and not a wall-clock reading anything can be compared against. Every
/// equality and ordering above the presentation layer therefore uses the UTC
/// instant alone, exactly as the rest of the codebase does.
///
/// ## This client does not convert into [timeZoneName], and says so on screen
///
/// Doing so needs an IANA time-zone database. The application ships none —
/// there is no `package:timezone`, no `package:intl`, and `date_format.dart`
/// deliberately hand-rolls a single-locale formatter rather than take a
/// localisation dependency for a handful of strings. Adding a zone database to a
/// read-only screen is not a trade this milestone makes.
///
/// So dates are rendered in the **device's** zone, and [timeZoneName] is shown
/// beside them as its own labelled fact, with copy that states which is which.
/// That is a real limitation, and stating it is the point: silently showing a
/// device-local date under a heading that implies the campaign's own zone would
/// be the failure mode worth avoiding, and inventing an offset would be worse.
///
/// ## No end date is a real campaign, not a missing value
///
/// `ends_at` is nullable and the migration calls the null case *"the evergreen
/// campaign — a first-class case"*. [isEvergreen] is that case. It is never
/// rendered as a blank, a dash or a far-future date.
///
/// ## Nothing here derives a lifecycle state
///
/// No comparison against the device clock happens in this class or anywhere in
/// this feature. `CampaignLifecycleState` arrives already derived by
/// `campaign_derived_state`, which reads the **server's** `now()`. A phone with
/// a wrong clock changes nothing about which section a campaign appears in.
final class CampaignSchedule extends Equatable {
  const CampaignSchedule({
    required this.startsAt,
    required this.endsAt,
    required this.timeZoneName,
  });

  /// `campaign_versions.starts_at`. `NOT NULL` in the schema, always UTC here.
  final DateTime startsAt;

  /// `campaign_versions.ends_at`. Null for an evergreen campaign; UTC when
  /// present.
  final DateTime? endsAt;

  /// `campaign_versions.timezone_name` — an IANA identifier such as
  /// `Asia/Dubai`.
  ///
  /// Carried and displayed as a label. **Never** used to compute anything: see
  /// the class doc for why this client does no conversion.
  final String timeZoneName;

  /// The campaign has no end date.
  bool get isEvergreen => endsAt == null;

  /// Whether the period is one the backend could have stored.
  ///
  /// `campaign_versions_period_ordered` is `check (ends_at is null or ends_at >
  /// starts_at)` — strictly greater, because the migration notes a zero-length
  /// period *"can reward nothing, so admitting it would only produce a campaign
  /// that looks live in a list and is dead in every evaluation"*.
  ///
  /// Asserted by the parser, which refuses a row that fails it rather than
  /// rendering a period that runs backwards.
  bool get isOrdered => endsAt == null || endsAt!.isAfter(startsAt);

  @override
  List<Object?> get props => <Object?>[startsAt, endsAt, timeZoneName];
}
