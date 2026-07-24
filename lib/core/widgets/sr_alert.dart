import 'package:flutter/material.dart';

import '../design/design.dart';

/// The intent of an inline alert.
enum SrAlertTone { info, success, warning, error }

/// An inline notice (§ 3.9): 12-radius, 1px border, `px-4 py-3`, 14px text, a
/// leading 16px icon offset 2px down, 12px gap.
///
/// ## Why this exists instead of a snackbar
///
/// **The product has no snackbars or toasts.** All feedback is inline and in
/// place: a form-level result renders as an alert at the top of the form, and a
/// field error renders under its control. The handoff is explicit that a
/// validation error must never become a snackbar, and that a Material default
/// dark pill would read as a different app.
///
/// Status is never carried by colour alone — the icon and the message text both
/// state it, and [semanticsLabel] mirrors the web's `role="alert"` on errors and
/// `role="status"` on everything else.
class SrAlert extends StatelessWidget {
  const SrAlert({
    super.key,
    required this.message,
    this.tone = SrAlertTone.info,
    this.title,
  });

  final String message;
  final String? title;
  final SrAlertTone tone;

  SrTone get _tone => switch (tone) {
    SrAlertTone.info => SrTone.blue,
    SrAlertTone.success => SrTone.emerald,
    SrAlertTone.warning => SrTone.amber,
    SrAlertTone.error => SrTone.red,
  };

  IconData get _icon => switch (tone) {
    SrAlertTone.info => Icons.info_outline_rounded,
    SrAlertTone.success => Icons.check_circle_outline_rounded,
    SrAlertTone.warning => Icons.warning_amber_rounded,
    SrAlertTone.error => Icons.warning_amber_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final SrToneColors colors = context.sr.tone(_tone);

    return Semantics(
      // The web marks an error `role="alert"` (assertive) and everything else
      // `role="status"` (polite).
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: SrSpacing.lg,
          vertical: SrSpacing.md,
        ),
        decoration: BoxDecoration(
          color: colors.fill,
          borderRadius: BorderRadius.circular(SrRadii.control),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              // The web offsets the icon 2px down so it aligns with the first
              // line of text rather than the box.
              padding: const EdgeInsets.only(top: SrSpacing.xxs),
              child: Icon(_icon, size: 16, color: colors.foreground),
            ),
            const SizedBox(width: SrSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (title != null) ...<Widget>[
                    Text(
                      title!,
                      style: SrTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.alertText,
                      ),
                    ),
                    const SizedBox(height: SrSpacing.xxs),
                  ],
                  Text(
                    message,
                    style: SrTypography.body.copyWith(color: colors.alertText),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
