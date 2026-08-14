import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../theme.dart';

class TouristProfileDialog extends StatefulWidget {
  final String touristUid;
  const TouristProfileDialog({super.key, required this.touristUid});

  @override
  State<TouristProfileDialog> createState() => _TouristProfileDialogState();
}

class _TouristProfileDialogState extends State<TouristProfileDialog> {
  Map? _profileData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    try {
      final snap = await FirebaseDatabase.instance.ref('users/${widget.touristUid}').get();
      if (snap.exists) {
        setState(() => _profileData = snap.value as Map);
      } else {
        final tSnap = await FirebaseDatabase.instance.ref('tourist_users/${widget.touristUid}').get();
        if (tSnap.exists) {
          setState(() => _profileData = tSnap.value as Map);
        }
      }
    } catch (e) {
      debugPrint("Error fetching tourist profile: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: _isLoading 
          ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
          : _profileData == null 
            ? const SizedBox(height: 100, child: Center(child: Text("Could not load tourist profile data.")))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tourist Profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(24),
                          image: _profileData!['profilePicUrl'] != null 
                              ? DecorationImage(image: NetworkImage(_profileData!['profilePicUrl']), fit: BoxFit.cover)
                              : null
                        ),
                        child: _profileData!['profilePicUrl'] == null ? const Icon(Icons.person, size: 32, color: Colors.grey) : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${_profileData!['firstName'] ?? _profileData!['name'] ?? 'Unknown'} ${_profileData!['lastName'] ?? ''}".trim(),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _profileData!['idVerificationStatus'] == 'Verified' ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_profileData!['idVerificationStatus'] == 'Verified' ? Icons.check_circle : Icons.warning, size: 14, color: _profileData!['idVerificationStatus'] == 'Verified' ? Colors.green : Colors.orange),
                                  const SizedBox(width: 4),
                                  Text(
                                    _profileData!['idVerificationStatus'] == 'Verified' ? 'ID Verified' : 'ID Not Verified',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _profileData!['idVerificationStatus'] == 'Verified' ? Colors.green : Colors.orange),
                                  ),
                                ],
                              ),
                            )
                          ],
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('CONTACT INFORMATION', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]), child: const Icon(Icons.phone, size: 16, color: AppTheme.primaryAccent)),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Phone Number', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                                Text(_profileData!['phone'] ?? _profileData!['phoneNumber'] ?? 'Not provided', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              ],
                            )
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]), child: const Icon(Icons.email, size: 16, color: AppTheme.primaryAccent)),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Email Address', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                                Text(_profileData!['email'] ?? 'Not provided', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              ],
                            )
                          ],
                        ),
                      ],
                    ),
                  )
                ],
              )
      ),
    );
  }
}
