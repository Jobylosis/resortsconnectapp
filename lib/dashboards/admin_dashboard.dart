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
    _notifStream =
        FirebaseDatabase.instance.ref("notifications/${user?.uid}").onValue;
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
              child: const Text('Logout',
                  style: TextStyle(color: AppTheme.primaryAccent)),
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
        content: Text(
            'Are you sure you want to ${currentStatus ? 'restore' : 'suspend'} access for $name?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await FirebaseDatabase.instance.ref("users/$uid").update({
                  'isBanned': !currentStatus,
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          '$name has been ${currentStatus ? 'unbanned' : 'banned'}.')));
                }
              },
              child: Text(currentStatus ? 'Unban' : 'Ban',
                  style: TextStyle(
                      color: currentStatus
                          ? Colors.green
                          : AppTheme.primaryAccent))),
        ],
      ),
    );
  }

  void _showVerificationDialog(String uid, Map userData) {
    String name = "${userData['firstName'] ?? ''} ${userData['middleName'] ?? ''} ${userData['lastName'] ?? ''}".replaceAll(RegExp(r'\s+'), ' ').trim();
    String email = userData['email']?.toString() ?? 'No Email';
    String phone = userData['phoneNumber']?.toString() ?? 'No Phone';
    String role = userData['role']?.toString() ?? 'Tourist';
    String? idType = userData['idType']?.toString();
    String? imageUrl = userData['idImageUrl']?.toString();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Theme.of(context).cardTheme.color,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  color: AppTheme.primaryAccent.withOpacity(0.05),
                  border: Border(bottom: BorderSide(color: AppTheme.primaryAccent.withOpacity(0.1))),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24))
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryAccent,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: AppTheme.primaryAccent.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]
                      ),
                      child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Review Registration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('Identity Verification Request', style: TextStyle(fontSize: 12, color: AppTheme.primaryAccent, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('APPLICANT DETAILS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600], letterSpacing: 1)),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.withOpacity(0.2)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: AppTheme.primaryAccent,
                                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.email_outlined, size: 14, color: Colors.grey[600]),
                                        const SizedBox(width: 4),
                                        Expanded(child: Text(email, style: TextStyle(fontSize: 13, color: Colors.grey[600]), overflow: TextOverflow.ellipsis)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.phone_outlined, size: 14, color: Colors.grey[600]),
                                        const SizedBox(width: 4),
                                        Expanded(child: Text(phone, style: TextStyle(fontSize: 13, color: Colors.grey[600]), overflow: TextOverflow.ellipsis)),
                                      ],
                                    )
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Divider(height: 1),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('ACCOUNT ROLE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[500])),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: AppTheme.primaryAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                      child: Text(role.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent)),
                                    )
                                  ],
                                )
                              )
                            ],
                          )
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('IDENTITY DOCUMENT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600], letterSpacing: 1)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                          child: Text(idType ?? 'Unknown ID', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue)),
                        )
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.withOpacity(0.2)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: imageUrl != null
                          ? Image.network(imageUrl, height: 250, fit: BoxFit.contain)
                          : Container(
                              height: 250,
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.image_not_supported_outlined, size: 48, color: Colors.grey[600]),
                                  const SizedBox(height: 12),
                                  Text('No ID Image Provided', style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.w500))
                                ],
                              ),
                            ),
                    ),

                    const SizedBox(height: 32),
                    
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () async {
                              Navigator.pop(context);
                              await FirebaseDatabase.instance.ref("users/$uid").update({
                                'isBanned': true,
                                'banReason': 'ID Verification Rejected'
                              });
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name rejected and banned.')));
                              }
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.red.withOpacity(0.1),
                              foregroundColor: Colors.red,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                            ),
                            child: const Text('Reject User', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              Navigator.pop(context);
                              await FirebaseDatabase.instance.ref("users/$uid").update({
                                'idVerified': true,
                              });
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name approved successfully.')));
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                            ),
                            child: const Text('Approve User', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showResolveDialog(String reportId, Map reportData) {
    String resolveAction = 'dismiss';
    String resolveMessage = '';
    String reportedUid = reportData['reportedUid']?.toString() ?? '';
    String reporterUid = reportData['reporterUid']?.toString() ?? '';
    String reportedName = reportData['reportedName']?.toString() ?? reportedUid;
    String reason = reportData['reason']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateSB) {
          return AlertDialog(
            title: const Text('Resolve Report'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Report against: $reportedName', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Reason: "$reason"', style: const TextStyle(fontStyle: FontStyle.italic)),
                  const SizedBox(height: 16),
                  DropdownButton<String>(
                    value: resolveAction,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'dismiss', child: Text('Dismiss / No Action')),
                      DropdownMenuItem(value: 'warn_reported', child: Text('Warn Reported User')),
                      DropdownMenuItem(value: 'ban_reported', child: Text('Ban Reported User')),
                      DropdownMenuItem(value: 'warn_reporter', child: Text('Warn Reporter (False Report)')),
                    ],
                    onChanged: (val) {
                      setStateSB(() {
                        resolveAction = val!;
                        resolveMessage = '';
                      });
                    },
                  ),
                  if (resolveAction != 'dismiss') ...[
                    const SizedBox(height: 16),
                    TextField(
                      onChanged: (val) => resolveMessage = val,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: resolveAction == 'ban_reported' ? "Reason for banning..." : "Message for warning...",
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  String targetUid = resolveAction == 'warn_reporter' ? reporterUid : reportedUid;
                  
                  if (resolveAction == 'ban_reported') {
                    await FirebaseDatabase.instance.ref("users/$targetUid").update({
                      'isBanned': true,
                      'banReason': resolveMessage.isEmpty ? 'Banned due to report' : resolveMessage,
                      'bannedAt': ServerValue.timestamp,
                    });
                  } else if (resolveAction == 'warn_reported' || resolveAction == 'warn_reporter') {
                    final userSnap = await FirebaseDatabase.instance.ref("users/$targetUid/warningCount").get();
                    int currentWarnings = 0;
                    if (userSnap.exists) currentWarnings = (userSnap.value as num).toInt();
                    int newWarnings = currentWarnings + 1;
                    
                    Map<String, dynamic> updates = {'warningCount': newWarnings};
                    if (newWarnings >= 3) {
                      updates['isBanned'] = true;
                      updates['banReason'] = 'Accumulated 3 Warnings';
                      updates['bannedAt'] = ServerValue.timestamp;
                    }
                    await FirebaseDatabase.instance.ref("users/$targetUid").update(updates);
                    
                    await FirebaseDatabase.instance.ref("notifications/$targetUid").push().set({
                      'title': 'Official Warning',
                      'body': resolveMessage.isEmpty ? 'You have received a warning regarding your behavior.' : resolveMessage,
                      'isRead': false,
                      'timestamp': ServerValue.timestamp,
                    });
                  }

                  await FirebaseDatabase.instance.ref("reports/$reportId").update({
                    'status': 'resolved',
                    'resolvedAt': ServerValue.timestamp,
                    'resolveAction': resolveAction,
                  });
                  
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report resolved successfully.')));
                },
                child: const Text('Confirm Action'),
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _buildReportsTab() {
    final Query reportsQuery = FirebaseDatabase.instance.ref().child('reports').orderByChild('status').equalTo('pending');
    
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pending Reports', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent)),
          const SizedBox(height: 16),
          Expanded(
            child: FirebaseAnimatedList(
              query: reportsQuery,
              defaultChild: const Center(child: CircularProgressIndicator()),
              itemBuilder: (context, snapshot, animation, index) {
                Map reportData = snapshot.value as Map;
                String reportId = snapshot.key!;
                String reportedName = reportData['reportedName']?.toString() ?? 'Unknown';
                String reason = reportData['reason']?.toString() ?? 'No reason';
                
                return SizeTransition(
                  sizeFactor: animation,
                  child: Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.redAccent,
                        child: Icon(Icons.report, color: Colors.white),
                      ),
                      title: Text('Reported: $reportedName', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Reason: "$reason"'),
                      trailing: ElevatedButton(
                        onPressed: () => _showResolveDialog(reportId, reportData),
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent, foregroundColor: Colors.white),
                        child: const Text('Resolve'),
                      ),
                    ),
                  ),
                );
              },
            ),
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

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
            centerTitle: false,
            titleSpacing: 16,
            title: Row(
              children: [
                const Icon(Icons.admin_panel_settings_rounded,
                    color: AppTheme.primaryAccent, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'System Admin',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'IT: $adminName',
                        style: const TextStyle(
                            color: AppTheme.primaryAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w500),
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
                icon: Icon(themeProvider.themeMode == ThemeMode.dark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded),
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
                      unreadCount = notifs.values
                          .where((n) => n['isRead'] == false)
                          .length;
                    }
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.notifications_none_rounded,
                              color: AppTheme.primaryAccent),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    const NotificationsPage()),
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
                              decoration: BoxDecoration(
                                  color: AppTheme.primaryAccent,
                                  borderRadius: BorderRadius.circular(10)),
                              constraints: const BoxConstraints(
                                  minWidth: 14, minHeight: 14),
                              child: Text(
                                '$unreadCount',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    );
                  }),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.person_outline_rounded,
                    color: AppTheme.primaryAccent),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfilePage()),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.logout_rounded,
                    color: AppTheme.primaryAccent),
                onPressed: () => _showLogoutDialog(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 16),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'User Directory'),
                Tab(text: 'Reports'),
              ],
              labelColor: AppTheme.primaryAccent,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppTheme.primaryAccent,
            ),
          ),
          body: TabBarView(
            children: [
              Padding(
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
                        const Text('System Overview',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryAccent)),
                        const SizedBox(height: 8),
                        Text(
                            'Monitor and manage all user accounts in real-time.',
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text('User Directory',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                Expanded(
                  child: FirebaseAnimatedList(
                    query: usersQuery,
                    sort: (a, b) {
                      final aTime = (a.value as Map)['createdAt'] ?? 0;
                      final bTime = (b.value as Map)['createdAt'] ?? 0;
                      return bTime.compareTo(aTime);
                    },
                    itemBuilder: (context, snapshot, animation, index) {
                      Map userData = snapshot.value as Map;
                      String uid = snapshot.key!;
                      bool isBanned = userData['isBanned'] ?? false;
                      bool isVerified = userData['idVerified'] != false; // Defaults to true if null

                      String fName = userData['firstName']?.toString() ?? '';
                      if (fName.toLowerCase() == 'null') fName = '';
                      String lName = userData['lastName']?.toString() ?? '';
                      if (lName.toLowerCase() == 'null') lName = '';

                      String fullName = '$fName $lName'.trim();
                      if (fullName.isEmpty) fullName = 'Unknown User';

                      String customId =
                          userData['customId']?.toString() ?? 'No ID';

                      String role = userData['role']?.toString() ?? 'User';
                      if (role.toLowerCase() == 'null') role = 'User';

                      if (uid == FirebaseAuth.instance.currentUser?.uid) {
                        return const SizedBox.shrink();
                      }

                      return SizeTransition(
                        sizeFactor: animation,
                        child: Card(
                          color: isBanned
                              ? AppTheme.primaryAccent.withOpacity(0.1)
                              : Theme.of(context).cardTheme.color,
                          child: ListTile(
                            leading: CircleAvatar(
                                backgroundColor: isBanned || !isVerified
                                    ? AppTheme.primaryAccent
                                    : AppTheme.primaryAccent.withOpacity(0.1),
                                child: Icon(
                                    !isVerified 
                                        ? Icons.pending_actions_rounded
                                        : (isBanned
                                            ? Icons.block_rounded
                                            : Icons.person_rounded),
                                    color: isBanned || !isVerified
                                        ? Colors.white
                                        : AppTheme.primaryAccent)),
                            title: Text(fullName,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    decoration: isBanned
                                        ? TextDecoration.lineThrough
                                        : null)),
                            subtitle: Text('ID: $customId | Role: $role ${!isVerified ? "\nPending Verification" : ""}'),
                            isThreeLine: !isVerified,
                            trailing: !isVerified
                                ? ElevatedButton(
                                    onPressed: () => _showVerificationDialog(uid, userData),
                                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryAccent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 12)),
                                    child: const Text('Review', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  )
                                : Switch(
                                    value: !isBanned,
                                    activeThumbColor: Colors.green,
                                    inactiveThumbColor: AppTheme.primaryAccent,
                                    onChanged: (value) =>
                                        _toggleUserBan(uid, isBanned, fullName),
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
          _buildReportsTab(),
        ],
          ),
        ),
      );
      },
    );
  }
}
