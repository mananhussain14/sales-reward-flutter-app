import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/vendor_product_field.dart';
import '../../../domain/entities/vendor_product_input.dart';
import 'vendor_product_copy.dart';

/// The product fields, shared by the create and edit screens.
///
/// One widget for both, because the fields *are* the same four values plus a code
/// that is editable in one place and read-only in the other. Two copies would be
/// two places for a label, a hint, a maximum length or an autofill behaviour to
/// drift, and the pair would immediately disagree about what a barcode hint says.
///
/// ## The product code is the difference, and it is a mode rather than a field
///
/// [codeIsReadOnly] switches the code between an editable control and read-only
/// context. It is never *hidden* on the edit screen: a person needs to know which
/// product they are changing, and the code is the identifier they actually use. It
/// is never submitted from there either — the edit request type has no field for
/// it — so read-only here is a courtesy to the reader rather than the enforcement,
/// which lives in a trigger and in the absence of an RPC parameter.
///
/// ## What is deliberately not here
///
/// No status selector, on either screen. `create_vendor_product` has no
/// initial-status argument and `update_vendor_product` never writes `status`, so a
/// control for it would be a promise no RPC can keep; activating and deactivating
/// is a separate action with its own confirmation.
///
/// No Vendor or organization selector: the Vendor is derived from `auth.uid()` in
/// SQL and cannot be nominated. No Retailer picker, assignment checkbox or bulk
/// control: assignment writes are a separate milestone on a separate permission.
/// No price, stock, quantity, image, upload, reward, incentive, campaign or receipt
/// field: none of those columns exists anywhere in the schema.
///
/// No barcode scanner and no "generate" button. Nothing in the deployed contract
/// produces a barcode or a product code — both are typed by an administrator — and
/// a scan affordance would be a camera integration invented to decorate a form.
///
/// ## Accessibility
///
/// Every control carries its own visible label, and requirement is marked with a
/// visible asterisk while optional fields carry a visible "(optional)" — never
/// colour alone. A validation message replaces the field's hint **below** the
/// control, so it never displaces what is being typed, and it is announced because
/// it is part of the field's own semantics. Focus moves to the first offending
/// control after a refused submission, in reading order.
class VendorProductFormFields extends StatefulWidget {
  const VendorProductFormFields({
    super.key,
    required this.values,
    required this.fieldErrors,
    required this.enabled,
    required this.codeIsReadOnly,
    required this.onFieldChanged,
    this.firstInvalidField,
  });

  /// The values to display. Raw while typing; the normalized ones after a
  /// submission, which is when the controllers are re-synced.
  final VendorProductFormValues values;

  final Map<VendorProductField, String> fieldErrors;

  /// False while a write is in flight or has settled, which disables every control
  /// so a submitted form cannot be edited underneath its own request.
  final bool enabled;

  /// True on the edit screen, where the code is immutable context.
  final bool codeIsReadOnly;

  final void Function(VendorProductField field, String value) onFieldChanged;

  /// The control focus should move to after a refused submission.
  final VendorProductField? firstInvalidField;

  @override
  State<VendorProductFormFields> createState() =>
      _VendorProductFormFieldsState();
}

