import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';
import 'theme.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final user = FirebaseAuth.instance.currentUser;
  String searchQuery = '';
  String selectedFilter = 'All';
  final List<String> filters = ['All', 'Booking', 'Refund', 'Reschedule', 'Approved', 'Pending', 'Declined'];


  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          actions: [
            IconButton(
              icon: Icon(themeProvider.themeMode == ThemeMode.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded),
              onPressed: () => themeProvider.toggleTheme(),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: "Active"),
              Tab(text: "Archive"),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search user, room, or date...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (val) => setState(() => searchQuery = val.toLowerCase()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: selectedFilter,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: filters.map((f) => DropdownMenuItem(value: f, child: Text(f, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (val) => setState(() => selectedFilter = val!),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<DatabaseEvent>(
          stream: FirebaseDatabase.instance.ref("notifications/${user?.uid}").onValue,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data?.snapshot.value as Map?;
            List<Map<String, dynamic>> notifications = [];
            
            if (data != null) {
              data.forEach((key, value) {
                final Map<String, dynamic> notif = Map<String, dynamic>.from(value as Map);
                notif['id'] = key;
                notifications.add(notif);
              });
            }

            // Sort: unread at the top, then oldest to newest
            notifications.sort((a, b) {
              final aRead = (a['isRead'] == true) ? 1 : 0;
              final bRead = (b['isRead'] == true) ? 1 : 0;
              
              if (aRead != bRead) {
                return aRead.compareTo(bRead);
              }
              
              final aTime = a['timestamp'] ?? 0;
              final bTime = b['timestamp'] ?? 0;
              
              if (aRead == 0) {
                // Unread: oldest to newest (ascending)
                return aTime.compareTo(bTime);
              } else {
                // Read: newest to oldest (descending)
                return bTime.compareTo(aTime);
              }
            });


            // Apply Filters and Search
            List<Map<String, dynamic>> filteredList = notifications.where((n) {
              String title = (n['title'] ?? '').toString().toLowerCase();
              String msg = (n['message'] ?? '').toString().toLowerCase();
              String type = (n['type'] ?? '').toString().toLowerCase();
              String dateStr = _formatTimestamp(n['timestamp']).toLowerCase();
              
              bool matchesSearch = searchQuery.isEmpty || 
                                   title.contains(searchQuery) || 
                                   msg.contains(searchQuery) || 
                                   dateStr.contains(searchQuery);
                                   
              bool matchesFilter = true;
              if (selectedFilter != 'All') {
                 String f = selectedFilter.toLowerCase();
                 matchesFilter = title.contains(f) || msg.contains(f) || type.contains(f);
              }
              
              return matchesSearch && matchesFilter;
            }).toList();

            final activeNotifs = filteredList.where((n) => n['isArchived'] != true).toList();
            final archivedNotifs = filteredList.where((n) => n['isArchived'] == true).toList();

            return TabBarView(
              children: [
                _buildList(activeNotifs, false),
                _buildList(archivedNotifs, true),
              ],
            );
          },
        ),
      ),
      ],
      ),
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> list, bool isArchive) {
    if (list.isEmpty) {
      return Center(
        child: Text(
          isArchive ? "No archived notifications" : "All caught up!",
          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final notif = list[index];
        bool isRead = notif['isRead'] ?? false;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
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
                  .ref("notifications/${user?.uid}/${notif['id']}")
                  .update({'isRead': true});
            },
            trailing: isArchive 
              ? IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Notification'),
                        content: const Text('Are you sure you want to permanently delete this notification?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              FirebaseDatabase.instance
                                  .ref("notifications/${user?.uid}/${notif['id']}")
                                  .remove();
                              Navigator.pop(context);
                            },
                            child: const Text('Delete', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                  },
                )
              : IconButton(
                  icon: const Icon(Icons.archive_outlined, color: Colors.grey),
                  onPressed: () {
                    FirebaseDatabase.instance
                        .ref("notifications/${user?.uid}/${notif['id']}")
                        .update({'isArchived': true});
                  },
                ),
          ),
        );
      },
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
