import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:intl/intl.dart';
import '../profile_page.dart';
import '../property_details_page.dart';
import '../notifications_page.dart';

class TouristDashboard extends StatefulWidget {
  const TouristDashboard({super.key});

  @override
  State<TouristDashboard> createState() => _TouristDashboardState();
}

class _TouristDashboardState extends State<TouristDashboard> {
  late Stream<DatabaseEvent> _userStream;
  late Stream<DatabaseEvent> _notifStream;

  final Color _brand20 = const Color(0xFF2196F3);

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _userStream = FirebaseDatabase.instance.ref("users/${user?.uid}").onValue.asBroadcastStream();
    _notifStream = FirebaseDatabase.instance.ref("notifications/${user?.uid}").onValue.asBroadcastStream();
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                FirebaseAuth.instance.signOut();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Logout'),
            ),
          ],
        );
      },
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
              decoration: const InputDecoration(hintText: 'Reason...', border: OutlineInputBorder()),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, Cancel', style: TextStyle(color: Colors.red))),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking request cancelled.'), backgroundColor: Colors.orange));
    }
  }

  void _showReviewDialog(Map booking, String bookingId) {
    int rating = 5;
    final commentController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Rate your stay at ${booking['propertyName']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (index) => IconButton(icon: Icon(Icons.star_rounded, size: 32, color: index < rating ? Colors.amber : Colors.grey[300]), onPressed: () => setDialogState(() => rating = index + 1)))),
              const SizedBox(height: 16),
              TextField(controller: commentController, maxLines: 3, decoration: const InputDecoration(hintText: 'Share your experience...', border: OutlineInputBorder())),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final user = FirebaseAuth.instance.currentUser;
                await FirebaseDatabase.instance.ref("reviews/${booking['ownerUid']}").push().set({'touristUid': user?.uid, 'touristName': booking['touristName'], 'rating': rating, 'comment': commentController.text.trim(), 'timestamp': ServerValue.timestamp});
                await FirebaseDatabase.instance.ref("bookings/$bookingId").update({'isReviewed': true});
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Submit Review'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final myBookingsQuery = FirebaseDatabase.instance.ref("bookings").orderByChild("touristUid").equalTo(user?.uid);

    return StreamBuilder<DatabaseEvent>(
      stream: _userStream,
      builder: (context, snapshot) {
        String firstName = "Tourist";
        String? profilePic;
        if (snapshot.hasData && snapshot.data!.snapshot.exists) {
          Map data = snapshot.data!.snapshot.value as Map;
          firstName = data['firstName'] ?? "Tourist";
          profilePic = data['profilePicUrl'];
        }

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            backgroundColor: const Color(0xFFF8F9FA),
            appBar: AppBar(
              toolbarHeight: 80,
              elevation: 0,
              backgroundColor: Colors.white,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Resort Connect', style: TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  Text('Hello, $firstName!', style: TextStyle(color: _brand20, fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
              actions: [
                _appBarAction(Icons.notifications_none_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsPage()))),
                Padding(
                  padding: const EdgeInsets.only(right: 16, left: 8),
                  child: GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfilePage())),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: _brand20.withOpacity(0.1),
                      backgroundImage: profilePic != null ? NetworkImage(profilePic) : null,
                      child: profilePic == null ? Icon(Icons.person_outline_rounded, color: _brand20) : null,
                    ),
                  ),
                ),
                _appBarAction(Icons.logout_rounded, () => _showLogoutDialog(context), isLogout: true),
              ],
              bottom: TabBar(
                tabs: const [Tab(text: 'Partners'), Tab(text: 'My Bookings')],
                labelColor: _brand20,
                unselectedLabelColor: Colors.grey,
                indicatorColor: _brand20,
                indicatorWeight: 4,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            body: Container(
              decoration: const BoxDecoration(color: Color(0xFFF8F9FA)),
              child: TabBarView(
                children: [
                  PartnersList(firstName: firstName),
                  FirebaseAnimatedList(
                    query: myBookingsQuery,
                    padding: const EdgeInsets.all(20),
                    itemBuilder: (context, snapshot, animation, index) {
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
    decoration: BoxDecoration(color: isLogout ? Colors.red.withOpacity(0.05) : _brand20.withOpacity(0.05), shape: BoxShape.circle),
    child: IconButton(icon: Icon(icon, color: isLogout ? Colors.red : _brand20, size: 22), onPressed: onTap),
  );

  Widget _buildMyBookingCard(Map booking, String bookingId) {
    Color statusColor = const Color(0xFFFF8F00);
    if (booking['status'] == 'Confirmed') statusColor = Colors.green;
    if (booking['status'] == 'Cancelled') statusColor = Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: statusColor.withOpacity(0.05),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(booking['propertyName'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(30)),
                    child: Text(booking['status'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                  )
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(booking['activityTitle'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 14, color: Colors.grey[400]),
                      const SizedBox(width: 6),
                      Text(booking['bookingDate'], style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                      const SizedBox(width: 12),
                      Icon(Icons.access_time_rounded, size: 14, color: Colors.grey[400]),
                      const SizedBox(width: 6),
                      Text(booking['bookingTime'], style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                    ],
                  ),
                  if (booking['status'] == 'Cancelled' && booking['cancellationReason'] != null) ...[
                    const SizedBox(height: 8),
                    Text('Reason: ${booking['cancellationReason']}', style: const TextStyle(color: Colors.red, fontSize: 12, fontStyle: FontStyle.italic)),
                  ],
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Payment', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                      Text('₱${booking['totalPrice'] ?? booking['price']}', style: TextStyle(fontWeight: FontWeight.w900, color: _brand20, fontSize: 20)),
                    ],
                  ),
                  if (booking['status'] == 'Pending') ...[
                    const SizedBox(height: 16),
                    SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => _cancelBooking(bookingId), style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Cancel Request', style: TextStyle(fontWeight: FontWeight.bold)))),
                  ],
                  if (booking['status'] == 'Confirmed' && booking['isReviewed'] != true) ...[
                    const SizedBox(height: 16),
                    SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => _showReviewDialog(booking, bookingId), style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Rate & Review', style: TextStyle(fontWeight: FontWeight.bold)))),
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PartnersList extends StatefulWidget {
  final String firstName;
  const PartnersList({super.key, required this.firstName});

  @override
  State<PartnersList> createState() => _PartnersListState();
}

class _PartnersListState extends State<PartnersList> with AutomaticKeepAliveClientMixin {
  final Query _propertiesQuery = FirebaseDatabase.instance.ref("properties");

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Text('Featured Partners', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        ),
        Expanded(
          child: FirebaseAnimatedList(
            query: _propertiesQuery,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemBuilder: (context, snapshot, animation, index) {
              Map propData = snapshot.value as Map;
              String ownerUid = snapshot.key!;
              return FadeTransition(
                opacity: animation,
                child: _buildPartnerCard(propData['name'], propData, ownerUid),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPartnerCard(String name, Map? data, String ownerUid) {
    final Color brandColor = const Color(0xFF2196F3);
    bool isReg = data != null;
    final List imgs = data?['imageUrls'] != null ? (data!['imageUrls'] is List ? data['imageUrls'] : (data['imageUrls'] as Map).values.toList()) : [];
    String? firstImg = imgs.isNotEmpty ? imgs[0] : null;

    return GestureDetector(
      onTap: isReg 
        ? () => Navigator.push(context, MaterialPageRoute(builder: (context) => PropertyDetailsPage(propertyName: name, propertyData: data!, ownerUid: ownerUid)))
        : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 25, offset: const Offset(0, 12))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  child: firstImg != null 
                    ? Image.network(firstImg, height: 180, width: double.infinity, fit: BoxFit.cover)
                    : Container(height: 180, width: double.infinity, color: brandColor.withOpacity(0.1), child: Icon(Icons.beach_access_rounded, size: 50, color: brandColor)),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(20)),
                    child: Text(data?['type'] ?? 'Resort', style: TextStyle(color: brandColor, fontWeight: FontWeight.bold, fontSize: 11)),
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
                      Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.5))),
                      Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey[300], size: 16),
                    ],
                  ),
                  const SizedBox(height: 6),
                  StreamBuilder<DatabaseEvent>(
                    stream: FirebaseDatabase.instance.ref("reviews/$ownerUid").onValue,
                    builder: (context, snapshot) {
                      double avg = 0;
                      int count = 0;
                      if (snapshot.hasData && snapshot.data!.snapshot.exists) {
                        Map reviews = snapshot.data!.snapshot.value as Map;
                        count = reviews.length;
                        double total = 0;
                        reviews.forEach((k, v) => total += (v['rating'] ?? 0));
                        avg = total / count;
                      }
                      return Row(
                        children: [
                          Icon(Icons.star_rounded, color: Colors.amber[600], size: 18),
                          const SizedBox(width: 4),
                          Text(count > 0 ? avg.toStringAsFixed(1) : 'New', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(width: 4),
                          Text(count > 0 ? '($count reviews)' : '(No reviews yet)', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                        ],
                      );
                    }
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
