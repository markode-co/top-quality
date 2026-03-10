import 'package:top_quality/domain/repositories/auth_repository.dart';

class SignInUseCase {
  const SignInUseCase(this._repository);

  final AuthRepository _repository;

  Future<void> call({required String identifier, required String password}) {
    return _repository.signIn(identifier: identifier, password: password);
  }
}
