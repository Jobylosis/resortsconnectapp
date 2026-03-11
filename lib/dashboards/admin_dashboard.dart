import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import '../profile_page.dart';
import '../notifications_page.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late Stream<DatabaseEvent> _notifStream;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _notifStream = FirebaseDatabase.instance.ref("notifications/${user?.uid}").onValue;
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                FirebaseAuth.instance.signOut();
              },
              child: const Text('Logout', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _toggleUserBan(String uid, bool currentStatus, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(currentStatus ? 'Unban User?' : 'Ban User?'),
        content: Text('Are you sure you want to ${currentStatus ? 'restore' : 'suspend'} access for $name?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseDatabase.instance.ref("users/$uid").update({
                'isBanned': !currentStatus,
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$name has been ${currentStatus ? 'unbanned' : 'banned'}.'))
                );
              }
            }, 
            child: Text(currentStatus ? 'Unban' : 'Ban', style: TextStyle(color: currentStatus ? Colors.green : Colors.red))
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userRef = FirebaseDatabase.instance.ref("users/${user?.uid}");
    final Query usersQuery = FirebaseDatabase.instance.ref().child('users');

    return StreamBuilder<DatabaseEvent>(
      stream: userRef.onValue,
      builder: (context, snapshot) {
        String firstName = "Admin";
        if (snapshot.hasData && snapshot.data!.snapshot.exists) {
          Map data = snapshot.data!.snapshot.value as Map;
          firstName = data['firstName'] ?? "Admin";
        }

        return Scaffold(
          backgroundColor: Colors.grey[50],
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.white,
            title: Row(
              children: [
                const Icon(Icons.admin_panel_settings_rounded, color: Colors.redAccent, size: 28),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'System Admin',
                      style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'IT: $firstName',
                      style: TextStyle(color: Colors.redAccent[700], fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              StreamBuilder<DatabaseEvent>(
                stream: _notifStream,
                builder: (context, snapshot) {
                  int unreadCount = 0;
                  if (snapshot.hasData && snapshot.data!.snapshot.exists) {
                    Map notifs = snapshot.data!.snapshot.value as Map;
                    unreadCount = notifs.values.where((n) => n['isRead'] == false).length;
                  }
                  return Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_none, color: Colors.redAccent),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const NotificationsPage()),
                        ),
                        tooltip: 'Notifications',
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text(
                              '$unreadCount',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                }
              ),
              IconButton(
                icon: const Icon(Icons.person_outline, color: Colors.redAccent),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfilePage()),
                ),
                tooltip: 'Edit Profile',
              ),
              Container(
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
                child: IconButton(
                  icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                  onPressed: () => _showLogoutDialog(context),
                ),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('System Overview', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.redAccent[700])),
                      const SizedBox(height: 8),
                      const Text('Monitor and manage all user accounts in real-time.', style: TextStyle(fontSize: 14, color: Colors.grey)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text('User Directory', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                const SizedBox(height: 16),
                Expanded(
                  child: FirebaseAnimatedList(
                    query: usersQuery,
                    itemBuilder: (context, snapshot, animation, index) {
                      Map userData = snapshot.value as Map;
                      String uid = snapshot.key!;
                      bool isBanned = userData['isBanned'] ?? false;
                      String fullName = '${userData['firstName']} ${userData['lastName']}';

                      // Don't show the current admin in their own list to prevent self-banning
                      if (uid == FirebaseAuth.instance.currentUser?.uid) return const SizedBox.shrink();

                      return SizeTransition(
                        sizeFactor: animation,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isBanned ? Colors.red[50] : Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5, offset: const Offset(0, 2))],
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isBanned ? Colors.red : Colors.red[50], 
                              child: Icon(isBanned ? Icons.block : Icons.person, color: isBanned ? Colors.white : Colors.redAccent)
                            ),
                            title: Text(fullName, style: TextStyle(fontWeight: FontWeight.bold, decoration: isBanned ? TextDecoration.lineThrough : null)),
                            subtitle: Text('Role: ${userData['role']}'),
                            trailing: Switch(
                              value: !isBanned, 
                              activeColor: Colors.green,
                              inactiveThumbColor: Colors.red,
                              onChanged: (value) => _toggleUserBan(uid, isBanned, fullName),
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
      },
    );
  }
}
