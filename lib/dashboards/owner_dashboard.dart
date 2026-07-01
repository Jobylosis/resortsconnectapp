import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart' as crypto;
import '../chat_page.dart';
import '../theme_provider.dart';
import '../theme.dart';
import 'package:share_plus/share_plus.dart';

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard>
    with SingleTickerProviderStateMixin {
  final String _cloudName = "dnv6ezitm";
  final String _uploadPreset = "resort_unsigned";

  final _profileFormKey = GlobalKey<FormState>();
  final _activityFormKey = GlobalKey<FormState>();

  final _propNameController = TextEditingController();
  final _propDescController = TextEditingController();
  final _roomsController = TextEditingController();
  final _staffController = TextEditingController();
  final _checkInController = TextEditingController();
  final _checkOutController = TextEditingController();
  final _instrController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _capacityController = TextEditingController();
  final _gcashNumberController = TextEditingController();
  final _gcashNameController = TextEditingController();
  String _propertyType = 'Resort';
  List<String> _imageUrls = [];
  List<String> _propVideoUrls = [];
  List<String> _selectedAmenities = [];

  final List<String> _amenityOptions = [
    'Swimming Pool',
    'Free WiFi',
    'Parking',
    'Restaurant',
    'Bar',
    'Gym',
    'Spa',
    'Beachfront',
    'Air Conditioning',
    'Pet Friendly',
    'Laundry Service'
  ];

  String _existingRoomTitle = "";
  final _activityDescController = TextEditingController();
  final _activityPriceController = TextEditingController();
  final _maxPaxController = TextEditingController();
  String _roomCategory = 'Standard';
  String _roomLocation = 'Riverside (R)';
  String _roomActivity = 'Swimming';
  List<String> _selectedInclusions = [];
  List<String> _activityImageUrls = [];
  String? _activityVideoUrl;

  late TabController _tabController;

  // Stable Queries and Broadcast Streams
  late DatabaseReference _propRef;
  late Stream<DatabaseEvent> _propStream;
  late Query _roomQuery;
  late Query _bookingQuery;
  late Stream<DatabaseEvent> _statsStream;
  late Query _chatQuery;
  late Stream<DatabaseEvent> _chatRoomsStream;
  int _totalUnread = 0;
  int _pendingBookingsCount = 0;
  Map<String, int> _bookingCounts = {'All': 0};

  final List<String> _inclusionOptions = [
    'Refrigerator',
    'Air Conditioning',
    'Smart Tv',
    'Free Wifi',
    'Bathroom essentials',
    'Heater',
    'Sofa',
    'Cabinet',
    'Ceiling fan',
    'Cabinet clothes/foods',
    'Swimming Pool'
  ];

  bool _isSubmitting = false;
  String? _editingActivityKey;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? "unknown";

    _propRef = FirebaseDatabase.instance.ref("properties/$uid");
    _propStream = _propRef.onValue.asBroadcastStream();

    _roomQuery = _propRef.child("roomInventory");

    _bookingQuery = FirebaseDatabase.instance
        .ref("bookings")
        .orderByChild("ownerUid")
        .equalTo(uid);
    _statsStream = _bookingQuery.onValue.asBroadcastStream();

    final chatRoomsRef = FirebaseDatabase.instance.ref("chat_rooms/$uid");
    _chatQuery =
        chatRoomsRef; // Removed orderByChild to ensure everyone shows up
    _chatRoomsStream = chatRoomsRef.onValue.asBroadcastStream();

    _chatRoomsStream.listen((event) {
      if (event.snapshot.exists) {
        int count = 0;
        final data = event.snapshot.value as Map;
        data.forEach((k, v) {
          if (v is Map) {
            count += int.tryParse(v['unreadCount']?.toString() ?? '0') ?? 0;
          }
        });
        if (mounted) setState(() => _totalUnread = count);
      }
    });

    _statsStream.listen((event) {
      if (event.snapshot.exists) {
        int pendingCount = 0;
        Map<String, int> counts = {'All': 0};
        Map data = {};
        final rawData = event.snapshot.value;
        if (rawData is Map) {
          data = rawData;
        } else if (rawData is List) {
          for (int i = 0; i < rawData.length; i++) {
            if (rawData[i] != null) data[i.toString()] = rawData[i];
          }
        }
        
        data.forEach((k, v) {
          if (v is Map) {
            String status = v['status'] ?? 'Pending';
            if (status == 'Pending') pendingCount++;
            counts['All'] = (counts['All'] ?? 0) + 1;
            
            String normalizedStatus = status;
            if (status == 'Declined') normalizedStatus = 'Cancelled';
            counts[normalizedStatus] = (counts[normalizedStatus] ?? 0) + 1;
          }
        });
        if (mounted) {
          setState(() {
            _pendingBookingsCount = pendingCount;
            _bookingCounts = counts;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _pendingBookingsCount = 0;
            _bookingCounts = {'All': 0};
          });
        }
      }
    });

    // Automatically setup property node if it doesn't exist
    _ensurePropertyExists();
  }

  Future<void> _ensurePropertyExists() async {
    final snap = await _propRef.get();
    if (!snap.exists) {
      await _propRef.set({
        'name': '',
        'description': '',
        'type': 'Resort',
        'rooms': 0,
        'staffCount': 0,
        'ownerUid': FirebaseAuth.instance.currentUser?.uid,
        'createdAt': ServerValue.timestamp,
      });
    }
  }

  @override
  void dispose() {
    _propNameController.dispose();
    _propDescController.dispose();
    _roomsController.dispose();
    _staffController.dispose();
    _checkInController.dispose();
    _checkOutController.dispose();
    _instrController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _contactPhoneController.dispose();
    _contactEmailController.dispose();
    _capacityController.dispose();
    _gcashNumberController.dispose();
    _gcashNameController.dispose();
    _activityDescController.dispose();
    _activityPriceController.dispose();
    _maxPaxController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // --- UI Components ---

  Widget _buildTextField(
      TextEditingController controller, String label, IconData icon,
      {int maxLines = 1,
      TextInputType keyboardType = TextInputType.text,
      bool required = true,
      List<TextInputFormatter>? inputFormatters,
      int? maxLength,
      String? placeholder}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: [
        ...?inputFormatters,
        FilteringTextInputFormatter.deny(RegExp(
            r'[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]',
            unicode: true)),
      ],
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: label,
        hintText: placeholder,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        counterText: "",
      ),
      validator: (v) {
        if (required && (v == null || v.trim().isEmpty))
          return '$label is required';
        if (v != null && v.trim().isNotEmpty) {
          final trimmed = v.trim();
          if (keyboardType == TextInputType.number ||
              keyboardType == TextInputType.phone) {
            if (double.tryParse(trimmed) == null &&
                keyboardType == TextInputType.number) return 'Invalid number';
            if (label.contains('Price') && (double.tryParse(trimmed) ?? 0) <= 0)
              return 'Must be > 0';
            if (label.contains('Rooms') && (int.tryParse(trimmed) ?? 0) < 0)
              return 'Cannot be negative';
            if (label.contains('Staff') && (int.tryParse(trimmed) ?? 0) < 0)
              return 'Cannot be negative';
            if (label.contains('Pax') && (int.tryParse(trimmed) ?? 0) <= 0)
              return 'Must be at least 1';
            if (label.contains('Phone') || label.contains('GCash Number')) {
              if (trimmed.length != 11) return 'Must be 11 digits';
              if (!trimmed.startsWith('09')) return 'Must start with 09';
            }
          }
          if (label == 'Name' && trimmed.length < 3) return 'Too short';
        }
        return null;
      },
    );
  }

  // --- Logic Methods ---

  void _clearActivityForm() {
    _existingRoomTitle = "";
    _activityDescController.clear();
    _activityPriceController.clear();
    _maxPaxController.clear();
    _roomCategory = 'Standard';
    _roomLocation = 'Riverside (R)';
    _roomActivity = 'Swimming';
    _selectedInclusions = [];
    _activityImageUrls = [];
    _activityVideoUrl = null;
    _editingActivityKey = null;
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              FirebaseAuth.instance.signOut();
            },
            child: const Text('Logout',
                style: TextStyle(color: AppTheme.primaryAccent)),
          )
        ],
      ),
    );
  }

  void _showDeleteActivityDialog(String key, String title) {
    // Legacy dialog, now we use inline deletion in the UI
  }

  Future<void> _deleteActivityDirectly(String key) async {
    await _propRef.child("roomInventory/$key").remove();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Room deleted successfully.')));
  }

  void _showDeleteBookingDialog(String key, String touristName) {
    // Legacy dialog, replaced with inline confirm
  }

  Future<void> _deleteBookingDirectly(String key) async {
    await FirebaseDatabase.instance.ref("bookings/$key").remove();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking record deleted.')));
  }

  void _viewReceipt(String url) {
    showDialog(
        context: context,
        builder: (context) => Dialog(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              url.startsWith('data:image')
                  ? Image.memory(base64Decode(url.split(',').last),
                      errorBuilder: (c, e, s) => const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text("Error loading image")))
                  : Image.network(url,
                      errorBuilder: (c, e, s) => const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text("Error loading image"))),
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'))
            ])));
  }

  bool _isOverlapping(
      DateTime startA, DateTime endA, DateTime startB, DateTime endB) {
    return startA.isBefore(endB) && endA.isAfter(startB);
  }

  Future<bool> _checkBookingConflict(
      String currentBookingKey, String activityId, Map bA) async {
    try {
      final ownerUid = bA['ownerUid'] ?? FirebaseAuth.instance.currentUser?.uid;
      if (ownerUid == null) return false;

      final snap = await FirebaseDatabase.instance
          .ref("bookings")
          .orderByChild("ownerUid")
          .equalTo(ownerUid)
          .get();

      if (!snap.exists) return false;

      Map allBookings = {};
      dynamic snapValue = snap.value;
      if (snapValue is Map) {
        allBookings = snapValue;
      } else if (snapValue is List) {
        for (int i = 0; i < snapValue.length; i++) {
          if (snapValue[i] != null) allBookings[i.toString()] = snapValue[i];
        }
      }

      String? dateStrA = bA['bookingDate'] ??
          bA['checkInDate'] ??
          bA['date'] ??
          bA['createdAt'];
      if (dateStrA == null) return false;

      DateTime startA;
      if (dateStrA.contains('T') && dateStrA.contains('Z')) {
        startA = DateTime.parse(dateStrA);
      } else {
        startA = DateFormat('MMM dd, yyyy').parse(dateStrA);
      }

      int nightsA = int.tryParse(bA['nights']?.toString() ?? '1') ?? 1;
      DateTime endA = startA.add(Duration(days: nightsA));

      for (var entry in allBookings.entries) {
        if (entry.key == currentBookingKey) continue;
        Map bB = entry.value as Map;

        String status = (bB['status'] ?? '').toString().trim().toLowerCase();
        if (status != 'confirmed' && status != 'checked in') continue;

        final bActivityId = bB['activityId'] ?? bB['roomId'];
        if (bActivityId != activityId) continue;

        String? dateStrB = bB['bookingDate'] ??
            bB['checkInDate'] ??
            bB['date'] ??
            bB['createdAt'];
        if (dateStrB == null) continue;

        DateTime startB;
        if (dateStrB.contains('T') && dateStrB.contains('Z')) {
          startB = DateTime.parse(dateStrB);
        } else {
          startB = DateFormat('MMM dd, yyyy').parse(dateStrB);
        }

        int nightsB = int.tryParse(bB['nights']?.toString() ?? '1') ?? 1;
        DateTime endB = startB.add(Duration(days: nightsB));

        if (_isOverlapping(startA, endA, startB, endB)) {
          return true;
        }
      }
    } catch (e) {
      return false; // Safely fail open instead of crashing
    }
    return false;
  }

  void _updateBookingStatus(String key, String status, Map booking) async {
    String? cancellationReason;

    // Confirmation for non-routine status changes
    if (status == 'Cancelled' || status == 'Reschedule Declined' || status == 'Refund Declined') {
      final reasonController = TextEditingController();
      String actionText = status == 'Cancelled' ? 'cancelling this booking' : (status == 'Reschedule Declined' ? 'declining this reschedule request' : 'declining this refund');
      String titleText = status == 'Cancelled' ? 'Cancel Booking?' : (status == 'Reschedule Declined' ? 'Decline Reschedule?' : 'Decline Refund?');
      
      cancellationReason = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(titleText),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Please provide a reason for $actionText:'),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Back')),
            TextButton(
              onPressed: () => Navigator.pop(context, reasonController.text),
              child: const Text('Confirm', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (cancellationReason == null) return;
    } else if (status == 'Confirmed' ||
        status == 'Checked In' ||
        status == 'Completed' ||
        status == 'Reschedule Approved' ||
        status == 'Refund Approved') {
      bool confirm = await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('$status?'),
              content: Text(
                  'Are you sure you want to mark this booking as $status?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('Confirm',
                      style: TextStyle(
                          color: (status.contains('Approved') ||
                                  status == 'Completed')
                              ? Colors.green
                              : Colors.red)),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirm) return;
    }

    if (status == 'Confirmed') {
      final activityId = booking['activityId'] ?? booking['roomId'];
      if (activityId != null) {
        final hasConflict =
            await _checkBookingConflict(key, activityId, booking);
        if (hasConflict) {
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Booking Conflict'),
                content: const Text(
                    'This booking overlaps with an existing confirmed reservation. You cannot confirm it.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'))
                ],
              ),
            );
          }
          return;
        }

        // Auto-reject overlapping pending bookings
        final ownerUid = FirebaseAuth.instance.currentUser?.uid;
        if (ownerUid != null) {
          final snap = await FirebaseDatabase.instance.ref("bookings").orderByChild("ownerUid").equalTo(ownerUid).get();
          if (snap.exists) {
            Map allBookings = {};
            dynamic val = snap.value;
            if (val is Map) allBookings = val;
            else if (val is List) {
              for(int i=0; i<val.length; i++) if (val[i]!=null) allBookings[i.toString()] = val[i];
            }
            
            String? dateStrA = booking['bookingDate'] ?? booking['checkInDate'] ?? booking['date'] ?? booking['createdAt'];
            if (dateStrA != null) {
              DateTime startA;
              if (dateStrA.contains('T') && dateStrA.contains('Z')) startA = DateTime.parse(dateStrA);
              else startA = DateFormat('MMM dd, yyyy').parse(dateStrA);
              int nightsA = int.tryParse(booking['nights']?.toString() ?? '1') ?? 1;
              DateTime endA = startA.add(Duration(days: nightsA));
              
              for (var entry in allBookings.entries) {
                if (entry.key == key) continue;
                Map bB = entry.value as Map;
                String bStatus = (bB['status'] ?? '').toString().trim().toLowerCase();
                if (bStatus == 'pending') {
                  final bActivityId = bB['activityId'] ?? bB['roomId'];
                  if (bActivityId == activityId) {
                    String? dateStrB = bB['bookingDate'] ?? bB['checkInDate'] ?? bB['date'] ?? bB['createdAt'];
                    if (dateStrB != null) {
                      DateTime startB;
                      if (dateStrB.contains('T') && dateStrB.contains('Z')) startB = DateTime.parse(dateStrB);
                      else startB = DateFormat('MMM dd, yyyy').parse(dateStrB);
                      int nightsB = int.tryParse(bB['nights']?.toString() ?? '1') ?? 1;
                      DateTime endB = startB.add(Duration(days: nightsB));
                      
                      if (_isOverlapping(startA, endA, startB, endB)) {
                        await FirebaseDatabase.instance.ref("bookings/${entry.key}").update({
                          'status': 'Declined',
                          'cancellationReason': 'Room became unavailable for your selected dates.',
                        });
                        String tUidB = bB['touristUid'] ?? bB['userId'] ?? "";
                        if (tUidB.isNotEmpty) {
                          await FirebaseDatabase.instance.ref("notifications/$tUidB").push().set({
                            'title': 'Booking Declined',
                            'message': 'Your booking for "${bB['activityTitle'] ?? bB['roomTitle'] ?? 'Room'}" was declined because the room became unavailable for your selected dates.',
                            'type': 'booking_rejected',
                            'isRead': false,
                            'timestamp': ServerValue.timestamp,
                          });
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    if (status == 'Reschedule Approved') {
      final newDate = booking['requestedRescheduleDate'];
      final newNights = booking['requestedRescheduleNights'];
      if (newDate != null) {
        await FirebaseDatabase.instance.ref("bookings/$key").update({
          'status': 'Confirmed',
          'bookingDate': newDate,
          if (newNights != null) 'nights': newNights,
          'requestedRescheduleDate': null,
          'requestedRescheduleNights': null,
        });
        status = 'Confirmed'; // For notification
      }
    } else if (status == 'Reschedule Declined') {
      await FirebaseDatabase.instance.ref("bookings/$key").update({
        'status': 'Confirmed',
        'requestedRescheduleDate': null,
        'requestedRescheduleNights': null,
        if (cancellationReason != null && cancellationReason!.isNotEmpty)
          'cancellationReason': cancellationReason,
      });
      status = 'Reschedule Request Declined';
    } else {
      await FirebaseDatabase.instance.ref("bookings/$key").update({
        'status': status,
        if (cancellationReason != null && cancellationReason!.isNotEmpty)
          'cancellationReason': cancellationReason,
      });
    }
    String tUid = booking['touristUid'] ?? booking['userId'] ?? "";
    if (tUid.isNotEmpty) {
      String notifType = 'booking_updated';
      if (status == 'Confirmed') {
        notifType = 'booking_accepted';
      } else if (status == 'Cancelled' || status.contains('Declined'))
        notifType = 'booking_rejected';
      else if (status == 'Completed') notifType = 'booking_completed';

      String message =
          'Your booking for "${booking['activityTitle'] ?? booking['roomTitle'] ?? booking['room'] ?? booking['roomId'] ?? "Room"}" is now $status.';
      if (cancellationReason != null && cancellationReason!.isNotEmpty) {
        message += ' Reason: $cancellationReason';
      }

      await FirebaseDatabase.instance.ref("notifications/$tUid").push().set({
        'title': 'Booking Updated',
        'message': message,
        'type': notifType,
        'isRead': false,
        'timestamp': ServerValue.timestamp,
        'bookingId': key,
      });

      // Automatically send a system-generated chat message in the existing chat conversation
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid != null) {
        List<String> ids = [currentUid, tUid];
        ids.sort();
        String chatId = ids.join("_");

        final keyBytes = crypto.sha256.convert(utf8.encode(chatId)).bytes;
        final keyEnc = encrypt.Key(Uint8List.fromList(keyBytes));
        final encrypter =
            encrypt.Encrypter(encrypt.AES(keyEnc, mode: encrypt.AESMode.cbc));
        final ivBytes = crypto.md5
            .convert(utf8.encode(chatId.split('').reversed.join('')))
            .bytes;
        final iv = encrypt.IV(Uint8List.fromList(ivBytes));

        final chatMessage =
            "System: Your booking for \"${booking['activityTitle'] ?? booking['roomTitle'] ?? booking['room'] ?? booking['roomId'] ?? 'Room'}\" is now $status.";
        final encryptedText = encrypter.encrypt(chatMessage, iv: iv).base64;

        await FirebaseDatabase.instance
            .ref("chats/$chatId/messages")
            .push()
            .set({
          'senderUid': currentUid,
          'text': encryptedText,
          'timestamp': ServerValue.timestamp,
          'seen': false,
        });

        await FirebaseDatabase.instance
            .ref("chat_rooms/$currentUid/$tUid")
            .update({
          'lastMessage': encryptedText,
          'timestamp': ServerValue.timestamp,
        });
        await FirebaseDatabase.instance
            .ref("chat_rooms/$tUid/$currentUid")
            .update({
          'lastMessage': encryptedText,
          'timestamp': ServerValue.timestamp,
          'unreadCount': ServerValue.increment(1),
        });
      }
    }
  }

  void _showResetRevenueDialog() {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset All Data?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Enter your password to reset all bookings and revenue data.'),
            const SizedBox(height: 16),
            TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final user = FirebaseAuth.instance.currentUser;
                if (user == null || user.email == null) return;
                final cred = EmailAuthProvider.credential(
                    email: user.email!, password: passwordController.text);
                try {
                  await user.reauthenticateWithCredential(cred);
                  await FirebaseDatabase.instance
                      .ref("bookings")
                      .orderByChild("ownerUid")
                      .equalTo(user.uid)
                      .get()
                      .then((snap) {
                    if (snap.exists) {
                      Map bookings = {};
                      dynamic val = snap.value;
                      if (val is Map) {
                        bookings = val;
                      } else if (val is List) {
                        for (int i = 0; i < val.length; i++) {
                          if (val[i] != null) bookings[i.toString()] = val[i];
                        }
                      }
                      bookings.forEach((k, v) => FirebaseDatabase.instance
                          .ref("bookings/$k")
                          .remove());
                    }
                  });
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Revenue reset.')));
                } catch (e) {
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Verification failed. Wrong password.')));
                }
              },
              child: const Text('Confirm & Reset',
                  style: TextStyle(color: AppTheme.primaryAccent))),
        ],
      ),
    );
  }

  void _showRevenueHistoryDialog(Map bookings) {
    String selectedMonth = "All";
    String selectedYear = "All";
    String? expandedMonth;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setS) {
        Map<String, double> monthlyRevenue = {};
        Map<String, int> roomSales = {};
        Map<String, List<Map<String, dynamic>>> monthDetails = {};
        double filteredTotal = 0;

        List<String> months = ["All"];
        List<String> years = ["All"];

        // Pre-process all months and years available in bookings
        bookings.forEach((key, value) {
          if (value is Map) {
            String? dateStr = value['bookingDate'] ??
                value['checkInDate'] ??
                value['date'] ??
                value['createdAt'];
            if (dateStr != null) {
              try {
                DateTime date;
                if (dateStr.contains('T') && dateStr.contains('Z')) {
                  date = DateTime.parse(dateStr);
                } else {
                  date = DateFormat('MMM dd, yyyy').parse(dateStr);
                }
                String mKey = DateFormat('MMMM yyyy').format(date);
                String yKey = DateFormat('yyyy').format(date);
                if (!months.contains(mKey)) months.add(mKey);
                if (!years.contains(yKey)) years.add(yKey);
              } catch (e) {}
            }
          }
        });

        bookings.forEach((key, value) {
          if (value is Map) {
            String status =
                (value['status'] ?? '').toString().trim().toLowerCase();
            if (status == 'confirmed' ||
                status == 'completed' ||
                status == 'checked in') {
              try {
                String? dateStr = value['bookingDate'] ??
                    value['checkInDate'] ??
                    value['date'] ??
                    value['createdAt'];
                if (dateStr != null) {
                  DateTime date;
                  if (dateStr.contains('T') && dateStr.contains('Z')) {
                    date = DateTime.parse(dateStr);
                  } else {
                    date = DateFormat('MMM dd, yyyy').parse(dateStr);
                  }
                  String monthKey = DateFormat('MMMM yyyy').format(date);
                  String yearKey = DateFormat('yyyy').format(date);

                  bool matchMonth = selectedMonth == "All" || selectedMonth == monthKey;
                  bool matchYear = selectedYear == "All" || selectedYear == yearKey;

                  if (matchMonth && matchYear) {
                    double amount = double.tryParse((value['totalPrice'] ??
                                value['total'] ??
                                value['amount'] ??
                                value['payment'] ??
                                value['price'] ??
                                '0')
                            .toString()
                            .replaceAll(',', '')) ??
                        0;
                    monthlyRevenue[monthKey] =
                        (monthlyRevenue[monthKey] ?? 0) + amount;
                    filteredTotal += amount;

                    String room = value['activityTitle'] ??
                        value['roomTitle'] ??
                        value['room'] ??
                        value['roomId'] ??
                        'Unknown Room';
                    roomSales[room] = (roomSales[room] ?? 0) + 1;

                    if (monthDetails[monthKey] == null)
                      monthDetails[monthKey] = [];
                    monthDetails[monthKey]!.add({
                      'room': room,
                      'date': dateStr,
                      'nights':
                          int.tryParse(value['nights']?.toString() ?? '1') ?? 1,
                      'tourist': value['touristName'] ??
                          value['customerName'] ??
                          value['userName'] ??
                          value['name'] ??
                          value['fullName'] ??
                          'Tourist',
                      'amount': amount,
                      'rawBooking': value,
                    });
                  }
                }
              } catch (e) {/* skip */}
            }
          }
        });

        String bestSeller = roomSales.entries.isEmpty
            ? "No sales yet"
            : roomSales.entries.reduce((a, b) => a.value > b.value ? a : b).key;

        return AlertDialog(
          title: const Text('Sales Report'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filter by Year:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedYear,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                        border: OutlineInputBorder()),
                    items: years
                        .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                        .toList(),
                    onChanged: (v) => setS(() => selectedYear = v!),
                  ),
                  const SizedBox(height: 16),
                  const Text('Filter by Month:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedMonth,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                        border: OutlineInputBorder()),
                    items: months
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setS(() => selectedMonth = v!),
                  ),
                  const Divider(height: 32),
                  Text('Best Selling Room:',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  Text(bestSeller,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: AppTheme.secondaryAccent)),
                  const Divider(height: 32),
                  Row(
                    children: [
                      const Expanded(
                          child: Text('Total Revenue:',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Flexible(
                        child: Text('₱${filteredTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Colors.green,
                                fontSize: 18),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  const Text('Monthly Earnings:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (monthlyRevenue.isEmpty)
                    const Text('No confirmed bookings for this period.')
                  else
                    ...monthlyRevenue.entries.map((e) {
                      List<Map<String, dynamic>> details =
                          monthDetails[e.key] ?? [];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        elevation: 0,
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[850] : Colors.grey[50],
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.withOpacity(0.2))),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => MonthlyReportPage(
                                        monthName: e.key,
                                        details: details,
                                        totalRevenue: e.value)));
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                          child: Text(e.key,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 16),
                                              overflow: TextOverflow.ellipsis)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                            color: Colors.grey.withOpacity(0.2),
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        child: Text(
                                            '${details.length} bookings',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87,
                                                fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                ),
                                Flexible(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text('₱${e.value.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.secondaryAccent,
                                                fontSize: 16),
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward_ios,
                                          size: 14, color: Colors.grey),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'))
          ],
        );
      }),
    );
  }

  // --- Data Methods ---

  List<String> _parseList(dynamic data) {
    if (data == null) return [];
    if (data is List)
      return data.where((e) => e != null).map((e) => e.toString()).toList();
    if (data is Map) {
      var sortedKeys = data.keys.toList()
        ..sort((a, b) => a.toString().compareTo(b.toString()));
      return sortedKeys.map((k) => data[k].toString()).toList();
    }
    return [];
  }

  Future<void> _saveProfile(
      {Function? setModalState, required BuildContext modalContext}) async {
    if (!_profileFormKey.currentState!.validate()) return;
    if (_imageUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please add at least one business photo.')));
      return;
    }

    if (setModalState != null) setModalState(() => _isSubmitting = true);
    setState(() => _isSubmitting = true);
    try {
      await _propRef.update({
        'name': _propNameController.text.trim(),
        'description': _propDescController.text.trim(),
        'type': _propertyType,
        'rooms': int.tryParse(_roomsController.text) ?? 0,
        'staffCount': int.tryParse(_staffController.text) ?? 0,
        'checkInTime': _checkInController.text.trim(),
        'checkOutTime': _checkOutController.text.trim(),
        'bookingInstructions': _instrController.text.trim(),
        'latitude': double.tryParse(_latController.text) ?? 0.0,
        'longitude': double.tryParse(_lngController.text) ?? 0.0,
        'contactPhone': _contactPhoneController.text.trim(),
        'contactEmail': _contactEmailController.text.trim(),
        'maxCapacity': int.tryParse(_capacityController.text) ?? 0,
        'amenities': _selectedAmenities,
        'gcashNumber': _gcashNumberController.text.trim(),
        'gcashName': _gcashNameController.text.trim(),
        'imageUrls': _imageUrls,
        'videoUrls': _propVideoUrls,
        'ownerUid': FirebaseAuth.instance.currentUser?.uid,
        'updatedAt': ServerValue.timestamp,
      });
      if (modalContext.mounted) {
        Navigator.of(modalContext).pop();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Business profile updated!')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (setModalState != null) setModalState(() => _isSubmitting = false);
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitActivity(
      {Function? setModalState, required BuildContext modalContext}) async {
    if (!_activityFormKey.currentState!.validate()) return;
    if (_activityImageUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please add at least one photo for this room.')));
      return;
    }

    if (setModalState != null) setModalState(() => _isSubmitting = true);
    setState(() => _isSubmitting = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      String finalTitle = _existingRoomTitle.trim();

      if (_editingActivityKey == null) {
        String prefix = _roomLocation.isNotEmpty ? _roomLocation[0].toUpperCase() : "R";

        final snap = await _propRef.child("roomInventory").get();
        int maxNum = 0;
        if (snap.exists) {
          final dynamic val = snap.value;
          Map rooms = {};
          if (val is Map) {
            rooms = val;
          } else if (val is List) {
            for (int i = 0; i < val.length; i++) {
              if (val[i] != null) rooms[i.toString()] = val[i];
            }
          }

          rooms.forEach((k, v) {
            if (v != null && v is Map) {
              final String t = v['title']?.toString() ?? "";
              final regex = RegExp('^Room ' + prefix + r'(\d+)');
              final match = regex.firstMatch(t);
              if (match != null) {
                final int? n = int.tryParse(match.group(1)!);
                if (n != null && n > maxNum) maxNum = n;
              }
            }
          });
        }
        finalTitle = "Room $prefix${maxNum + 1}";
      }

      DatabaseReference ref = _editingActivityKey != null
          ? _propRef.child("roomInventory/$_editingActivityKey")
          : _propRef.child("roomInventory").push();

      Map<String, dynamic> data = {
        'title': finalTitle,
        'description': _activityDescController.text.trim(),
        'price': _activityPriceController.text.trim(),
        'maxPax': _maxPaxController.text.trim(),
        'category': _roomCategory,
        'location': _roomLocation,
        'activity': _roomActivity,
        'inclusions': _selectedInclusions,
        'imageUrls': _activityImageUrls,
        'timestamp': ServerValue.timestamp,
      };

      if (_activityVideoUrl != null) {
        data['videoUrl'] = _activityVideoUrl;
      }

      await ref.set(data);

      if (modalContext.mounted) {
        Navigator.of(modalContext).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_editingActivityKey != null
                ? 'Room updated!'
                : 'Room added!')));
      }
      _clearActivityForm();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error saving room: $e')));
    } finally {
      if (setModalState != null) setModalState(() => _isSubmitting = false);
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // --- Cloudinary Methods ---

  Future<String?> _uploadToCloudinary(File file, {bool isVideo = false}) async {
    try {
      final String resourceType = isVideo ? "video" : "image";
      final url = Uri.parse(
          "https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/upload");
      final request = http.MultipartRequest("POST", url)
        ..fields['upload_preset'] = _uploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', file.path));
      final response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        return jsonDecode(responseData)['secure_url'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _pickAndUploadImages(
      {bool isActivity = false, Function? setModalState}) async {
    final picker = ImagePicker();
    final List<XFile> pickedFiles =
        await picker.pickMultiImage(imageQuality: 70);
    if (pickedFiles.isNotEmpty) {
      if (setModalState != null) {
        setModalState(() => _isSubmitting = true);
      } else {
        setState(() => _isSubmitting = true);
      }

      for (var file in pickedFiles) {
        final url = await _uploadToCloudinary(File(file.path));
        if (url != null) {
          if (setModalState != null) {
            setModalState(() {
              if (isActivity) {
                _activityImageUrls.add(url);
              } else {
                _imageUrls.add(url);
              }
            });
          } else {
            setState(() {
              if (isActivity) {
                _activityImageUrls.add(url);
              } else {
                _imageUrls.add(url);
              }
            });
          }
        }
      }
      if (setModalState != null) {
        setModalState(() => _isSubmitting = false);
      } else {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _pickAndUploadVideo(
      {bool isActivity = false, Function? setModalState}) async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickVideo(source: ImageSource.gallery);
    if (file != null) {
      if (setModalState != null) {
        setModalState(() => _isSubmitting = true);
      } else {
        setState(() => _isSubmitting = true);
      }

      final url = await _uploadToCloudinary(File(file.path), isVideo: true);
      if (url != null) {
        if (setModalState != null) {
          setModalState(() {
            if (isActivity) {
              _activityVideoUrl = url;
            } else {
              _propVideoUrls.add(url);
            }
          });
        } else {
          setState(() {
            if (isActivity) {
              _activityVideoUrl = url;
            } else {
              _propVideoUrls.add(url);
            }
          });
        }
      }

      if (setModalState != null) {
        setModalState(() => _isSubmitting = false);
      } else {
        setState(() => _isSubmitting = false);
      }
    }
  }

  // --- QR Scanner ---

  void _openScanner() {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => Scaffold(
                  appBar: AppBar(title: const Text('Scan Booking QR')),
                  body: MobileScanner(
                    onDetect: (capture) async {
                      final List<Barcode> barcodes = capture.barcodes;
                      if (barcodes.isNotEmpty) {
                        final String? code = barcodes.first.rawValue;
                        if (code != null) {
                          Navigator.pop(context);
                          _processScannedCode(code);
                        }
                      }
                    },
                  ),
                )));
  }

  void _processScannedCode(String scannedData) async {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()));

    try {
      // Robust Extraction: Handle both plain IDs and URLs
      String bookingId = scannedData.trim();

      if (bookingId.contains('scan=')) {
        // Correct extraction for the new URL format: domain.com/owner?scan=ID
        bookingId = Uri.parse(bookingId).queryParameters['scan'] ?? bookingId;
      } else if (bookingId.contains('/')) {
        // Fallback for path-based URLs: domain.com/booking/ID
        bookingId = bookingId.split('/').last.split('?').first;
      }

      final snap =
          await FirebaseDatabase.instance.ref("bookings/$bookingId").get();
      if (mounted) Navigator.pop(context);

      if (snap.exists) {
        final Map booking = snap.value as Map;
        // Verify this booking belongs to this owner
        final user = FirebaseAuth.instance.currentUser;
        if (booking['ownerUid'] != user?.uid) {
          _showErrorDialog("This booking does not belong to your property.");
          return;
        }

        _showBookingDetailsDialog(bookingId, booking);
      } else {
        _showErrorDialog("Invalid QR Code. Booking '$bookingId' not found.");
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showErrorDialog("Error: $e");
    }
  }

  void _showCheckoutConfirmation(String key, Map b) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Check-out?'),
        content: const Text(
            'Are you sure you want to complete the check-out for this guest?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _updateBookingStatus(key, 'Completed', b);
            },
            child: const Text('Confirm Check-out',
                style: TextStyle(
                    color: Colors.green, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showBookingDetailsDialog(String key, Map b) {
    String status = (b['status'] ?? 'Pending').toString().trim().toLowerCase();
    Color c = status == 'confirmed'
        ? Colors.green
        : (status == 'cancelled'
            ? AppTheme.primaryAccent
            : (status == 'completed'
                ? Colors.blue
                : (status == 'checked in' ? Colors.indigo : Colors.orange)));
    List addons = b['selectedAddons'] is List ? b['selectedAddons'] : [];

    String? bookingDate =
        b['bookingDate'] ?? b['checkInDate'] ?? b['date'] ?? b['createdAt'];
    if (bookingDate != null &&
        bookingDate.contains('T') &&
        bookingDate.contains('Z')) {
      try {
        bookingDate =
            DateFormat('MMM dd, yyyy').format(DateTime.parse(bookingDate));
      } catch (e) {}
    }

    String dateRange = bookingDate ?? 'N/A';
    try {
      if (bookingDate != null) {
        DateTime start = DateFormat('MMM dd, yyyy').parse(bookingDate);
        int nights = int.tryParse(b['nights'].toString()) ?? 1;
        DateTime end = start.add(Duration(days: nights));
        dateRange =
            "$bookingDate - ${DateFormat('MMM dd, yyyy').format(end)} ($nights Nights)";
      }
    } catch (e) {}

    double total = double.tryParse((b['totalPrice'] ??
                b['total'] ??
                b['amount'] ??
                b['payment'] ??
                b['price'] ??
                0)
            .toString()) ??
        0;
    double paid = double.tryParse((b['amountPaid'] ?? 0).toString()) ?? 0;
    String payOption =
        (b['paymentOption'] ?? b['paymentMethod'] ?? '').toString();

    // Fallback calculation for older records
    if (paid == 0 && total > 0) {
      if (payOption.contains('30%')) {
        paid = total * 0.3;
      } else {
        paid = total;
      }
    }
    double balance = total - paid;

    String? r = (b['gcashReceipt'] != null &&
            b['gcashReceipt'].toString().trim().isNotEmpty)
        ? b['gcashReceipt']
        : (b['paymentReceiptDataUrl']);
    String? photo = b['touristProfilePic'];
    String touristName = b['touristName'] ??
        b['customerName'] ??
        b['userName'] ??
        b['name'] ??
        b['fullName'] ??
        'N/A';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Booking Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  backgroundImage: photo != null ? NetworkImage(photo) : null,
                  child: photo == null ? const Icon(Icons.person) : null,
                ),
                title: Text(touristName,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("Tourist"),
              ),
              const Divider(),
              _detailRow(
                  "Room",
                  b['activityTitle'] ??
                      b['roomTitle'] ??
                      b['activityName'] ??
                      b['room'] ??
                      b['roomId'] ??
                      'N/A'),
              _detailRow("Date Range", dateRange),
              const Divider(),
              _detailRow("Total Price", "₱${total.toStringAsFixed(2)}"),
              _detailRow("Amount Paid", "₱${paid.toStringAsFixed(2)}",
                  isHighlight: true),
              _detailRow("Remaining", "₱${balance.toStringAsFixed(2)}",
                  isError: balance > 0),
              _detailRow(
                  "Method",
                  b['paymentMethod'] ??
                      b['paymentOption'] ??
                      b['payment'] ??
                      b['paymentType'] ??
                      'N/A'),
              const SizedBox(height: 8),
              if (addons.isNotEmpty)
                Text("Add-ons: ${addons.join(', ')}",
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold)),
              if (b['cancellationReason'] != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text("Cancel Reason: ${b['cancellationReason']}",
                        style: const TextStyle(
                            color: AppTheme.primaryAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12))),
              if (status == 'reschedule requested')
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                        "Reschedule to: ${b['requestedRescheduleDate']} (${b['requestedRescheduleNights'] ?? b['nights']} Night/s)",
                        style: const TextStyle(
                            color: Colors.deepPurple,
                            fontWeight: FontWeight.bold,
                            fontSize: 13))),
              if (status == 'refund requested')
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Refund Reason: ${b['refundReason']}",
                            style: const TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                        const SizedBox(height: 4),
                        FutureBuilder(
                          future: FirebaseDatabase.instance
                              .ref('users/${b['touristUid'] ?? ''}')
                              .get(),
                          builder: (context, AsyncSnapshot snap) {
                            if (snap.connectionState ==
                                ConnectionState.waiting) {
                              return const Text(
                                  "Send To: Loading GCash details...",
                                  style: TextStyle(
                                      color: Colors.redAccent, fontSize: 13));
                            }
                            String gn = (b['gcashName'] != null &&
                                    b['gcashName'].toString().isNotEmpty)
                                ? b['gcashName']
                                : 'N/A';
                            String gnum = (b['gcashNumber'] != null &&
                                    b['gcashNumber'].toString().isNotEmpty)
                                ? b['gcashNumber']
                                : 'N/A';

                            if (snap.hasData && snap.data!.exists) {
                              final u = snap.data!.value as Map;
                              if (u['gcashName'] != null &&
                                  u['gcashName'].toString().trim().isNotEmpty)
                                gn = u['gcashName'];
                              if (u['gcashNumber'] != null &&
                                  u['gcashNumber'].toString().trim().isNotEmpty)
                                gnum = u['gcashNumber'];
                            }
                            return Text("Send To: $gn ($gnum)",
                                style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13));
                          },
                        ),
                      ],
                    )),
              const Divider(),
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: c.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(b['status'] ?? 'Pending',
                      style: TextStyle(color: c, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close')),
                if (r != null)
                  TextButton.icon(
                      onPressed: () => _viewReceipt(r),
                      icon: const Icon(Icons.receipt_long, size: 16),
                      label: const Text('View Proof')),
                if (status == 'pending') ...[
                  TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _updateBookingStatus(key, 'Cancelled', b);
                      },
                      style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primaryAccent),
                      child: const Text('Decline')),
                  ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _updateBookingStatus(key, 'Confirmed', b);
                      },
                      child: const Text('Confirm')),
                ],
                if (status == 'reschedule requested') ...[
                  TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _updateBookingStatus(key, 'Reschedule Declined', b);
                      },
                      style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primaryAccent),
                      child: const Text('Decline')),
                  ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _updateBookingStatus(key, 'Reschedule Approved', b);
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green),
                      child: const Text('Approve Reschedule')),
                ],
                if (status == 'refund requested') ...[
                  TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _updateBookingStatus(key, 'Refund Declined', b);
                      },
                      style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primaryAccent),
                      child: const Text('Decline')),
                  ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _updateBookingStatus(key, 'Refund Approved', b);
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green),
                      child: const Text('Approve Refund')),
                ],
                if (status == 'confirmed')
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _updateBookingStatus(key, 'Checked In', b);
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo),
                    child: const Text('CHECK IN'),
                  ),
                if (status == 'checked in')
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showCheckoutConfirmation(key, b);
                    },
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: const Text('CHECK OUT & COMPLETE'),
                  ),
              ])
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value,
          {bool isHighlight = false, bool isError = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text("$label: ", style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
              child: Text(value,
                  style: TextStyle(
                    color: isError
                        ? AppTheme.primaryAccent
                        : (isHighlight ? Colors.green[700] : null),
                    fontWeight:
                        (isHighlight || isError) ? FontWeight.bold : null,
                  )))
        ]),
      );

  void _showErrorDialog(String msg) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text("Error"),
                content: Text(msg),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("OK"))
                ]));
  }

  Future<void> _pickLocationFromMap() async {
    LatLng currentLoc = const LatLng(14.5995, 120.9842); // Default Manila
    if (_latController.text.isNotEmpty && _lngController.text.isNotEmpty) {
      final lat = double.tryParse(_latController.text);
      final lng = double.tryParse(_lngController.text);
      if (lat != null && lng != null) {
        currentLoc = LatLng(lat, lng);
      }
    }

    LatLng? selectedLoc = await showDialog<LatLng>(
      context: context,
      builder: (ctx) {
        LatLng tempLoc = currentLoc;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Pick Location'),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: tempLoc,
                    initialZoom: 13.0,
                    onTap: (tapPosition, point) {
                      setDialogState(() {
                        tempLoc = point;
                      });
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: tempLoc,
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.location_pin,
                              color: Colors.red, size: 40),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, tempLoc),
                  child: const Text('Select'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selectedLoc != null) {
      setState(() {
        _latController.text = selectedLoc.latitude.toStringAsFixed(6);
        _lngController.text = selectedLoc.longitude.toStringAsFixed(6);
      });
    }
  }

  // --- UI Component Builders ---

  void _showEditPropertySheet() {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
        builder: (context) => StatefulBuilder(
            builder: (context, setModalState) => Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                    left: 24,
                    right: 24,
                    top: 24),
                child: Form(
                    key: _profileFormKey,
                    child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('Edit Business Details',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 80,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _imageUrls.length + 1,
                            itemBuilder: (context, index) {
                              if (index == _imageUrls.length)
                                return GestureDetector(
                                    onTap: () async {
                                      await _pickAndUploadImages(
                                          setModalState: setModalState);
                                    },
                                    child: Container(
                                        width: 80,
                                        margin:
                                            const EdgeInsets.only(right: 12),
                                        decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surface,
                                            borderRadius:
                                                BorderRadius.circular(15),
                                            border: Border.all(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withOpacity(0.3))),
                                        child: Icon(Icons.add_a_photo,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            size: 20)));
                              return Stack(children: [
                                Container(
                                    width: 80,
                                    margin: const EdgeInsets.only(right: 12),
                                    decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(15),
                                        image: DecorationImage(
                                            image:
                                                NetworkImage(_imageUrls[index]),
                                            fit: BoxFit.cover))),
                                Positioned(
                                    top: 2,
                                    right: 14,
                                    child: GestureDetector(
                                        onTap: () {
                                          setModalState(() {
                                            _imageUrls.removeAt(index);
                                          });
                                        },
                                        child: const CircleAvatar(
                                            radius: 8,
                                            backgroundColor:
                                                AppTheme.primaryAccent,
                                            child: Icon(Icons.close,
                                                size: 10,
                                                color: Colors.white))))
                              ]);
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await _pickAndUploadVideo(
                                setModalState: setModalState);
                          },
                          icon: const Icon(Icons.video_call),
                          label: Text(_propVideoUrls.isNotEmpty
                              ? 'Videos Attached'
                              : 'Add Property Video'),
                          style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  Theme.of(context).colorScheme.primary,
                              side: BorderSide(
                                  color:
                                      Theme.of(context).colorScheme.primary)),
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                            _propNameController, 'Name', Icons.business,
                            maxLength: 50),
                        const SizedBox(height: 12),
                        _buildTextField(_propDescController, 'Description',
                            Icons.description,
                            maxLines: 2, maxLength: 500),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: _buildTextField(_checkInController,
                                  'Check-in', Icons.login_rounded,
                                  placeholder: '2:00 PM')),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _buildTextField(_checkOutController,
                                  'Check-out', Icons.logout_rounded,
                                  placeholder: '12:00 PM')),
                        ]),
                        const SizedBox(height: 12),
                        _buildTextField(
                            _instrController,
                            'Booking Instructions / House Rules',
                            Icons.list_alt_rounded,
                            maxLines: 3,
                            required: false,
                            maxLength: 1000),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: _buildTextField(_latController, 'Latitude',
                                  Icons.location_on_rounded,
                                  keyboardType: TextInputType.number,
                                  placeholder: 'e.g. 14.5995')),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _buildTextField(_lngController,
                                  'Longitude', Icons.location_on_rounded,
                                  keyboardType: TextInputType.number,
                                  placeholder: 'e.g. 120.9842')),
                        ]),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await _pickLocationFromMap();
                            },
                            icon: const Icon(Icons.map_rounded),
                            label: const Text('Pick Location from Map'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(_contactPhoneController,
                            'Contact Phone', Icons.phone_callback_rounded,
                            keyboardType: TextInputType.phone, maxLength: 11),
                        const SizedBox(height: 12),
                        _buildTextField(_contactEmailController,
                            'Contact Email', Icons.contact_mail_rounded,
                            keyboardType: TextInputType.emailAddress),
                        const SizedBox(height: 12),
                        _buildTextField(
                            _capacityController,
                            'Total Guest Capacity',
                            Icons.person_add_alt_1_rounded,
                            keyboardType: TextInputType.number),
                        const SizedBox(height: 20),
                        const Text('Amenities',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: _amenityOptions
                              .map((amenity) => FilterChip(
                                    label: Text(amenity,
                                        style: const TextStyle(fontSize: 12)),
                                    selected:
                                        _selectedAmenities.contains(amenity),
                                    onSelected: (selected) {
                                      setModalState(() {
                                        if (selected) {
                                          _selectedAmenities.add(amenity);
                                        } else {
                                          _selectedAmenities.remove(amenity);
                                        }
                                      });
                                    },
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: _buildTextField(
                                  _roomsController, 'Rooms', Icons.room,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  maxLength: 4)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _buildTextField(
                                  _staffController, 'Staff', Icons.groups,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  maxLength: 4))
                        ]),
                        const SizedBox(height: 12),
                        _buildTextField(_gcashNumberController, 'GCash Number',
                            Icons.phone_android,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            maxLength: 11),
                        const SizedBox(height: 12),
                        _buildTextField(
                            _gcashNameController, 'GCash Name', Icons.badge,
                            maxLength: 50),
                        const SizedBox(height: 24),
                        ElevatedButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => _saveProfile(
                                    setModalState: setModalState,
                                    modalContext: context),
                            style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary),
                            child: const Text('UPDATE PROFILE')),
                        const SizedBox(height: 24),
                      ]),
                    )))));
  }

  void _showActivitySheet() {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
        builder: (modalContext) => StatefulBuilder(
            builder: (context, setS) => Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                    left: 24,
                    right: 24,
                    top: 24),
                child: Form(
                    key: _activityFormKey,
                    child: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                          _editingActivityKey != null
                              ? 'Edit Room'
                              : 'New Room',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 24),
                      SizedBox(
                          height: 80,
                          child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _activityImageUrls.length + 1,
                              itemBuilder: (context, i) {
                                if (i == _activityImageUrls.length)
                                  return GestureDetector(
                                      onTap: () async {
                                        await _pickAndUploadImages(
                                            isActivity: true,
                                            setModalState: setS);
                                      },
                                      child: Container(
                                          width: 80,
                                          margin:
                                              const EdgeInsets.only(right: 12),
                                          decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surface,
                                              borderRadius:
                                                  BorderRadius.circular(15),
                                              border: Border.all(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withOpacity(0.3))),
                                          child: Icon(Icons.add_a_photo,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              size: 20)));
                                return Stack(children: [
                                  Container(
                                      width: 80,
                                      margin: const EdgeInsets.only(right: 12),
                                      decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(15),
                                          image: DecorationImage(
                                              image: NetworkImage(
                                                  _activityImageUrls[i]),
                                              fit: BoxFit.cover))),
                                  Positioned(
                                      top: 2,
                                      right: 14,
                                      child: GestureDetector(
                                          onTap: () {
                                            setS(() {
                                              _activityImageUrls.removeAt(i);
                                            });
                                          },
                                          child: const CircleAvatar(
                                              radius: 8,
                                              backgroundColor:
                                                  AppTheme.primaryAccent,
                                              child: Icon(Icons.close,
                                                  size: 10,
                                                  color: Colors.white))))
                                ]);
                              })),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                          onPressed: () async {
                            await _pickAndUploadVideo(
                                isActivity: true, setModalState: setS);
                          },
                          icon: const Icon(Icons.video_call),
                          label: Text(_activityVideoUrl != null
                              ? 'Video Added'
                              : 'Add Video'),
                          style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  Theme.of(context).colorScheme.primary,
                              side: BorderSide(
                                  color:
                                      Theme.of(context).colorScheme.primary))),
                      const SizedBox(height: 20),

                      StreamBuilder<DatabaseEvent>(
                        stream: FirebaseDatabase.instance
                            .ref("master_data/activities")
                            .onValue,
                        builder: (context, snapshot) {
                          List<String> activityOptions = [
                            'Swimming',
                            'Kayaking',
                            'Camping',
                            'Island Hopping',
                            'None'
                          ];
                          if (snapshot.hasData &&
                              snapshot.data!.snapshot.exists) {
                            final val = snapshot.data!.snapshot.value;
                            if (val is Map) {
                              activityOptions =
                                  val.values.map((e) => e.toString()).toList();
                            } else if (val is List)
                              activityOptions = val
                                  .where((e) => e != null)
                                  .map((e) => e.toString())
                                  .toList();
                          }
                          if (!activityOptions.contains(_roomActivity))
                            _roomActivity = activityOptions.first;

                          return DropdownButtonFormField<String>(
                            initialValue: _roomActivity,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Primary Activity',
                                prefixIcon: Icon(Icons.beach_access)),
                            items: activityOptions
                                .map((a) =>
                                    DropdownMenuItem(value: a, child: Text(a)))
                                .toList(),
                            onChanged: (v) => setS(() => _roomActivity = v!),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: _roomCategory,
                              decoration: const InputDecoration(labelText: 'Category (Type)'),
                              onChanged: (v) => _roomCategory = v,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              initialValue: _roomLocation,
                              decoration: const InputDecoration(
                                  labelText: 'Location in Property (Type)',
                                  hintText: 'e.g. Penthouse, Riverside'
                              ),
                              onChanged: (v) => _roomLocation = v,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                          _maxPaxController, 'Max Pax', Icons.people,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          maxLength: 2),
                      const SizedBox(height: 12),
                      _buildTextField(
                          _activityPriceController, 'Price (₱)', Icons.payments,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          maxLength: 6),
                      const SizedBox(height: 20),
                      const Text('Inclusions',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: _inclusionOptions
                            .map((inclusion) => FilterChip(
                                  label: Text(inclusion,
                                      style: const TextStyle(fontSize: 12)),
                                  selected:
                                      _selectedInclusions.contains(inclusion),
                                  onSelected: (selected) {
                                    setS(() {
                                      if (selected) {
                                        _selectedInclusions.add(inclusion);
                                      } else {
                                        _selectedInclusions.remove(inclusion);
                                      }
                                    });
                                  },
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(_activityDescController,
                          'Additional Details', Icons.notes,
                          maxLines: 2, required: false, maxLength: 200),
                      const SizedBox(height: 32),
                      ElevatedButton(
                          onPressed: _isSubmitting
                              ? null
                              : () => _submitActivity(
                                  setModalState: setS, modalContext: context),
                          style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary),
                          child: _isSubmitting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Text('SAVE ROOM',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1))),
                      const SizedBox(height: 32)
                    ]))))));
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        title: StreamBuilder<DatabaseEvent>(
            stream: _propStream,
            builder: (context, snapshot) {
              String name = "Business";
              String type = "";
              String? img;
              if (snapshot.hasData && snapshot.data!.snapshot.exists) {
                Map data = snapshot.data!.snapshot.value as Map;
                name = data['name'] ?? "Business";
                type = data['type'] ?? "";
                List imgs = _parseList(data['imageUrls']);
                if (imgs.isNotEmpty) img = imgs[0];
              }
              return Row(children: [
                CircleAvatar(
                    radius: 24,
                    backgroundColor:
                        Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    backgroundImage: img != null ? NetworkImage(img) : null,
                    child: img == null ? const Icon(Icons.business) : null),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      Text(name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900)),
                      if (type.isNotEmpty)
                        Text(type,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold))
                    ]))
              ]);
            }),
        actions: [
          IconButton(
            icon: Icon(themeProvider.themeMode == ThemeMode.dark
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded),
            color: Theme.of(context).colorScheme.primary,
            onPressed: () => themeProvider.toggleTheme(),
          ),
          IconButton(
            icon: const Icon(Icons.edit_note_rounded),
            color: Theme.of(context).colorScheme.primary,
            onPressed: () async {
              final snap = await _propRef.get();
              if (snap.exists) {
                Map data = snap.value as Map;
                _propNameController.text = data['name'] ?? '';
                _propDescController.text = data['description'] ?? '';
                _roomsController.text = (data['rooms'] ?? 0).toString();
                _staffController.text = (data['staffCount'] ?? 0).toString();
                _checkInController.text = data['checkInTime'] ?? '';
                _checkOutController.text = data['checkOutTime'] ?? '';
                _instrController.text = data['bookingInstructions'] ?? '';
                _latController.text = (data['latitude'] ?? '').toString();
                _lngController.text = (data['longitude'] ?? '').toString();
                _contactPhoneController.text = data['contactPhone'] ?? '';
                _contactEmailController.text = data['contactEmail'] ?? '';
                _capacityController.text =
                    (data['maxCapacity'] ?? 0).toString();
                _selectedAmenities = _parseList(data['amenities']);
                _gcashNumberController.text = data['gcashNumber'] ?? '';
                _gcashNameController.text = data['gcashName'] ?? '';
                _imageUrls = _parseList(data['imageUrls']);
                _propVideoUrls = _parseList(data['videoUrls']);
                _propertyType = data['type'] ?? 'Resort';
              } else {
                _propNameController.clear();
                _propDescController.clear();
                _roomsController.text = '0';
                _staffController.text = '0';
                _checkInController.clear();
                _checkOutController.clear();
                _instrController.clear();
                _latController.clear();
                _lngController.clear();
                _contactPhoneController.clear();
                _contactEmailController.clear();
                _capacityController.text = '0';
                _selectedAmenities = [];
                _gcashNumberController.clear();
                _gcashNameController.clear();
                _imageUrls = [];
                _propVideoUrls = [];
                _propertyType = 'Resort';
              }
              _showEditPropertySheet();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.red),
            onPressed: () => _showLogoutDialog(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'Rooms'),
            Tab(
                child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Bookings'),
                if (_pendingBookingsCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(_pendingBookingsCount.toString(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ]
              ],
            )),
            Tab(
                child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Chat'),
                if (_totalUnread > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppTheme.primaryAccent,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(_totalUnread.toString(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ]
              ],
            )),
          ],
          labelColor: Theme.of(context).colorScheme.primary,
          indicatorColor: Theme.of(context).colorScheme.primary,
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            RoomsTab(
              propStream: _propStream,
              roomQuery: _roomQuery,
              statsStream: _statsStream,
              onAddRoom: () {
                _clearActivityForm();
                _showActivitySheet();
              },
              onEditRoom: (key, act) {
                _existingRoomTitle = act['title'] ?? '';
                _activityDescController.text = act['description'] ?? '';
                _activityPriceController.text = (act['price'] ?? '').toString();
                _maxPaxController.text = (act['maxPax'] ?? '').toString();
                _roomCategory = act['category'] ?? 'Standard';
                _roomLocation = act['location'] ?? 'Riverside (R)';
                _roomActivity = act['activity'] ?? 'Swimming';
                _selectedInclusions = _parseList(act['inclusions']);
                _activityImageUrls = _parseList(act['imageUrls']);
                _activityVideoUrl = act['videoUrl'];
                _editingActivityKey = key;
                _showActivitySheet();
              },
              onDeleteRoom: (key, title) => _deleteActivityDirectly(key),
              onShowRevenue: _showRevenueHistoryDialog,
              onResetRevenue: _showResetRevenueDialog,
              onGoToBookings: () => _tabController.animateTo(1),
            ),
            BookingsTab(
              bookingQuery: _bookingQuery,
              bookingCounts: _bookingCounts,
              onDeleteRecord: (key, name) => _deleteBookingDirectly(key),
              onScanQR: _openScanner,
              onTapBooking: (key, booking) =>
                  _showBookingDetailsDialog(key, booking),
            ),
            ChatTab(chatQuery: _chatQuery),
          ],
        ),
      ),
    );
  }
}

