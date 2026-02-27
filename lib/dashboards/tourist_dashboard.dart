import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TouristDashboard extends StatelessWidget {
  const TouristDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tourist Dashboard'),
        backgroundColor: Colors.blue,
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
            Icon(Icons.beach_access, size: 80, color: Colors.blue),
            SizedBox(height: 20),
            Text('Welcome, Traveler!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Find your next vacation destination here.', textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}
