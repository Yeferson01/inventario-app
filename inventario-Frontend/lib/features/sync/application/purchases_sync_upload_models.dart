import '../data/models/catalog_upload_models.dart';
import 'purchase_product_dependency_resolver.dart';

class PurchasesSyncUploadRunResult extends CatalogUploadRunResult {
  const PurchasesSyncUploadRunResult({
    required super.batchesChecked,
    required super.batchesUploaded,
    required super.batchesCompleted,
    required super.batchesPartial,
    required super.batchesFailed,
    required super.mutationsUploaded,
    required this.batchesWaitingForDependencies,
    required this.batchesBlockedByDependencies,
    this.waitingProductIds = const [],
    this.blockedProductIds = const [],
    this.dependencyIssues = const [],
  });

  final int batchesWaitingForDependencies;
  final int batchesBlockedByDependencies;
  final List<String> waitingProductIds;
  final List<String> blockedProductIds;
  final List<PurchaseProductDependencyIssue> dependencyIssues;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'batches_waiting_for_dependencies': batchesWaitingForDependencies,
      'batches_blocked_by_dependencies': batchesBlockedByDependencies,
      'waiting_product_ids': waitingProductIds,
      'blocked_product_ids': blockedProductIds,
      'dependency_issues': dependencyIssues
          .map((issue) => issue.toJson())
          .toList(growable: false),
    };
  }
}
