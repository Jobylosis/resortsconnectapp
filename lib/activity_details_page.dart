import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

class ActivityDetailsPage extends StatefulWidget {
  final String activityId;
  final Map activityData;
  final String ownerUid;
  final String propertyName;

  const ActivityDetailsPage({
    super.key,
    required this.activityId,
    required this.activityData,
    required this.ownerUid,
    required this.propertyName,
  });

  @override
  State<ActivityDetailsPage> createState() => _ActivityDetailsPageState();
}

class _ActivityDetailsPageState extends State<ActivityDetailsPage> {
  final Color _brand20 = const Color(0xFF2196F3);
  final Color _accent10 = const Color(0xFFFF8F00);
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _checkAndStartBooking() async {
    final user = FirebaseAuth.instance.currentUser;
    final myBookingCheck = await FirebaseDatabase.instance.ref("bookings").orderByChild("touristUid").equalTo(user?.uid).get();
    if (myBookingCheck.exists) {
      Map bookings = myBookingCheck.value as Map;
      bool alreadyBookedByMe = bookings.values.any((b) => b['activityId'] == widget.activityId && (b['status'] == 'Pending' || b['status'] == 'Confirmed'));
      if (alreadyBookedByMe) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You already have an active booking for this activity!'), backgroundColor: Colors.orange));
        return;
      }
    }
    _selectBookingDetails();
  }

  Future<void> _selectBookingDetails() async {
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
      bool isSlotTaken = allBookings.values.any((b) => b['activityId'] == widget.activityId && b['bookingDate'] == dateStr && b['bookingTime'] == timeStr && (b['status'] == 'Pending' || b['status'] == 'Confirmed'));
      if (isSlotTaken) {
        if (!mounted) return;
        _showOverbookedDialog(widget.activityData['title'], dateStr, timeStr);
        return;
      }
    }
    if (!mounted) return;
    _confirmBooking(selectedDate, selectedTime);
  }

  void _showOverbookedDialog(String title, String date, String time) {
    showDialog(context: context, builder: (context) => AlertDialog(title: const Text('Slot Unavailable'), content: Text('Sorry, "$title" is already reserved for $date at $time. Please choose another schedule.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
  }

  void _confirmBooking(DateTime date, TimeOfDay time) {
    final dateStr = DateFormat('MMM dd, yyyy').format(date);
    final timeStr = time.format(context);
    int nights = 1;
    double basePrice = double.tryParse(widget.activityData['price'].toString()) ?? 0;
    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
      double totalPrice = basePrice * nights;
      return AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: const Text('Confirm Booking'), content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Activity: ${widget.activityData['title']}', style: const TextStyle(fontWeight: FontWeight.bold)), Text('Rate per night: ₱${basePrice.toStringAsFixed(2)}'), const Divider(height: 24), const Text('Duration of Stay:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)), Row(mainAxisAlignment: MainAxisAlignment.center, children: [IconButton(onPressed: nights > 1 ? () => setDialogState(() => nights--) : null, icon: const Icon(Icons.remove_circle_outline, color: Colors.blue)), Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)), child: Text('$nights ${nights > 1 ? 'Nights' : 'Night'}', style: const TextStyle(fontWeight: FontWeight.bold))), IconButton(onPressed: () => setDialogState(() => nights++), icon: const Icon(Icons.add_circle_outline, color: Colors.blue))]), const Divider(height: 24), Row(children: [const Icon(Icons.calendar_today, size: 16, color: Colors.blue), const SizedBox(width: 8), Text(dateStr)]), const SizedBox(height: 8), Row(children: [const Icon(Icons.access_time, size: 16, color: Colors.blue), const SizedBox(width: 8), const Text('Check-in: '), Text(timeStr)]), const SizedBox(height: 16), Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Total Price:', style: TextStyle(fontWeight: FontWeight.bold)), Text('₱${totalPrice.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: _brand20, fontSize: 18))]))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () { Navigator.pop(context); _processBooking(dateStr, timeStr, nights, totalPrice); }, style: ElevatedButton.styleFrom(backgroundColor: _brand20, foregroundColor: Colors.white), child: const Text('Book Now'))]);
    }));
  }

  Future<void> _processBooking(String date, String time, int nights, double totalPrice) async {
    final user = FirebaseAuth.instance.currentUser;
    final bookingRef = FirebaseDatabase.instance.ref("bookings").push();
    final touristSnapshot = await FirebaseDatabase.instance.ref("users/${user?.uid}").get();
    String touristName = "Anonymous";
    if (touristSnapshot.exists) {
      Map data = touristSnapshot.value as Map;
      touristName = "${data['firstName']} ${data['lastName']}";
    }
    try {
      await bookingRef.set({'touristUid': user?.uid, 'touristName': touristName, 'ownerUid': widget.ownerUid, 'activityId': widget.activityId, 'propertyName': widget.propertyName, 'activityTitle': widget.activityData['title'], 'price': widget.activityData['price'], 'totalPrice': totalPrice, 'nights': nights, 'bookingDate': date, 'bookingTime': time, 'status': 'Pending', 'timestamp': ServerValue.timestamp});
      await FirebaseDatabase.instance.ref("notifications/${widget.ownerUid}").push().set({'title': 'New Booking Request', 'message': '$touristName booked "${widget.activityData['title']}" for $nights nights.', 'type': 'booking_new', 'isRead': false, 'timestamp': ServerValue.timestamp});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking request sent successfully!'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to book: $e'), backgroundColor: Colors.red)); }
  }

  @override
  Widget build(BuildContext context) {
    final List imageUrls = widget.activityData['imageUrls'] ?? [];
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300, 
            pinned: true, 
            backgroundColor: _brand20, 
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  PageView.builder(
                    controller: _pageController,
                    itemCount: imageUrls.isNotEmpty ? imageUrls.length : 1,
                    onPageChanged: (index) => setState(() => _currentPage = index),
                    itemBuilder: (context, index) {
                      if (imageUrls.isEmpty) {
                        return Container(color: _brand20, child: const Icon(Icons.local_activity, size: 80, color: Colors.white));
                      }
                      return Image.network(imageUrls[index], fit: BoxFit.cover, errorBuilder: (c, e, s) => const Center(child: Icon(Icons.error, color: Colors.white)));
                    },
                  ),
                  if (imageUrls.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(imageUrls.length, (index) => 
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 8,
                            width: _currentPage == index ? 24 : 8,
                            decoration: BoxDecoration(
                              color: _currentPage == index ? Colors.white : Colors.white54,
                              borderRadius: BorderRadius.circular(12)
                            ),
                          )
                        ),
                      ),
                    )
                ],
              ),
            )
          ),
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))), 
              child: Padding(
                padding: const EdgeInsets.all(24.0), 
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  children: [
                    Text(widget.activityData['title'], style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Offered by: ${widget.propertyName}', style: TextStyle(color: _brand20, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 24),
                    const Text('About this offer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(widget.activityData['description'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 15, height: 1.5)),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey[200]!)
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Rate per night', style: TextStyle(color: Colors.grey, fontSize: 13)),
                              Text('₱${widget.activityData['price']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
                            ],
                          ),
                          ElevatedButton(
                            onPressed: _checkAndStartBooking,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accent10,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                            ),
                            child: const Text('Avail Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          )
                        ],
                      ),
                    )
                  ]
                )
              )
            )
          ),
        ],
      ),
    );
  }
}
