import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/entities/extracted_value.dart';
import '../../../domain/entities/receipt_civil_date.dart';
import '../../../domain/entities/receipt_civil_time.dart';
import '../../../domain/entities/receipt_extraction.dart';
import '../cubit/receipt_review_cubit.dart';
import 'receipt_review_copy.dart';

/// The eight values a reviewer may type, and no others.
///
/// These eight are the editable part of a confirmation, and they are not the
/// whole of what the call sends. `confirm_receipt_extraction` also receives the
/// submission id — which comes from the route, not from a control — and the
/// currency's minor unit, which comes from `get_receipt_currency_minor_unit` and
/// is never typed: it is the scale the amounts below were built with, declared
/// so the backend can verify it rather than infer it.
///
/// What is deliberately absent is a control for an entry mode, a changed-fields
/// list, an extraction id, a shop, an organization or a profile. Every one of
/// those is derived server-side — the first two as *outcomes* of the
/// confirmation — and the absence of a control is the visible half of the reason
/// this client cannot supply one.
///
/// ## Amounts are typed in major units and stored in minor units
///
/// A person types `125.50`, because that is what the paper says. The conversion
/// to the integer `12550` happens once, on confirm, by splitting the string —
/// never by multiplying a `double`. The number of decimals is the currency's
/// own, it comes from the backend, and **until it has arrived this form claims
/// nothing**: [minorDigits] is null, the amount hints say so plainly, and the
/// confirm control does not fire.
///
/// Changing the currency never rewrites an amount box. The digits somebody typed
/// stay exactly as typed and it is for them to move the decimal point — a form
/// that re-scaled `12.34` into `1234` on their behalf would be asserting it knew
/// which of the two the paper said.
///
/// ## What was read is shown beside what may be typed
///
/// A field the provider resolved shows its confidence quietly. A field it could
/// **not** resolve but did see is the important case: the printed text is shown
/// and the box is left empty, so the person reads the paper and types the figure
/// themselves rather than confirming a value nobody produced.
class ReceiptReviewForm extends StatefulWidget {
  const ReceiptReviewForm({
    super.key,
    required this.state,
    required this.minorDigits,
    required this.cubit,
  });

  final ReceiptReviewState state;

  /// The authoritative decimal width, or null while it is not established.
  final int? minorDigits;
  final ReceiptReviewCubit cubit;

  @override
  State<ReceiptReviewForm> createState() => _ReceiptReviewFormState();
}

class _ReceiptReviewFormState extends State<ReceiptReviewForm> {
  late final TextEditingController _currency;
  late final TextEditingController _merchant;
  late final TextEditingController _document;
  late final TextEditingController _total;
  late final TextEditingController _subtotal;
  late final TextEditingController _tax;

  @override
  void initState() {
    super.initState();
    final ReceiptReviewDraft draft = widget.state.draft;
    _currency = TextEditingController(text: draft.currencyCode);
    _merchant = TextEditingController(text: draft.merchantName);
    _document = TextEditingController(text: draft.documentNumber);
    _total = TextEditingController(text: draft.totalText);
    _subtotal = TextEditingController(text: draft.subtotalText);
    _tax = TextEditingController(text: draft.taxText);
  }

  @override
  void didUpdateWidget(ReceiptReviewForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The draft becomes non-empty exactly once, when the reading arrives. Every
    // later change originates from these controllers, so the texts already
    // agree and nothing is reset under somebody's cursor.
    final ReceiptReviewDraft draft = widget.state.draft;
    _sync(_currency, draft.currencyCode);
    _sync(_merchant, draft.merchantName);
    _sync(_document, draft.documentNumber);
    _sync(_total, draft.totalText);
    _sync(_subtotal, draft.subtotalText);
    _sync(_tax, draft.taxText);
  }

