import 'package:flutter/material.dart';

import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_role_status.dart';
import 'vendor_role_copy.dart';

/// The sentence that makes a permission list truthful.
///
/// ## Why a whole widget for one alert
///
/// This is the single most consequential piece of copy in the feature, and it is
/// conditional on a rule that is easy to state backwards. Keeping it here means
/// the rule is written once:
///
/// * `ACTIVE` → **nothing is shown.** The permissions below are effective, and a
///   banner saying so would be noise on the common case.
/// * `INACTIVE` → the mapped permissions are **not** effective, and the list
///   below is still shown in full so an administrator can see what the
///   definition holds before retiring it further.
/// * anything this build does not recognise → a neutral notice that says the
///   effectiveness cannot be shown. Never an affirmative claim, because the one
///   thing an unknown status may never do is imply access.
///
/// The condition is a **positive test** — `grantsMappedPermissions`, which is
/// true for `ACTIVE` alone — so a future status token can never reach "no notice
/// needed" by failing to match `INACTIVE`.
///
/// ## Why this is presentation, and only presentation
///
/// `public.has_organization_permission()` filters on `r.status = 'ACTIVE'`, and
/// there is no permission-status column anywhere to filter on instead — so an
/// inactive role grants nothing however many permissions remain mapped to it.
/// That is a fact about the **backend's** behaviour, restated here for a reader.
/// Nothing in this feature computes access from it: the permission list is
/// configuration information, not a capability check, and the backend decides
/// the real question again on every call.
///
/// ## Not colour alone
///
/// [SrAlert] carries a glyph, a bold title and a full sentence, and the
/// surrounding page keeps the status pill visible while the permissions are on
/// screen. A reader who perceives no colour at all still gets the fact three
/// times over.
class VendorRoleEffectivenessNotice extends StatelessWidget {
  const VendorRoleEffectivenessNotice({super.key, required this.status});

  final VendorRoleStatus status;

  /// The spoken form for [status], or null when no notice is warranted.
  ///
  /// Exposed so a test can assert the mapping — including its silence on an
  /// active role — without building three widgets.
  static String? semanticsFor(VendorRoleStatus status) => switch (status) {
    VendorRoleStatus.active => null,
    VendorRoleStatus.inactive => VendorRoleCopy.inactiveNoticeSemantics,
    VendorRoleStatus.unknown => VendorRoleCopy.unknownStatusNoticeSemantics,
  };

  @override
  Widget build(BuildContext context) {
    if (status.grantsMappedPermissions) {
      return const SizedBox.shrink();
    }

    final (String title, String body) = switch (status) {
      // Unreachable — the guard above returns first — but written positively so
      // that adding a future "effective" status cannot silently fall through to
      // the inactive wording.
      VendorRoleStatus.active => (
        VendorRoleCopy.inactiveNoticeTitle,
        VendorRoleCopy.inactiveNoticeBody,
      ),
      VendorRoleStatus.inactive => (
        VendorRoleCopy.inactiveNoticeTitle,
        VendorRoleCopy.inactiveNoticeBody,
      ),
      VendorRoleStatus.unknown => (
        VendorRoleCopy.unknownStatusNoticeTitle,
        VendorRoleCopy.unknownStatusNoticeBody,
      ),
    };

    return Semantics(
      label: semanticsFor(status),
      child: SrAlert(tone: SrAlertTone.warning, title: title, message: body),
    );
  }
}
