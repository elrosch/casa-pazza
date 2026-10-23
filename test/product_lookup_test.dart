import 'dart:convert';

import 'package:casa_pazza/src/features/shopping/product_lookup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('parseProductResponse', () {
    test('prefers the German name and adds the brand', () {
      final product = parseProductResponse('4000000000001', {
        'status': 1,
        'product': {
          'product_name': 'UHT milk 1.5%',
          'product_name_de': 'H-Milch 1,5 %',
          'brands': 'Weihenstephan, Müller',
          'quantity': '1 l',
        },
      })!;
      expect(product.name, 'H-Milch 1,5 %');
      expect(product.brand, 'Weihenstephan');
      expect(product.packageSize, '1 l');
      expect(product.suggestedName, 'Weihenstephan H-Milch 1,5 %');
    });

    test('does not repeat a brand that is part of the name', () {
      final product = parseProductResponse('4008400401621', {
        'status': 1,
        'product': {'product_name': 'Nutella', 'brands': 'Nutella'},
      })!;
      expect(product.suggestedName, 'Nutella');
    });

    test('falls back to the generic name', () {
      final product = parseProductResponse('1', {
        'status': 1,
        'product': {'product_name': ' ', 'generic_name_de': 'Nuss-Nugat-Creme'},
      })!;
      expect(product.name, 'Nuss-Nugat-Creme');
    });

    test('unknown or nameless products are null', () {
      expect(parseProductResponse('1', {'status': 0}), isNull);
      expect(
        parseProductResponse('1', {
          'status': 1,
          'product': {'brands': 'X'},
        }),
        isNull,
      );
    });
  });

  test('isProductBarcode', () {
    expect(isProductBarcode('4008400401621'), isTrue);
    expect(isProductBarcode('96385074'), isTrue);
    expect(isProductBarcode('1234'), isFalse);
    expect(isProductBarcode('https://example.com'), isFalse);
  });

  group('ProductLookup', () {
    late List<http.Request> requests;

    ProductLookup lookupWith(http.Response Function(http.Request) handler) {
      requests = [];
      return ProductLookup(
        MockClient((request) async {
          requests.add(request);
          return handler(request);
        }),
      );
    }

    test('queries API v2 with a User-Agent and decodes UTF-8', () async {
      final lookup = lookupWith(
        (_) => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'status': 1,
              'product': {'product_name': 'Spätzle', 'quantity': '500 g'},
            }),
          ),
          200,
        ),
      );
      final product = await lookup.lookup('4000000000002');
      expect(product?.name, 'Spätzle');
      expect(requests.single.url.path, '/api/v2/product/4000000000002');
      expect(requests.single.url.queryParameters['fields'], contains('brands'));
      expect(requests.single.headers['User-Agent'], startsWith('CasaPazza/'));
    });

    test('unknown products return null', () async {
      expect(
        await lookupWith((_) => http.Response('{}', 404)).lookup('1'),
        isNull,
      );
      expect(
        await lookupWith((_) => http.Response('{"status":0}', 200)).lookup('1'),
        isNull,
      );
    });

    test('server and network errors throw', () async {
      expect(
        lookupWith((_) => http.Response('', 503)).lookup('1'),
        throwsA(isA<ProductLookupException>()),
      );
      expect(
        lookupWith((_) => throw http.ClientException('offline')).lookup('1'),
        throwsA(isA<ProductLookupException>()),
      );
    });
  });
}