  static void _sync(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  void dispose() {
    _currency.dispose();
    _merchant.dispose();
    _document.dispose();
    _total.dispose();
    _subtotal.dispose();
    _tax.dispose();
    super.dispose();
  }

  String? _error(ReceiptReviewField field) {
    final ReceiptReviewFieldProblem? problem =
        widget.state.fieldProblems[field];
    return problem == null
        ? null
        : ReceiptReviewCopy.fieldError(field, problem);
  }

  @override
  Widget build(BuildContext context) {
    final ReceiptReviewState state = widget.state;
    final ReceiptExtraction? extraction = state.extraction;
    // NOT `canEdit`. The moment the atomic write starts, the header is as
    // frozen as the products it was sent with — and it stays frozen for every
    // state that write can reach. Disabling here is structural: each control
    // receives `enabled: false` rather than being dimmed and left tappable.
    final bool enabled = state.canEditTransaction;

    return SrSectionCard(
      title: 'Invoice / receipt details',
      description:
          'Check each value against the printed invoice / receipt and correct '
          'anything '
          'that is wrong.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _DateField(
            value: state.draft.transactionDate,
            enabled: enabled,
            errorText: _error(ReceiptReviewField.transactionDate),
            source: extraction?.transactionDate,
            onChanged: widget.cubit.setTransactionDate,
          ),
          const SizedBox(height: SrSpacing.xl),

          _TimeField(
            value: state.draft.transactionTime,
            enabled: enabled,
            source: extraction?.transactionTime,
            onChanged: widget.cubit.setTransactionTime,
          ),
          const SizedBox(height: SrSpacing.xl),

          SrTextField(
            label: 'Currency',
            controller: _currency,
            required: true,
            enabled: enabled,
            maxLength: 3,
            textCapitalization: TextCapitalization.characters,
            placeholder: 'AED',
            hint: 'The three-letter code printed on the invoice / receipt.',
            // A code this system will not accept outlives a keystroke that did
            // not change it, so it is derived from the resolution rather than
            // read out of the per-field map an edit clears.
            errorText:
                _error(ReceiptReviewField.currencyCode) ??
                (state.currencyProblem == null
                    ? null
                    : ReceiptReviewCopy.fieldError(
                        ReceiptReviewField.currencyCode,
                        state.currencyProblem!,
                      )),
            onChanged: widget.cubit.setCurrencyCode,
          ),
          _CurrencyStatus(
            state: state,
            onResolve: widget.cubit.resolveCurrency,
          ),
          _Source(value: extraction?.currencyCode, what: 'currency'),
          const SizedBox(height: SrSpacing.xl),

          _AmountField(
            label: 'Total',
            controller: _total,
            required: true,
            enabled: enabled,
            digits: widget.minorDigits,
            errorText: _error(ReceiptReviewField.total),
            source: extraction?.total,
            onChanged: widget.cubit.setTotal,
          ),
          const SizedBox(height: SrSpacing.xl),

          _AmountField(
            label: 'Subtotal',
            controller: _subtotal,
            required: false,
            enabled: enabled,
            digits: widget.minorDigits,
            errorText: _error(ReceiptReviewField.subtotal),
            source: extraction?.subtotal,
            onChanged: widget.cubit.setSubtotal,
          ),
          const SizedBox(height: SrSpacing.xl),

          _AmountField(
            label: 'Tax',
            controller: _tax,
            required: false,
            enabled: enabled,
            digits: widget.minorDigits,
            errorText: _error(ReceiptReviewField.tax),
            source: extraction?.taxTotal,
            onChanged: widget.cubit.setTax,
          ),
          const SizedBox(height: SrSpacing.xl),

          SrTextField(
            label: 'Shop name',
            controller: _merchant,
            enabled: enabled,
            maxLength: 255,
            errorText: _error(ReceiptReviewField.merchantName),
            onChanged: widget.cubit.setMerchantName,
          ),
          _Source(value: extraction?.merchantName, what: 'shop name'),
          const SizedBox(height: SrSpacing.xl),

          SrTextField(
            label: 'Invoice / receipt no.',
            controller: _document,
            enabled: enabled,
            maxLength: 100,
            errorText: _error(ReceiptReviewField.documentNumber),
            onChanged: widget.cubit.setDocumentNumber,
          ),
          _Source(
            value: extraction?.documentNumber,
            what: 'invoice / receipt number',
          ),
          const SizedBox(height: SrSpacing.sm),

          // NO submit control here, deliberately. These details and the product
          // proposal below are written by one RPC as one immutable assertion,
          // so there is one control on this screen that sends anything and it
          // lives at the foot of the page, after the products it will be sent
          // with. See `ReceiptFinalConfirmationSection`.
          Text(
            'These details are confirmed together with the products below.',
            textAlign: TextAlign.center,
            style: SrTypography.caption.copyWith(
              color: context.sr.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The chosen receipt date. A civil date, never a `DateTime`.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.enabled,
    required this.errorText,
    required this.source,
    required this.onChanged,
  });

  final ReceiptCivilDate? value;
  final bool enabled;
  final String? errorText;
  final ExtractedValue<ReceiptCivilDate>? source;
  final ValueChanged<ReceiptCivilDate> onChanged;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              'Date',
              style: SrTypography.label.copyWith(color: sr.textLabel),
            ),
            Text(
              ' *',
              style: SrTypography.label.copyWith(color: sr.dangerFill),
            ),
          ],
        ),
        const SizedBox(height: SrSpacing.sm),
        Semantics(
          button: true,
          label: 'Choose the invoice / receipt date',
          child: SrButton(
            label: value?.iso ?? 'Choose date',
            icon: Icons.event_outlined,
            variant: SrButtonVariant.outline,
            fullWidth: true,
            onPressed: enabled ? () => _pick(context) : null,
          ),
        ),
        if (errorText != null) ...<Widget>[
          const SizedBox(height: SrSpacing.sm),
          Text(errorText!, style: SrTypography.fieldError),
        ],
        _Source(value: source, what: 'date'),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final ReceiptCivilDate? current = value;
    final DateTime initial = current == null
        ? DateTime.now()
        : DateTime(current.year, current.month, current.day);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      // The floor the backend enforces, and a ceiling a shop-floor clock can
      // still reach if the device's date is a day ahead.
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) {
      return;
    }
    onChanged(ReceiptCivilDate(picked.year, picked.month, picked.day));
  }
}

