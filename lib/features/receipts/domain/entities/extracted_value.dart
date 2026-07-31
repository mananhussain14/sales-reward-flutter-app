import 'package:equatable/equatable.dart';

/// One extracted field: the normalized value, the text it was read from, and a
/// confidence.
///
/// The backend stores all three for each of the eight readable fields, and the
/// safe client projection returns all three. Modelling them as one value rather
/// than twenty-four loose properties is what stops a review screen from showing
/// a figure next to somebody else's source text.
///
/// ## The important case is [needsAttention], not [isPresent]
///
/// > *"Source text may exist when the normalized value is NULL — and that is
/// > the important case, not an edge case. An amount whose decimal separator
/// > could not be resolved is stored as a NULL value with its printed text
/// > intact and `AMBIGUOUS_AMOUNT_FORMAT` warned, so the reviewer sees exactly
/// > what was printed and types the figure themselves."*
///
/// No constraint requires a normalized counterpart to be non-null, so [value]
/// and [sourceText] are independently nullable here as well. Collapsing them —
/// treating a null value as "nothing was read" — would hide the printed text a
/// reviewer needs in precisely the case they need it most.
///
/// [T] is deliberately unconstrained by any transport type: a monetary field is
/// `ExtractedValue<int>` in **integer minor units** and never a double.
final class ExtractedValue<T extends Object> extends Equatable {
  const ExtractedValue({this.value, this.sourceText, this.confidence});

  /// The normalized reading, or null when the backend could not resolve one.
  final T? value;

  /// The text the value was read from, exactly as it was printed. Null when the
  /// field was not found at all.
  final String? sourceText;

  /// The provider's confidence, `0.0`–`1.0`, or null.
  ///
  /// A `numeric(4,3)` column bounded by a CHECK on both ends. It is a display
  /// hint: nothing in this client branches on it, and the backend's own review
  /// hints arrive as warning codes instead.
  final double? confidence;

  /// Whether a normalized value was produced.
  bool get isPresent => value != null;

  /// Whether something was printed but could not be resolved into a value.
  ///
  /// The reviewer must be shown [sourceText] and asked to type the figure.
  bool get needsAttention => value == null && sourceText != null;

  /// Whether the field was not found at all.
  bool get isAbsent => value == null && sourceText == null;

  @override
  List<Object?> get props => <Object?>[value, sourceText, confidence];
}
