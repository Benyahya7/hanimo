// The one rule of the 2.0 rebuild: nothing fails silently.
// Every load and every action returns a Result — Ok(value) or
// Err(message) with a message a person can read. Screens always show the
// message when there is one. If the user cannot see what happened, the
// code is wrong.
sealed class Result<T> {
  const Result();
  const factory Result.ok(T value) = Ok<T>;
  const factory Result.err(String message) = Err<T>;

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  /// The value when ok, null otherwise.
  T? get valueOrNull => this is Ok<T> ? (this as Ok<T>).value : null;

  /// The message when err, null otherwise.
  String? get errorOrNull => this is Err<T> ? (this as Err<T>).message : null;
}

final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

final class Err<T> extends Result<T> {
  final String message;
  const Err(this.message);
}
