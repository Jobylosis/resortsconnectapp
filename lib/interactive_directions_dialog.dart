import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'theme.dart';

class InteractiveDirectionsDialog extends StatefulWidget {
  final Map initialProperty;
  final List<Map<String, dynamic>> allProperties;

  const InteractiveDirectionsDialog({
    super.key,
    required this.initialProperty,
    this.allProperties = const [],
  });

  @override
  State<InteractiveDirectionsDialog> createState() => _InteractiveDirectionsDialogState();
}

class _InteractiveDirectionsDialogState extends State<InteractiveDirectionsDialog> {
  late Map _activeDestination;
  List<Map<String, dynamic>> _destinations = [];
  
  // User start pin
  LatLng _userLocation = const LatLng(14.2790, 121.4150); // Default to Santa Cruz Laguna
  String _userLocationLabel = "Laguna Town Center (Tap map to change pin)";
  
  // Route state
  List<LatLng> _routePoints = [];
  double? _distanceKm;
  int? _durationMinutes;
  bool _isLoadingRoute = false;
  String? _routeError;
  bool _isSatellite = false; // Toggle between OpenStreetMap standard and Satellite tiles

  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _activeDestination = widget.initialProperty;

    // Filter valid resort destinations
    final list = widget.allProperties.isNotEmpty 
        ? widget.allProperties 
        : [Map<String, dynamic>.from(widget.initialProperty)];
    
    _destinations = list.where((p) {
      final lat = double.tryParse(p['latitude']?.toString() ?? '');
      final lng = double.tryParse(p['longitude']?.toString() ?? '');
      return lat != null && lng != null && (lat != 0 || lng != 0);
    }).toList();

    if (_destinations.isEmpty) {
      _destinations = [Map<String, dynamic>.from(widget.initialProperty)];
    }