// --- Tab Widgets ---

class RoomsTab extends StatefulWidget {
  final Stream<DatabaseEvent> propStream;
  final Query roomQuery;
  final Stream<DatabaseEvent> statsStream;
  final VoidCallback onAddRoom;
  final Function(String, Map) onEditRoom;
  final Function(String, String) onDeleteRoom;
  final Function(Map) onShowRevenue;
  final VoidCallback onResetRevenue;
  final VoidCallback onGoToBookings;

  const RoomsTab(
      {super.key,
      required this.propStream,
      required this.roomQuery,
      required this.statsStream,
      required this.onAddRoom,
      required this.onEditRoom,
      required this.onDeleteRoom,
      required this.onShowRevenue,
      required this.onResetRevenue,
      required this.onGoToBookings});

  @override
  State<RoomsTab> createState() => _RoomsTabState();
}

class _RoomsTabState extends State<RoomsTab>
    with AutomaticKeepAliveClientMixin {
  String? _deletingRoomKey;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<DatabaseEvent>(
        stream: widget.propStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.snapshot.exists) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.business_center_outlined,
                      size: 80, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text("No property found.",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text("Tap the edit icon above to setup your business.",
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          Map propData = snapshot.data!.snapshot.value as Map;

          return ListView(
              padding: const EdgeInsets.symmetric(vertical: 20),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Expanded(
                                child: _buildStatItem(
                                    'Rooms',
                                    (propData['rooms'] ?? 0).toString(),
                                    Icons.meeting_room_rounded)),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: StreamBuilder<DatabaseEvent>(
                                  stream: widget.statsStream,
                                  builder: (context, bSnapshot) {
                                    double totalRevenue = 0;
                                    Map bookings = {};
                                    int totalBookings = 0;
                                    if (bSnapshot.hasData &&
                                        bSnapshot.data!.snapshot.exists) {
                                      dynamic bValue =
                                          bSnapshot.data!.snapshot.value;
                                      if (bValue is Map) {
                                        bookings = bValue;
                                      } else if (bValue is List) {
                                        for (int i = 0;
                                            i < bValue.length;
                                            i++) {
                                          if (bValue[i] != null)
                                            bookings[i.toString()] = bValue[i];
                                        }
                                      }
                                      totalBookings = bookings.length;
                                      bookings.forEach((key, value) {
                                        if (value is Map) {
                                          String status =
                                              (value['status'] ?? '')
                                                  .toString()
                                                  .trim()
                                                  .toLowerCase();
                                          if (status == 'confirmed' ||
                                              status == 'completed' ||
                                              status == 'checked in') {
                                            totalRevenue += double.tryParse(
                                                    (value['totalPrice'] ??
                                                            value['total'] ??
                                                            value['amount'] ??
                                                            value['payment'] ??
                                                            value['price'] ??
                                                            '0')
                                                        .toString()
                                                        .replaceAll(',', '')) ??
                                                0;
                                          }
                                        }
                                      });
                                    }
                                    return Row(
                                      children: [
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: widget.onGoToBookings,
                                            child: _buildStatItem(
                                                'Bookings',
                                                totalBookings.toString(),
                                                Icons.book_online_rounded),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () =>
                                                widget.onShowRevenue(bookings),
                                            onLongPress: widget.onResetRevenue,
                                            child: _buildStatItem(
                                                'Revenue',
                                                '₱${totalRevenue.toStringAsFixed(0)}',
                                                Icons.payments_rounded),
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                            ),
                          ]),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                          child: Text('Manage Rooms',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5),
                              overflow: TextOverflow.ellipsis)),
                      ElevatedButton.icon(
                        onPressed: widget.onAddRoom,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Rooms'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          minimumSize: const Size(120, 44),
                        ),
                      ),
                    ],
                  ),
                ),
                FirebaseAnimatedList(
                    query: widget.roomQuery,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                    sort: (a, b) {
                      final Map aVal = (a.value ?? {}) as Map;
                      final Map bVal = (b.value ?? {}) as Map;

                      String aTitle = (aVal['title'] ?? '').toString();
                      String bTitle = (bVal['title'] ?? '').toString();
                      int titleCompare = aTitle.compareTo(bTitle);
                      if (titleCompare != 0) return titleCompare;

                      num aTime = aVal['timestamp'] ?? 0;
                      num bTime = bVal['timestamp'] ?? 0;
                      return bTime.compareTo(aTime);
                    },
                    itemBuilder: (context, snapshot, animation, index) {
                      if (!snapshot.exists || snapshot.value is! Map)
                        return const SizedBox();
                      Map act = snapshot.value as Map;
                      String key = snapshot.key!;
                      List imgs = (act['imageUrls'] is List)
                          ? List.from(act['imageUrls'])
                          : [];
                      String? firstImg = imgs.isNotEmpty ? imgs[0] : null;
                      return FadeTransition(
                          opacity: animation,
                          child: Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                  contentPadding: const EdgeInsets.all(12),
                                  leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: firstImg != null
                                          ? Image.network(firstImg,
                                              width: 60,
                                              height: 60,
                                              fit: BoxFit.cover,
                                              errorBuilder: (c, e, s) =>
                                                  Container(
                                                      width: 60,
                                                      height: 60,
                                                      color: Colors.grey[200],
                                                      child: const Icon(
                                                          Icons.broken_image)))
                                          : Container(
                                              width: 60,
                                              height: 60,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surface,
                                              child: const Icon(
                                                  Icons.local_activity))),
                                  title: Text(act['title'] ?? '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  subtitle: Text('₱${act['price']}',
                                      style: TextStyle(
                                          color: Theme.of(context).colorScheme.primary,
                                          fontWeight: FontWeight.w900)),
                                  trailing: _deletingRoomKey == key
                                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                                          TextButton(
                                              onPressed: () => setState(() =>
                                                  _deletingRoomKey = null),
                                              child: const Text('Cancel',
                                                  style:
                                                      TextStyle(fontSize: 12))),
                                          TextButton(
                                              onPressed: () {
                                                widget.onDeleteRoom(
                                                    key, act['title'] ?? '');
                                                setState(() =>
                                                    _deletingRoomKey = null);
                                              },
                                              child: const Text('Delete',
                                                  style: TextStyle(
                                                      color: AppTheme
                                                          .primaryAccent,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold))),
                                        ])
                                      : Row(mainAxisSize: MainAxisSize.min, children: [
                                          IconButton(
                                              icon: const Icon(
                                                  Icons.edit_rounded,
                                                  color: Colors.blue,
                                                  size: 20),
                                              onPressed: () =>
                                                  widget.onEditRoom(key, act)),
                                          IconButton(
                                              icon: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  color: AppTheme.primaryAccent,
                                                  size: 20),
                                              onPressed: () => setState(() =>
                                                  _deletingRoomKey = key)),
                                        ]))));
                    }),
              ]);
        });
  }

  Widget _buildStatItem(String label, String value, IconData icon) =>
      Column(children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 24),
        const SizedBox(height: 8),
        FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 18))),
        Text(label,
            style: Theme.of(context).textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis)
      ]);
}

