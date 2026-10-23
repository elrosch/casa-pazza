import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../settings/settings_screen.dart' show sourceCodeUrl;

/// A product found in Open Food Facts (https://world.openfoodfacts.org).
@immutable
class ProductInfo {
  const ProductInfo({
    required this.barcode,
    required this.name,
    this.brand = '',
    this.packageSize = '',
  });

  final String barcode;
  final String name;
  final String brand;

  /// E.g. "450 g" or "1 l", as printed on the package.
  final String packageSize;

  /// Name for the shopping list, e.g. "Weihenstephan H-Milch 1,5 %".
  String get suggestedName {
    if (brand.isEmpty || name.toLowerCase().contains(brand.toLowerCase())) {
      return name;
    }
    return '$brand $name';
  }
}

/// Barcodes Open Food Facts can know: EAN-8, UPC-A, EAN-13 and GTIN-14.
bool isProductBarcode(String code) => RegExp(r'^\d{8,14}$').hasMatch(code);

/// Extracts a [ProductInfo] from an API v2 response, preferring German names.
/// Returns null when the product is unknown or has no usable name.
@visibleForTesting
ProductInfo? parseProductResponse(String barcode, Map<String, dynamic> json) {
  final product = json['product'];
  if (json['status'] != 1 || product is! Map<String, dynamic>) return null;

  String field(String key) => (product[key] as String? ?? '').trim();
  final name = [
    field('product_name_de'),
    field('product_name'),
    field('generic_name_de'),
  ].firstWhere((n) => n.isNotEmpty, orElse: () => '');
  if (name.isEmpty) return null;

  return ProductInfo(
    barcode: barcode,
    name: name,
    // "brands" is a comma separated list; the first one is the main brand.
    brand: field('brands').split(',').first.trim(),
    packageSize: field('quantity'),
  );
}

/// Thrown when Open Food Facts cannot be reached.
class ProductLookupException implements Exception {
  const ProductLookupException(this.message);

  final String message;

  @override
  String toString() => 'ProductLookupException: $message';
}

final productLookupProvider = Provider<ProductLookup>((ref) {
  final lookup = ProductLookup(http.Client());
  ref.onDispose(lookup.close);
  return lookup;
});

/// Looks up products by barcode in the Open Food Facts database.
class ProductLookup {
  ProductLookup(this._client, {Uri? baseUrl})
    : _baseUrl = baseUrl ?? Uri.parse('https://world.openfoodfacts.org');

  final http.Client _client;
  final Uri _baseUrl;

  // Open Food Facts asks apps to identify themselves with name and contact.
  static const _userAgent = 'CasaPazza/1.0 ($sourceCodeUrl)';
  static const _fields =
      'code,product_name,product_name_de,generic_name_de,brands,quantity';

  /// Returns the product, null if Open Food Facts does not know it.
  /// Throws [ProductLookupException] when the service is unreachable.
  Future<ProductInfo?> lookup(String barcode) async {
    final uri = _baseUrl.replace(
      path: '/api/v2/product/$barcode',
      queryParameters: {'fields': _fields},
    );
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      throw ProductLookupException('$e');
    }
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw ProductLookupException('HTTP ${response.statusCode}');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map<String, dynamic>) return null;
    return parseProductResponse(barcode, json);
  }

  void close() => _client.close();
}
