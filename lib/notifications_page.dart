import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final Query notificationsQuery = FirebaseDatabase.instance
        .ref("notifications/${user?.uid}")
        .orderByChild("timestamp");

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Notifications'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      body: FirebaseAnimatedList(
        query: notificationsQuery,
        sort: (a, b) {
          // Sort by newest first
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
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              color: isRead ? Colors.white : Colors.blue[50],
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
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    ),
                  ],
                ),
                onTap: () {
                  // Mark as read
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
      case 'booking_new': return Icons.add_shopping_cart;
      case 'booking_accepted': return Icons.check_circle;
      case 'booking_rejected': return Icons.cancel;
      default: return Icons.notifications;
    }
  }

  Color _getIconColor(String? type) {
    switch (type) {
      case 'booking_new': return Colors.blue;
      case 'booking_accepted': return Colors.green;
      case 'booking_rejected': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
    var date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return "${date.hour}:${date.minute.toString().padLeft(2, '0')} - ${date.day}/${date.month}/${date.year}";
  }
}
