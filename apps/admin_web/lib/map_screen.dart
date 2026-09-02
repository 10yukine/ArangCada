import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'admin_controller.dart';
import 'models.dart';
import 'session.dart';
import 'theme.dart';
import 'widgets.dart';

@visibleForTesting
const dashboardMapGesturesEnabled = true;

class LiveMapScreen extends ConsumerStatefulWidget {
  const LiveMapScreen({super.key});
  @override
  ConsumerState<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends ConsumerState<LiveMapScreen> {
  static const mapTilerKey = String.fromEnvironment('MAPTILER_KEY');
  static const boundarySource = 'toda-boundaries';
  static const rideSource = 'active-rides';
  static const osmStyle = '''{
    "version": 8,
    "sources": {
      "osm": {
        "type": "raster",
        "tiles": ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
        "tileSize": 256,
        "maxzoom": 19,
        "attribution": "© OpenStreetMap contributors"
      }
    },
    "layers": [{"id": "osm", "type": "raster", "source": "osm"}]
  }''';
  MapLibreMapController? mapController;
  bool styleReady = false;
  String filter = 'All rides';
  String? mapError;

  static String get mapStyle => mapTilerKey.isEmpty
      ? osmStyle
      : 'https://api.maptiler.com/maps/streets-v2/style.json?key=$mapTilerKey';

  String get styleUrl => mapStyle;

  List<Ride> get scopedRides {
    final rides = ref.read(adminProvider.notifier).visibleRides(auth.value!);
    return filter == 'All rides'
        ? rides
        : rides.where((ride) => ride.status == filter).toList();
  }

  List<Driver> get onlineDrivers => ref
      .read(adminProvider.notifier)
      .scopedDrivers(auth.value!)
      .where(
        (driver) =>
            driver.online &&
            driver.latitude != null &&
            driver.longitude != null,
      )
      .toList();

  Map<String, dynamic> boundaryGeoJson(AdminState state) => {
    'type': 'FeatureCollection',
    'features': [
      for (final boundary in state.boundaries)
        if (auth.value?.role == AdminRole.lgu ||
            boundary.name == auth.value?.toda)
          {
            'type': 'Feature',
            'id': boundary.name,
            'properties': {
              'name': boundary.name,
              'color': '#${boundary.color.toRadixString(16).substring(2)}',
            },
            'geometry': {
              'type': 'Polygon',
              'coordinates': [boundary.coordinates],
            },
          },
    ],
  };

  Map<String, dynamic> rideGeoJson(String? selected) => {
    'type': 'FeatureCollection',
    'features': [
      for (final ride in scopedRides)
        {
          'type': 'Feature',
          'id': ride.id,
          'properties': {
            'id': ride.id,
            'selected': ride.id == selected,
            'status': ride.status,
            'kind': 'ride',
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [ride.longitude, ride.latitude],
          },
        },
      for (final driver in onlineDrivers)
        if (!scopedRides.any((ride) => ride.driverId == driver.id))
          {
            'type': 'Feature',
            'id': 'driver:${driver.id}',
            'properties': {
              'id': 'driver:${driver.id}',
              'selected': false,
              'status': 'Available',
              'kind': 'driver',
            },
            'geometry': {
              'type': 'Point',
              'coordinates': [driver.longitude, driver.latitude],
            },
          },
    ],
  };

  Future<void> loadLayers() async {
    final controller = mapController;
    if (controller == null) return;
    try {
      final state = ref.read(adminProvider);
      await controller.addGeoJsonSource(
        boundarySource,
        boundaryGeoJson(state),
        promoteId: 'name',
      );
      await controller.addFillLayer(
        boundarySource,
        'toda-fill',
        const FillLayerProperties(
          fillColor: ['get', 'color'],
          fillOpacity: .18,
          fillOutlineColor: ['get', 'color'],
        ),
        enableInteraction: true,
      );
      await controller.addGeoJsonSource(
        rideSource,
        rideGeoJson(state.selectedRide),
        promoteId: 'id',
      );
      await controller.addCircleLayer(
        rideSource,
        'ride-circles',
        const CircleLayerProperties(
          circleRadius: [
            'case',
            ['get', 'selected'],
            13,
            9,
          ],
          circleColor: [
            'case',
            ['get', 'selected'],
            '#1262D0',
            [
              '==',
              ['get', 'kind'],
              'driver',
            ],
            '#16795C',
            '#0F1A28',
          ],
          circleStrokeWidth: 3,
          circleStrokeColor: '#FFFFFF',
        ),
        enableInteraction: true,
      );
      controller.onFeatureTapped.add((
        point,
        coordinates,
        id,
        layerId,
        annotation,
      ) {
        if (layerId == 'ride-circles' && !id.startsWith('driver:')) {
          selectRide(id);
        }
      });
      if (mounted) {
        setState(() {
          styleReady = true;
          mapError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => mapError =
              'The map loaded, but its prototype layers could not be drawn.',
        );
      }
    }
  }

  Future<void> syncRides() async {
    if (!styleReady || mapController == null) return;
    await mapController!.setGeoJsonSource(
      rideSource,
      rideGeoJson(ref.read(adminProvider).selectedRide),
    );
  }

  Future<void> selectRide(String id) async {
    ref.read(adminProvider.notifier).selectRide(id);
    await syncRides();
    final ride = ref
        .read(adminProvider)
        .rides
        .firstWhere((item) => item.id == id);
    await mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(ride.latitude, ride.longitude), 14.5),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminProvider);
    ref.listen(
      adminProvider.select((value) => value.selectedRide),
      (_, _) => syncRides(),
    );
    ref.listen(
      adminProvider.select((value) => value.rides),
      (_, _) => syncRides(),
    );
    ref.listen(
      adminProvider.select((value) => value.drivers),
      (_, _) => syncRides(),
    );
    final liveDrivers = onlineDrivers;
    final centerLatitude =
        scopedRides.firstOrNull?.latitude ??
        liveDrivers.firstOrNull?.latitude ??
        14.2094;
    final centerLongitude =
        scopedRides.firstOrNull?.longitude ??
        liveDrivers.firstOrNull?.longitude ??
        121.1647;
    final selected = state.selectedRide == null
        ? null
        : scopedRides
              .where((ride) => ride.id == state.selectedRide)
              .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          title: 'Live dispatch map',
          subtitle: state.connected
              ? 'Inspect live commuter requests, driver GPS, and server-scoped TODA jurisdictions.'
              : 'Inspect synthetic ride positions and evaluation-only TODA overlays.',
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: AdminColors.warningTint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AdminColors.warning.withValues(alpha: .25),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: AdminColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  state.connected
                      ? 'TODA boundaries are read-only server records. The SJVTODA developer-test polygon is provisional; only trusted server dispatch determines ride eligibility.'
                      : 'Prototype boundary · evaluation only. These polygons are not authoritative and must never determine ride eligibility.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final stack = constraints.maxWidth < 980;
            final map = Panel(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: stack ? 500 : 650,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Semantics(
                          label: state.connected
                              ? 'Interactive MapLibre dispatch map with ${scopedRides.length} visible live rides'
                              : 'Interactive MapLibre dispatch map with ${scopedRides.length} visible simulated rides',
                          child: MapLibreMap(
                            styleString: styleUrl,
                            initialCameraPosition: CameraPosition(
                              target: LatLng(centerLatitude, centerLongitude),
                              zoom: 13.2,
                            ),
                            onMapCreated: (controller) =>
                                mapController = controller,
                            onStyleLoadedCallback: loadLayers,
                            compassEnabled: true,
                            rotateGesturesEnabled: true,
                            tiltGesturesEnabled: false,
                            minMaxZoomPreference: const MinMaxZoomPreference(
                              10,
                              18,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 14,
                        left: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(99),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x22000000),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration: const BoxDecoration(
                                  color: AdminColors.success,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                styleReady ? 'Map connected' : 'Loading map…',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (mapError != null)
                        Positioned(
                          left: 14,
                          right: 14,
                          bottom: 14,
                          child: Material(
                            color: AdminColors.dangerTint,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber,
                                    color: AdminColors.danger,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(mapError!)),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
            final side = SizedBox(
              width: stack ? double.infinity : 340,
              child: Column(
                children: [
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Active rides',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const Spacer(),
                            StatusPill(
                              '${scopedRides.length} visible',
                              tone: StatusTone.brand,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: filter,
                          decoration: const InputDecoration(
                            labelText: 'Filter map',
                          ),
                          items: [
                            for (final item in const [
                              'All rides',
                              'En route',
                              'Arriving',
                              'On trip',
                            ])
                              DropdownMenuItem(value: item, child: Text(item)),
                          ],
                          onChanged: (value) {
                            setState(() => filter = value!);
                            if (state.selectedRide != null &&
                                !scopedRides.any(
                                  (ride) => ride.id == state.selectedRide,
                                )) {
                              ref.read(adminProvider.notifier).selectRide(null);
                            } else {
                              syncRides();
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        for (final ride in scopedRides)
                          _RideCard(
                            ride: ride,
                            selected: ride.id == state.selectedRide,
                            onTap: () => selectRide(ride.id),
                          ),
                      ],
                    ),
                  ),
                  if (selected != null) ...[
                    const SizedBox(height: 14),
                    Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  selected.id,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              StatusPill(
                                selected.status,
                                tone: StatusTone.success,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _MapDetailRow(Icons.badge_outlined, selected.driver),
                          _MapDetailRow(Icons.person_outline, selected.rider),
                          _MapDetailRow(Icons.groups_outlined, selected.toda),
                          _MapDetailRow(
                            Icons.update,
                            'Updated ${selected.updatedMinutes} min ago',
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () {
                              ref.read(adminProvider.notifier).selectRide(null);
                              syncRides();
                            },
                            icon: const Icon(Icons.close),
                            label: const Text('Clear selection'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Online drivers',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            StatusPill(
                              '${liveDrivers.length} sharing GPS',
                              tone: StatusTone.success,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (liveDrivers.isEmpty)
                          const Text(
                            'No online drivers are currently sharing a location.',
                          )
                        else
                          for (final driver in liveDrivers)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.electric_rickshaw,
                                color: AdminColors.success,
                              ),
                              title: Text(driver.name),
                              subtitle: Text(driver.toda),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            );
            return stack
                ? Column(children: [map, const SizedBox(height: 14), side])
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: map),
                      const SizedBox(width: 16),
                      side,
                    ],
                  );
          },
        ),
      ],
    );
  }
}

class DashboardMapPreview extends StatefulWidget {
  const DashboardMapPreview({
    super.key,
    required this.rides,
    this.connected = false,
  });

  final List<Ride> rides;
  final bool connected;

  @override
  State<DashboardMapPreview> createState() => _DashboardMapPreviewState();
}

class _DashboardMapPreviewState extends State<DashboardMapPreview> {
  static const source = 'dashboard-active-rides';
  MapLibreMapController? controller;
  bool sourceReady = false;
  bool failed = false;

  Map<String, dynamic> get rideGeoJson => {
    'type': 'FeatureCollection',
    'features': [
      for (final ride in widget.rides)
        {
          'type': 'Feature',
          'id': ride.id,
          'properties': {'id': ride.id},
          'geometry': {
            'type': 'Point',
            'coordinates': [ride.longitude, ride.latitude],
          },
        },
    ],
  };

  @override
  void didUpdateWidget(DashboardMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.rides, widget.rides)) syncRides();
  }

  Future<void> loadRides() async {
    final map = controller;
    if (map == null) return;
    try {
      await map.addGeoJsonSource(source, rideGeoJson, promoteId: 'id');
      await map.addCircleLayer(
        source,
        'dashboard-ride-circles',
        const CircleLayerProperties(
          circleRadius: 8,
          circleColor: '#1262D0',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
        ),
      );
      if (!mounted) return;
      sourceReady = true;
      await syncRides();
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  Future<void> syncRides() async {
    final map = controller;
    if (!sourceReady || map == null) return;
    try {
      await map.setGeoJsonSource(source, rideGeoJson);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.connected
        ? 'Interactive dispatch map with ${widget.rides.length} live rides'
        : 'Interactive dispatch map with ${widget.rides.length} simulated rides';
    if (!kIsWeb || failed) {
      return ColoredBox(
        color: AdminColors.surface,
        child: Center(
          child: Semantics(
            label: label,
            child: Icon(
              failed ? Icons.map_outlined : Icons.location_on_outlined,
              color: AdminColors.primary,
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: label,
      child: MapLibreMap(
        styleString: _LiveMapScreenState.mapStyle,
        initialCameraPosition: const CameraPosition(
          target: LatLng(14.2094, 121.1647),
          zoom: 12.7,
        ),
        onMapCreated: (map) => controller = map,
        onStyleLoadedCallback: loadRides,
        compassEnabled: false,
        rotateGesturesEnabled: false,
        tiltGesturesEnabled: false,
        dragEnabled: dashboardMapGesturesEnabled,
        scrollGesturesEnabled: dashboardMapGesturesEnabled,
        zoomGesturesEnabled: dashboardMapGesturesEnabled,
      ),
    );
  }
}

class _RideCard extends StatelessWidget {
  const _RideCard({
    required this.ride,
    required this.selected,
    required this.onTap,
  });
  final Ride ride;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: '${ride.id}, ${ride.driver}, ${ride.status}',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AdminColors.primaryTint : AdminColors.background,
          border: Border.all(
            color: selected ? AdminColors.primary : AdminColors.border,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 39,
              height: 39,
              decoration: BoxDecoration(
                color: selected ? AdminColors.primary : AdminColors.rail,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.electric_rickshaw,
                color: Colors.white,
                size: 21,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ride.driver,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${ride.id} · ${ride.toda}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              '${ride.updatedMinutes}m',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _MapDetailRow extends StatelessWidget {
  const _MapDetailRow(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 19, color: AdminColors.muted),
        const SizedBox(width: 9),
        Expanded(child: Text(label)),
      ],
    ),
  );
}
