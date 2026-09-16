import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProductiveSyncStatusRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void markLocalStateChanged() {
    state++;
  }
}

final productiveSyncStatusRevisionProvider =
    NotifierProvider<ProductiveSyncStatusRevisionNotifier, int>(
  ProductiveSyncStatusRevisionNotifier.new,
);
