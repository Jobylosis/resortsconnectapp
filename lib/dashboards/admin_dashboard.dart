import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final Query usersQuery = FirebaseDatabase.instance.ref().child('users');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Super Admin (IT Maintenance)'),
        backgroundColor: Colors.redAccent,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.admin_panel_settings, size: 50, color: Colors.redAccent),
                SizedBox(width: 16),
                Text('Realtime System Overview', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: FirebaseAnimatedList(
                query: usersQuery,
                itemBuilder: (context, snapshot, animation, index) {
                  Map userData = snapshot.value as Map;
                  return SizeTransition(
                    sizeFactor: animation,
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.person),
                        title: Text('${userData['firstName']} ${userData['lastName']}'),
                        subtitle: Text('Role: ${userData['role']} | ${userData['email']}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            // Add logic to deactivate or delete user
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