class BookingsTab extends StatefulWidget {
  final Query bookingQuery;
  final Map<String, int> bookingCounts;
  final Function(String, String) onDeleteRecord;
  final VoidCallback onScanQR;
  final Function(String, Map) onTapBooking;

  const BookingsTab(
      {super.key,
      required this.bookingQuery,
      required this.bookingCounts,
      required this.onDeleteRecord,
      required this.onScanQR,
      required this.onTapBooking});

  @override
  State<BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<BookingsTab>
    with AutomaticKeepAliveClientMixin {
  String _filter = "All";
  String? _deletingBookingKey;
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      "All",
                      "Pending",
                      "Confirmed",
                      "Checked In",
                      "Completed",
                      "Reschedule Requested",
                      "Refund Requested",
                      "Refund Approved",
                      "Refund Declined",
                      "Declined",
                      "Cancelled"
                    ]
                        .map((f) {
                          int count = widget.bookingCounts[f] ?? 0;
                          String labelText = f;
                          if (f == 'Reschedule Requested') labelText = 'Reschedule Requests';
                          if (f == 'Refund Requested') labelText = 'Refund Requests';
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text("$labelText ($count)",
                                  style: TextStyle(
                                      color:
                                          _filter == f ? Colors.white : null,
                                      fontSize: 12)),
                              selected: _filter == f,
                              selectedColor:
                                  Theme.of(context).colorScheme.primary,
                              onSelected: (s) {
                                if (s) setState(() => _filter = f);
                              },
                            ),
                          );
                        })
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAliasWithSaveLayer,
                child: MaterialButton(
                  onPressed: widget.onScanQR,
                  color: AppTheme.primaryAccent,
                  elevation: 0,
                  highlightElevation: 0,
                  focusElevation: 0,
                  hoverElevation: 0,
                  disabledElevation: 0,
                  minWidth: 44,
                  height: 44,
                  padding: EdgeInsets.zero,
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FirebaseAnimatedList(
            query: widget.bookingQuery,
            sort: (a, b) {
              final Map aVal = (a.value ?? {}) as Map;
              final Map bVal = (b.value ?? {}) as Map;
              
              if (_filter == "All") {
                 List<String> attention = ['Pending', 'Reschedule Requested', 'Refund Requested'];
                 String aStatus = aVal['status'] ?? 'Pending';
                 String bStatus = bVal['status'] ?? 'Pending';
                 bool aNeeds = attention.contains(aStatus);
                 bool bNeeds = attention.contains(bStatus);
                 if (aNeeds && !bNeeds) return -1;
                 if (!aNeeds && bNeeds) return 1;
              }

              final aTime = aVal['timestamp'];
              final bTime = bVal['timestamp'];

              num aNum = (aTime is num)
                  ? aTime
                  : (aTime is Map ? DateTime.now().millisecondsSinceEpoch : 0);
              num bNum = (bTime is num)
                  ? bTime
                  : (bTime is Map ? DateTime.now().millisecondsSinceEpoch : 0);

              return bNum.compareTo(aNum);
            },
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 150),
            itemBuilder: (context, snapshot, animation, index) {
              if (!snapshot.exists || snapshot.value is! Map)
                return const SizedBox.shrink();

              final Map b = snapshot.value as Map;
              final String key = snapshot.key!;

              final String status =
                  (b['status'] ?? 'Pending').toString().trim().toLowerCase();
              final String currentFilter = _filter.trim().toLowerCase();

              if (_filter != "All" && status != currentFilter) {
                return const SizedBox.shrink();
              }

              return FadeTransition(
                opacity: animation,
                child: _buildCard(b, key),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCard(Map b, String key) {
    String s = b['status'] ?? 'Pending';
    String statusNorm = s.trim().toLowerCase();

    Color c = statusNorm == 'confirmed'
        ? Colors.green
        : (statusNorm == 'cancelled'
            ? AppTheme.primaryAccent
            : (statusNorm == 'completed'
                ? Colors.blue
                : (statusNorm == 'checked in'
                    ? Colors.indigo
                    : (statusNorm.contains('requested')
                        ? Colors.deepPurple
                        : Colors.orange))));
    String? r = (b['gcashReceipt'] != null &&
            b['gcashReceipt'].toString().trim().isNotEmpty)
        ? b['gcashReceipt']
        : (b['paymentReceiptDataUrl']);
    List addons = b['selectedAddons'] is List ? b['selectedAddons'] : [];

    // Web Fallback Logic
    String touristName = b['touristName'] ??
        b['customerName'] ??
        b['userName'] ??
        b['name'] ??
        b['fullName'] ??
        'Tourist';
    String roomTitle = b['activityTitle'] ??
        b['roomTitle'] ??
        b['activityName'] ??
        b['room'] ??
        b['roomId'] ??
        'Booking';
    String paymentMethod = b['paymentMethod'] ??
        b['paymentOption'] ??
        b['payment'] ??
        b['paymentType'] ??
        'N/A';

    String? bookingDate = b['bookingDate'] ??
        b['checkInDate'] ??
        b['date'] ??
        b['createdAt'] ??
        'N/A';
    if (bookingDate != null &&
        bookingDate.contains('T') &&
        bookingDate.contains('Z')) {
      try {
        bookingDate =
            DateFormat('MMM dd, yyyy').format(DateTime.parse(bookingDate));
      } catch (e) {}
    }

    String dateRange = bookingDate ?? 'N/A';
    try {
      if (bookingDate != null && b['nights'] != null) {
        DateTime start = DateFormat('MMM dd, yyyy').parse(bookingDate);
        int nights = int.tryParse(b['nights'].toString()) ?? 1;
        DateTime end = start.add(Duration(days: nights));
        dateRange =
            "$bookingDate - ${DateFormat('MMM dd, yyyy').format(end)} ($nights Nights)";
      }
    } catch (e) {}

    String? photo = b['touristProfilePic'];

    return Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Stack(children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => widget.onTapBooking(key, b),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  backgroundImage: photo != null ? NetworkImage(photo) : null,
                  child: photo == null ? const Icon(Icons.person) : null,
                ),
                title: Text(touristName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 16)),
                subtitle: Text(
                    "$roomTitle\nDate: $dateRange\nPayment: $paymentMethod"),
                isThreeLine: true,
                trailing: SizedBox(
                  width: 85,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          decoration: BoxDecoration(
                              color: c.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20)),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(s,
                                style: TextStyle(
                                    color: c,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10)),
                          )),
                      if (['Pending', 'Reschedule Requested', 'Refund Requested'].contains(s))
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                            decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(10)),
                            child: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Action Needed',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 9)),
                            ),
                          ),
                        )
                    ],
                  ),
                ),
              ),
              if (addons.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text("Add-ons: ${addons.join(', ')}",
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              if (b['cancellationReason'] != null)
                Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text("Owner Note/Reason: ${b['cancellationReason']}",
                        style: const TextStyle(
                            color: AppTheme.primaryAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12))),
              if (b['status'] == 'Reschedule Requested')
                Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                        "Reschedule to: ${b['requestedRescheduleDate']} (${b['requestedRescheduleNights'] ?? b['nights']} Night/s)",
                        style: const TextStyle(
                            color: Colors.deepPurple,
                            fontWeight: FontWeight.bold,
                            fontSize: 13))),
              if (b['status'] == 'Refund Requested')
                Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Refund Reason: ${b['refundReason']}",
                            style: const TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                        const SizedBox(height: 4),
                        FutureBuilder(
                          future: FirebaseDatabase.instance
                              .ref('users/${b['touristUid'] ?? ''}')
                              .get(),
                          builder: (context, AsyncSnapshot snap) {
                            if (snap.connectionState ==
                                ConnectionState.waiting) {
                              return const Text(
                                  "Send To: Loading GCash details...",
                                  style: TextStyle(
                                      color: Colors.redAccent, fontSize: 13));
                            }
                            String gn = (b['gcashName'] != null &&
                                    b['gcashName'].toString().isNotEmpty)
                                ? b['gcashName']
                                : 'N/A';
                            String gnum = (b['gcashNumber'] != null &&
                                    b['gcashNumber'].toString().isNotEmpty)
                                ? b['gcashNumber']
                                : 'N/A';

                            if (snap.hasData && snap.data!.exists) {
                              final u = snap.data!.value as Map;
                              if (u['gcashName'] != null &&
                                  u['gcashName'].toString().trim().isNotEmpty)
                                gn = u['gcashName'];
                              if (u['gcashNumber'] != null &&
                                  u['gcashNumber'].toString().trim().isNotEmpty)
                                gnum = u['gcashNumber'];
                            }
                            return Text("Send To: $gn ($gnum)",
                                style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13));
                          },
                        ),
                      ],
                    )),
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 20),
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                        color: Colors.indigo.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Colors.indigo.withOpacity(0.15))),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.visibility, size: 14, color: Colors.indigo),
                        SizedBox(width: 6),
                        Text("Tap to view full details & actions",
                            style: TextStyle(
                                color: Colors.indigo,
                                fontSize: 12,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ),
            ]),
          ),
          Positioned(
              top: 4,
              right: 4,
              child: _deletingBookingKey == key
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red[200]!)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton(
                            onPressed: () =>
                                setState(() => _deletingBookingKey = null),
                            child: const Text('Cancel',
                                style: TextStyle(fontSize: 12))),
                        TextButton(
                            onPressed: () {
                              widget.onDeleteRecord(key, touristName);
                              setState(() => _deletingBookingKey = null);
                            },
                            child: const Text('Delete',
                                style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold))),
                      ]))
                  : IconButton(
                      icon: const Icon(Icons.delete_forever_rounded,
                          color: Colors.grey, size: 20),
                      onPressed: () =>
                          setState(() => _deletingBookingKey = key))),
        ]));
  }
}

