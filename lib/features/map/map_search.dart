/// Offline search on the map (MAP-9): the user's properties by name or
/// process number, and places by name. Choosing a result moves the map.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/places/place_search.dart';
import 'package:terrenos/core/properties/property_query.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// The place last chosen in search, marked with a pin until the next
/// search or until the pin is tapped.
final searchPinProvider = NotifierProvider<SearchPinController, LatLng?>(
  SearchPinController.new,
);

class SearchPinController extends Notifier<LatLng?> {
  @override
  LatLng? build() => null;

  // A method rather than a setter, to match the other controllers.
  // ignore: use_setters_to_change_properties
  void place(LatLng? point) => state = point;
}

/// A search result: one of the user's properties or a place.
sealed class MapSearchHit {
  const new();
}

class PropertyHit extends MapSearchHit {
  const new(this.property);

  final PropertyDocument property;
}

class PlaceHit extends MapSearchHit {
  const new(this.place);

  final PlaceResult place;
}

/// The search box over the top of the map. Must be a child of
/// [FlutterMap], whose controller it moves.
class MapSearchBar extends ConsumerWidget {
  const new({super.key});

  /// Zoom for a place shown as a point, by kind.
  static const Map<PlaceResultKind, double> pointZoom = {
    PlaceResultKind.city: 13,
    PlaceResultKind.town: 14,
    PlaceResultKind.village: 15,
    PlaceResultKind.hamlet: 16,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      elevation: 3,
      shape: const StadiumBorder(),
      color: theme.colorScheme.surfaceContainerHigh,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => unawaited(_search(context, ref)),
        child: Semantics(
          button: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.search),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.mapSearchHint,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _search(BuildContext context, WidgetRef ref) async {
    final controller = MapController.of(context);
    final pin = ref.read(searchPinProvider.notifier)..place(null);
    final hit = await showSearch<MapSearchHit?>(
      context: context,
      delegate: _MapSearchDelegate(AppLocalizations.of(context)),
    );
    switch (hit) {
      case null:
        return;
      case PropertyHit(:final property):
        final vertices = property.geometry.current?.vertices ?? const [];
        controller.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([
              for (final v in vertices) LatLng(v.lat, v.lon),
            ]),
            padding: const EdgeInsets.all(48),
            maxZoom: 18,
          ),
        );
      case PlaceHit(:final place):
        if (place.southWest case final southWest?) {
          controller.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds(southWest, place.northEast!),
              padding: const EdgeInsets.all(24),
            ),
          );
        } else {
          controller.move(place.centre, pointZoom[place.kind]!);
          pin.place(place.centre);
        }
    }
  }
}

/// The pin on the place chosen in search; tapping it removes it.
class SearchPinLayer extends ConsumerWidget {
  const new({super.key});

  static const size = 48.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final point = ref.watch(searchPinProvider);
    if (point == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return MarkerLayer(
      rotate: true,
      markers: [
        Marker(
          point: point,
          width: size,
          height: size,
          alignment: Alignment.topCenter,
          child: Semantics(
            label: l10n.mapSearchPin,
            button: true,
            child: GestureDetector(
              onTap: () => ref.read(searchPinProvider.notifier).place(null),
              child: const Icon(
                Icons.location_pin,
                size: size,
                color: Colors.redAccent,
                shadows: [Shadow(blurRadius: 4)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MapSearchDelegate extends SearchDelegate<MapSearchHit?> {
  new(AppLocalizations l10n) : super(searchFieldLabel: l10n.mapSearchHint);

  /// The user's properties shown at most, before the places.
  static const maxProperties = 20;

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: AppLocalizations.of(context).actionClear,
        icon: const Icon(Icons.clear),
        onPressed: () => query = '',
      ),
  ];

  @override
  Widget buildLeading(BuildContext context) => const BackButton();

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) =>
      _Results(query: query, onChosen: (hit) => close(context, hit));
}

class _Results extends ConsumerWidget {
  const new({required this.query, required this.onChosen});

  final String query;
  final ValueChanged<MapSearchHit> onChosen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final q = query.trim();
    if (q.length < PlaceSearch.minQueryLength) {
      return _Message(l10n.mapSearchPrompt);
    }
    final properties = [
      for (final doc
          in ref.watch(propertiesProvider).value ?? const <PropertyDocument>[])
        if (doc.geometry.current?.vertices.isNotEmpty ?? false)
          if (PropertyQuery.matchesSearch(doc, q)) doc,
    ].take(_MapSearchDelegate.maxProperties).toList();
    final search = ref.watch(placeSearchProvider);
    final places = search?.search(q) ?? const <PlaceResult>[];
    if (properties.isEmpty && places.isEmpty) {
      return search == null
          ? const Center(child: CircularProgressIndicator())
          : _Message(l10n.mapSearchNoResults(q));
    }
    final theme = Theme.of(context);
    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
    return ListView(
      children: [
        if (properties.isNotEmpty) header(l10n.mapSearchMyProperties),
        for (final doc in properties)
          ListTile(
            leading: const Icon(Icons.crop_square),
            title: Text(doc.name),
            subtitle: switch (doc.processNumber) {
              final number? => Text(l10n.processNumberShort(number)),
              null => null,
            },
            onTap: () => onChosen(PropertyHit(doc)),
          ),
        if (places.isNotEmpty) header(l10n.mapSearchPlaces),
        for (final place in places)
          ListTile(
            leading: Icon(_icons[place.kind]),
            title: Text(place.name),
            subtitle: Text(
              [
                _kindName(l10n, place.kind),
                if (place.where case final where? when where.isNotEmpty) where,
              ].join(' · '),
            ),
            onTap: () => onChosen(PlaceHit(place)),
          ),
      ],
    );
  }

  static const Map<PlaceResultKind, IconData> _icons = {
    PlaceResultKind.distrito: Icons.map_outlined,
    PlaceResultKind.concelho: Icons.account_balance_outlined,
    PlaceResultKind.freguesia: Icons.holiday_village_outlined,
    PlaceResultKind.city: Icons.location_city,
    PlaceResultKind.town: Icons.location_city,
    PlaceResultKind.village: Icons.home_work_outlined,
    PlaceResultKind.hamlet: Icons.home_outlined,
  };

  static String _kindName(AppLocalizations l10n, PlaceResultKind kind) =>
      switch (kind) {
        PlaceResultKind.distrito => l10n.placeKindDistrito,
        PlaceResultKind.concelho => l10n.placeKindConcelho,
        PlaceResultKind.freguesia => l10n.placeKindFreguesia,
        PlaceResultKind.city => l10n.placeKindCity,
        PlaceResultKind.town => l10n.placeKindTown,
        PlaceResultKind.village => l10n.placeKindVillage,
        PlaceResultKind.hamlet => l10n.placeKindHamlet,
      };
}

class _Message extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyLarge,
    ),
  );
}
