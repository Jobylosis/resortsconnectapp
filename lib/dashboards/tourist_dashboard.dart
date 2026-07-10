import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../chat_page.dart';
import '../profile_page.dart';
import '../property_details_page.dart';
import '../notifications_page.dart';
import 'price_breakdown_dialog.dart';
import '../bill_splitter_page.dart';
import '../bill_splitter_scanner.dart';
import '../theme_provider.dart';
import '../theme.dart';
import '../terms_and_policies_page.dart';

class TouristDashboard extends StatefulWidget {
  const TouristDashboard({super.key});

  @override
  State<TouristDashboard> createState() => _TouristDashboardState();
}

class _TouristDashboardState extends State<TouristDashboard> {
  late Stream<DatabaseEvent> _userStream;
  late Stream<DatabaseEvent> _chatRoomsStream;
  int _totalUnread = 0;
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  String? _deletingBookingKey;
  String _cachedFirstName = "Tourist";
  String _expenseMonthFilter = 'All Months';
  String _expenseStatusFilter = 'All Bookings';
  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _userStream = FirebaseDatabase.instance
        .ref("users/${user?.uid}")
        .onValue
        .asBroadcastStream();

    // M1 Fix: Load cached name immediately so greeting shows before stream resolves
    _loadCachedName();

    // Seed FAQ data if it doesn't exist
    _seedFaqs();

