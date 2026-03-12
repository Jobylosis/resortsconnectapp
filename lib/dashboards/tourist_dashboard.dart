import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:provider/provider.dart';
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

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _userStream = FirebaseDatabase.instance.ref("users/${user?.uid}").onValue.asBroadcastStream();
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                FirebaseAuth.instance.signOut();
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent, foregroundColor: Colors.white),
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
          title: Text('Rate your stay at ${booking['propertyName']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (index) => IconButton(icon: Icon(Icons.star_rounded, size: 32, color: index < rating ? Colors.amber : Colors.grey[300]), onPressed: () => setDialogState(() => rating = index + 1)))),
              const SizedBox(height: 16),
              TextField(controller: commentController, maxLines: 3, decoration: const InputDecoration(hintText: 'Share your experience...')),
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
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryAccent, foregroundColor: Colors.black),
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
    final themeProvider = Provider.of<ThemeProvider>(context);
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
                      backgroundColor: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                      backgroundImage: profilePic != null ? NetworkImage(profilePic) : null,
                      child: profilePic == null ? Icon(Icons.person_outline_rounded, color: Theme.of(context).colorScheme.secondary) : null,
                    ),
                  ),
                ),
                _appBarAction(Icons.logout_rounded, () => _showLogoutDialog(context), isLogout: true),
              ],
              bottom: TabBar(
                tabs: const [Tab(text: 'Partners'), Tab(text: 'My Bookings')],
                labelColor: Theme.of(context).colorScheme.secondary,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Theme.of(context).colorScheme.secondary,
              ),
            ),
            body: TabBarView(
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
        );
      },
    );
  }

  Widget _appBarAction(IconData icon, VoidCallback onTap, {bool isLogout = false}) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(
      color: isLogout ? Colors.red.withOpacity(0.05) : Theme.of(context).colorScheme.secondary.withOpacity(0.05), 
      shape: BoxShape.circle
    ),
    child: IconButton(icon: Icon(icon, color: isLogout ? Colors.red : Theme.of(context).colorScheme.secondary, size: 22), onPressed: onTap),
  );

  Widget _buildMyBookingCard(Map booking, String bookingId) {
    Color statusColor = Colors.orange;
    if (booking['status'] == 'Confirmed') statusColor = Colors.green;
    if (booking['status'] == 'Cancelled') statusColor = AppTheme.primaryAccent;

    return Card(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: statusColor.withOpacity(0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(booking['propertyName'], style: Theme.of(context).textTheme.titleLarge),
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
                      const Icon(Icons.calendar_today_rounded, size: 14),
                      const SizedBox(width: 6),
                      Text(booking['bookingDate'], style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(width: 12),
                      const Icon(Icons.access_time_rounded, size: 14),
                      const SizedBox(width: 6),
                      Text(booking['bookingTime'], style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                  if (booking['status'] == 'Cancelled' && booking['cancellationReason'] != null) ...[
                    const SizedBox(height: 8),
                    Text('Reason: ${booking['cancellationReason']}', style: const TextStyle(color: AppTheme.primaryAccent, fontSize: 12, fontStyle: FontStyle.italic)),
                  ],
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Payment', style: TextStyle(fontWeight: FontWeight.w500)),
                      Text('₱${booking['totalPrice'] ?? booking['price']}', style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.secondary, fontSize: 20)),
                    ],
                  ),
                  if (booking['status'] == 'Pending') ...[
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => _cancelBooking(bookingId), 
                      style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primaryAccent, side: const BorderSide(color: AppTheme.primaryAccent)),
                      child: const Text('Cancel Request', style: TextStyle(fontWeight: FontWeight.bold))
                    ),
                  ],
                  if (booking['status'] == 'Confirmed' && booking['isReviewed'] != true) ...[
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _showReviewDialog(booking, bookingId), 
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                      child: const Text('Rate & Review', style: TextStyle(fontWeight: FontWeight.bold))
                    ),
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
    final Color secondaryColor = Theme.of(context).colorScheme.secondary;
    final List imgs = data?['imageUrls'] != null ? (data!['imageUrls'] is List ? data['imageUrls'] : (data['imageUrls'] as Map).values.toList()) : [];
    String? firstImg = imgs.isNotEmpty ? imgs[0] : null;

    return GestureDetector(
      onTap: data != null 
        ? () => Navigator.push(context, MaterialPageRoute(builder: (context) => PropertyDetailsPage(propertyName: name, propertyData: data, ownerUid: ownerUid)))
        : null,
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: firstImg != null 
                    ? Image.network(firstImg, height: 180, width: double.infinity, fit: BoxFit.cover)
                    : Container(height: 180, width: double.infinity, color: secondaryColor.withOpacity(0.1), child: Icon(Icons.beach_access_rounded, size: 50, color: secondaryColor)),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface.withOpacity(0.9), borderRadius: BorderRadius.circular(20)),
                    child: Text(data?['type'] ?? 'Resort', style: TextStyle(color: secondaryColor, fontWeight: FontWeight.bold, fontSize: 11)),
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
                      Expanded(child: Text(name, style: Theme.of(context).textTheme.titleLarge)),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 16),
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
                          Text(count > 0 ? '($count reviews)' : '(No reviews yet)', style: Theme.of(context).textTheme.bodyMedium),
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
