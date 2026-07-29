part of 'lifecycle_access_cubit.dart';

/// How far the one diagnostic request has got.
///
/// Four phases, not "state or null": "we have not asked", "we are asking", "we
/// have an answer" and "we could not get one" choose different sentences, and
/// collapsing the first, second and fourth into a falsy value would render an
/// outage as though it were an answer.
enum LifecycleAccessPhase { initial, loading, resolved, unavailable }

/// The diagnostic Cubit's entire visible state.
///
/// ## What it deliberately does not carry
///
/// No auth user id, no timestamp, no `Failure`, no SQLSTATE, no exception, no
/// backend message and no raw response body. Each omission is load-bearing:
///
/// * The **auth user id** is a request-scoping concern, private to the Cubit. On
///   the state it would be one `toString()` away from a rendered UUID.
/// * A **timestamp** would imply a staleness policy that does not exist — the
///   Cubit answers once per page mount and is then disposed.
/// * A **`Failure`, SQLSTATE, exception or message** would reintroduce the
///   unauthenticated-versus-transport distinction the repository exists to
///   collapse, and would put backend text one interpolation away from a screen.
/// * The **raw body** would let a widget re-parse what the parser already
///   refused.
///
/// The state is therefore exactly a phase plus, on success, one enum member —
/// which is all that is needed to choose a sentence, and nothing more.
final class LifecycleAccessViewState extends Equatable {
  const LifecycleAccessViewState._(this.phase, this.state);

  /// Nothing has been asked yet. The page renders the ordinary denial.
  const LifecycleAccessViewState.initial()
    : this._(LifecycleAccessPhase.initial, null);

  /// The one request is in flight. The page still renders the ordinary denial,
  /// which is truthful at every instant.
  const LifecycleAccessViewState.loading()
    : this._(LifecycleAccessPhase.loading, null);

  /// One of the six words came back.
  const LifecycleAccessViewState.resolved(LifecycleAccessState state)
    : this._(LifecycleAccessPhase.resolved, state);

  /// The diagnostic could not be read, or answered something unrecognized.
  const LifecycleAccessViewState.unavailable()
    : this._(LifecycleAccessPhase.unavailable, null);

  final LifecycleAccessPhase phase;

  /// Non-null only when [phase] is [LifecycleAccessPhase.resolved].
  ///
  /// A resolved [LifecycleAccessState.active] or
  /// [LifecycleAccessState.noSupportedAccess] still renders the ordinary denial
  /// — see `lifecycle_access_copy.dart` for why both are absent from the notice
  /// map.
  final LifecycleAccessState? state;

  @override
  List<Object?> get props => <Object?>[phase, state];
}
