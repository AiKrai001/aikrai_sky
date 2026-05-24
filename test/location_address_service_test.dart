import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'package:aikrai_sky/services/location_address_service.dart';

void main() {
  const service = LocationAddressService();

  test(
    'buildAddressRecord keeps Chinese city and district in correct fields',
    () {
      final record = service.buildAddressRecord(
        _position(latitude: 34.17869, longitude: 108.8943),
        const Placemark(
          isoCountryCode: 'CN',
          country: '中国',
          administrativeArea: '陕西省',
          subAdministrativeArea: '西安市',
          locality: '雁塔区',
          subLocality: '小寨路街道',
          thoroughfare: '长安南路',
        ),
      );

      expect(record.province, '陕西省');
      expect(record.city, '西安市');
      expect(record.district, '雁塔区');
    },
  );

  test('buildAddressRecord supports non-China placemark fields', () {
    final record = service.buildAddressRecord(
      _position(latitude: 37.75986, longitude: -122.4148),
      const Placemark(
        isoCountryCode: 'US',
        country: 'United States',
        administrativeArea: 'California',
        subAdministrativeArea: 'San Francisco County',
        locality: 'San Francisco',
        subLocality: 'Mission District',
        thoroughfare: 'Valencia Street',
      ),
    );

    expect(record.province, 'California');
    expect(record.city, 'San Francisco');
    expect(record.district, 'Mission District');
    expect(record.detailAddress, contains('United States'));
    expect(record.detailAddress, contains('Mission District'));
  });
}

Position _position({required double latitude, required double longitude}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime(2026, 5, 24, 10),
    accuracy: 1,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}
