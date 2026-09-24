import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wind_chimes/location/location.dart';
import 'package:wind_chimes/location/open_meteo_place_search.dart';

void main() {
  const body = '{"results":[{"id":2867714,"name":"Munich","latitude":48.13743,'
      '"longitude":11.57549,"country":"Germany","admin1":"Bavaria"},'
      '{"id":5060556,"name":"Munich","latitude":48.66917,"longitude":-98.83263,'
      '"country":"United States","admin1":"North Dakota"},'
      '{"id":3143244,"name":"Oslo","latitude":59.91273,"longitude":10.74609,'
      '"country":"Norway","admin1":"Oslo"},'
      '{"id":1,"name":"Nowhere"}],"generationtime_ms":0.4}';

  test('finds places, telling same-named ones apart', () async {
    final search = OpenMeteoPlaceSearch(MockClient((request) async {
      expect(request.url.host, 'geocoding-api.open-meteo.com');
      expect(request.url.queryParameters['name'], 'Munich');
      return http.Response(body, 200);
    }));
    final places = await search.search(' Munich ');
    expect(places.map((p) => '$p'), [
      'Munich, Bavaria, Germany',
      'Munich, North Dakota, United States',
      'Oslo, Norway',
    ]);
    expect(places.first.coordinates, const Coordinates(48.13743, 11.57549));
  });

  test('no results is an empty list, a failure is an error', () async {
    final empty = OpenMeteoPlaceSearch(MockClient((_) async => http.Response('{}', 200)));
    expect(await empty.search('Xyzzy'), isEmpty);
    expect(await empty.search('X'), isEmpty, reason: 'too short to search');
    final down = OpenMeteoPlaceSearch(MockClient((_) async => http.Response('', 503)));
    await expectLater(down.search('Munich'), throwsA(isA<http.ClientException>()));
  });

  test('place choices survive a round trip through JSON', () {
    const place = Place(name: 'Munich', detail: 'Bavaria, Germany', coordinates: Coordinates(48.14, 11.58));
    expect(LocationChoice.fromJson(place.toJson()), place);
    expect(LocationChoice.fromJson(const DeviceLocation().toJson()), const DeviceLocation());
    expect(place.key, 'place:48.14, 11.58');
    expect(const Coordinates(48.13743, 11.57549).rounded, const Coordinates(48.14, 11.58));
  });
}
