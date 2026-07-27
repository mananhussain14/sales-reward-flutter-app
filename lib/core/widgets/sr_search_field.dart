import 'package:flutter/material.dart';

import 'sr_text_field.dart';

/// A local-filter search box.
///
/// ## It filters, it does not query
///
/// Every use of this widget in the Retailer portal drives a **presentation
/// filter over rows already read**. Nothing typed here is sent anywhere: the
/// four Retailer RPCs take zero arguments, so there is no parameter a term could
/// travel through even if someone tried.
///
/// That is why [hint] is required rather than optional. A search box that does
/// not say what it searches invites a user to conclude a shop is missing when it
/// is merely not matched by the fields the contract returned — so each caller
/// states its own coverage in words.
///
/// Owns its controller so the clear button can empty the field. The controller
/// is seeded from [term] and resynchronised when the parent resets it, which is
/// what makes a session change clear the box rather than leave the previous
/// person's search fragment visible.
class SrSearchField extends StatefulWidget {
  const SrSearchField({
    super.key,
    required this.label,
    required this.hint,
    required this.term,
    required this.onChanged,
    this.placeholder,
  });

  final String label;

  /// What this search actually covers. Required — see the class doc.
  final String hint;

  /// The current term, owned by the cubit.
  final String term;

  final ValueChanged<String> onChanged;
  final String? placeholder;

  @override
  State<SrSearchField> createState() => _SrSearchFieldState();
}

class _SrSearchFieldState extends State<SrSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.term,
  );

  @override
  void didUpdateWidget(SrSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Resynchronise only when the two genuinely disagree, so typing is not
    // interrupted by the rebuild its own onChanged caused. The case that matters
    // is the cubit clearing the term on a session change: the field must empty
    // itself rather than keep the previous person's search fragment on screen.
    if (widget.term != _controller.text) {
      _controller.text = widget.term;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SrTextField(
      label: widget.label,
      controller: _controller,
      placeholder: widget.placeholder,
      hint: widget.hint,
      showOptionalMarker: false,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.search,
      onChanged: widget.onChanged,
      suffix: widget.term.isEmpty
          ? null
          : IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: 'Clear search',
              onPressed: () {
                _controller.clear();
                widget.onChanged('');
              },
            ),
    );
  }
}
