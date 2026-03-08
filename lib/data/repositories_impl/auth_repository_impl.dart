import 'package:top_quality/data/datasources/remote/backend_data_source.dart';
import 'package:top_quality/domain/entities/app_user.dart';
import 'package:top_quality/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(this._dataSource);

  final BackendDataSource _dataSource;

  @override
  Future<AppUser?> getCurrentUser() => _dataSource.getCurrentUser();

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) {
    return _dataSource.signIn(email: email, password: password);
  }

  @override
  Future<void> signOut() => _dataSource.signOut();

  @override
  Stream<AppUser?> watchSession() => _dataSource.watchSession();
}