class ChatTab extends StatefulWidget {
  final Query chatQuery;
  const ChatTab({super.key, required this.chatQuery});
  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FirebaseAnimatedList(
      query: widget.chatQuery,
      sort: (a, b) {
        final Map aVal = (a.value ?? {}) as Map;
        final Map bVal = (b.value ?? {}) as Map;
        final aTime = aVal['timestamp'];
        final bTime = bVal['timestamp'];

        // Handle ServerValue.timestamp placeholders (Maps) during sync
        num aNum = (aTime is num)
            ? aTime
            : (aTime is Map ? DateTime.now().millisecondsSinceEpoch : 0);
        num bNum = (bTime is num)
            ? bTime
            : (bTime is Map ? DateTime.now().millisecondsSinceEpoch : 0);

        return bNum.compareTo(aNum);
      },
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, snapshot, animation, index) {
        if (!snapshot.exists || snapshot.value is! Map) return const SizedBox();
        Map room = snapshot.value as Map;
        String uid = snapshot.key!;
        int unread = int.tryParse(room['unreadCount']?.toString() ?? '0') ?? 0;
        String? photo = room['otherProfilePic'];

        return FadeTransition(
          opacity: animation,
          child: Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    Theme.of(context).colorScheme.primary.withOpacity(0.1),
                backgroundImage: photo != null ? NetworkImage(photo) : null,
                child: photo == null ? const Icon(Icons.person) : null,
              ),
              title: Row(
                children: [
                  Expanded(
                      child: Text(room['otherUserName'] ?? 'Tourist',
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                  if (unread > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppTheme.primaryAccent,
                          borderRadius: BorderRadius.circular(12)),
                      child: Text(unread.toString(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              subtitle: Text(
                room['lastMessage'] != null
                    ? 'View messages'
                    : 'Tap to open chat',
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => ChatPage(
                          otherUserUid: uid,
                          otherUserName: room['otherUserName'] ?? 'Tourist'))),
            ),
          ),
        );
      },
    );
  }
}

