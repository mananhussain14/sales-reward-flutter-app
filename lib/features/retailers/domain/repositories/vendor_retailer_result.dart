import '../../../../core/result/read_result.dart';

export '../../../../core/result/read_result.dart';

/// The outcome of a Vendor Retailer **read**.
///
/// Now an alias of the shared [ReadResult], promoted into `core/` when the
/// Vendor User feature became the third to need the same two cases. The aliases
/// are kept rather than deleted so this feature's call sites and tests continue
/// to read in its own vocabulary, and so the promotion cost one file instead of
/// a hundred lines of rename.
typedef VendorRetailerResult<T> = ReadResult<T>;

/// The read succeeded. See [ReadSuccess].
typedef VendorRetailerReadSuccess<T> = ReadSuccess<T>;

/// The read did not produce an answer. See [ReadFailure].
typedef VendorRetailerReadFailure<T> = ReadFailure<T>;
