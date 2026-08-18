enum CatalogEntityReconciliationState {
  cleanRemoteSynced,
  pendingLocal,
  transportAmbiguous,
  remotelyApplied,
  dirtyWithoutOutbox,
}

class CatalogEntityReconciliationClassification {
  const CatalogEntityReconciliationClassification({
    required this.state,
    required this.hasDirtyFlag,
    required this.recognizedAt,
  });

  final CatalogEntityReconciliationState state;
  final bool hasDirtyFlag;
  final DateTime? recognizedAt;

  bool get canAcceptRemote =>
      state == CatalogEntityReconciliationState.cleanRemoteSynced ||
      state == CatalogEntityReconciliationState.remotelyApplied;

  bool get mustPreserveLocal => !canAcceptRemote;
}
