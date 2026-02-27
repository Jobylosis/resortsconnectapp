import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';
import 'login_page.dart';

import 'dashboards/tourist_dashboard.dart';
import 'dashboards/resort_owner_dashboard.dart';
import 'dashboards/hotel_owner_dashboard.dart';
import 'dashboards/admin_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Resort Connect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          // Use StreamBuilder instead of FutureBuilder to listen for role changes in realtime
          return StreamBuilder<DatabaseEvent>(
            stream: FirebaseDatabase.instance.ref("users/${snapshot.data!.uid}").onValue,
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              if (userSnapshot.hasData && userSnapshot.data!.snapshot.exists) {
                Map<dynamic, dynamic> userData = userSnapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                String role = userData['role'] ?? 'Tourist';
                
                switch (role) {
                  case 'Resort Owner':
                    return const ResortOwnerDashboard();
                  case 'Hotel Owner':
                    return const HotelOwnerDashboard();
                  case 'Admin':
                    return const AdminDashboard();
                  default:
                    return const TouristDashboard();
                }
              }
              // If user exists in Auth but not in Database, we might still be writing it or it was deleted
              return const Scaffold(body: Center(child: Text("User data not found.")));
            },
          );
        }
        return const LoginPage();
      },
    );
  }
}