/// The optional receipt time. A civil time, never a `DateTime`.
class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.value,
    required this.enabled,
    required this.source,
    required this.onChanged,
  });

  final ReceiptCivilTime? value;
  final bool enabled;
  final ExtractedValue<ReceiptCivilTime>? source;
  final ValueChanged<ReceiptCivilTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              'Time',
              style: SrTypography.label.copyWith(color: sr.textLabel),
            ),
            const SizedBox(width: SrSpacing.xs),
            Text(
              '(optional)',
              style: SrTypography.caption.copyWith(color: sr.textMuted),
            ),
          ],
        ),
        const SizedBox(height: SrSpacing.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: Semantics(
                button: true,
                label: 'Choose the invoice / receipt time',
                child: SrButton(
                  label: value?.iso ?? 'Choose time',
                  icon: Icons.schedule_outlined,
                  variant: SrButtonVariant.outline,
                  fullWidth: true,
                  onPressed: enabled ? () => _pick(context) : null,
                ),
              ),
            ),
            if (value != null) ...<Widget>[
              const SizedBox(width: SrSpacing.sm),
              Semantics(
                button: true,
                label: 'Remove the invoice / receipt time',
                child: SrButton(
                  label: 'Clear',
                  variant: SrButtonVariant.ghost,
                  onPressed: enabled ? () => onChanged(null) : null,
                ),
              ),
            ],
          ],
        ),
        _Source(value: source, what: 'time'),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final ReceiptCivilTime? current = value;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: current == null
          ? const TimeOfDay(hour: 12, minute: 0)
          : TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) {
      return;
    }
    // Minute precision, which is exactly what the backend compares at: a
    // provider's `:00` seconds is not a correction.
    onChanged(ReceiptCivilTime(picked.hour, picked.minute));
  }
}

