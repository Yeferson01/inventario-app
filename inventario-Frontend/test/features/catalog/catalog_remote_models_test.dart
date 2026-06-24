import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/catalog/data/models/catalog_remote_models.dart';

void main() {
  group('CatalogPullResponse', () {
    test('parses standard RPC response', () {
      final response = CatalogPullResponse.fromRpc({
        'records': [
          {
            'entity_type': 'master_product',
            'payload': {
              'id': 'master-1',
              'name': 'Producto 1',
            },
          },
        ],
        'server_time': '2026-06-23T12:00:00Z',
        'catalog_version': 10,
        'next_page_token': {'offset': 500},
        'has_more': true,
      });

      expect(response.records, hasLength(1));
      expect(response.catalogVersion, equals(10));
      expect(response.nextPageToken, isA<Map<String, dynamic>>());
      expect(response.hasMore, isTrue);
      expect(response.serverTime.toIso8601String(), contains('2026-06-23'));
    });

    test('parses list response as records fallback', () {
      final response = CatalogPullResponse.fromRpc([
        {
          'entity_type': 'global_barcode',
          'payload': {
            'id': 'barcode-1',
          },
        },
      ]);

      expect(response.records, hasLength(1));
      expect(response.hasMore, isFalse);
    });

    test('empty next_page_token does not imply hasMore', () {
      final response = CatalogPullResponse.fromRpc({
        'records': [],
        'server_time': '2026-06-23T12:00:00Z',
        'next_page_token': {},
      });

      expect(response.nextPageToken, isNull);
      expect(response.hasMore, isFalse);
    });
  });

  group('CatalogPullRequest', () {
    test('creates RPC params matching real backend function signature', () {
      final request = CatalogPullRequest(
        businessId: 'business-1',
        sinceUpdatedAt: DateTime.parse('2026-06-23T12:00:00Z'),
        pageToken: {'offset': 500},
        limit: 250,
        includeDeleted: false,
      );

      final params = request.toRpcParams();

      expect(params['p_business_id'], equals('business-1'));
      expect(params['p_since_updated_at'], isA<String>());
      expect(params['p_limit'], equals(250));
      expect(params['p_page_token'], isA<Map<String, dynamic>>());
      expect(params['p_include_deleted'], isFalse);

      expect(params.containsKey('p_since_catalog_version'), isFalse);
    });

    test('uses empty json object as default page token', () {
      const request = CatalogPullRequest(
        businessId: 'business-1',
      );

      final params = request.toRpcParams();

      expect(params['p_page_token'], equals(<String, dynamic>{}));
      expect(params['p_limit'], equals(1000));
      expect(params['p_include_deleted'], isFalse);
    });
  });
}
