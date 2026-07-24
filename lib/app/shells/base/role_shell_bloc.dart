import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../navigation/role_destination.dart';

/// Events accepted by a role shell BLoC.
sealed class RoleShellEvent extends Equatable {
  const RoleShellEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// The user tapped a destination in this role's navigation.
final class RoleShellDestinationSelected extends RoleShellEvent {
  const RoleShellDestinationSelected(this.index);

  final int index;

  @override
  List<Object?> get props => <Object?>[index];
}

/// The router moved — deep link, back gesture, or a programmatic redirect.
///
/// The router is the source of truth for *where* the app is; this event keeps
/// the shell's highlighted tab in agreement with it. Without it, a back gesture
/// would change the screen and leave the wrong tab lit.
final class RoleShellLocationChanged extends RoleShellEvent {
  const RoleShellLocationChanged(this.location);

  final String location;

  @override
  List<Object?> get props => <Object?>[location];
}

/// The shell's presentation state: which destination is currently active.
final class RoleShellState extends Equatable {
  const RoleShellState({required this.selectedIndex});

  final int selectedIndex;

  @override
  List<Object?> get props => <Object?>[selectedIndex];
}

/// The shared mechanics of a role shell's navigation state.
///
/// ## Why this is abstract
///
/// The four roles genuinely share this behaviour — "keep the highlighted
/// destination in step with the router" is not role-specific — so the logic is
/// written once. What is role-specific is *which* destinations exist, and that
/// arrives as [navigation], supplied by each concrete subclass from its own
/// navigation file.
///
/// ## Why there are still four subclasses
///
/// Each role gets its own concrete type — [VendorShellBloc],
/// [RetailerOwnerShellBloc], [RetailerManagerShellBloc],
/// [SalesStaffShellBloc] — so that the type system, not a comment, prevents one
/// role's shell from being handed another role's BLoC. A single
/// `RoleShellBloc(navigation)` used everywhere would make that a runtime
/// question. It also gives each role an obvious place to put behaviour that
/// diverges later — a Sales Staff offline-queue badge, a Vendor pending-approval
/// count — without any of them growing a `switch (role)`.
abstract class RoleShellBloc extends Bloc<RoleShellEvent, RoleShellState> {
  RoleShellBloc(this.navigation)
    : super(const RoleShellState(selectedIndex: 0)) {
    on<RoleShellDestinationSelected>((event, emit) {
      if (event.index < 0 || event.index >= navigation.destinations.length) {
        // Fail closed: an out-of-range index leaves the shell where it is
        // rather than throwing into the widget tree.
        return;
      }
      emit(RoleShellState(selectedIndex: event.index));
    });

    on<RoleShellLocationChanged>((event, emit) {
      emit(
        RoleShellState(
          selectedIndex: navigation.indexForLocation(event.location),
        ),
      );
    });
  }

  /// This role's own navigation model. Never another role's.
  final RoleNavigation navigation;

  /// The route path for the currently selected destination.
  String get selectedPath => navigation.destinations[state.selectedIndex].path;
}
