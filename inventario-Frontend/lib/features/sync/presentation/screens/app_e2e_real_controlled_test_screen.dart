import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/supabase/supabase_client_provider.dart';
import '../../application/app_e2e_local_flow_models.dart';
import '../../application/app_e2e_local_flow_provider.dart';
import '../../application/app_e2e_product_from_catalog_flow_models.dart';
import '../../application/app_e2e_product_from_catalog_flow_provider.dart';
import '../../application/operational_bootstrap_entry_models.dart';
import '../../application/operational_bootstrap_entry_providers.dart';
import '../../application/operational_bootstrap_orchestration_models.dart';
import '../../application/operational_bootstrap_providers.dart';
import '../../../inventory/application/inventory_initial_stock_models.dart';
import '../../../inventory/application/inventory_initial_stock_provider.dart';
import '../../application/inventory_sync_upload_provider.dart';
import '../../../inventory/application/product_stock_balance_providers.dart';
import '../../../sales/application/pos_local_sale_models.dart';
import '../../../sales/application/pos_local_sale_provider.dart';
import '../../application/pos_sync_upload_provider.dart';
import '../../../inventory/application/purchase_local_models.dart';
import '../../../inventory/application/purchase_local_provider.dart';
import '../../application/purchases_sync_upload_provider.dart';
import '../../../cash/application/cash_session_local_models.dart';
import '../../../cash/application/cash_session_local_provider.dart';
import '../../application/cash_sync_upload_provider.dart';
import '../../../cash/presentation/cash_presentation.dart';

class AppE2ERealControlledTestScreen extends ConsumerStatefulWidget {
  const AppE2ERealControlledTestScreen({
    super.key,
  });

  @override
  ConsumerState<AppE2ERealControlledTestScreen> createState() =>
      _AppE2ERealControlledTestScreenState();
}

