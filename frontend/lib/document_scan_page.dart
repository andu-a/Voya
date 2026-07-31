import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'config.dart';
import 'add_traveler_page.dart';

class DocumentScanPage extends StatefulWidget {
  const DocumentScanPage({super.key});

  @override
  State<DocumentScanPage> createState() => DocumentScanPageState();
}

class DocumentScanPageState extends State<DocumentScanPage> {
  File? frontImage;
  File? backImage;
  bool isScanning = false;

  Future<void> pickImage({required bool isFront}) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isFront ? 'Front of Document' : 'Back of Document',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF5B85AA)),
                title: Text('Take a photo', style: GoogleFonts.poppins()),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: Color(0xFF5B85AA),
                ),
                title: Text(
                  'Choose from gallery',
                  style: GoogleFonts.poppins(),
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() {
      if (isFront) {
        frontImage = File(picked.path);
      } else {
        backImage = File(picked.path);
      }
    });
  }

  Future<String> fileToBase64(File file) async {
    final bytes = await file.readAsBytes();
    final ext = file.path.split('.').last.toLowerCase();
    return 'data:image/$ext;base64,${base64Encode(bytes)}';
  }

  Future<void> submitScan() async {
    if (frontImage == null) return;

    setState(() => isScanning = true);

    try {
      final frontBase64 = await fileToBase64(frontImage!);
      String? backBase64;
      if (backImage != null) {
        backBase64 = await fileToBase64(backImage!);
      }

      final storage = const FlutterSecureStorage();
      String? token = await storage.read(key: 'access_token');

      final body = <String, dynamic>{'front_image': frontBase64};
      if (backBase64 != null) body['back_image'] = backBase64;

      Future<http.Response> sendRequest(String? t) => http.post(
        Uri.parse('${AppConfig.baseUrl}/user/api/scan-document/'),
        headers: {
          if (t != null) 'Authorization': 'Bearer $t',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      http.Response response = await sendRequest(token);

      // Token refresh if needed
      if (response.statusCode == 401) {
        final refreshToken = await storage.read(key: 'refresh_token');
        if (refreshToken != null) {
          final refreshResp = await http.post(
            Uri.parse('${AppConfig.baseUrl}/user/api/token/refresh/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh': refreshToken}),
          );
          if (refreshResp.statusCode == 200) {
            final newAccess = jsonDecode(refreshResp.body)['access'] as String?;
            if (newAccess != null) {
              await storage.write(key: 'access_token', value: newAccess);
              token = newAccess;
              response = await sendRequest(token);
            }
          }
        }
      }

      if (!mounted) return;

      if (response.statusCode == 200) {
        final extracted = jsonDecode(response.body) as Map<String, dynamic>;
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AddTravelerPage(prefillData: extracted),
          ),
        );
        if (result == true && mounted) {
          Navigator.pop(context, true);
        }
      } else {
        final msg =
            jsonDecode(response.body)['error'] ?? 'Failed to scan document.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              msg,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: ${e.toString()}',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Scan Document',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF5B85AA),
        elevation: 4,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'Scan your document',
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Capture both sides of your ID or passport for the best accuracy.',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),

            // Front card
            DocumentCard(
              label: 'Front of Document',
              sublabel: 'Required',
              icon: Icons.credit_card,
              image: frontImage,
              onTap: () => pickImage(isFront: true),
              onRemove: () => setState(() => frontImage = null),
            ),
            const SizedBox(height: 16),

            // Back card
            DocumentCard(
              label: 'Back of Document',
              sublabel: 'Optional — improves accuracy',
              icon: Icons.credit_card,
              image: backImage,
              onTap: () => pickImage(isFront: false),
              onRemove: () => setState(() => backImage = null),
            ),
            const SizedBox(height: 32),

            // Submit button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (frontImage != null && !isScanning)
                    ? submitScan
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B85AA),
                  disabledBackgroundColor: const Color(
                    0xFF5B85AA,
                  ).withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 2,
                ),
                child: isScanning
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Scanning...',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        'Scan Document',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable card widget for front / back image capture
// ---------------------------------------------------------------------------
class DocumentCard extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final File? image;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const DocumentCard({
    super.key,
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.image,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = image != null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasImage
                ? const Color(0xFF4CAF50).withValues(alpha: 0.6)
                : const Color(0xFF5B85AA).withValues(alpha: 0.3),
            width: hasImage ? 2 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: hasImage ? buildPreview(context) : buildPlaceholder(),
      ),
    );
  }

  Widget buildPlaceholder() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF5B85AA).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: const Color(0xFF5B85AA)),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF333333),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sublabel,
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_a_photo, size: 16, color: Colors.grey[500]),
              const SizedBox(width: 6),
              Text(
                'Tap to capture',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildPreview(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Image.file(
            image!,
            width: double.infinity,
            height: 200,
            fit: BoxFit.cover,
          ),
        ),
        // Gradient overlay at the bottom with label
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(15),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.6),
                ],
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Text(
                  'Tap to retake',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Remove button
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}
