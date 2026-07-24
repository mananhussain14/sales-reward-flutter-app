import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/design.dart';
import '../../../core/widgets/widgets.dart';
import '../../../features/auth/domain/entities/portal_context.dart';
import '../../navigation/role_destination.dart';
import 'account_sheet.dart';
import 'role_shell_bloc.dart';

/// The shared chrome every role shell is built from.
///
/// ## What it translates
///
/// The web presents one navigation pattern: a fixed **white** 256px sidebar with
/// a 1px slate-200 right border, which below `lg` becomes a left drawer behind a
/// hamburger. This scaffold keeps that identity and adapts the *form* per role
/// (decision **D-4**): a drawer for the Vendor's twelve entries, a bottom bar
/// (promoted to a rail at 640px, a permanent panel at 1024px) for the others.
///
/// > **The drawer is white, not dark.** `--surface-nav` is declared in
/// > `globals.css` but never applied — the shipped sidebar is white.
///
/// ## Capabilities are a presentation hint here, and nowhere else
///
/// The scaffold hides a destination whose backend capability is explicitly
/// false, via [RoleNavigation.visibleDestinations]. That can only ever *remove*
/// an entry the database would refuse anyway; it never grants one, and it can
/// never empty a shell. It is not authorization: the backend re-decides every
/// operation regardless of what is shown.
///
/// ## What it is not
///
/// It is not a role switch. Each shell supplies its own BLoC type and its own
/// navigation model; this widget never asks which role it is rendering.
class RoleShellScaffold<B extends RoleShellBloc> extends StatefulWidget {
  const RoleShellScaffold({
    super.key,
    required this.child,
    required this.location,
    required this.portalContext,
  });

  /// The routed page for the active destination.
  final Widget child;

  /// The router's current location, so the highlighted destination stays in
  /// step with deep links, the back gesture and guard redirects.
  final String location;

  /// The resolved context this shell was built for. Supplies the organization
  /// caption and the capability hints.
  final PortalContext portalContext;

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

  /// Dispatched from the lifecycle rather than from `build`, so the shell never
  /// mutates BLoC state while the tree is being laid out.
  void _syncLocation() {
    context.read<B>().add(RoleShellLocationChanged(widget.location));
  }

  void _go(RoleDestination destination) {
    final String? path = destination.path;
    if (path == null) {
      // A "Soon" placeholder. Shown, never navigable.
      return;
    }
    context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final RoleNavigation navigation = context.read<B>().navigation;
    final List<RoleDestination> visible = navigation.visibleDestinations(
      widget.portalContext.capabilities,
    );

    return BlocBuilder<B, RoleShellState>(
      builder: (BuildContext context, RoleShellState state) {
        // The bloc tracks selection against the full list by path; map that onto
        // the (possibly filtered) visible list so the highlight stays correct.
        final RoleDestination? selected =
            state.selectedIndex >= 0 &&
                state.selectedIndex < navigation.destinations.length
            ? navigation.destinations[state.selectedIndex]
            : null;
        final int visibleIndex = selected == null
            ? 0
            : visible.indexOf(selected).clamp(0, visible.length - 1);

        return switch (navigation.chrome) {
          RoleShellChrome.drawer => _DrawerShell(
            navigation: navigation,
            destinations: visible,
            portalContext: widget.portalContext,
            selectedIndex: visibleIndex,
            onSelected: (int i) => _go(visible[i]),
            body: widget.child,
          ),
          RoleShellChrome.bottomBar => _BottomBarShell(
            navigation: navigation,
            destinations: visible,
            portalContext: widget.portalContext,
            selectedIndex: visibleIndex,
            onSelected: (int i) => _go(visible[i]),
            body: widget.child,
          ),
        };
      },
    );
  }
}

