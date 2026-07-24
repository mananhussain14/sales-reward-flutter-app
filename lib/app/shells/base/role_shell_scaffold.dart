import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/design.dart';
import '../../../core/widgets/widgets.dart';
import '../../../features/auth/domain/entities/app_role.dart';
import '../../navigation/role_destination.dart';
import 'role_shell_bloc.dart';

/// The shared chrome every role shell is built from.
///
/// ## What it translates
///
/// The web application presents one navigation pattern for everything: a fixed
/// dark sidebar on `--surface-nav`, with the brand lockup at the top and an
/// indigo active state. That does not survive a 360px viewport, so this scaffold
/// keeps the *identity* and adapts the *form*:
///
/// | Web | Mobile |
/// | --- | --- |
/// | Fixed dark sidebar, 6+ links | [RoleShellChrome.drawer] — a dark drawer on the same surface |
/// | Fixed sidebar, 3–5 links | [RoleShellChrome.bottomBar] — a bottom bar, promoted to a rail at ≥640px |
/// | Sidebar brand lockup | The same lockup, in the app bar and the drawer header |
/// | Indigo active link | The indigo `brand-soft` navigation indicator |
///
/// ## What it is not
///
/// It is not a role switch. Each role's shell supplies its own BLoC type and its
/// own navigation model; this widget never asks what role it is rendering, and
/// there is no `if (role == ...)` anywhere in it. That is the difference between
/// four shells sharing chrome and one shell pretending to be four.
class RoleShellScaffold<B extends RoleShellBloc> extends StatefulWidget {
  const RoleShellScaffold({
    super.key,
    required this.child,
    required this.location,
    required this.resolved,
  });

  /// The routed page for the active destination.
  final Widget child;

  /// The router's current location, so the highlighted destination stays in
  /// step with deep links and the back gesture.
  final String location;

  /// The role this shell was built for, and how far it can be trusted.
  ///
  /// Used for the caption under the brand lockup and — when the role is only a
  /// local preview — for the banner that says so.
  final ResolvedRole resolved;

  @override
  State<RoleShellScaffold<B>> createState() => _RoleShellScaffoldState<B>();
}

class _RoleShellScaffoldState<B extends RoleShellBloc>
    extends State<RoleShellScaffold<B>> {
  @override
  void initState() {
    super.initState();
    _syncLocation();
  }

  @override
  void didUpdateWidget(covariant RoleShellScaffold<B> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _syncLocation();
    }
  }

  /// Keeps the highlighted tab in agreement with the router, whatever moved it
  /// — a tap, a deep link, the back gesture, or a guard redirect.
  ///
  /// Dispatched from the lifecycle rather than from `build`, so the shell never
  /// mutates BLoC state while the tree is being laid out.
  void _syncLocation() {
    context.read<B>().add(RoleShellLocationChanged(widget.location));
  }

  @override
  Widget build(BuildContext context) {
    final RoleNavigation navigation = context.read<B>().navigation;

    return BlocBuilder<B, RoleShellState>(
      builder: (BuildContext context, RoleShellState state) {
        final double width = MediaQuery.sizeOf(context).width;
        final bool wide = width >= SrSpacing.railBreakpoint;

        void go(int index) {
          if (index < 0 || index >= navigation.destinations.length) {
            return;
          }
          context.read<B>().add(RoleShellDestinationSelected(index));
          context.go(navigation.destinations[index].path);
        }

        final Widget body = Column(
          children: <Widget>[
            if (widget.resolved.trust == RoleTrust.localPreview)
              _PreviewBanner(role: widget.resolved.role),
            Expanded(child: widget.child),
          ],
        );

        return switch (navigation.chrome) {
          RoleShellChrome.drawer => _DrawerShell(
            navigation: navigation,
            resolved: widget.resolved,
            selectedIndex: state.selectedIndex,
            onSelected: go,
            body: body,
          ),
          RoleShellChrome.bottomBar => _BottomBarShell(
            navigation: navigation,
            resolved: widget.resolved,
            selectedIndex: state.selectedIndex,
            onSelected: go,
            useRail: wide,
            body: body,
          ),
        };
      },
    );
  }
}

/// The app bar shared by both chrome variants: the brand lockup captioned with
/// the role, exactly as the web sidebar captions itself ("Vendor Admin").
class _ShellAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ShellAppBar({required this.resolved, this.leading});

  final ResolvedRole resolved;
  final Widget? leading;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 64,
      leading: leading,
      leadingWidth: leading == null ? 0 : null,
      titleSpacing: leading == null ? SrSpacing.lg : 0,
      title: SrBrandLockup(
        size: 32,
        context: resolved.retailerName ?? resolved.role.displayName,
      ),
      shape: const Border(bottom: BorderSide(color: SrColors.border)),
    );
  }
}

