import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';
import 'theme.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final Query notificationsQuery = FirebaseDatabase.instance
        .ref("notifications/${user?.uid}")
        .orderByChild("timestamp");

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: Icon(themeProvider.themeMode == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            onPressed: () => themeProvider.toggleTheme(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FirebaseAnimatedList(
        query: notificationsQuery,
        sort: (a, b) {
          final aTime = (a.value as Map)['timestamp'] ?? 0;
          final bTime = (b.value as Map)['timestamp'] ?? 0;
          return bTime.compareTo(aTime);
        },
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, snapshot, animation, index) {
          Map notif = snapshot.value as Map;
          bool isRead = notif['isRead'] ?? false;

          return SizeTransition(
            sizeFactor: animation,
            child: Card(
              color: isRead 
                  ? Theme.of(context).cardTheme.color 
                  : Theme.of(context).colorScheme.secondary.withOpacity(0.1),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _getIconColor(notif['type']),
                  child: Icon(_getIcon(notif['type']), color: Colors.white, size: 20),
                ),
                title: Text(
                  notif['title'] ?? '',
                  style: TextStyle(
                    fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(notif['message'] ?? ''),
                    const SizedBox(height: 4),
                    Text(
                      _formatTimestamp(notif['timestamp']),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10),
                    ),
                  ],
                ),
                onTap: () {
                  FirebaseDatabase.instance
                      .ref("notifications/${user?.uid}/${snapshot.key}")
                      .update({'isRead': true});
                },
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _getIcon(String? type) {
    switch (type) {
      case 'booking_new': return Icons.add_shopping_cart_rounded;
      case 'booking_accepted': return Icons.check_circle_rounded;
      case 'booking_rejected': return Icons.cancel_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  Color _getIconColor(String? type) {
    switch (type) {
      case 'booking_new': return Colors.blue;
      case 'booking_accepted': return Colors.green;
      case 'booking_rejected': return AppTheme.primaryAccent;
      default: return AppTheme.secondaryAccent;
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
    var date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return "${date.hour}:${date.minute.toString().padLeft(2, '0')} - ${date.day}/${date.month}/${date.year}";
  }
}
