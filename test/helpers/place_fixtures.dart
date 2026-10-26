/// A little of CAOP and of the place names, around Coimbra and Arganil.
library;

import 'dart:typed_data';

import 'package:terrenos/core/caop/admin_boundaries.dart';
import 'package:terrenos/core/places/places.dart';

Freguesia _freguesia(String code, String name, String shortName, List<int> b) =>
    Freguesia(
      code: code,
      name: name,
      shortName: shortName,
      bounds: Int32List.fromList(b),
      arcs: Int32List(0),
    );

/// Two concelhos in one distrito, with one freguesia each.
final testCaop = AdminBoundaries(
  edition: caopEdition,
  distritos: const {'06': AdminArea('06', 'Coimbra')},
  concelhos: const {
    '0601': AdminArea('0601', 'Arganil'),
    '0603': AdminArea('0603', 'Coimbra'),
  },
  freguesias: [
    _freguesia('060111', 'Piódão', 'Piódão', [
      -790000,
      4015000,
      -775000,
      4030000,
    ]),
    _freguesia(
      '060334',
      'União das freguesias de Coimbra (Sé Nova, Santa Cruz, Almedina e '
          'São Bartolomeu)',
      'Coimbra (Sé Nova, Santa Cruz, Almedina e São Bartolomeu)',
      [-845000, 4019000, -840000, 4023000],
    ),
  ],
  levels: const [],
  arcs: const [],
);

Place _place(String name, PlaceKind kind, String freguesia, int x, int y) =>
    Place(name: name, kind: kind, x: x, y: y, freguesia: freguesia);

/// "Malhadapiodao" sits exactly on Piódão, so their labels collide.
final testPlaces = Places(
  osmTimestamp: '2026-10-26T20:16:01Z',
  places: [
    _place('Coimbra', PlaceKind.city, '060334', -842915, 4021119),
    _place(
      'Vila Nova de Coimbrões',
      PlaceKind.village,
      '060334',
      -841000,
      4022000,
    ),
    _place('Piódão', PlaceKind.village, '060111', -782476, 4022955),
    _place('Foz de Piódão', PlaceKind.hamlet, '060111', -783000, 4023500),
    _place('Chãs de Piódão', PlaceKind.hamlet, '060111', -782000, 4022000),
    _place('Malhadapiodao', PlaceKind.hamlet, '060111', -782476, 4022955),
  ],
);
