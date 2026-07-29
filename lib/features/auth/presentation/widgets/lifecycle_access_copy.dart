import '../../domain/entities/lifecycle_access_state.dart';

/// The fixed copy shown for one lifecycle state.
///
/// Every field is a const literal. None interpolates a name, an id, an
/// organization, a role, a raw status, a SQLSTATE or a backend message — there is
/// nothing available here to interpolate, because the RPC returns one word and
/// this record is built from a compile-time constant map keyed on an enum that
/// carries no string.
final class LifecycleNotice {
  const LifecycleNotice({
    required this.title,
    required this.body,
    required this.closing,
  });

  final String title;
  final String body;

  /// The Flutter-specific closing line. Present only on lifecycle notices,
  /// because only there is there a specific thing that might change.
  final String closing;
}

/// The one instruction added on top of the copy the web already approved.
///
/// Flutter has an affordance the web does not — the web's access-denied page is
/// a server component and recovers only on a page reload — so this sentence
/// exists here and nowhere in the shared copy.
const String lifecycleNoticeClosing =
    'If this changes, use Check access again.';

/// The four lifecycle causes that have something specific and safe to say.
///
/// ## Two states are deliberately absent, and their absence is the security boundary
///
/// [LifecycleAccessState.active] and [LifecycleAccessState.noSupportedAccess]
/// have **no entry**, so [noticeFor] returns null for them and the page renders
/// the ordinary access-denied card. Enforcing that by a missing key rather than
/// by a branch means a future contributor adding a case has to add it *here*,
/// where this comment is, rather than in a `switch` somewhere else:
///
/// * `ACTIVE` — nothing about this person's lifecycle explains the refusal, so
///   some other condition did: a missing permission, a wrong role, a route they
///   are simply not entitled to. Saying anything specific would be a guess, and
///   a wrong one. It is emphatically not an authorization grant.
/// * `NO_SUPPORTED_ACCESS` — the ordinary "you are signed in but this is not for
///   you" case, which is exactly what the existing card already says. Distinct
///   copy would tell an unauthorized, possibly hostile account that it holds no
///   Retailer membership at all — a fact the current screen deliberately does
///   not disclose.
///
/// The same two are absent from the web's `NOTICES` map, for the same reasons.
/// The two clients must keep agreeing on this.
const Map<LifecycleAccessState, LifecycleNotice> _notices =
    <LifecycleAccessState, LifecycleNotice>{
      LifecycleAccessState.organizationInactive: LifecycleNotice(
        title: 'Retailer inactive',
        body:
            'This Retailer is currently inactive. Contact the Vendor or your '
            'Retailer administrator.',
        closing: lifecycleNoticeClosing,
      ),
      LifecycleAccessState.membershipInactive: LifecycleNotice(
        title: 'Account inactive',
        body:
            'Your access to this Retailer is inactive. Contact your Retailer '
            'administrator.',
        closing: lifecycleNoticeClosing,
      ),
      LifecycleAccessState.profileInactive: LifecycleNotice(
        title: 'Account unavailable',
        body:
            'Your SalesReward account is currently inactive. Contact support '
            'or your administrator.',
        closing: lifecycleNoticeClosing,
      ),
      LifecycleAccessState.ambiguous: LifecycleNotice(
        title: 'Account setup needs attention',
        body:
            'More than one Retailer context is available for this account. '
            'Contact support.',
        closing: lifecycleNoticeClosing,
      ),
    };

/// The notice to render for a resolved diagnostic state, or null to keep the
/// ordinary access-denied card.
///
/// Null is returned for [LifecycleAccessState.active] and
/// [LifecycleAccessState.noSupportedAccess] — see [_notices] for why each is
/// deliberate. The page returns null for the initial, loading and unavailable
/// phases too, so an unreadable diagnostic says no more than the denial already
/// does.
LifecycleNotice? noticeFor(LifecycleAccessState state) => _notices[state];
