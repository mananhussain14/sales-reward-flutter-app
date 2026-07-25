import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_retailer_status.dart';
import 'vendor_retailer_badges.dart';
import 'vendor_retailer_copy.dart';

/// Search and status narrowing for the Retailer directory.
///
/// ## Both are local, and the hint says so
///
/// `list_vendor_retailers()` takes no arguments and returns the Vendor's whole
/// directory in one unpaginated response, so narrowing the loaded rows narrows
/// the complete trusted answer. Nothing typed here is sent anywhere — the field
/// hint states that plainly, because a search box that silently queries a server
/// and one that filters in memory behave differently the moment a connection
/// drops.
///
/// ## The status chips are built from the data, not from the enum
///
/// [availableStatuses] comes from the statuses actually present in the loaded
/// rows. A chip that could only ever produce an empty list would be a filter for
/// a status this Vendor's directory does not contain, and offering one implies
/// the backend uses a value it has not sent.
class VendorRetailerFilterBar extends StatefulWidget {
  const VendorRetailerFilterBar({
    super.key,
    required this.searchTerm,
    required this.statusFilter,
    required this.availableStatuses,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onClear,
  });

  final String searchTerm;
  final VendorRetailerStatus? statusFilter;
  final List<VendorRetailerStatus> availableStatuses;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<VendorRetailerStatus?> onStatusChanged;
  final VoidCallback onClear;

  bool get _hasFilters => searchTerm.trim().isNotEmpty || statusFilter != null;

  @override
  State<VendorRetailerFilterBar> createState() =>
      _VendorRetailerFilterBarState();
}

class _VendorRetailerFilterBarState extends State<VendorRetailerFilterBar> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.searchTerm,
  );

  @override
  void didUpdateWidget(VendorRetailerFilterBar oldWidget) {
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
    final SrColorScheme sr = context.sr;
    // Only worth offering when there is more than one thing to choose between.
    final bool showStatusChips = widget.availableStatuses.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SrTextField(
          label: VendorRetailerCopy.searchLabel,
          controller: _controller,
          placeholder: VendorRetailerCopy.searchPlaceholder,
          hint: VendorRetailerCopy.searchHint,
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
        if (showStatusChips) ...<Widget>[
          const SizedBox(height: SrSpacing.lg),
          Text(
            VendorRetailerCopy.filterLabel,
            style: SrTypography.label.copyWith(color: sr.textLabel),
          ),
          const SizedBox(height: SrSpacing.sm),
          Wrap(
            spacing: SrSpacing.sm,
            runSpacing: SrSpacing.sm,
            children: <Widget>[
              _StatusChip(
                label: VendorRetailerCopy.filterAll,
                selected: widget.statusFilter == null,
                onPressed: () => widget.onStatusChanged(null),
              ),
              for (final VendorRetailerStatus status
                  in widget.availableStatuses)
                _StatusChip(
                  label: VendorRetailerStatusBadge.labelFor(status),
                  selected: widget.statusFilter == status,
                  onPressed: () => widget.onStatusChanged(status),
                ),
            ],
          ),
        ],
        if (widget._hasFilters) ...<Widget>[
          const SizedBox(height: SrSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SrButton(
              label: VendorRetailerCopy.clearFilters,
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

/// One filter chip.
///
/// An [SrButton] rather than a Material `FilterChip`: the product's controls are
/// 12-radius with a semibold label and a `shadow-sm`, and a Material chip would
/// read as a different application. Selection is carried by the filled variant
/// **and** by the semantics flag, so it is never conveyed by fill alone.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
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