    final chatRoomsRef =
        FirebaseDatabase.instance.ref("chat_rooms/${user?.uid}");
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
  }

  Future<void> _loadCachedName() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('cachedFirstName');
    if (cached != null && mounted) {
      setState(() => _cachedFirstName = cached);
    }
  }

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

  void _toggleFavorite(String propertyId, bool isCurrentlyFav) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseDatabase.instance
        .ref("users/${user.uid}/favorites/$propertyId");
    if (isCurrentlyFav) {
      await ref.remove();
    } else {
      await ref.set(true);
    }
  }

  Future<void> _seedFaqs() async {
    final ref = FirebaseDatabase.instance.ref("master_data/faqs");
    final snap = await ref.get();
    bool shouldSeed = true;
    if (snap.exists) {
      final val = snap.value;
      if (val is Map && val.length >= 15) {
        shouldSeed = false;
      } else if (val is List && val.length >= 15) {
        shouldSeed = false;
      }
    }

    if (shouldSeed) {
      await ref.set({
        '1': {
          'q': 'How do I book a room?',
          'a':
              'Navigate to the Partners tab, select a resort, choose a room, and click "Book Now". Follow the payment steps to complete.'
        },
        '2': {
          'q': 'Can I cancel my booking?',
          'a':
              'Yes, go to My Bookings and click "Cancel". Note that cancellations may be subject to owner approval or policies.'
        },
        '3': {
          'q': 'How does rescheduling work?',
          'a':
              'Click "Reschedule" on your booking. You can pick a new date and duration. The owner will review and confirm if the slot is available.'
        },
        '4': {
          'q': 'Is my payment secure?',
          'a':
              'Yes, we use GCash for verified payments. You will need to upload your receipt for the owner to verify.'
        },
        '5': {
          'q': 'How do I contact the owner?',
          'a':
              'You can use the Chat feature or find their contact information in the Property Details page.'
        },
        '6': {
          'q': 'Can I book multiple rooms?',
          'a':
              'Yes, you can initiate separate bookings for different rooms. Each request will be reviewed by the owner independently.'
        },
        '7': {
          'q': 'What happens if my request is declined?',
          'a':
              'If an owner declines, your booking status will change to "Cancelled", and you can try booking for another date or another resort.'
        },
        '8': {
          'q': 'Do I need to pay in full?',
          'a':
              'Most resorts offer a 30% downpayment option via GCash, with the remaining balance payable at the property.'
        },
        '9': {
          'q': 'How do I know my booking is confirmed?',
          'a':
              'You will receive a notification, and your booking status in "My Bookings" will change to "Confirmed".'
        },
        '10': {
          'q': 'What is the "Check-in" process?',
          'a':
              'Once you arrive, show your Booking QR Code (found in My Bookings) to the resort staff for verification.'
        },
        '11': {
          'q': 'Are pets allowed?',
          'a':
              'Pet policies vary by resort. Please check the property details or chat with the owner directly.'
        },
        '12': {
          'q': 'Is there a refund if I cancel?',
          'a':
              'Refunds depend on the owner\'s policy. If approved, the refund process will be initiated via your original payment method.'
        },
        '13': {
          'q': 'Can I bring my own food?',
          'a':
              'Most resorts allow outside food, but some may charge a corkage fee. It\'s best to ask the owner.'
        },
        '14': {
          'q': 'What time is check-in and check-out?',
          'a':
              'Standard check-in is usually at 2:00 PM and check-out at 12:00 PM, but this can vary per property.'
        },
        '15': {
          'q': 'Do the resorts have Wi-Fi?',
          'a':
              'Many of our partner resorts offer free Wi-Fi. Look for the Wi-Fi icon in the amenities section of the property details.'
        },
      });
    }
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
                        style: TextStyle(color: AppTheme.primaryAccent)))
              ],
            ));
  }

  Future<void> _cancelBookingDirectly(String bookingId) async {
    await FirebaseDatabase.instance.ref("bookings/$bookingId").update({
      'status': 'Cancelled',
      'cancellationReason': 'Cancelled via Dashboard',
      'cancelledBy': 'Tourist'
    });
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking request cancelled.')));
  }

  Future<void> _cancelBooking(String bookingId) async {
    // Legacy dialog method
  }

  Future<List<DateTime>> _fetchBookedDates(String activityId,
      {String? excludeBookingId}) async {
    List<DateTime> bookedDates = [];
    try {
      final snap = await FirebaseDatabase.instance
          .ref("bookings")
          .orderByChild("activityId")
          .equalTo(activityId)
          .get();

      if (snap.exists) {
        Map allBookings = {};
        final value = snap.value;
        if (value is Map) {
          allBookings = value;
        } else if (value is List) {
          for (int i = 0; i < value.length; i++) {
            if (value[i] != null) allBookings[i.toString()] = value[i];
          }
        }

        for (var entry in allBookings.entries) {
          if (entry.key == excludeBookingId) continue;
          final b = entry.value;
          if (b is! Map) continue;

          String status = (b['status'] ?? '').toString().trim().toLowerCase();
          if (status != 'confirmed' && status != 'checked in') continue;

          try {
            DateTime start = DateFormat('MMM dd, yyyy').parse(b['bookingDate']);
            int nights = int.tryParse(b['nights'].toString()) ?? 1;
            for (int i = 0; i < nights; i++) {
              bookedDates.add(DateUtils.dateOnly(start.add(Duration(days: i))));
            }
          } catch (e) {}
        }
      }
    } catch (e) {
      debugPrint("Error fetching booked dates: $e");
    }
    return bookedDates;
  }

  Future<void> _requestReschedule(
      String bookingId, String activityId, Map booking) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    List<DateTime> bookedDates =
        await _fetchBookedDates(activityId, excludeBookingId: bookingId);

    if (mounted) Navigator.pop(context); // hide loading

    DateTime firstDate = DateUtils.dateOnly(DateTime.now());
    DateTime initialDate = firstDate;

    while (bookedDates.any((d) => DateUtils.isSameDay(d, initialDate))) {
      initialDate = initialDate.add(const Duration(days: 1));
    }

    if (!mounted) return;

    DateTime? newDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: firstDate.add(const Duration(days: 365)),
      selectableDayPredicate: (day) {
        return !bookedDates.any((d) => DateUtils.isSameDay(d, day));
      },
    );

    if (newDate == null) return;

    int originalNights =
        int.tryParse(booking['nights']?.toString() ?? '1') ?? 1;

    // Validate that the fixed duration doesn't overlap with existing bookings
    bool hasConflict = false;
    for (int i = 0; i < originalNights; i++) {
      DateTime checkDate = newDate.add(Duration(days: i));
      if (bookedDates.any((d) => DateUtils.isSameDay(d, checkDate))) {
        hasConflict = true;
        break;
      }
    }

    if (hasConflict) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Cannot reschedule: The required duration overlaps with an existing booking. Please pick another date.'),
            backgroundColor: Colors.red));
      }
      return;
    }

    String dateStr = DateFormat('MMM dd, yyyy').format(newDate);

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Reschedule?'),
        content: Text(
            'Request to reschedule this booking to $dateStr for $originalNights night/s? The owner will need to approve this change.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send Request',
                  style: TextStyle(color: AppTheme.secondaryAccent))),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseDatabase.instance.ref("bookings/$bookingId").update({
        'status': 'Reschedule Requested',
        'requestedRescheduleDate': dateStr,
        'requestedRescheduleNights': originalNights,
      });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reschedule request sent.')));
    }
  }

  Future<void> _requestRefund(String bookingId) async {
    final reasonController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Request Refund',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text(
                'Please tell us why you are requesting a refund for this booking.',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            TextField(
              controller: reasonController,
              maxLines: 3,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(
                    r'[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]',
                    unicode: true))
              ],
              decoration: InputDecoration(
                hintText: 'Enter reason here...',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: () async {
                  String reason = reasonController.text.trim();
                  if (reason.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Please provide a reason.')));
                    return;
                  }

                  Navigator.pop(context);
                  await FirebaseDatabase.instance
                      .ref("bookings/$bookingId")
                      .update({
                    'status': 'Refund Requested',
                    'refundReason': reason,
                  });
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Refund request submitted.')));
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryAccent),
                child: const Text('SUBMIT REQUEST'),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showReviewDialog(Map booking, String bookingId) {
    int rating = 5;
    final commentController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Rate ${booking['propertyName']}',
              overflow: TextOverflow.ellipsis),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                      5,
                      (index) => IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(Icons.star_rounded,
                              size: 44,
                              color: index < rating
                                  ? Colors.amber
                                  : Colors.grey[400]),
                          onPressed: () =>
                              setDialogState(() => rating = index + 1))),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                  controller: commentController,
                  maxLines: 3,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(
                        r'[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]',
                        unicode: true))
                  ],
                  decoration: const InputDecoration(
                      hintText: 'Share your experience...')),
            ],
          ),
          actions: [
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    final user = FirebaseAuth.instance.currentUser;
                    try {
                      String tName = booking['touristName'] ??
                          booking['name'] ??
                          booking['fullName'] ??
                          'Tourist';
                      await FirebaseDatabase.instance
                          .ref("reviews/${booking['ownerUid']}")
                          .push()
                          .set({
                        'touristUid': user?.uid,
                        'touristName': tName,
                        'rating': rating,
                        'comment': commentController.text.trim(),
                        'timestamp': ServerValue.timestamp
                      });
                      await FirebaseDatabase.instance
                          .ref("bookings/$bookingId")
                          .update({'isReviewed': true});
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Thank you for your review!')));
                      }
                    } catch (e) {
                      if (mounted)
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondaryAccent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(100, 45)),
                  child: const Text('Submit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteBookingDirectly(String key) async {
    await FirebaseDatabase.instance.ref("bookings/$key").remove();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking record deleted.')));
  }

  void _showDeleteBookingDialog(String key) {
    // Legacy dialog
  }

  void _showQRCode(String bookingId) {
    // URL format used by the website to identify bookings
    final String bookingUrl =
        "https://resortconnect-f7dd6.web.app/owner?scan=${Uri.encodeComponent(bookingId)}";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Booking QR Code', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Show this to the resort staff. It works with both our website and app scanners.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.1), blurRadius: 10)
                  ]),
              child: QrImageView(
                data: bookingUrl,
                version: QrVersions.auto,
                size: 200.0,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(bookingId,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'))
        ],
      ),
    );
  }

  void _showBookingDetails(Map booking, String bookingId) {
    String rawStatus =
        (booking['status'] ?? 'Pending').toString().trim().toLowerCase();
    String status = rawStatus == 'approved' ? 'confirmed' : rawStatus;

    List addons =
        booking['selectedAddons'] is List ? booking['selectedAddons'] : [];

    String roomTitle = booking['activityTitle'] ??
        booking['roomTitle'] ??
        booking['activityName'] ??
        booking['room'] ??
        booking['roomId'] ??
        'N/A';
    String? bDate = booking['bookingDate'] ??
        booking['checkInDate'] ??
        booking['date'] ??
        booking['createdAt'] ??
        'N/A';
    if (bDate != null && bDate.contains('T') && bDate.contains('Z')) {
      try {
        bDate = DateFormat('MMM dd, yyyy').format(DateTime.parse(bDate));
      } catch (e) {}
    }
    String totalAmountStr = (booking['totalPrice'] ??
            booking['total'] ??
            booking['amount'] ??
            booking['payment'] ??
            booking['price'] ??
            0)
        .toString();
    double total = double.tryParse(totalAmountStr) ?? 0;
    double paid = double.tryParse((booking['amountPaid'] ?? 0).toString()) ?? 0;
    String payMethod = booking['paymentMethod'] ??
        booking['paymentOption'] ??
        booking['payment'] ??
        booking['paymentType'] ??
        'N/A';
    String payOption =
        (booking['paymentOption'] ?? booking['paymentMethod'] ?? '').toString();

    String dateRange = bDate ?? 'N/A';
    try {
      if (bDate != null) {
        DateTime start = DateFormat('MMM dd, yyyy').parse(bDate);
        int nights = int.tryParse(booking['nights'].toString()) ?? 1;
        DateTime end = start.add(Duration(days: nights));
        dateRange =
            "$bDate - ${DateFormat('MMM dd, yyyy').format(end)} ($nights Nights)";
      }
    } catch (e) {}

    // Fallback calculation
    if (paid == 0 && total > 0) {
      if (payOption.contains('30%')) {
        paid = total * 0.3;
      } else {
        paid = total;
      }
    }
    double balance = total - paid;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                      child: Text(booking['propertyName'] ?? 'Resort',
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w900))),
                  IconButton(
                    icon: const Icon(Icons.share_rounded),
                    onPressed: () {
                      String msg =
                          "My Booking Details at ${booking['propertyName']}:\n"
                          "Room: $roomTitle\n"
                          "Date: $dateRange\n"
                          "Status: ${status.toUpperCase()}\n"
                          "Booking ID: $bookingId";
                      Share.share(msg);
                    },
                  ),
                ],
              ),
              const Divider(height: 32),
              _detailItem(Icons.meeting_room_rounded, "Room", roomTitle),
              _detailItem(
                  Icons.calendar_month_rounded, "Date Range", dateRange),
              _detailItem(Icons.access_time_rounded, "Arrival Time",
                  booking['bookingTime'] ?? 'N/A'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .secondary
                        .withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .secondary
                            .withOpacity(0.1))),
                child: Column(
                  children: [
                    _priceRow("Total Amount", "₱${total.toStringAsFixed(2)}"),
                    const SizedBox(height: 8),
                    _priceRow("Amount Paid", "₱${paid.toStringAsFixed(2)}",
                        isBold: true, color: Colors.green),
                    const SizedBox(height: 8),
                    _priceRow(
                        "Remaining Balance", "₱${balance.toStringAsFixed(2)}",
                        isBold: true,
                        color: balance > 0 ? AppTheme.primaryAccent : null),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _detailItem(
                  Icons.credit_card_rounded, "Payment Method", payMethod),
              if (addons.isNotEmpty)
                _detailItem(
                    Icons.add_box_rounded, "Add-ons", addons.join(', ')),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) =>
                          PriceBreakdownDialog(booking: booking),
                    );
                  },
                  icon: const Icon(Icons.shopping_bag_rounded),
                  label: const Text('VIEW PRICE BREAKDOWN',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, letterSpacing: 1)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.1),
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                ),
              ),
              if (booking['cancellationReason'] != null)
                _detailItem(Icons.error_outline_rounded, "Note",
                    booking['cancellationReason'],
                    isError: true),
              const SizedBox(height: 32),
              if (status == 'confirmed' || status == 'checked in') ...[
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showQRCode(bookingId);
                    },
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: const Text('SHOW QR CODE',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, letterSpacing: 1)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      String? pGCash;
                      if (booking['propertyId'] != null) {
                        try {
                          final snap = await FirebaseDatabase.instance
                              .ref('properties/${booking['propertyId']}')
                              .get();
                          if (snap.exists && snap.value != null) {
                            final p = snap.value as Map;
                            if (p['gcashNumber'] != null &&
                                p['gcashNumber'].toString().isNotEmpty) {
                              pGCash =
                                  "GCash ${p['gcashNumber']} - ${p['gcashName'] ?? 'Resort'}";
                            }
                          }
                        } catch (e) {}
                      }
                      if (context.mounted) {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => BillSplitterPage(
                                    initialAmount: total,
                                    resortGCash: pGCash)));
                      }
                    },
                    icon: const Icon(Icons.call_split_rounded),
                    label: const Text('SPLIT BILL',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, letterSpacing: 1)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        foregroundColor: Theme.of(context).colorScheme.primary,
                        side: BorderSide(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (status == 'reschedule requested') ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await FirebaseDatabase.instance
                              .ref("bookings/$bookingId")
                              .update({
                            'status': 'Confirmed',
                            'requestedRescheduleDate': null,
                            'requestedRescheduleNights': null,
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Reschedule request cancelled.')));
                          }
                        },
                        icon: const Icon(Icons.cancel_rounded, size: 18),
                        label: const Text('CANCEL RESCHEDULE'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (status == 'confirmed' || status == 'pending') ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _requestReschedule(
                              bookingId, booking['activityId'], booking);
                        },
                        icon:
                            const Icon(Icons.calendar_month_rounded, size: 18),
                        label: const Text('RESCHEDULE'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).colorScheme.secondary,
                          side: BorderSide(
                              color: Theme.of(context).colorScheme.secondary),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _requestRefund(bookingId);
                        },
                        icon: const Icon(Icons.payments_rounded, size: 18),
                        label: const Text('REFUND'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (status == 'pending')
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _cancelBooking(bookingId);
                    },
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryAccent,
                        side: const BorderSide(color: AppTheme.primaryAccent),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: const Text('CANCEL BOOKING REQUEST',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _priceRow(String label, String value,
          {bool isBold = false, Color? color}) =>
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
                  color: color)),
        ],
      );

  Widget _detailItem(IconData icon, String label, String value,
          {bool isError = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 20,
                color: isError
                    ? AppTheme.primaryAccent
                    : Theme.of(context).colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isError ? AppTheme.primaryAccent : null)),
                ],
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final themeProvider = Provider.of<ThemeProvider>(context);

    return StreamBuilder<DatabaseEvent>(
      stream: _userStream,
      builder: (context, snapshot) {
        String firstName = _cachedFirstName;
        String? profilePic;
        Map favorites = {};
        if (snapshot.hasData && snapshot.data!.snapshot.exists) {
          Map data = snapshot.data!.snapshot.value as Map;
          firstName = data['firstName'] ?? _cachedFirstName;
          profilePic = data['profilePicUrl'];
          favorites = data['favorites'] ?? {};
          // Keep cache fresh
          SharedPreferences.getInstance()
              .then((p) => p.setString('cachedFirstName', firstName));
        }

        return DefaultTabController(
          length: 5,
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: 80,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Resort Connect',
                      style: TextStyle(
                          fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  Text('Hello, $firstName!',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              actions: [
                IconButton(
                  icon: Icon(themeProvider.themeMode == ThemeMode.dark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded),
                  color: Theme.of(context).colorScheme.secondary,
                  onPressed: () => themeProvider.toggleTheme(),
                ),
                _appBarAction(
                    Icons.notifications_none_rounded,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const NotificationsPage()))),
                Padding(
                  padding: const EdgeInsets.only(right: 16, left: 8),
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const ProfilePage())),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .secondary
                          .withValues(alpha: 0.1),
                      backgroundImage:
                          profilePic != null ? NetworkImage(profilePic) : null,
                      child: profilePic == null
                          ? Icon(Icons.person_outline_rounded,
                              color: Theme.of(context).colorScheme.secondary)
                          : null,
                    ),
                  ),
                ),
                _appBarAction(
                    Icons.logout_rounded, () => _showLogoutDialog(context),
                    isLogout: true),
              ],
              bottom: TabBar(
                tabs: [
                  const Tab(text: 'Partners'),
                  const Tab(text: 'Favorites'),
                  Tab(
                      child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Chat'),
                      if (_totalUnread > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
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
                  const Tab(text: 'My Bookings'),
                  const Tab(text: 'My Expenses'),
                ],
                labelColor: Theme.of(context).colorScheme.secondary,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Theme.of(context).colorScheme.secondary,
              ),
            ),
            body: SafeArea(
              child: TabBarView(
                children: [
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: TextField(
                          controller: _searchController,
                          inputFormatters: [
                            FilteringTextInputFormatter.deny(RegExp(
                                r'[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]',
                                unicode: true))
                          ],
                          decoration: InputDecoration(
                            hintText: "Search Resorts, Hotels, Locations...",
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () => setState(() {
                                          _searchController.clear();
                                          _searchQuery = "";
                                        }))
                                : null,
                          ),
                          onChanged: (v) =>
                              setState(() => _searchQuery = v.toLowerCase()),
                        ),
                      ),
                      Expanded(
                          child: PartnersList(
                              firstName: firstName,
                              parseList: _parseList,
                              searchQuery: _searchQuery,
                              favorites: favorites,
                              onFavToggle: _toggleFavorite)),
                    ],
                  ),
                  FavoritesList(
                      parseList: _parseList,
                      favorites: favorites,
                      onFavToggle: _toggleFavorite),
                  _ChatTab(
                      chatQuery: FirebaseDatabase.instance
                          .ref("chat_rooms/${user?.uid}")),
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                            label: const Text('Scan Split Bill',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              backgroundColor:
                                  Theme.of(context).colorScheme.surface,
                              foregroundColor:
                                  Theme.of(context).colorScheme.onSurface,
                              elevation: 0,
                              side: BorderSide(
                                  color: Theme.of(context)
                                      .dividerColor
                                      .withValues(alpha: 0.2)),
                            ),
                            onPressed: () async {
                              final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          const BillSplitterScanner()));
                              if (result != null && result is String) {
                                if (result.contains('Bill Split Summary') ||
                                    result.contains('Bill Breakdown') ||
                                    result.contains('Personal Bill')) {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Split Bill Breakdown',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      content: Text(
                                          result.replaceAll('\\n', '\n'),
                                          style: const TextStyle(fontSize: 16)),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20)),
                                      actions: [],
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Security Check: Invalid QR Code. This scanner is only for Split Bills.')),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ),
                      Expanded(
                        child: FirebaseAnimatedList(
                          query: FirebaseDatabase.instance
                              .ref("bookings")
                              .orderByChild("touristUid")
                              .equalTo(user?.uid),
                          sort: (a, b) {
                            final aTime = (a.value as Map)['timestamp'] ?? 0;
                            final bTime = (b.value as Map)['timestamp'] ?? 0;
                            return bTime.compareTo(aTime);
                          },
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemBuilder: (context, snapshot, animation, index) {
                            if (!snapshot.exists)
                              return const SizedBox.shrink();
                            final booking = Map<String, dynamic>.from(
                                snapshot.value as Map);
                            return _buildMyBookingCard(booking, snapshot.key!);
                          },
                        ),
                      ),
                    ],
                  ),
                  _buildMyExpensesTab(user?.uid),
                ],
              ),
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AiChatBotPage())),
              backgroundColor: Theme.of(context).colorScheme.secondary,
              child: const Icon(Icons.smart_toy_rounded, color: Colors.black),
            ),
          ),
        );
      },
    );
  }

  Widget _appBarAction(IconData icon, VoidCallback onTap,
          {bool isLogout = false}) =>
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
            color: isLogout
                ? Colors.red.withValues(alpha: 0.05)
                : Theme.of(context)
                    .colorScheme
                    .secondary
                    .withValues(alpha: 0.05),
            shape: BoxShape.circle),
        child: IconButton(
            icon: Icon(icon,
                color: isLogout
                    ? Colors.red
                    : Theme.of(context).colorScheme.secondary,
                size: 22),
            onPressed: onTap),
      );

  Widget _buildMyExpensesTab(String? touristUid) {
    if (touristUid == null) return const Center(child: Text('Please login'));
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref("bookings").orderByChild("touristUid").equalTo(touristUid).onValue,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
          return const Center(child: Text('No expenses yet.'));
        }

        final data = snapshot.data!.snapshot.value;
        Map<String, dynamic> allBookings = {};
        if (data is Map) {
          data.forEach((k, v) => allBookings[k.toString()] = v);
        } else if (data is List) {
          for (int i = 0; i < data.length; i++) {
            if (data[i] != null) allBookings[i.toString()] = data[i];
          }
        }

        Set<String> availableMonthsSet = {};
        allBookings.forEach((key, b) {
          if (b is! Map) return;
          String bDate = b['bookingDate']?.toString() ?? '';
          List<String> parts = bDate.split(' ');
          if (parts.length >= 3) {
            String monthYear = '${parts[0]} ${parts[2]}';
            availableMonthsSet.add(monthYear);
          }
        });
        List<String> availableMonths = availableMonthsSet.toList()..sort();

        Map<String, Map<String, dynamic>> expensesByProperty = {};
        allBookings.forEach((key, b) {
          if (b is! Map) return;
          String status = (b['status'] ?? '').toString().trim();
          if (status == 'Cancelled' || status == 'Refund Approved') return;
          if (_expenseStatusFilter == 'Completed Only' && status != 'Completed') return;

          if (_expenseMonthFilter != 'All Months') {
            String bDate = b['bookingDate']?.toString() ?? '';
            List<String> parts = bDate.split(' ');
            if (parts.length < 3) return;
            String monthYear = '${parts[0]} ${parts[2]}';
            if (monthYear != _expenseMonthFilter) return;
          }
          
          String propName = b['propertyName'] ?? 'Unknown Property';
          if (!expensesByProperty.containsKey(propName)) {
            expensesByProperty[propName] = { 'total': 0.0, 'bookings': [] };
          }
          
          double price = double.tryParse((b['totalPrice'] ?? b['total'] ?? b['amount'] ?? b['price'] ?? 0).toString()) ?? 0.0;
          expensesByProperty[propName]!['total'] += price;
          expensesByProperty[propName]!['bookings'].add({ ...b, 'id': key });
        });

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _expenseMonthFilter,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: [
                        const DropdownMenuItem(value: 'All Months', child: Text('All Months')),
                        ...availableMonths.map((m) => DropdownMenuItem(value: m, child: Text(m))),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _expenseMonthFilter = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _expenseStatusFilter,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'All Bookings', child: Text('All Bookings')),
                        DropdownMenuItem(value: 'Completed Only', child: Text('Completed Only')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _expenseStatusFilter = val);
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (expensesByProperty.isEmpty)
              const Expanded(child: Center(child: Text('No active expenses found.')))
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: expensesByProperty.length,
                  itemBuilder: (context, index) {
            String propName = expensesByProperty.keys.elementAt(index);
            Map<String, dynamic> details = expensesByProperty[propName]!;
            double total = details['total'];
            List bookingsList = details['bookings'];

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(propName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 4),
                              Text('${bookingsList.length} Booking(s)', style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Total Spent', style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                            Text('₱${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.green)),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    ...bookingsList.map((b) {
                      double bPrice = double.tryParse((b['totalPrice'] ?? b['total'] ?? b['amount'] ?? b['price'] ?? 0).toString()) ?? 0.0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(b['activityTitle'] ?? b['roomTitle'] ?? 'Booking', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text('${b['bookingDate'] ?? 'N/A'} (${b['nights'] ?? 1} Nights)', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                ],
                              ),
                            ),
                            Text('₱${bPrice.toStringAsFixed(2)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => _showBookingDetails(b, b['id']),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                minimumSize: const Size(0, 0),
                                backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text('Details', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}
    );
  }

  Widget _buildMyBookingCard(Map booking, String bookingId) {
    Color statusColor = Colors.orange;
    String rawStatus =
        (booking['status'] ?? 'Pending').toString().trim().toLowerCase();
    String status = rawStatus == 'approved' ? 'confirmed' : rawStatus;

    if (status == 'confirmed' ||
        status == 'checked in' ||
        status == 'completed') statusColor = Colors.green;
    if (status == 'cancelled') statusColor = AppTheme.primaryAccent;

    String roomTitle = booking['activityTitle'] ??
        booking['roomTitle'] ??
        booking['activityName'] ??
        booking['room'] ??
        booking['roomId'] ??
        'Booking';
    String? bDate = booking['bookingDate'] ??
        booking['checkInDate'] ??
        booking['date'] ??
        booking['createdAt'] ??
        'N/A';
    if (bDate != null && bDate.contains('T') && bDate.contains('Z')) {
      try {
        bDate = DateFormat('MMM dd, yyyy').format(DateTime.parse(bDate));
      } catch (e) {}
    }

    String dateRange = bDate ?? 'N/A';
    try {
      if (bDate != null && booking['nights'] != null) {
        DateTime start = DateFormat('MMM dd, yyyy').parse(bDate);
        int nights = int.tryParse(booking['nights'].toString()) ?? 1;
        DateTime end = start.add(Duration(days: nights));
        dateRange =
            "$bDate - ${DateFormat('MMM dd, yyyy').format(end)} ($nights Nights)";
      }
    } catch (e) {}

    String totalAmount = (booking['totalPrice'] ??
            booking['total'] ??
            booking['amount'] ??
            booking['payment'] ??
            booking['price'] ??
            0)
        .toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () => _showBookingDetails(booking, bookingId),
        borderRadius: BorderRadius.circular(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: statusColor.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(booking['propertyName'] ?? 'Resort',
                            style: Theme.of(context).textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: statusColor,
                          borderRadius: BorderRadius.circular(30)),
                      child: Text(
                          status == 'confirmed'
                              ? 'Confirmed'
                              : (booking['status'] ?? 'Pending'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10)),
                    ),
                    if (booking['isReviewed'] == true || status == 'cancelled')
                      _deletingBookingKey == bookingId
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              TextButton(
                                  onPressed: () => setState(
                                      () => _deletingBookingKey = null),
                                  style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(40, 30)),
                                  child: const Text('Back',
                                      style: TextStyle(fontSize: 12))),
                              TextButton(
                                  onPressed: () {
                                    _deleteBookingDirectly(bookingId);
                                    setState(() => _deletingBookingKey = null);
                                  },
                                  style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(40, 30)),
                                  child: const Text('Delete',
                                      style: TextStyle(
                                          color: AppTheme.primaryAccent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold))),
                            ])
                          : IconButton(
                              icon: Icon(Icons.delete_outline_rounded,
                                  size: 20,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.5)),
                              onPressed: () => setState(
                                  () => _deletingBookingKey = bookingId),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.only(left: 8),
                            ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(roomTitle,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(dateRange,
                                style: Theme.of(context).textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 14),
                        const SizedBox(width: 6),
                        Text(booking['bookingTime'] ?? 'Arrival time not set',
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                    const Divider(height: 32),
                    Builder(
                      builder: (context) {
                        double totalPrice = double.tryParse(
                                (booking['totalPrice'] ??
                                        booking['total'] ??
                                        booking['price'] ??
                                        0)
                                    .toString()) ??
                            0.0;
                        double amountPaid = double.tryParse(
                                (booking['amountPaid'] ??
                                        booking['payment'] ??
                                        0)
                                    .toString()) ??
                            0.0;
                        double balance = totalPrice - amountPaid;
                        if (balance < 0) balance = 0;

                        return Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total Price',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13,
                                        color: Colors.grey)),
                                Text('₱${totalPrice.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Amount Paid',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13,
                                        color: Colors.grey)),
                                Text('₱${amountPaid.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Colors.green)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Remaining Balance',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14)),
                                Text(
                                  '₱${balance.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: balance > 0
                                        ? AppTheme.primaryAccent
                                        : Colors.green,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text('Tap to view details & QR code',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                            fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatTab extends StatelessWidget {
  final Query chatQuery;
  const _ChatTab({required this.chatQuery});

  @override
  Widget build(BuildContext context) {
    return FirebaseAnimatedList(
      query: chatQuery,
      sort: (a, b) {
        final Map aVal = (a.value ?? {}) as Map;
        final Map bVal = (b.value ?? {}) as Map;
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
      padding: const EdgeInsets.all(20),
      itemBuilder: (context, snapshot, animation, index) {
        if (!snapshot.exists || snapshot.value == null)
          return const SizedBox.shrink();
        Map room = snapshot.value as Map;
        String otherUid = snapshot.key!;
        int unread = int.tryParse(room['unreadCount']?.toString() ?? '0') ?? 0;
        String? photo = room['otherProfilePic'];

        return FadeTransition(
          opacity: animation,
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                backgroundImage: photo != null ? NetworkImage(photo) : null,
                child: photo == null ? const Icon(Icons.person) : null,
              ),
              title: Row(
                children: [
                  Expanded(
                      child: Text(room['otherUserName'] ?? 'User',
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
                  style: const TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => ChatPage(
                          otherUserUid: otherUid,
                          otherUserName: room['otherUserName'] ?? 'User'))),
            ),
          ),
        );
      },
    );
  }
}

class PartnersList extends StatefulWidget {
  final String firstName;
  final List<String> Function(dynamic) parseList;
  final String searchQuery;
  final Map favorites;
  final Function(String, bool) onFavToggle;

  const PartnersList(
      {super.key,
      required this.firstName,
      required this.parseList,
      required this.searchQuery,
      required this.favorites,
      required this.onFavToggle});

  @override
  State<PartnersList> createState() => _PartnersListState();
}

class _PartnersListState extends State<PartnersList> {
  int _limit = 5;
  bool _isLoadingMore = false;
  String _viewMode = 'list';

  void _loadMore() {
    setState(() {
      _isLoadingMore = true;
      _limit += 5;
    });
    // StreamBuilder will automatically rebuild with the new limit
  }

  @override
  Widget build(BuildContext context) {
    final Query propertiesQuery = FirebaseDatabase.instance.ref("properties");
    final Query reviewsQuery = FirebaseDatabase.instance.ref("reviews");

    return StreamBuilder<DatabaseEvent>(
      stream: propertiesQuery.onValue,
      builder: (context, propsSnapshot) {
        return StreamBuilder<DatabaseEvent>(
          stream: reviewsQuery.onValue,
          builder: (context, reviewsSnapshot) {
            if (propsSnapshot.connectionState == ConnectionState.waiting &&
                !propsSnapshot.hasData) return _buildShimmerList();
            if (!propsSnapshot.hasData ||
                propsSnapshot.data!.snapshot.value == null)
              return const Center(child: Text("No properties found."));

            Map propsData = propsSnapshot.data!.snapshot.value as Map;
            Map reviewsData = (reviewsSnapshot.hasData &&
                    reviewsSnapshot.data!.snapshot.value != null)
                ? reviewsSnapshot.data!.snapshot.value as Map
                : {};

            List<Map> recentReviews = [];
            reviewsData.forEach((ownerUid, reviewsMap) {
              if (reviewsMap is Map) {
                reviewsMap.forEach((_, r) {
                  if (r is Map &&
                      r['comment'] != null &&
                      r['comment'].toString().trim().isNotEmpty) {
                    recentReviews.add({...r, 'ownerUid': ownerUid});
                  }
                });
              }
            });
            recentReviews.sort((a, b) {
              int tA = int.tryParse(a['timestamp']?.toString() ?? '0') ?? 0;
              int tB = int.tryParse(b['timestamp']?.toString() ?? '0') ?? 0;
              return tB.compareTo(tA);
            });
            if (recentReviews.length > 5) {
              recentReviews = recentReviews.sublist(0, 5);
            }

            List propertyList = [];
            propsData.forEach((k, v) {
              Map prop = Map<String, dynamic>.from(v);
              prop['uid'] = k;

              double avgRating = 0.0;
              if (reviewsData.containsKey(k)) {
                Map propReviews = reviewsData[k] as Map;
                double sum = 0;
                int count = 0;
                propReviews.forEach((_, rv) {
                  if (rv is Map && rv['rating'] != null) {
                    double val =
                        double.tryParse(rv['rating'].toString()) ?? 0.0;
                    if (val > 0) {
                      sum += val;
                      count++;
                    }
                  }
                });
                if (count > 0) avgRating = sum / count;
              }
              prop['avgRating'] = avgRating;

              if (widget.searchQuery.isEmpty ||
                  prop['name']
                      .toString()
                      .toLowerCase()
                      .contains(widget.searchQuery) ||
                  prop['description']
                      .toString()
                      .toLowerCase()
                      .contains(widget.searchQuery)) {
                propertyList.add(prop);
              }
            });

            // Priority Partner Sorting
            final List<String> priorityPartners = [
              'Hotel Ramiro',
              'Nadzville Resort',
              'Casa DelRio'
            ];

            propertyList.sort((a, b) {
              String nameA = a['name']?.toString() ?? '';
              String nameB = b['name']?.toString() ?? '';

              int indexA =
                  priorityPartners.indexWhere((p) => nameA.contains(p));
              int indexB =
                  priorityPartners.indexWhere((p) => nameB.contains(p));

              if (indexA != -1 && indexB != -1) return indexA.compareTo(indexB);
              if (indexA != -1) return -1;
              if (indexB != -1) return 1;

              // Fallback to average rating
              double aRating = a['avgRating'] ?? 0.0;
              double bRating = b['avgRating'] ?? 0.0;
              if (aRating != bRating) return bRating.compareTo(aRating);

              num aTime = a['createdAt'] ?? 0;
              num bTime = b['createdAt'] ?? 0;
              return bTime.compareTo(aTime);
            });

            bool hasMore = propertyList.length > _limit;
            List displayList =
                hasMore ? propertyList.sublist(0, _limit) : propertyList;

            if (propertyList.isEmpty)
              return const Center(child: Text("No results match your search."));

            return Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Explore Destinations',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            InkWell(
                              onTap: () => setState(() => _viewMode = 'list'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _viewMode == 'list'
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.list,
                                        size: 16,
                                        color: _viewMode == 'list'
                                            ? Colors.white
                                            : Colors.grey),
                                    const SizedBox(width: 4),
                                    Text('List',
                                        style: TextStyle(
                                            color: _viewMode == 'list'
                                                ? Colors.white
                                                : Colors.grey,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => setState(() => _viewMode = 'map'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _viewMode == 'map'
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.map,
                                        size: 16,
                                        color: _viewMode == 'map'
                                            ? Colors.white
                                            : Colors.grey),
                                    const SizedBox(width: 4),
                                    Text('Map',
                                        style: TextStyle(
                                            color: _viewMode == 'map'
                                                ? Colors.white
                                                : Colors.grey,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_viewMode == 'map')
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.2)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: const LatLng(12.8797, 121.7740),
                            initialZoom: 5.5,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.resortsconnectapp',
                            ),
                            MarkerLayer(
                              markers: propertyList
                                  .where((p) =>
                                      p['latitude'] != null &&
                                      p['longitude'] != null &&
                                      p['latitude'] != 0)
                                  .map<Marker>((property) {
                                return Marker(
                                  point: LatLng(
                                      (property['latitude'] as num).toDouble(),
                                      (property['longitude'] as num)
                                          .toDouble()),
                                  width: 250,
                                  height: 80,
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (context) =>
                                                  PropertyDetailsPage(
                                                      propertyName:
                                                          property['name'] ??
                                                              'Resort',
                                                      propertyData: property,
                                                      ownerUid:
                                                          property['uid'])));
                                    },
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            boxShadow: const [
                                              BoxShadow(
                                                  color: Colors.black26,
                                                  blurRadius: 4,
                                                  offset: Offset(0, 2))
                                            ],
                                          ),
                                          child: Text(
                                            property['name'] ?? 'Resort',
                                            style: const TextStyle(
                                                color: Colors.black,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const Icon(Icons.location_on,
                                            color: Colors.red, size: 30),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: displayList.length + 1,
                      itemBuilder: (context, index) {
                        if (index == displayList.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Column(
                              children: [
                                if (hasMore)
                                  ElevatedButton(
                                    onPressed: _loadMore,
                                    child: const Text("LOAD MORE"),
                                  )
                                else
                                  const Text("You've reached the end",
                                      style: TextStyle(
                                          color: Colors.grey, fontSize: 12)),
                                const SizedBox(height: 24),
                                TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) =>
                                                const TermsAndPoliciesPage()));
                                  },
                                  child: const Text(
                                    "Platform Terms & Policies",
                                    style: TextStyle(
                                      decoration: TextDecoration.underline,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                                if (recentReviews.isNotEmpty) ...[
                                  const SizedBox(height: 40),
                                  const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.star,
                                          color: Colors.amber, size: 20),
                                      SizedBox(width: 8),
                                      Text("What Our Guests Say",
                                          style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.amber)),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    height: 160,
                                    child: ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: recentReviews.length,
                                      itemBuilder: (context, rIndex) {
                                        final rev = recentReviews[rIndex];
                                        final rating = double.tryParse(
                                                rev['rating']?.toString() ??
                                                    '0') ??
                                            0;
                                        return Container(
                                          width: 280,
                                          margin:
                                              const EdgeInsets.only(right: 16),
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).cardColor,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            boxShadow: [
                                              BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.05),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 4))
                                            ],
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children:
                                                    List.generate(5, (index) {
                                                  return Icon(
                                                    index < rating
                                                        ? Icons.star
                                                        : Icons.star_border,
                                                    size: 16,
                                                    color: Colors.amber,
                                                  );
                                                }),
                                              ),
                                              const SizedBox(height: 8),
                                              Expanded(
                                                child: Text(
                                                  '"${rev['comment']}"',
                                                  style: const TextStyle(
                                                      fontStyle:
                                                          FontStyle.italic,
                                                      fontSize: 13),
                                                  maxLines: 3,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  const Icon(Icons.person,
                                                      size: 16,
                                                      color: Colors.grey),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    rev['touristName'] ??
                                                        'Guest',
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ]
                              ],
                            ),
                          );
                        }
                        Map property = displayList[index];
                        bool isFav =
                            widget.favorites.containsKey(property['uid']);
                        List<String> images =
                            widget.parseList(property['imageUrls']);
                        String? firstImage =
                            images.isNotEmpty ? images[0] : null;
                        String? fallbackAsset;
                        if (firstImage == null) {
                          final name = (property['name'] ?? '').toString();
                          if (name.contains('Casa DelRio') ||
                              name.contains('Casa Delrio')) {
                            fallbackAsset = 'assets/CasaDelRio5.webp';
                          } else if (name.contains('Hotel Ramiro')) {
                            fallbackAsset = 'assets/HotelRamiro5.webp';
                          } else if (name.contains('Nadzville Resort')) {
                            fallbackAsset = 'assets/NadzvilleResort1.jpg';
                          }
                        }

                        return Card(
                          margin: const EdgeInsets.only(bottom: 20),
                          child: InkWell(
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => PropertyDetailsPage(
                                        propertyName:
                                            property['name'] ?? 'Resort',
                                        propertyData: property,
                                        ownerUid: property['uid']))),
                            borderRadius: BorderRadius.circular(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(16)),
                                      child: firstImage != null
                                          ? Image.network(firstImage,
                                              height: 200,
                                              width: double.infinity,
                                              fit: BoxFit.cover,
                                              cacheWidth: 600,
                                              errorBuilder: (c, e, s) =>
                                                  Container(
                                                      height: 200,
                                                      color: Colors.grey[200],
                                                      child: const Icon(
                                                          Icons.broken_image,
                                                          size: 50)))
                                          : (fallbackAsset != null
                                              ? Image.asset(fallbackAsset,
                                                  height: 200,
                                                  width: double.infinity,
                                                  fit: BoxFit.cover)
                                              : Container(
                                                  height: 200,
                                                  color: Colors.grey[200],
                                                  child: const Icon(
                                                      Icons.business,
                                                      size: 50))),
                                    ),
                                    Positioned(
                                      top: 12,
                                      right: 12,
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                                color: Colors.black
                                                    .withValues(alpha: 0.7),
                                                borderRadius:
                                                    BorderRadius.circular(20)),
                                            child: Text(
                                                property['type'] ?? 'Resort',
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ),
                                          const SizedBox(width: 8),
                                          _FavoriteHeart(
                                              propertyId: property['uid'],
                                              isInitiallyFav: isFav,
                                              onToggle: widget.onFavToggle),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                              child: Text(
                                                  property['name'] ?? 'Resort',
                                                  style: const TextStyle(
                                                      fontSize: 20,
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          _buildRatingBadge(property['uid']),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(property['description'] ?? '',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          _buildInfoChip(
                                              context,
                                              Icons.meeting_room_outlined,
                                              '${property['rooms'] ?? 0} Rooms'),
                                          const SizedBox(width: 12),
                                          _buildInfoChip(
                                              context,
                                              Icons.people_outline,
                                              '${property['staffCount'] ?? 0} Staff'),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildShimmerList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 3,
      itemBuilder: (context, index) => Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Container(
          height: 300,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  Widget _buildRatingBadge(String propertyUid) {
    return StreamBuilder<DatabaseEvent>(
        stream: FirebaseDatabase.instance.ref("reviews/$propertyUid").onValue,
        builder: (context, snapshot) {
          double rating = 0.0;
          int count = 0;
          if (snapshot.hasData && snapshot.data!.snapshot.exists) {
            final rawValue = snapshot.data!.snapshot.value;
            if (rawValue is Map) {
              double sum = 0;
              rawValue.forEach((k, v) {
                if (v is Map && v['rating'] != null) {
                  double val = double.tryParse(v['rating'].toString()) ?? 0.0;
                  if (val > 0) {
                    sum += val;
                    count++;
                  }
                }
              });
              if (count > 0) rating = sum / count;
            }
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_rounded,
                  color: rating > 0 ? Colors.amber[600] : Colors.grey[400],
                  size: 20),
              const SizedBox(width: 4),
              Text(rating > 0 ? rating.toStringAsFixed(1) : '0.0',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (count > 0)
                Text(' ($count)',
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          );
        });
  }

  Widget _buildInfoChip(BuildContext context, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color:
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.secondary)),
        ],
      ),
    );
  }
}

class _FavoriteHeart extends StatefulWidget {
  final String propertyId;
  final bool isInitiallyFav;
  final Function(String, bool) onToggle;
  const _FavoriteHeart(
      {required this.propertyId,
      required this.isInitiallyFav,
      required this.onToggle});

  @override
  State<_FavoriteHeart> createState() => _FavoriteHeartState();
}

class _FavoriteHeartState extends State<_FavoriteHeart> {
  late bool _isFav;

  @override
  void initState() {
    super.initState();
    _isFav = widget.isInitiallyFav;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() => _isFav = !_isFav);
        widget.onToggle(widget.propertyId, !_isFav);
      },
      child: CircleAvatar(
        radius: 18,
        backgroundColor: Colors.white.withValues(alpha: 0.9),
        child: Icon(_isFav ? Icons.favorite : Icons.favorite_border,
            color: _isFav ? Colors.red : Colors.grey, size: 20),
      ),
    );
  }
}

class FavoritesList extends StatelessWidget {
  final List<String> Function(dynamic) parseList;
  final Map favorites;
  final Function(String, bool) onFavToggle;

  const FavoritesList(
      {super.key,
      required this.parseList,
      required this.favorites,
      required this.onFavToggle});

  @override
  Widget build(BuildContext context) {
    if (favorites.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border_rounded, size: 60, color: Colors.grey),
            SizedBox(height: 16),
            Text("You haven't added any favorites yet.",
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final propertiesQuery = FirebaseDatabase.instance.ref("properties");
    return StreamBuilder<DatabaseEvent>(
      stream: propertiesQuery.onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null)
          return const SizedBox();

        Map data = snapshot.data!.snapshot.value as Map;
        List propertyList = [];
        data.forEach((k, v) {
          if (favorites.containsKey(k)) {
            Map prop = Map<String, dynamic>.from(v);
            prop['uid'] = k;
            propertyList.add(prop);
          }
        });

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: propertyList.length,
          itemBuilder: (context, index) {
            Map property = propertyList[index];
            List<String> images = parseList(property['imageUrls']);
            String? firstImage = images.isNotEmpty ? images[0] : null;

            return Card(
              margin: const EdgeInsets.only(bottom: 20),
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: firstImage != null
                      ? Image.network(firstImage,
                          width: 60, height: 60, fit: BoxFit.cover)
                      : Container(
                          width: 60, height: 60, color: Colors.grey[200]),
                ),
                title: Text(property['name'] ?? 'Resort',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(property['type'] ?? ''),
                trailing: IconButton(
                  icon: const Icon(Icons.favorite, color: Colors.red),
                  onPressed: () => onFavToggle(property['uid'], true),
                ),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => PropertyDetailsPage(
                            propertyName: property['name'] ?? 'Resort',
                            propertyData: property,
                            ownerUid: property['uid']))),
              ),
            );
          },
        );
      },
    );
  }
}

