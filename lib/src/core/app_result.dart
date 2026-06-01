import 'app_error.dart';

sealed class AppResult<T> {
  const AppResult();

  bool get isOk => this is AppOk<T>;
}

class AppOk<T> extends AppResult<T> {
  const AppOk(this.value);

  final T value;
}

class AppFail<T> extends AppResult<T> {
  const AppFail(this.error);

  final AppError error;
}
