import '../data/datasources/authorized_operational_context_local_dao.dart';
import '../data/datasources/core_context_local_dao.dart';
import '../data/models/core_context_snapshot_models.dart';
import '../data/models/local_recovery_models.dart';
import '../data/models/operational_bootstrap_models.dart';
import 'operational_bootstrap_page_applier.dart';

class CoreContextSnapshotApplier implements OperationalBootstrapPageApplier {
  CoreContextSnapshotApplier({
    required CoreContextLocalDao coreContextLocalDao,
    required AuthorizedOperationalContextLocalDao authorizationDao,
  })  : _coreContextLocalDao = coreContextLocalDao,
        _authorizationDao = authorizationDao;

  final CoreContextLocalDao _coreContextLocalDao;
  final AuthorizedOperationalContextLocalDao _authorizationDao;

  @override
  Future<OperationalBootstrapPageApplyResult> applyPage({
    required String profileId,
    required OperationalBootstrapSnapshotPage snapshot,
    required OperationalBootstrapDatasetPage page,
  }) async {
    if (snapshot.bundle != 'core' ||
        page.dataset != 'context' ||
        snapshot.datasets.length != 1 ||
        page.rows.length != 1) {
      throw const OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.malformedResponse,
        message:
            'CoreContextSnapshotApplier accepts only one core/context row.',
      );
    }

    final context = CoreContextSnapshot.fromBootstrapRow(page.rows.single);
    _validateScope(profileId, snapshot, context);

    await _coreContextLocalDao.upsertBusinessAndBranch(context);
    await _authorizationDao.replaceContext(
      AuthorizedOperationalContextProjection(
        profileId: context.profileId,
        businessId: context.business.id,
        branchId: context.branch.id,
        effectivePermissions: context.effectivePermissions,
        effectiveRoles: context.effectiveRoles
            .map((role) => role.name)
            .toList(growable: false),
        applicableMembershipIds: context.applicableMembershipIds,
        authorizationValidatedAt: context.authorizationValidatedAt,
        snapshotId: snapshot.snapshotId,
      ),
    );

    return OperationalBootstrapPageApplyResult(
      seenEntityIds: [
        'context:${context.profileId}:${context.business.id}:${context.branch.id}',
      ],
    );
  }

  void _validateScope(
    String profileId,
    OperationalBootstrapSnapshotPage snapshot,
    CoreContextSnapshot context,
  ) {
    if (context.profileId != profileId ||
        context.profileId != snapshot.profileId ||
        context.business.id != snapshot.businessId ||
        context.branch.id != snapshot.branchId ||
        context.appDevice.id != snapshot.appDeviceId ||
        context.authorizationValidatedAt != snapshot.authorizationValidatedAt) {
      throw const OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.scopeMismatch,
        message: 'Core context row does not match bootstrap snapshot scope.',
      );
    }
  }
}