class _VendorProductFormFieldsState extends State<VendorProductFormFields> {
  late final Map<VendorProductField, TextEditingController> _controllers;
  late final Map<VendorProductField, FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = <VendorProductField, TextEditingController>{
      for (final VendorProductField field in VendorProductField.values)
        field: TextEditingController(text: _valueOf(widget.values, field)),
    };
    _focusNodes = <VendorProductField, FocusNode>{
      for (final VendorProductField field in VendorProductField.values)
        field: FocusNode(debugLabel: field.key),
    };
  }

  @override
  void didUpdateWidget(VendorProductFormFields oldWidget) {
    super.didUpdateWidget(oldWidget);

    // The controllers follow the cubit, but only when the cubit's value genuinely
    // differs from what is in the box. Assigning unconditionally would move the
    // caret to the end on every keystroke; assigning never would leave the
    // normalized values a submission produced — and a whole seeded form — invisible.
    for (final VendorProductField field in VendorProductField.values) {
      final String incoming = _valueOf(widget.values, field);
      final TextEditingController controller = _controllers[field]!;
      if (controller.text != incoming) {
        controller.value = TextEditingValue(
          text: incoming,
          selection: TextSelection.collapsed(offset: incoming.length),
        );
      }
    }

    // Focus the first offending control, once, when a submission is refused.
    // Conditioned on the field having *changed* so a rebuild for any other reason
    // — a theme change, a parent's state — does not steal focus back from somebody
    // who has already moved on to fix a different field.
    final VendorProductField? invalid = widget.firstInvalidField;
    if (invalid != null && invalid != oldWidget.firstInvalidField) {
      // The code control on the edit screen is read-only and never invalid, so
      // this can only ever target something focusable.
      _focusNodes[invalid]?.requestFocus();
    }
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers.values) {
      controller.dispose();
    }
    for (final FocusNode node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  static String _valueOf(
    VendorProductFormValues values,
    VendorProductField field,
  ) => switch (field) {
    VendorProductField.productCode => values.productCode,
    VendorProductField.productName => values.productName,
    VendorProductField.barcode => values.barcode,
    VendorProductField.brand => values.brand,
    VendorProductField.description => values.description,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.codeIsReadOnly)
          _ReadOnlyCode(code: widget.values.productCode)
        else
          SrTextField(
            label: VendorProductCopy.codeLabel,
            controller: _controllers[VendorProductField.productCode],
            focusNode: _focusNodes[VendorProductField.productCode],
            required: true,
            enabled: widget.enabled,
            placeholder: VendorProductCopy.codePlaceholder,
            hint: VendorProductCopy.codeFieldHint,
            errorText: widget.fieldErrors[VendorProductField.productCode],
            // Counted in characters, matching the backend's own `length()` — which
            // counts characters rather than bytes, so a 64-character code of
            // multi-byte characters is accepted.
            maxLength: VendorProductInput.maxProductCodeLength,
            textInputAction: TextInputAction.next,
            // No autofill: a product code is catalogue data and has no
            // correspondence to anything a browser or a keyboard has stored about
            // the person typing it. Offering one would invite an address or a name
            // into a field with a strict shape.
            autofillHints: const <String>[],
            textCapitalization: TextCapitalization.characters,
            onChanged: (String value) =>
                widget.onFieldChanged(VendorProductField.productCode, value),
          ),
        const SizedBox(height: SrSpacing.xl),

        SrTextField(
          label: VendorProductCopy.nameLabel,
          controller: _controllers[VendorProductField.productName],
          focusNode: _focusNodes[VendorProductField.productName],
          required: true,
          enabled: widget.enabled,
          placeholder: VendorProductCopy.namePlaceholder,
          errorText: widget.fieldErrors[VendorProductField.productName],
          maxLength: VendorProductInput.maxProductNameLength,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[],
          textCapitalization: TextCapitalization.words,
          onChanged: (String value) =>
              widget.onFieldChanged(VendorProductField.productName, value),
        ),
        const SizedBox(height: SrSpacing.xl),

        SrTextField(
          label: VendorProductCopy.barcodeLabel,
          controller: _controllers[VendorProductField.barcode],
          focusNode: _focusNodes[VendorProductField.barcode],
          enabled: widget.enabled,
          placeholder: VendorProductCopy.barcodePlaceholder,
          hint: VendorProductCopy.barcodeFieldHint,
          errorText: widget.fieldErrors[VendorProductField.barcode],
          // A digit-friendly keyboard, and deliberately NOT a number *type*: the
          // value is text all the way down, because parsing it would drop a leading
          // zero and a 14-digit GTIN exceeds what a double holds exactly. Spaces and
          // hyphens are accepted as typed and stripped on submit, so nothing here
          // filters keystrokes.
          keyboardType: TextInputType.text,
          // Generous enough for the separators a person transcribes, since those are
          // removed before the 8-to-14-digit rule is applied.
          maxLength: 32,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[],
          onChanged: (String value) =>
              widget.onFieldChanged(VendorProductField.barcode, value),
        ),
        const SizedBox(height: SrSpacing.xl),

        SrTextField(
          label: VendorProductCopy.brandLabel,
          controller: _controllers[VendorProductField.brand],
          focusNode: _focusNodes[VendorProductField.brand],
          enabled: widget.enabled,
          placeholder: VendorProductCopy.brandPlaceholder,
          errorText: widget.fieldErrors[VendorProductField.brand],
          maxLength: VendorProductInput.maxBrandLength,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[],
          textCapitalization: TextCapitalization.words,
          onChanged: (String value) =>
              widget.onFieldChanged(VendorProductField.brand, value),
        ),
        const SizedBox(height: SrSpacing.xl),

        SrTextField(
          label: VendorProductCopy.descriptionLabel,
          controller: _controllers[VendorProductField.description],
          focusNode: _focusNodes[VendorProductField.description],
          enabled: widget.enabled,
          hint: VendorProductCopy.descriptionFieldHint,
          errorText: widget.fieldErrors[VendorProductField.description],
          maxLength: VendorProductInput.maxDescriptionLength,
          // Multi-line, and the newlines survive: the backend trims only the ends of
          // a description and preserves its internal formatting verbatim, because a
          // paragraph break belongs to whoever wrote it. Collapsing it in Dart would
          // throw that away before the backend ever saw it.
          minLines: 4,
          maxLines: 10,
          keyboardType: TextInputType.multiline,
          // Deliberately not `next`: on a multi-line field the newline must reach the
          // text rather than move focus.
          textInputAction: TextInputAction.newline,
          autofillHints: const <String>[],
          textCapitalization: TextCapitalization.sentences,
          onChanged: (String value) =>
              widget.onFieldChanged(VendorProductField.description, value),
        ),
      ],
    );
  }
}

/// The immutable product code, as read-only context on the edit screen.
///
/// Rendered as a labelled fact rather than as a disabled input. A greyed-out text
/// box invites a person to try typing into it and then says nothing when they
/// cannot; a fact with a sentence beneath it explains itself once. The label,
/// value and reason are spoken as one node so a screen reader announces "Product
/// code, read only" rather than leaving somebody to discover it by failing to edit.
class _ReadOnlyCode extends StatelessWidget {
  const _ReadOnlyCode({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Semantics(
      label:
          '${VendorProductCopy.codeLabel}: $code. '
          '${VendorProductCopy.codeReadOnlySemantics}',
      readOnly: true,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            VendorProductCopy.codeLabel,
            style: SrTypography.label.copyWith(color: sr.textLabel),
          ),
          const SizedBox(height: SrSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: SrSpacing.lg,
              vertical: SrSpacing.md,
            ),
            decoration: BoxDecoration(
              color: sr.inputDisabledFill,
              borderRadius: BorderRadius.circular(SrRadii.control),
              border: Border.all(color: sr.border),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.lock_outline_rounded, size: 16, color: sr.textMuted),
                const SizedBox(width: SrSpacing.sm),
                Expanded(
                  child: Text(
                    code,
                    style: SrTypography.body.copyWith(color: sr.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SrSpacing.sm),
          Text(
            VendorProductCopy.codeReadOnlyHint,
            style: SrTypography.caption.copyWith(color: sr.textSecondary),
          ),
        ],
      ),
    );
  }
}
