import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';

/// Initials computed from a name, for a decorative avatar.
///
/// ## Why this is computed locally, and why that is not "deriving data"
///
/// **No image exists to show.** `public.organizations` and `public.profiles` have
/// no logo, avatar, image or path column of any kind, and the only Storage bucket
/// in the project is `receipts` — private, zero policies, unrelated to identity.
/// Both shipped clients therefore render initials, and the web does exactly this
/// (`getOrganizationInitials`, `components/ui/avatar.tsx`).
///
/// Initials are **presentation derived from a value already on screen**, not a
/// second read: nothing here queries anything, stores anything or asks the
/// backend for anything, and the full name is rendered beside the avatar in every
/// case. The avatar is decorative and is excluded from the semantics tree, so a
/// screen reader hears the name rather than two letters.
String initialsOf(String name) {
  final List<String> words = name
      .split(RegExp(r'\s+'))
      .where((String word) => word.isNotEmpty)
      .toList(growable: false);

  if (words.isEmpty) {
    // Unreachable: every caller of this function has already had its input
    // through the parser's non-blank guard, or is a session organization name the
    // backend constrains to be non-blank. Returning empty rather than inventing a
    // letter, because a fabricated initial would be a fabricated name.
    return '';
  }
  if (words.length == 1) {
    // A single word yields one letter rather than two, so a name is never
    // padded out with a letter it does not contain.
    return words.first.characters.first.toUpperCase();
  }
  return (words.first.characters.first + words.last.characters.first)
      .toUpperCase();
}

/// A tinted disc carrying [initials], sized to sit beside a name.
///
/// Decorative by construction: [ExcludeSemantics] keeps the letters out of the
/// semantics tree, because the name they were computed from is announced in full
/// by the card around it.
class VendorProfileAvatar extends StatelessWidget {
  const VendorProfileAvatar({
    super.key,
    required this.name,
    this.tone = SrTone.indigo,
    this.size = 48,
  });

  final String name;
  final SrTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final SrToneColors colors = context.sr.tone(tone);
    final String initials = initialsOf(name);

    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.fill,
          borderRadius: BorderRadius.circular(SrRadii.control),
          border: Border.all(color: colors.ring),
        ),
        child: initials.isEmpty
            ? Icon(
                Icons.person_outline_rounded,
                size: size * 0.5,
                color: colors.foreground,
              )
            : Text(
                initials,
                style: SrTypography.cardTitle.copyWith(
                  color: colors.foreground,
                ),
              ),
      ),
    );
  }
}
