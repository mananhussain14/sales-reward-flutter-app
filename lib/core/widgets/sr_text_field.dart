import 'package:flutter/material.dart';

import '../design/design.dart';

/// The standard single-line text field, translated from `TextField` in the web
/// application's `components/ui/field.tsx`.
///
/// ## The layout rule, preserved
///
/// The web component carries a deliberate, documented rule: the label sits on
/// top, the control directly beneath it, and the hint **or** the error is
/// rendered BELOW the control — never between the label and the input. That is
/// what lets two fields side by side keep their inputs on the same row when only
/// one of them has a hint.
///
/// Mobile stacks fields vertically, so the alignment argument does not apply —
/// but the rule is kept anyway, because it also means a message only ever grows
/// downward and never pushes the control the user is typing into.
///
/// A hint and an error are mutually exclusive: when both are supplied the error
/// wins, and `aria-describedby` on the web points at whichever is rendered. The
/// Flutter equivalent is that only one message widget exists in the tree.
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
    this.autofillHints,
    this.maxLength,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController? controller;

  /// Guidance shown under the control when there is no [errorText].
  final String? hint;

  /// A validation message. When present it replaces [hint] and tints the border.
  final String? errorText;

  final String? placeholder;

  /// Renders the visible `*` marker, so a requirement is not left to color or
  /// placement alone.
  final bool required;

  /// Renders the "(optional)" marker. Defaults to the inverse of [required].
  final bool? showOptionalMarker;

  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<String>? autofillHints;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final bool hasError = errorText != null;
    final bool optional = showOptionalMarker ?? !required;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Label(label: label, required: required, optional: optional),
        const SizedBox(height: SrSpacing.sm),
        TextField(
          controller: controller,
          obscureText: obscureText,
          enabled: enabled,
          readOnly: readOnly,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          maxLength: maxLength,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: SrTypography.body,
          cursorColor: SrColors.brand,
          decoration: InputDecoration(
            hintText: placeholder,
            // The message is rendered below by this widget rather than by
            // InputDecoration, so the two never disagree about which one shows
            // and the field keeps a stable height.
            counterText: '',
            errorText: null,
            helperText: null,
            enabledBorder: hasError
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SrRadii.lg),
                    borderSide: const BorderSide(color: SrColors.red400),
                  )
                : null,
            focusedBorder: hasError
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SrRadii.lg),
                    borderSide: const BorderSide(
                      color: SrColors.red600,
                      width: 2,
                    ),
                  )
                : null,
            fillColor: enabled ? SrColors.surface : SrColors.appBackground,
          ),
        ),
        if (hasError) ...<Widget>[
          const SizedBox(height: SrSpacing.sm),
          Text(errorText!, style: SrTypography.fieldError),
        ] else if (hint != null) ...<Widget>[
          const SizedBox(height: SrSpacing.sm),
          Text(hint!, style: SrTypography.caption),
        ],
      ],
    );
  }
}

/// A labelled wrapper for a control this package does not provide (a dropdown,
/// a date picker, a segmented control), so those still get the product's label,
/// hint and error treatment. Mirrors the web's generic `Field`.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Label(label: label, required: required, optional: !required),
        const SizedBox(height: SrSpacing.sm),
        child,
        if (errorText != null) ...<Widget>[
          const SizedBox(height: SrSpacing.sm),
          Text(errorText!, style: SrTypography.fieldError),
        ] else if (hint != null) ...<Widget>[
          const SizedBox(height: SrSpacing.sm),
          Text(hint!, style: SrTypography.caption),
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
    return Text.rich(
      TextSpan(
        text: label,
        style: SrTypography.label,
        children: <InlineSpan>[
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: SrColors.red600),
            ),
          if (optional)
            TextSpan(
              text: ' (optional)',
              style: SrTypography.label.copyWith(
                fontWeight: FontWeight.w400,
                color: SrColors.slate400,
              ),
            ),
        ],
      ),
    );
  }
}
