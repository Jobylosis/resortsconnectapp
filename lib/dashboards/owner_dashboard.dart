import 'package:flutter/material.dart';
import '../notifications_page.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'tourist_profile_dialog.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart' as crypto;
import '../chat_page.dart';
import 'price_breakdown_dialog.dart';
import '../theme_provider.dart';
import '../theme.dart';
import 'package:share_plus/share_plus.dart';
import '../services/email_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'activity_edit_sheet.dart';
import 'historical_import_page.dart';

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
  final _receptionController = TextEditingController();
  final _instrController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _capacityController = TextEditingController();
  final _gcashNumberController = TextEditingController();
  final _gcashNameController = TextEditingController();
  final _cancellationPolicyController = TextEditingController();
  final _paymentPolicyController = TextEditingController();
  final _resortRulesController = TextEditingController();
  final _petPolicyController = TextEditingController();
  final _safetyGuidelinesController = TextEditingController();
  String? _gcashQrUrl;
  
  String _propertyType = 'Resort';
  bool _showActivities = true;
  bool _enableCustomMenuUpload = false;
  Map<String, dynamic> _addonPrices = {};
  final _newAddonNameController = TextEditingController();
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
  bool _roomIsAvailable = true;

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
  int _unreadReviewsCount = 0;
  Set<String> _readReviewIds = {};
  Map<String, int> _bookingCounts = {'All': 0};

  final List<String> _inclusionOptions = [
    'Refrigerator',
    'Air Conditioning',
    'Smart Tv',
    'Free Wifi',
    'Bathroom essentials',
    'Shower Heater',
    'Heater',
    'Sofa',
    'Cabinet',
    'Ceiling fan',
    'Cabinet clothes/foods',
    'Swimming Pool',
    'Breakfast'
  ];

  bool _isSubmitting = false;
  String? _editingActivityKey;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? "unknown";

    if (user != null) {
      NotificationService().requestPermission();
      NotificationService().startListening(user.uid);
    }

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
    _chatRoomsStream = _chatQuery.onValue.asBroadcastStream();

    _loadReadReviews(uid);

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

    FirebaseDatabase.instance.ref("reviews/$uid").onValue.listen((event) {
      if (event.snapshot.exists) {
        final val = event.snapshot.value;
        int unread = 0;
        if (val is Map) {
          val.forEach((k, v) {
            if (!_readReviewIds.contains(k.toString())) {
              unread++;
            }
          });
        }
        if (mounted) setState(() => _unreadReviewsCount = unread);
      } else {
        if (mounted) setState(() => _unreadReviewsCount = 0);
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

        DateTime today = DateTime.now();
        DateTime todayMidnight = DateTime(today.year, today.month, today.day);

        data.forEach((k, v) {
          if (v is Map) {
            String status = v['status'] ?? 'Pending';
            String rawStatus = status.trim().toLowerCase();

            // Auto-transition to No Show if check-out date has passed and guest never checked in
            if (rawStatus == 'confirmed' || rawStatus == 'pending') {
              String? dateStr = v['bookingDate'] ?? v['checkInDate'] ?? v['date'];
              if (dateStr != null && dateStr.isNotEmpty) {
                try {
                  DateTime start;
                  if (dateStr.contains('T') && dateStr.contains('Z')) {
                    start = DateTime.parse(dateStr);
                  } else {
                    start = DateFormat("MMM dd, yyyy").parse(dateStr);
                  }
                  DateTime startMidnight = DateTime(start.year, start.month, start.day);
                  int nights = int.tryParse(v['nights']?.toString() ?? '1') ?? 1;
                  DateTime endMidnight = startMidnight.add(Duration(days: nights));

                  if (todayMidnight.isAfter(endMidnight)) {
                    status = 'No Show';
                    FirebaseDatabase.instance.ref("bookings/$k").update({
                      'status': 'No Show',
                      'cancellationReason': 'Guest did not check in and checkout date has passed.'
                    });

                    String? tUid = v['touristUid'] ?? v['userId'];
                    if (tUid != null && tUid.isNotEmpty) {
                      String itemTitle = (v['activityTitle'] ?? v['roomTitle'] ?? 'Reservation').toString();
                      FirebaseDatabase.instance.ref("notifications/$tUid").push().set({
                        'title': 'Booking Marked as No Show',
                        'message': 'Your reservation for "$itemTitle" was marked as No Show because the checkout date has passed without check-in.',
                        'type': 'booking_updated',
                        'isRead': false,
                        'timestamp': ServerValue.timestamp,
                        'bookingId': k,
                      });
                    }
                  }
                } catch (e) {
                  // Silently ignore format issues for backward compatibility
                }
              }
            }

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

  Future<void> _loadReadReviews(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('read_reviews_$uid') ?? [];
      if (mounted) {
        setState(() {
          _readReviewIds = list.toSet();
        });
      }
    } catch (_) {}
  }

  Future<void> _markReviewAsRead(String reviewId) async {
    if (_readReviewIds.contains(reviewId)) return;
    setState(() {
      _readReviewIds.add(reviewId);
      if (_unreadReviewsCount > 0) _unreadReviewsCount--;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('read_reviews_${user.uid}', _readReviewIds.toList());
      }
    } catch (_) {}
  }

  Future<void> _markAllReviewsAsRead(List<String> allIds) async {
    setState(() {
      _readReviewIds.addAll(allIds);
      _unreadReviewsCount = 0;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('read_reviews_${user.uid}', _readReviewIds.toList());
      }
    } catch (_) {}
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
    _receptionController.dispose();
    _instrController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _contactPhoneController.dispose();
    _contactEmailController.dispose();
    _capacityController.dispose();
    _gcashNumberController.dispose();
    _gcashNameController.dispose();
    _cancellationPolicyController.dispose();
    _paymentPolicyController.dispose();
    _resortRulesController.dispose();
    _petPolicyController.dispose();
    _safetyGuidelinesController.dispose();
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
      String? placeholder,
      Function(String)? onChanged}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
      inputFormatters: [
        ...?inputFormatters,
        FilteringTextInputFormatter.deny(RegExp(
            r'[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]',
            unicode: true)),
        FilteringTextInputFormatter.deny(RegExp(r'[!#^&*+={}\[\]|\\<>\/~]')),
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
          if (label == 'GCash Name' && !RegExp(r'^[a-zA-Z\s\.]+$').hasMatch(trimmed)) {
            return 'Only letters, spaces, and periods allowed';
          }
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
    _roomIsAvailable = true;
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

  void _showDeleteActivityDialog(String key, String title) {
    // Legacy dialog, now we use inline deletion in the UI
  }

  Future<void> _deleteActivityDirectly(String key) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      String uid = FirebaseAuth.instance.currentUser!.uid;
      DataSnapshot snap = await FirebaseDatabase.instance.ref('bookings').orderByChild('ownerUid').equalTo(uid).get();
      bool hasActive = false;
      String warningMessage = "Cannot delete room because it has active bookings on the following dates:\n\n";
      DateTime? latestCheckoutDate;

      if (snap.exists && snap.value != null) {
        Map b = snap.value as Map;
        b.forEach((k, v) {
          if (v is Map && (v['roomId'] == key || v['activityId'] == key)) {
            String status = (v['status'] ?? '').toString().toLowerCase();
            if (status == 'pending' || status == 'confirmed' || status == 'checked in' || status == 'checked-in') {
              hasActive = true;

              String dateStr = v['bookingDate'] ?? v['checkInDate'] ?? v['date'] ?? '';
              if (dateStr.isNotEmpty) {
                try {
                  DateTime start = DateFormat('MMM dd, yyyy').parse(dateStr);
                  int nights = int.tryParse(v['nights']?.toString() ?? '1') ?? 1;
                  DateTime end = start.add(Duration(days: nights));
                  warningMessage += "- ${DateFormat('MMM dd, yyyy').format(start)} to ${DateFormat('MMM dd, yyyy').format(end)}\n";

                  if (latestCheckoutDate == null || end.isAfter(latestCheckoutDate!)) {
                    latestCheckoutDate = end;
                  }
                } catch (e) {
                  warningMessage += "- $dateStr\n";
                }
              }
            }
          }
        });
      }

      if (mounted) Navigator.pop(context); // pop loading

      if (hasActive) {
        if (latestCheckoutDate != null) {
          warningMessage += "\nYou will have the ability to delete this room after the supposed checkout on ${DateFormat('MMM dd, yyyy').format(latestCheckoutDate!)}.";
        }
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Warning', style: TextStyle(color: Colors.red)),
              content: Text(warningMessage),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                )
              ],
            )
          );
        }
        return;
      }

      await _propRef.child("roomInventory/$key").remove();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Room deleted successfully.')));
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
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
              SizedBox(
                height: 400,
                child: Builder(
                  builder: (context) {
                    if (url == 'MANUAL_GCASH_PAYMENT') {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('Manual GCash Payment\n(No receipt image provided)', 
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
                        )
                      );
                    }
                    
                    List<String> urls = url.contains(',') && !url.startsWith('data:image') 
                        ? url.split(',') 
                        : [url];

                    return Column(
                      children: [
                        Expanded(
                          child: PageView.builder(
                            itemCount: urls.length,
                            itemBuilder: (context, index) {
                              final u = urls[index].trim();
                              return u.startsWith('data:image')
                                  ? Image.memory(base64Decode(u.split(',').last),
                                      errorBuilder: (c, e, s) => const Center(child: Text("Error loading image")))
                                  : Image.network(u,
                                      errorBuilder: (c, e, s) => const Center(child: Text("Error loading image")));
                            },
                          ),
                        ),
                        if (urls.length > 1)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text('Swipe to see more (${urls.length} receipts)', style: const TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic)),
                          ),
                      ],
                    );
                  }
                )
              ),
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'))
            ])));
  }

  bool _isOverlapping(
      DateTime startA, DateTime endA, DateTime startB, DateTime endB) {
    return startA.isBefore(endB) && endA.isAfter(startB);
  }

  // Helper to extract normalized activity items from a booking Map in Dart
  List<Map<String, String>> _getBookingActivityItems(Map b) {
    List<Map<String, String>> items = [];
    if (b['activityList'] is List && (b['activityList'] as List).isNotEmpty) {
      for (var act in (b['activityList'] as List)) {
        if (act is Map) {
          items.add({
            'id': (act['id'] ?? act['activityId'] ?? '').toString(),
            'title': (act['title'] ?? act['name'] ?? '').toString(),
            'timeSlot': (act['timeSlot'] ?? act['arrivalTime'] ?? b['timeSlot'] ?? b['arrivalTime'] ?? '').toString(),
          });
        }
      }
    } else if (b['selectedActivities'] is List && (b['selectedActivities'] as List).isNotEmpty) {
      for (var act in (b['selectedActivities'] as List)) {
        if (act is Map) {
          items.add({
            'id': (act['id'] ?? act['activityId'] ?? '').toString(),
            'title': (act['title'] ?? act['name'] ?? '').toString(),
            'timeSlot': (act['timeSlot'] ?? act['arrivalTime'] ?? b['timeSlot'] ?? b['arrivalTime'] ?? '').toString(),
          });
        }
      }
    } else if (b['activityId'] != null || b['activityTitle'] != null || b['isActivityBooking'] == true) {
      items.add({
        'id': (b['activityId'] ?? '').toString(),
        'title': (b['activityTitle'] ?? 'Activity').toString(),
        'timeSlot': (b['timeSlot'] ?? b['arrivalTime'] ?? '').toString(),
      });
    }
    return items;
  }

  bool _isKaraokeString(String? str) {
    return (str ?? '').toLowerCase().contains('karaoke');
  }

  static DateTime? _parseTolerantDate(dynamic val) {
    if (val == null) return null;
    if (val is DateTime) return val;
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
    final s = val.toString().trim();
    if (s.isEmpty || s == 'N/A') return null;

    // 1. Slashes: MM/dd/yy or MM/dd/yyyy
    if (s.contains('/')) {
      final parts = s.split('/');
      if (parts.length == 3) {
        final m = int.tryParse(parts[0]);
        final d = int.tryParse(parts[1]);
        int? y = int.tryParse(parts[2]);
        if (m != null && d != null && y != null && m >= 1 && m <= 12) {
          if (parts[2].length == 2) y = 2000 + y;
          return DateTime(y, m, d);
        }
      }
    }

    // 2. ISO or yyyy-MM-dd
    if (s.contains('-') || s.contains('T')) {
      try {
        return DateTime.parse(s);
      } catch (_) {}
    }

    // 3. MMM dd, yyyy (e.g. Oct 02, 2026)
    try {
      return DateFormat('MMM dd, yyyy').parse(s);
    } catch (_) {}

    // 4. MMMM dd, yyyy (e.g. October 02, 2026)
    try {
      return DateFormat('MMMM dd, yyyy').parse(s);
    } catch (_) {}

    return null;
  }

  DateTime? _parseBookingDate(Map b) {
    dynamic val = b['bookingDate'] ??
        b['checkInDate'] ??
        b['date'] ??
        b['createdAt'] ??
        b['timestamp'];
    return _parseTolerantDate(val);
  }

  // Check if booking bA conflicts with booking bB
  Map<String, dynamic>? _checkConflictBetweenBookings(Map bA, Map bB) {
    // 1. Room conflict
    final roomA = bA['roomId'] ?? (bA['isActivityBooking'] != true && bA['activityId'] == null ? bA['roomTitle'] : null);
    final roomB = bB['roomId'] ?? (bB['isActivityBooking'] != true && bB['activityId'] == null ? bB['roomTitle'] : null);
    if (roomA != null && roomB != null && roomA.toString() == roomB.toString()) {
      DateTime? startA = _parseBookingDate(bA);
      DateTime? startB = _parseBookingDate(bB);
      if (startA != null && startB != null) {
        int nightsA = int.tryParse(bA['nights']?.toString() ?? '1') ?? 1;
        int nightsB = int.tryParse(bB['nights']?.toString() ?? '1') ?? 1;
        DateTime endA = startA.add(Duration(days: nightsA));
        DateTime endB = startB.add(Duration(days: nightsB));
        if (_isOverlapping(startA, endA, startB, endB)) {
          return {
            'hasConflict': true,
            'type': 'room',
            'title': bB['roomTitle'] ?? bA['roomTitle'] ?? 'Room'
          };
        }
      }
    }

    // 2. Activity conflicts
    List<Map<String, String>> actsA = _getBookingActivityItems(bA);
    List<Map<String, String>> actsB = _getBookingActivityItems(bB);

    if (actsA.isNotEmpty && actsB.isNotEmpty) {
      DateTime? startA = _parseBookingDate(bA);
      DateTime? startB = _parseBookingDate(bB);
      if (startA != null && startB != null) {
        if (startA.year == startB.year && startA.month == startB.month && startA.day == startB.day) {
          // Karaoke whole-day exclusivity
          bool hasKaraokeA = actsA.any((a) => _isKaraokeString(a['title']));
          bool hasKaraokeB = actsB.any((b) => _isKaraokeString(b['title']));
          if (hasKaraokeA && hasKaraokeB) {
            return {
              'hasConflict': true,
              'type': 'activity',
              'title': 'Karaoke'
            };
          }

          // Hourly / slot activities
          for (var itemA in actsA) {
            if (_isKaraokeString(itemA['title'])) continue;
            String titleA = (itemA['title'] ?? '').trim().toLowerCase();
            String idA = (itemA['id'] ?? '').trim().toLowerCase();
            String slotA = (itemA['timeSlot'] ?? '').trim().toLowerCase();

            for (var itemB in actsB) {
              if (_isKaraokeString(itemB['title'])) continue;
              String titleB = (itemB['title'] ?? '').trim().toLowerCase();
              String idB = (itemB['id'] ?? '').trim().toLowerCase();
              String slotB = (itemB['timeSlot'] ?? '').trim().toLowerCase();

              bool isSame = (idA.isNotEmpty && idB.isNotEmpty && idA == idB) ||
                  (titleA.isNotEmpty && titleB.isNotEmpty && titleA == titleB) ||
                  (titleA.contains('boatride') && titleB.contains('boatride')) ||
                  (titleA.contains('kayak') && titleB.contains('kayak')) ||
                  (titleA.contains('paddle') && titleB.contains('paddle'));

              if (isSame) {
                if (slotA.isNotEmpty && slotB.isNotEmpty &&
                    slotA != 'regular operating hours' && slotB != 'regular operating hours') {
                  if (slotA == slotB) {
                    return {
                      'hasConflict': true,
                      'type': 'activity',
                      'title': itemB['title'] ?? itemA['title'] ?? 'Activity'
                    };
                  }
                } else {
                  return {
                    'hasConflict': true,
                    'type': 'activity',
                    'title': itemB['title'] ?? itemA['title'] ?? 'Activity'
                  };
                }
              }
            }
          }
        }
      }
    }

    return null;
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

      for (var entry in allBookings.entries) {
        if (entry.key == currentBookingKey) continue;
        Map bB = entry.value as Map;

        String status = (bB['status'] ?? '').toString().trim().toLowerCase();
        if (status != 'confirmed' && status != 'checked in') continue;

        if (_checkConflictBetweenBookings(bA, bB) != null) {
          return true;
        }
      }
    } catch (e) {
      return false; // Safely fail open instead of crashing
    }
    return false;
  }

  void _updateBookingStatus(String key, String status, Map booking,
      {bool skipConfirm = false, bool? markAsPaid}) async {
    String? cancellationReason;

    // Confirmation for non-routine status changes
    if (status == 'Cancelled' ||
        status == 'Reschedule Declined' ||
        status == 'Refund Declined') {
      final reasonController = TextEditingController();
      String actionText = status == 'Cancelled'
          ? 'cancelling this booking'
          : (status == 'Reschedule Declined'
              ? 'declining this reschedule request'
              : 'declining this refund');
      String titleText = status == 'Cancelled'
          ? 'Cancel Booking?'
          : (status == 'Reschedule Declined'
              ? 'Decline Reschedule?'
              : 'Decline Refund?');

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
    } else if (status == 'Refund Confirmed') {
      if (!skipConfirm) {
        bool confirm = await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Confirm Refund?'),
                content: const Text(
                    'Confirm that the refund has been sent to the guest?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Confirm',
                        style: TextStyle(color: Colors.green)),
                  ),
                ],
              ),
            ) ??
            false;
        if (!confirm) return;
      }
    } else if (status == 'Confirmed' ||
        status == 'Checked In' ||
        status == 'Completed' ||
        status == 'Reschedule Approved' ||
        status == 'Refund Approved') {
      if (!skipConfirm) {
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
    }

    if (status == 'Confirmed') {
      final activityId = booking['activityId'] ?? booking['roomId'] ?? booking['roomTitle'] ?? 'unit';
      final hasConflict =
          await _checkBookingConflict(key, activityId.toString(), booking);
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
        final snap = await FirebaseDatabase.instance
            .ref("bookings")
            .orderByChild("ownerUid")
            .equalTo(ownerUid)
            .get();
        if (snap.exists) {
          Map allBookings = {};
          dynamic val = snap.value;
          if (val is Map) {
            allBookings = val;
          } else if (val is List) {
            for (int i = 0; i < val.length; i++) {
              if (val[i] != null) allBookings[i.toString()] = val[i];
            }
          }

          for (var entry in allBookings.entries) {
            if (entry.key == key) continue;
            Map bB = entry.value as Map;
            String bStatus =
                (bB['status'] ?? '').toString().trim().toLowerCase();
            if (bStatus == 'pending') {
              final conflict = _checkConflictBetweenBookings(booking, bB);
              if (conflict != null) {
                bool isActB = conflict['type'] == 'activity';
                String itemTitle = (conflict['title'] ?? bB['activityTitle'] ?? bB['roomTitle'] ?? (isActB ? 'Activity' : 'Room')).toString();
                String declineReason =
                    'This ${isActB ? 'activity slot' : 'room'} was booked by another guest. Please request a refund or reschedule your booking.';

                await FirebaseDatabase.instance
                    .ref("bookings/${entry.key}")
                    .update({
                  'status': 'Declined',
                  'cancellationReason': declineReason,
                });
                String tUidB = bB['touristUid'] ?? bB['userId'] ?? "";
                if (tUidB.isNotEmpty) {
                  await FirebaseDatabase.instance
                      .ref("notifications/$tUidB")
                      .push()
                      .set({
                    'title': 'Booking Declined',
                    'message':
                        'Your booking for "$itemTitle" was declined because this slot was reserved by another guest. Please request a refund or reschedule your booking.',
                    'type': 'booking_rejected',
                    'isRead': false,
                    'timestamp': ServerValue.timestamp,
                    'bookingId': entry.key,
                  });
                }
              }
            }
          }
        }
      }
    }

    if (status == 'Reschedule Approved') {
      final newDate = booking['requestedRescheduleDate'];
      final newDuration = booking['requestedRescheduleHours'] ?? booking['requestedRescheduleNights'];
      bool isActivity = booking['isActivityBooking'] == true ||
          (booking['activityId'] != null && booking['activityId'].toString().trim().isNotEmpty) ||
          (booking['activityTitle'] != null && booking['roomId'] == null);

      if (newDate != null) {
        await FirebaseDatabase.instance.ref("bookings/$key").update({
          'status': 'Confirmed',
          'bookingDate': newDate,
          if (newDuration != null) 'nights': newDuration,
          if (newDuration != null && isActivity) 'hours': newDuration,
          'requestedRescheduleDate': null,
          'requestedRescheduleNights': null,
          'requestedRescheduleHours': null,
        });
        status = 'Confirmed'; // For notification
      }
    } else if (status == 'Reschedule Declined') {
      await FirebaseDatabase.instance.ref("bookings/$key").update({
        'status': 'Confirmed',
        'requestedRescheduleDate': null,
        'requestedRescheduleNights': null,
        'requestedRescheduleHours': null,
        if (cancellationReason != null && cancellationReason.isNotEmpty)
          'cancellationReason': cancellationReason,
      });
      status = 'Reschedule Request Declined';
    } else if (status == 'Refund Declined') {
      await FirebaseDatabase.instance.ref("bookings/$key").update({
        'status': 'Confirmed',
        'refundReason': null,
        if (cancellationReason != null && cancellationReason.isNotEmpty)
          'cancellationReason': cancellationReason,
      });
      status = 'Refund Request Declined';
    } else if (status == 'Refund Confirmed') {
      await FirebaseDatabase.instance.ref("bookings/$key").update({
        'status': 'Refund Confirmed',
        'refundConfirmedAt': ServerValue.timestamp,
        'refundConfirmedBy': FirebaseAuth.instance.currentUser?.uid,
        if (cancellationReason != null && cancellationReason.isNotEmpty)
          'cancellationReason': cancellationReason,
      });
    } else {
      await FirebaseDatabase.instance.ref("bookings/$key").update({
        'status': status,
        if (cancellationReason != null && cancellationReason.isNotEmpty)
          'cancellationReason': cancellationReason,
        if (markAsPaid == true)
          'amountPaid': booking['totalPrice'] ?? booking['total'] ?? booking['amount'] ?? booking['payment'] ?? booking['price'] ?? 0,
      });
    }
    String tUid = booking['touristUid'] ?? booking['userId'] ?? "";
    if (tUid.isNotEmpty) {
      String notifType = 'booking_updated';
      if (status == 'Confirmed') {
        notifType = 'booking_accepted';
      } else if (status == 'Cancelled' || status.contains('Declined')) {
        notifType = 'booking_rejected';
      } else if (status == 'Completed' || status == 'Refund Confirmed') {
        notifType = 'booking_completed';
      }

      String notifTitle = 'Booking Updated';
      String message =
          'Your booking for "${booking['activityTitle'] ?? booking['roomTitle'] ?? booking['room'] ?? booking['roomId'] ?? "Room"}" is now $status.';

      if (status == 'Refund Approved') {
        notifTitle = 'Refund Approved - Please Wait';
        message = 'Your refund request for "${booking['activityTitle'] ?? booking['roomTitle'] ?? 'Booking'}" has been APPROVED. Please wait for a moment while the owner transfers the refund to your GCash account.';
      } else if (status == 'Refund Confirmed') {
        notifTitle = 'Refund Confirmed';
        message = 'Your refund for "${booking['activityTitle'] ?? booking['roomTitle'] ?? booking['room'] ?? booking['roomId'] ?? 'Booking'}" has been confirmed by the resort.';
      } else if (cancellationReason != null && cancellationReason.isNotEmpty) {
        message += ' Reason: $cancellationReason';
      }

      await FirebaseDatabase.instance.ref("notifications/$tUid").push().set({
        'title': notifTitle,
        'message': message,
        'type': notifType,
        'isRead': false,
        'timestamp': ServerValue.timestamp,
        'bookingId': key,
      });

      // EmailJS Booking Status Update
      FirebaseDatabase.instance.ref("users/$tUid").get().then((tSnap) {
        if (tSnap.exists && tSnap.value != null) {
          final tData = Map<String, dynamic>.from(tSnap.value as Map);
          final tEmail = tData['email'] ?? booking['touristEmail'];
          if (tEmail != null && tEmail.toString().isNotEmpty) {
            EmailService.sendBookingStatusUpdate(
              toEmail: tEmail.toString(),
              toName: "${tData['firstName'] ?? ''} ${tData['lastName'] ?? ''}".trim(),
              bookingId: key,
              propertyName: booking['propertyName'] ?? (_propNameController.text.isNotEmpty ? _propNameController.text : 'Resort'),
              roomName: (booking['activityTitle'] ?? booking['roomTitle'] ?? 'Room').toString(),
              newStatus: status,
              notes: cancellationReason ?? 'No additional notes.',
            ).catchError((e) {
              debugPrint('[EmailJS] Status email error: $e');
              return false;
            });
          }
        }
      }).catchError((e) {
        debugPrint('[EmailJS] Fetch user error: $e');
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


  void _disableRoom(String roomId, Map roomData) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    bool isCurrentlyDisabled = roomData['isDisabled'] == true;
    if (isCurrentlyDisabled) {
      // Re-enable
      try {
        await FirebaseDatabase.instance.ref('properties/$uid/roomInventory/$roomId').update({
          'isDisabled': false,
          'disabledStartDate': null,
          'disabledDays': null,
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Room re-enabled.')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to re-enable: $e')));
      }
      return;
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
    }

    Set<DateTime> bookedDates = {};
    bool isCheckedIn = false;

    try {
      final snapshot = await FirebaseDatabase.instance.ref('bookings').orderByChild('ownerUid').equalTo(uid).get();
      if (snapshot.exists) {
        final data = snapshot.value as Map;
        for (var b in data.values) {
          if (b['roomId'] != roomId && b['activityId'] != roomId) continue;
          
          String st = (b['status'] ?? '').toString().toLowerCase();
          if (st == 'checked in') {
            isCheckedIn = true;
          }
          if (st == 'pending' || st == 'confirmed' || st == 'reschedule requested' || st == 'checked in') {
            String bDateStr = b['bookingDate'] ?? '';
            if (bDateStr.isNotEmpty) {
              try {
                DateTime bookingStart = DateFormat('MMM dd, yyyy').parse(bDateStr);
                int nights = int.tryParse((b['nights'] ?? '1').toString()) ?? 1;
                for (int i = 0; i < nights; i++) {
                  DateTime d = bookingStart.add(Duration(days: i));
                  bookedDates.add(DateTime(d.year, d.month, d.day));
                }
              } catch (e) {
                // ignore parse error
              }
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // close loading
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to fetch bookings: $e')));
      }
      return;
    }

    if (mounted) Navigator.pop(context); // close loading

    if (isCheckedIn) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cannot Disable Room'),
            content: const Text('There is a tourist currently checked into this room. You cannot disable it until they check out.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          )
        );
      }
      return;
    }

    DateTime? selectedStartDate;
    DateTime? selectedEndDate;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateContext, setState) => AlertDialog(
          title: const Text('Disable Room'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select the exact dates to disable this room (booked dates are greyed out).'),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Start Date:', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        selectableDayPredicate: (day) => !bookedDates.contains(DateTime(day.year, day.month, day.day)),
                      );
                      if (date != null) {
                        setState(() {
                          selectedStartDate = date;
                          // Reset end date if it's before new start date
                          if (selectedEndDate != null && selectedEndDate!.isBefore(selectedStartDate!)) {
                            selectedEndDate = null;
                          }
                        });
                      }
                    },
                    child: Text(selectedStartDate != null ? DateFormat('MMM dd, yyyy').format(selectedStartDate!) : 'Select Date'),
                  )
                ]
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('End Date:', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: selectedStartDate == null ? null : () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedStartDate!,
                        firstDate: selectedStartDate!,
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        selectableDayPredicate: (day) => !bookedDates.contains(DateTime(day.year, day.month, day.day)),
                      );
                      if (date != null) {
                        setState(() => selectedEndDate = date);
                      }
                    },
                    child: Text(selectedEndDate != null ? DateFormat('MMM dd, yyyy').format(selectedEndDate!) : (selectedStartDate == null ? 'Select Start First' : 'Select Date')),
                  )
                ]
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () async {
                if (selectedStartDate == null || selectedEndDate == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select both start and end dates.')));
                  return;
                }
                
                DateTime checkDate = selectedStartDate!;
                bool conflict = false;
                while (!checkDate.isAfter(selectedEndDate!)) {
                  if (bookedDates.contains(DateTime(checkDate.year, checkDate.month, checkDate.day))) {
                    conflict = true;
                    break;
                  }
                  checkDate = checkDate.add(const Duration(days: 1));
                }

                if (conflict) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selected range overlaps with an existing booking.')));
                  return;
                }

                int days = selectedEndDate!.difference(selectedStartDate!).inDays + 1;
                Navigator.pop(dialogContext); // Pops the date picker dialog

                if (!mounted) return;

                showDialog(
                  context: context, // Outer context
                  barrierDismissible: false,
                  builder: (loadingContext) => const Center(child: CircularProgressIndicator()),
                );

                try {
                  await FirebaseDatabase.instance.ref('properties/$uid/roomInventory/$roomId').update({
                    'isDisabled': true,
                    'disabledStartDate': DateFormat('yyyy-MM-dd').format(selectedStartDate!),
                    'disabledDays': days,
                  });
                  if (mounted) {
                    Navigator.pop(context); // close loading dialog
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Room disabled successfully.')));
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(context); // close loading dialog
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to disable room: $e')));
                  }
                }
              },
              child: const Text('Disable'),
            )
          ],
        )
      )
    );
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

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setS) {
        Map<String, double> monthlyRevenue = {};
        Map<String, double> monthlyPending = {};
        Map<String, int> roomSales = {};
        Map<String, List<Map<String, dynamic>>> monthDetails = {};
        Map<String, List<Map<String, dynamic>>> pendingDetails = {};
        double filteredTotal = 0;
        double filteredPendingTotal = 0;

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
            if (status != 'cancelled' &&
                status != 'declined' &&
                status != 'refund approved' &&
                status != 'refund confirmed') {
              // Exclude historical records marked not counting toward revenue
              if (value['isHistorical'] == true && value['countsTowardRevenue'] == false) {
                return;
              }
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

                  bool matchMonth =
                      selectedMonth == "All" || selectedMonth == monthKey;
                  bool matchYear =
                      selectedYear == "All" || selectedYear == yearKey;

                  if (matchMonth && matchYear) {
                    double total = double.tryParse((value['totalPrice'] ??
                                value['total'] ??
                                value['amount'] ??
                                value['payment'] ??
                                value['price'] ??
                                '0')
                            .toString()
                            .replaceAll(',', '')) ??
                        0;
                    double paid = double.tryParse((value['amountPaid'] ?? '0')
                            .toString()
                            .replaceAll(',', '')) ??
                        0;
                    String payOption = (value['paymentOption'] ??
                            value['paymentMethod'] ??
                            '')
                        .toString()
                        .toLowerCase();

                    if (paid == 0 && total > 0) {
                      if (payOption.contains('30%') ||
                          payOption.contains('downpayment')) {
                        paid = total * 0.3;
                      } else if (payOption.contains('full') ||
                          payOption.contains('100%') ||
                          value['paymentStatus'] == 'paid' || value['isPaid'] == true) {
                        paid = total;
                      }
                    }

                    if ((status == 'completed' || status == 'checked out') &&
                        paid == 0) {
                      paid = total;
                    }

                    double pending = 0;
                    if (status != 'cancelled') {
                      pending = (total - paid) > 0 ? (total - paid) : 0;
                    }
                    String room = value['activityTitle'] ??
                        value['roomTitle'] ??
                        value['room'] ??
                        value['roomId'] ??
                        'Unknown Room';

                    if (status != 'declined' && status != 'refund approved' && status != 'refund confirmed' && status != 'refund requested') {
                      if (paid > 0) {
                        monthlyRevenue[monthKey] =
                            (monthlyRevenue[monthKey] ?? 0) + paid;
                        filteredTotal += paid;
                      roomSales[room] = (roomSales[room] ?? 0) + 1;

                      if (monthDetails[monthKey] == null) {
                        monthDetails[monthKey] = [];
                      }
                      monthDetails[monthKey]!.add({
                        'room': room,
                        'date': dateStr,
                        'nights': int.tryParse(value['nights']?.toString() ?? '1') ?? 1,
                        'tourist': value['touristName'] ??
                            value['customerName'] ??
                            value['userName'] ??
                            value['name'] ??
                            value['fullName'] ??
                            'Tourist',
                        'amount': paid,
                        'rawBooking': value,
                      });
                    }
                    }

                    if (pending > 0) {
                      monthlyPending[monthKey] =
                          (monthlyPending[monthKey] ?? 0) + pending;
                      filteredPendingTotal += pending;

                      if (pendingDetails[monthKey] == null) {
                        pendingDetails[monthKey] = [];
                      }
                      pendingDetails[monthKey]!.add({
                        'room': room,
                        'date': dateStr,
                        'nights': int.tryParse(value['nights']?.toString() ?? '1') ?? 1,
                        'tourist': value['touristName'] ??
                            value['customerName'] ??
                            value['userName'] ??
                            value['name'] ??
                            value['fullName'] ??
                            'Tourist',
                        'amount': pending,
                        'rawBooking': value,
                      });
                    }
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Current Revenue:',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('₱${filteredTotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Colors.green,
                                  fontSize: 16),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Pending Balances:',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('+ ₱${filteredPendingTotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Colors.orange,
                                  fontSize: 16),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Expected Total:',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('₱${(filteredTotal + filteredPendingTotal).toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.primaryAccent,
                                  fontSize: 16),
                              overflow: TextOverflow.ellipsis),
                        ],
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
                    ...(() {
                      final sortedEntries = monthlyRevenue.entries.toList()
                        ..sort((a, b) {
                          DateTime? da;
                          DateTime? db;
                          try { da = DateFormat('MMMM yyyy').parse(a.key); } catch (_) {}
                          try { db = DateFormat('MMMM yyyy').parse(b.key); } catch (_) {}
                          return (da ?? DateTime(1970)).compareTo(db ?? DateTime(1970));
                        });
                      return sortedEntries.map((e) {
                        List<Map<String, dynamic>> details =
                            monthDetails[e.key] ?? [];
                        return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        elevation: 0,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[850]
                            : Colors.grey[50],
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: Colors.grey.withOpacity(0.2))),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => MonthlyReportPage(
                                        monthName: e.key,
                                        details: details,
                                        pendingDetails: pendingDetails[e.key] ?? [],
                                        totalRevenue: e.value,
                                        totalPending: monthlyPending[e.key] ?? 0)));
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
                                                color: Theme.of(context)
                                                            .brightness ==
                                                        Brightness.dark
                                                    ? Colors.white70
                                                    : Colors.black87,
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
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                                '₱${e.value.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: AppTheme.secondaryAccent,
                                                    fontSize: 16),
                                                overflow: TextOverflow.ellipsis),
                                            if ((monthlyPending[e.key] ?? 0) > 0)
                                              Text(
                                                '+ ₱${(monthlyPending[e.key] ?? 0).toStringAsFixed(2)} Pending',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.orange,
                                                    fontSize: 10),
                                                overflow: TextOverflow.ellipsis),
                                          ],
                                        ),
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
                    }).toList();
                  })(),
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
        'showActivities': _showActivities,
        'enableCustomMenuUpload': _enableCustomMenuUpload,
        'addonPrices': _addonPrices,
        'rooms': int.tryParse(_roomsController.text) ?? 0,
        'staffCount': int.tryParse(_staffController.text) ?? 0,
        'checkInTime': _checkInController.text.trim(),
        'checkOutTime': _checkOutController.text.trim(),
        'receptionOpenUntil': _receptionController.text.trim(),
        'bookingInstructions': _instrController.text.trim(),
        'latitude': double.tryParse(_latController.text) ?? 0.0,
        'longitude': double.tryParse(_lngController.text) ?? 0.0,
        'contactPhone': _contactPhoneController.text.trim(),
        'contactEmail': _contactEmailController.text.trim(),
        'maxCapacity': int.tryParse(_capacityController.text) ?? 0,
        'amenities': _selectedAmenities,
        'gcashNumber': _gcashNumberController.text.trim(),
        'gcashName': _gcashNameController.text.trim(),
        'cancellationPolicy': _cancellationPolicyController.text.trim(),
        'paymentPolicy': _paymentPolicyController.text.trim(),
        'resortRules': _resortRulesController.text.trim(),
        'petPolicy': _petPolicyController.text.trim(),
        'safetyGuidelines': _safetyGuidelinesController.text.trim(),
        'gcashQrUrl': _gcashQrUrl,
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
        String prefix =
            _roomLocation.isNotEmpty ? _roomLocation[0].toUpperCase() : "R";

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
        'isAvailable': _roomIsAvailable,
        'timestamp': ServerValue.timestamp,
      };

      if (_activityVideoUrl != null) {
        data['videoUrl'] = _activityVideoUrl;
      }

      if (_editingActivityKey != null) {
        await ref.update(data);
      } else {
        await ref.set(data);
      }

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

  Future<void> _pickAndUploadQrImage({required Function setModalState}) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile != null) {
      setModalState(() => _isSubmitting = true);
      final url = await _uploadToCloudinary(File(pickedFile.path));
      if (url != null) {
        setModalState(() => _gcashQrUrl = url);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to upload QR code')));
        }
      }
      setModalState(() => _isSubmitting = false);
    }
  }

  // --- QR Scanner ---

  void _openScanner() async {
    final code = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BookingScannerScreen()),
    );
    if (code != null) {
      _processScannedCode(code.toString());
    }
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

        String currentStatus =
            (booking['status'] ?? '').toString().toLowerCase();

        _showBookingDetailsDialog(bookingId, booking, scannedViaQr: true);
      } else {
        _showErrorDialog("Invalid QR Code. Booking '$bookingId' not found.");
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showErrorDialog("Error: $e");
    }
  }

  void _showExtendStayDialog(String key, Map b) {
    int additionalNights = 1;
    bool isLoading = false;
    String error = '';
    
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Extend Stay'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('How many additional nights would the tourist like to extend?'),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: additionalNights > 1 ? () => setDialogState(() => additionalNights--) : null,
                      ),
                      Text('$additionalNights', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: additionalNights < 10 ? () => setDialogState(() => additionalNights++) : null,
                      ),
                    ],
                  ),
                  if (error.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(error, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  ],
                  if (isLoading) ...[
                     const SizedBox(height: 16),
                     const CircularProgressIndicator()
                  ]
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    setDialogState(() { isLoading = true; error = ''; });
                    try {
                      final activityId = b['activityId'] ?? b['roomId'];
                      if (activityId == null) throw Exception('Room ID not found');
                      
                      Map tempBooking = Map.from(b);
                      int currentNights = int.tryParse(b['nights']?.toString() ?? '1') ?? 1;
                      tempBooking['nights'] = currentNights + additionalNights;
                      
                      bool hasConflict = await _checkBookingConflict(key, activityId, tempBooking);
                      if (hasConflict) {
                        setDialogState(() {
                          isLoading = false;
                          error = 'Conflict: Room is already booked during the extended dates.';
                        });
                        return;
                      }
                      
                      double grandTotal = 0;
                      double oldBasePrice = 0;
                      if (b['pricing'] != null && b['pricing'] is Map) {
                         grandTotal = double.tryParse(b['pricing']['grandTotal']?.toString() ?? '0') ?? 0;
                         oldBasePrice = double.tryParse(b['pricing']['basePrice']?.toString() ?? '0') ?? 0;
                      } else {
                         grandTotal = double.tryParse(b['totalPrice']?.toString() ?? '0') ?? 0;
                         double addonsTotal = 0;
                         if (b['selectedAddons'] is List) {
                           for (var addon in b['selectedAddons']) {
                             addonsTotal += double.tryParse(addon['price']?.toString() ?? '0') ?? 0;
                           }
                         }
                         oldBasePrice = (grandTotal - addonsTotal);
                         if (oldBasePrice < 0) oldBasePrice = 0;
                      }
                      
                      double pricePerNight = currentNights > 0 ? (oldBasePrice / currentNights) : 0;
                      double extraCost = pricePerNight * additionalNights;
                      
                      Map<String, dynamic> updates = {
                         'nights': currentNights + additionalNights,
                      };
                      
                      if (b['pricing'] != null && b['pricing'] is Map) {
                         Map pricing = Map.from(b['pricing']);
                         pricing['basePrice'] = oldBasePrice + extraCost;
                         pricing['grandTotal'] = grandTotal + extraCost;
                         updates['pricing'] = pricing;
                      } else {
                         updates['totalPrice'] = grandTotal + extraCost;
                      }
                      
                      await FirebaseDatabase.instance.ref("bookings/$key").update(updates);
                      
                      if (mounted) {
                         Navigator.pop(context);
                         ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
                             content: Text('Stay extended successfully! Added \u20b1${extraCost.toStringAsFixed(2)} to balance.'),
                             backgroundColor: Colors.green,
                         ));
                      }
                    } catch (e) {
                      setDialogState(() {
                        isLoading = false;
                        error = 'An error occurred: $e';
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  child: const Text('Extend Stay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      }
    );
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

  void _showStatusConfirmation(String key, String newStatus, Map b, {bool? markAsPaid}) {
    String msg = "Are you sure you want to mark this booking as $newStatus?";
    if (newStatus == 'Confirmed') {
      msg = "Are you sure you want to confirm this booking?";
    } else if (newStatus == 'Checked In') {
      msg = "Are you sure you want to check-in this customer?";
    } else if (newStatus == 'No Show') {
      msg = "Are you sure you want to mark this reservation as No Show? This will release dates and update the status.";
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm $newStatus'),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _updateBookingStatus(key, newStatus, b, skipConfirm: true, markAsPaid: markAsPaid);
            },
            child: Text('Confirm',
                style: TextStyle(
                    color: ['Cancelled', 'Declined', 'Refund Declined', 'Reschedule Declined', 'No Show'].contains(newStatus) ? AppTheme.primaryAccent : Colors.green, 
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showBookingDetailsDialog(String key, Map b, {bool scannedViaQr = false}) {
    String status = (b['status'] ?? 'Pending').toString().trim().toLowerCase();
    Color statusColor = (status == 'confirmed' || status == 'refund confirmed')
        ? Colors.green
        : (status == 'cancelled'
            ? AppTheme.primaryAccent
            : (status == 'completed'
                ? Colors.blue
                : (status == 'checked in' 
                    ? Colors.indigo 
                    : (status == 'no show' ? Colors.grey[700]! : Colors.orange))));
    List addons = b['selectedAddons'] is List ? b['selectedAddons'] : [];

    final rawArrival = b['bookingDate'] ?? b['checkInDate'] ?? b['date'] ?? b['createdAt'] ?? b['timestamp'];
    final parsedStart = _parseTolerantDate(rawArrival);
    String? bookingDate = parsedStart != null ? DateFormat('MMM dd, yyyy').format(parsedStart) : (rawArrival?.toString());

    bool isActivity = b['isActivityBooking'] == true ||
        (b['roomId'] == null &&
            b['roomTitle'] == null &&
            !(b['activityTitle']?.toString().toLowerCase().contains('room') ?? false) &&
            b['nights'] == null &&
            b['activityId'] != null &&
            b['activityId'].toString().trim().isNotEmpty);

    final duration = int.tryParse((b['hours'] ?? b['nights'] ?? 1).toString()) ?? 1;

    String dateRange = bookingDate ?? 'N/A';
    try {
      if (parsedStart != null) {
        if (isActivity) {
          dateRange = "$bookingDate ($duration ${duration == 1 ? 'Hour' : 'Hours'})";
        } else {
          int nights = int.tryParse(b['nights']?.toString() ?? '1') ?? 1;
          final rawDeparture = b['departureDate'] ?? b['checkOutDate'];
          final parsedEnd = _parseTolerantDate(rawDeparture) ?? parsedStart.add(Duration(days: nights));
          final endFormatted = DateFormat('MMM dd, yyyy').format(parsedEnd);
          dateRange = "$bookingDate - $endFormatted ($nights Nights)";
        }
      }
    } catch (e) {}

    double total = double.tryParse(((b['pricing'] != null ? b['pricing']['grandTotal'] : null) ?? b['totalPrice'] ??
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
    if (balance < 0) balance = 0;

    String? r = (b['gcashReceipt'] != null &&
            b['gcashReceipt'].toString().trim().isNotEmpty)
        ? b['gcashReceipt'].toString()
        : ((b['historicalPhotoUrl'] != null && b['historicalPhotoUrl'].toString().trim().isNotEmpty)
            ? b['historicalPhotoUrl'].toString()
            : (b['paymentReceiptDataUrl']?.toString()));
    String? photo = b['touristProfilePic'];
    String touristName = b['touristName'] ??
        b['customerName'] ??
        b['userName'] ??
        b['name'] ??
        b['fullName'] ??
        'Guest';

    // AI Verification data extraction
    final ocrStatus = (b['ocrStatus'] ?? '').toString().trim();
    final hasAiVerification = b['isHistorical'] != true && (ocrStatus.isNotEmpty || (b['extractedRefNo'] != null && b['extractedRefNo'].toString().trim().isNotEmpty));
    final isVerified = ocrStatus == 'Verified';

    final rawReason = b['ocrIssues'] ?? b['ocrReason'] ?? b['flaggedReason'] ?? b['verificationDetails'];
    String reasonText = '';
    if (rawReason is String) {
      reasonText = rawReason.trim();
    } else if (rawReason is List) {
      reasonText = rawReason.where((e) => e != null && e.toString().trim().isNotEmpty).map((e) => e.toString().trim()).join(', ');
    } else if (rawReason is Map) {
      reasonText = rawReason.values.where((e) => e != null && e.toString().trim().isNotEmpty).map((e) => e.toString().trim()).join(', ');
    }
    if (reasonText.isEmpty && hasAiVerification && !isVerified) {
      reasonText = "No detailed reason was recorded for this booking.";
    }

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final cardBg = isDark ? Colors.grey[900]! : const Color(0xFFF9FAFB);
        final borderColor = isDark ? Colors.grey[800]! : const Color(0xFFE5E7EB);
        final mutedColor = isDark ? Colors.grey[400]! : const Color(0xFF6B7280);

        Widget buildItemRow({
          required IconData icon,
          required Color iconColor,
          required String label,
          required Widget child,
        }) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: mutedColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    child,
                  ],
                ),
              ),
            ],
          );
        }

        return Dialog(
          backgroundColor: Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 550),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: Title + Status Badge + Close Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Verification Result',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: statusColor.withOpacity(0.3)),
                              ),
                              child: Text(
                                b['status'] ?? 'Pending',
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, size: 22),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Inner Card Container
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Guest Header Profile
                        Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: photo != null && photo.isNotEmpty
                                  ? Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.person, size: 30, color: Theme.of(context).colorScheme.secondary))
                                  : Icon(Icons.person, size: 30, color: Theme.of(context).colorScheme.secondary),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    touristName,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Guest Verification',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: mutedColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Divider(color: borderColor, height: 1),
                        const SizedBox(height: 16),

                        // Details Group (matching Web Verification Result)
                        // 1. Booked Room / Booked Activity
                        buildItemRow(
                          icon: Icons.home_rounded,
                          iconColor: Theme.of(context).colorScheme.primary,
                          label: isActivity ? 'Booked Activity' : 'Booked Room',
                          child: Text(
                            (b['activityTitle'] ?? b['roomTitle'] ?? b['activityName'] ?? b['room'] ?? b['roomId'] ?? 'N/A').toString(),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 2. Dates
                        if (b['isHistorical'] == true) ...[
                          buildItemRow(
                            icon: Icons.calendar_today_rounded,
                            iconColor: Theme.of(context).colorScheme.secondary,
                            label: 'Arrival Date',
                            child: Text(
                              parsedStart != null ? DateFormat('MMM dd, yyyy').format(parsedStart) : (bookingDate ?? 'N/A'),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (!isActivity) ...[
                            const SizedBox(height: 14),
                            buildItemRow(
                              icon: Icons.calendar_month_rounded,
                              iconColor: Theme.of(context).colorScheme.primary,
                              label: 'Departure Date',
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: () {
                                        final rawDep = b['departureDate'] ?? b['checkOutDate'];
                                        final pEnd = _parseTolerantDate(rawDep) ?? (parsedStart != null ? parsedStart.add(Duration(days: duration)) : null);
                                        return pEnd != null ? DateFormat('MMM dd, yyyy').format(pEnd) : 'N/A';
                                      }(),
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                                    ),
                                    TextSpan(
                                      text: ' ($duration ${duration == 1 ? 'Night' : 'Nights'})',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: mutedColor),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ] else ...[
                          buildItemRow(
                            icon: Icons.calendar_today_rounded,
                            iconColor: Theme.of(context).colorScheme.secondary,
                            label: isActivity ? 'Activity Date & Duration' : 'Check-in Date & Duration',
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: dateRange,
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                                  ),
                                  TextSpan(
                                    text: ' ($duration ${isActivity ? 'Hour/s' : (duration == 1 ? 'Night' : 'Nights')})',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: mutedColor),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),

                        // 3. Guest Arrival Time
                        buildItemRow(
                          icon: Icons.access_time_rounded,
                          iconColor: Theme.of(context).colorScheme.primary,
                          label: 'Guest Arrival Time',
                          child: Text(
                            (b['arrivalTime'] ?? b['timeSlot'] ?? b['bookingTime'] ?? (isActivity ? 'Regular Operating Hours' : 'Check-in Time')).toString(),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 4. Payment Breakdown
                        buildItemRow(
                          icon: Icons.trending_up_rounded,
                          iconColor: const Color(0xFF10B981),
                          label: 'Payment Breakdown',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Total:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  Text('₱${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Paid:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF059669))),
                                  Text('₱${paid.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF059669))),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Divider(color: borderColor, height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Balance:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                  Text(
                                    '₱${balance.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      color: balance > 0 ? Theme.of(context).colorScheme.primary : const Color(0xFF059669),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 5. Payment Details
                        buildItemRow(
                          icon: Icons.credit_card_rounded,
                          iconColor: const Color(0xFF1D4ED8),
                          label: 'Payment Details',
                          child: Text(
                            "${(b['paymentOption'] ?? 'Full Payment')} via ${(b['paymentMethod'] ?? 'GCash')}",
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),

                        // 6. Refund Request Details (if any)
                        if (status == 'refund requested') ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'REFUND REQUEST DETAILS',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFEF4444)),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Reason: ${b['refundReason'] ?? 'No reason provided'}",
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 3),
                                      FutureBuilder(
                                        future: FirebaseDatabase.instance.ref('users/${b['touristUid'] ?? ''}').get(),
                                        builder: (context, AsyncSnapshot snap) {
                                          String gn = (b['touristGcashName'] != null && b['touristGcashName'].toString().isNotEmpty)
                                              ? b['touristGcashName'].toString()
                                              : ((b['gcashName'] != null && b['gcashName'].toString().isNotEmpty) ? b['gcashName'].toString() : 'N/A');
                                          String gnum = (b['touristGcashNumber'] != null && b['touristGcashNumber'].toString().isNotEmpty)
                                              ? b['touristGcashNumber'].toString()
                                              : ((b['gcashNumber'] != null && b['gcashNumber'].toString().isNotEmpty) ? b['gcashNumber'].toString() : 'N/A');
                                          if (snap.hasData && snap.data!.exists) {
                                            final u = snap.data!.value as Map;
                                            if (gn == 'N/A' && u['gcashName'] != null && u['gcashName'].toString().trim().isNotEmpty) gn = u['gcashName'].toString();
                                            if (gnum == 'N/A' && u['gcashNumber'] != null && u['gcashNumber'].toString().trim().isNotEmpty) gnum = u['gcashNumber'].toString();
                                          }
                                          return Text("Send To: $gn ($gnum)", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800));
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // 7. Reschedule Request Details (if any)
                        if (status == 'reschedule requested') ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4F46E5).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.event_repeat_rounded, size: 18, color: Color(0xFF4F46E5)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'RESCHEDULE REASON',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF4F46E5)),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Reschedule to: ${b['requestedRescheduleDate'] ?? 'Date'} (${b['requestedRescheduleNights'] ?? b['nights'] ?? 1} Night/s)",
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "Reason: ${b['rescheduleReason'] ?? 'None provided'}",
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // 8. Add-ons
                        if (addons.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          buildItemRow(
                            icon: Icons.add_box_rounded,
                            iconColor: Theme.of(context).colorScheme.primary,
                            label: 'Add-ons',
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: addons.map<Widget>((a) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Text(
                                    a.toString(),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],

                        if (b['cancellationReason'] != null && b['cancellationReason'].toString().trim().isNotEmpty) ...[
                          const SizedBox(height: 14),
                          buildItemRow(
                            icon: Icons.info_outline_rounded,
                            iconColor: AppTheme.primaryAccent,
                            label: 'Cancellation Note',
                            child: Text(
                              b['cancellationReason'].toString(),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent),
                            ),
                          ),
                        ],

                        // View Price Breakdown Button
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => PriceBreakdownDialog(booking: b),
                              );
                            },
                            icon: const Icon(Icons.shopping_bag_outlined, size: 16),
                            label: const Text('View Price Breakdown', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5).withOpacity(0.1),
                              foregroundColor: const Color(0xFF4F46E5),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: const Color(0xFF4F46E5).withOpacity(0.2)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Close and View Receipt Row (matching Web)
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            side: BorderSide(color: borderColor),
                          ),
                          child: const Text('Close', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      if (r != null && r != 'MANUAL_GCASH_PAYMENT') ...[
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: () => _viewReceipt(r),
                          icon: const Icon(Icons.visibility_outlined, size: 16),
                          label: Text(
                            b['isHistorical'] == true ? 'View Photo' : 'View Receipt',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1D4ED8).withOpacity(0.1),
                            foregroundColor: const Color(0xFF2563EB),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // AI Verification Card (matching Web exact wording and badges)
                  if (hasAiVerification) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isVerified ? const Color(0xFF10B981).withOpacity(0.1) : const Color(0xFFF59E0B).withOpacity(0.1),
                        border: Border.all(
                          color: isVerified ? const Color(0xFF10B981).withOpacity(0.25) : const Color(0xFFF59E0B).withOpacity(0.25),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isVerified ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                            size: 18,
                            color: isVerified ? const Color(0xFF059669) : const Color(0xFFB45309),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "AI Verification: ${isVerified ? 'Passed' : (ocrStatus == 'Multiple Receipts (Manual Review)' ? 'Multiple Receipts' : 'Flagged for Review')}",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: isVerified ? const Color(0xFF059669) : const Color(0xFFB45309),
                                  ),
                                ),
                                if (b['extractedRefNo'] != null && b['extractedRefNo'].toString().trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    "Ref No: ${b['extractedRefNo']}",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isVerified ? const Color(0xFF059669) : const Color(0xFFB45309),
                                    ),
                                  ),
                                ],
                                if (reasonText.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    "Reason: $reasonText",
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFB45309),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Action Buttons (Decline / Confirm / Check-in / Reschedule / Refund etc.)
                  if (['pending', 'reschedule requested', 'refund requested', 'confirmed', 'checked in', 'refund declined', 'no show'].contains(status)) ...[
                    const SizedBox(height: 14),
                    if (status == 'pending') ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _updateBookingStatus(key, 'Cancelled', b);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFB3640).withOpacity(0.15),
                                foregroundColor: AppTheme.primaryAccent,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Decline', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _showStatusConfirmation(key, 'Confirmed', b);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Confirm', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (status == 'reschedule requested') ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _updateBookingStatus(key, 'Reschedule Declined', b);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFB3640).withOpacity(0.15),
                                foregroundColor: AppTheme.primaryAccent,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Decline Reschedule', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _updateBookingStatus(key, 'Reschedule Approved', b);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Approve Reschedule', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (status == 'refund requested') ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _updateBookingStatus(key, 'Refund Declined', b);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFB3640).withOpacity(0.15),
                                foregroundColor: AppTheme.primaryAccent,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Decline Refund', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _updateBookingStatus(key, 'Refund Approved', b);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Approve Refund', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (status == 'refund approved') ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _updateBookingStatus(key, 'Refund Confirmed', b);
                          },
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text('Confirm Refund', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                    if (status == 'confirmed' || status == 'refund declined')
                      (() {
                        bool canCheckIn = true;
                        bool isExpired = false;
                        String? bDateStr = b['bookingDate'];
                        if (bDateStr != null && bDateStr.isNotEmpty) {
                          try {
                            DateTime parsed = DateFormat("MMM dd, yyyy").parse(bDateStr);
                            DateTime today = DateTime.now();
                            DateTime todayMidnight = DateTime(today.year, today.month, today.day);
                            DateTime parsedMidnight = DateTime(parsed.year, parsed.month, parsed.day);
                            int nights = int.tryParse(b['nights']?.toString() ?? '1') ?? 1;
                            DateTime endDate = parsedMidnight.add(Duration(days: nights));
                            
                            if (todayMidnight.isAfter(endDate)) {
                              canCheckIn = false;
                              isExpired = true;
                            } else if (todayMidnight.isBefore(parsedMidnight)) {
                              canCheckIn = false;
                            }
                          } catch(e) {}
                        }

                        if (isExpired) {
                          return SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _showStatusConfirmation(key, 'No Show', b);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Mark as No Show (Checkout Expired)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                          );
                        }

                        if (!scannedViaQr) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFB3640).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.qr_code_scanner_rounded, size: 16, color: AppTheme.primaryAccent),
                                    SizedBox(width: 6),
                                    Text(
                                      'Please use QR Scanner to Check-In Customer',
                                      style: TextStyle(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 12),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _showStatusConfirmation(key, 'No Show', b);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade100,
                                    foregroundColor: Colors.red.shade900,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Mark as No Show', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          );
                        }

                        bool markAsPaid = false;
                        return StatefulBuilder(
                          builder: (context, setDialogState) {
                            return Column(
                              children: [
                                if (balance > 0)
                                  Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
                                        child: Text('Remaining Balance: ₱${balance.toStringAsFixed(2)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15)),
                                      ),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Checkbox(
                                            value: markAsPaid,
                                            onChanged: canCheckIn ? (val) {
                                              setDialogState(() {
                                                markAsPaid = val ?? false;
                                              });
                                            } : null,
                                          ),
                                          Text('Mark balance as paid', style: TextStyle(color: canCheckIn ? null : Colors.grey)),
                                        ],
                                      ),
                                    ],
                                  ),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: (canCheckIn && (balance <= 0 || markAsPaid)) ? () {
                                      Navigator.pop(context);
                                      _showStatusConfirmation(key, 'Checked In', b, markAsPaid: markAsPaid);
                                    } : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: canCheckIn ? Colors.indigo : Colors.grey,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: Text(canCheckIn ? 'Check In Customer' : 'Check-in on ${b['bookingDate']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      })(),
                    if (status == 'checked in') ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _showCheckoutConfirmation(key, b);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('VERIFY CHECK-OUT', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _showExtendStayDialog(key, b);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('EXTEND STAY', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                    if (status == 'no show') ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _deleteBookingDirectly(key);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Delete No Show Record', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
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
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Show "Book Activities" to Guests',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text(
                            _showActivities
                                ? 'Activities section will be displayed on your property page'
                                : 'Activities section will be hidden (recommended for standard hotels)',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          value: _showActivities,
                          activeColor: AppTheme.primaryAccent,
                          onChanged: (val) {
                            setModalState(() => _showActivities = val);
                            setState(() => _showActivities = val);
                          },
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Enable Custom Food Menu Upload',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text(
                            _enableCustomMenuUpload
                                ? 'Upload digital menu images instead of standard meal counters'
                                : 'Default to standard interactive (+/-) meal quantity counters',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          value: _enableCustomMenuUpload,
                          activeColor: AppTheme.primaryAccent,
                          onChanged: (val) {
                            setModalState(() => _enableCustomMenuUpload = val);
                            setState(() => _enableCustomMenuUpload = val);
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                            _propNameController, 'Name', Icons.business,
                            maxLength: 50,
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s]'))]),
                        const SizedBox(height: 12),
                        _buildTextField(_propDescController, 'Description',
                            Icons.description,
                            maxLines: 2, maxLength: 500),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: _buildTextField(_checkInController,
                                  'Check-in', Icons.login_rounded,
                                  placeholder: '2:00 PM',
                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s:]'))])),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _buildTextField(_checkOutController,
                                  'Check-out', Icons.logout_rounded,
                                  placeholder: '12:00 PM',
                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s:]'))])),
                        ]),
                        const SizedBox(height: 12),
                        _buildTextField(_receptionController,
                            'Reception Open Until', Icons.access_time_rounded,
                            placeholder: '10:00 PM',
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9:\sAPMapm]')),
                              LengthLimitingTextInputFormatter(8),
                            ],
                            onChanged: (val) {
                              final upper = val.toUpperCase();
                              if (val != upper) {
                                _receptionController.value = _receptionController.value.copyWith(
                                  text: upper,
                                  selection: TextSelection.collapsed(offset: upper.length),
                                );
                              }
                            }),
                        const SizedBox(height: 12),
                        _buildTextField(
                            _instrController,
                            'Booking Instructions / House Rules',
                            Icons.list_alt_rounded,
                            maxLines: 3,
                            required: false,
                            maxLength: 1000,
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s.,!?\x27"()-]'))]),
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
                            keyboardType: TextInputType.emailAddress,
                            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                            onChanged: (val) {
                              final lower = val.toLowerCase();
                              if (val != lower) {
                                _contactEmailController.value = _contactEmailController.value.copyWith(
                                  text: lower,
                                  selection: TextSelection.collapsed(offset: lower.length),
                                );
                              }
                            }),
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
                        const SizedBox(height: 16),
                        
                        // Policies section
                        const Divider(height: 32),
                        const Text('Policies & Guidelines', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        _buildTextField(_cancellationPolicyController, 'Cancellation & Refund Policy', Icons.policy_rounded, maxLines: 3, required: false, placeholder: 'e.g. Full refund if cancelled 7 days prior.', inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s.,!?\x27"()-]'))]),
                        const SizedBox(height: 16),
                        _buildTextField(_paymentPolicyController, 'Payment Policies', Icons.payment_rounded, maxLines: 3, required: false, placeholder: 'e.g. Partial deposit required upon booking.', inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s.,!?\x27"()-]'))]),
                        const SizedBox(height: 16),
                        _buildTextField(_resortRulesController, 'Resort Rules', Icons.rule_rounded, maxLines: 4, required: false, placeholder: 'e.g. No smoking inside rooms, quiet hours.', inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s.,!?\x27"()-]'))]),
                        const SizedBox(height: 16),
                        _buildTextField(_petPolicyController, 'Pet Policy', Icons.pets_rounded, maxLines: 2, required: false, placeholder: 'e.g. Pets allowed in designated rooms.', inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s.,!?\x27"()-]'))]),
                        const SizedBox(height: 16),
                        _buildTextField(_safetyGuidelinesController, 'Safety Guidelines', Icons.health_and_safety_rounded, maxLines: 2, required: false, placeholder: 'e.g. Pool safety, emergency exits.', inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s.,!?\x27"()-]'))]),
                        const SizedBox(height: 16),
                        const Divider(height: 32),

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
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\u00C0-\u024F\u1E00-\u1EFF\s.'-]"))
                            ],
                            maxLength: 50),
                        const SizedBox(height: 12),
                        const Text('GCash QR Code', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        if (_gcashQrUrl != null && _gcashQrUrl!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Stack(
                              alignment: Alignment.topRight,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(_gcashQrUrl!,
                                      width: 120, height: 120, fit: BoxFit.cover),
                                ),
                                Positioned(
                                  top: -10,
                                  right: -10,
                                  child: IconButton(
                                    icon: const Icon(Icons.cancel, color: Colors.red),
                                    onPressed: () =>
                                        setModalState(() => _gcashQrUrl = null),
                                  ),
                                )
                              ],
                            ),
                          ),
                        OutlinedButton.icon(
                          onPressed: _isSubmitting
                              ? null
                              : () => _pickAndUploadQrImage(
                                  setModalState: setModalState),
                          icon: const Icon(Icons.qr_code_2),
                          label: Text((_gcashQrUrl == null || _gcashQrUrl!.isEmpty)
                              ? 'Upload QR Code'
                              : 'Change QR Code'),
                          style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  Theme.of(context).colorScheme.primary,
                              side: BorderSide(
                                  color: Theme.of(context).colorScheme.primary)),
                        ),
                        const SizedBox(height: 24),
                        const Text('Add-ons & Extras Prices',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        ..._addonPrices.entries.map((entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text(entry.key,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      initialValue: entry.value.toString(),
                                      decoration: const InputDecoration(
                                        labelText: 'Price (₱)',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (val) {
                                        _addonPrices[entry.key] =
                                            int.tryParse(val) ?? 0;
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    onPressed: () {
                                      setModalState(() {
                                        _addonPrices.remove(entry.key);
                                      });
                                    },
                                  )
                                ],
                              ),
                            )),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _newAddonNameController,
                                decoration: const InputDecoration(
                                  labelText: 'Custom Add-on Name',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () {
                                final name =
                                    _newAddonNameController.text.trim();
                                if (name.isNotEmpty &&
                                    !_addonPrices.containsKey(name)) {
                                  setModalState(() {
                                    _addonPrices[name] = 0;
                                    _newAddonNameController.clear();
                                  });
                                }
                              },
                              child: const Text('Add'),
                            )
                          ],
                        ),
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
                              decoration: const InputDecoration(
                                  labelText: 'Category (Type)'),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s]'))],
                              onChanged: (v) => _roomCategory = v,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              initialValue: _roomLocation,
                              decoration: const InputDecoration(
                                  labelText: 'Location in Property',
                                  hintText: 'e.g. Penthouse, Riverside'),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s]'))],
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
                          maxLines: 2, required: false, maxLength: 200,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s.,!?\x27"()-]'))]),
                      const SizedBox(height: 16),
                      const SizedBox(height: 16),
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
          StreamBuilder<DatabaseEvent>(
            stream: FirebaseDatabase.instance
                .ref("notifications/${FirebaseAuth.instance.currentUser?.uid}")
                .onValue,
            builder: (context, notifSnap) {
              int unreadCount = 0;
              if (notifSnap.hasData && notifSnap.data!.snapshot.exists) {
                final data = notifSnap.data!.snapshot.value;
                if (data is Map) {
                  data.forEach((k, v) {
                    if (v is Map && v['isRead'] != true && v['isArchived'] != true) {
                      unreadCount++;
                    }
                  });
                }
              }
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_active_rounded),
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const NotificationsPage()));
                    },
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryAccent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 1.5,
                          ),
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Center(
                          child: Text(
                            unreadCount > 99 ? '99+' : unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: Icon(themeProvider.themeMode == ThemeMode.dark
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded),
            color: Theme.of(context).colorScheme.primary,
            onPressed: () => themeProvider.toggleTheme(),
          ),
          IconButton(
            tooltip: 'Import Historical Data',
            icon: const Icon(Icons.history_edu_rounded),
            color: Theme.of(context).colorScheme.primary,
            onPressed: () {
              final user = FirebaseAuth.instance.currentUser;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HistoricalImportPage(
                    isAdmin: false,
                    preselectedPropertyId: user?.uid,
                  ),
                ),
              );
            },
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
                _receptionController.text = data['receptionOpenUntil'] ?? '';
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
                _cancellationPolicyController.text = data['cancellationPolicy'] ?? '';
                _paymentPolicyController.text = data['paymentPolicy'] ?? '';
                _resortRulesController.text = data['resortRules'] ?? '';
                _petPolicyController.text = data['petPolicy'] ?? '';
                _safetyGuidelinesController.text = data['safetyGuidelines'] ?? '';
                _gcashQrUrl = data['gcashQrUrl'];
                _imageUrls = _parseList(data['imageUrls']);
                _propVideoUrls = _parseList(data['videoUrls']);
                _propertyType = data['type'] ?? 'Resort';
                _showActivities = data['showActivities'] ?? (_propertyType != 'Hotel');
                _enableCustomMenuUpload = data['enableCustomMenuUpload'] == true || data['enableCustomMenuUpload'] == 'true';
                if (data['addonPrices'] != null && data['addonPrices'] is Map) {
                  _addonPrices = Map<String, dynamic>.from(data['addonPrices']);
                } else {
                  _addonPrices = {};
                }
              } else {
                _propNameController.clear();
                _propDescController.clear();
                _roomsController.text = '0';
                _staffController.text = '0';
                _checkInController.clear();
                _checkOutController.clear();
                _receptionController.clear();
                _instrController.clear();
                _latController.clear();
                _lngController.clear();
                _contactPhoneController.clear();
                _contactEmailController.clear();
                _capacityController.text = '0';
                _selectedAmenities = [];
                _gcashNumberController.clear();
                _gcashNameController.clear();
                _gcashQrUrl = null;
                _imageUrls = [];
                _propVideoUrls = [];
                _propertyType = 'Resort';
                _showActivities = true;
                _enableCustomMenuUpload = false;
                _addonPrices = {};
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
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: 16),
          tabs: [
            const Tab(text: 'Rooms'),
            const Tab(text: 'Activities'),
            const Tab(text: 'Food Menu'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Bookings'),
                  if (_pendingBookingsCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10)),
                      child: Text(
                          _pendingBookingsCount > 99
                              ? '99+'
                              : _pendingBookingsCount.toString(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ]
                ],
              ),
            ),
            const Tab(text: 'Balances'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Reviews'),
                  if (_unreadReviewsCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.amber.shade700,
                          borderRadius: BorderRadius.circular(10)),
                      child: Text(
                          _unreadReviewsCount > 99
                              ? '99+'
                              : _unreadReviewsCount.toString(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ]
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Chat'),
                  if (_totalUnread > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppTheme.primaryAccent,
                          borderRadius: BorderRadius.circular(10)),
                      child: Text(
                          _totalUnread > 99 ? '99+' : _totalUnread.toString(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ]
                ],
              ),
            ),
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
                _roomIsAvailable = act['isAvailable'] != false;
                _showActivitySheet();
              },
              onDeleteRoom: (key, title) => _deleteActivityDirectly(key),
              onShowRevenue: _showRevenueHistoryDialog,
              onResetRevenue: _showResetRevenueDialog,
              onGoToBookings: () => _tabController.animateTo(3),
              onShowUnpaidBalances: () => _tabController.animateTo(4),
              onDisableRoom: _disableRoom,
            ),
            ActivitiesTab(
              propStream: _propStream,
              activitiesQuery: _propRef.child("activities"),
              onAddActivity: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (ctx) => const ActivityEditSheet(),
                );
              },
              onEditActivity: (key, act) {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (ctx) => ActivityEditSheet(existingActivity: act, activityKey: key),
                );
              },
              onDeleteActivity: (key, title) async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete Activity?'),
                    content: Text('Are you sure you want to remove "$title"?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _propRef.child("activities/$key").remove();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Activity "$title" deleted.')));
                  }
                }
              },
              onToggleVisibility: (val) async {
                setState(() => _showActivities = val);
                await _propRef.update({'showActivities': val});
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(val ? 'Activities are now VISIBLE to guests.' : 'Activities are now HIDDEN from guests.')),
                  );
                }
              },
              onSeedStandardActivities: () async {
                final standardActivities = [
                  {
                    'title': 'Kayak',
                    'price': 300,
                    'maxPax': 1,
                    'description': 'Enjoy a peaceful paddle across scenic waters with our standard single kayak.',
                    'imageUrls': ['https://images.unsplash.com/photo-1544551763-46a013bb70d5?w=800&q=80'],
                    'inclusions': ['Kayak paddle', 'Life vest', 'Safety briefing'],
                    'isAvailable': true,
                  },
                  {
                    'title': 'Paddle Board',
                    'price': 300,
                    'maxPax': 1,
                    'description': 'Stand up paddle board adventure along calm resort waters. Great balance workout.',
                    'imageUrls': ['https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800&q=80'],
                    'inclusions': ['Stand-up paddle', 'Board leash', 'Life vest'],
                    'isAvailable': true,
                  },
                  {
                    'title': 'Boatride to falls',
                    'price': 1450,
                    'maxPax': 3,
                    'minPax': 1,
                    'description': 'Scenic boat journey direct to the majestic falls. (Note: Solo passenger rate includes a ₱750 surcharge, total ₱2,200).',
                    'imageUrls': ['https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=800&q=80'],
                    'inclusions': ['Boat transfer roundtrip', 'Life jackets', 'Tour guide guide fee'],
                    'isAvailable': true,
                  },
                  {
                    'title': 'Boatride to falls with meal',
                    'price': 2000,
                    'maxPax': 3,
                    'minPax': 1,
                    'description': 'Complete falls boat excursion packaged with a fresh resort meal set. (Note: Solo passenger rate includes a ₱750 surcharge, total ₱2,750).',
                    'imageUrls': ['https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=800&q=80'],
                    'inclusions': ['Roundtrip boat transfer', 'Fresh cooked lunch/dinner meal set', 'Bottled water', 'Life jackets'],
                    'isAvailable': true,
                  },
                  {
                    'title': 'Karaoke',
                    'price': 750,
                    'maxPax': 10,
                    'description': 'High-definition karaoke machine with top hits playlist, 2 wireless microphones, and sound system.',
                    'imageUrls': ['https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=800&q=80'],
                    'inclusions': ['Karaoke system', '2 Microphones', 'Song book & remote'],
                    'isAvailable': true,
                  },
                ];

                for (var act in standardActivities) {
                  await _propRef.child("activities").push().set({
                    ...act,
                    'createdAt': ServerValue.timestamp,
                  });
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('5 Standard Activities loaded successfully!')),
                  );
                }
              },
            ),
            FoodMenuTab(propStream: _propStream),
            BookingsTab(
              bookingQuery: _bookingQuery,
              bookingCounts: _bookingCounts,
              onDeleteRecord: (key, name) {},
              onScanQR: _openScanner,
              onTapBooking: (key, booking) =>
                  _showBookingDetailsDialog(key, booking),
            ),
            BalancesTab(ownerId: FirebaseAuth.instance.currentUser!.uid),
            OwnerReviewsTab(
              ownerUid: FirebaseAuth.instance.currentUser?.uid ?? '',
              readReviewIds: _readReviewIds,
              onMarkAsRead: _markReviewAsRead,
              onMarkAllAsRead: _markAllReviewsAsRead,
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
  final VoidCallback onShowUnpaidBalances;
  final Function(String, Map) onDisableRoom;

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
      required this.onGoToBookings,
      required this.onShowUnpaidBalances,
      required this.onDisableRoom});

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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      child: StreamBuilder<DatabaseEvent>(
                        stream: widget.statsStream,
                        builder: (context, bSnapshot) {
                          double totalRevenue = 0;
                          double totalPending = 0;
                          Map bookings = {};
                          int totalBookings = 0;
                          if (bSnapshot.hasData &&
                              bSnapshot.data!.snapshot.exists) {
                            dynamic bValue =
                                bSnapshot.data!.snapshot.value;
                            if (bValue is Map) {
                              bookings = bValue;
                            } else if (bValue is List) {
                              for (int i = 0; i < bValue.length; i++) {
                                if (bValue[i] != null)
                                  bookings[i.toString()] = bValue[i];
                              }
                            }
                            totalBookings = bookings.length;
                            bookings.forEach((key, value) {
                              if (value is Map) {
                                String status = (value['status'] ?? '')
                                    .toString()
                                    .trim()
                                    .toLowerCase();
                                double total = double.tryParse(
                                        value['totalPrice']?.toString() ?? '0') ??
                                    0;
                                String paymentOption =
                                    (value['paymentOption'] ?? '').toString().toLowerCase();
                                double paid = double.tryParse(
                                        value['amountPaid']?.toString() ?? '0') ??
                                    0;

                                if (paid == 0 && total > 0) {
                                  if (paymentOption.contains('30%') ||
                                      paymentOption.contains('downpayment')) {
                                    paid = total * 0.3;
                                  } else if (paymentOption.contains('full') ||
                                      paymentOption.contains('100%') ||
                                      value['paymentStatus'] == 'paid' ||
                                      value['isPaid'] == true) {
                                    paid = total;
                                  }
                                }
                                if ((status == 'completed' ||
                                        status == 'checked out') &&
                                    paid == 0) {
                                  paid = total;
                                }

                                if (status != 'declined' &&
                                    status != 'refund approved' &&
                                    status != 'refund confirmed' &&
                                    status != 'refund requested') {
                                  // Exclude historical bookings marked not counting toward revenue
                                  if (value['isHistorical'] != true || value['countsTowardRevenue'] != false) {
                                    totalRevenue += paid;
                                  }
                                }

                                // Calculate pending balance
                                double remaining = 0;
                                if (status != 'cancelled') {
                                  if (value['isPaid'] == true ||
                                      value['remainingBalance']?.toString() == '0' ||
                                      value['paymentStatus'] == 'fully_paid') {
                                    remaining = 0;
                                  } else if (value['remainingBalance'] != null) {
                                    remaining = double.tryParse(
                                            value['remainingBalance'].toString()) ??
                                        0;
                                  } else {
                                    remaining = total - paid;
                                  }
                                }

                                if (remaining > 0 &&
                                    (status == 'pending' ||
                                        status == 'confirmed' ||
                                        status == 'checked in' ||
                                        status == 'checked-in')) {
                                  totalPending += remaining;
                                }
                              }
                            });
                          }
                          return Row(
                            children: [
                              Expanded(
                                child: _buildStatItem(
                                  'Rooms',
                                  (propData['rooms'] ?? 0).toString(),
                                  Icons.meeting_room_rounded,
                                ),
                              ),
                              Container(
                                height: 36,
                                width: 1,
                                color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: widget.onGoToBookings,
                                  child: _buildStatItem(
                                    'Bookings',
                                    totalBookings.toString(),
                                    Icons.book_online_rounded,
                                  ),
                                ),
                              ),
                              Container(
                                height: 36,
                                width: 1,
                                color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => widget.onShowRevenue(bookings),
                                  onLongPress: widget.onResetRevenue,
                                  child: _buildStatItem(
                                    'Revenue',
                                    '₱${_formatCompactNumber(totalRevenue)}',
                                    Icons.payments_rounded,
                                  ),
                                ),
                              ),
                              Container(
                                height: 36,
                                width: 1,
                                color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: widget.onShowUnpaidBalances,
                                  child: _buildStatItem(
                                    'Unpaid',
                                    '₱${_formatCompactNumber(totalPending)}',
                                    Icons.account_balance_wallet_rounded,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
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
                                          IconButton(
                                              icon: Icon(
                                                  act['isDisabled'] == true ? Icons.check_circle_outline : Icons.block,
                                                  color: act['isDisabled'] == true ? Colors.green : Colors.orange,
                                                  size: 20),
                                              onPressed: () =>
                                                  widget.onDisableRoom(key, act)),
                                        ]))));
                    }),
              ]);
        });
  }

  static String _formatCompactNumber(double value) {
    if (value >= 1000000) {
      return "${(value / 1000000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}M";
    } else if (value >= 1000) {
      return "${(value / 1000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}k";
    }
    return value.toStringAsFixed(0);
  }

  Widget _buildStatItem(String label, String value, IconData icon) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 22),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
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
                      "Refund Confirmed",
                      "Refund Declined",
                      "No Show",
                      "Declined",
                      "Cancelled"
                    ].map((f) {
                      int count = widget.bookingCounts[f] ?? 0;
                      String labelText = f;
                      if (f == 'Reschedule Requested')
                        labelText = 'Reschedule Requests';
                      if (f == 'Refund Requested')
                        labelText = 'Refund Requests';
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text("$labelText ($count)",
                              style: TextStyle(
                                  color: _filter == f ? Colors.white : null,
                                  fontSize: 12)),
                          selected: _filter == f,
                          selectedColor: Theme.of(context).colorScheme.primary,
                          onSelected: (s) {
                            if (s) setState(() => _filter = f);
                          },
                        ),
                      );
                    }).toList(),
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
                List<String> attention = [
                  'Pending',
                  'Reschedule Requested',
                  'Refund Requested'
                ];
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

    Color c = (statusNorm == 'confirmed' || statusNorm == 'refund confirmed')
        ? Colors.green
        : (statusNorm == 'cancelled'
            ? AppTheme.primaryAccent
            : (statusNorm == 'completed'
                ? Colors.blue
                : (statusNorm == 'checked in'
                    ? Colors.indigo
                    : (statusNorm == 'no show'
                        ? Colors.grey[700]!
                        : (statusNorm.contains('requested')
                            ? Colors.deepPurple
                            : Colors.orange)))));
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

    final rawArrival = b['bookingDate'] ?? b['checkInDate'] ?? b['date'] ?? b['createdAt'] ?? b['timestamp'];
    final parsedStart = _OwnerDashboardState._parseTolerantDate(rawArrival);
    String? bookingDate = parsedStart != null ? DateFormat('MMM dd, yyyy').format(parsedStart) : (rawArrival?.toString() ?? 'N/A');

    bool isActivity = b['isActivityBooking'] == true ||
        (b['roomId'] == null &&
            b['roomTitle'] == null &&
            !(b['activityTitle']?.toString().toLowerCase().contains('room') ?? false) &&
            b['nights'] == null &&
            b['activityId'] != null &&
            b['activityId'].toString().trim().isNotEmpty);

    String dateRange = bookingDate;
    try {
      if (parsedStart != null) {
        if (isActivity) {
          int hours = int.tryParse((b['hours'] ?? b['nights'] ?? 1).toString()) ?? 1;
          dateRange = "$bookingDate ($hours ${hours == 1 ? 'Hour' : 'Hours'})";
        } else {
          int nights = int.tryParse(b['nights']?.toString() ?? '1') ?? 1;
          final rawDeparture = b['departureDate'] ?? b['checkOutDate'];
          final parsedEnd = _OwnerDashboardState._parseTolerantDate(rawDeparture) ?? parsedStart.add(Duration(days: nights));
          final endFormatted = DateFormat('MMM dd, yyyy').format(parsedEnd);
          dateRange = "$bookingDate - $endFormatted ($nights Nights)";
        }
      }
    } catch (e) {}

    String? photo = b['touristProfilePic'];

    bool isOverdue = false;
    if (statusNorm == 'checked in' && parsedStart != null) {
      try {
        int nights = int.tryParse(b['nights']?.toString() ?? '1') ?? 1;
        final rawDeparture = b['departureDate'] ?? b['checkOutDate'];
        final endDate = _OwnerDashboardState._parseTolerantDate(rawDeparture) ?? parsedStart.add(Duration(days: nights));
        DateTime todayMidnight = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
        if (todayMidnight.isAfter(endDate) || todayMidnight.isAtSameMomentAs(endDate)) {
          isOverdue = true;
        }
      } catch (e) {}
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isOverdue ? const BorderSide(color: Colors.red, width: 2) : BorderSide(color: Colors.grey.withOpacity(0.15)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => widget.onTapBooking(key, b),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isOverdue)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                  child: const Text(
                    'ACTION NEEDED: OVERDUE CHECKOUT',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5),
                  ),
                ),
              if (b['status'] == 'Refund Requested')
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
                  decoration: BoxDecoration(color: Colors.amber.shade800, borderRadius: BorderRadius.circular(4)),
                  child: const Text(
                    'REFUND IN PROCESS: Please review and settle',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (b['touristUid'] != null) {
                        showDialog(
                          context: context,
                          builder: (context) => TouristProfileDialog(touristUid: b['touristUid']),
                        );
                      }
                    },
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      backgroundImage: photo != null ? NetworkImage(photo) : null,
                      child: photo == null ? const Icon(Icons.person, size: 20) : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  if (b['touristUid'] != null) {
                                    showDialog(
                                      context: context,
                                      builder: (context) => TouristProfileDialog(touristUid: b['touristUid']),
                                    );
                                  }
                                },
                                child: Text(
                                  touristName,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                              child: Text(
                                s,
                                style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          roomTitle,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[800]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.calendar_today_rounded, size: 11, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                dateRange,
                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              "₱${b['totalPrice'] ?? '0'}",
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.secondaryAccent),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (addons.isNotEmpty || b['isHistorical'] == true || (b['gcashReceipt'] != null && b['gcashReceipt'].toString().trim().isNotEmpty && b['gcashReceipt'] != 'MANUAL_GCASH_PAYMENT') || (b['historicalPhotoUrl'] != null && b['historicalPhotoUrl'].toString().trim().isNotEmpty) || (b['paymentReceiptDataUrl'] != null && b['paymentReceiptDataUrl'].toString().trim().isNotEmpty)) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (b['isHistorical'] == true)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: AppTheme.secondaryAccent.withOpacity(0.12), borderRadius: BorderRadius.circular(4), border: Border.all(color: AppTheme.secondaryAccent, width: 0.8)),
                        child: const Text('Imported', style: TextStyle(color: AppTheme.secondaryAccent, fontWeight: FontWeight.bold, fontSize: 9)),
                      ),
                    if ((b['gcashReceipt'] != null && b['gcashReceipt'].toString().trim().isNotEmpty && b['gcashReceipt'] != 'MANUAL_GCASH_PAYMENT') || (b['historicalPhotoUrl'] != null && b['historicalPhotoUrl'].toString().trim().isNotEmpty) || (b['paymentReceiptDataUrl'] != null && b['paymentReceiptDataUrl'].toString().trim().isNotEmpty))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: Colors.blue.withOpacity(0.12), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.blue, width: 0.8)),
                        child: const Text('Photo/Receipt', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 9)),
                      ),
                    if (addons.isNotEmpty)
                      Text("Add-ons: ${addons.join(', ')}", style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
  final List<Map<String, dynamic>> pendingDetails;
  final double totalRevenue;
  final double totalPending;

  const MonthlyReportPage(
      {super.key,
      required this.monthName,
      required this.details,
      required this.pendingDetails,
      required this.totalRevenue,
      required this.totalPending});

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
              report +=
                  "Total Revenue: ₱${totalRevenue.toStringAsFixed(2)}\n\n";
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        const Text('Revenue',
                            style: TextStyle(
                                color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('₱${totalRevenue.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.green)),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('Pending',
                            style: TextStyle(
                                color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('₱${totalPending.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.orange)),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('Expected',
                            style: TextStyle(
                                color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('₱${(totalRevenue + totalPending).toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.primaryAccent)),
                        ),
                      ],
                    ),
                  ],
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
                    itemCount: details.length + pendingDetails.length,
                    itemBuilder: (context, index) {
                      final isPending = index >= details.length;
                      final b = isPending ? pendingDetails[index - details.length] : details[index];
                      final raw = b['rawBooking'] as Map?;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 1,
                        color: isPending ? Colors.orange[50] : Colors.white,
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
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text('₱${b['amount'].toStringAsFixed(2)}',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: isPending ? Colors.orange : Colors.green,
                                              fontSize: 16)),
                                      Text(isPending ? 'PENDING BALANCE' : 'PAID',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: isPending ? Colors.orange : Colors.green,
                                              fontSize: 10)),
                                    ],
                                  ),
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
                                  Builder(builder: (context) {
                                    bool isAct = raw?['isActivityBooking'] == true ||
                                        (raw?['roomId'] == null &&
                                            raw?['roomTitle'] == null &&
                                            !(raw?['activityTitle']?.toString().toLowerCase().contains('room') ?? false) &&
                                            raw?['nights'] == null &&
                                            raw?['activityId'] != null &&
                                            raw!['activityId'].toString().trim().isNotEmpty);
                                    if (isAct) {
                                      int hours = int.tryParse((raw?['hours'] ?? raw?['nights'] ?? b['nights'] ?? 1).toString()) ?? 1;
                                      return Text('${b['date']} ($hours ${hours == 1 ? 'hour' : 'hours'})');
                                    }
                                    return Text('${b['date']} (${b['nights']} nights)');
                                  }),
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
                                  raw['paymentMethod'] != null && !isPending) ...[
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


class BalancesTab extends StatefulWidget {
  final String ownerId;
  const BalancesTab({super.key, required this.ownerId});

  @override
  State<BalancesTab> createState() => _BalancesTabState();
}

class _BalancesTabState extends State<BalancesTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map> _unpaidBookings = [];
  bool _isLoading = true;
  Set<String> _selectedBookingIds = {};

  @override
  void initState() {
    super.initState();
    _fetchUnpaidBookings();
  }

  Future<void> _fetchUnpaidBookings() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('bookings')
          .orderByChild('ownerUid')
          .equalTo(widget.ownerId)
          .get();

      List<Map> unpaid = [];
      if (snapshot.exists) {
        final data = snapshot.value as Map;
        data.forEach((key, value) {
          try {
            String status = (value['status'] ?? '').toString().toLowerCase();
            
            double remaining = 0;
            if (value['isPaid'] == true || value['remainingBalance']?.toString() == '0' || value['paymentStatus'] == 'fully_paid') {
              remaining = 0;
            } else if (value['remainingBalance'] != null) {
              remaining = double.tryParse(value['remainingBalance'].toString()) ?? 0;
            } else {
              double total = double.tryParse(value['totalPrice']?.toString() ?? '0') ?? 0;
              String paymentOption = (value['paymentOption'] ?? '').toString();
              double paid = double.tryParse(value['amountPaid']?.toString() ?? '0') ?? 0;
              if (value['amountPaid'] == null) {
                paid = paymentOption.contains('30%') ? total * 0.3 : total;
              }
              remaining = total - paid;
            }

            bool isMissed = false;
            if ((status == 'pending' || status == 'confirmed') && value['bookingDate'] != null) {
              try {
                DateTime bookingDate = DateFormat('MMMM d, yyyy').parse(value['bookingDate'].toString());
                int nights = int.tryParse(value['nights']?.toString() ?? '1') ?? 1;
                DateTime endDate = bookingDate.add(Duration(days: nights));
                DateTime today = DateTime.now();
                DateTime todayMidnight = DateTime(today.year, today.month, today.day);
                if (todayMidnight.isAfter(endDate) || todayMidnight.isAtSameMomentAs(endDate)) {
                  isMissed = true;
                }
              } catch(e) {}
            }

            if (remaining > 0 && !isMissed && (status == 'pending' || status == 'confirmed' || status == 'checked in' || status == 'checked-in')) {
              Map b = Map.from(value);
              b['id'] = key;
              b['calculatedBalance'] = remaining;
              unpaid.add(b);
            }
          } catch(e) {
            // ignore parsing error for single booking
          }
        });
      }

      if (mounted) {
        setState(() {
          _unpaidBookings = unpaid;
          _isLoading = false;
        });
      }
    } catch(e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _processPaymentForBookings(List<Map> bookingsToPay) async {
    double totalAmount = 0;
    for (var b in bookingsToPay) {
      totalAmount += double.tryParse(b['calculatedBalance']?.toString() ?? '0') ?? 0;
    }

    bool confirm = await showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 32),
              ),
              const SizedBox(height: 16),
              const Text(
                'Confirm Payment',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Mark ${bookingsToPay.length} booking(s) as fully paid (Total: ₱${totalAmount.toStringAsFixed(0)})?',
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Confirm Paid'),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      )
    ) ?? false;

    if (!confirm) return;

    // Process all updates
    final statsRef = FirebaseDatabase.instance.ref('owner_stats/${widget.ownerId}');
    final sSnap = await statsRef.get();
    double currentRev = 0;
    if (sSnap.exists) {
      final sData = sSnap.value as Map;
      currentRev = (sData['totalRevenue'] ?? 0).toDouble();
    }

    double newlyPaid = 0;
    for (var booking in bookingsToPay) {
      double bal = double.tryParse(booking['calculatedBalance']?.toString() ?? '0') ?? 0;
      newlyPaid += bal;
      
      // Update primary booking
      await FirebaseDatabase.instance.ref('bookings/${booking['id']}').update({
        'remainingBalance': 0,
        'isPaid': true,
        'paymentStatus': 'fully_paid'
      });
      
      // Update tourist user booking record if exists
      if (booking['touristUid'] != null) {
        await FirebaseDatabase.instance.ref('tourist_users/${booking['touristUid']}/bookings/${booking['id']}').update({
          'remainingBalance': 0,
          'isPaid': true,
          'paymentStatus': 'fully_paid'
        });
      }

      await FirebaseDatabase.instance.ref('revenue_reports/${widget.ownerId}').push().set({
        'bookingId': booking['id'],
        'amount': bal,
        'date': ServerValue.timestamp,
        'description': 'Balance paid for ${booking['bookingCode'] ?? 'Unknown'}',
        'type': 'balance_payment'
      });
    }

    await statsRef.update({
      'totalRevenue': currentRev + newlyPaid
    });

    setState(() {
      _selectedBookingIds.removeAll(bookingsToPay.map((b) => b['id'].toString()));
    });
    
    _fetchUnpaidBookings();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payments recorded successfully.')));
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    DateTime d = DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp.toString()));
    return "${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][d.month-1]} ${d.day}, ${d.year}";
  }

  @override
  Widget build(BuildContext context) {
    List<Map> displayList = _unpaidBookings;
    if (_searchCtrl.text.isNotEmpty) {
      displayList = _unpaidBookings.where((b) => 
        (b['bookingCode']?.toString().toLowerCase() ?? '').contains(_searchCtrl.text.toLowerCase()) ||
        (b['touristName']?.toString().toLowerCase() ?? '').contains(_searchCtrl.text.toLowerCase())
      ).toList();
    }

    // Group by tourist
    Map<String, List<Map>> grouped = {};
    for (var b in displayList) {
      String tName = (b['touristName'] ?? 'Unknown Tourist').toString().trim();
      if (tName.isEmpty) tName = 'Unknown Tourist';
      grouped.putIfAbsent(tName, () => []).add(b);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100], // light background like web
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Row(
              children: [
                const Icon(Icons.credit_card, color: AppTheme.primaryAccent),
                const SizedBox(width: 8),
                const Text('Unpaid Balances', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Use this section to manually mark a booking as fully paid if a tourist decides to pay their remaining balance early (e.g., via PM) before arriving at the resort.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search tourist name or booking ID',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (val) => setState(() {}),
            ),
            const SizedBox(height: 16),
            _isLoading
              ? const Center(child: CircularProgressIndicator())
              : grouped.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('ALL SETTLED!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))))
                : Expanded(
                    child: ListView.builder(
                      itemCount: grouped.keys.length,
                      itemBuilder: (context, i) {
                        String tName = grouped.keys.elementAt(i);
                        List<Map> items = grouped[tName]!;
                        double totalUnpaid = items.fold(0.0, (sum, item) => sum + (double.tryParse(item['calculatedBalance']?.toString() ?? '0') ?? 0));
                        
                        List<Map> selectedItems = items.where((b) => _selectedBookingIds.contains(b['id'].toString())).toList();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 24),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                            ]
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(tName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                                  const SizedBox(height: 4),
                                  Text('Total Unpaid Balance: ₱${totalUnpaid.toStringAsFixed(0)}', style: const TextStyle(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blueAccent, 
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                                        ),
                                        onPressed: selectedItems.isEmpty ? null : () => _processPaymentForBookings(selectedItems),
                                        child: const Text('Mark Selected Paid', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF00C853), // Green
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                                        ),
                                        onPressed: () => _processPaymentForBookings(items),
                                        child: const Text('Mark All Paid', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      ),
                                    ]
                                  )
                                ],
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Divider(color: Colors.black12, thickness: 1, height: 1),
                              ),
                              // Booking Items
                              ...items.map((b) {
                                bool isSelected = _selectedBookingIds.contains(b['id'].toString());
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.blue.withOpacity(0.05) : Colors.grey[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: isSelected ? Colors.blue.withOpacity(0.3) : Colors.grey[200]!)
                                  ),
                                  child: Row(
                                    children: [
                                      Checkbox(
                                        value: isSelected,
                                        activeColor: Colors.blueAccent,
                                        onChanged: (val) {
                                          setState(() {
                                            if (val == true) _selectedBookingIds.add(b['id'].toString());
                                            else _selectedBookingIds.remove(b['id'].toString());
                                          });
                                        }
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('Room ${b['activityTitle'] ?? b['roomTitle'] ?? b['activityName'] ?? b['room'] ?? b['roomName'] ?? b['roomId'] ?? 'Unknown'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                              const SizedBox(height: 4),
                                              Text('Booking Ref: ${b['bookingCode'] ?? (b['id'] != null ? b['id'].toString().substring(0, 8).toUpperCase() : 'N/A')} • ${_formatDate(b['createdAt'] ?? b['timestamp'])}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                              const SizedBox(height: 4),
                                              Text('Balance: ₱${b['calculatedBalance']}', style: const TextStyle(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                            ],
                                          )
                                        )
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: TextButton(
                                          style: TextButton.styleFrom(
                                            backgroundColor: Colors.green.withOpacity(0.1),
                                            foregroundColor: Colors.green[700],
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                                          ),
                                          onPressed: () => _processPaymentForBookings([b]),
                                          child: const Text('Mark as Paid', style: TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      )
                                    ],
                                  ),
                                );
                              }).toList()
                            ],
                          )
                        );
                      }
                    )
                  ),
          ],
        ),
    );
  }
}

