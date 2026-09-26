enum CashMovementAckState { applied, rejected, ambiguous, notFound }

class CashMovementAck {
  const CashMovementAck({
    required this.id,
    required this.state,
    this.reason,
  });

  factory CashMovementAck.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final rawState = json['state'];
    if (id is! String || id.isEmpty || rawState is! String) {
      throw const FormatException('Malformed cash movement acknowledgement.');
    }
    final state = switch (rawState) {
      'applied' => CashMovementAckState.applied,
      'rejected' => CashMovementAckState.rejected,
      'ambiguous' => CashMovementAckState.ambiguous,
      'not_found' => CashMovementAckState.notFound,
      _ =>
        throw const FormatException('Unknown cash movement acknowledgement.'),
    };
    final rawReason = json['reason'];
    if (rawReason != null && rawReason is! String) {
      throw const FormatException(
          'Malformed cash movement acknowledgement reason.');
    }
    return CashMovementAck(id: id, state: state, reason: rawReason as String?);
  }

  final String id;
  final CashMovementAckState state;
  final String? reason;
}
