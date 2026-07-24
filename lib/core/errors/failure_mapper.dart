import 'package:supabase_flutter/supabase_flutter.dart';

import 'failure.dart';
import 'sql_state.dart';

/// Maps a thrown Supabase error to the shared [Failure] contract.
///
/// This is the **only** place in the application that inspects a backend error
/// object, which is what keeps three rules enforceable by review rather than by
/// vigilance:
///
/// 1. **No raw message escapes.** Nothing here reads `error.message` for display
///    or for discrimination. Postgres messages name tables, columns, functions
///    and policies, and the backend contract explicitly warns that message text
///    is not an API — the web client's two remaining substring checks are listed
///    as a defect to fix, not a pattern to copy.
/// 2. **Transport is never a denial.** Anything that is not a recognized
///    SQLSTATE becomes [UnavailableFailure].
/// 3. **Fail closed.** No branch returns a success-shaped value.
Failure mapSupabaseError(Object error) {
  if (error is PostgrestException) {
    return switch (error.code) {
      SqlState.insufficientPrivilege => const DeniedFailure(),
      SqlState.uniqueViolation => const DuplicateFailure(),
      SqlState.checkViolation => const InvalidFailure(),
      SqlState.objectNotInPrerequisiteState => const NotReadyFailure(),
      _ => const UnavailableFailure(),
    };
  }

  if (error is AuthException) {
    // The session is absent, expired, or rejected. Deliberately not bound to a
    // message: auth exceptions can carry token material, and the web client
    // avoids binding them for exactly that reason.
    return const UnauthenticatedFailure();
  }

  if (error is StorageException) {
    return const UnavailableFailure();
  }

  return const UnavailableFailure();
}
