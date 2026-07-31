import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'config.dart';
import 'services/auth_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'dart:ui';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final storage = const FlutterSecureStorage();
  bool isLoading = false;

  // Full pool – shuffled on every page open
  static const allDestinations = [
    TravelSuggestion(
      city: 'Paris',
      country: 'France',
      iata: 'CDG',
      description:
          'The city of light – Eiffel Tower, world-class cuisine and timeless romance.',
      imageUrl:
          'https://images.unsplash.com/photo-1499856871958-5b9627545d1a?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Rome',
      country: 'Italy',
      iata: 'FCO',
      description:
          'Walk through millennia of history – Colosseum, Vatican and perfect pasta.',
      imageUrl:
          'https://images.unsplash.com/photo-1552832230-c0197dd311b5?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Barcelona',
      country: 'Spain',
      iata: 'BCN',
      description:
          'Gaudí architecture, vibrant nightlife and golden Mediterranean beaches.',
      imageUrl:
          'https://images.unsplash.com/photo-1539037116277-4db20889f2d4?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Amsterdam',
      country: 'Netherlands',
      iata: 'AMS',
      description:
          'Charming canals, world-famous museums and a relaxed cycling culture.',
      imageUrl:
          'https://images.unsplash.com/photo-1468557893527-7db5e1c15f49?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Santorini',
      country: 'Greece',
      iata: 'JTR',
      description:
          'Iconic white-washed villages perched above the stunning Aegean Sea.',
      imageUrl:
          'https://images.unsplash.com/photo-1613395877344-13d4a8e0d49e?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Prague',
      country: 'Czech Republic',
      iata: 'PRG',
      description: 'A fairytale old town, Gothic spires and cosy beer halls.',
      imageUrl:
          'https://images.unsplash.com/photo-1541849546-216549ae216d?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Dubai',
      country: 'UAE',
      iata: 'DXB',
      description:
          'Futuristic skyline, luxury shopping and a gateway to the desert.',
      imageUrl:
          'https://images.unsplash.com/photo-1512453979798-5ea266f8880c?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Tokyo',
      country: 'Japan',
      iata: 'NRT',
      description:
          "Ultra-modern meets ancient tradition in the world's most dynamic city.",
      imageUrl:
          'https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Lisbon',
      country: 'Portugal',
      iata: 'LIS',
      description:
          'Sun-soaked hills, trams, pastel tiles and the finest pastéis de nata.',
      imageUrl:
          'https://images.unsplash.com/photo-1585208798174-6cedd4b71a63?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Vienna',
      country: 'Austria',
      iata: 'VIE',
      description:
          'Imperial palaces, Mozart, coffee houses and world-class classical music.',
      imageUrl:
          'https://images.unsplash.com/photo-1516550893923-42d28e5677af?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Budapest',
      country: 'Hungary',
      iata: 'BUD',
      description:
          'The Pearl of the Danube – thermal baths, ruin bars and stunning bridges.',
      imageUrl:
          'https://images.unsplash.com/photo-1555993539-1732b0258235?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Istanbul',
      country: 'Turkey',
      iata: 'IST',
      description:
          'Where East meets West – bazaars, minarets and the Bosphorus at sunset.',
      imageUrl:
          'https://images.unsplash.com/photo-1524231757912-21f4fe3a7200?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Marrakech',
      country: 'Morocco',
      iata: 'RAK',
      description:
          'Vibrant souks, riads and the magic of the Djemaa el-Fna at nightfall.',
      imageUrl:
          'https://images.unsplash.com/photo-1539020140153-e479b8c22e70?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'New York',
      country: 'USA',
      iata: 'JFK',
      description:
          'The city that never sleeps – skyscrapers, Broadway and Central Park.',
      imageUrl:
          'https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Bali',
      country: 'Indonesia',
      iata: 'DPS',
      description:
          'Emerald rice terraces, temple ceremonies and world-class surf breaks.',
      imageUrl:
          'https://images.unsplash.com/photo-1537996194471-e657df975ab4?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Bangkok',
      country: 'Thailand',
      iata: 'BKK',
      description:
          'Golden temples, street food heaven and an electrifying urban energy.',
      imageUrl:
          'https://images.unsplash.com/photo-1508009603885-50cf7c579365?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Maldives',
      country: 'Maldives',
      iata: 'MLE',
      description:
          'Crystal-clear lagoons, overwater bungalows and untouched coral reefs.',
      imageUrl:
          'https://images.unsplash.com/photo-1514282401047-d79a71a590e8?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Cape Town',
      country: 'South Africa',
      iata: 'CPT',
      description:
          'Table Mountain, pristine beaches and a vibrant multicultural food scene.',
      imageUrl:
          'https://images.unsplash.com/photo-1580060839134-75a5edca2e99?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Singapore',
      country: 'Singapore',
      iata: 'SIN',
      description:
          'A gleaming city-state where futuristic gardens meet incredible street food.',
      imageUrl:
          'https://images.unsplash.com/photo-1525625293386-3f8f99389edd?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Sydney',
      country: 'Australia',
      iata: 'SYD',
      description:
          'Opera House, Bondi Beach and a laid-back lifestyle under endless sunshine.',
      imageUrl:
          'https://images.unsplash.com/photo-1506973035872-a4ec16b8e8d9?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Florence',
      country: 'Italy',
      iata: 'FLR',
      description:
          'Renaissance art, rolling Tuscan hills and the finest Chianti in the world.',
      imageUrl:
          'https://images.unsplash.com/photo-1543429257-3eb0b65d9c58?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Edinburgh',
      country: 'Scotland',
      iata: 'EDI',
      description:
          'A dramatic castle, cobbled closes and the world-famous Fringe Festival.',
      imageUrl:
          'https://images.unsplash.com/photo-1506377585622-bedcbb027afc?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Reykjavik',
      country: 'Iceland',
      iata: 'KEF',
      description:
          'Northern lights, geysers, hot springs and the midnight sun.',
      imageUrl:
          'https://images.unsplash.com/photo-1476610182048-b716b8518aae?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Kyoto',
      country: 'Japan',
      iata: 'ITM',
      description:
          'Bamboo forests, geisha districts, zen gardens and thousands of temples.',
      imageUrl:
          'https://images.unsplash.com/photo-1493976040374-85c8e12f0c0e?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Amalfi',
      country: 'Italy',
      iata: 'NAP',
      description:
          'Cliffside villages, lemon groves and the most scenic coastline in Europe.',
      imageUrl:
          'https://images.unsplash.com/photo-1533587851505-d119e13fa0d7?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Dubrovnik',
      country: 'Croatia',
      iata: 'DBV',
      description:
          'The Pearl of the Adriatic – medieval walls, clear sea and Game of Thrones glory.',
      imageUrl:
          'https://images.unsplash.com/photo-1555990793-da11153b2473?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Queenstown',
      country: 'New Zealand',
      iata: 'ZQN',
      description:
          'The adventure capital of the world – bungee, ski and fjord cruises.',
      imageUrl:
          'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Montreal',
      country: 'Canada',
      iata: 'YUL',
      description:
          'Bilingual charm, world-class festivals and a legendary food scene.',
      imageUrl:
          'https://images.unsplash.com/photo-1519178614-68673b201f36?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Cairo',
      country: 'Egypt',
      iata: 'CAI',
      description:
          'The Pyramids of Giza, the Sphinx and 5,000 years of civilisation.',
      imageUrl:
          'https://images.unsplash.com/photo-1572252009286-268acec5ca0a?w=600&q=80',
    ),
    TravelSuggestion(
      city: 'Havana',
      country: 'Cuba',
      iata: 'HAV',
      description:
          'Vintage cars, salsa rhythms, colonial architecture and Cuban cigars.',
      imageUrl:
          'https://images.unsplash.com/photo-1500759285222-a95626b934cb?w=600&q=80',
    ),
  ];

  static const allRegions = [
    RegionSuggestion(
      name: 'Western Europe',
      emoji: '🗼',
      imageUrl:
          'https://images.unsplash.com/photo-1467269204594-9661b134dd2b?w=400&q=80',
    ),
    RegionSuggestion(
      name: 'Mediterranean',
      emoji: '🏖️',
      imageUrl:
          'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=400&q=80',
    ),
    RegionSuggestion(
      name: 'Middle East',
      emoji: '🕌',
      imageUrl:
          'https://images.unsplash.com/photo-1548036328-c9fa89d128fa?w=400&q=80',
    ),
    RegionSuggestion(
      name: 'East Asia',
      emoji: '⛩️',
      imageUrl:
          'https://images.unsplash.com/photo-1528360983277-13d401cdc186?w=400&q=80',
    ),
    RegionSuggestion(
      name: 'Southeast Asia',
      emoji: '🌴',
      imageUrl:
          'https://images.unsplash.com/photo-1537996194471-e657df975ab4?w=400&q=80',
    ),
    RegionSuggestion(
      name: 'North America',
      emoji: '🗽',
      imageUrl:
          'https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?w=400&q=80',
    ),
    RegionSuggestion(
      name: 'Africa',
      emoji: '🦁',
      imageUrl:
          'https://images.unsplash.com/photo-1580060839134-75a5edca2e99?w=400&q=80',
    ),
    RegionSuggestion(
      name: 'Oceania',
      emoji: '🌊',
      imageUrl:
          'https://images.unsplash.com/photo-1506973035872-a4ec16b8e8d9?w=400&q=80',
    ),
  ];

  late List<TravelSuggestion> travelSuggestions;
  late List<RegionSuggestion> regionSuggestions;

  @override
  void initState() {
    super.initState();
    final destinations = List<TravelSuggestion>.from(allDestinations)
      ..shuffle();
    travelSuggestions = destinations.take(8).toList();
    final regions = List<RegionSuggestion>.from(allRegions)..shuffle();
    regionSuggestions = regions.take(4).toList();
  }

  Future<void> logout() async {
    setState(() => isLoading = true);

    try {
      final refreshToken = await storage.read(key: 'refresh_token');
      if (refreshToken == null) {
        throw Exception('No refresh token stored');
      }

      final accessToken = await storage.read(key: 'access_token');

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/user/api/logout/'),
        headers: {
          'Content-Type': 'application/json',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'refresh': refreshToken}),
      );

      if (response.statusCode == 200) {
        await AuthService.clearSession();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Logged out successfully',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pushReplacementNamed(context, '/login');
        }
      } else {
        String errorMessage = 'Logout failed. Please try again.';
        try {
          final errorBody = jsonDecode(response.body);
          if (errorBody is Map && errorBody.containsKey('detail')) {
            errorMessage = errorBody['detail'];
          }
        } catch (_) {}

        if (mounted) {
          showError('Logout Error', errorMessage);
        }
      }
    } catch (e) {
      if (mounted) {
        showError('Error', e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void showError(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          title,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.red,
          ),
        ),
        content: Text(message, style: GoogleFonts.poppins(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: GoogleFonts.poppins(
                color: const Color(0xFF5B85AA),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Image.asset('assets/images/logo_fara_scris_3.png', height: 140),
        backgroundColor: const Color(0xFF5B85AA),
        elevation: 4,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : PopupMenuButton(
                      icon: const Icon(Icons.more_vert),
                      itemBuilder: (BuildContext context) => [
                        PopupMenuItem(
                          onTap: logout,
                          child: Text(
                            'Logout',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Section
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF5B85AA), Color(0xFF7BA5C9)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF5B85AA,
                            ).withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Welcome to Voya',
                            style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Plan the best trip!',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Travel suggestions section
              Text(
                'Where to next?',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF333333),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Handpicked destinations just for you',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 260,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: travelSuggestions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final s = travelSuggestions[index];
                    return TravelCard(suggestion: s);
                  },
                ),
              ),
              const SizedBox(height: 32),

              // Popular regions
              Text(
                'Popular regions',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF333333),
                ),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: regionSuggestions.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.55,
                ),
                itemBuilder: (context, index) {
                  final r = regionSuggestions[index];
                  return RegionCard(region: r);
                },
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Data models ─────────────────────────────────────────────────────────────

class TravelSuggestion {
  final String city;
  final String country;
  final String description;
  final String imageUrl;
  final String iata;
  const TravelSuggestion({
    required this.city,
    required this.country,
    required this.description,
    required this.imageUrl,
    required this.iata,
  });
}

class RegionSuggestion {
  final String name;
  final String emoji;
  final String imageUrl;
  const RegionSuggestion({
    required this.name,
    required this.emoji,
    required this.imageUrl,
  });
}

// ── Card widgets ─────────────────────────────────────────────────────────────

class TravelCard extends StatelessWidget {
  final TravelSuggestion suggestion;
  const TravelCard({super.key, required this.suggestion});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        width: 190,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Photo
              Image.network(
                suggestion.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: const Color(0xFF5B85AA),
                  child: const Icon(
                    Icons.flight_takeoff,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
              // Gradient overlay
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.72),
                    ],
                    stops: const [0.45, 1.0],
                  ),
                ),
              ),
              // Text content
              Positioned(
                left: 12,
                right: 12,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      suggestion.city,
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      suggestion.country,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      suggestion.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.80),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RegionCard extends StatelessWidget {
  final RegionSuggestion region;
  const RegionCard({super.key, required this.region});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              region.imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Container(color: const Color(0xFF5B85AA)),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(region.emoji, style: const TextStyle(fontSize: 28)),
                  const SizedBox(height: 4),
                  Text(
                    region.name,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
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
