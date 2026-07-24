import 'package:flutter/material.dart';

import '../../features/auth/domain/entities/app_role.dart';

/// One entry in a role's primary navigation.
@immutable
class RoleDestination {
  const RoleDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.path,
  });

  /// The user-facing label. Also the accessibility label for the icon.
  final String label;

  final IconData icon;

  /// The filled counterpart, shown when the destination is active — the mobile
  /// equivalent of the web sidebar's active-link treatment.
  final IconData selectedIcon;

  /// The absolute route path. Always inside the owning role's prefix, which is
  /// what makes route isolation checkable.
  final String path;
}

/// How a role's shell presents its navigation.
///
/// The web application uses one pattern for everything — a fixed dark sidebar.
/// That does not survive a 360px viewport, so each role takes the mobile pattern
/// that fits the *size* of its navigation, while keeping the sidebar's visual
/// identity (the dark `--surface-nav` surface, the brand lockup, the indigo
/// active state).
enum RoleShellChrome {
  /// Three to five destinations → a bottom navigation bar, promoted to a
  /// navigation rail at [SrSpacing.railBreakpoint] and above.
  ///
  /// This is the standard translation of the sidebar for the Retailer roles.
  bottomBar,

  /// More destinations than a bottom bar can hold → a navigation drawer, which
  /// keeps the dark sidebar surface almost verbatim.
  ///
  /// Used by the Vendor Super Admin shell, whose web sidebar carries six active
  /// modules and would be unusable as five crowded tabs.
  drawer,
}

/// A role's complete navigation model: where it lands, what its shell looks
/// like, and which destinations it offers.
///
/// ## Navigation is not authorization
///
/// Which items appear here is presentation. It is decided again on the server by
/// every RPC behind every read and write. Omitting a destination removes an
/// accident — a user tapping into a screen the database will refuse — never a
/// capability. Adding one back would not grant anything either.
///
/// ## Why each role declares its own list
///
/// Every model below is built from its own destinations, declared in its own
/// file next to its own shell. None of them is a filtered view of a master list.
/// The web application made the same choice for the same reason, and states it
/// plainly in `components/retailer-portal/retailer-nav-items.tsx`:
///
/// > Two lists that share nothing cannot leak into each other.
///
/// A filtered master list is one rendering bug away from showing a Vendor
/// destination inside a Sales Staff shell.
@immutable
class RoleNavigation {
  const RoleNavigation({
    required this.role,
    required this.routePrefix,
    required this.landingPath,
    required this.chrome,
    required this.destinations,
  });

  final AppRole role;

  /// Every route this role owns starts with this prefix, and no other role's
  /// routes do. Route isolation is asserted against it in the tests.
  final String routePrefix;

  /// The first screen this role sees. Mirrors the web's `LANDING_ROUTES`
  /// precedence, translated to the mobile route tree.
  final String landingPath;

  final RoleShellChrome chrome;

  final List<RoleDestination> destinations;

  /// The index of the destination that owns [location], or 0 if none does.
  ///
  /// Longest-prefix wins, so `/retailer-owner/staff/invite` selects the Staff
  /// tab rather than falling back to the first one.
  int indexForLocation(String location) {
    int bestIndex = 0;
    int bestLength = -1;

    for (int i = 0; i < destinations.length; i++) {
      final String path = destinations[i].path;
      final bool matches = location == path || location.startsWith('$path/');
      if (matches && path.length > bestLength) {
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