    _fetchRoute();
  }

  Future<void> _fetchRoute() async {
    final destLat = double.tryParse(_activeDestination['latitude']?.toString() ?? '');
    final destLng = double.tryParse(_activeDestination['longitude']?.toString() ?? '');
    if (destLat == null || destLng == null) return;

    setState(() {
      _isLoadingRoute = true;
      _routeError = null;
    });

    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/${_userLocation.longitude},${_userLocation.latitude};$destLng,$destLat?overview=full&geometries=geojson',
    );

    try {
      final response = await http.get(url, headers: {'User-Agent': 'ResortsConnectApp/1.0'}).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final coords = (route['geometry']['coordinates'] as List);
          final points = coords.map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
          
          final distanceM = (route['distance'] as num).toDouble();
          final durationS = (route['duration'] as num).toDouble();

          if (mounted) {
            setState(() {
              _routePoints = points;
              _distanceKm = double.parse((distanceM / 1000).toStringAsFixed(1));
              _durationMinutes = (durationS / 60).round();
              _isLoadingRoute = false;
            });
            _fitBounds();
          }
          return;
        }
      }
      throw Exception('Route not found');
    } catch (e) {
      if (mounted) {
        final constDist = const Distance();
        final destLatLng = LatLng(destLat, destLng);
        final distM = constDist.as(LengthUnit.Meter, _userLocation, destLatLng);
        setState(() {
          _routePoints = [_userLocation, destLatLng];
          _distanceKm = double.parse((distM / 1000).toStringAsFixed(1));
          _durationMinutes = ((_distanceKm! / 40) * 60).round();
          _routeError = "Direct path shown";
          _isLoadingRoute = false;
        });
        _fitBounds();
      }
    }
  }

  void _fitBounds() {
    final destLat = double.tryParse(_activeDestination['latitude']?.toString() ?? '');
    final destLng = double.tryParse(_activeDestination['longitude']?.toString() ?? '');
    if (destLat == null || destLng == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final bounds = LatLngBounds.fromPoints([
          _userLocation,
          LatLng(destLat, destLng),
        ]);
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(40),
          ),
        );
      } catch (_) {}
    });
  }

  String _formatDuration(int? mins) {
    if (mins == null) return "Calculating...";
    if (mins < 60) return "$mins mins";
    final h = mins ~/ 60;
    final m = mins % 60;
    return m > 0 ? "$h hr $m mins" : "$h hr";
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final destLat = double.tryParse(_activeDestination['latitude']?.toString() ?? '') ?? 14.2690;
    final destLng = double.tryParse(_activeDestination['longitude']?.toString() ?? '') ?? 121.4588;
    final destPos = LatLng(destLat, destLng);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Column(
          children: [
            // Modal Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200)),
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF1DD3B0), Color(0xFF00887A)]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.explore_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Live Route & Directions",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          "Tap anywhere to set your starting location pin",
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _isSatellite ? 'Switch to Street Map' : 'Switch to Satellite View',
                    icon: Icon(
                      _isSatellite ? Icons.map_outlined : Icons.satellite_alt_outlined,
                      color: AppTheme.primaryAccent,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _isSatellite = !_isSatellite),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.black54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Resort Destination Switcher
            if (_destinations.length > 1)
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                color: isDark ? const Color(0xFF141E30) : const Color(0xFFF1F5F9),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _destinations.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final dest = _destinations[idx];
                    final isSelected = dest['name'] == _activeDestination['name'];
                    return ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 8,
                            backgroundColor: isSelected ? Colors.white : AppTheme.primaryAccent,
                            child: Text(
                              "${idx + 1}",
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? AppTheme.primaryAccent : Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(dest['name'] ?? 'Resort ${idx + 1}', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      selected: isSelected,
                      selectedColor: AppTheme.primaryAccent,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (val) {
                        if (val) {
                          setState(() => _activeDestination = dest);
                          _fetchRoute();
                        }
                      },
                    );
                  },
                ),
              ),

            // Real-Time Route Stats Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200)),
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Travel Time
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined, color: AppTheme.primaryAccent, size: 20),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("EST. TIME", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                          Text(
                            _isLoadingRoute ? "Calculating..." : _formatDuration(_durationMinutes),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(height: 24, width: 1, color: isDark ? Colors.white12 : Colors.grey.shade300),
                  // Distance
                  Row(
                    children: [
                      const Icon(Icons.alt_route, color: AppTheme.secondaryAccent, size: 20),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("DISTANCE", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                          Text(
                            _isLoadingRoute ? "..." : (_distanceKm != null ? "$_distanceKm km" : "—"),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(height: 24, width: 1, color: isDark ? Colors.white12 : Colors.grey.shade300),
                  // Destination Pin Name
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("DESTINATION", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                          Text(
                            _activeDestination['name'] ?? 'Resort',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.redAccent),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Full Map with Tappable Pinning & Route Polyline
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: destPos,
                      initialZoom: 13.0,
                      onTap: (tapPosition, point) {
                        setState(() {
                          _userLocation = point;
                          _userLocationLabel = "Pinned Starting Point";
                        });
                        _fetchRoute();
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: _isSatellite 
                            ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                            : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.resortsconnectapp',
                      ),
                      // Road Path Route Polyline
                      if (_routePoints.isNotEmpty)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _routePoints,
                              strokeWidth: 5.0,
                              color: const Color(0xFF3B82F6),
                            ),
                          ],
                        ),
                      // Markers
                      MarkerLayer(
                        markers: [
                          // User Starting Point Marker
                          Marker(
                            point: _userLocation,
                            width: 44,
                            height: 44,
                            child: const Icon(
                              Icons.my_location,
                              color: Color(0xFF3B82F6),
                              size: 38,
                            ),
                          ),
                          // Resort Destination Markers
                          ..._destinations.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final dest = entry.value;
                            final dLat = double.tryParse(dest['latitude']?.toString() ?? '') ?? 0.0;
                            final dLng = double.tryParse(dest['longitude']?.toString() ?? '') ?? 0.0;
                            final isSel = dest['name'] == _activeDestination['name'];

                            return Marker(
                              point: LatLng(dLat, dLng),
                              width: 42,
                              height: 42,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() => _activeDestination = dest);
                                  _fetchRoute();
                                },
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: isSel ? Colors.red : AppTheme.primaryAccent,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4),
                                        ],
                                      ),
                                      child: Text(
                                        "${idx + 1}",
                                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    Icon(
                                      Icons.location_on,
                                      color: isSel ? Colors.red : AppTheme.primaryAccent,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ],
                  ),

                  // Pin Placement Prompt
                  Positioned(
                    top: 10,
                    left: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.touch_app, color: Color(0xFF1DD3B0), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "📍 Start: $_userLocationLabel",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Route Loading Spinner
                  if (_isLoadingRoute)
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6)],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text("Calculating road route...", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200)),
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _routeError != null 
                        ? "Notice: $_routeError (${destLat.toStringAsFixed(4)}, ${destLng.toStringAsFixed(4)})"
                        : "Destination: ${destLat.toStringAsFixed(4)}, ${destLng.toStringAsFixed(4)}",
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Done", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
