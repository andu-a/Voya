import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps a protected route and redirects to /login if no access token exists.
class RouteGuard extends StatefulWidget {
  final Widget child;
  const RouteGuard({super.key, required this.child});

  @override
  State<RouteGuard> createState() => RouteGuardState();
}

class RouteGuardState extends State<RouteGuard> {
  static const storage = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    checkAuth();
  }

  Future<void> checkAuth() async {
    final token = await storage.read(key: 'access_token');
    if (token == null && mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