class MonthlyReportPage extends StatelessWidget {
  final String monthName;
  final List<Map<String, dynamic>> details;
  final double totalRevenue;

  const MonthlyReportPage(
      {super.key,
      required this.monthName,
      required this.details,
      required this.totalRevenue});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$monthName Report'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Export Report',
            onPressed: () {
              String report = "$monthName Sales Report\n";
              report += "Total Revenue: ₱${totalRevenue.toStringAsFixed(2)}\n\n";
              report += "Bookings:\n";
              for (var d in details) {
                report += "- ${d['room']}: ₱${d['amount']} (${d['tourist']})\n";
              }
              Share.share(report, subject: '$monthName Sales Report');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            width: double.infinity,
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('Total Revenue',
                    style: TextStyle(
                        color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('₱${totalRevenue.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.secondaryAccent)),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12)),
                  child: Text('${details.length} Confirmed Bookings',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: details.isEmpty
                ? const Center(child: Text('No details available.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: details.length,
                    itemBuilder: (context, index) {
                      final b = details[index];
                      final raw = b['rawBooking'] as Map?;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                      child: Text(b['room'],
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 16))),
                                  Text('₱${b['amount'].toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green,
                                          fontSize: 16)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(Icons.person,
                                      size: 16, color: Colors.grey),
                                  const SizedBox(width: 8),
                                  Text(b['tourist'],
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.calendar_month,
                                      size: 16, color: Colors.grey),
                                  const SizedBox(width: 8),
                                  Text('${b['date']} (${b['nights']} nights)'),
                                ],
                              ),
                              if (raw != null && raw['addOns'] != null) ...[
                                const SizedBox(height: 12),
                                const Text('Add-ons:',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: Colors.grey)),
                                const SizedBox(height: 4),
                                ...((raw['addOns'] as List)
                                    .where((e) => e != null)
                                    .map((e) {
                                  if (e is Map) {
                                    return Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                            '- ${e['name'] ?? 'Add-on'} x${e['quantity'] ?? 1}',
                                            style:
                                                const TextStyle(fontSize: 12)),
                                        Text('₱${e['totalPrice'] ?? 0}',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold)),
                                      ],
                                    );
                                  }
                                  return Text('- ${e.toString()}',
                                      style: const TextStyle(fontSize: 12));
                                }).toList()),
                              ],
                              if (raw != null &&
                                  raw['paymentMethod'] != null) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Icon(Icons.credit_card,
                                        size: 16, color: Colors.grey),
                                    const SizedBox(width: 8),
                                    Text('Paid via ${raw['paymentMethod']}',
                                        style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ]
                            ],
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
}
