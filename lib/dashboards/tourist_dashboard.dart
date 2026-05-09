import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../chat_page.dart';
import '../profile_page.dart';
import '../property_details_page.dart';
import '../notifications_page.dart';
import '../theme_provider.dart';
import '../theme.dart';

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

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _userStream = FirebaseDatabase.instance.ref("users/${user?.uid}").onValue.asBroadcastStream();
    
    final chatRoomsRef = FirebaseDatabase.instance.ref("chat_rooms/${user?.uid}");
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

  List<String> _parseList(dynamic data) {
    if (data == null) return [];
    if (data is List) return data.where((e) => e != null).map((e) => e.toString()).toList();
    if (data is Map) {
      var sortedKeys = data.keys.toList()..sort((a, b) => a.toString().compareTo(b.toString()));
      return sortedKeys.map((k) => data[k].toString()).toList();
    }
    return [];
  }

  void _toggleFavorite(String propertyId, bool isCurrentlyFav) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseDatabase.instance.ref("users/${user.uid}/favorites/$propertyId");
    if (isCurrentlyFav) {
      await ref.remove();
    } else {
      await ref.set(true);
    }
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Logout?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  FirebaseAuth.instance.signOut();
                },
                child: const Text('Logout', style: TextStyle(color: AppTheme.primaryAccent))
            )
          ],
        )
    );
  }

  Future<void> _cancelBooking(String bookingId) async {
    final reasonController = TextEditingController();
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Booking?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please provide a reason for cancellation:'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(hintText: 'Reason...'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, Cancel', style: TextStyle(color: AppTheme.primaryAccent))),
        ],
      ),
    );

    if (confirm == true) {
      String reason = reasonController.text.trim();
      if (reason.isEmpty) reason = "No reason provided";

      await FirebaseDatabase.instance.ref("bookings/$bookingId").update({
        'status': 'Cancelled',
        'cancellationReason': reason,
        'cancelledBy': 'Tourist'
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking request cancelled.')));
    }
  }

  void _showReviewDialog(Map booking, String bookingId) {
    int rating = 5;
    final commentController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Rate ${booking['propertyName']}', overflow: TextOverflow.ellipsis),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) => IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(Icons.star_rounded, size: 44, color: index < rating ? Colors.amber : Colors.grey[400]),
                      onPressed: () => setDialogState(() => rating = index + 1)
                  )),
                ),
              ),
              const SizedBox(height: 16),
              TextField(controller: commentController, maxLines: 3, decoration: const InputDecoration(hintText: 'Share your experience...')),
            ],
          ),
          actions: [
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    final user = FirebaseAuth.instance.currentUser;
                    try {
                      String tName = booking['touristName'] ?? booking['name'] ?? booking['fullName'] ?? 'Tourist';
                      await FirebaseDatabase.instance.ref("reviews/${booking['ownerUid']}").push().set({
                        'touristUid': user?.uid,
                        'touristName': tName,
                        'rating': rating,
                        'comment': commentController.text.trim(),
                        'timestamp': ServerValue.timestamp
                      });
                      await FirebaseDatabase.instance.ref("bookings/$bookingId").update({'isReviewed': true});
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thank you for your review!')));
                      }
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondaryAccent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(100, 45)
                  ),
                  child: const Text('Submit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteBookingDialog(String key) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Booking Record?'),
        content: const Text('This will permanently remove this booking from your history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await FirebaseDatabase.instance.ref("bookings/$key").remove();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Record deleted.')));
              },
              child: const Text('Delete', style: TextStyle(color: AppTheme.primaryAccent))
          ),
        ],
      ),
    );
  }

  void _showQRCode(String bookingId) {
    // URL format used by the website to identify bookings
    final String bookingUrl = "https://resortconnect-f7dd6.web.app/owner?scan=${Uri.encodeComponent(bookingId)}";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Booking QR Code', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Show this to the resort staff. It works with both our website and app scanners.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white, 
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)
                ]
              ),
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
            SelectableText(bookingId, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _showBookingDetails(Map booking, String bookingId) {
    String rawStatus = (booking['status'] ?? 'Pending').toString().trim().toLowerCase();
    String status = rawStatus == 'approved' ? 'confirmed' : rawStatus;
    
    List addons = booking['selectedAddons'] is List ? booking['selectedAddons'] : [];

    String roomTitle = booking['activityTitle'] ?? booking['roomTitle'] ?? booking['activityName'] ?? booking['room'] ?? booking['roomId'] ?? 'N/A';
    String? bDate = booking['bookingDate'] ?? booking['checkInDate'] ?? booking['date'] ?? booking['createdAt'] ?? 'N/A';
    if (bDate != null && bDate.contains('T') && bDate.contains('Z')) {
      try { bDate = DateFormat('MMM dd, yyyy').format(DateTime.parse(bDate)); } catch (e) {}
    }
    String totalAmountStr = (booking['totalPrice'] ?? booking['total'] ?? booking['amount'] ?? booking['payment'] ?? booking['price'] ?? 0).toString();
    double total = double.tryParse(totalAmountStr) ?? 0;
    double paid = double.tryParse((booking['amountPaid'] ?? 0).toString()) ?? 0;
    String payMethod = booking['paymentMethod'] ?? booking['paymentOption'] ?? booking['payment'] ?? booking['paymentType'] ?? 'N/A';
    String payOption = (booking['paymentOption'] ?? booking['paymentMethod'] ?? '').toString();

    String dateRange = bDate ?? 'N/A';
    try {
      if (bDate != null) {
        DateTime start = DateFormat('MMM dd, yyyy').parse(bDate);
        int nights = int.tryParse(booking['nights'].toString()) ?? 1;
        DateTime end = start.add(Duration(days: nights));
        dateRange = "$bDate - ${DateFormat('MMM dd, yyyy').format(end)} ($nights Nights)";
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
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
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(booking['propertyName'] ?? 'Resort', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
                  IconButton(
                    icon: const Icon(Icons.share_rounded),
                    onPressed: () {
                      String msg = "My Booking Details at ${booking['propertyName']}:\n"
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
              _detailItem(Icons.calendar_month_rounded, "Date Range", dateRange),
              _detailItem(Icons.access_time_rounded, "Arrival Time", booking['bookingTime'] ?? 'N/A'),
              
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondary.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).colorScheme.secondary.withOpacity(0.1))),
                child: Column(
                  children: [
                    _priceRow("Total Amount", "₱${total.toStringAsFixed(2)}"),
                    const SizedBox(height: 8),
                    _priceRow("Amount Paid", "₱${paid.toStringAsFixed(2)}", isBold: true, color: Colors.green),
                    const SizedBox(height: 8),
                    _priceRow("Remaining Balance", "₱${balance.toStringAsFixed(2)}", isBold: true, color: balance > 0 ? AppTheme.primaryAccent : null),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              _detailItem(Icons.credit_card_rounded, "Payment Method", payMethod),
              if (addons.isNotEmpty) _detailItem(Icons.add_box_rounded, "Add-ons", addons.join(', ')),
              if (booking['cancellationReason'] != null) _detailItem(Icons.error_outline_rounded, "Note", booking['cancellationReason'], isError: true),
              const SizedBox(height: 32),
              if (status == 'confirmed' || status == 'checked in') ...[
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton.icon(
                    onPressed: () { Navigator.pop(context); _showQRCode(bookingId); },
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: const Text('SHOW QR CODE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (status == 'pending') SizedBox(
                width: double.infinity,
                height: 55,
                child: OutlinedButton(
                  onPressed: () { Navigator.pop(context); _cancelBooking(bookingId); },
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primaryAccent, side: const BorderSide(color: AppTheme.primaryAccent), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text('CANCEL BOOKING REQUEST', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _priceRow(String label, String value, {bool isBold = false, Color? color}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
      Text(value, style: TextStyle(fontSize: 15, fontWeight: isBold ? FontWeight.w900 : FontWeight.bold, color: color)),
    ],
  );

  Widget _detailItem(IconData icon, String label, String value, {bool isError = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: isError ? AppTheme.primaryAccent : Theme.of(context).colorScheme.primary),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isError ? AppTheme.primaryAccent : null)),
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
    final myBookingsQuery = FirebaseDatabase.instance.ref("bookings").orderByChild("touristUid").equalTo(user?.uid);

    return StreamBuilder<DatabaseEvent>(
      stream: _userStream,
      builder: (context, snapshot) {
        String firstName = "Tourist";
        String? profilePic;
        Map favorites = {};
        if (snapshot.hasData && snapshot.data!.snapshot.exists) {
          Map data = snapshot.data!.snapshot.value as Map;
          firstName = data['firstName'] ?? "Tourist";
          profilePic = data['profilePicUrl'];
          favorites = data['favorites'] ?? {};
        }

        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: 80,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Resort Connect', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  Text('Hello, $firstName!', style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
              actions: [
                IconButton(
                  icon: Icon(themeProvider.themeMode == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
                  color: Theme.of(context).colorScheme.secondary,
                  onPressed: () => themeProvider.toggleTheme(),
                ),
                _appBarAction(Icons.notifications_none_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsPage()))),
                Padding(
                  padding: const EdgeInsets.only(right: 16, left: 8),
                  child: GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfilePage())),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
                      backgroundImage: profilePic != null ? NetworkImage(profilePic) : null,
                      child: profilePic == null ? Icon(Icons.person_outline_rounded, color: Theme.of(context).colorScheme.secondary) : null,
                    ),
                  ),
                ),
                _appBarAction(Icons.logout_rounded, () => _showLogoutDialog(context), isLogout: true),
              ],
              bottom: TabBar(
                tabs: [
                  const Tab(text: 'Partners'), 
                  const Tab(text: 'Favorites'), 
                  Tab(child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Chat'),
                      if (_totalUnread > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppTheme.primaryAccent, borderRadius: BorderRadius.circular(10)),
                          child: Text(_totalUnread.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ]
                    ],
                  )),
                  const Tab(text: 'My Bookings')
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
                          decoration: InputDecoration(
                            hintText: "Search Resorts, Hotels, Locations...",
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() { _searchController.clear(); _searchQuery = ""; })) : null,
                          ),
                          onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                        ),
                      ),
                      Expanded(child: PartnersList(firstName: firstName, parseList: _parseList, searchQuery: _searchQuery, favorites: favorites, onFavToggle: _toggleFavorite)),
                    ],
                  ),
                  FavoritesList(parseList: _parseList, favorites: favorites, onFavToggle: _toggleFavorite),
                  _ChatTab(chatQuery: FirebaseDatabase.instance.ref("chat_rooms/${user?.uid}")),
                  FirebaseAnimatedList(
                    query: myBookingsQuery,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                    itemBuilder: (context, snapshot, animation, index) {
                      if (!snapshot.exists || snapshot.value == null) return const SizedBox.shrink();
                      Map booking = snapshot.value as Map;
                      return FadeTransition(opacity: animation, child: _buildMyBookingCard(booking, snapshot.key!));
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _appBarAction(IconData icon, VoidCallback onTap, {bool isLogout = false}) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(
        color: isLogout ? Colors.red.withValues(alpha: 0.05) : Theme.of(context).colorScheme.secondary.withValues(alpha: 0.05),
        shape: BoxShape.circle
    ),
    child: IconButton(icon: Icon(icon, color: isLogout ? Colors.red : Theme.of(context).colorScheme.secondary, size: 22), onPressed: onTap),
  );

  Widget _buildMyBookingCard(Map booking, String bookingId) {
    Color statusColor = Colors.orange;
    String rawStatus = (booking['status'] ?? 'Pending').toString().trim().toLowerCase();
    String status = rawStatus == 'approved' ? 'confirmed' : rawStatus;
    
    if (status == 'confirmed' || status == 'checked in' || status == 'completed') statusColor = Colors.green;
    if (status == 'cancelled') statusColor = AppTheme.primaryAccent;

    String roomTitle = booking['activityTitle'] ?? booking['roomTitle'] ?? booking['activityName'] ?? booking['room'] ?? booking['roomId'] ?? 'Booking';
    String? bDate = booking['bookingDate'] ?? booking['checkInDate'] ?? booking['date'] ?? booking['createdAt'] ?? 'N/A';
    if (bDate != null && bDate.contains('T') && bDate.contains('Z')) {
      try { bDate = DateFormat('MMM dd, yyyy').format(DateTime.parse(bDate)); } catch (e) {}
    }

    String dateRange = bDate ?? 'N/A';
    try {
      if (bDate != null && booking['nights'] != null) {
        DateTime start = DateFormat('MMM dd, yyyy').parse(bDate);
        int nights = int.tryParse(booking['nights'].toString()) ?? 1;
        DateTime end = start.add(Duration(days: nights));
        dateRange = "$bDate - ${DateFormat('MMM dd, yyyy').format(end)} ($nights Nights)";
      }
    } catch (e) {}

    String totalAmount = (booking['totalPrice'] ?? booking['total'] ?? booking['amount'] ?? booking['payment'] ?? booking['price'] ?? 0).toString();

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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: statusColor.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    Expanded(child: Text(booking['propertyName'] ?? 'Resort', style: Theme.of(context).textTheme.titleLarge, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(30)),
                      child: Text(status == 'confirmed' ? 'Confirmed' : (booking['status'] ?? 'Pending'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                    ),
                    if (booking['isReviewed'] == true || status == 'cancelled') IconButton(
                      icon: Icon(Icons.delete_outline_rounded, size: 20, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                      onPressed: () => _showDeleteBookingDialog(bookingId),
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
                    Text(roomTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 14),
                        const SizedBox(width: 6),
                        Expanded(child: Text(dateRange, style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 14),
                        const SizedBox(width: 6),
                        Text(booking['bookingTime'] ?? 'Arrival time not set', style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                    const Divider(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Payment', style: TextStyle(fontWeight: FontWeight.w500)),
                        Text('₱$totalAmount', style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.secondary, fontSize: 20)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Tap to view details & QR code', style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic)),
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
        
        num aNum = (aTime is num) ? aTime : (aTime is Map ? DateTime.now().millisecondsSinceEpoch : 0);
        num bNum = (bTime is num) ? bTime : (bTime is Map ? DateTime.now().millisecondsSinceEpoch : 0);
        
        return bNum.compareTo(aNum);
      },
      padding: const EdgeInsets.all(20),
      itemBuilder: (context, snapshot, animation, index) { 
        if (!snapshot.exists || snapshot.value == null) return const SizedBox.shrink(); 
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
                backgroundColor: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                backgroundImage: photo != null ? NetworkImage(photo) : null,
                child: photo == null ? const Icon(Icons.person) : null,
              ),
              title: Row(
                children: [
                  Expanded(child: Text(room['otherUserName'] ?? 'User', style: const TextStyle(fontWeight: FontWeight.bold))),
                  if (unread > 0) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AppTheme.primaryAccent, borderRadius: BorderRadius.circular(12)),
                    child: Text(unread.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              subtitle: Text(room['lastMessage'] != null ? 'New Message' : 'Tap to open chat', style: const TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChatPage(otherUserUid: otherUid, otherUserName: room['otherUserName'] ?? 'User'))),
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

  const PartnersList({super.key, required this.firstName, required this.parseList, required this.searchQuery, required this.favorites, required this.onFavToggle});

  @override
  State<PartnersList> createState() => _PartnersListState();
}

class _PartnersListState extends State<PartnersList> {
  final DatabaseReference _propertiesQuery = FirebaseDatabase.instance.ref("properties");

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: _propertiesQuery.onValue,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return _buildShimmerList();
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) return const Center(child: Text("No properties found."));

        Map data = snapshot.data!.snapshot.value as Map;
        List propertyList = [];
        data.forEach((k, v) {
          Map prop = Map<String, dynamic>.from(v);
          prop['uid'] = k;
          if (widget.searchQuery.isEmpty ||
              prop['name'].toString().toLowerCase().contains(widget.searchQuery) ||
              prop['description'].toString().toLowerCase().contains(widget.searchQuery)) {
            propertyList.add(prop);
          }
        });

        if (propertyList.isEmpty) return const Center(child: Text("No results match your search."));

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: propertyList.length,
          itemBuilder: (context, index) {
            Map property = propertyList[index];
            bool isFav = widget.favorites.containsKey(property['uid']);
            List<String> images = widget.parseList(property['imageUrls']);
            String? firstImage = images.isNotEmpty ? images[0] : null;

            return Card(
              margin: const EdgeInsets.only(bottom: 20),
              child: InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => PropertyDetailsPage(propertyName: property['name'] ?? 'Resort', propertyData: property, ownerUid: property['uid']))),
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          child: firstImage != null
                              ? Image.network(firstImage, height: 200, width: double.infinity, fit: BoxFit.cover, cacheWidth: 600, errorBuilder: (c, e, s) => Container(height: 200, color: Colors.grey[200], child: const Icon(Icons.broken_image, size: 50)))
                              : Container(height: 200, color: Colors.grey[200], child: const Icon(Icons.business, size: 50)),
                        ),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(20)),
                                child: Text(property['type'] ?? 'Resort', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              _FavoriteHeart(
                                  propertyId: property['uid'],
                                  isInitiallyFav: isFav,
                                  onToggle: widget.onFavToggle
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text(property['name'] ?? 'Resort', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                              _buildRatingBadge(property['uid']),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(property['description'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _buildInfoChip(context, Icons.meeting_room_outlined, '${property['rooms'] ?? 0} Rooms'),
                              const SizedBox(width: 12),
                              _buildInfoChip(context, Icons.people_outline, '${property['staffCount'] ?? 0} Staff'),
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
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
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
              Icon(Icons.star_rounded, color: rating > 0 ? Colors.amber[600] : Colors.grey[400], size: 20),
              const SizedBox(width: 4),
              Text(rating > 0 ? rating.toStringAsFixed(1) : '0.0', style: const TextStyle(fontWeight: FontWeight.bold)),
              if (count > 0) Text(' ($count)', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          );
        }
    );
  }

  Widget _buildInfoChip(BuildContext context, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.secondary)),
        ],
      ),
    );
  }
}

class _FavoriteHeart extends StatefulWidget {
  final String propertyId;
  final bool isInitiallyFav;
  final Function(String, bool) onToggle;
  const _FavoriteHeart({required this.propertyId, required this.isInitiallyFav, required this.onToggle});

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
        child: Icon(_isFav ? Icons.favorite : Icons.favorite_border, color: _isFav ? Colors.red : Colors.grey, size: 20),
      ),
    );
  }
}

class FavoritesList extends StatelessWidget {
  final List<String> Function(dynamic) parseList;
  final Map favorites;
  final Function(String, bool) onFavToggle;

  const FavoritesList({super.key, required this.parseList, required this.favorites, required this.onFavToggle});

  @override
  Widget build(BuildContext context) {
    if (favorites.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border_rounded, size: 60, color: Colors.grey),
            SizedBox(height: 16),
            Text("You haven't added any favorites yet.", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final propertiesQuery = FirebaseDatabase.instance.ref("properties");
    return StreamBuilder<DatabaseEvent>(
      stream: propertiesQuery.onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) return const SizedBox();

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
                  child: firstImage != null ? Image.network(firstImage, width: 60, height: 60, fit: BoxFit.cover) : Container(width: 60, height: 60, color: Colors.grey[200]),
                ),
                title: Text(property['name'] ?? 'Resort', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(property['type'] ?? ''),
                trailing: IconButton(
                  icon: const Icon(Icons.favorite, color: Colors.red),
                  onPressed: () => onFavToggle(property['uid'], true),
                ),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => PropertyDetailsPage(propertyName: property['name'] ?? 'Resort', propertyData: property, ownerUid: property['uid']))),
              ),
            );
          },
        );
      },
    );
  }
}