class _AppE2ERealControlledTestScreenState
    extends ConsumerState<AppE2ERealControlledTestScreen> {
  static const bool _showLegacyE2EDebugButtons = false;

  final _businessIdController = TextEditingController(
    text: 'e56ea013-c8e1-4d38-86d0-ef5bc67b072b',
  );
  final _branchIdController = TextEditingController(
    text: 'a2115ea1-9104-419f-910f-30682993e6a3',
  );
  final _salePriceController = TextEditingController(text: '3500');
  final _purchasePriceController = TextEditingController(text: '0');
  final _initialStockQuantityController = TextEditingController(text: '10');
  final _initialStockUnitCostController = TextEditingController(text: '1200');
  final _syncedProductIdController = TextEditingController(
    text: '019f0ba1-704e-7ed6-a420-4114debb9ffa',
  );
  final _saleQuantityController = TextEditingController(text: '1');
  final _salePaymentMethodController = TextEditingController(text: 'cash');
  final _purchaseQuantityController = TextEditingController(text: '5');
  final _purchaseUnitCostController = TextEditingController(text: '1000');
  final _purchaseSupplierNameController = TextEditingController(
    text: 'Proveedor E2E Local',
  );
  final _cashRegisterNameController = TextEditingController(
    text: 'Caja E2E Principal',
  );
  final _cashRegisterCodeController = TextEditingController(text: 'MAIN');
  final _cashOpeningAmountController = TextEditingController(text: '50000');
  final _cashClosingAmountController = TextEditingController(text: '50000');

  bool _isRunning = false;
  Map<String, dynamic>? _lastResult;
  Object? _lastError;

  Future<void> _runOperationalBootstrap() async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final businessId = _optionalText(_businessIdController);
      final branchId = _optionalText(_branchIdController);
      if ((businessId == null) != (branchId == null)) {
        throw StateError(
          'Business y branch deben indicarse juntos o dejarse ambos vacíos.',
        );
      }
      final result = await ref.read(operationalBootstrapEntryRunnerProvider)(
        OperationalBootstrapEntryRequest(
          mode: OperationalBootstrapMode.recovery,
          selection: businessId == null
              ? null
              : OperationalContextSelection(
                  businessId: businessId,
                  branchId: branchId!,
                ),
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          metadata: const {
            'source': 'app_e2e_real_controlled_test_screen',
            'flow': 'operational_recovery_bootstrap',
          },
        ),
      );
      setState(() {
        _lastResult = {
          'flow': 'operational_recovery_bootstrap',
          ...result.toJson(),
        };
      });
    } catch (error) {
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _run({
    required bool runManualSync,
  }) async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final service = ref.read(appE2ELocalFlowServiceProvider);

      final result = await service.run(
        AppE2ELocalFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
          isOnline: isOnline,
          runManualSync: runManualSync,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'run_manual_sync': runManualSync,
          },
        ),
      );

      setState(() {
        _lastResult = result.toJson();
      });
    } catch (error) {
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _createProductFromCatalog({
    required bool runManualSyncAfterCreate,
  }) async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final service = ref.read(appE2EProductFromCatalogFlowServiceProvider);

      final result = await service.run(
        AppE2EProductFromCatalogFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
          isOnline: isOnline,
          salePrice: _doubleFromController(_salePriceController),
          purchasePrice: _doubleFromController(_purchasePriceController),
          runManualSyncAfterCreate: runManualSyncAfterCreate,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'flow': 'product_from_catalog',
            'run_manual_sync_after_create': runManualSyncAfterCreate,
          },
        ),
      );

      setState(() {
        _lastResult = result.toJson();
      });
    } catch (error) {
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _pullStockBalances() async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final preflightService = ref.read(appE2ELocalFlowServiceProvider);
      final stockPullService = ref.read(productStockBalancePullServiceProvider);

      final preflight = await preflightService.run(
        AppE2ELocalFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
          isOnline: isOnline,
          runManualSync: false,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'flow': 'pull_stock_balances',
          },
        ),
      );

      final context = preflight.selectedContext;

      if (context == null) {
        throw StateError('No se pudo resolver selectedContext.');
      }

      final productId = _requiredText(
        _syncedProductIdController,
        'Product ID sincronizado',
      );

      final businessId = context.savedBusinessId.trim().isNotEmpty
          ? context.savedBusinessId
          : context.selected.businessId;

      final branchId = context.savedBranchId?.trim().isNotEmpty == true
          ? context.savedBranchId!
          : context.selected.branchId;

      if (branchId == null || branchId.trim().isEmpty) {
        throw StateError(
            'No se pudo resolver branch_id para consultar saldos.');
      }

      final pullResult = await stockPullService.pullBranchBalances(
        businessId: businessId,
        branchId: branchId,
      );

      final localProductBalance = await stockPullService.getLocalProductBalance(
        businessId: businessId,
        branchId: branchId,
        productId: productId,
      );

      setState(() {
        _lastResult = {
          'flow': 'pull_stock_balances',
          'pull_result': pullResult.toJson(),
          'local_product_balance': localProductBalance,
        };
      });
    } catch (error) {
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _createInitialStock({
    required bool runManualSyncAfterCreate,
  }) async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final preflightService = ref.read(appE2ELocalFlowServiceProvider);
      final initialStockService =
          ref.read(inventoryInitialStockServiceProvider);
      final inventoryUploadService =
          ref.read(inventorySyncUploadServiceProvider);

      final preflight = await preflightService.run(
        AppE2ELocalFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
          isOnline: isOnline,
          runManualSync: true,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'flow': 'initial_stock_preflight',
          },
        ),
      );

      final context = preflight.selectedContext;
      final preflightJson = preflight.toJson();

      if (context == null) {
        throw StateError('No se pudo resolver selectedContext.');
      }

      final appDeviceId = _findStringDeep(
        preflightJson,
        const [
          'app_device_id',
          'appDeviceId',
          'app_devices_id',
          'appDevicesId',
        ],
      );

      if (appDeviceId == null) {
        setState(() {
          _lastResult = {
            'flow': 'initial_stock_preflight_debug',
            'preflight_json': preflightJson,
          };
        });

        throw StateError(
          'No se pudo resolver app_device_id real. '
          'El preflight sí corrió, pero la respuesta no expuso app_device_id '
          'en una ruta conocida. Revisa preflight_json en el resultado.',
        );
      }

      final businessId = context.savedBusinessId.trim().isNotEmpty
          ? context.savedBusinessId
          : context.selected.businessId;

      final branchId = context.savedBranchId?.trim().isNotEmpty == true
          ? context.savedBranchId
          : context.selected.branchId;

      if (branchId == null || branchId.trim().isEmpty) {
        throw StateError(
            'No se pudo resolver branch_id para crear stock inicial.');
      }

      final result = await initialStockService.createInitialStockAndQueueSync(
        CreateInitialStockInput(
          businessId: businessId,
          branchId: branchId,
          productId: _requiredText(
            _syncedProductIdController,
            'Product ID sincronizado',
          ),
          quantity: _intFromController(_initialStockQuantityController),
          unitCost: _doubleFromController(_initialStockUnitCostController),
          profileId: user,
          appDeviceId: appDeviceId,
          deviceInstallationId: preflight.installationId,
          clientSequenceStart: _safeClientSequenceStart(),
        ),
      );

      Map<String, dynamic>? uploadResult;

      if (runManualSyncAfterCreate) {
        final uploaded =
            await inventoryUploadService.uploadPendingInventoryBatches(
          businessId: businessId,
          branchId: branchId,
          batchLimit: 10,
        );

        uploadResult = uploaded.toJson();
      }

      setState(() {
        _lastResult = {
          'flow': 'initial_stock',
          'app_device_id': appDeviceId,
          'preflight_json': preflightJson,
          'creation_result': result.toJson(),
          'upload_result': uploadResult,
        };
      });
    } catch (error) {
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _uploadPendingPosSales() async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final preflightService = ref.read(appE2ELocalFlowServiceProvider);
      final posUploadService = ref.read(posSyncUploadServiceProvider);
      final stockPullService = ref.read(productStockBalancePullServiceProvider);

      final preflight = await preflightService.run(
        AppE2ELocalFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
          isOnline: isOnline,
          runManualSync: true,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'flow': 'upload_pending_pos_sales',
          },
        ),
      );

      final context = preflight.selectedContext;

      if (context == null) {
        throw StateError('No se pudo resolver selectedContext.');
      }

      final businessId = context.savedBusinessId.trim().isNotEmpty
          ? context.savedBusinessId
          : context.selected.businessId;

      final branchId = context.savedBranchId?.trim().isNotEmpty == true
          ? context.savedBranchId!
          : context.selected.branchId;

      if (branchId == null || branchId.trim().isEmpty) {
        throw StateError('No se pudo resolver branch_id para upload POS.');
      }

      final productId = _requiredText(
        _syncedProductIdController,
        'Product ID sincronizado',
      );

      final uploadResult = await posUploadService.uploadPendingPosBatches(
        businessId: businessId,
        branchId: branchId,
        batchLimit: 10,
      );

      final pullResult = await stockPullService.pullBranchBalances(
        businessId: businessId,
        branchId: branchId,
      );

      final localProductBalance = await stockPullService.getLocalProductBalance(
        businessId: businessId,
        branchId: branchId,
        productId: productId,
      );

      setState(() {
        _lastResult = {
          'flow': 'upload_pending_pos_sales',
          'business_id': businessId,
          'branch_id': branchId,
          'product_id': productId,
          'upload_result': uploadResult.toJson(),
          'pull_after_upload': pullResult.toJson(),
          'local_product_balance_after_pull': localProductBalance,
        };
      });
    } catch (error) {
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _enqueuePendingPosSales() async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final preflightService = ref.read(appE2ELocalFlowServiceProvider);
      final posOutboxService = ref.read(posSyncOutboxServiceProvider);

      final preflight = await preflightService.run(
        AppE2ELocalFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
          isOnline: isOnline,
          runManualSync: false,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'flow': 'enqueue_pending_pos_sales',
          },
        ),
      );

      final context = preflight.selectedContext;

      if (context == null) {
        throw StateError('No se pudo resolver selectedContext.');
      }

      final businessId = context.savedBusinessId.trim().isNotEmpty
          ? context.savedBusinessId
          : context.selected.businessId;

      final branchId = context.savedBranchId?.trim().isNotEmpty == true
          ? context.savedBranchId!
          : context.selected.branchId;

      if (branchId == null || branchId.trim().isEmpty) {
        throw StateError(
            'No se pudo resolver branch_id para encolar ventas POS.');
      }

      final preflightJson = preflight.toJson();

      final appDeviceId = _findStringDeep(
        preflightJson,
        const [
          'app_device_id',
          'appDeviceId',
          'app_devices_id',
          'appDevicesId',
        ],
      );

      if (appDeviceId == null || appDeviceId.trim().isEmpty) {
        setState(() {
          _lastResult = {
            'flow': 'enqueue_pending_pos_sales_preflight_debug',
            'preflight_json': preflightJson,
          };
        });

        throw StateError(
          'No se pudo resolver app_device_id real para encolar ventas POS.',
        );
      }

      final result = await posOutboxService.enqueuePendingPosSales(
        businessId: businessId,
        branchId: branchId,
        profileId: user,
        appDeviceId: appDeviceId,
        deviceInstallationId: preflight.installationId,
        limit: 10,
      );

      setState(() {
        _lastResult = {
          'flow': 'enqueue_pending_pos_sales',
          'business_id': businessId,
          'branch_id': branchId,
          'app_device_id': appDeviceId,
          'result': result.toJson(),
        };
      });
    } catch (error) {
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _enqueuePendingCash() async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final preflightService = ref.read(appE2ELocalFlowServiceProvider);
      final cashOutboxService = ref.read(cashSyncOutboxServiceProvider);

      final preflight = await preflightService.run(
        AppE2ELocalFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
          isOnline: isOnline,
          runManualSync: false,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'flow': 'enqueue_pending_cash',
          },
        ),
      );

      final context = preflight.selectedContext;

      if (context == null) {
        throw StateError('No se pudo resolver selectedContext.');
      }

      final businessId = context.savedBusinessId.trim().isNotEmpty
          ? context.savedBusinessId
          : context.selected.businessId;

      final branchId = context.savedBranchId?.trim().isNotEmpty == true
          ? context.savedBranchId!
          : context.selected.branchId;

      if (branchId == null || branchId.trim().isEmpty) {
        throw StateError('No se pudo resolver branch_id para encolar cash.');
      }

      final preflightJson = preflight.toJson();

      final appDeviceId = _findStringDeep(
        preflightJson,
        const [
          'app_device_id',
          'appDeviceId',
          'app_devices_id',
          'appDevicesId',
        ],
      );

      if (appDeviceId == null || appDeviceId.trim().isEmpty) {
        setState(() {
          _lastResult = {
            'flow': 'enqueue_pending_cash_preflight_debug',
            'preflight_json': preflightJson,
          };
        });

        throw StateError(
          'No se pudo resolver app_device_id real para encolar cash.',
        );
      }

      final result = await cashOutboxService.enqueuePendingCash(
        businessId: businessId,
        branchId: branchId,
        profileId: user,
        appDeviceId: appDeviceId,
        deviceInstallationId: preflight.installationId,
        limit: 10,
      );

      setState(() {
        _lastResult = {
          'flow': 'enqueue_pending_cash',
          'business_id': businessId,
          'branch_id': branchId,
          'app_device_id': appDeviceId,
          'result': result.toJson(),
        };
      });
    } catch (error) {
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _uploadPendingCash() async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final preflightService = ref.read(appE2ELocalFlowServiceProvider);
      final cashUploadService = ref.read(cashSyncUploadServiceProvider);
      final cashSessionService = ref.read(cashSessionLocalServiceProvider);

      final preflight = await preflightService.run(
        AppE2ELocalFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
          isOnline: isOnline,
          runManualSync: true,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'flow': 'upload_pending_cash',
          },
        ),
      );

      final context = preflight.selectedContext;

      if (context == null) {
        throw StateError('No se pudo resolver selectedContext.');
      }

      final businessId = context.savedBusinessId.trim().isNotEmpty
          ? context.savedBusinessId
          : context.selected.businessId;

      final branchId = context.savedBranchId?.trim().isNotEmpty == true
          ? context.savedBranchId!
          : context.selected.branchId;

      if (branchId == null || branchId.trim().isEmpty) {
        throw StateError('No se pudo resolver branch_id para upload cash.');
      }

      final uploadResult = await cashUploadService.uploadPendingCashBatches(
        businessId: businessId,
        branchId: branchId,
        batchLimit: 10,
      );

      final summary = await cashSessionService.getPosCashReadinessSummary(
        businessId: businessId,
        branchId: branchId,
      );

      final preview = await cashSessionService.getSalesCashAssociationPreview(
        businessId: businessId,
        branchId: branchId,
        limit: 10,
      );

      setState(() {
        _lastResult = {
          'flow': 'upload_pending_cash',
          'business_id': businessId,
          'branch_id': branchId,
          'upload_result': uploadResult.toJson(),
          'cash_readiness_after_upload': summary,
          'sales_cash_preview_after_upload': preview,
          'expected': {
            'dirty_cash_register_count': 0,
            'dirty_cash_session_count': 0,
            'can_upload_pos_now': true,
          },
        };
      });
    } catch (error) {
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _verifyPosCashAssociation() async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final preflightService = ref.read(appE2ELocalFlowServiceProvider);
      final cashSessionService = ref.read(cashSessionLocalServiceProvider);

      final preflight = await preflightService.run(
        AppE2ELocalFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
          isOnline: isOnline,
          runManualSync: false,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'flow': 'verify_pos_cash_association',
          },
        ),
      );

      final context = preflight.selectedContext;

      if (context == null) {
        throw StateError('No se pudo resolver selectedContext.');
      }

      final businessId = context.savedBusinessId.trim().isNotEmpty
          ? context.savedBusinessId
          : context.selected.businessId;

      final branchId = context.savedBranchId?.trim().isNotEmpty == true
          ? context.savedBranchId!
          : context.selected.branchId;

      if (branchId == null || branchId.trim().isEmpty) {
        throw StateError(
            'No se pudo resolver branch_id para verificar POS/caja.');
      }

      final summary = await cashSessionService.getPosCashReadinessSummary(
        businessId: businessId,
        branchId: branchId,
      );

      final preview = await cashSessionService.getSalesCashAssociationPreview(
        businessId: businessId,
        branchId: branchId,
        limit: 10,
      );

      setState(() {
        _lastResult = {
          'flow': 'verify_pos_cash_association',
          'business_id': businessId,
          'branch_id': branchId,
          'summary': summary,
          'sales_cash_preview': preview,
          'recommended_upload_order': [
            'cash_registers',
            'cash_sessions',
            'sales',
            'sale_items',
            'sale_payments',
          ],
          'interpretation': {
            'cash_must_upload_before_pos':
                summary['cash_must_upload_before_pos'] == true,
            'can_upload_pos_now': summary['pos_upload_blocked_reason'] == null,
            'next_phase_if_blocked':
                '6.18C.38F - Encolar/upload cash_registers y cash_sessions',
          },
        };
      });
    } catch (error) {
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _openRealCashDashboard() async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final preflightService = ref.read(appE2ELocalFlowServiceProvider);

      final preflight = await preflightService.run(
        AppE2ELocalFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
          isOnline: isOnline,
          runManualSync: false,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'flow': 'open_real_cash_dashboard',
          },
        ),
      );

      final selectedContext = preflight.selectedContext;

      if (selectedContext == null) {
        throw StateError('No se pudo resolver selectedContext.');
      }

      final businessId = selectedContext.savedBusinessId.trim().isNotEmpty
          ? selectedContext.savedBusinessId
          : selectedContext.selected.businessId;

      final branchId = selectedContext.savedBranchId?.trim().isNotEmpty == true
          ? selectedContext.savedBranchId!
          : selectedContext.selected.branchId;

      if (branchId == null || branchId.trim().isEmpty) {
        throw StateError(
          'No se pudo resolver branch_id para abrir UI real de caja.',
        );
      }

      final preflightJson = preflight.toJson();

      final appDeviceId = _findStringDeep(
        preflightJson,
        const [
          'app_device_id',
          'appDeviceId',
        ],
      );

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) {
            return CashDashboardScreen(
              businessId: businessId,
              branchId: branchId,
              profileId: user,
              canReadCash: true,
              canOpenCash: true,
              canCloseCash: true,
              appDeviceId: appDeviceId,
              deviceInstallationId: preflight.installationId,
            );
          },
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _lastResult = {
          'flow': 'open_real_cash_dashboard',
          'status': 'returned_from_cash_dashboard',
          'business_id': businessId,
          'branch_id': branchId,
          'profile_id': user,
          'app_device_id': appDeviceId,
          'device_installation_id': preflight.installationId,
        };
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _showCashCloseSummary() async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final preflightService = ref.read(appE2ELocalFlowServiceProvider);
      final cashSessionService = ref.read(cashSessionLocalServiceProvider);

      final preflight = await preflightService.run(
        AppE2ELocalFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
          isOnline: isOnline,
          runManualSync: false,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'flow': 'show_cash_close_summary',
          },
        ),
      );

      final context = preflight.selectedContext;

      if (context == null) {
        throw StateError('No se pudo resolver selectedContext.');
      }

      final businessId = context.savedBusinessId.trim().isNotEmpty
          ? context.savedBusinessId
          : context.selected.businessId;

      final branchId = context.savedBranchId?.trim().isNotEmpty == true
          ? context.savedBranchId!
          : context.selected.branchId;

      if (branchId == null || branchId.trim().isEmpty) {
        throw StateError(
          'No se pudo resolver branch_id para resumen de cierre de caja.',
        );
      }

      final summary =
          await cashSessionService.getLatestCashSessionSummaryForBranch(
        businessId: businessId,
        branchId: branchId,
      );

      setState(() {
        _lastResult = {
          'flow': 'show_cash_close_summary',
          'business_id': businessId,
          'branch_id': branchId,
          'summary': summary,
          'expected_meaning': {
            'opening_cash_amount': 'Monto inicial de caja',
            'cash_payments': 'Pagos en efectivo de ventas de la sesión',
            'calculated_expected_cash_amount':
                'opening_cash_amount + cash_payments',
            'closing_cash_amount': 'Monto contado al cerrar',
            'difference_amount': 'closing_cash_amount - expected_cash_amount',
          },
        };
      });
    } catch (error) {
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _closeLocalCashSession() async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final preflightService = ref.read(appE2ELocalFlowServiceProvider);
      final cashSessionService = ref.read(cashSessionLocalServiceProvider);

      final preflight = await preflightService.run(
        AppE2ELocalFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
          isOnline: isOnline,
          runManualSync: false,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'flow': 'close_local_cash_session',
          },
        ),
      );

      final context = preflight.selectedContext;

      if (context == null) {
        throw StateError('No se pudo resolver selectedContext.');
      }

      final businessId = context.savedBusinessId.trim().isNotEmpty
          ? context.savedBusinessId
          : context.selected.businessId;

      final branchId = context.savedBranchId?.trim().isNotEmpty == true
          ? context.savedBranchId!
          : context.selected.branchId;

      if (branchId == null || branchId.trim().isEmpty) {
        throw StateError('No se pudo resolver branch_id para cerrar caja.');
      }

      final closingAmount = double.tryParse(
        _cashClosingAmountController.text.trim(),
      );

      if (closingAmount == null) {
        throw StateError('Monto de cierre inválido.');
      }

      final result = await cashSessionService.closeCashSession(
        CloseCashSessionInput(
          businessId: businessId,
          branchId: branchId,
          profileId: user,
          actualClosingAmount: closingAmount,
          notes: 'Cierre local E2E desde debug screen',
        ),
      );

      final summary = await cashSessionService.getPosCashReadinessSummary(
        businessId: businessId,
        branchId: branchId,
      );

      final preview = await cashSessionService.getSalesCashAssociationPreview(
        businessId: businessId,
        branchId: branchId,
        limit: 10,
      );

      setState(() {
        _lastResult = {
          'flow': 'close_local_cash_session',
          'business_id': businessId,
          'branch_id': branchId,
          'result': result.toJson(),
          'cash_readiness_after_close': summary,
          'sales_cash_preview_after_close': preview,
          'next_steps': [
            '17. Encolar cash pendiente',
            '18. Upload cash pendiente',
            '16. Verificar POS/caja',
          ],
        };
      });
    } catch (error) {
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _openLocalCashSession() async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final preflightService = ref.read(appE2ELocalFlowServiceProvider);
      final cashSessionService = ref.read(cashSessionLocalServiceProvider);

      final preflight = await preflightService.run(
        AppE2ELocalFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
          isOnline: isOnline,
          runManualSync: false,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'flow': 'open_local_cash_session',
          },
        ),
      );

      final context = preflight.selectedContext;

      if (context == null) {
        throw StateError('No se pudo resolver selectedContext.');
      }

      final businessId = context.savedBusinessId.trim().isNotEmpty
          ? context.savedBusinessId
          : context.selected.businessId;

      final branchId = context.savedBranchId?.trim().isNotEmpty == true
          ? context.savedBranchId!
          : context.selected.branchId;

      if (branchId == null || branchId.trim().isEmpty) {
        throw StateError(
            'No se pudo resolver branch_id para abrir caja local.');
      }

      final preflightJson = preflight.toJson();

      final appDeviceId = _findStringDeep(
        preflightJson,
        const [
          'app_device_id',
          'appDeviceId',
          'app_devices_id',
          'appDevicesId',
        ],
      );

      if (appDeviceId == null || appDeviceId.trim().isEmpty) {
        setState(() {
          _lastResult = {
            'flow': 'open_local_cash_session_preflight_debug',
            'preflight_json': preflightJson,
          };
        });

        throw StateError(
          'No se pudo resolver app_device_id real para abrir caja local.',
        );
      }

      final result = await cashSessionService.openCashSession(
        OpenCashSessionInput(
          businessId: businessId,
          branchId: branchId,
          profileId: user,
          cashRegisterName: _requiredText(
            _cashRegisterNameController,
            'Nombre de caja',
          ),
          cashRegisterCode: _requiredText(
            _cashRegisterCodeController,
            'Código de caja',
          ),
          openingCashAmount: _doubleFromController(
            _cashOpeningAmountController,
          ),
          appDeviceId: appDeviceId,
          deviceInstallationId: preflight.installationId,
          metadata: {
            'phase': '6.18C.38C',
            'source': 'app_e2e_real_controlled_test_screen',
          },
        ),
      );

      final openSession = await cashSessionService.getOpenCashSession(
        businessId: businessId,
        branchId: branchId,
      );

      setState(() {
        _lastResult = {
          'flow': 'open_local_cash_session',
          'business_id': businessId,
          'branch_id': branchId,
          'app_device_id': appDeviceId,
          'result': result.toJson(),
          'open_session_after': openSession?.toJson(),
          'expected': {
            'cash_register_created_first_time': true,
            'cash_session_status': 'open',
            'reusing_same_open_session_on_repeat': true,
            'remote_should_not_change_yet': true,
          },
        };
      });
    } catch (error) {
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _uploadPendingPurchases() async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final preflightService = ref.read(appE2ELocalFlowServiceProvider);
      final purchasesUploadService =
          ref.read(purchasesSyncUploadServiceProvider);
      final stockPullService = ref.read(productStockBalancePullServiceProvider);

      final preflight = await preflightService.run(
        AppE2ELocalFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
          isOnline: isOnline,
          runManualSync: true,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'flow': 'upload_pending_purchases',
          },
        ),
      );

      final context = preflight.selectedContext;

      if (context == null) {
        throw StateError('No se pudo resolver selectedContext.');
      }

      final businessId = context.savedBusinessId.trim().isNotEmpty
          ? context.savedBusinessId
          : context.selected.businessId;

      final branchId = context.savedBranchId?.trim().isNotEmpty == true
          ? context.savedBranchId!
          : context.selected.branchId;

      if (branchId == null || branchId.trim().isEmpty) {
        throw StateError(
            'No se pudo resolver branch_id para upload de compras.');
      }

      final productId = _requiredText(
        _syncedProductIdController,
        'Product ID sincronizado',
      );

      final uploadResult =
          await purchasesUploadService.uploadPendingPurchasesBatches(
        businessId: businessId,
        branchId: branchId,
        batchLimit: 10,
      );

      final pullResult = await stockPullService.pullBranchBalances(
        businessId: businessId,
        branchId: branchId,
      );

      final localProductBalance = await stockPullService.getLocalProductBalance(
        businessId: businessId,
        branchId: branchId,
        productId: productId,
      );

      setState(() {
        _lastResult = {
          'flow': 'upload_pending_purchases',
          'business_id': businessId,
          'branch_id': branchId,
          'product_id': productId,
          'upload_result': uploadResult.toJson(),
          'pull_after_upload': pullResult.toJson(),
          'local_product_balance_after_pull': localProductBalance,
        };
      });
    } catch (error) {
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _enqueuePendingPurchases() async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final preflightService = ref.read(appE2ELocalFlowServiceProvider);
      final purchaseOutboxService = ref.read(purchaseSyncOutboxServiceProvider);

      final preflight = await preflightService.run(
        AppE2ELocalFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
          isOnline: isOnline,
          runManualSync: false,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'flow': 'enqueue_pending_purchases',
          },
        ),
      );

      final context = preflight.selectedContext;

      if (context == null) {
        throw StateError('No se pudo resolver selectedContext.');
      }

      final businessId = context.savedBusinessId.trim().isNotEmpty
          ? context.savedBusinessId
          : context.selected.businessId;

      final branchId = context.savedBranchId?.trim().isNotEmpty == true
          ? context.savedBranchId!
          : context.selected.branchId;

      if (branchId == null || branchId.trim().isEmpty) {
        throw StateError('No se pudo resolver branch_id para encolar compras.');
      }

      final preflightJson = preflight.toJson();

      final appDeviceId = _findStringDeep(
        preflightJson,
        const [
          'app_device_id',
          'appDeviceId',
          'app_devices_id',
          'appDevicesId',
        ],
      );

      if (appDeviceId == null || appDeviceId.trim().isEmpty) {
        setState(() {
          _lastResult = {
            'flow': 'enqueue_pending_purchases_preflight_debug',
            'preflight_json': preflightJson,
          };
        });

        throw StateError(
          'No se pudo resolver app_device_id real para encolar compras.',
        );
      }

      final result = await purchaseOutboxService.enqueuePendingPurchases(
        businessId: businessId,
        branchId: branchId,
        profileId: user,
        appDeviceId: appDeviceId,
        deviceInstallationId: preflight.installationId,
        limit: 10,
      );

      setState(() {
        _lastResult = {
          'flow': 'enqueue_pending_purchases',
          'business_id': businessId,
          'branch_id': branchId,
          'app_device_id': appDeviceId,
          'result': result.toJson(),
        };
      });
    } catch (error) {
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _createOfflineLocalPurchase() async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final preflightService = ref.read(appE2ELocalFlowServiceProvider);
      final purchaseLocalService = ref.read(purchaseLocalServiceProvider);
      final stockPullService = ref.read(productStockBalancePullServiceProvider);

      final preflight = await preflightService.run(
        AppE2ELocalFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
          isOnline: isOnline,
          runManualSync: false,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'flow': 'purchase_offline_local',
          },
        ),
      );

      final context = preflight.selectedContext;

      if (context == null) {
        throw StateError('No se pudo resolver selectedContext.');
      }

      final businessId = context.savedBusinessId.trim().isNotEmpty
          ? context.savedBusinessId
          : context.selected.businessId;

      final branchId = context.savedBranchId?.trim().isNotEmpty == true
          ? context.savedBranchId!
          : context.selected.branchId;

      if (branchId == null || branchId.trim().isEmpty) {
        throw StateError('No se pudo resolver branch_id para compra offline.');
      }

      final preflightJson = preflight.toJson();
      final appDeviceId = _findStringDeep(
        preflightJson,
        const [
          'app_device_id',
          'appDeviceId',
          'app_devices_id',
          'appDevicesId',
        ],
      );

      if (appDeviceId == null || appDeviceId.trim().isEmpty) {
        setState(() {
          _lastResult = {
            'flow': 'purchase_offline_local_preflight_debug',
            'preflight_json': preflightJson,
          };
        });

        throw StateError(
          'No se pudo resolver app_device_id real para compra offline.',
        );
      }

      final productId = _requiredText(
        _syncedProductIdController,
        'Product ID sincronizado',
      );

      final beforeBalance = await stockPullService.getLocalProductBalance(
        businessId: businessId,
        branchId: branchId,
        productId: productId,
      );

      final result = await purchaseLocalService.createLocalPurchase(
        CreatePurchaseLocalInput(
          businessId: businessId,
          branchId: branchId,
          profileId: user,
          supplierName: _optionalText(_purchaseSupplierNameController),
          appDeviceId: appDeviceId,
          deviceInstallationId: preflight.installationId,
          clientSequenceStart: _safeClientSequenceStart(),
          items: [
            PurchaseLocalItemInput(
              productId: productId,
              quantity: _intFromController(_purchaseQuantityController),
              unitCost: _doubleFromController(_purchaseUnitCostController),
            ),
          ],
          metadata: {
            'phase': '6.18C.37C.2',
            'source': 'app_e2e_real_controlled_test_screen',
          },
        ),
      );

      final afterBalance = await stockPullService.getLocalProductBalance(
        businessId: businessId,
        branchId: branchId,
        productId: productId,
      );

      setState(() {
        _lastResult = {
          'flow': 'purchase_offline_local',
          'purchase_result': result.toJson(),
          'stock_before': beforeBalance,
          'stock_after': afterBalance,
          'expected': {
            'purchase_quantity':
                _intFromController(_purchaseQuantityController),
            'unit_cost': _doubleFromController(_purchaseUnitCostController),
            'remote_should_not_change_yet': true,
            'legacy_stock_quantity_should_remain': 0,
          },
        };
      });
    } catch (error) {
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _createOfflineLocalSale() async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final preflightService = ref.read(appE2ELocalFlowServiceProvider);
      final posLocalSaleService = ref.read(posLocalSaleServiceProvider);
      final cashSessionService = ref.read(cashSessionLocalServiceProvider);
      final stockPullService = ref.read(productStockBalancePullServiceProvider);

      final preflight = await preflightService.run(
        AppE2ELocalFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
          isOnline: isOnline,
          runManualSync: false,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'flow': 'pos_offline_local_sale',
          },
        ),
      );

      final context = preflight.selectedContext;

      if (context == null) {
        throw StateError('No se pudo resolver selectedContext.');
      }

      final businessId = context.savedBusinessId.trim().isNotEmpty
          ? context.savedBusinessId
          : context.selected.businessId;

      final branchId = context.savedBranchId?.trim().isNotEmpty == true
          ? context.savedBranchId!
          : context.selected.branchId;

      if (branchId == null || branchId.trim().isEmpty) {
        throw StateError('No se pudo resolver branch_id para venta offline.');
      }

      final preflightJson = preflight.toJson();

      final openCashSession = await cashSessionService.getOpenCashSession(
        businessId: businessId,
        branchId: branchId,
      );

      if (openCashSession == null) {
        throw StateError(
          'No hay caja abierta para esta sucursal. Usa primero el botón 15. Abrir caja local.',
        );
      }

      final productId = _requiredText(
        _syncedProductIdController,
        'Product ID sincronizado',
      );

      final appDeviceId = _findStringDeep(
        preflightJson,
        const [
          'app_device_id',
          'appDeviceId',
          'app_devices_id',
          'appDevicesId',
        ],
      );

      if (appDeviceId == null || appDeviceId.trim().isEmpty) {
        setState(() {
          _lastResult = {
            'flow': 'pos_offline_local_sale_preflight_debug',
            'preflight_json': preflightJson,
          };
        });

        throw StateError(
          'No se pudo resolver app_device_id real para venta offline.',
        );
      }

      final beforeBalance = await stockPullService.getLocalProductBalance(
        businessId: businessId,
        branchId: branchId,
        productId: productId,
      );

      final saleQuantity = _intFromController(_saleQuantityController);

      final result = await posLocalSaleService.createLocalSale(
        CreatePosLocalSaleInput(
          businessId: businessId,
          branchId: branchId,
          profileId: user,
          customerId: null,
          cashRegisterId: openCashSession.cashRegisterId,
          cashSessionId: openCashSession.id,
          appDeviceId: appDeviceId,
          deviceInstallationId: preflight.installationId,
          clientSequenceStart: _safeClientSequenceStart(),
          items: [
            PosLocalSaleItemInput(
              productId: productId,
              quantity: saleQuantity,
            ),
          ],
          payments: const [],
          metadata: {
            'phase': '6.18C.33C',
            'source': 'app_e2e_real_controlled_test_screen',
            'payment_method': 'cash',
          },
        ),
      );

      final afterBalance = await stockPullService.getLocalProductBalance(
        businessId: businessId,
        branchId: branchId,
        productId: productId,
      );

      setState(() {
        _lastResult = {
          'flow': 'pos_offline_local_sale',
          'business_id': businessId,
          'branch_id': branchId,
          'app_device_id': appDeviceId,
          'product_id': productId,
          'sale_quantity': saleQuantity,
          'sale_result': result.toJson(),
          'cash_session_used': openCashSession.toJson(),
          'stock_before': beforeBalance,
          'stock_after': afterBalance,
          'expected': {
            'quantity_before': 10,
            'sale_quantity': saleQuantity,
            'quantity_after': 10 - saleQuantity,
            'legacy_stock_quantity_should_remain': 0,
          },
        };
      });
    } catch (error) {
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<void> _previewProductsWithLocalStock() async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final preflightService = ref.read(appE2ELocalFlowServiceProvider);
      final stockDao = ref.read(productStockBalanceLocalDaoProvider);

      final preflight = await preflightService.run(
        AppE2ELocalFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
          isOnline: isOnline,
          runManualSync: false,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'flow': 'preview_products_with_local_stock',
          },
        ),
      );

      final context = preflight.selectedContext;

      if (context == null) {
        throw StateError('No se pudo resolver selectedContext.');
      }

      final businessId = context.savedBusinessId.trim().isNotEmpty
          ? context.savedBusinessId
          : context.selected.businessId;

      final branchId = context.savedBranchId?.trim().isNotEmpty == true
          ? context.savedBranchId!
          : context.selected.branchId;

      if (branchId == null || branchId.trim().isEmpty) {
        throw StateError(
            'No se pudo resolver branch_id para preview de stock.');
      }

      final products = await stockDao.getProductsWithLocalStock(
        businessId: businessId,
        branchId: branchId,
        limit: 30,
      );

      setState(() {
        _lastResult = {
          'flow': 'preview_products_with_local_stock',
          'business_id': businessId,
          'branch_id': branchId,
          'count': products.length,
          'products': products,
        };
      });
    } catch (error) {
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _businessIdController.dispose();
    _branchIdController.dispose();
    _salePriceController.dispose();
    _purchasePriceController.dispose();
    _initialStockQuantityController.dispose();
    _initialStockUnitCostController.dispose();
    _syncedProductIdController.dispose();
    _saleQuantityController.dispose();
    _salePaymentMethodController.dispose();
    _purchaseQuantityController.dispose();
    _purchaseUnitCostController.dispose();
    _purchaseSupplierNameController.dispose();
    _cashRegisterNameController.dispose();
    _cashRegisterCodeController.dispose();
    _cashOpeningAmountController.dispose();
    _cashClosingAmountController.dispose();
    super.dispose();
  }

  String _requireCurrentUserId() {
    final supabase = ref.read(supabaseClientProvider);
    final user = supabase.auth.currentUser;

    if (user == null) {
      throw StateError(
        'No hay usuario autenticado. Inicia sesión antes de ejecutar la prueba.',
      );
    }

    return user.id;
  }

  Future<bool> _isOnline() async {
    final connectivity = await Connectivity().checkConnectivity();

    return connectivity.any(
      (item) => item != ConnectivityResult.none,
    );
  }

  String? _optionalText(TextEditingController controller) {
    final value = controller.text.trim();

    if (value.isEmpty) {
      return null;
    }

    return value;
  }

  double _doubleFromController(TextEditingController controller) {
    final value = double.tryParse(
      controller.text.trim().replaceAll(',', '.'),
    );

    if (value == null || value < 0) {
      throw ArgumentError('Precio inválido: ${controller.text}');
    }

    return value;
  }

  String _requiredText(
    TextEditingController controller,
    String fieldName,
  ) {
    final value = controller.text.trim();

    if (value.isEmpty) {
      throw StateError('El campo $fieldName es obligatorio.');
    }

    return value;
  }

  int _intFromController(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());

    if (value == null || value < 0) {
      throw ArgumentError('Cantidad inválida: ${controller.text}');
    }

    return value;
  }

  int _safeClientSequenceStart() {
    final value = DateTime.now().microsecondsSinceEpoch.remainder(2000000000);

    if (value < 1) {
      return 1;
    }

    return value;
  }

  String? _findStringDeep(
    Object? value,
    List<String> keys,
  ) {
    if (value == null) {
      return null;
    }

    if (value is Map) {
      for (final key in keys) {
        final raw = value[key];

        if (raw != null) {
          final text = raw.toString().trim();

          if (text.isNotEmpty) {
            return text;
          }
        }
      }

      for (final entry in value.entries) {
        final found = _findStringDeep(entry.value, keys);

        if (found != null) {
          return found;
        }
      }

      return null;
    }

    if (value is Iterable) {
      for (final item in value) {
        final found = _findStringDeep(item, keys);

        if (found != null) {
          return found;
        }
      }
    }

    return null;
  }

  String _deviceName() {
    if (kIsWeb) {
      return 'Web';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android device';
      case TargetPlatform.iOS:
        return 'iOS device';
      case TargetPlatform.macOS:
        return 'macOS device';
      case TargetPlatform.windows:
        return 'Windows device';
      case TargetPlatform.linux:
        return 'Linux device';
      case TargetPlatform.fuchsia:
        return 'Fuchsia device';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(supabaseClientProvider).auth.currentUser;
    final bootstrapProgress = ref.watch(operationalBootstrapProgressProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prueba real controlada'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '6.18C.26 — Producto real desde catálogo',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Esta pantalla valida login real, contexto operativo, sync manual '
            'y creación de producto local desde catálogo con outbox.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Laboratorio interno E2E. No es UI final. '
                'Usar solo para pruebas controladas de catálogo, inventario, '
                'POS, compras y caja.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _InfoTile(
            title: 'Usuario autenticado',
            value: user?.id ?? 'No autenticado',
          ),
          _InfoTile(
            title: 'Operational bootstrap',
            value: [
              bootstrapProgress.stage.name,
              if (bootstrapProgress.bundle != null) bootstrapProgress.bundle!,
              if (bootstrapProgress.dataset != null) bootstrapProgress.dataset!,
              if (bootstrapProgress.message != null) bootstrapProgress.message!,
            ].join(' / '),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _businessIdController,
            decoration: const InputDecoration(
              labelText: 'Business ID para pull operativo',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _branchIdController,
            decoration: const InputDecoration(
              labelText: 'Branch ID preferida',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _salePriceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Precio de venta para producto de prueba',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _purchasePriceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Precio de compra para producto de prueba',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _syncedProductIdController,
            decoration: const InputDecoration(
              labelText: 'Product ID sincronizado para stock inicial',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _initialStockQuantityController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Cantidad inicial',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _initialStockUnitCostController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Costo unitario inicial',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _saleQuantityController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Cantidad venta offline local',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _salePaymentMethodController,
            decoration: const InputDecoration(
              labelText: 'Método de pago venta local',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _purchaseQuantityController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Cantidad compra offline local',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _purchaseUnitCostController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Costo unitario compra local',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _purchaseSupplierNameController,
            decoration: const InputDecoration(
              labelText: 'Proveedor compra local',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cashRegisterNameController,
            decoration: const InputDecoration(
              labelText: 'Nombre caja local',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cashRegisterCodeController,
            decoration: const InputDecoration(
              labelText: 'Código caja local',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cashOpeningAmountController,
            decoration: const InputDecoration(
              labelText: 'Monto apertura caja local',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cashClosingAmountController,
            decoration: const InputDecoration(
              labelText: 'Monto cierre caja local',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: _isRunning ? null : _runOperationalBootstrap,
            child: const Text('Operational Recovery / Bootstrap'),
          ),
          const SizedBox(height: 12),
          if (_showLegacyE2EDebugButtons) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isRunning
                  ? null
                  : () {
                      _run(runManualSync: false);
                    },
              child: const Text(
                '1. Ejecutar flujo base E2E',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isRunning
                  ? null
                  : () {
                      _createProductFromCatalog(
                        runManualSyncAfterCreate: false,
                      );
                    },
              child: const Text(
                '2. Crear producto desde catálogo',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isRunning ? null : _pullStockBalances,
              child: const Text(
                '3. Pull stock balances',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isRunning
                  ? null
                  : () {
                      _createInitialStock(
                        runManualSyncAfterCreate: false,
                      );
                    },
              child: const Text(
                '4. Crear stock inicial',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isRunning ? null : _previewProductsWithLocalStock,
              child: const Text(
                '5. Preview productos con stock local',
              ),
            ),
          ],
          // legacy_debug_buttons_restored_hidden_1_to_6

          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isRunning ? null : _pullStockBalances,
            child: const Text(
              '7. Pull stock remoto',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isRunning ? null : _previewProductsWithLocalStock,
            child: const Text(
              '8. Preview productos con stock local',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isRunning ? null : _createOfflineLocalSale,
            child: const Text(
              '9. Crear venta POS offline local',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isRunning ? null : _enqueuePendingPosSales,
            child: const Text(
              '10. Encolar ventas POS pendientes',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isRunning ? null : _uploadPendingPosSales,
            child: const Text(
              '11. Upload ventas POS pendientes',
            ),
          ),
          FilledButton(
            onPressed: _isRunning ? null : _createOfflineLocalPurchase,
            child: const Text(
              '12. Crear compra offline local',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isRunning ? null : _enqueuePendingPurchases,
            child: const Text(
              '13. Encolar compras pendientes',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isRunning ? null : _uploadPendingPurchases,
            child: const Text(
              '14. Upload compras pendientes',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isRunning ? null : _openLocalCashSession,
            child: const Text(
              '15. Abrir caja local',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isRunning ? null : _closeLocalCashSession,
            child: const Text(
              '19. Cerrar caja local',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isRunning ? null : _showCashCloseSummary,
            child: const Text(
              '20. Resumen cierre caja',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isRunning ? null : _openRealCashDashboard,
            child: const Text(
              '21. Abrir UI real caja',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isRunning ? null : _verifyPosCashAssociation,
            child: const Text(
              '16. Verificar POS/caja',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isRunning ? null : _enqueuePendingCash,
            child: const Text(
              '17. Encolar cash pendiente',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isRunning ? null : _uploadPendingCash,
            child: const Text(
              '18. Upload cash pendiente',
            ),
          ),
          if (_isRunning) ...[
            const SizedBox(height: 24),
            const LinearProgressIndicator(),
          ],
          if (_lastError != null) ...[
            const SizedBox(height: 24),
            Text(
              'Error',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(
              _lastError.toString(),
              style: const TextStyle(color: Colors.red),
            ),
          ],
          if (_lastResult != null) ...[
            const SizedBox(height: 24),
            Text(
              'Resultado',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(
              _lastResult.toString(),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(title),
      subtitle: Text(value),
    );
  }
}
