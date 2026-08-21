enum OperationalIntegrationFailureKind {
  unauthorized,
  forbidden,
  deviceBlocked,
  networkTransient,
  malformedResponse,
  scopeMismatch,
  remoteFailure,
}

class OperationalIntegrationException implements Exception {
  const OperationalIntegrationException({
    required this.kind,
    required this.message,
    this.cause,
  });

  final OperationalIntegrationFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => 'OperationalIntegrationException($kind): $message';
}
