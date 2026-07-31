import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class AirportSearchField extends StatefulWidget {
  final String label;
  final IconData prefixIcon;
  final void Function(String iataCode, String displayLabel) onSelected;
  final VoidCallback? onCleared;

  const AirportSearchField({
    super.key,
    required this.label,
    required this.prefixIcon,
    required this.onSelected,
    this.onCleared,
  });

  @override
  State<AirportSearchField> createState() => AirportSearchFieldState();
}

class AirportSearchFieldState extends State<AirportSearchField> {
  final storage = const FlutterSecureStorage();
  final controller = TextEditingController();
  final layerLink = LayerLink();
  final focusNode = FocusNode();

  Timer? debounce;
  OverlayEntry? overlay;
  List<Map<String, dynamic>> suggestions = [];
  bool loading = false;
  bool hasSelection = false;

  @override
  void initState() {
    super.initState();
    focusNode.addListener(() {
      if (!focusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 150), removeOverlay);
      }
    });
  }

  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    focusNode.dispose();
    removeOverlay();
    super.dispose();
  }

  void removeOverlay() {
    overlay?.remove();
    overlay = null;
  }

  void showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> refreshAccessToken() async {
    try {
      final refreshToken = await storage.read(key: 'refresh_token');
      if (refreshToken == null) return null;
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/user/api/token/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refreshToken}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newAccess = data['access'] as String?;
        if (newAccess != null) {
          await storage.write(key: 'access_token', value: newAccess);
          final newRefresh = data['refresh'] as String?;
          if (newRefresh != null) {
            await storage.write(key: 'refresh_token', value: newRefresh);
          }
          return newAccess;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> search(String query) async {
    if (query.length < 2) {
      removeOverlay();
      if (mounted) setState(() => suggestions = []);
      return;
    }

    if (mounted) setState(() => loading = true);

    try {
      String? token = await storage.read(key: 'access_token');
      final encodedQuery = Uri.encodeComponent(query);
      Future<http.Response> doRequest(String? t) => http.get(
        Uri.parse(
          '${AppConfig.baseUrl}/user/api/select-destination/$encodedQuery/',
        ),
        headers: {if (t != null) 'Authorization': 'Bearer $t'},
      );

      http.Response response = await doRequest(token);

      if (response.statusCode == 401) {
        final refreshed = await refreshAccessToken();
        if (refreshed != null) {
          token = refreshed;
          response = await doRequest(token);
        } else {
          await storage.delete(key: 'access_token');
          await storage.delete(key: 'refresh_token');
          showError('Session expired. Please log in again.');
          removeOverlay();
          if (mounted) setState(() => suggestions = []);
          return;
        }
      }

      if (response.statusCode == 200 && mounted) {
        final body = jsonDecode(response.body);
        setState(() {
          suggestions = ((body['data'] as List?) ?? [])
              .cast<Map<String, dynamic>>();
        });
        showOverlay();
      } else if (response.statusCode != 200) {
        String message = 'Could not load airport suggestions.';
        try {
          final body = jsonDecode(response.body);
          if (body is Map && body['detail'] != null) {
            message = body['detail'].toString();
          } else if (body is Map && body['error'] != null) {
            message = body['error'].toString();
          }
        } catch (_) {}
        showError(message);
        removeOverlay();
        if (mounted) setState(() => suggestions = []);
      }
    } catch (_) {
      showError('Network error while loading airport suggestions.');
    }

    if (mounted) setState(() => loading = false);
  }

  void showOverlay() {
    removeOverlay();
    if (suggestions.isEmpty || !mounted) return;

    final overlayState = Overlay.of(context);
    overlay = OverlayEntry(
      builder: (_) => Positioned(
        width: 320,
        child: CompositedTransformFollower(
          link: layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 58),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: suggestions.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final item = suggestions[i];
                  final iata = item['iataCode'] as String? ?? '';
                  final name = item['name'] as String? ?? '';
                  final city = item['cityName'] as String? ?? '';
                  final country = item['countryName'] as String? ?? '';
                  final isAirport = item['subType'] == 'AIRPORT';
                  final displayLabel = city.isNotEmpty
                      ? '$city ($iata)'
                      : '$name ($iata)';
                  final subtitle = isAirport && name.isNotEmpty
                      ? '$name · $country'
                      : country;

                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isAirport ? Icons.flight : Icons.location_city,
                      color: const Color(0xFF5B85AA),
                      size: 20,
                    ),
                    title: Text(
                      displayLabel,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: subtitle.isNotEmpty
                        ? Text(
                            subtitle,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          )
                        : null,
                    onTap: () {
                      hasSelection = true;
                      controller.text = displayLabel;
                      widget.onSelected(iata, displayLabel);
                      removeOverlay();
                      setState(() => suggestions = []);
                      focusNode.unfocus();
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    overlayState.insert(overlay!);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: layerLink,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        style: GoogleFonts.poppins(fontSize: 14),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: GoogleFonts.poppins(color: Colors.grey[700]),
          prefixIcon: Icon(widget.prefixIcon, color: const Color(0xFF5B85AA)),
          suffixIcon: loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF5B85AA),
                    ),
                  ),
                )
              : controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    debounce?.cancel();
                    controller.clear();
                    hasSelection = false;
                    widget.onCleared?.call();
                    removeOverlay();
                    setState(() => suggestions = []);
                    focusNode.requestFocus();
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF5B85AA), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        onChanged: (value) {
          if (hasSelection) {
            hasSelection = false;
            widget.onCleared?.call();
          }
          debounce?.cancel();
          if (value.trim().isEmpty) {
            removeOverlay();
            setState(() => suggestions = []);
            return;
          }
          debounce = Timer(
            const Duration(milliseconds: 400),
            () => search(value.trim()),
          );
        },
        onTap: () {
          if (suggestions.isNotEmpty) showOverlay();
        },
      ),
    );
  }
}
