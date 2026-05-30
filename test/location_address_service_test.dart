import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'package:aikrai_sky/services/location_address_service.dart';

void main() {
  const service = LocationAddressService();

  test(
    'buildAddressRecord keeps Shanghai Hongkou city and district fields',
    () {
      final record = service.buildAddressRecord(
        _position(latitude: 31.2646, longitude: 121.5051),
        const Placemark(
          isoCountryCode: 'CN',
          country: '中国',
          administrativeArea: '上海市',
          subAdministrativeArea: '上海市',
          locality: '虹口区',
          subLocality: '北外滩街道',
          thoroughfare: '东大名路',
        ),
      );

      expect(record.province, '上海市');
      expect(record.city, '上海市');
      expect(record.district, '虹口区');
      expect(record.sortOrder, -1);
    },
  );

  test('buildAddressRecord keeps Hongkou sub-locality in detail address', () {
    final record = service.buildAddressRecord(
      _position(latitude: 31.2646, longitude: 121.5051),
      const Placemark(
        isoCountryCode: 'CN',
        country: '中国',
        administrativeArea: '上海市',
        subAdministrativeArea: '上海市',
        locality: '虹口区',
        subLocality: '四川北路街道',
        thoroughfare: '四川北路',
      ),
    );

    expect(record.province, '上海市');
    expect(record.city, '上海市');
    expect(record.district, '虹口区');
    expect(record.detailAddress, contains('中国'));
    expect(record.detailAddress, contains('虹口区'));
  });

  test('buildTencentSuggestionAddressRecord maps POI suggestions', () {
    final record = service.buildTencentSuggestionAddressRecord({
      'title': '上海虹口足球场',
      'address': '上海市虹口区东江湾路444号',
      'street': '东江湾路',
      'province': '上海市',
      'city': '上海市',
      'district': '虹口区',
      'location': {'lat': 31.2714, 'lng': 121.4800},
    });

    expect(record, isNotNull);
    expect(record!.province, '上海市');
    expect(record.city, '上海市');
    expect(record.district, '虹口区');
    expect(record.detailAddress, '上海市虹口区东江湾路444号上海虹口足球场');
    expect(record.latitude, 31.2714);
    expect(record.longitude, 121.4800);
  });

  test(
    'buildTencentSuggestionAddressRecord uses title for administrative row',
    () {
      final record = service.buildTencentSuggestionAddressRecord({
        'title': '虹口区',
        'province': '上海市',
        'city': '上海市',
        'lat': 31.2646,
        'lng': 121.5051,
      });

      expect(record, isNotNull);
      expect(record!.province, '上海市');
      expect(record.city, '上海市');
      expect(record.district, '虹口区');
      expect(record.detailAddress, '上海市虹口区');
    },
  );

  test('buildTencentGeocoderAddressRecord maps geocoder fallback', () {
    final record = service.buildTencentGeocoderAddressRecord({
      'status': 0,
      'result': {
        'location': {'lat': 31.25095, 'lng': 121.49228},
        'address': '上海市虹口区东大名路501号',
        'address_components': {
          'province': '上海市',
          'city': '上海市',
          'district': '虹口区',
          'street': '东大名路',
          'street_number': '501号',
        },
      },
    });

    expect(record, isNotNull);
    expect(record!.province, '上海市');
    expect(record.city, '上海市');
    expect(record.district, '虹口区');
    expect(record.detailAddress, contains('东大名路501号'));
    expect(record.latitude, 31.25095);
    expect(record.longitude, 121.49228);
  });

  test('buildTencentGeocoderAddressRecord maps reverse geocoder response', () {
    final record = service.buildTencentGeocoderAddressRecord({
      'status': 0,
      'result': {
        'location': {'lat': 31.25095, 'lng': 121.49228},
        'address': '上海市虹口区东大名路501号',
        'address_component': {
          'nation': '中国',
          'province': '上海市',
          'city': '上海市',
          'district': '虹口区',
          'street': '东大名路',
          'street_number': '501号',
        },
      },
    });

    expect(record, isNotNull);
    expect(record!.province, '上海市');
    expect(record.city, '上海市');
    expect(record.district, '虹口区');
    expect(record.detailAddress, contains('东大名路501号'));
    expect(record.latitude, 31.25095);
    expect(record.longitude, 121.49228);
  });

  test('buildTencentNativeAddressRecord maps Android SDK location', () {
    final record = service.buildTencentNativeAddressRecord({
      'latitude': 31.2646,
      'longitude': 121.5051,
      'nation': '中国',
      'province': '上海市',
      'city': '上海市',
      'district': '虹口区',
      'street': '东大名路',
      'streetNo': '501号',
      'name': '上海白玉兰广场',
      'address': '上海市虹口区东大名路501号',
    });

    expect(record.province, '上海市');
    expect(record.city, '上海市');
    expect(record.district, '虹口区');
    expect(record.detailAddress, contains('东大名路501号'));
    expect(record.latitude, 31.2646);
    expect(record.longitude, 121.5051);
  });

  test(
    'capture mapper rejects Tencent native location without area fields',
    () {
      expect(
        () => service.buildTencentNativeAddressRecord({
          'latitude': 31.2646,
          'longitude': 121.5051,
        }),
        throwsA(isA<LocationAddressException>()),
      );
    },
  );
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
