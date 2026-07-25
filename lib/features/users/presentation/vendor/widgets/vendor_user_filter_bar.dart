import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_user_status.dart';
import 'vendor_user_badges.dart';
import 'vendor_user_copy.dart';

/// Search and status narrowing for the Vendor user directory.
///
/// ## All of it is local, and the hint says so
///
/// `list_vendor_users()` takes no arguments — it has no search or filter
/// parameter by design — and returns the Vendor's whole directory in one
/// unpaginated response, so narrowing the loaded rows narrows the complete
/// trusted answer. Nothing typed here is sent anywhere; the field hint states
/// that plainly, because a search box that silently queries a server and one
/// that filters in memory behave differently the moment a connection drops.
///
/// ## Two filter rows, because there are two independent statuses
///
/// A person's profile status and their membership status in this Vendor are
/// separate facts. One combined filter would make "active profile, suspended
/// membership" unreachable, which is exactly the case an administrator opens
/// this screen to find.
///
/// ## The chips are built from the data, not from the enum
///
/// Each row's options come from the statuses actually present in the loaded
/// rows. A chip that could only ever produce an empty list would be a filter for
/// a status this Vendor's directory does not contain, and offering one implies
/// the backend uses a value it has not sent. A row with fewer than two distinct
/// statuses is not shown at all — there would be nothing to choose between.
class VendorUserFilterBar extends StatefulWidget {
  const VendorUserFilterBar({
    super.key,
    required this.searchTerm,
    required this.profileFilter,
    required this.membershipFilter,
    required this.availableProfileStatuses,
    required this.availableMembershipStatuses,
    required this.onSearchChanged,
    required this.onProfileStatusChanged,
    required this.onMembershipStatusChanged,
    required this.onClear,
  });

  final String searchTerm;
  final VendorUserStatus? profileFilter;
  final VendorUserStatus? membershipFilter;
  final List<VendorUserStatus> availableProfileStatuses;
  final List<VendorUserStatus> availableMembershipStatuses;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<VendorUserStatus?> onProfileStatusChanged;
  final ValueChanged<VendorUserStatus?> onMembershipStatusChanged;
  final VoidCallback onClear;

  bool get _hasFilters =>
      searchTerm.trim().isNotEmpty ||
      profileFilter != null ||
      membershipFilter != null;

  @override
  State<VendorUserFilterBar> createState() => _VendorUserFilterBarState();
}

class _VendorUserFilterBarState extends State<VendorUserFilterBar> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.searchTerm,
  );

  @override
  void didUpdateWidget(VendorUserFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keeps the field in step when the term is cleared from outside — by the
    // "Clear filters" action, or by a session change wiping the cubit. Guarded
    // on inequality so typing is never fought by a rebuild.
    if (widget.searchTerm != _controller.text) {
      _controller.text = widget.searchTerm;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SrTextField(
          label: VendorUserCopy.searchLabel,
          controller: _controller,
          placeholder: VendorUserCopy.searchPlaceholder,
          hint: VendorUserCopy.searchHint,
          showOptionalMarker: false,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
          onChanged: widget.onSearchChanged,
          suffix: widget.searchTerm.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Clear search',
                  onPressed: () => widget.onSearchChanged(''),
                ),
        ),
        _StatusFilterRow(
          label: VendorUserCopy.profileFilterLabel,
          statuses: widget.availableProfileStatuses,
          selected: widget.profileFilter,
          onChanged: widget.onProfileStatusChanged,
        ),
        _StatusFilterRow(
          label: VendorUserCopy.membershipFilterLabel,
          statuses: widget.availableMembershipStatuses,
          selected: widget.membershipFilter,
          onChanged: widget.onMembershipStatusChanged,
        ),
        if (widget._hasFilters) ...<Widget>[
          const SizedBox(height: SrSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SrButton(
              label: VendorUserCopy.clearFilters,
              variant: SrButtonVariant.ghost,
              size: SrButtonSize.sm,
              icon: Icons.filter_alt_off_outlined,
              onPressed: widget.onClear,
            ),
          ),
        ],
      ],
    );
  }
}

/// One labelled row of status chips, or nothing.
class _StatusFilterRow extends StatelessWidget {
  const _StatusFilterRow({
    required this.label,
    required this.statuses,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<VendorUserStatus> statuses;
  final VendorUserStatus? selected;
  final ValueChanged<VendorUserStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    // Only worth offering when there is more than one thing to choose between.
    if (statuses.length < 2) {
      return const SizedBox.shrink();
    }
    final SrColorScheme sr = context.sr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: SrSpacing.lg),
        Text(label, style: SrTypography.label.copyWith(color: sr.textLabel)),
        const SizedBox(height: SrSpacing.sm),
        Wrap(
          spacing: SrSpacing.sm,
          runSpacing: SrSpacing.sm,
          children: <Widget>[
            _StatusChip(
              label: VendorUserCopy.filterAll,
              semanticsLabel: '$label: ${VendorUserCopy.filterAll}',
              selected: selected == null,
              onPressed: () => onChanged(null),
            ),
            for (final VendorUserStatus status in statuses)
              _StatusChip(
                label: VendorUserStatusBadge.labelFor(status),
                semanticsLabel:
                    '$label: ${VendorUserStatusBadge.labelFor(status)}',
                selected: selected == status,
                onPressed: () => onChanged(status),
              ),
          ],
        ),
      ],
    );
  }
}

/// One filter chip.
///
/// An [SrButton] rather than a Material `FilterChip`: the product's controls are
/// 12-radius with a semibold label and a `shadow-sm`, and a Material chip would
/// read as a different application. Selection is carried by the filled variant,
/// by a check glyph **and** by the semantics flag, so it is never conveyed by
/// fill alone.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.semanticsLabel,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final String semanticsLabel;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      selected: selected,
      button: true,
      child: SrButton(
        label: label,
        variant: selected ? SrButtonVariant.primary : SrButtonVariant.outline,
        size: SrButtonSize.sm,
        icon: selected ? Icons.check_rounded : null,
        onPressed: onPressed,
      ),
    );
  }
}
