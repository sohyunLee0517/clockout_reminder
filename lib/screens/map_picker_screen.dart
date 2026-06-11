import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/permission_service.dart';

/// 지도에서 회사 위치를 탭으로 지정하는 화면.
/// 확인 시 선택한 [LatLng] 를 반환한다.
class MapPickerScreen extends StatefulWidget {
  final LatLng initial;
  final double radiusMeters;

  const MapPickerScreen({
    super.key,
    required this.initial,
    required this.radiusMeters,
  });

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _mapController = MapController();
  late LatLng _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  Future<void> _moveToCurrentLocation() async {
    final result = await PermissionService.instance.ensureLocationPermission();
    if (!result.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
      }
      return;
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    final here = LatLng(pos.latitude, pos.longitude);
    setState(() => _selected = here);
    _mapController.move(here, 17);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('회사 위치 지정'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_selected),
            child: const Text('확인'),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.initial,
              initialZoom: 16,
              onTap: (tapPosition, point) =>
                  setState(() => _selected = point),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.isohyeon.clockout_reminder',
              ),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _selected,
                    radius: widget.radiusMeters,
                    useRadiusInMeter: true,
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    borderColor: theme.colorScheme.primary,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _selected,
                    width: 44,
                    height: 44,
                    alignment: Alignment.topCenter,
                    child: Icon(
                      Icons.location_on,
                      size: 44,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.touch_app),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '지도를 탭해 회사 위치를 지정하세요.\n'
                        '위도 ${_selected.latitude.toStringAsFixed(6)}, '
                        '경도 ${_selected.longitude.toStringAsFixed(6)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _moveToCurrentLocation,
        tooltip: '현재 위치로',
        child: const Icon(Icons.my_location),
      ),
    );
  }
}
