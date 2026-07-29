import '../entities/lifecycle_access_state.dart';

/// The outcome of asking the backend "why is *my* access refused?".
///
/// Two outcomes, not three, and the collapse is the whole design:
///
/// * [LifecycleAccessResolved] — one of the six words came back.
/// * [LifecycleAccessUnavailable] — **everything else**, identically.
///
/// ## Why there is no third case, and no payload on the second
///
/// The portal-context contract keeps `Denied` and `Failed` apart because one is
/// a decision the user must act on and the other is an outage they should retry.
/// This contract has no such distinction to preserve: it is read *after* a
/// refusal has already been decided, so "the diagnostic was denied", "the
/// diagnostic timed out" and "the diagnostic returned a word this build does not
/// know" all lead to the same screen — the ordinary access-denied card, saying
/// no more than the denial already does.
///
/// Giving [LifecycleAccessUnavailable] a `Failure`, a SQLSTATE or a message
/// would create exactly the distinction this feature exists to erase. The only
/// error the function raises is `42501` for an unauthenticated caller; a page
/// that has already refused access gains nothing from telling that apart from a
/// dropped connection, and a caller who could tell them apart would hold a probe.
///
/// So this union is deliberately impoverished. There is nothing here to leak,
/// because there is nothing here.
sealed class LifecycleAccessResult {
  const LifecycleAccessResult();
}

/// The diagnostic answered with one of the six supported states.
final class LifecycleAccessResolved extends LifecycleAccessResult {
  const LifecycleAccessResolved(this.state);

  final LifecycleAccessState state;
}

/// The diagnostic could not be read, or answered something this build does not
/// recognize.
///
/// Carries **no payload of any kind** — no [Object], no `Failure`, no SQLSTATE,
/// no message, no identifier, no timestamp. Const and field-free by design: a
/// future change that wants to add one is a change that wants to reintroduce the
/// distinction described above, and should be refused here rather than argued
/// about at the widget.
final class LifecycleAccessUnavailable extends LifecycleAccessResult {
  const LifecycleAccessUnavailable();
}

/// Reads the caller's own lifecycle access state from the backend.
///
/// Backed by exactly one authenticated call to
/// `public.get_my_lifecycle_access_state()`, which takes **zero arguments**.
/// There is no auth-user id, profile id, membership id, organization id, role
/// code, permission code, email or tenant selector parameter — the subject is
/// `auth.uid()` and can only ever be `auth.uid()`. A caller cannot ask about
/// anybody else, and this interface could not express the question if it wanted
/// to.
///
/// Two rules for any implementation:
///
/// * **Never throw.** [read] is contractually non-throwing; every failure is
///   [LifecycleAccessUnavailable]. A caller that had to catch would be a caller
///   that could inspect.
/// * **Never cache.** The answer describes a lifecycle state a Retailer Owner or
///   the Vendor can change at any moment. A cached `ACTIVE` outliving its truth
///   is the one way a diagnostic could influence a later decision.
abstract interface class LifecycleAccessRepository {
  Future<LifecycleAccessResult> read();
}
