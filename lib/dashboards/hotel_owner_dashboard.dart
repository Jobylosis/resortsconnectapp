import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HotelOwnerDashboard extends StatelessWidget {
  const HotelOwnerDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hotel Owner Panel'),
        backgroundColor: Colors.orange,
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
            Icon(Icons.hotel, size: 80, color: Colors.orange),
            SizedBox(height: 20),
            Text('Manage Your Hotel', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Track room availability and check-ins.', textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}