/// The app bar (§ 3.19): 64 tall, a bottom hairline, the identity cluster on the
/// right. The title is the organization name where the backend supplied one,
/// falling back to the portal name — the web omits a name it cannot read rather
/// than fabricating one.
class _ShellAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ShellAppBar({
    required this.navigation,
    required this.portalContext,
    this.leading,
  });

  final RoleNavigation navigation;
  final PortalContext portalContext;
  final Widget? leading;

  @override
  Size get preferredSize => const Size.fromHeight(SrSpacing.appBarHeight);

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final String title =
        portalContext.organizationName ?? navigation.portalName;

    return AppBar(
      leading: leading,
      automaticallyImplyLeading: false,
      titleSpacing: leading == null ? SrSpacing.lg : 0,
      title: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: SrTypography.cardTitle.copyWith(color: sr.foreground),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            navigation.portalName,
            style: SrTypography.caption.copyWith(color: sr.textMuted),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: SrSpacing.lg),
          child: Semantics(
            button: true,
            label: 'Account',
            container: true,
            excludeSemantics: true,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => AccountSheet.show(
                context,
                portalContext: portalContext,
                portalName: navigation.portalName,
              ),
              child: const SrInitialsAvatar(name: null),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bottom navigation on a phone; a navigation rail from 640px up.
class _BottomBarShell extends StatelessWidget {
  const _BottomBarShell({
    required this.navigation,
    required this.destinations,
    required this.portalContext,
    required this.selectedIndex,
    required this.onSelected,
    required this.body,
  });

  final RoleNavigation navigation;
  final List<RoleDestination> destinations;
  final PortalContext portalContext;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final bool wide =
        MediaQuery.sizeOf(context).width >= SrSpacing.breakpointSm;

    if (wide) {
      return Scaffold(
        appBar: _ShellAppBar(
          navigation: navigation,
          portalContext: portalContext,
        ),
        body: Row(
          children: <Widget>[
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelected,
              labelType: NavigationRailLabelType.all,
              destinations: <NavigationRailDestination>[
                for (final RoleDestination d in destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            VerticalDivider(width: 1, color: sr.border),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: _ShellAppBar(
        navigation: navigation,
        portalContext: portalContext,
      ),
      body: body,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: sr.border)),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          destinations: <NavigationDestination>[
            for (final RoleDestination d in destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
                tooltip: d.label,
              ),
          ],
        ),
      ),
    );
  }
}

/// A drawer for a role with more destinations than a bottom bar can carry, and
/// a permanent side panel once there is desktop room for one.
class _DrawerShell extends StatelessWidget {
  const _DrawerShell({
    required this.navigation,
    required this.destinations,
    required this.portalContext,
    required this.selectedIndex,
    required this.onSelected,
    required this.body,
  });

  final RoleNavigation navigation;
  final List<RoleDestination> destinations;
  final PortalContext portalContext;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final bool expanded =
        MediaQuery.sizeOf(context).width >= SrSpacing.breakpointLg;

    final Widget panel = _RoleNavPanel(
      navigation: navigation,
      destinations: destinations,
      selectedIndex: selectedIndex,
      onSelected: (int index) {
        if (!expanded) {
          Navigator.of(context).maybePop();
        }
        onSelected(index);
      },
    );

    if (expanded) {
      return Scaffold(
        body: Row(
          children: <Widget>[
            SizedBox(
              width: SrSpacing.navWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: sr.surfaceNav,
                  border: Border(right: BorderSide(color: sr.border)),
                ),
                child: panel,
              ),
            ),
            Expanded(
              child: Scaffold(
                appBar: _ShellAppBar(
                  navigation: navigation,
                  portalContext: portalContext,
                ),
                body: body,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: _ShellAppBar(
        navigation: navigation,
        portalContext: portalContext,
        leading: Builder(
          builder: (BuildContext context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            tooltip: 'Open navigation menu',
            onPressed: Scaffold.of(context).openDrawer,
          ),
        ),
      ),
      drawer: Drawer(child: panel),
      body: body,
    );
  }
}

/// The sidebar's contents: a 64px header carrying the brand lockup over a
/// hairline, then the items, then the version footer.
class _RoleNavPanel extends StatelessWidget {
  const _RoleNavPanel({
    required this.navigation,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final RoleNavigation navigation;
  final List<RoleDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: SrSpacing.appBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: SrSpacing.lg),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: sr.border)),
            ),
            child: SrBrandLockup(size: 32, portal: navigation.portalName),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: SrSpacing.md,
                vertical: SrSpacing.md,
              ),
              children: <Widget>[
                for (int i = 0; i < destinations.length; i++)
                  _NavItem(
                    destination: destinations[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SrSpacing.lg,
              vertical: SrSpacing.md,
            ),
            child: Text(
              'SalesReward · v0.1',
              style: SrTypography.caption.copyWith(
                fontWeight: FontWeight.w500,
                color: sr.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One sidebar item (§ 3.19): `px-3 py-2`, 12-radius, 14/500, a 20px leading
/// icon 12px from the label. The active state is a brand-tinted fill **plus** a
/// 4 × 24 rail — two signals, because the product never carries meaning by
/// colour alone.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final RoleDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final bool enabled = destination.isEnabled;

    final Color labelColor = !enabled
        ? sr.textMuted
        : selected
        ? sr.navActiveLabel
        : sr.navLabel;

    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SrSpacing.md,
        vertical: SrSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            selected ? destination.selectedIcon : destination.icon,
            size: 20,
            color: labelColor,
          ),
          const SizedBox(width: SrSpacing.md),
          Expanded(
            child: Text(
              destination.label,
              style: SrTypography.label.copyWith(
                color: labelColor,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!enabled) const _SoonPill(),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: SrSpacing.xs),
      child: Semantics(
        button: enabled,
        selected: selected,
        enabled: enabled,
        child: Stack(
          children: <Widget>[
            Material(
              color: selected ? sr.navActiveFill : Colors.transparent,
              borderRadius: BorderRadius.circular(SrRadii.control),
              child: enabled
                  ? InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(SrRadii.control),
                      child: row,
                    )
                  : Tooltip(message: 'Coming soon', child: row),
            ),
            if (selected)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: sr.navActiveRail,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(SrRadii.full),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The trailing "Soon" pill on a disabled nav item.
class _SoonPill extends StatelessWidget {
  const _SoonPill();

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SrSpacing.sm,
        vertical: SrSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: sr.slate.fill,
        borderRadius: BorderRadius.circular(SrRadii.full),
      ),
      child: Text(
        'SOON',
        style: SrTypography.soonPill.copyWith(color: sr.textSecondary),
      ),
    );
  }
}
