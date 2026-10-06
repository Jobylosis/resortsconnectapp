import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:provider/provider.dart';
import '../profile_page.dart';
import '../theme_provider.dart';
import '../theme.dart';
import 'admin_cms_page.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> with SingleTickerProviderStateMixin {
  late Stream<DatabaseEvent> _notifStream;
  late TabController _tabController;
  int _userPageIndex = 0;
  static const int _usersPerPage = 10;
  String _searchQuery = '';
  String _statusFilter = 'all';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      NotificationService().requestPermission();
      NotificationService().startListening(user.uid);
    }
    _notifStream =
        FirebaseDatabase.instance.ref("notifications/${user?.uid}").onValue;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 10))]
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.logout_rounded, size: 48, color: Colors.redAccent),
              const SizedBox(height: 16),
              const Text('Logout', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Are you sure you want to log out?', textAlign: TextAlign.center, style: TextStyle(fontSize: 14)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14)
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')
                    )
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14)
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        AuthService.signOut();
                      },
                      child: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold))
                    )
                  )
                ]
              )
            ]
          )
        )
      )
    );
  }

  void _toggleUserBan(String uid, bool currentStatus, String name) {
    if (currentStatus) {
      // Unban
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Unban Account?', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text('Are you sure you want to restore access for $name? They will be able to use the platform again.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await FirebaseDatabase.instance.ref("users/$uid").update({
                  'isBanned': false,
                  'banReason': null,
                  'bannedAt': null,
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$name has been unbanned.'))
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Unban Account'),
            ),
          ],
        ),
      );
    } else {
      // Ban / Restrict Access with Reason
      String banReason = '';
      String? banError;
      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Restrict Access?', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Are you sure you want to restrict access for $name? They will not be able to log in or use the platform.'),
                  const SizedBox(height: 16),
                  const Text('Reason for Restriction *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextField(
                    maxLines: 3,
                    onChanged: (val) {
                      banReason = val;
                      if (banError != null) {
                        setDialogState(() => banError = null);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'e.g., Violation of terms of service, inappropriate conduct...',
                      errorText: banError,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (banReason.trim().isEmpty) {
                    setDialogState(() => banError = 'Please provide a reason for restricting this user.');
                    return;
                  }
                  Navigator.pop(context);
                  await FirebaseDatabase.instance.ref("users/$uid").update({
                    'isBanned': true,
                    'banReason': banReason.trim(),
                    'bannedAt': ServerValue.timestamp,
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$name has been restricted.'))
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Restrict Access'),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _showRejectDialog(String uid, String name) {
    String selectedReason = 'Blurry Image';
    final List<String> reasons = [
      'Blurry Image',
      'Information Mismatch',
      'Expired ID',
      'Invalid Document',
      'Selfie Does Not Match'
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: AppTheme.darkSurface,
              title: const Text('Reject Verification', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select a reason for rejection:', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.darkBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderDark),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: selectedReason,
                        dropdownColor: AppTheme.darkBg,
                        items: reasons.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(color: Colors.white)))).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => selectedReason = val);
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await FirebaseDatabase.instance.ref("users/$uid").update({
                      'identityStatus': 'rejected',
                      'rejectionReason': selectedReason,
                      'idVerified': false,
                      'idImageUrl': null,
                      'selfieUrl': null,
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name\'s verification rejected.'), backgroundColor: Colors.orange));
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Reject', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      }
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
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('VALID ID', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600], letterSpacing: 1)),
                              const SizedBox(height: 8),
                              Container(
                                height: 200,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: imageUrl != null
                                    ? Image.network(imageUrl, fit: BoxFit.contain)
                                    : Center(child: Text('No ID Image', style: TextStyle(color: Colors.grey[500]))),
                              ),
                            ],
                          )
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('SELFIE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600], letterSpacing: 1)),
                              const SizedBox(height: 8),
                              Container(
                                height: 200,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: userData['selfieUrl'] != null
                                    ? Image.network(userData['selfieUrl'].toString(), fit: BoxFit.cover)
                                    : Center(child: Text('No Selfie', style: TextStyle(color: Colors.grey[500]))),
                              ),
                            ],
                          )
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),
                    
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _showRejectDialog(uid, name);
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.red.withOpacity(0.1),
                              foregroundColor: Colors.red,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                            ),
                            child: const Text('Reject Verification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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

  void _showUserDetailsDialog(String uid, Map userData) {
    String fName = userData['firstName']?.toString() ?? '';
    if (fName.toLowerCase() == 'null') fName = '';
    String lName = userData['lastName']?.toString() ?? '';
    if (lName.toLowerCase() == 'null') lName = '';
    String fullName = '$fName $lName'.trim();
    if (fullName.isEmpty) fullName = 'Unknown User';

    String email = userData['email']?.toString() ?? 'No Email';
    String phone = userData['phoneNumber']?.toString() ?? 'No Phone';
    String role = userData['role']?.toString() ?? 'Tourist';
    String idType = userData['idType']?.toString() ?? 'N/A';
    String? idUrl = userData['idImageUrl']?.toString();
    String? selfieUrl = userData['selfieUrl']?.toString();
    String identityStatus = userData['identityStatus']?.toString() ?? (userData['idVerified'] == true ? 'verified' : 'Not Submitted');
    int warnings = (userData['warningCount'] as num?)?.toInt() ?? 0;

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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  color: AppTheme.primaryAccent.withOpacity(0.05),
                  border: Border(bottom: BorderSide(color: AppTheme.primaryAccent.withOpacity(0.1))),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24))
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppTheme.primaryAccent,
                      backgroundImage: userData['profilePicUrl'] != null ? NetworkImage(userData['profilePicUrl']) : null,
                      child: userData['profilePicUrl'] == null ? Text(fullName.isNotEmpty ? fullName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)) : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(email, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: role == 'Owner' ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(role.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: role == 'Owner' ? Colors.green : Colors.grey[600])),
                          )
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
                    Text('VERIFICATION DOCUMENTS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600], letterSpacing: 1)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Valid ID', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Container(
                                height: 100,
                                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                                child: idUrl != null 
                                  ? Image.network(idUrl, fit: BoxFit.cover, width: double.infinity)
                                  : Center(child: Text('N/A', style: TextStyle(color: Colors.grey[600]))),
                              ),
                            ],
                          )
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Selfie', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Container(
                                height: 100,
                                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                                child: selfieUrl != null 
                                  ? Image.network(selfieUrl, fit: BoxFit.cover, width: double.infinity)
                                  : Center(child: Text('N/A', style: TextStyle(color: Colors.grey[600]))),
                              ),
                            ],
                          )
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildDetailRow(Icons.badge, 'ID Type', idType),
                    _buildDetailRow(Icons.verified, 'Status', identityStatus.toUpperCase()),
                    _buildDetailRow(Icons.phone, 'Phone', phone),
                    _buildDetailRow(Icons.warning_amber_rounded, 'Warnings', '$warnings / 3'),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.withOpacity(0.1),
                          foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
                          elevation: 0,
                        ),
                        child: const Text('Close'),
                      ),
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryAccent,
                          foregroundColor: Colors.white,
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
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

  void _showPropertyDetailsDialog(String propId, Map propData) {
    String name = propData['name']?.toString() ?? 'Resort Partner';
    String type = propData['type']?.toString() ?? 'Resort';
    String location = propData['location']?.toString() ?? 'Location not specified';
    String description = propData['description']?.toString() ?? 'No description provided.';
    String contactEmail = propData['contactEmail']?.toString() ?? 'N/A';
    String contactPhone = propData['contactPhone']?.toString() ?? 'N/A';
    String checkIn = propData['checkInTime']?.toString() ?? '2:00 PM';
    String checkOut = propData['checkOutTime']?.toString() ?? '12:00 NN';
    String staffCount = propData['staffCount']?.toString() ?? 'N/A';
    String gcashNumber = propData['gcashNumber']?.toString() ?? 'N/A';
    String gcashName = propData['gcashName']?.toString() ?? 'N/A';

    List imageUrls = [];
    if (propData['imageUrls'] is List) {
      imageUrls = propData['imageUrls'];
    } else if (propData['imageUrls'] is Map) {
      imageUrls = (propData['imageUrls'] as Map).values.toList();
    }
    String? bannerUrl = imageUrls.isNotEmpty ? imageUrls.first?.toString() : null;

    int roomCount = 0;
    if (propData['roomInventory'] is Map) {
      roomCount = (propData['roomInventory'] as Map).length;
    } else if (propData['rooms'] != null) {
      roomCount = int.tryParse(propData['rooms'].toString()) ?? 0;
    }

    int activityCount = 0;
    if (propData['activities'] is Map) {
      activityCount = (propData['activities'] as Map).length;
    }

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
              if (bannerUrl != null)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  child: Image.network(
                    bannerUrl,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 120,
                      color: AppTheme.primaryAccent.withOpacity(0.1),
                      child: const Icon(Icons.apartment_rounded, size: 48, color: AppTheme.primaryAccent),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.location_on, size: 14, color: AppTheme.secondaryAccent),
                                  const SizedBox(width: 4),
                                  Expanded(child: Text(location, style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(type.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(description, style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.4)),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryAccent.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                const Text('Rooms', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text('$roomCount', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryAccent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                const Text('Activities', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text('$activityCount', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.secondaryAccent)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                const Text('Staff', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text(staffCount, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.amber)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildDetailRow(Icons.email, 'Email', contactEmail),
                    _buildDetailRow(Icons.phone, 'Phone', contactPhone),
                    _buildDetailRow(Icons.schedule, 'Hours', '$checkIn - $checkOut'),
                    _buildDetailRow(Icons.payment, 'GCash', gcashNumber != 'N/A' ? '$gcashName ($gcashNumber)' : 'Not set'),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Close Overview', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
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

  Widget _buildPartnersTab() {
    final Query propertiesQuery = FirebaseDatabase.instance.ref().child('properties');

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Resort & Hotel Partners', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Live Ecosystem', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.secondaryAccent)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Tap any partner establishment to inspect live status, rooms, and contact details.', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          const SizedBox(height: 16),
          Expanded(
            child: FirebaseAnimatedList(
              query: propertiesQuery,
              defaultChild: const Center(child: CircularProgressIndicator()),
              itemBuilder: (context, snapshot, animation, index) {
                Map propData = snapshot.value is Map ? snapshot.value as Map : {};
                String propId = snapshot.key ?? '';
                String name = propData['name']?.toString() ?? 'Resort Partner';
                String type = propData['type']?.toString() ?? 'Resort';
                String location = propData['location']?.toString() ?? 'Location pending';

                int rooms = 0;
                if (propData['roomInventory'] is Map) {
                  rooms = (propData['roomInventory'] as Map).length;
                } else if (propData['rooms'] != null) {
                  rooms = int.tryParse(propData['rooms'].toString()) ?? 0;
                }

                return SizeTransition(
                  sizeFactor: animation,
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.secondaryAccent.withOpacity(0.15),
                        child: Icon(
                          type.toLowerCase() == 'hotel' ? Icons.hotel_rounded : Icons.beach_access_rounded,
                          color: AppTheme.secondaryAccent,
                        ),
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      subtitle: Text('$type · $location\n$rooms listed room${rooms == 1 ? "" : "s"}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      isThreeLine: true,
                      trailing: ElevatedButton(
                        onPressed: () => _showPropertyDetailsDialog(propId, propData),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          minimumSize: Size.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('View', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      onTap: () => _showPropertyDetailsDialog(propId, propData),
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
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppTheme.primaryAccent,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppTheme.primaryAccent,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              tabs: const [
                Tab(text: 'All Users'),
                Tab(text: 'Resort Partners'),
                Tab(text: 'Reports'),
                Tab(text: 'Landing Page'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
                child: StreamBuilder<DatabaseEvent>(
                  stream: FirebaseDatabase.instance.ref().child('users').onValue,
                  builder: (context, usersSnapshot) {
                    if (usersSnapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 80),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final currentAdminUid = FirebaseAuth.instance.currentUser?.uid;
                    final rawData = usersSnapshot.data?.snapshot.value;
                    final List<MapEntry<String, Map>> allUsers = [];

                    if (rawData is Map) {
                      rawData.forEach((k, v) {
                        if (k.toString() != currentAdminUid && v is Map) {
                          allUsers.add(MapEntry(k.toString(), v));
                        }
                      });
                    }

                    allUsers.sort((a, b) {
                      final aTime = (a.value['createdAt'] ?? 0) as num;
                      final bTime = (b.value['createdAt'] ?? 0) as num;
                      return bTime.compareTo(aTime);
                    });

                    // Filter users
                    final filteredUsers = allUsers.where((entry) {
                      final u = entry.value;
                      final fName = u['firstName']?.toString() ?? '';
                      final lName = u['lastName']?.toString() ?? '';
                      final fullName = '$fName $lName'.toLowerCase();
                      final email = (u['email']?.toString() ?? '').toLowerCase();
                      final q = _searchQuery.trim().toLowerCase();

                      final matchesSearch = q.isEmpty || fullName.contains(q) || email.contains(q);
                      if (!matchesSearch) return false;

                      final isBanned = u['isBanned'] == true;
                      final role = u['role']?.toString().toLowerCase() ?? 'tourist';

                      if (_statusFilter == 'active') return !isBanned;
                      if (_statusFilter == 'suspended') return isBanned;
                      if (_statusFilter == 'owner') return role == 'owner';
                      if (_statusFilter == 'tourist') return role != 'owner';
                      return true;
                    }).toList();

                    final totalPages = (filteredUsers.length / _usersPerPage).ceil();
                    final safePageIndex = _userPageIndex >= totalPages ? (totalPages > 0 ? totalPages - 1 : 0) : _userPageIndex;
                    final startIndex = safePageIndex * _usersPerPage;
                    final pageUsers = filteredUsers.skip(startIndex).take(_usersPerPage).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // System Control Gradient Banner matching website
                        Container(
                          margin: const EdgeInsets.only(bottom: 24),
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFEF4444), Color(0xFF10B981)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFEF4444).withOpacity(0.25),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                right: -20,
                                bottom: -30,
                                child: Icon(
                                  Icons.shield_outlined,
                                  size: 130,
                                  color: Colors.white.withOpacity(0.12),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: const [
                                      Icon(Icons.shield_rounded, color: Colors.white, size: 28),
                                      SizedBox(width: 12),
                                      Text(
                                        'System Control',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 24,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Oversee ecosystem health, manage memberships, and maintain security.',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // 3 KPI Stat Cards StreamBuilder with properties and reports
                        StreamBuilder<DatabaseEvent>(
                          stream: FirebaseDatabase.instance.ref().child('properties').onValue,
                          builder: (context, propsSnap) {
                            int propertiesCount = 0;
                            if (propsSnap.hasData && propsSnap.data?.snapshot.value is Map) {
                              propertiesCount = (propsSnap.data!.snapshot.value as Map).length;
                            }

                            return StreamBuilder<DatabaseEvent>(
                              stream: FirebaseDatabase.instance.ref().child('reports').onValue,
                              builder: (context, reportsSnap) {
                                int pendingReportsCount = 0;
                                if (reportsSnap.hasData && reportsSnap.data?.snapshot.value is Map) {
                                  final rMap = reportsSnap.data!.snapshot.value as Map;
                                  rMap.forEach((_, rep) {
                                    if (rep is Map && rep['status'] == 'pending') {
                                      pendingReportsCount++;
                                    }
                                  });
                                }

                                return LayoutBuilder(
                                  builder: (context, constraints) {
                                    final isWide = constraints.maxWidth > 650;
                                    if (isWide) {
                                      return Row(
                                        children: [
                                          Expanded(
                                            child: _buildKpiCard(
                                              icon: Icons.people_outline_rounded,
                                              iconColor: const Color(0xFF10B981),
                                              iconBg: const Color(0xFF10B981).withOpacity(0.12),
                                              count: '${allUsers.length}',
                                              label: 'TOTAL USERS',
                                              onTap: () {},
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: _buildKpiCard(
                                              icon: Icons.warning_amber_rounded,
                                              iconColor: const Color(0xFFEF4444),
                                              iconBg: const Color(0xFFEF4444).withOpacity(0.12),
                                              count: '$pendingReportsCount',
                                              label: 'PENDING REPORTS',
                                              onTap: () => _tabController.animateTo(2),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: _buildKpiCard(
                                              icon: Icons.apartment_rounded,
                                              iconColor: const Color(0xFF3B82F6),
                                              iconBg: const Color(0xFF3B82F6).withOpacity(0.12),
                                              count: '$propertiesCount',
                                              label: 'RESORT PARTNERS',
                                              onTap: () => _tabController.animateTo(1),
                                            ),
                                          ),
                                        ],
                                      );
                                    }

                                    // Mobile vertical / wrap layout
                                    return Column(
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _buildKpiCard(
                                                icon: Icons.people_outline_rounded,
                                                iconColor: const Color(0xFF10B981),
                                                iconBg: const Color(0xFF10B981).withOpacity(0.12),
                                                count: '${allUsers.length}',
                                                label: 'TOTAL USERS',
                                                onTap: () {},
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: _buildKpiCard(
                                                icon: Icons.warning_amber_rounded,
                                                iconColor: const Color(0xFFEF4444),
                                                iconBg: const Color(0xFFEF4444).withOpacity(0.12),
                                                count: '$pendingReportsCount',
                                                label: 'PENDING REPORTS',
                                                onTap: () => _tabController.animateTo(2),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        _buildKpiCard(
                                          icon: Icons.apartment_rounded,
                                          iconColor: const Color(0xFF3B82F6),
                                          iconBg: const Color(0xFF3B82F6).withOpacity(0.12),
                                          count: '$propertiesCount',
                                          label: 'RESORT PARTNERS',
                                          onTap: () => _tabController.animateTo(1),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),

                        const SizedBox(height: 28),

                        // Section Header & Search + Filter controls
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth > 580;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Review and manage user access permissions.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                if (isWide)
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildSearchField(),
                                      ),
                                      const SizedBox(width: 12),
                                      _buildStatusFilterDropdown(),
                                    ],
                                  )
                                else
                                  Column(
                                    children: [
                                      _buildSearchField(),
                                      const SizedBox(height: 10),
                                      _buildStatusFilterDropdown(fullWidth: true),
                                    ],
                                  ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 18),

                        // Users Table / Cards Container
                        Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardTheme.color ?? Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? AppTheme.borderDark
                                  : Colors.grey.withOpacity(0.15),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Column(
                              children: [
                                if (pageUsers.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 48),
                                    child: Center(
                                      child: Text(
                                        'No users found matching your criteria.',
                                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  )
                                else
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: pageUsers.length,
                                    separatorBuilder: (context, index) => Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? AppTheme.borderDark.withOpacity(0.5)
                                          : Colors.grey.withOpacity(0.12),
                                    ),
                                    itemBuilder: (context, index) {
                                      final entry = pageUsers[index];
                                      final uid = entry.key;
                                      final userData = entry.value;

                                      final isBanned = userData['isBanned'] == true;
                                      final banReason = userData['banReason']?.toString() ?? '';

                                      String fName = userData['firstName']?.toString() ?? '';
                                      if (fName.toLowerCase() == 'null') fName = '';
                                      String lName = userData['lastName']?.toString() ?? '';
                                      if (lName.toLowerCase() == 'null') lName = '';
                                      String fullName = '$fName $lName'.trim();
                                      if (fullName.isEmpty) fullName = 'Unknown User';

                                      final email = userData['email']?.toString() ?? 'No email provided';
                                      final role = userData['role']?.toString().toUpperCase() ?? 'TOURIST';
                                      final initial = fName.isNotEmpty ? fName[0].toUpperCase() : 'U';

                                      return _buildWebsiteUserCard(
                                        uid: uid,
                                        userData: userData,
                                        fullName: fullName,
                                        email: email,
                                        role: role,
                                        initial: initial,
                                        isBanned: isBanned,
                                        banReason: banReason,
                                      );
                                    },
                                  ),

                                // Pagination Footer matching website
                                if (filteredUsers.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? AppTheme.darkBg.withOpacity(0.5)
                                          : Colors.grey.withOpacity(0.04),
                                      border: Border(
                                        top: BorderSide(
                                          color: Theme.of(context).brightness == Brightness.dark
                                              ? AppTheme.borderDark
                                              : Colors.grey.withOpacity(0.12),
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Showing ${startIndex + 1}-${startIndex + pageUsers.length} of ${filteredUsers.length}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.chevron_left_rounded),
                                              iconSize: 22,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              onPressed: safePageIndex > 0
                                                  ? () => setState(() => _userPageIndex = safePageIndex - 1)
                                                  : null,
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 10),
                                              child: Text(
                                                'Page ${safePageIndex + 1} of $totalPages',
                                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.chevron_right_rounded),
                                              iconSize: 22,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              onPressed: safePageIndex < totalPages - 1
                                                  ? () => setState(() => _userPageIndex = safePageIndex + 1)
                                                  : null,
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
                        const SizedBox(height: 32),
                      ],
                    );
                  },
                ),
              ),
              _buildPartnersTab(),
              _buildReportsTab(),
              const AdminCmsPage(isEmbedded: true),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKpiCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String count,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppTheme.borderDark
                : Colors.grey.withOpacity(0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(height: 18),
            Text(
              count,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (val) {
        setState(() {
          _searchQuery = val;
          _userPageIndex = 0;
        });
      },
      decoration: InputDecoration(
        hintText: 'Search by name or email...',
        hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Colors.grey),
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark
            ? AppTheme.darkSurface
            : Colors.grey.withOpacity(0.08),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppTheme.borderDark
                : Colors.grey.withOpacity(0.15),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.primaryAccent, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildStatusFilterDropdown({bool fullWidth = false}) {
    return Container(
      width: fullWidth ? double.infinity : 160,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppTheme.darkSurface
            : Colors.grey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppTheme.borderDark
              : Colors.grey.withOpacity(0.15),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _statusFilter,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: Colors.grey),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All Accounts', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            DropdownMenuItem(value: 'active', child: Text('Active Only', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            DropdownMenuItem(value: 'suspended', child: Text('Suspended', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            DropdownMenuItem(value: 'owner', child: Text('Owners', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            DropdownMenuItem(value: 'tourist', child: Text('Tourists', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _statusFilter = val;
                _userPageIndex = 0;
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildWebsiteUserCard({
    required String uid,
    required Map userData,
    required String fullName,
    required String email,
    required String role,
    required String initial,
    required bool isBanned,
    required String banReason,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 620;

          if (isCompact) {
            // Responsive mobile card layout
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isBanned
                            ? const Color(0xFFEF4444).withOpacity(0.12)
                            : const Color(0xFF3B82F6).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: TextStyle(
                          color: isBanned ? const Color(0xFFEF4444) : const Color(0xFF1D4ED8),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fullName,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            email,
                            style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Role pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: role == 'OWNER'
                            ? const Color(0xFF10B981).withOpacity(0.12)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        role,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: role == 'OWNER' ? const Color(0xFF10B981) : Colors.grey[600],
                        ),
                      ),
                    ),
                    // Status indicator
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isBanned ? Icons.cancel_outlined : Icons.check_circle_outline_rounded,
                          size: 15,
                          color: isBanned ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isBanned ? 'Restricted' : 'Active',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isBanned ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (isBanned && banReason.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Reason: $banReason',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _showUserDetailsDialog(uid, userData),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          side: BorderSide(color: Colors.grey.withOpacity(0.3)),
                        ),
                        child: const Text('View Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _toggleUserBan(uid, isBanned, fullName),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isBanned
                              ? const Color(0xFF10B981).withOpacity(0.15)
                              : const Color(0xFFEF4444).withOpacity(0.15),
                          foregroundColor: isBanned ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          isBanned ? 'Unban' : 'Restrict Access',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          }

          // Full desktop/tablet table row style
          return Row(
            children: [
              // Initial Avatar Box
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isBanned
                      ? const Color(0xFFEF4444).withOpacity(0.12)
                      : const Color(0xFF3B82F6).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: TextStyle(
                    color: isBanned ? const Color(0xFFEF4444) : const Color(0xFF1D4ED8),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Name + Email
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Role pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: role == 'OWNER'
                      ? const Color(0xFF10B981).withOpacity(0.12)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  role,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: role == 'OWNER' ? const Color(0xFF10B981) : Colors.grey[600],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Status
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isBanned ? Icons.cancel_outlined : Icons.check_circle_outline_rounded,
                          size: 15,
                          color: isBanned ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isBanned ? 'Restricted' : 'Active',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isBanned ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                    if (isBanned && banReason.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          banReason,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Action buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () => _showUserDetailsDialog(uid, userData),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      side: BorderSide(color: Colors.grey.withOpacity(0.3)),
                    ),
                    child: const Text('View Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _toggleUserBan(uid, isBanned, fullName),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isBanned
                          ? const Color(0xFF10B981).withOpacity(0.15)
                          : const Color(0xFFEF4444).withOpacity(0.15),
                      foregroundColor: isBanned ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                      elevation: 0,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      isBanned ? 'Unban Account' : 'Restrict Access',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
