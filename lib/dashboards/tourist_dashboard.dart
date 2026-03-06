import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:intl/intl.dart';
import '../profile_page.dart';

class TouristDashboard extends StatefulWidget {
  const TouristDashboard({super.key});

  @override
  State<TouristDashboard> createState() => _TouristDashboardState();
}

class _TouristDashboardState extends State<TouristDashboard> {
  String _selectedCategory = 'All';

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
              child: const Text('Logout', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userRef = FirebaseDatabase.instance.ref("users/${user?.uid}");
    final propertiesRef = FirebaseDatabase.instance.ref("properties");
    final myBookingsQuery = FirebaseDatabase.instance.ref("bookings").orderByChild("touristUid").equalTo(user?.uid);

    return StreamBuilder<DatabaseEvent>(
      stream: userRef.onValue,
      builder: (context, snapshot) {
        String firstName = "Tourist";
        if (snapshot.hasData && snapshot.data!.snapshot.exists) {
          Map data = snapshot.data!.snapshot.value as Map;
          firstName = data['firstName'] ?? "Tourist";
        }

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            backgroundColor: Colors.grey[50],
            appBar: AppBar(
              elevation: 0,
              backgroundColor: Colors.white,
              title: Row(
                children: [
                  const Icon(Icons.beach_access, color: Colors.blue, size: 28),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Resort Connect',
                        style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Tourist: $firstName',
                        style: TextStyle(color: Colors.blue[700], fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.person_outline, color: Colors.blue),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ProfilePage()),
                  ),
                  tooltip: 'Edit Profile',
                ),
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(color: Colors.blue[50], shape: BoxShape.circle),
                  child: IconButton(
                    icon: const Icon(Icons.logout_rounded, color: Colors.blue),
                    onPressed: () => _showLogoutDialog(context),
                  ),
                ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Discover'),
                  Tab(text: 'My Bookings'),
                ],
                labelColor: Colors.blue,
                indicatorColor: Colors.blue,
              ),
            ),
            body: TabBarView(
              children: [
                // Tab 1: Discover
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hello, $firstName! 👋', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          const Text('Explore beautiful destinations', style: TextStyle(fontSize: 16, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                      child: Row(
                        children: [
                          _buildCategoryChip('All'),
                          const SizedBox(width: 8),
                          _buildCategoryChip('Resort'),
                          const SizedBox(width: 8),
                          _buildCategoryChip('Hotel'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: FirebaseAnimatedList(
                        query: propertiesRef,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        itemBuilder: (context, snapshot, animation, index) {
                          Map prop = snapshot.value as Map;
                          String type = prop['type'] ?? 'Resort';
                          String ownerUid = prop['ownerUid'] ?? '';
                          if (_selectedCategory != 'All' && type != _selectedCategory) return const SizedBox.shrink();
                          return SizeTransition(sizeFactor: animation, child: _buildPropertyCard(prop, ownerUid));
                        },
                      ),
                    ),
                  ],
                ),
                // Tab 2: My Bookings
                FirebaseAnimatedList(
                  query: myBookingsQuery,
                  padding: const EdgeInsets.all(20),
                  itemBuilder: (context, snapshot, animation, index) {
                    Map booking = snapshot.value as Map;
                    return SizeTransition(sizeFactor: animation, child: _buildMyBookingCard(booking));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMyBookingCard(Map booking) {
    Color statusColor = Colors.orange;
    if (booking['status'] == 'Confirmed') statusColor = Colors.green;
    if (booking['status'] == 'Cancelled') statusColor = Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(booking['propertyName'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(booking['status'], style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Activity: ${booking['activityTitle']}', style: const TextStyle(fontSize: 14)),
            Text('Date: ${booking['bookingDate']} at ${booking['bookingTime']}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
            const Divider(),
            Text('Total: ₱${booking['price']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String label) {
    bool isSelected = _selectedCategory == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey[300]!),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildPropertyCard(Map prop, String ownerUid) {
    String type = prop['type'] ?? 'Resort';
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(prop['name'] ?? 'Unnamed', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                    _buildBadge(type, type == 'Resort' ? Colors.blue : Colors.orange),
                  ],
                ),
                const SizedBox(height: 8),
                Text(prop['description'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildIconInfo(Icons.meeting_room, '${prop['rooms']} Rooms'),
                    const SizedBox(width: 16),
                    _buildIconInfo(Icons.badge, '${prop['staffCount']} Staff'),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.grey[50], borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(25), bottomRight: Radius.circular(25))),
            child: ElevatedButton(
              onPressed: () => _showOffersDialog(prop['name'], ownerUid),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              child: const Text('View Available Activities & Offers'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _buildIconInfo(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  void _showOffersDialog(String propertyName, String ownerUid) {
    final activitiesRef = FirebaseDatabase.instance.ref("activities/$ownerUid");
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text('Offers from $propertyName', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: FirebaseAnimatedList(
                query: activitiesRef,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemBuilder: (context, snapshot, animation, index) {
                  Map act = snapshot.value as Map;
                  String activityId = snapshot.key!;
                  return InkWell(
                    onTap: () => _checkAndStartBooking(propertyName, ownerUid, activityId, act),
                    child: _buildActivityTile(act),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkAndStartBooking(String propertyName, String ownerUid, String activityId, Map activity) async {
    final user = FirebaseAuth.instance.currentUser;
    final existingBookingCheck = await FirebaseDatabase.instance.ref("bookings").orderByChild("touristUid").equalTo(user?.uid).get();
    if (existingBookingCheck.exists) {
      Map bookings = existingBookingCheck.value as Map;
      bool alreadyBooked = bookings.values.any((b) => b['activityId'] == activityId && (b['status'] == 'Pending' || b['status'] == 'Confirmed'));
      if (alreadyBooked) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You already have an active booking for this activity!'), backgroundColor: Colors.orange));
        return;
      }
    }
    _selectBookingDetails(propertyName, ownerUid, activityId, activity);
  }

  Future<void> _selectBookingDetails(String propertyName, String ownerUid, String activityId, Map activity) async {
    DateTime? selectedDate = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (selectedDate == null) return;
    if (!mounted) return;
    TimeOfDay? selectedTime = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (selectedTime == null) return;
    if (!mounted) return;
    _confirmBooking(propertyName, ownerUid, activityId, activity, selectedDate, selectedTime);
  }

  void _confirmBooking(String propertyName, String ownerUid, String activityId, Map activity, DateTime date, TimeOfDay time) {
    final dateStr = DateFormat('MMM dd, yyyy').format(date);
    final timeStr = time.format(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Activity: ${activity['title']}'),
            Text('Place: $propertyName'),
            Text('Price: ₱${activity['price']}'),
            const Divider(),
            Text('Date: $dateStr', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Time: $timeStr', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _processBooking(ownerUid, propertyName, activityId, activity, dateStr, timeStr);
            },
            child: const Text('Confirm Booking'),
          ),
        ],
      ),
    );
  }

  Future<void> _processBooking(String ownerUid, String propertyName, String activityId, Map activity, String date, String time) async {
    final user = FirebaseAuth.instance.currentUser;
    final bookingRef = FirebaseDatabase.instance.ref("bookings").push();
    final touristSnapshot = await FirebaseDatabase.instance.ref("users/${user?.uid}").get();
    String touristName = "Anonymous";
    if (touristSnapshot.exists) {
      Map data = touristSnapshot.value as Map;
      touristName = "${data['firstName']} ${data['lastName']}";
    }
    try {
      await bookingRef.set({
        'touristUid': user?.uid,
        'touristName': touristName,
        'ownerUid': ownerUid,
        'activityId': activityId,
        'propertyName': propertyName,
        'activityTitle': activity['title'],
        'price': activity['price'],
        'bookingDate': date,
        'bookingTime': time,
        'status': 'Pending',
        'timestamp': ServerValue.timestamp,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking request sent successfully!'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to book: $e'), backgroundColor: Colors.red));
    }
  }

  Widget _buildActivityTile(Map act) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(15)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(act['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(act['description'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₱${act['price']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 16)),
              const Text('Click to book', style: TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }
}
