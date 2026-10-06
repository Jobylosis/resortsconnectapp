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
  final List<String> filters = ['All', 'Message', 'Booking', 'Refund', 'Reschedule', 'Approved', 'Pending', 'Declined'];

  // Selection mode states
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  // Scroll controllers to preserve exact scroll position across selection actions
  final ScrollController _activeScrollController = ScrollController();
  final ScrollController _archiveScrollController = ScrollController();

  @override
  void dispose() {
    _activeScrollController.dispose();
    _archiveScrollController.dispose();
    super.dispose();
  }

  void _enterSelectionMode(String initialId) {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.add(initialId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(List<Map<String, dynamic>> currentList) {
    setState(() {
      final allIds = currentList.map((n) => n['id']?.toString()).whereType<String>().toSet();
      if (_selectedIds.length == allIds.length && allIds.isNotEmpty) {
        _selectedIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedIds.addAll(allIds);
      }
    });
  }

  Future<void> _batchArchive() async {
    if (_selectedIds.isEmpty || user == null) return;
    final idsToArchive = Set<String>.from(_selectedIds);
    _exitSelectionMode();
    final Map<String, Object?> updates = {};
    for (final id in idsToArchive) {
      updates["notifications/${user?.uid}/$id/isArchived"] = true;
    }
    await FirebaseDatabase.instance.ref().update(updates);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Archived ${idsToArchive.length} notification(s)')),
      );
    }
  }

  Future<void> _batchDelete() async {
    if (_selectedIds.isEmpty || user == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Selected Notifications'),
        content: Text('Are you sure you want to permanently delete ${_selectedIds.length} notification(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final idsToDelete = Set<String>.from(_selectedIds);
      _exitSelectionMode();
      final Map<String, Object?> updates = {};
      for (final id in idsToDelete) {
        updates["notifications/${user?.uid}/$id"] = null;
      }
      await FirebaseDatabase.instance.ref().update(updates);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted ${idsToDelete.length} notification(s)')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: _isSelectionMode
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _exitSelectionMode,
                )
              : null,
          title: Text(
            _isSelectionMode ? '${_selectedIds.length} Selected' : 'Notifications',
          ),
          actions: [
            if (!_isSelectionMode) ...[
              IconButton(
                icon: Icon(themeProvider.themeMode == ThemeMode.dark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded),
                onPressed: () => themeProvider.toggleTheme(),
              ),
              const SizedBox(width: 8),
            ],
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
                        hintText: 'Search room, date, etc...',
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

            // Sort stably by newest to oldest (timestamp descending) so list position does not jump when items are read or selected
            notifications.sort((a, b) {
              final aTime = a['timestamp'] ?? 0;
              final bTime = b['timestamp'] ?? 0;
              return bTime.compareTo(aTime);
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

    final allSelected = list.isNotEmpty && list.every((n) => _selectedIds.contains(n['id']));

    return Column(
      children: [
        if (_isSelectionMode)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
            child: Row(
              children: [
                Checkbox(
                  value: allSelected,
                  onChanged: (_) => _selectAll(list),
                ),
                Text(
                  allSelected ? 'Deselect All' : 'Select All (${list.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                if (!isArchive)
                  TextButton.icon(
                    icon: const Icon(Icons.archive_outlined, size: 18),
                    label: const Text('Archive'),
                    onPressed: _selectedIds.isNotEmpty ? _batchArchive : null,
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                  label: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                  onPressed: _selectedIds.isNotEmpty ? _batchDelete : null,
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            key: PageStorageKey<String>(isArchive ? 'notifs_archive_list' : 'notifs_active_list'),
            controller: isArchive ? _archiveScrollController : _activeScrollController,
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final notif = list[index];
              final notifId = notif['id']?.toString() ?? '';
              final isSelected = _selectedIds.contains(notifId);
              bool isRead = notif['isRead'] ?? false;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: isSelected
                      ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
                      : BorderSide.none,
                ),
                color: isSelected
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
                    : isRead
                        ? Theme.of(context).cardTheme.color
                        : Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onLongPress: () {
                    if (!_isSelectionMode) {
                      _enterSelectionMode(notifId);
                    } else {
                      _toggleSelection(notifId);
                    }
                  },
                  onTap: () {
                    if (_isSelectionMode) {
                      _toggleSelection(notifId);
                    } else {
                      FirebaseDatabase.instance
                          .ref("notifications/${user?.uid}/$notifId")
                          .update({'isRead': true});
                    }
                  },
                  child: ListTile(
                    leading: _isSelectionMode
                        ? Checkbox(
                            value: isSelected,
                            onChanged: (_) => _toggleSelection(notifId),
                          )
                        : CircleAvatar(
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
                    trailing: _isSelectionMode
                        ? null
                        : isArchive
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
                                                .ref("notifications/${user?.uid}/$notifId")
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
                                      .ref("notifications/${user?.uid}/$notifId")
                                      .update({'isArchived': true});
                                },
                              ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _getIcon(String? type) {
    switch (type) {
      case 'new_message': return Icons.chat_bubble_rounded;
      case 'booking_new': return Icons.add_shopping_cart_rounded;
      case 'booking_accepted': return Icons.check_circle_rounded;
      case 'booking_rejected': return Icons.cancel_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  Color _getIconColor(String? type) {
    switch (type) {
      case 'new_message': return AppTheme.secondaryAccent;
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
