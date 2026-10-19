class OperationCancelled implements Exception {
  const OperationCancelled([this.reason = 'Operation cancelled']);

  final String reason;

  @override
  String toString() => reason;
}

/// Cancellation is cooperative: network adapters should connect this token to
/// their HTTP client's abort/cancel mechanism instead of merely ignoring it.
class CancellationToken {
  bool _isCancelled = false;
  String _reason = 'Operation cancelled';
  final List<void Function(String reason)> _listeners = [];

  bool get isCancelled => _isCancelled;
  String get reason => _reason;

  void throwIfCancelled() {
    if (_isCancelled) throw OperationCancelled(_reason);
  }

  void cancel([String reason = 'Operation cancelled']) {
    if (_isCancelled) return;
    _isCancelled = true;
    _reason = reason;
    final listeners = List<void Function(String)>.from(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener(reason);
    }
  }

  void Function() onCancel(void Function(String reason) listener) {
    if (_isCancelled) {
      listener(_reason);
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}
