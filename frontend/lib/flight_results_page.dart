import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'flight_confirm_page.dart';

class FlightResultsPage extends StatelessWidget {
  final List flights;
  const FlightResultsPage({super.key, required this.flights});

  Future<void> launchUrlLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      debugPrint('Blocked unsafe URL: $url');
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Flight Results',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF5B85AA),
        elevation: 4,
      ),
      body: flights.isEmpty
          ? Center(
              child: Text(
                'No flights found.',
                style: GoogleFonts.poppins(fontSize: 16),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: flights.length,
              separatorBuilder: (_, _) => const SizedBox(height: 16),
              itemBuilder: (context, idx) {
                final flight = flights[idx];
                final display = (flight['display'] as Map?) ?? {};
                final airlineName = flight['airline_name'] as String? ?? '';
                final origin = display['origin'] as String? ?? '';
                final destination = display['destination'] as String? ?? '';
                final departure = display['departure'] as String? ?? '';
                final arrival = display['arrival'] as String? ?? '';
                final price = flight['price']?['total'];
                final currency = flight['price']?['currency'] ?? 'EUR';
                final stops = display['stops'] as int? ?? 0;
                final returnDeparture =
                    display['return_departure'] as String? ?? '';
                final returnArrival =
                    display['return_arrival'] as String? ?? '';
                final returnStops = display['return_stops'] as int?;
                final isRound =
                    (display['return_departure'] as String?) != null;

                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.flight,
                              color: Color(0xFF5B85AA),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$airlineName  |  $origin → $destination',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Outbound leg
                        LegRow(
                          label: isRound ? 'Outbound' : null,
                          from: origin,
                          to: destination,
                          departure: departure,
                          arrival: arrival,
                          stops: stops,
                        ),
                        // Return leg
                        if (isRound) ...[
                          const Divider(height: 18),
                          LegRow(
                            label: 'Return',
                            from: destination,
                            to: origin,
                            departure: returnDeparture,
                            arrival: returnArrival,
                            stops: returnStops ?? 0,
                          ),
                        ],
                        if (price != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Price: $price $currency',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF5B85AA),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Estimated price — select flight to see final price',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                        const Divider(height: 20),
                        if (flight['checkin_link'] != null) ...[
                          Text(
                            'Check-in:',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          BookButton(
                            label: 'Check-in',
                            onTap: () => launchUrlLink(flight['checkin_link']),
                          ),
                        ],
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FlightConfirmPage(
                                    flight: Map<String, dynamic>.from(flight),
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5B85AA),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              'Select flight',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class BookButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const BookButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF5B85AA),
        side: const BorderSide(color: Color(0xFF5B85AA)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: Text(label),
    );
  }
}

class LegRow extends StatelessWidget {
  final String? label;
  final String from;
  final String to;
  final String departure;
  final String arrival;
  final int stops;
  const LegRow({
    super.key,
    required this.from,
    required this.to,
    required this.departure,
    required this.arrival,
    required this.stops,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  label == 'Return' ? Icons.flight_land : Icons.flight_takeoff,
                  size: 14,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  label!,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    from,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    departure,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: const Color(0xFF5B85AA),
                ),
                const SizedBox(height: 2),
                Text(
                  stops == 0 ? 'Direct' : '$stops stop${stops > 1 ? 's' : ''}',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: stops == 0 ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    to,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    arrival,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
