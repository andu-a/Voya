import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'services/auth_service.dart';

class HotelMapPage extends StatefulWidget {
  const HotelMapPage({super.key});

  @override
  State<HotelMapPage> createState() => HotelMapPageState();
}

class PlaceSuggestion {
  final String placeId;
  final String description;
  const PlaceSuggestion({required this.placeId, required this.description});
}

class HotelMapPageState extends State<HotelMapPage> {
  final Completer<GoogleMapController> mapControllerCompleter = Completer();
  static const Duration hotelFetchDelay = Duration(milliseconds: 1200);
  bool loading = false;
  Timer? debounce;
  Set<Marker> markers = {};
  int hotelCount = 0;
  bool skipNextCameraIdleFetch = false;
  int hotelRequestId = 0;
  LatLng? lastFetchedCenter;

  // Camera tracking
  LatLng currentCenter = const LatLng(44.4268, 26.1025);

  // Search bar state
  final TextEditingController searchController = TextEditingController();
  List<PlaceSuggestion> suggestions = [];
  bool searchLoading = false;
  final FocusNode searchFocus = FocusNode();
  final storage = const FlutterSecureStorage();

  static const CameraPosition initialPosition = CameraPosition(
    target: LatLng(44.4268, 26.1025),
    zoom: 12,
  );

  Future<String?> getToken() => storage.read(key: 'access_token');

