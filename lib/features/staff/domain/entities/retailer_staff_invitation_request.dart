import 'package:equatable/equatable.dart';

import 'retailer_staff_invitation_role.dart';

/// The maximum length of an email address, per RFC 5321.
///
/// The three numbers below are copied from the deployed shared contract
/// (`lib/staff/staff-invitation-delivery-contract.ts`: `MAX_EMAIL_LENGTH`,
/// `MAX_NAME_LENGTH`, `MAX_SHOP_SELECTION`) so a value this client accepts is
/// one the Edge Function accepts. They are **not** the enforcement: the function
/// re-applies each of them and `reserve_retailer_staff_invitation()` re-applies
/// the email and name rules again in SQL. Checking them here only means an
/// obviously impossible value never leaves the device.
const int maxInvitationEmailLength = 254;

/// A defensive bound on a submitted name. Not a product rule — the database
/// imposes no length limit on `first_name` / `last_name`.
const int maxInvitationNameLength = 200;

/// A defensive cap on how many shops one submission may name.
const int maxInvitationShopSelection = 200;

/// Which control a validation message belongs under.
enum RetailerStaffInvitationField { firstName, lastName, email, role, shops }

/// What is wrong with one field.
///
/// A discriminant rather than a sentence: the wording lives in the presentation
/// copy, so no validation message can ever be built from a backend response.
enum RetailerStaffInvitationProblem {
  /// A required value is absent or blank after trimming.
  missing,

  /// Longer than the bound the deployed contract accepts.
  tooLong,

  /// Present, but not shaped like an address.
  malformed,

  /// Sales Staff was chosen and no shop was selected.
  shopsRequired,

  /// A Retailer Manager was chosen and shops were somehow still submitted.
  ///
  /// Not reachable through the form, which clears the selection from the request
  /// for a Manager. It exists because the request type is constructible from
  /// anywhere and the rule belongs to the request, not to a widget.
  shopsNotAllowed,

  /// The same shop id appears twice.
  ///
  /// Refused rather than de-duplicated, exactly as the Edge Function refuses it:
  /// the database would collapse a duplicate silently, so a client that sent one
  /// would have a defect that never surfaced.
  duplicateShops,

  /// More shops than one submission may name.
  tooManyShops,
}

/// The 8-4-4-4-12 hexadecimal shape PostgreSQL's `uuid` type accepts.
///
/// Case-insensitive and anchored at both ends, matching the pattern the shared
/// contract applies to every element of `shopIds`.
final RegExp _uuidShape = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// The pragmatic email shape check: something, an `@`, something, a dot,
/// something, with no whitespace.
///
/// Byte-identical to `EMAIL_PATTERN` in the shared delivery contract, to
/// `lib/staff/staff-invite-input.ts`, and to the
/// `retailer_staff_invitations_email_shape` check constraint. Deliberately not a
/// stricter rule: a client that refused an address the database accepts would be
/// the only thing standing between a real colleague and an invitation.
final RegExp _emailShape = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// The whole payload of a staff invitation: five values, and nothing else.
///
/// ## The field list is the security property
///
/// The deployed Edge Function accepts exactly `firstName`, `lastName`, `email`,
/// `roleCode` and `shopIds`, and **rejects an unknown top-level key rather than
/// ignoring it**. This type has exactly five fields with the same meanings.
///
/// There is no Retailer organization id, actor / user / profile id, membership
/// id, invitation id, token, token hash, audit field, invitation state,
/// normalized email, expiry, permission code, service-role credential or Resend
/// setting here, and there is nowhere to put one: a request object with no such
/// field cannot send it, whatever a caller intends.
///
/// The Retailer is derived server-side from `auth.uid()` inside
/// `reserve_retailer_staff_invitation()`, and every submitted shop is then
/// validated against **that** derived Retailer. So a shop id is not an
/// authorization — holding one grants nothing, and another Retailer's shop id is
/// refused byte-identically to an id that names nothing.
///
/// ## Canonical by construction
///
/// [validated] is the only way to build one. It trims the names, trims and
/// lower-cases the email, lower-cases and sorts the shop ids, and applies the
/// role/shop rule — the same normalization the function performs — so the value
/// this client validates is the value it sends.
///
/// ## Backend validation remains authoritative
///
/// Nothing here reproduces a backend *invitation* rule. Whether the address is
/// already a member, already has a live invitation with a different role or shop
/// set, belongs to a retired account, or names a shop that is not this
/// Retailer's and ACTIVE are all questions only the reservation can answer, and
/// this type does not guess at any of them.
final class RetailerStaffInvitationRequest extends Equatable {
  const RetailerStaffInvitationRequest._({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    required this.shopIds,
  });

