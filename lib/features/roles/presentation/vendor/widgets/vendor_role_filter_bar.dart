import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_role_status.dart';
import 'vendor_role_badges.dart';
import 'vendor_role_copy.dart';

/// Search and status narrowing for the role catalogue.
///
/// ## All of it is local, and the hint says so
///
/// `list_vendor_roles()` takes no arguments — it has no search, status or filter
/// parameter by design — and returns the whole catalogue in one unpaginated
/// response, so narrowing the loaded rows narrows the complete trusted answer.
/// Nothing typed here is sent anywhere; the field hint states that plainly,
/// because a search box that silently queries a server and one that filters in
/// memory behave differently the moment a connection drops.
///
/// ## Name only
///
/// The search matches the role **name**, which is the only text a reader can see
/// and the only one the contract returns for matching. There is no code to
/// search — codes are authorization vocabulary and are not returned at all.
///
/// ## The chips are built from the data, not from the enum
///
/// The options come from the statuses actually present in the loaded rows. A
/// chip that could only ever produce an empty list would be a filter for a
/// status this catalogue does not contain, and offering one implies the backend
/// uses a value it has not sent. With fewer than two distinct statuses the row
/// is not shown at all — there would be nothing to choose between.
class VendorRoleFilterBar extends StatefulWidget {
  const VendorRoleFilterBar({
    super.key,
    required this.searchTerm,
    required this.statusFilter,
    required this.availableStatuses,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onClear,
  });

  final String searchTerm;
  final VendorRoleStatus? statusFilter;
  final List<VendorRoleStatus> availableStatuses;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<VendorRoleStatus?> onStatusChanged;
  final VoidCallback onClear;

  bool get _hasFilters => searchTerm.trim().isNotEmpty || statusFilter != null;

  @override
  State<VendorRoleFilterBar> createState() => _VendorRoleFilterBarState();
}

class _VendorRoleFilterBarState extends State<VendorRoleFilterBar> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.searchTerm,
  );

  @override
  void didUpdateWidget(VendorRoleFilterBar oldWidget) {
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
          label: VendorRoleCopy.searchLabel,
          controller: _controller,
          placeholder: VendorRoleCopy.searchPlaceholder,
          hint: VendorRoleCopy.searchHint,
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
          statuses: widget.availableStatuses,
          selected: widget.statusFilter,
          onChanged: widget.onStatusChanged,
        ),
        if (widget._hasFilters) ...<Widget>[
          const SizedBox(height: SrSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SrButton(
              label: VendorRoleCopy.clearFilters,
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

/// The labelled row of status chips, or nothing.
class _StatusFilterRow extends StatelessWidget {
  const _StatusFilterRow({
    required this.statuses,
    required this.selected,
    required this.onChanged,
  });

  final List<VendorRoleStatus> statuses;
  final VendorRoleStatus? selected;
  final ValueChanged<VendorRoleStatus?> onChanged;

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
        Text(
          VendorRoleCopy.statusFilterLabel,
          style: SrTypography.label.copyWith(color: sr.textLabel),
        ),
        const SizedBox(height: SrSpacing.sm),
        Wrap(
          spacing: SrSpacing.sm,
          runSpacing: SrSpacing.sm,
          children: <Widget>[
            _StatusChip(
              label: VendorRoleCopy.filterAll,
              semanticsLabel:
                  '${VendorRoleCopy.statusFilterLabel}: '
                  '${VendorRoleCopy.filterAll}',
              selected: selected == null,
              onPressed: () => onChanged(null),
            ),
            for (final VendorRoleStatus status in statuses)
              _StatusChip(
                label: VendorRoleStatusBadge.labelFor(status),
                semanticsLabel: VendorRoleStatusBadge.semanticsFor(status),
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
