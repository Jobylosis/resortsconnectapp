import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:intl/intl.dart';
import 'chat_page.dart';

class PropertyDetailsPage extends StatefulWidget {
  final String propertyName;
  final Map propertyData;
  final String ownerUid;

  const PropertyDetailsPage({
    super.key,
    required this.propertyName,
    required this.propertyData,
    required this.ownerUid,
  });

  @override
  State<PropertyDetailsPage> createState() => _PropertyDetailsPageState();
}

class _PropertyDetailsPageState extends State<PropertyDetailsPage> {
  final Color _brand20 = const Color(0xFF2196F3);
  final Color _accent10 = const Color(0xFFFF8F00);

  Future<void> _checkAndStartBooking(String activityId, Map activity) async {
    final user = FirebaseAuth.instance.currentUser;
    final myBookingCheck = await FirebaseDatabase.instance.ref("bookings").orderByChild("touristUid").equalTo(user?.uid).get();
    if (myBookingCheck.exists) {
      Map bookings = myBookingCheck.value as Map;
      bool alreadyBookedByMe = bookings.values.any((b) => b['activityId'] == activityId && (b['status'] == 'Pending' || b['status'] == 'Confirmed'));
      if (alreadyBookedByMe) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You already have an active booking for this activity!'), backgroundColor: Colors.orange));
        return;
      }
    }
    _selectBookingDetails(activityId, activity);
  }

  Future<void> _selectBookingDetails(String activityId, Map activity) async {
    DateTime? selectedDate = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (selectedDate == null) return;
    if (!mounted) return;
    TimeOfDay? selectedTime = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (selectedTime == null) return;
    final dateStr = DateFormat('MMM dd, yyyy').format(selectedDate);
    final timeStr = selectedTime.format(context);
    final globalCheck = await FirebaseDatabase.instance.ref("bookings").orderByChild("ownerUid").equalTo(widget.ownerUid).get();
    if (globalCheck.exists) {
      Map allBookings = globalCheck.value as Map;
      bool isSlotTaken = allBookings.values.any((b) => b['activityId'] == activityId && b['bookingDate'] == dateStr && b['bookingTime'] == timeStr && (b['status'] == 'Pending' || b['status'] == 'Confirmed'));
      if (isSlotTaken) {
        if (!mounted) return;
        _showOverbookedDialog(activity['title'], dateStr, timeStr);
        return;
      }
    }
    if (!mounted) return;
    _confirmBooking(activityId, activity, selectedDate, selectedTime);
  }

  void _showOverbookedDialog(String title, String date, String time) {
    showDialog(context: context, builder: (context) => AlertDialog(title: const Text('Slot Unavailable'), content: Text('Sorry, "$title" is already reserved for $date at $time. Please choose another schedule.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
  }

  void _confirmBooking(String activityId, Map activity, DateTime date, TimeOfDay time) {
    final dateStr = DateFormat('MMM dd, yyyy').format(date);
    final timeStr = time.format(context);
    int nights = 1;
    double basePrice = double.tryParse(activity['price'].toString()) ?? 0;
    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
      double totalPrice = basePrice * nights;
      return AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: const Text('Confirm Booking'), content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Activity: ${activity['title']}', style: const TextStyle(fontWeight: FontWeight.bold)), Text('Rate per night: ₱${basePrice.toStringAsFixed(2)}'), const Divider(height: 24), const Text('Duration of Stay:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)), Row(mainAxisAlignment: MainAxisAlignment.center, children: [IconButton(onPressed: nights > 1 ? () => setDialogState(() => nights--) : null, icon: const Icon(Icons.remove_circle_outline, color: Colors.blue)), Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)), child: Text('$nights ${nights > 1 ? 'Nights' : 'Night'}', style: const TextStyle(fontWeight: FontWeight.bold))), IconButton(onPressed: () => setDialogState(() => nights++), icon: const Icon(Icons.add_circle_outline, color: Colors.blue))]), const Divider(height: 24), Row(children: [const Icon(Icons.calendar_today, size: 16, color: Colors.blue), const SizedBox(width: 8), Text(dateStr)]), const SizedBox(height: 8), Row(children: [const Icon(Icons.access_time, size: 16, color: Colors.blue), const SizedBox(width: 8), const Text('Check-in: '), Text(timeStr)]), const SizedBox(height: 16), Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Total Price:', style: TextStyle(fontWeight: FontWeight.bold)), Text('₱${totalPrice.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: _brand20, fontSize: 18))]))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () { Navigator.pop(context); _processBooking(activityId, activity, dateStr, timeStr, nights, totalPrice); }, style: ElevatedButton.styleFrom(backgroundColor: _brand20, foregroundColor: Colors.white), child: const Text('Book Now'))]);
    }));
  }

  Future<void> _processBooking(String activityId, Map activity, String date, String time, int nights, double totalPrice) async {
    final user = FirebaseAuth.instance.currentUser;
    final bookingRef = FirebaseDatabase.instance.ref("bookings").push();
    final touristSnapshot = await FirebaseDatabase.instance.ref("users/${user?.uid}").get();
    String touristName = "Anonymous";
    if (touristSnapshot.exists) {
      Map data = touristSnapshot.value as Map;
      touristName = "${data['firstName']} ${data['lastName']}";
    }
    try {
      await bookingRef.set({'touristUid': user?.uid, 'touristName': touristName, 'ownerUid': widget.ownerUid, 'activityId': activityId, 'propertyName': widget.propertyName, 'activityTitle': activity['title'], 'price': activity['price'], 'totalPrice': totalPrice, 'nights': nights, 'bookingDate': date, 'bookingTime': time, 'status': 'Pending', 'timestamp': ServerValue.timestamp});
      await FirebaseDatabase.instance.ref("notifications/${widget.ownerUid}").push().set({'title': 'New Booking Request', 'message': '$touristName booked "${activity['title']}" for $nights nights.', 'type': 'booking_new', 'isRead': false, 'timestamp': ServerValue.timestamp});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking request sent successfully!'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to book: $e'), backgroundColor: Colors.red)); }
  }

  @override
  Widget build(BuildContext context) {
    final activitiesRef = FirebaseDatabase.instance.ref("activities/${widget.ownerUid}");
    final List imageUrls = widget.propertyData['imageUrls'] ?? [];
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChatPage(otherUserUid: widget.ownerUid, otherUserName: widget.propertyName))),
        label: const Text('Chat with Owner'),
        icon: const Icon(Icons.chat_bubble_outline),
        backgroundColor: _brand20,
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(expandedHeight: 300, pinned: true, backgroundColor: _brand20, flexibleSpace: FlexibleSpaceBar(background: imageUrls.isNotEmpty ? PageView.builder(itemCount: imageUrls.length, itemBuilder: (context, index) => Image.network(imageUrls[index], fit: BoxFit.cover)) : Container(color: _brand20, child: const Icon(Icons.beach_access, size: 80, color: Colors.white)))),
          SliverToBoxAdapter(child: Container(decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))), child: Padding(padding: const EdgeInsets.all(24.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.propertyName, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)), const SizedBox(height: 12), Row(children: [_buildChip(widget.propertyData['type'], Colors.blue), const SizedBox(width: 8), _buildChip('${widget.propertyData['rooms']} Rooms', Colors.orange), const SizedBox(width: 8), _buildChip('${widget.propertyData['staffCount']} Staff', Colors.green)]), const SizedBox(height: 24), const Text('About this property', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(widget.propertyData['description'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 15, height: 1.5)), const SizedBox(height: 32), const Text('Offers & Services', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 16)])))),
          SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 24), sliver: StreamBuilder<DatabaseEvent>(stream: activitiesRef.onValue, builder: (context, snapshot) { if (!snapshot.hasData || snapshot.data!.snapshot.value == null) return const SliverToBoxAdapter(child: Center(child: Text("No offers available yet."))); Map activities = snapshot.data!.snapshot.value as Map; List<MapEntry> items = activities.entries.toList(); return SliverList(delegate: SliverChildBuilderDelegate((context, index) => _buildActivityTile(items[index].value as Map, items[index].key), childCount: items.length)); })),
          const SliverToBoxAdapter(child: SizedBox(height: 100)), // Space for FAB
        ],
      ),
    );
  }

  Widget _buildChip(String label, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)));

  Widget _buildActivityTile(Map act, String activityId) => Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(act['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)), const SizedBox(height: 4), Text(act['description'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 13))])), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('₱${act['price']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 18)), const SizedBox(height: 12), ElevatedButton(onPressed: () => _checkAndStartBooking(activityId, act), style: ElevatedButton.styleFrom(backgroundColor: _accent10, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('Book', style: TextStyle(fontWeight: FontWeight.bold)))])]));
}