  double distanceKm(LatLng first, LatLng second) {
    const earthRadiusKm = 6371.0;
    final dLat = (second.latitude - first.latitude) * math.pi / 180.0;
    final dLng = (second.longitude - first.longitude) * math.pi / 180.0;
    final originLat = first.latitude * math.pi / 180.0;
    final targetLat = second.latitude * math.pi / 180.0;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(originLat) *
            math.cos(targetLat) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  bool shouldFetchHotels(LatLng center, {bool force = false}) {
    if (force || lastFetchedCenter == null) {
      return true;
    }
    return distanceKm(lastFetchedCenter!, center) >= 0.8;
  }

  void scheduleHotelFetch({bool force = false}) {
    if (debounce?.isActive ?? false) {
      debounce!.cancel();
    }
    debounce = Timer(hotelFetchDelay, () {
      fetchHotels(currentCenter, force: force);
    });
  }

  void handleAuthFailure() {
    AuthService.clearSession();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  Future<void> fetchSuggestions(String input) async {
    if (input.isEmpty) {
      setState(() => suggestions = []);
      return;
    }
    setState(() => searchLoading = true);
    String? token = await getToken();
    final uri = Uri.parse(
      '${AppConfig.baseUrl}/api/places/autocomplete/',
    ).replace(queryParameters: {'q': input});
    try {
      http.Response response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 401) {
        token = await AuthService.refreshAccessToken();
        if (token == null) {
          handleAuthFailure();
          return;
        }
        response = await http.get(
          uri,
          headers: {'Authorization': 'Bearer $token'},
        );
      }
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final predictions = data['predictions'] as List<dynamic>;
        setState(() {
          suggestions = predictions
              .map(
                (p) => PlaceSuggestion(
                  placeId: p['placeId'] as String,
                  description: p['description'] as String,
                ),
              )
              .toList();
        });
      } else {
        debugPrint(
          '[Places] autocomplete error ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('[Places] autocomplete exception: $e');
    } finally {
      setState(() => searchLoading = false);
    }
  }

  Future<void> goToPlace(String placeId) async {
    String? token = await getToken();
    final uri = Uri.parse(
      '${AppConfig.baseUrl}/api/places/details/',
    ).replace(queryParameters: {'place_id': placeId});
    try {
      http.Response response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 401) {
        token = await AuthService.refreshAccessToken();
        if (token == null) {
          handleAuthFailure();
          return;
        }
        response = await http.get(
          uri,
          headers: {'Authorization': 'Bearer $token'},
        );
      }
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final lat = data['lat'] as double;
        final lng = data['lng'] as double;
        final target = LatLng(lat, lng);
        final mapController = await mapControllerCompleter.future;
        currentCenter = target;
        skipNextCameraIdleFetch = true;
        setState(() {
          suggestions = [];
          searchFocus.unfocus();
        });
        await mapController.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: target, zoom: 14),
          ),
        );
        scheduleHotelFetch(force: true);
      } else {
        debugPrint(
          '[Places] details error ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('[Places] details exception: $e');
    }
  }

  Future<void> fetchHotels(LatLng center, {bool force = false}) async {
    if (!shouldFetchHotels(center, force: force)) {
      return;
    }

    final requestId = ++hotelRequestId;
    setState(() => loading = true);
    String? token = await getToken();
    final uri = Uri.parse('${AppConfig.baseUrl}/api/hotels/search/').replace(
      queryParameters: {
        'lat': center.latitude.toString(),
        'lng': center.longitude.toString(),
        'radius': '5',
      },
    );
    try {
      http.Response response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 401) {
        token = await AuthService.refreshAccessToken();
        if (token == null) {
          handleAuthFailure();
          return;
        }
        response = await http.get(
          uri,
          headers: {'Authorization': 'Bearer $token'},
        );
      }
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final hotels = data['hotels'] as List<dynamic>;
        final warning = data['warning'] as String?;
        if (!mounted || requestId != hotelRequestId) {
          return;
        }
        if (warning != null && warning.isNotEmpty) {
          debugPrint('[Hotels] warning: $warning');
        }
        debugPrint('[Hotels] received ${hotels.length} hotels from API');
        final newMarkers = <Marker>{};
        for (final h in hotels) {
          final latRaw = h['lat'];
          final lngRaw = h['lng'];
          debugPrint('[Hotels] hotel: ${h['name']} lat=$latRaw lng=$lngRaw');
          if (latRaw == null || lngRaw == null) continue;
          final lat = (latRaw as num).toDouble();
          final lng = (lngRaw as num).toDouble();
          final name = h['name'] as String? ?? 'Hotel';
          final address = h['address'] as String? ?? '';
          newMarkers.add(
            Marker(
              markerId: MarkerId(h['hotelId'] as String? ?? name),
              position: LatLng(lat, lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure,
              ),
              onTap: () => showHotelBottomSheet(name, address),
            ),
          );
        }
        debugPrint('[Hotels] placing ${newMarkers.length} markers on map');
        setState(() {
          markers = newMarkers;
          hotelCount = newMarkers.length;
        });
        lastFetchedCenter = center;
      } else {
        debugPrint(
          '[Hotels] search error ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('[Hotels] search exception: $e');
    } finally {
      if (mounted && requestId == hotelRequestId) {
        setState(() => loading = false);
      }
    }
  }

  void onCameraMove(CameraPosition position) {
    if (debounce?.isActive ?? false) {
      debounce!.cancel();
    }
    currentCenter = position.target;
  }

  void onCameraIdle() {
    if (skipNextCameraIdleFetch) {
      skipNextCameraIdleFetch = false;
    }
    scheduleHotelFetch();
  }

  void showHotelBottomSheet(String name, String address) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (address.isNotEmpty)
              Text(
                address,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  String hotelCountLabel() {
    if (hotelCount == 1) {
      return '1 hotel found';
    }
    return '$hotelCount hotels found';
  }

  @override
  void dispose() {
    debounce?.cancel();
    searchController.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hotel Map')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: initialPosition,
            onMapCreated: (controller) =>
                mapControllerCompleter.complete(controller),
            onCameraMove: onCameraMove,
            onCameraIdle: onCameraIdle,
            markers: markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          ),
          // Search bar overlay
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              children: [
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: TextField(
                    controller: searchController,
                    focusNode: searchFocus,
                    decoration: InputDecoration(
                      hintText: 'Search for an area or hotel...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchLoading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                searchController.clear();
                                setState(() => suggestions = []);
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onChanged: (value) {
                      setState(() {});
                      fetchSuggestions(value);
                    },
                  ),
                ),
                if (suggestions.isNotEmpty)
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: suggestions.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final suggestion = suggestions[index];
                        return ListTile(
                          leading: const Icon(
                            Icons.location_on,
                            color: Colors.blue,
                          ),
                          title: Text(
                            suggestion.description,
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () {
                            searchController.text = suggestion.description;
                            goToPlace(suggestion.placeId);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (loading)
            const Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Center(child: CircularProgressIndicator()),
            ),
          Positioned(
            bottom: 24,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
              child: Text(
                loading ? 'Searching...' : hotelCountLabel(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