  /// Validates and canonicalizes raw form input.
  ///
  /// Returns [RetailerStaffInvitationValid] with a canonical request, or
  /// [RetailerStaffInvitationInvalid] with one problem per offending field —
  /// all of them, so a person fixes one form rather than one field per attempt.
  static RetailerStaffInvitationInput validated({
    required String firstName,
    required String lastName,
    required String email,
    required RetailerStaffInvitationRole? role,
    required List<String> shopIds,
  }) {
    final Map<RetailerStaffInvitationField, RetailerStaffInvitationProblem>
    problems = <RetailerStaffInvitationField, RetailerStaffInvitationProblem>{};

    final String trimmedFirst = firstName.trim();
    final String trimmedLast = lastName.trim();
    final String canonicalEmail = email.trim().toLowerCase();

    if (trimmedFirst.isEmpty) {
      problems[RetailerStaffInvitationField.firstName] =
          RetailerStaffInvitationProblem.missing;
    } else if (trimmedFirst.length > maxInvitationNameLength) {
      problems[RetailerStaffInvitationField.firstName] =
          RetailerStaffInvitationProblem.tooLong;
    }

    if (trimmedLast.isEmpty) {
      problems[RetailerStaffInvitationField.lastName] =
          RetailerStaffInvitationProblem.missing;
    } else if (trimmedLast.length > maxInvitationNameLength) {
      problems[RetailerStaffInvitationField.lastName] =
          RetailerStaffInvitationProblem.tooLong;
    }

    if (canonicalEmail.isEmpty) {
      problems[RetailerStaffInvitationField.email] =
          RetailerStaffInvitationProblem.missing;
    } else if (canonicalEmail.length > maxInvitationEmailLength) {
      problems[RetailerStaffInvitationField.email] =
          RetailerStaffInvitationProblem.tooLong;
    } else if (!_emailShape.hasMatch(canonicalEmail)) {
      problems[RetailerStaffInvitationField.email] =
          RetailerStaffInvitationProblem.malformed;
    }

    if (role == null) {
      problems[RetailerStaffInvitationField.role] =
          RetailerStaffInvitationProblem.missing;
    }

    // Canonicalized before the shop rules are applied, so "the same shop twice"
    // is decided on the values that would actually be sent rather than on their
    // spelling.
    final List<String> canonicalShops = shopIds
        .map((String id) => id.trim().toLowerCase())
        .toList(growable: false);

    if (canonicalShops.any((String id) => !_uuidShape.hasMatch(id))) {
      // A value that is not shaped like a uuid cannot have come from
      // `list_retailer_staff_assignable_shops()`, so this is a defect rather
      // than a person's mistake — reported on the shops control because that is
      // where a reader can act.
      problems[RetailerStaffInvitationField.shops] =
          RetailerStaffInvitationProblem.malformed;
    } else if (canonicalShops.toSet().length != canonicalShops.length) {
      problems[RetailerStaffInvitationField.shops] =
          RetailerStaffInvitationProblem.duplicateShops;
    } else if (canonicalShops.length > maxInvitationShopSelection) {
      problems[RetailerStaffInvitationField.shops] =
          RetailerStaffInvitationProblem.tooManyShops;
    } else if (role != null) {
      if (role.carriesShops && canonicalShops.isEmpty) {
        problems[RetailerStaffInvitationField.shops] =
            RetailerStaffInvitationProblem.shopsRequired;
      } else if (!role.carriesShops && canonicalShops.isNotEmpty) {
        problems[RetailerStaffInvitationField.shops] =
            RetailerStaffInvitationProblem.shopsNotAllowed;
      }
    }

    if (problems.isNotEmpty) {
      return RetailerStaffInvitationInvalid(
        Map<
          RetailerStaffInvitationField,
          RetailerStaffInvitationProblem
        >.unmodifiable(problems),
      );
    }

    // Sorted so two selections of the same shops produce the same request
    // regardless of the order the boxes were ticked, matching the function's own
    // `shopIds.sort()`.
    final List<String> sorted = List<String>.of(canonicalShops)..sort();

    return RetailerStaffInvitationValid(
      RetailerStaffInvitationRequest._(
        firstName: trimmedFirst,
        lastName: trimmedLast,
        email: canonicalEmail,
        role: role!,
        shopIds: List<String>.unmodifiable(sorted),
      ),
    );
  }

  /// Trimmed. Never case-folded: a person's name is theirs.
  final String firstName;
  final String lastName;

  /// Trimmed and lower-cased, matching the database's canonical-email
  /// constraint.
  final String email;

  /// The role, as a value. Its wire token is [RetailerStaffInvitationRole.code].
  final RetailerStaffInvitationRole role;

  /// Lower-cased, de-duplicated and sorted. **Always empty for a Retailer
  /// Manager** — the validation refuses to build a Manager request that carries
  /// one, so there is no path by which a stale selection can be sent.
  final List<String> shopIds;

  @override
  List<Object?> get props => <Object?>[
    firstName,
    lastName,
    email,
    role,
    shopIds,
  ];
}

/// The result of validating form input.
sealed class RetailerStaffInvitationInput {
  const RetailerStaffInvitationInput();
}

/// The input is well-formed and canonical.
final class RetailerStaffInvitationValid extends RetailerStaffInvitationInput {
  const RetailerStaffInvitationValid(this.request);

  final RetailerStaffInvitationRequest request;
}

/// The input cannot be sent, with one problem per offending field.
final class RetailerStaffInvitationInvalid
    extends RetailerStaffInvitationInput {
  const RetailerStaffInvitationInvalid(this.problems);

  final Map<RetailerStaffInvitationField, RetailerStaffInvitationProblem>
  problems;
}
