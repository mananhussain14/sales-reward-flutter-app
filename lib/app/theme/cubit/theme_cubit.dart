import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Owns the user's light / dark / system preference.
///
/// ## Why a Cubit and not a Bloc
///
/// The whole state is one enum with three values and one transition — "the user
/// picked a mode". There is no event to model beyond the call itself, so a Bloc
/// would add an event class and a handler for no additional clarity. Every
/// other state holder in the app that *does* have meaningful events
/// (`SessionBloc`, the four shell BLoCs) remains a Bloc.
///
/// ## Why the selection is not persisted
///
/// [ThemeMode.system] is the default, so a fresh install already follows the
/// device — which is what most users want and never have to configure. Storing
/// an override would mean adding a persistence package for a single enum, and
/// this milestone is explicitly meant to stay lightweight.
///
/// The consequence is honest and small: an explicit light/dark override lasts
/// for the session and resets to system on relaunch. When a preferences store
/// arrives for something that genuinely needs it, this Cubit is one `emit` away
/// from reading and writing through it — the surface is already correct.
class ThemeCubit extends Cubit<ThemeMode> {
  ThemeCubit({ThemeMode initialMode = ThemeMode.system}) : super(initialMode);

  /// Follow the device setting. The default.
  void useSystem() => emit(ThemeMode.system);

  void useLight() => emit(ThemeMode.light);

  void useDark() => emit(ThemeMode.dark);

  void select(ThemeMode mode) => emit(mode);
}