/// A visible, permanent reminder that the role in effect was chosen locally.
///
/// It is not dismissible on purpose. A preview role authorizes nothing, and the
/// moment this banner can be hidden, a screenshot of this build becomes
/// indistinguishable from one where role resolution actually works.
class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner({required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SrTone.amber.background,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SrSpacing.lg,
          vertical: SrSpacing.smPlus,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: SrTone.amber.foreground,
            ),
            const SizedBox(width: SrSpacing.sm),
            Expanded(
              child: Text(
                'Interface preview — ${role.displayName} was selected on this '
                'device. It grants no access.',
                style: SrTypography.caption.copyWith(
                  color: SrTone.amber.foreground,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom navigation on a phone; a navigation rail from 640px up.
class _BottomBarShell extends StatelessWidget {
  const _BottomBarShell({
    required this.navigation,
    required this.resolved,
    required this.selectedIndex,
    required this.onSelected,
    required this.useRail,
    required this.body,
  });

  final RoleNavigation navigation;
  final ResolvedRole resolved;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool useRail;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    if (useRail) {
      return Scaffold(
        appBar: _ShellAppBar(resolved: resolved),
        body: Row(
          children: <Widget>[
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelected,
              labelType: NavigationRailLabelType.all,
              destinations: <NavigationRailDestination>[
                for (final RoleDestination destination
                    in navigation.destinations)
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: Text(destination.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: _ShellAppBar(resolved: resolved),
      body: body,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: SrColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          destinations: <NavigationDestination>[
            for (final RoleDestination destination in navigation.destinations)
              NavigationDestination(
                icon: Icon(destination.icon),
                selectedIcon: Icon(destination.selectedIcon),
                label: destination.label,
                tooltip: destination.label,
              ),
          ],
        ),
      ),
    );
  }
}

/// A drawer for a role with more destinations than a bottom bar can hold. The
/// drawer keeps the web sidebar's dark `--surface-nav` surface, so the role that
/// most resembles the desktop admin still looks like it.
class _DrawerShell extends StatelessWidget {
  const _DrawerShell({
    required this.navigation,
    required this.resolved,
    required this.selectedIndex,
    required this.onSelected,
    required this.body,
  });

  final RoleNavigation navigation;
  final ResolvedRole resolved;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final bool expanded =
        MediaQuery.sizeOf(context).width >= SrSpacing.expandedBreakpoint;

    final Widget drawer = _RoleNavDrawer(
      navigation: navigation,
      resolved: resolved,
      selectedIndex: selectedIndex,
      onSelected: (int index) {
        if (!expanded) {
          Navigator.of(context).maybePop();
        }
        onSelected(index);
      },
    );

    // At desktop width the drawer stops being modal and simply sits beside the
    // content, which is the web layout again.
    if (expanded) {
      return Scaffold(
        body: Row(
          children: <Widget>[
            SizedBox(width: 288, child: drawer),
            Expanded(
              child: Scaffold(
                appBar: _ShellAppBar(resolved: resolved),
                body: body,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: _ShellAppBar(
        resolved: resolved,
        leading: Builder(
          builder: (BuildContext context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            tooltip: 'Open navigation',
            onPressed: Scaffold.of(context).openDrawer,
          ),
        ),
      ),
      drawer: drawer,
      body: body,
    );
  }
}

class _RoleNavDrawer extends StatelessWidget {
  const _RoleNavDrawer({
    required this.navigation,
    required this.resolved,
    required this.selectedIndex,
    required this.onSelected,
  });

  final RoleNavigation navigation;
  final ResolvedRole resolved;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(SrSpacing.xl),
              child: SrBrandLockup(
                size: 36,
                context: resolved.role.displayName,
                onDarkSurface: true,
              ),
            ),
            const Divider(color: SrColors.slate800, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: SrSpacing.md,
                  vertical: SrSpacing.md,
                ),
                children: <Widget>[
                  for (int i = 0; i < navigation.destinations.length; i++)
                    _DrawerTile(
                      destination: navigation.destinations[i],
                      selected: i == selectedIndex,
                      onTap: () => onSelected(i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final RoleDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The web sidebar marks its active link with an indigo tint on the dark
    // surface; the same treatment reads correctly here.
    final Color foreground = selected ? SrColors.white : SrColors.slate400;

    return Padding(
      padding: const EdgeInsets.only(bottom: SrSpacing.xs),
      child: Material(
        color: selected
            ? SrColors.brand.withValues(alpha: 0.9)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(SrRadii.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SrRadii.lg),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SrSpacing.md,
              vertical: SrSpacing.md,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 20,
                  color: foreground,
                ),
                const SizedBox(width: SrSpacing.md),
                Expanded(
                  child: Text(
                    destination.label,
                    style: SrTypography.body.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
