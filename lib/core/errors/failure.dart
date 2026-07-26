import 'package:equatable/equatable.dart';

/// The shared failure contract, mirroring the discriminated unions the web
/// application already returns from every operation.
///
/// Specified in § 8.3 of `docs/mobile-architecture-recommendation.md`. The rules
/// that make it safe, all inherited from the web layer:
///
/// * **Never carry a raw Postgres message.** They can name tables, columns,
///   functions and policies. A [Failure] carries a discriminant and, at most, a
///   caller-safe field name — never the database's own text.
/// * **A transport failure is [UnavailableFailure], never [DeniedFailure].** An
///   outage must not be presented as an authorization denial, nor the reverse.
/// * **Fail closed.** Anything unrecognized becomes a non-authorized result.
///
/// A [Failure] is presentation input. It is never an authorization decision:
/// the backend decided that already, and will decide it again on the next call.
sealed class Failure extends Equatable {
  const Failure();

  @override
  List<Object?> get props => const <Object?>[];
}

/// `42501` — the caller may not do this.
///
/// Deliberately carries no detail. The backend returns the same answer for "not
/// authorized", "no such id", and "that id is someone else's", so distinguishing
/// them in the UI would reintroduce the existence oracle SQL is careful to deny.
final class DeniedFailure extends Failure {
  const DeniedFailure();
}

/// `23505` — the value already exists.
///
/// [field] is a client-side hint for which input to highlight — a **form-field
/// key**, never a database column name, and never the backend's own text.
///
/// It is set by the caller, from the strongest discriminator the operation
/// actually offers. Usually that is a machine code. The Vendor Product writes are
/// the one exception in the deployed contract: `create_vendor_product` and
/// `update_vendor_product` share SQLSTATE `23505` for both of their per-Vendor
/// unique indexes, so the *only* thing telling a duplicate product code apart from
/// a duplicate barcode is one of two fixed message literals the functions raise
/// themselves. `mapVendorProductWriteError` matches those two, in one place, and
/// carries forward only this field key; see that function for why that is safe and
/// why an unrecognized message degrades to a hint-less duplicate instead.
final class DuplicateFailure extends Failure {
  const DuplicateFailure({this.field});

  final String? field;

  @override
  List<Object?> get props => <Object?>[field];
}

/// `23514` — the input shape or a business rule was rejected.
final class InvalidFailure extends Failure {
  const InvalidFailure({this.field});

  final String? field;

  @override
  List<Object?> get props => <Object?>[field];
}

/// `55000` — an inactive relationship, retailer, or product. The caller is
/// permitted, but the target is not in a state that allows the operation.
final class NotReadyFailure extends Failure {
  const NotReadyFailure();
}

/// A transport, serialization, or unknown backend failure.
///
/// Never an authorization answer. The UI offers a retry; it must not tell the
/// user they lack access.
final class UnavailableFailure extends Failure {
  const UnavailableFailure();
}

/// There is no verified session. Distinct from [DeniedFailure]: the caller is
/// not signed in, rather than signed in and refused.
final class UnauthenticatedFailure extends Failure {
  const UnauthenticatedFailure();
}

/// The operation depends on a backend capability that does not exist yet.
///
/// This exists so the app can be honest about an unfinished contract instead of
/// dressing a missing RPC up as a denial or an outage. [capability] names the
/// missing backend object (e.g. `get_my_portal_context()`) for developer-facing
/// copy only — it is never used to make a decision, and never shown as the
/// reason a user was refused anything.
final class NotImplementedFailure extends Failure {
  const NotImplementedFailure({required this.capability});

  final String capability;

  @override
  List<Object?> get props => <Object?>[capability];
}
