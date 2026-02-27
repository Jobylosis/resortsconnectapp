import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ResortOwnerDashboard extends StatelessWidget {
  const ResortOwnerDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resort Owner Panel'),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.house, size: 80, color: Colors.teal),
            SizedBox(height: 20),
            Text('Manage Your Resort', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('View bookings and update your resort information.', textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}
