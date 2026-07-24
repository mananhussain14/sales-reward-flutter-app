import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/design.dart';
import '../../../core/widgets/widgets.dart';
import '../../../features/auth/domain/entities/app_role.dart';
import '../../navigation/role_destination.dart';
import 'account_sheet.dart';
import 'role_shell_bloc.dart';

/// The shared chrome every role shell is built from.
///
/// ## What it translates
///
/// The web presents one navigation pattern: a fixed **white** 256px sidebar with
/// a 1px slate-200 right border, which below `lg` becomes a left drawer behind a
/// hamburger. This scaffold keeps that identity and adapts the *form* per role,
/// which is decision **D-4** in the design handoff:
///
/// | Web | Mobile |
/// | --- | --- |
/// | Sidebar, 12 entries (Vendor) | [RoleShellChrome.drawer] — same surface, same items, same "Soon" pills |
/// | Sidebar, 2–4 entries (Retailer) | [RoleShellChrome.bottomBar] — a bar on a phone, a rail from 640px |
/// | Sidebar brand lockup | The same lockup in the drawer header |
/// | Indigo active link + 4×24 rail | The same fill and rail in the drawer; a brand-tinted pill in the bar |
/// | App bar identity cluster | The avatar, opening [AccountSheet] |
///
/// > **The drawer is white, not dark.** `--surface-nav` (`#0F172A`) is declared
/// > in `globals.css` but never applied — the shipped sidebar is white — and
/// > § 2.3 of the handoff says explicitly not to build a dark drawer from it.
///
/// ## What it is not
///
/// It is not a role switch. Each shell supplies its own BLoC type and its own
/// navigation model; this widget never asks which role it is rendering, and
/// there is no `if (role == …)` anywhere in it. That is the difference between
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
  /// step with deep links, the back gesture and guard redirects.
  final String location;

  /// The role this shell was built for, and how far it can be trusted.
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

  /// Dispatched from the lifecycle rather than from `build`, so the shell never
  /// mutates BLoC state while the tree is being laid out.
  void _syncLocation() {
    context.read<B>().add(RoleShellLocationChanged(widget.location));
  }

  void _go(RoleNavigation navigation, int index) {
    if (index < 0 || index >= navigation.destinations.length) {
      return;
    }
    final String? path = navigation.destinations[index].path;
    if (path == null) {
      // A "Soon" placeholder. Shown, never navigable.
      return;
    }
    context.read<B>().add(RoleShellDestinationSelected(index));
    context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final RoleNavigation navigation = context.read<B>().navigation;

    return BlocBuilder<B, RoleShellState>(
      builder: (BuildContext context, RoleShellState state) {
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
            onSelected: (int i) => _go(navigation, i),
            body: body,
          ),
          RoleShellChrome.bottomBar => _BottomBarShell(
            navigation: navigation,
            resolved: widget.resolved,
            selectedIndex: state.selectedIndex,
            onSelected: (int i) => _go(navigation, i),
            body: body,
          ),
        };
      },
    );
  }
}

/// The app bar (§ 3.19): 64 tall, the portal title at 16/600, a bottom hairline,
/// and the identity cluster on the right.
class _ShellAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ShellAppBar({
    required this.navigation,
    required this.resolved,
    this.leading,
  });

  final RoleNavigation navigation;
  final ResolvedRole resolved;
  final Widget? leading;

  @override
  Size get preferredSize => const Size.fromHeight(SrSpacing.appBarHeight);

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return AppBar(
      leading: leading,
      automaticallyImplyLeading: false,
      titleSpacing: leading == null ? SrSpacing.lg : 0,
      title: Text(
        navigation.portalName,
        style: SrTypography.cardTitle.copyWith(color: sr.foreground),
        overflow: TextOverflow.ellipsis,
      ),
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: SrSpacing.lg),
          child: Semantics(
            button: true,
            label: 'Account',
            container: true,
            // The avatar's initials are decorative here; the button's own
            // label is what assistive technology should announce.
            excludeSemantics: true,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => AccountSheet.show(
                context,
                role: resolved,
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

/// A permanent, non-dismissible reminder that the role in effect was chosen
/// locally.
///
/// It cannot be hidden on purpose: a preview role authorizes nothing, and the
/// moment this banner can be dismissed, a screenshot of this build becomes
/// indistinguishable from one where role resolution actually works.
class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner({required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final SrToneColors colors = context.sr.tone(SrTone.amber);

    return Material(
      color: colors.fill,
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
              color: colors.foreground,
            ),
            const SizedBox(width: SrSpacing.sm),
            Expanded(
              child: Text(
                'Interface preview — ${role.displayName} was selected on this '
                'device. It grants no access.',
                style: SrTypography.caption.copyWith(
                  color: colors.alertText,
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
    required this.body,
  });

  final RoleNavigation navigation;
  final ResolvedRole resolved;
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
        appBar: _ShellAppBar(navigation: navigation, resolved: resolved),
        body: Row(
          children: <Widget>[
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelected,
              labelType: NavigationRailLabelType.all,
              destinations: <NavigationRailDestination>[
                for (final RoleDestination d in navigation.destinations)
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
      appBar: _ShellAppBar(navigation: navigation, resolved: resolved),
      body: body,
      bottomNavigationBar: DecoratedBox(
        // The bar's 1px top hairline, matching the sidebar's right border.
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: sr.border)),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          destinations: <NavigationDestination>[
            for (final RoleDestination d in navigation.destinations)
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
    final SrColorScheme sr = context.sr;
    final bool expanded =
        MediaQuery.sizeOf(context).width >= SrSpacing.breakpointLg;

    final Widget panel = _RoleNavPanel(
      navigation: navigation,
      selectedIndex: selectedIndex,
      onSelected: (int index) {
        // Tapping an item closes the drawer, as the web's does.
        if (!expanded) {
          Navigator.of(context).maybePop();
        }
        onSelected(index);
      },
    );

    // At desktop width the drawer stops being modal and simply sits beside the
    // content — the web layout again.
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
                  resolved: resolved,
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
        resolved: resolved,
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
    required this.selectedIndex,
    required this.onSelected,
  });

  final RoleNavigation navigation;
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
                for (int i = 0; i < navigation.destinations.length; i++)
                  _NavItem(
                    destination: navigation.destinations[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
              ],
            ),
          ),
          // The sidebar footer, verbatim from the web.
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
/// icon 12px from the label.
///
/// The active state is a brand-tinted fill **plus** a 4 × 24 rail flush to the
/// left edge — deliberately two signals, because the product never carries
/// meaning by colour alone.
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
                  // Not a link and not tappable, matching `title="Coming soon"`
                  // on the web.
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
