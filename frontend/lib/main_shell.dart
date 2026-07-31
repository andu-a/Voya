import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home_page.dart';
import 'flight_availability_page.dart';
import 'manage_profile_page.dart';
import 'hotel_map_page.dart';
import 'ai_chat_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int currentIndex = 0;

  final List<Widget> pages = const [
    HomePage(),
    ManageProfilePage(),
    FlightAvailabilityPage(),
    HotelMapPage(),
  ];

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF5B85AA);

    return Scaffold(
      body: IndexedStack(index: currentIndex, children: pages),
      floatingActionButton: SizedBox(
        width: 64,
        height: 64,
        child: FloatingActionButton(
          elevation: 6,
          backgroundColor: accent,
          shape: const CircleBorder(),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiChatPage()),
            );
          },
          child: const Icon(Icons.auto_awesome, size: 28, color: Colors.white),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: Colors.white,
        elevation: 12,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left side
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    buildNavItem(Icons.home_rounded, 'Home', 0),
                    buildNavItem(Icons.person_rounded, 'Profile', 1),
                  ],
                ),
              ),
              // Gap for the FAB
              const SizedBox(width: 64),
              // Right side
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    buildNavItem(Icons.flight_rounded, 'Flight', 2),
                    buildNavItem(Icons.hotel_rounded, 'Hotel', 3),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildNavItem(IconData icon, String label, int index) {
    final isSelected = currentIndex == index;
    const accent = Color(0xFF5B85AA);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => currentIndex = index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? accent : Colors.grey[400], size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? accent : Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
