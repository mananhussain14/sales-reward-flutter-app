import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/errors/failure.dart';
import '../../domain/entities/app_role.dart';
import '../../domain/repositories/portal_context_repository.dart';

part 'role_session_event.dart';
part 'role_session_state.dart';

/// Owns the answer to "which experience is this caller in?" for the whole app.
///
/// ## Why this BLoC is shared and the others are not
///
/// Role resolution is one question with one answer, asked once per session and
/// re-asked on resume. Every role needs it and none of them needs a different
/// version of it, so it lives here, in the shared foundation, and each role's
/// shell BLoC owns only that role's own navigation.
///
/// The inverse — one BLoC holding every role's behaviour — is what this
/// architecture is specifically avoiding. This one is shared because it is
/// *role-neutral*, not because it is convenient.
///
/// ## What it is not
///
/// It is not an authorization service. It produces a hint about which shell to
/// build. Supabase remains the only authority on what the caller may do, and it
/// re-decides on every call regardless of what this BLoC last emitted.
class RoleSessionBloc extends Bloc<RoleSessionEvent, RoleSessionState> {
  RoleSessionBloc({required PortalContextRepository repository})
    : _repository = repository,
      super(const RoleSessionInitial()) {
    on<RoleSessionResolveRequested>(_onResolveRequested);
    on<RoleSessionPreviewSelected>(_onPreviewSelected);
    on<RoleSessionCleared>(_onCleared);
  }

  final PortalContextRepository _repository;

  Future<void> _onResolveRequested(
    RoleSessionResolveRequested event,
    Emitter<RoleSessionState> emit,
  ) async {
    emit(const RoleSessionResolving());

    final PortalContextResult result = await _repository.resolve();

    emit(switch (result) {
      PortalContextResolved(:final ResolvedRole role) => RoleSessionActive(
        role,
      ),
      PortalContextNone() => const RoleSessionNoAccess(),
      PortalContextFailed(:final Failure failure) => RoleSessionFailed(failure),
    });
  }

  void _onPreviewSelected(
    RoleSessionPreviewSelected event,
    Emitter<RoleSessionState> emit,
  ) {
    // Marked as a preview at construction, so nothing downstream can mistake it
    // for a backend answer.
    emit(RoleSessionActive(ResolvedRole.preview(event.role)));
  }

  void _onCleared(RoleSessionCleared event, Emitter<RoleSessionState> emit) {
    emit(const RoleSessionInitial());
  }
}
