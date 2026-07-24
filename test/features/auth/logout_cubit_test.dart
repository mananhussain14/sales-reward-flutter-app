import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/auth/domain/repositories/auth_repository.dart';
import 'package:sale_reward/features/auth/presentation/cubit/logout_cubit.dart';

import '../../support/fakes.dart';

void main() {
  late FakeAuthRepository auth;

  setUp(() => auth = FakeAuthRepository(initialUser: testUser));
  tearDown(() => auth.dispose());

  LogoutCubit build() => LogoutCubit(authRepository: auth);

  blocTest<LogoutCubit, LogoutStatus>(
    'calls sign-out; on success stays in-progress until the shell is replaced',
    build: build,
    act: (LogoutCubit c) => c.signOut(),
    expect: () => <LogoutStatus>[LogoutStatus.inProgress],
    verify: (_) => expect(auth.signOutCallCount, 1),
  );

  blocTest<LogoutCubit, LogoutStatus>(
    'surfaces a failure rather than pretending the user is signed out',
    build: () {
      auth.nextSignOutResult = const SignOutFailed(UnavailableFailure());
      return build();
    },
    act: (LogoutCubit c) => c.signOut(),
    expect: () => <LogoutStatus>[LogoutStatus.inProgress, LogoutStatus.failed],
  );

  blocTest<LogoutCubit, LogoutStatus>(
    'a duplicate sign-out while in flight does not call sign-out twice',
    build: build,
    act: (LogoutCubit c) async =>
        Future.wait<void>(<Future<void>>[c.signOut(), c.signOut()]),
    verify: (_) => expect(auth.signOutCallCount, 1),
  );
}