class BookingScannerScreen extends StatefulWidget {
  const BookingScannerScreen({super.key});

  @override
  State<BookingScannerScreen> createState() => _BookingScannerScreenState();
}

class _BookingScannerScreenState extends State<BookingScannerScreen> {
  bool _isProcessing = false;
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Booking QR')),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          if (_isProcessing) return;
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            final String? code = barcode.rawValue ?? barcode.displayValue;
            if (code != null) {
              setState(() => _isProcessing = true);
              _controller.stop();
              Navigator.pop(context, code);
              break;
            }
          }
        },
      ),
    );
  }
}

class ActivitiesTab extends StatelessWidget {
  final Stream<DatabaseEvent> propStream;
  final Query activitiesQuery;
  final VoidCallback onAddActivity;
  final Function(String, Map) onEditActivity;
  final Function(String, String) onDeleteActivity;
  final VoidCallback? onSeedStandardActivities;
  final Function(bool)? onToggleVisibility;

  const ActivitiesTab({
    super.key,
    required this.propStream,
    required this.activitiesQuery,
    required this.onAddActivity,
    required this.onEditActivity,
    required this.onDeleteActivity,
    this.onSeedStandardActivities,
    this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: propStream,
      builder: (context, propSnap) {
        bool showActivities = true;
        if (propSnap.hasData && propSnap.data?.snapshot.value is Map) {
          final pData = propSnap.data!.snapshot.value as Map;
          showActivities = pData['showActivities'] ?? (pData['type'] != 'Hotel');
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Card(
                elevation: 0,
                color: showActivities ? Colors.green.withOpacity(0.08) : Colors.orange.withOpacity(0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: showActivities ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    children: [
                      Icon(
                        showActivities ? Icons.visibility : Icons.visibility_off,
                        color: showActivities ? Colors.green[700] : Colors.orange[700],
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              showActivities ? 'Activities Section: VISIBLE' : 'Activities Section: HIDDEN',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: showActivities ? Colors.green[900] : Colors.orange[900],
                              ),
                            ),
                            Text(
                              showActivities
                                  ? 'Guests can see and book activities on your property page.'
                                  : 'Hidden from guests (recommended for hotels).',
                              style: TextStyle(
                                fontSize: 11,
                                color: showActivities ? Colors.green[800] : Colors.orange[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (onToggleVisibility != null)
                        Switch(
                          value: showActivities,
                          activeColor: Colors.green,
                          onChanged: (val) => onToggleVisibility!(val),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Activities', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (onSeedStandardActivities != null)
                        OutlinedButton.icon(
                          onPressed: onSeedStandardActivities,
                          icon: const Icon(Icons.flash_on, size: 16),
                          label: const Text('Load Standard', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ElevatedButton.icon(
                        onPressed: onAddActivity,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Activity', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<DatabaseEvent>(
                stream: activitiesQuery.onValue,
                builder: (context, snapshot) {
                  if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
                  if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.kayaking, size: 54, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          const Text("No activities added yet.", style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 12),
                          if (onSeedStandardActivities != null)
                            ElevatedButton.icon(
                              onPressed: onSeedStandardActivities,
                              icon: const Icon(Icons.flash_on),
                              label: const Text("Load 5 Standard Activities"),
                            ),
                        ],
                      ),
                    );
                  }
                  final data = snapshot.data!.snapshot.value;
                  if (data is! Map) return const Center(child: Text("No activities added yet."));
                  final acts = data.entries.map((e) => {'key': e.key, ...e.value as Map}).toList();

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: acts.length,
                    itemBuilder: (context, index) {
                      final act = acts[index];
                      final title = act['title'] ?? 'Activity';
                      final price = act['price'] ?? 0;
                      final maxPax = act['maxPax'] ?? 1;
                      final isBoatride = title.toLowerCase().contains('boatride');

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                            child: Icon(
                              isBoatride ? Icons.directions_boat : Icons.kayaking,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          subtitle: Text(
                            '₱$price/pax • Max $maxPax pax${isBoatride ? " • +₱750 if solo" : ""}',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => onEditActivity(act['key'], act),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => onDeleteActivity(act['key'], act['title'] ?? ''),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class FoodMenuTab extends StatefulWidget {
  final Stream<DatabaseEvent> propStream;
  const FoodMenuTab({super.key, required this.propStream});

  @override
  State<FoodMenuTab> createState() => _FoodMenuTabState();
}

class _FoodMenuTabState extends State<FoodMenuTab> with AutomaticKeepAliveClientMixin {
  bool _isUploading = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _uploadMenuImages(List<String> currentUrls) async {
    final picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage();
    if (images.isEmpty) return;

    setState(() => _isUploading = true);
    List<String> newUrls = List.from(currentUrls);

    for (var image in images) {
      try {
        final request = http.MultipartRequest('POST', Uri.parse('https://api.cloudinary.com/v1_1/dnv6ezitm/image/upload'))
          ..fields['upload_preset'] = 'resort_unsigned'
          ..files.add(await http.MultipartFile.fromPath('file', image.path));

        final response = await request.send();
        if (response.statusCode == 200) {
          final resData = await response.stream.bytesToString();
          final data = json.decode(resData);
          newUrls.add(data['secure_url']);
        }
      } catch (e) {
        debugPrint("Error uploading image: $e");
      }
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        await FirebaseDatabase.instance.ref('properties/$uid').update({
          'foodMenuUrls': newUrls,
        });
      } catch (e) {
        debugPrint("Database update error: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving to database: $e')));
        }
      }
    }
    if (mounted) {
      setState(() => _isUploading = false);
    }
  }

  Future<void> _deleteMenuImage(List<String> currentUrls, int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Menu Image?'),
        content: const Text('Are you sure you want to remove this menu image?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      List<String> newUrls = List.from(currentUrls);
      newUrls.removeAt(index);
      
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseDatabase.instance.ref('properties/$uid').update({
          'foodMenuUrls': newUrls,
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<DatabaseEvent>(
      stream: widget.propStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (!snapshot.data!.snapshot.exists) return const Center(child: Text("No property found."));

        final propData = snapshot.data!.snapshot.value as Map;
        final List<String> foodMenuUrls = [];
        if (propData['foodMenuUrls'] is List) {
          foodMenuUrls.addAll(List<String>.from(propData['foodMenuUrls']));
        }

        final bool enableCustomMenuUpload = propData['enableCustomMenuUpload'] == true || propData['enableCustomMenuUpload'] == 'true';

        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Food Menu Management', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (!enableCustomMenuUpload) ...[
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Defaulting to standard interactive (+ / -) meal quantity counters during booking.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Enable Custom Food Menu Upload in Property Settings to upload your own digital menu images.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                const Text('Upload your property\'s food menu images (Breakfast, Lunch, Dinner). Guests can view these images directly.', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 20),
                
                ElevatedButton.icon(
                  onPressed: _isUploading ? null : () => _uploadMenuImages(foodMenuUrls),
                  icon: _isUploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.upload),
                  label: Text(_isUploading ? 'Uploading...' : 'Upload Menu Images'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
                
                const SizedBox(height: 24),
              if (foodMenuUrls.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text('No menu images uploaded yet.', style: TextStyle(color: Colors.grey)),
                  ),
                )
              else
                Expanded(
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: foodMenuUrls.length,
                    itemBuilder: (context, index) {
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              foodMenuUrls[index],
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () => _deleteMenuImage(foodMenuUrls, index),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class OwnerReviewsTab extends StatelessWidget {
  final String ownerUid;
  final Set<String> readReviewIds;
  final Function(String) onMarkAsRead;
  final Function(List<String>) onMarkAllAsRead;

  const OwnerReviewsTab({
    super.key,
    required this.ownerUid,
    this.readReviewIds = const {},
    required this.onMarkAsRead,
    required this.onMarkAllAsRead,
  });

  @override
  Widget build(BuildContext context) {
    if (ownerUid.isEmpty) {
      return const Center(
        child: Text('Please log in to view guest reviews.',
            style: TextStyle(color: Colors.grey)),
      );
    }

    final reviewsRef = FirebaseDatabase.instance.ref('reviews/$ownerUid');

    return StreamBuilder<DatabaseEvent>(
      stream: reviewsRef.onValue,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data?.snapshot.value;
        if (data == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.star_outline_rounded,
                    size: 64, color: Colors.grey.withOpacity(0.5)),
                const SizedBox(height: 16),
                const Text(
                  'No guest reviews yet',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Reviews submitted by guests after their stay will appear here.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final List<Map<String, dynamic>> reviewsList = [];
        if (data is Map) {
          data.forEach((key, val) {
            if (val is Map) {
              final rMap = Map<String, dynamic>.from(val);
              rMap['id'] = key.toString();
              reviewsList.add(rMap);
            }
          });
        }

        reviewsList.sort((a, b) {
          final tA = a['timestamp'] is int ? a['timestamp'] as int : 0;
          final tB = b['timestamp'] is int ? b['timestamp'] as int : 0;
          return tB.compareTo(tA);
        });

        if (reviewsList.isEmpty) {
          return const Center(
            child: Text('No reviews yet.', style: TextStyle(color: Colors.grey)),
          );
        }

        double totalStars = 0;
        for (var r in reviewsList) {
          final ratingNum = (r['rating'] is num)
              ? (r['rating'] as num).toDouble()
              : double.tryParse(r['rating']?.toString() ?? '5') ?? 5.0;
          totalStars += ratingNum;
        }
        final double avgRating = totalStars / reviewsList.length;

        final isDark = Theme.of(context).brightness == Brightness.dark;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Summary Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black.withOpacity(0.08),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Overall Rating',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${reviewsList.length} ${reviewsList.length == 1 ? 'Review' : 'Reviews'}',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded,
                                color: Colors.amber, size: 28),
                            const SizedBox(width: 4),
                            Text(
                              avgRating.toStringAsFixed(1),
                              style: const TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(width: 4),
                            const Text('/ 5.0',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ),
                    if (reviewsList.any((r) => !readReviewIds.contains(r['id']?.toString()))) ...[
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            final allIds = reviewsList
                                .map((r) => r['id']?.toString() ?? '')
                                .where((id) => id.isNotEmpty)
                                .toList();
                            onMarkAllAsRead(allIds);
                          },
                          icon: const Icon(Icons.done_all_rounded, size: 16),
                          label: const Text('Mark all as read',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Responsive List/Grid of Reviews
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: reviewsList.length,
                separatorBuilder: (context, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final r = reviewsList[index];
                  final rId = r['id']?.toString() ?? '';
                  final isUnread = !readReviewIds.contains(rId);
                  final touristName =
                      r['touristName']?.toString() ?? 'Anonymous Guest';
                  final comment =
                      r['comment']?.toString() ?? 'No comment provided.';
                  final rating = (r['rating'] is num)
                      ? (r['rating'] as num).toInt()
                      : int.tryParse(r['rating']?.toString() ?? '5') ?? 5;
                  final photoUrl = r['photoUrl']?.toString();
                  final ownerReply = r['ownerReply']?.toString();
                  final ownerReplyTimestamp = r['ownerReplyTimestamp'];
                  final timestamp = r['timestamp'];
                  String dateStr = '';
                  if (timestamp is int) {
                    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
                    dateStr =
                        '${_monthName(dt.month)} ${dt.day}, ${dt.year}';
                  }

                  return InkWell(
                    onTap: () {
                      if (rId.isNotEmpty) onMarkAsRead(rId);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isUnread
                              ? Colors.amber.shade700
                              : (isDark
                                  ? Colors.white10
                                  : Colors.black.withOpacity(0.06)),
                          width: isUnread ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        touristName,
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isUnread) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade700,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'NEW',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(5, (starIdx) {
                                  return Icon(
                                    Icons.star_rounded,
                                    size: 16,
                                    color: starIdx < rating
                                        ? Colors.amber
                                        : Colors.grey.withOpacity(0.3),
                                  );
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            comment,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: isDark
                                  ? Colors.white70
                                  : Colors.grey.shade800,
                            ),
                          ),
                          if (photoUrl != null && photoUrl.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                photoUrl,
                                height: 140,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ],
                          if (ownerReply != null && ownerReply.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border(
                                  left: BorderSide(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 3.5,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '💬 Your Response',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary),
                                      ),
                                      GestureDetector(
                                        onTap: () => _showReplyDialog(
                                            context, rId, ownerReply),
                                        child: const Text(
                                          'Edit',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey,
                                              fontWeight: FontWeight.bold,
                                              decoration:
                                                  TextDecoration.underline),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    ownerReply,
                                    style: const TextStyle(
                                        fontSize: 12.5, height: 1.35),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (dateStr.isNotEmpty)
                                Text(
                                  dateStr,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.w600),
                                )
                              else
                                const SizedBox.shrink(),
                              if (ownerReply == null || ownerReply.isEmpty)
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      _showReplyDialog(context, rId, ''),
                                  icon: const Icon(Icons.reply_rounded, size: 14),
                                  label: const Text('Reply to Guest',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showReplyDialog(
      BuildContext context, String reviewId, String initialText) {
    final controller = TextEditingController(text: initialText);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reply to Guest Review',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Thank the guest or address their feedback...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          if (initialText.isNotEmpty)
            TextButton(
              onPressed: () async {
                try {
                  await FirebaseDatabase.instance
                      .ref('reviews/$ownerUid/$reviewId/ownerReply')
                      .remove();
                  await FirebaseDatabase.instance
                      .ref('reviews/$ownerUid/$reviewId/ownerReplyTimestamp')
                      .remove();
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('Failed to delete reply: $e')));
                  }
                }
              },
              child: const Text('Delete Reply', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              try {
                await FirebaseDatabase.instance
                    .ref('reviews/$ownerUid/$reviewId')
                    .update({
                  'ownerReply': text,
                  'ownerReplyTimestamp': ServerValue.timestamp,
                });
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Failed to save reply: $e')));
                }
              }
            },
            child: const Text('Save Reply'),
          ),
        ],
      ),
    );
  }

  static String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    if (month >= 1 && month <= 12) return months[month - 1];
    return '';
  }
}
