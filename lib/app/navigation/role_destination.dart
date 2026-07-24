import 'package:flutter/material.dart';

import '../../features/auth/domain/entities/app_role.dart';

/// One entry in a role's primary navigation.
@immutable
class RoleDestination {
  const RoleDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.path,
  });

  /// A destination that is shown but not navigable — the web's "Coming soon"
  /// nav entry, rendered with a trailing "Soon" pill.
  ///
  /// The Vendor drawer keeps these because they sketch a roadmap to an
  /// **internal** audience. The Retailer portal has none by design: advertising
  /// unbuilt modules to an external customer sets an expectation this milestone
  /// cannot meet.
  const RoleDestination.soon({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  }) : path = null;

  /// The user-facing label, and the accessibility label for the icon.
  final String label;

  final IconData icon;

  /// The filled counterpart, shown when the destination is active.
  final IconData selectedIcon;

  /// The absolute route path, always inside the owning role's prefix — or null
  /// for a "Soon" placeholder, which has no route.
  final String? path;

  bool get isEnabled => path != null;
}

/// How a role's shell presents its navigation.
///
/// The web uses one pattern for everything: a fixed 256px white sidebar that
/// becomes a left drawer below `lg`. That is a zero-risk port, but the
/// destination counts make a drawer a poor phone experience for three of the
/// four roles, so § 4.1 of the design handoff recommends a per-role split
/// (decision **D-4**) — which changes navigation *mechanics* only, while every
/// colour, icon and label stays identical.
enum RoleShellChrome {
  /// Two to five destinations → a bottom navigation bar on a phone, promoted to
  /// a navigation rail at [SrSpacing.breakpointSm] and above.
  bottomBar,

  /// More destinations than a bottom bar can carry → a navigation drawer,
  /// mirroring the web sidebar almost verbatim, and a permanent side panel at
  /// [SrSpacing.breakpointLg] and above.
  drawer,
}

/// A role's complete navigation model: where it lands, what its shell looks
/// like, and which destinations it offers.
///
/// ## Navigation is not authorization
///
/// Stated three separate times in the web source, and repeated in § 0 of the
/// role-flow map:
///
/// > *"NAVIGATION IS NOT AUTHORIZATION. Which items appear is presentation. …
/// > Hiding a link removes an accident, never a capability."*
///
/// Which items appear here is decided again on the server by every RPC behind
/// every read and write. Omitting a destination removes a dead end; adding one
/// back would grant nothing.
///
/// ## Why each role declares its own list
///
/// Every model is built from destinations declared in its own file next to its
/// own shell. None is a filtered view of a master list. The web made the same
/// choice for the same reason, and says so plainly in
/// `components/retailer-portal/retailer-nav-items.tsx`:
///
/// > *Two lists that share nothing cannot leak into each other.*
///
/// A filtered master list is one rendering bug away from putting a Vendor
/// destination inside a Sales Staff shell.
@immutable
class RoleNavigation {
  const RoleNavigation({
    required this.role,
    required this.routePrefix,
    required this.portalName,
    required this.landingPath,
    required this.chrome,
    required this.destinations,
  });

  final AppRole role;

  /// Every route this role owns starts with this prefix, and no other role's
  /// do. Route isolation is asserted against it in the tests.
  final String routePrefix;

  /// The portal name shown in the app bar and under the brand wordmark —
  /// "Vendor Admin", "Retailer Portal". Never a role name, and never a second
  /// product name.
  final String portalName;

  /// The first screen this role sees.
  final String landingPath;

  final RoleShellChrome chrome;

  /// Every entry in display order, including any "Soon" placeholder.
  final List<RoleDestination> destinations;

  /// The entries that actually have a route.
  List<RoleDestination> get routableDestinations =>
      destinations.where((RoleDestination d) => d.isEnabled).toList();

  /// The index into [destinations] that owns [location], or 0 if none does.
  ///
  /// Longest-prefix wins, so `/retailer-owner/staff/invite` selects Staff
  /// rather than falling back to the first entry.
  int indexForLocation(String location) {
    int bestIndex = 0;
    int bestLength = -1;

    for (int i = 0; i < destinations.length; i++) {
      final String? path = destinations[i].path;
      if (path == null) {
        continue;
      }
      if ((location == path || location.startsWith('$path/')) &&
          path.length > bestLength) {
        bestIndex = i;
        bestLength = path.length;
      }
    }
    return bestIndex;
  }

  /// Whether [location] belongs to this role.
  bool owns(String location) =>
      location == routePrefix || location.startsWith('$routePrefix/');
}
