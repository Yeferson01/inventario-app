import '../../../core/utils/app_uuid.dart';
import '../data/models/business_administration_models.dart';
import 'business_administration_service.dart';

typedef IdempotencyKeyFactory = String Function();

class BranchCreationController {
  BranchCreationController(
    this._service, {
    IdempotencyKeyFactory? keyFactory,
  }) : _keyFactory = keyFactory ?? AppUuid.v7;

  final BusinessAdministrationService _service;
  final IdempotencyKeyFactory _keyFactory;
  String? _fingerprint;
  String? _idempotencyKey;
  Future<BusinessBranchCreationResult>? _inFlight;

  Future<BusinessBranchCreationResult> submit(
    CreateBusinessBranchRequest request,
  ) {
    if (_inFlight != null && _fingerprint == request.fingerprint) {
      return _inFlight!;
    }
    if (_fingerprint != request.fingerprint) {
      _fingerprint = request.fingerprint;
      _idempotencyKey = _keyFactory();
    }
    final operation = _service.createBranch(
      request,
      idempotencyKey: _idempotencyKey!,
    );
    _inFlight = operation;
    operation.then((_) => _clear(), onError: (_) => _inFlight = null);
    return operation;
  }

  void _clear() {
    _fingerprint = null;
    _idempotencyKey = null;
    _inFlight = null;
  }
}

class BusinessInvitationIssueController {
  BusinessInvitationIssueController(
    this._service, {
    IdempotencyKeyFactory? keyFactory,
  }) : _keyFactory = keyFactory ?? AppUuid.v7;

  final BusinessAdministrationService _service;
  final IdempotencyKeyFactory _keyFactory;
  String? _fingerprint;
  String? _idempotencyKey;
  Future<IssueBusinessMemberInvitationResult>? _inFlight;

  Future<IssueBusinessMemberInvitationResult> submit(
    IssueBusinessMemberInvitationRequest request,
  ) {
    if (_inFlight != null && _fingerprint == request.fingerprint) {
      return _inFlight!;
    }
    if (_fingerprint != request.fingerprint) {
      _fingerprint = request.fingerprint;
      _idempotencyKey = _keyFactory();
    }
    final operation = _service.issueInvitation(
      request,
      idempotencyKey: _idempotencyKey!,
    );
    _inFlight = operation;
    operation.then((_) => _clear(), onError: (_) => _inFlight = null);
    return operation;
  }

  void _clear() {
    _fingerprint = null;
    _idempotencyKey = null;
    _inFlight = null;
  }
}
