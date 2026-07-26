import 'package:flutter/material.dart';

import '../design/design.dart';

/// The standard single-line text field (§ 3.2).
///
/// ## The layout rule, which is load-bearing
///
/// Label on top → control directly beneath → hint **or** error **below the
/// control**. Guidance never sits between the label and the input.
/// `components/ui/field.tsx` documents this as a CRITICAL LAYOUT RULE: it is
/// what lets two fields in a two-column grid keep their inputs on the same row
/// when only one of them has a hint.
///
/// Mobile stacks fields vertically, so the alignment argument does not apply —
/// but the rule is kept anyway, because it also means a message only ever grows
/// downward and never displaces the control the user is typing into.
///
/// Vertical rhythm: 8px label → control, 8px control → message, 20px between
/// fields (the caller supplies the last one).
class SrTextField extends StatelessWidget {
  const SrTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.errorText,
    this.placeholder,
    this.required = false,
    this.showOptionalMarker,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.maxLength,
    this.minLines,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.suffix,
  });

  final String label;
  final TextEditingController? controller;

  /// Guidance below the control, shown when there is no [errorText].
  final String? hint;

  /// A validation message. Replaces [hint] and tints the border.
  final String? errorText;

  final String? placeholder;

  /// Renders a **visible** red asterisk. Requirement is never signalled by
  /// colour or placement alone.
  final bool required;

  /// Renders the "(optional)" affix. Defaults to the inverse of [required].
  final bool? showOptionalMarker;

  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  /// How the soft keyboard capitalizes what is typed.
  ///
  /// A *keyboard* behaviour and never a transform: nothing is upper-cased on the
  /// caller's behalf by this widget, so a field whose stored value is case-folded
  /// still owns that rule itself.
  final TextCapitalization textCapitalization;

  final List<String>? autofillHints;
  final int? maxLength;

  /// The height the control starts at, in lines.
  final int? minLines;

  /// The height the control grows to, in lines. `1` — the default — keeps the
  /// field single-line, which is what every existing caller wants.
  ///
  /// A multi-line field passes both: text wraps and the control grows with it
  /// rather than scrolling a long value out of sight sideways. Newlines survive,
  /// which matters wherever the value's own formatting is content rather than
  /// noise — a product description being the case this was added for.
  final int? maxLines;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  /// A control rendered inside the field's trailing edge — the password
  /// visibility toggle being the only current use.
  ///
  /// Constrained to the control's 44px height so adding one cannot change the
  /// field's geometry, which is what keeps a row of fields aligned.
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;
    final bool hasError = errorText != null;

    final Widget field = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Label(
          label: label,
          required: required,
          optional: showOptionalMarker ?? !required,
        ),
        const SizedBox(height: SrSpacing.sm),
        TextField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscureText,
          enabled: enabled,
          readOnly: readOnly,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          textCapitalization: textCapitalization,
          autofillHints: autofillHints,
          maxLength: maxLength,
          minLines: minLines,
          maxLines: maxLines,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: SrTypography.body.copyWith(color: sr.foreground),
          cursorColor: sr.brand,
          decoration: InputDecoration(
            hintText: placeholder,
            // The message is rendered below by this widget, not by
            // InputDecoration, so the two can never disagree about which one
            // shows and the field keeps a stable height.
            counterText: '',
            errorText: null,
            helperText: null,
            fillColor: enabled ? sr.inputFill : sr.inputDisabledFill,
            suffixIcon: suffix,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 44,
            ),
            enabledBorder: hasError ? _border(sr.inputErrorBorder) : null,
            focusedBorder: hasError
                ? _border(sr.inputErrorFocusBorder, width: 2)
                : null,
          ),
        ),
        if (hasError) ...<Widget>[
          const SizedBox(height: SrSpacing.sm),
          Text(
            errorText!,
            style: SrTypography.fieldError.copyWith(color: sr.fieldError),
          ),
        ] else if (hint != null) ...<Widget>[
          const SizedBox(height: SrSpacing.sm),
          Text(
            hint!,
            style: SrTypography.caption.copyWith(color: sr.textSecondary),
          ),
        ],
      ],
    );

    // § 2.6: a disabled control drops to 70% over the muted fill.
    return enabled ? field : Opacity(opacity: 0.7, child: field);
  }

  static OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(SrRadii.control),
        borderSide: BorderSide(color: color, width: width),
      );
}

/// A labelled wrapper for a control this package does not provide — a dropdown,
/// a date picker, a segmented control — so those still take the product's
/// label, hint and error treatment.
class SrField extends StatelessWidget {
  const SrField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
    this.errorText,
    this.required = false,
  });

  final String label;
  final Widget child;
  final String? hint;
  final String? errorText;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Label(label: label, required: required, optional: !required),
        const SizedBox(height: SrSpacing.sm),
        child,
        if (errorText != null) ...<Widget>[
          const SizedBox(height: SrSpacing.sm),
          Text(
            errorText!,
            style: SrTypography.fieldError.copyWith(color: sr.fieldError),
          ),
        ] else if (hint != null) ...<Widget>[
          const SizedBox(height: SrSpacing.sm),
          Text(
            hint!,
            style: SrTypography.caption.copyWith(color: sr.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({
    required this.label,
    required this.required,
    required this.optional,
  });

  final String label;
  final bool required;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Text.rich(
      TextSpan(
        text: label,
        style: SrTypography.label.copyWith(color: sr.textLabel),
        children: <InlineSpan>[
          if (required)
            TextSpan(
              text: ' *',
              style: TextStyle(color: sr.dangerFill),
            ),
          if (optional)
            TextSpan(
              text: ' (optional)',
              style: SrTypography.label.copyWith(
                fontWeight: FontWeight.w400,
                color: sr.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}