class FaqList extends StatelessWidget {
  const FaqList({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref("master_data/faqs").onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.snapshot.exists) {
          return const Center(child: CircularProgressIndicator());
        }

        Map data = snapshot.data!.snapshot.value as Map;
        List faqs = data.values.toList();

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: faqs.length,
          itemBuilder: (context, index) {
            Map faq = faqs[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                title: Text(faq['q'] ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(faq['a'] ?? '',
                        style: const TextStyle(
                            fontSize: 14, height: 1.5, color: Colors.blueGrey)),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class AiChatBotPage extends StatefulWidget {
  const AiChatBotPage({super.key});

  @override
  State<AiChatBotPage> createState() => _AiChatBotPageState();
}

class _AiChatBotPageState extends State<AiChatBotPage> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [
    {
      'text':
          'Hello! I am your Resort Connect AI assistant. How can I help you today?',
      'isMe': false
    }
  ];
  bool _isTyping = false;
  List<Map<String, dynamic>> _faqs = [
    {
      'q': 'How do I book a room?',
      'a':
          'Browse resorts in the "Partners" tab, select a room, and click "Book Now".'
    },
    {
      'q': 'Can I cancel my booking?',
      'a': 'Yes, in the "My Bookings" tab, you can request a cancellation.'
    },
    {
      'q': 'How does rescheduling work?',
      'a':
          'Go to "My Bookings", click "Reschedule", and pick a new date and duration.'
    },
    {
      'q': 'Is my payment secure?',
      'a':
          'Yes, we use GCash for verified payments and manual receipt verification.'
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadFaqs();
  }

  Future<void> _loadFaqs() async {
    final snap = await FirebaseDatabase.instance.ref("master_data/faqs").get();
    if (snap.exists) {
      Map data = snap.value as Map;
      setState(() {
        _faqs = data.values.map((e) => Map<String, dynamic>.from(e)).toList();
      });
    }
  }

  void _handleSend([String? forcedMsg]) async {
    String text = forcedMsg ?? _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'text': text, 'isMe': true});
      _isTyping = true;
    });
    if (forcedMsg == null) _controller.clear();

    // Simulate AI delay
    await Future.delayed(const Duration(seconds: 1));

    String response = await _getAiResponse(text);

    if (mounted) {
      setState(() {
        _messages.add({'text': response, 'isMe': false});
        _isTyping = false;
      });
    }
  }

  Future<String> _getAiResponse(String input) async {
    String query = input.toLowerCase().trim();

    // 1. Try to find an exact match in the current faqs list
    for (var faq in _faqs) {
      if (faq['q'].toString().toLowerCase().trim() == query) {
        return faq['a'].toString();
      }
    }

    // 2. Fetch latest FAQs from Database if not matched yet
    final snap = await FirebaseDatabase.instance.ref("master_data/faqs").get();
    if (snap.exists) {
      Map faqs = snap.value as Map;
      for (var faq in faqs.values) {
        String faqQ = faq['q'].toString().toLowerCase();
        if (query.contains(faqQ) || faqQ.contains(query)) {
          return faq['a'].toString();
        }

        // Fuzzy match significant words
        final keywords = faqQ.split(' ').where((w) => w.length > 4);
        if (keywords.any((k) => query.contains(k))) {
          return faq['a'].toString();
        }
      }
    }

    if (query.contains('hi') || query.contains('hello')) {
      return 'Hello! How can I assist you with your resort adventure?';
    }
    if (query.contains('book')) {
      return 'To book, go to the "Partners" tab, pick a resort, and select a room.';
    }
    if (query.contains('cancel')) {
      return 'You can cancel bookings in the "My Bookings" tab, subject to owner approval.';
    }
    if (query.contains('mura') ||
        query.contains('cheapest') ||
        query.contains('lowest') ||
        query.contains('affordable')) {
      return await _findCheapestRoom();
    }
    if (query.contains('mahal') ||
        query.contains('expensive') ||
        query.contains('premium') ||
        query.contains('luxury')) {
      return await _findMostExpensiveRoom();
    }
    if (query.contains('pool') || query.contains('swimming')) {
      return "Many of our resorts have swimming pools! You can go to the 'Partners' tab and check the 'Amenities' section of each resort to find the perfect pool for your stay.";
    }
    if (query.contains('pet') ||
        query.contains('dog') ||
        query.contains('cat')) {
      return "Looking to bring your furry friends? Some of our resorts are pet-friendly! Please check the specific resort's policies in the Partners tab before booking.";
    }
    if (query.contains('thanks') ||
        query.contains('thank you') ||
        query.contains('salamat')) {
      return "You're very welcome! Let me know if you need anything else.";
    }
    if (query.contains('group') ||
        query.contains('family') ||
        query.contains('barkada') ||
        query.contains('marami')) {
      return await _findLargestRoom();
    }
    if (query.contains('payment') ||
        query.contains('gcash') ||
        query.contains('bayad')) {
      return "For payments, we currently support GCash! You have the option to pay the Full Amount or a 30% Downpayment when booking a room. The remaining balance can be paid at the resort.";
    }
    if (query.contains('location') ||
        query.contains('saan') ||
        query.contains('where')) {
      return "ResortsConnect features amazing properties! You can go to the 'Partners' tab and use the Map view to see exact locations and even get directions.";
    }
    if (query.contains('refund') || query.contains('bawi')) {
      return "Refunds are processed depending on the resort's cancellation policy. Generally, you need to request cancellation through the 'My Bookings' tab and wait for the owner's approval.";
    }

    return "I'm not quite sure about that. You can click one of the 'Common Questions' buttons at the top of our chat for help, or try asking about the cheapest, most expensive, or largest rooms for groups!";
  }

  Future<String> _findLargestRoom() async {
    final snap = await FirebaseDatabase.instance.ref("properties").get();
    if (!snap.exists)
      return "Sorry, I couldn't find any properties at the moment.";

    Map properties = snap.value as Map;
    int largestCapacity = 0;
    String bestRoomName = "";
    String bestResortName = "";

    properties.forEach((ownerUid, propData) {
      if (propData is Map && propData['roomInventory'] != null) {
        String resortName = propData['name'] ?? 'A resort';
        var rooms = propData['roomInventory'];

        Map roomsMap = {};
        if (rooms is Map) {
          roomsMap = rooms;
        } else if (rooms is List) {
          for (int i = 0; i < rooms.length; i++) {
            if (rooms[i] != null) roomsMap[i.toString()] = rooms[i];
          }
        }

        roomsMap.forEach((_, roomData) {
          if (roomData is Map) {
            int capacity = int.tryParse(roomData['maxPax']?.toString() ??
                    roomData['capacity']?.toString() ??
                    '0') ??
                0;
            if (capacity > largestCapacity) {
              largestCapacity = capacity;
              bestRoomName = roomData['title'] ?? 'Room';
              bestResortName = resortName;
            }
          }
        });
      }
    });

    if (largestCapacity == 0)
      return "I couldn't find any room capacities right now.";

    return "If you're traveling with a big group or family, I recommend the '$bestRoomName' at $bestResortName. It can accommodate up to $largestCapacity people! Check it out in the Partners tab.";
  }

  Future<String> _findCheapestRoom() async {
    final snap = await FirebaseDatabase.instance.ref("properties").get();
    if (!snap.exists)
      return "Sorry, I couldn't find any properties at the moment.";

    Map properties = snap.value as Map;
    double lowestPrice = double.infinity;
    String bestRoomName = "";
    String bestResortName = "";

    properties.forEach((ownerUid, propData) {
      if (propData is Map && propData['roomInventory'] != null) {
        String resortName = propData['name'] ?? 'A resort';
        var rooms = propData['roomInventory'];

        Map roomsMap = {};
        if (rooms is Map) {
          roomsMap = rooms;
        } else if (rooms is List) {
          for (int i = 0; i < rooms.length; i++) {
            if (rooms[i] != null) roomsMap[i.toString()] = rooms[i];
          }
        }

        roomsMap.forEach((_, roomData) {
          if (roomData is Map && roomData['price'] != null) {
            double price = double.tryParse(roomData['price'].toString()) ??
                double.infinity;
            if (price < lowestPrice) {
              lowestPrice = price;
              bestRoomName = roomData['title'] ?? 'Room';
              bestResortName = resortName;
            }
          }
        });
      }
    });

    if (lowestPrice == double.infinity) {
      return "I couldn't find any room prices right now. Please check the Partners tab for available rooms.";
    }

    return "Based on our current listings, the most affordable option is the '$bestRoomName' at $bestResortName for just ₱${lowestPrice.toStringAsFixed(0)} per night! Go to the Partners tab to book it.";
  }

  Future<String> _findMostExpensiveRoom() async {
    final snap = await FirebaseDatabase.instance.ref("properties").get();
    if (!snap.exists)
      return "Sorry, I couldn't find any properties at the moment.";

    Map properties = snap.value as Map;
    double highestPrice = 0;
    String bestRoomName = "";
    String bestResortName = "";

    properties.forEach((ownerUid, propData) {
      if (propData is Map && propData['roomInventory'] != null) {
        String resortName = propData['name'] ?? 'A resort';
        var rooms = propData['roomInventory'];

        Map roomsMap = {};
        if (rooms is Map) {
          roomsMap = rooms;
        } else if (rooms is List) {
          for (int i = 0; i < rooms.length; i++) {
            if (rooms[i] != null) roomsMap[i.toString()] = rooms[i];
          }
        }

        roomsMap.forEach((_, roomData) {
          if (roomData is Map && roomData['price'] != null) {
            double price = double.tryParse(roomData['price'].toString()) ?? 0;
            if (price > highestPrice) {
              highestPrice = price;
              bestRoomName = roomData['title'] ?? 'Room';
              bestResortName = resortName;
            }
          }
        });
      }
    });

    if (highestPrice == 0) {
      return "I couldn't find any room prices right now.";
    }

    return "If you're looking for premium luxury, our most expensive offering is the '$bestRoomName' at $bestResortName for ₱${highestPrice.toStringAsFixed(0)} per night. Check it out in the Partners tab!";
  }

  @override
  Widget build(BuildContext context) {
    final secondaryColor = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(title: const Text('AI Assistant'), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _messages.length + (_faqs.isNotEmpty ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == 0) {
                  // Always show the welcome message first
                  return _buildMsgBubble(
                      _messages[0]['text'], false, secondaryColor);
                }

                if (index == 1 && _faqs.isNotEmpty) {
                  // Show FAQs immediately after the welcome message
                  return Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('COMMON QUESTIONS',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Colors.grey,
                                letterSpacing: 1)),
                        const SizedBox(height: 8),
                        ..._faqs.map((f) => Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: InkWell(
                                onTap: () => _handleSend(f['q']),
                                borderRadius: BorderRadius.circular(15),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: secondaryColor.withOpacity(0.3)),
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  child: Text(f['q'] ?? '',
                                      style: TextStyle(
                                          color: secondaryColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                ),
                              ),
                            )),
                      ],
                    ),
                  );
                }

                // Adjust index for messages after FAQ block
                final msgIndex =
                    _faqs.isNotEmpty ? (index > 1 ? index - 1 : index) : index;
                if (msgIndex >= _messages.length)
                  return const SizedBox.shrink();
                if (msgIndex == 0)
                  return const SizedBox.shrink(); // Already shown at index 0

                final m = _messages[msgIndex];
                return _buildMsgBubble(m['text'], m['isMe'], secondaryColor);
              },
            ),
          ),
          if (_isTyping)
            const Padding(
                padding: EdgeInsets.only(left: 20, bottom: 8),
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('AI is typing...',
                        style: TextStyle(
                            fontSize: 10, fontStyle: FontStyle.italic)))),
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).cardColor,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(
                          r'[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]',
                          unicode: true))
                    ],
                    decoration: const InputDecoration(
                        hintText: 'Ask me anything...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
                IconButton(
                    onPressed: () => _handleSend(),
                    icon: Icon(Icons.send_rounded, color: secondaryColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMsgBubble(String text, bool isMe, Color secondaryColor) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe ? secondaryColor : Colors.grey[200],
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomRight: isMe ? const Radius.circular(0) : null,
            bottomLeft: isMe ? null : const Radius.circular(0),
          ),
        ),
        child: Text(text,
            style: TextStyle(
                color: isMe ? Colors.black : Colors.black87,
                fontWeight: FontWeight.w500)),
      ),
    );
  }
}