/// Where the typed currency's decimal width has reached, in one compact line.
///
/// Compact on purpose: this is a detail of one field, not a second status panel,
/// and it appears only while there is something to say. It shows no SQLSTATE, no
/// function name and no table name, because none of them reaches this layer.
class _CurrencyStatus extends StatelessWidget {
  const _CurrencyStatus({required this.state, required this.onResolve});

  final ReceiptReviewState state;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final String? message = ReceiptReviewCopy.currencyStatus(state);
    if (message == null) {
      return const SizedBox.shrink();
    }

    final SrColorScheme sr = context.sr;
    final bool resolving =
        state.currency.phase == ReceiptCurrencyPhase.resolving;

    return Padding(
      padding: const EdgeInsets.only(top: SrSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                message,
                style: SrTypography.caption.copyWith(
                  color: resolving
                      ? sr.textMuted
                      : sr.tone(SrTone.amber).alertText,
                ),
              ),
            ),
          ),
          // A read, which is the whole reason it may be offered as a retry.
          if (state.canResolveCurrency) ...<Widget>[
            const SizedBox(width: SrSpacing.sm),
            Semantics(
              button: true,
              label: 'Check this currency again',
              child: SrButton(
                label: 'Check currency',
                variant: SrButtonVariant.ghost,
                onPressed: onResolve,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One monetary field, typed in major units.
class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.label,
    required this.controller,
    required this.required,
    required this.enabled,
    required this.digits,
    required this.errorText,
    required this.source,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final bool required;
  final bool enabled;

  /// Null until the backend has said how wide this currency is. The hint says
  /// exactly that rather than naming a number nobody supplied.
  final int? digits;
  final String? errorText;
  final ExtractedValue<int>? source;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SrTextField(
          label: label,
          controller: controller,
          required: required,
          enabled: enabled,
          // A decimal keypad is a convenience and never the rule: a hardware
          // keyboard can type anything, so `parseMinorUnits` is what actually
          // decides, and it refuses rather than guesses.
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          hint: ReceiptReviewCopy.amountHint(digits),
          errorText: errorText,
          onChanged: onChanged,
        ),
        _Source(value: source, what: label.toLowerCase()),
      ],
    );
  }
}

/// What the reading said about one field, shown quietly beneath it.
///
/// Three independent facts, because the backend keeps them independent: a
/// normalized value, the text it was read from, and a confidence. The case that
/// matters most is a **null value with its source text intact** — an amount
/// whose decimal separator could not be resolved is stored exactly that way, and
/// showing the printed characters is the whole point.
class _Source extends StatelessWidget {
  const _Source({required this.value, required this.what});

  final ExtractedValue<Object>? value;
  final String what;

  @override
  Widget build(BuildContext context) {
    final ExtractedValue<Object>? extracted = value;
    if (extracted == null) {
      return const SizedBox.shrink();
    }

    final SrColorScheme sr = context.sr;
    final String? sourceText = extracted.sourceText;
    final double? confidence = extracted.confidence;

    final String message;
    Color colour = sr.textMuted;

    if (extracted.needsAttention && sourceText != null) {
      // Printed, but not resolvable. The reviewer must type it themselves.
      message = 'Printed as “$sourceText” — we could not read it exactly.';
      colour = sr.tone(SrTone.amber).alertText;
    } else if (extracted.isAbsent) {
      message = 'No $what found on the invoice / receipt.';
    } else if (sourceText != null) {
      message = confidence == null
          ? 'Read from “$sourceText”.'
          : 'Read from “$sourceText” · ${_percent(confidence)} confident.';
    } else {
      // A normalized value with no source text is legal and says nothing worth
      // a sentence of its own.
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: SrSpacing.xs),
      child: Text(message, style: SrTypography.caption.copyWith(color: colour)),
    );
  }

  /// A confidence is a display hint and nothing branches on it, so a whole
  /// percent is as much precision as is useful.
  static String _percent(double confidence) => '${(confidence * 100).round()}%';
}
