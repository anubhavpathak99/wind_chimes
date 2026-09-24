import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'location.dart';

/// City search through Open-Meteo's free geocoding API.
class OpenMeteoPlaceSearch implements PlaceSearch {
  OpenMeteoPlaceSearch(this._client, {this.timeout = const Duration(seconds: 8)});

  static const maxResults = 6;

  final http.Client _client;
  final Duration timeout;

  static Uri uriFor(String query) => Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': query.trim(),
        'count': '$maxResults',
        'language': 'en',
        'format': 'json',
      });

  /// Throws on network failure, so the caller can tell "offline" from "nothing found".
  @override
  Future<List<Place>> search(String query) async {
    if (query.trim().length < 2) return const [];
    final response = await _client.get(uriFor(query)).timeout(timeout);
    if (response.statusCode != 200) throw http.ClientException('HTTP ${response.statusCode}');
    return parse(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static List<Place> parse(Map<String, dynamic> json) {
    final results = json['results'] as List<dynamic>? ?? const [];
    return [
      for (final r in results.cast<Map<String, dynamic>>())
        if (r['latitude'] is num && r['longitude'] is num && r['name'] is String)
          Place(
            name: r['name'] as String,
            detail: [r['admin1'], r['country']]
                .whereType<String>()
                .where((part) => part != r['name'])
                .join(', '),
            coordinates: Coordinates(
              (r['latitude'] as num).toDouble(),
              (r['longitude'] as num).toDouble(),
            ),
          ),
    ];
  }
}
