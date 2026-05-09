import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:provider/provider.dart';
import '../profile_page.dart';
import '../notifications_page.dart';
import '../theme_provider.dart';
import '../theme.dart';

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
              child: const Text('Logout', style: TextStyle(color: AppTheme.primaryAccent)),
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
            child: Text(currentStatus ? 'Unban' : 'Ban', style: TextStyle(color: currentStatus ? Colors.green : AppTheme.primaryAccent))
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final userRef = FirebaseDatabase.instance.ref("users/${user?.uid}");
    final Query usersQuery = FirebaseDatabase.instance.ref().child('users');

    return StreamBuilder<DatabaseEvent>(
      stream: userRef.onValue,
      builder: (context, snapshot) {
        String adminName = "Admin";
        if (snapshot.hasData && snapshot.data!.snapshot.exists) {
          Map data = snapshot.data!.snapshot.value as Map;
          adminName = data['firstName'] ?? "Admin";
        }

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            centerTitle: false,
            titleSpacing: 16,
            title: Row(
              children: [
                const Icon(Icons.admin_panel_settings_rounded, color: AppTheme.primaryAccent, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'System Admin',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'IT: $adminName',
                        style: const TextStyle(color: AppTheme.primaryAccent, fontSize: 11, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(themeProvider.themeMode == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
                color: AppTheme.primaryAccent,
                onPressed: () => themeProvider.toggleTheme(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              StreamBuilder<DatabaseEvent>(
                stream: _notifStream,
                builder: (context, snapshot) {
                  int unreadCount = 0;
                  if (snapshot.hasData && snapshot.data!.snapshot.exists) {
                    Map notifs = snapshot.data!.snapshot.value as Map;
                    unreadCount = notifs.values.where((n) => n['isRead'] == false).length;
                  }
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.primaryAccent),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const NotificationsPage()),
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(color: AppTheme.primaryAccent, borderRadius: BorderRadius.circular(10)),
                            constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                            child: Text(
                              '$unreadCount',
                              style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                }
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.person_outline_rounded, color: AppTheme.primaryAccent),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfilePage()),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: AppTheme.primaryAccent),
                onPressed: () => _showLogoutDialog(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 16),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('System Overview', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent)),
                        const SizedBox(height: 8),
                        Text('Monitor and manage all user accounts in real-time.', style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text('User Directory', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                Expanded(
                  child: FirebaseAnimatedList(
                    query: usersQuery,
                    itemBuilder: (context, snapshot, animation, index) {
                      Map userData = snapshot.value as Map;
                      String uid = snapshot.key!;
                      bool isBanned = userData['isBanned'] ?? false;
                      
                      String fName = userData['firstName']?.toString() ?? '';
                      if (fName.toLowerCase() == 'null') fName = '';
                      String lName = userData['lastName']?.toString() ?? '';
                      if (lName.toLowerCase() == 'null') lName = '';
                      
                      String fullName = '$fName $lName'.trim();
                      if (fullName.isEmpty) fullName = 'Unknown User';

                      String role = userData['role']?.toString() ?? 'User';
                      if (role.toLowerCase() == 'null') role = 'User';

                      if (uid == FirebaseAuth.instance.currentUser?.uid) return const SizedBox.shrink();

                      return SizeTransition(
                        sizeFactor: animation,
                        child: Card(
                          color: isBanned ? AppTheme.primaryAccent.withOpacity(0.1) : Theme.of(context).cardTheme.color,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isBanned ? AppTheme.primaryAccent : AppTheme.primaryAccent.withOpacity(0.1), 
                              child: Icon(isBanned ? Icons.block_rounded : Icons.person_rounded, color: isBanned ? Colors.white : AppTheme.primaryAccent)
                            ),
                            title: Text(fullName, style: TextStyle(fontWeight: FontWeight.bold, decoration: isBanned ? TextDecoration.lineThrough : null)),
                            subtitle: Text('Role: $role'),
                            trailing: Switch(
                              value: !isBanned, 
                              activeColor: Colors.green,
                              inactiveThumbColor: AppTheme.primaryAccent,
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
