import '../../../../core/result/read_result.dart';
import '../entities/vendor_audit_log_entry.dart';

/// The one Vendor Audit Log read, and nothing else.
///
/// ## This milestone is read-only, and the interface is the proof
///
/// There is no write, edit, delete, clear, retention, export, CSV or PDF method
/// here, and no place to add one without changing this file. `public.audit_logs`
/// grants `authenticated` `SELECT` and nothing else — no `INSERT`, `UPDATE` or
/// `DELETE` privilege exists for any browser role — so a write method could not
/// even be implemented; stating its absence is still worth doing, because an
/// audit trail a client can edit is not an audit trail.
///
/// **There is no detail read either, and that is a finding rather than an
/// omission.** The backend audit searched the whole web application for an
/// audit-detail surface — a drawer, a modal, a `[auditLogId]` route, an
/// expandable row — and found none, so there is no shipped notion of what audit
/// "detail" would even mean in this product. The only thing a detail read could
/// add over the list is precisely what the list contract withholds: `metadata`
/// as a whole, `entity_id`, `ip_address`, `user_agent`. Adding one would not be
/// sharing an existing capability; it would be inventing a new and more
/// sensitive one on the most sensitive table in the schema.
///
/// ## What the signature makes impossible
///
/// [auditLogs] takes one optional cursor and nothing else. There is no auth user
/// id, profile id, membership id, Vendor organization id, tenant id, role code,
/// permission code, actor selector, entity selector, entity owner, action
/// filter, date range, search term, offset or page number anywhere on this
/// interface — not as an optional, not as a named argument with a default.
///
/// The absence is the point. The Vendor is derived from `auth.uid()` in SQL by
/// `get_vendor_super_admin_context()`, and the cursor selects a **position in an
/// already-authorized sequence** without ever deciding *whether* anything may be
/// read.
///
/// The page size is not a parameter either: it is fixed at 50 by the data
/// source. The backend refuses `0`, every negative value and everything above
/// 100 with `22023` rather than clamping, precisely so a client cannot ask for
/// 500, silently receive 100, and infer from the short page that it has reached
/// the end of the history. Fixing the value here means this client can never
/// construct such a request.
///
/// ## There are no filters, and that is deliberate
///
/// The web Audit Logs page offers none, so there is no shipped filter semantics
/// to share, and one invented here would be a product decision made in a client.
/// Scroll and refresh are the whole first experience. `actor` in particular is
/// not a candidate: it would take an identity as input.
abstract interface class VendorAuditLogRepository {
  /// `public.list_vendor_audit_logs(p_limit, p_before_occurred_at,
  /// p_before_audit_log_id)` — one keyset page, newest first.
  ///
  /// With no [before] this is the newest page. With one, it is the page strictly
  /// **older** than that exact position, in the backend's
  /// `occurred_at desc, audit_log_id desc` order.
  ///
  /// An **empty list is a legitimate answer** and is never produced from a
  /// failure. It means one of two ordinary things — this Vendor has recorded
  /// nothing, or the cursor sits at the oldest row — and on an audit surface
  /// confusing either with "you may not read this" would be a serious
  /// misstatement. A refusal is `42501` and arrives as a [ReadFailure].
  ///
  /// **New events cannot corrupt traversal.** The SQL predicate is
  /// strictly-less-than against a fixed position in a descending order, so every
  /// row a later page can return is older than the cursor. Events arriving after
  /// the first page are all newer than that page's last row and land outside
  /// every subsequent page by construction — and they are not lost either: they
  /// appear the moment the caller reads again with no cursor.
  ///
  /// **No total count is returned, and none is invented.** An exact `COUNT` over
  /// an append-only table that grows forever costs a full scan per page and is
  /// stale the moment it is computed. Keyset paging needs none: the end of the
  /// history is a short or empty page.
  Future<ReadResult<List<VendorAuditLogEntry>>> auditLogs({
    VendorAuditLogCursor? before,
  });
}
