import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0D17),
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.lock, color: Colors.white),
            title: const Text('Change Password', style: TextStyle(color: Colors.white)),
            onTap: () {
              // Add password change logic
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications, color: Colors.white),
            title: const Text('Notifications', style: TextStyle(color: Colors.white)),
            onTap: () {
              // Notifications logic
            },
          ),
          ListTile(
            leading: const Icon(Icons.help_outline, color: Colors.white),
            title: const Text('Help & Support', style: TextStyle(color: Colors.white)),
            onTap: () {
              // Help screen
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white),
            title: const Text('About App', style: TextStyle(color: Colors.white)),
            onTap: () {
              // About screen
            },
          ),
        ],
      ),
    );
  }
}
