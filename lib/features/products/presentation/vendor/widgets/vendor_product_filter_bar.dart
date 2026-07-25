import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_product_status.dart';
import 'vendor_product_badges.dart';
import 'vendor_product_copy.dart';

/// Search and status narrowing for the product catalogue.
///
/// ## All of it is local, and the hint says so
///
/// `list_vendor_products()` takes no arguments — it has no search, status or
/// filter parameter by design — and returns the whole catalogue in one
/// unpaginated response, so narrowing the loaded rows narrows the complete
/// trusted answer. Nothing typed here is sent anywhere; the field hint states
/// that plainly, because a search box that silently queries a server and one
/// that filters in memory behave differently the moment a connection drops.
///
/// A *server-side* status filter would be worse than merely absent: it would put
/// a status value in a caller's hands, which the backend contract deliberately
/// refuses.
///
/// ## Four fields, all of them visible
///
/// The search matches product **name, code, barcode and brand** — every text
/// field a reader can actually see on a card — case-insensitively. The
/// description is deliberately excluded: matching a paragraph would surface rows
/// whose reason for matching is nowhere in the result.
///
/// ## The chips are built from the data, not from the enum
///
/// The options come from the statuses actually present in the loaded rows. A
/// chip that could only ever produce an empty list would be a filter for a
/// status this catalogue does not contain, and offering one implies the backend
/// uses a value it has not sent. With fewer than two distinct statuses the row
/// is not shown at all — there would be nothing to choose between.
class VendorProductFilterBar extends StatefulWidget {
  const VendorProductFilterBar({
    super.key,
    required this.searchTerm,
    required this.statusFilter,
    required this.availableStatuses,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onClear,
  });

  final String searchTerm;
  final VendorProductStatus? statusFilter;
  final List<VendorProductStatus> availableStatuses;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<VendorProductStatus?> onStatusChanged;
  final VoidCallback onClear;

  bool get _hasFilters => searchTerm.trim().isNotEmpty || statusFilter != null;

  @override
  State<VendorProductFilterBar> createState() => _VendorProductFilterBarState();
}

class _VendorProductFilterBarState extends State<VendorProductFilterBar> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.searchTerm,
  );

  @override
  void didUpdateWidget(VendorProductFilterBar oldWidget) {
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
          label: VendorProductCopy.searchLabel,
          controller: _controller,
          placeholder: VendorProductCopy.searchPlaceholder,
          hint: VendorProductCopy.searchHint,
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
              label: VendorProductCopy.clearFilters,
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

  final List<VendorProductStatus> statuses;
  final VendorProductStatus? selected;
  final ValueChanged<VendorProductStatus?> onChanged;

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
          VendorProductCopy.statusFilterLabel,
          style: SrTypography.label.copyWith(color: sr.textLabel),
        ),
        const SizedBox(height: SrSpacing.sm),
        Wrap(
          spacing: SrSpacing.sm,
          runSpacing: SrSpacing.sm,
          children: <Widget>[
            _StatusChip(
              label: VendorProductCopy.filterAll,
              semanticsLabel:
                  '${VendorProductCopy.statusFilterLabel}: '
                  '${VendorProductCopy.filterAll}',
              selected: selected == null,
              onPressed: () => onChanged(null),
            ),
            for (final VendorProductStatus status in statuses)
              _StatusChip(
                label: VendorProductStatusBadge.labelFor(status),
                semanticsLabel: VendorProductStatusBadge.semanticsFor(status),
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
