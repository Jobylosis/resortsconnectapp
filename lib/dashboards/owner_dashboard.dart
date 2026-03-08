import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../profile_page.dart';
import '../notifications_page.dart';
import '../chat_page.dart';

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  final _profileFormKey = GlobalKey<FormState>();
  final _activityFormKey = GlobalKey<FormState>();

  final _propNameController = TextEditingController();
  final _propDescController = TextEditingController();
  final _roomsController = TextEditingController();
  final _staffController = TextEditingController();
  String _propertyType = 'Resort';
  List<String> _imageUrls = [];

  final _activityNameController = TextEditingController();
  final _activityDescController = TextEditingController();
  final _activityPriceController = TextEditingController();

  bool _isSubmitting = false;
  String? _editingActivityKey;
  late Stream<DatabaseEvent> _notifStream;

  final Color _bg70 = const Color(0xFFF8F9FA); 
  final Color _brand20 = const Color(0xFF00796B); 
  final Color _accent10 = const Color(0xFFFF8F00); 

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _notifStream = FirebaseDatabase.instance.ref("notifications/${user?.uid}").onValue;
  }

  @override
  void dispose() {
    _propNameController.dispose();
    _propDescController.dispose();
    _roomsController.dispose();
    _staffController.dispose();
    _activityNameController.dispose();
    _activityDescController.dispose();
    _activityPriceController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImages() async {
    final picker = ImagePicker();
    final List<XFile> pickedFiles = await picker.pickMultiImage(imageQuality: 70);

    if (pickedFiles.isNotEmpty) {
      if (_imageUrls.length + pickedFiles.length > 5) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Limit: 5 images.')));
        return;
      }
      setState(() => _isSubmitting = true);
      for (var file in pickedFiles) {
        try {
          final request = http.MultipartRequest('POST', Uri.parse('https://api.imgbb.com/1/upload?key=bbe2a79d18422542881211147631b619'));
          request.files.add(await http.MultipartFile.fromPath('image', file.path));
          final response = await request.send();
          if (response.statusCode == 200) {
            final responseData = await response.stream.bytesToString();
            final json = jsonDecode(responseData);
            setState(() => _imageUrls.add(json['data']['url']));
          }
        } catch (e) { print(e); }
      }
      setState(() => _isSubmitting = false);
    }
  }

  void _removeImage(int index) => setState(() => _imageUrls.removeAt(index));

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () { Navigator.pop(context); FirebaseAuth.instance.signOut(); }, child: const Text('Logout', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;
    if (_imageUrls.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a photo.'))); return; }
    setState(() => _isSubmitting = true);
    final user = FirebaseAuth.instance.currentUser;
    try {
      await FirebaseDatabase.instance.ref("properties/${user?.uid}").set({
        'name': _propNameController.text.trim(),
        'description': _propDescController.text.trim(),
        'type': _propertyType,
        'rooms': int.tryParse(_roomsController.text) ?? 0,
        'staffCount': int.tryParse(_staffController.text) ?? 0,
        'imageUrls': _imageUrls,
        'ownerUid': user?.uid,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) { print(e); } finally { if (mounted) setState(() => _isSubmitting = false); }
  }

  Future<void> _submitActivity() async {
    if (!_activityFormKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    final user = FirebaseAuth.instance.currentUser;
    try {
      DatabaseReference ref = _editingActivityKey != null 
          ? FirebaseDatabase.instance.ref("activities/${user?.uid}/$_editingActivityKey")
          : FirebaseDatabase.instance.ref("activities/${user?.uid}").push();
      await ref.set({
        'title': _activityNameController.text.trim(),
        'description': _activityDescController.text.trim(),
        'price': _activityPriceController.text.trim(),
        'timestamp': ServerValue.timestamp,
      });
      _clearActivityForm();
      Navigator.pop(context);
    } catch (e) { print(e); } finally { if (mounted) setState(() => _isSubmitting = false); }
  }

  void _clearActivityForm() {
    _activityNameController.clear();
    _activityDescController.clear();
    _activityPriceController.clear();
    _editingActivityKey = null;
  }

  Future<void> _deleteActivity(String key) async {
    final user = FirebaseAuth.instance.currentUser;
    await FirebaseDatabase.instance.ref("activities/${user?.uid}/$key").remove();
  }

  Future<void> _updateBookingStatus(String bookingKey, String status, Map booking) async {
    await FirebaseDatabase.instance.ref("bookings/$bookingKey").update({'status': status});
    await FirebaseDatabase.instance.ref("notifications/${booking['touristUid']}").push().set({
      'title': 'Booking Updated',
      'message': 'Your booking for "${booking['activityTitle']}" is $status.',
      'type': status == 'Confirmed' ? 'booking_accepted' : 'booking_rejected',
      'isRead': false,
      'timestamp': ServerValue.timestamp,
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final propRef = FirebaseDatabase.instance.ref("properties/${user?.uid}");
    final bookingsRef = FirebaseDatabase.instance.ref("bookings").orderByChild("ownerUid").equalTo(user?.uid);

    return StreamBuilder<DatabaseEvent>(
      stream: propRef.onValue,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (!snapshot.hasData || !snapshot.data!.snapshot.exists) return _buildProfileSetupScreen();
        Map propData = snapshot.data!.snapshot.value as Map;
        
        return StreamBuilder<DatabaseEvent>(
          stream: bookingsRef.onValue,
          builder: (context, bSnapshot) {
            double totalRevenue = 0;
            if (bSnapshot.hasData && bSnapshot.data!.snapshot.exists) {
              Map bookings = bSnapshot.data!.snapshot.value as Map;
              bookings.forEach((key, value) {
                if (value['status'] == 'Confirmed') {
                  totalRevenue += double.tryParse(value['totalPrice'].toString()) ?? 
                                 double.tryParse(value['price'].toString()) ?? 0;
                }
              });
            }
            return _buildMainDashboard(propData, totalRevenue);
          }
        );
      },
    );
  }

  Widget _buildProfileSetupScreen() {
    return Scaffold(
      backgroundColor: _bg70,
      appBar: AppBar(title: const Text('Setup Business'), centerTitle: true, elevation: 0, backgroundColor: Colors.white, foregroundColor: _brand20),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _profileFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Add 1-5 photos', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _imageUrls.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _imageUrls.length) return GestureDetector(onTap: _pickAndUploadImages, child: Container(width: 100, margin: const EdgeInsets.only(right: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: _brand20.withOpacity(0.3))), child: Icon(Icons.add_a_photo, color: _brand20)));
                    return Stack(children: [Container(width: 100, margin: const EdgeInsets.only(right: 12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), image: DecorationImage(image: NetworkImage(_imageUrls[index]), fit: BoxFit.cover))), Positioned(top: 5, right: 17, child: GestureDetector(onTap: () => _removeImage(index), child: const CircleAvatar(radius: 10, backgroundColor: Colors.red, child: Icon(Icons.close, size: 12, color: Colors.white))))]);
                  },
                ),
              ),
              const SizedBox(height: 24),
              SegmentedButton<String>(segments: const [ButtonSegment(value: 'Resort', label: Text('Resort')), ButtonSegment(value: 'Hotel', label: Text('Hotel'))], selected: {_propertyType}, onSelectionChanged: (s) => setState(() => _propertyType = s.first)),
              const SizedBox(height: 16),
              _buildTextField(_propNameController, 'Name', Icons.business),
              const SizedBox(height: 16),
              _buildTextField(_propDescController, 'Description', Icons.description, maxLines: 3),
              const SizedBox(height: 16),
              Row(children: [Expanded(child: _buildTextField(_roomsController, 'Rooms', Icons.room, keyboardType: TextInputType.number)), const SizedBox(width: 16), Expanded(child: _buildTextField(_staffController, 'Staff', Icons.groups, keyboardType: TextInputType.number))]),
              const SizedBox(height: 32),
              ElevatedButton(onPressed: _isSubmitting ? null : _saveProfile, style: ElevatedButton.styleFrom(backgroundColor: _accent10, foregroundColor: Colors.white, padding: const EdgeInsets.all(16)), child: const Text('Complete Setup')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainDashboard(Map propData, double totalRevenue) {
    final user = FirebaseAuth.instance.currentUser;
    final activityQuery = FirebaseDatabase.instance.ref("activities/${user?.uid}");
    final bookingsQuery = FirebaseDatabase.instance.ref("bookings").orderByChild("ownerUid").equalTo(user?.uid);
    String? firstImg = (propData['imageUrls'] != null && (propData['imageUrls'] as List).isNotEmpty) ? propData['imageUrls'][0] : null;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _bg70,
        appBar: AppBar(
          elevation: 0, backgroundColor: Colors.white,
          title: Row(children: [CircleAvatar(backgroundImage: firstImg != null ? NetworkImage(firstImg) : null, child: firstImg == null ? const Icon(Icons.business) : null), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(propData['name'], style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)), Text(propData['type'], style: TextStyle(color: _brand20, fontSize: 10))])]),
          actions: [
            StreamBuilder<DatabaseEvent>(
              stream: _notifStream,
              builder: (context, snapshot) {
                int unreadCount = 0;
                if (snapshot.hasData && snapshot.data!.snapshot.exists) {
                  Map notifs = snapshot.data!.snapshot.value as Map;
                  unreadCount = notifs.values.where((n) => n['isRead'] == false).length;
                }
                return Stack(
                  children: [
                    IconButton(
                      icon: Icon(Icons.notifications_none, color: _brand20), 
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsPage()))
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(
                            '$unreadCount',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              }
            ),
            IconButton(icon: Icon(Icons.person_outline, color: _brand20), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfilePage()))),
            IconButton(icon: Icon(Icons.logout, color: _brand20), onPressed: () => _showLogoutDialog(context))
          ],
          bottom: TabBar(tabs: const [Tab(text: 'Activities'), Tab(text: 'Bookings')], labelColor: _brand20, indicatorColor: _brand20),
        ),
        body: TabBarView(
          children: [
            ListView(padding: const EdgeInsets.symmetric(vertical: 16), children: [
              Container(margin: const EdgeInsets.symmetric(horizontal: 20), padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_buildStatItem('Rooms', propData['rooms'].toString(), Icons.meeting_room), _buildStatItem('Staff', propData['staffCount'].toString(), Icons.badge), _buildStatItem('Revenue', '₱${totalRevenue.toStringAsFixed(0)}', Icons.payments)])),
              const SizedBox(height: 24),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Offers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), FilledButton.icon(onPressed: () { _clearActivityForm(); _showActivitySheet(); }, icon: const Icon(Icons.add, size: 18), label: const Text('Add New'), style: FilledButton.styleFrom(backgroundColor: _brand20))])),
              FirebaseAnimatedList(query: activityQuery, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.all(20), itemBuilder: (context, snapshot, animation, index) => _buildActivityCard(snapshot.value as Map, snapshot.key!)),
            ]),
            FirebaseAnimatedList(query: bookingsQuery, padding: const EdgeInsets.all(20), itemBuilder: (context, snapshot, animation, index) => _buildBookingCard(snapshot.value as Map, snapshot.key!)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) => Column(children: [Icon(icon, color: _brand20, size: 20), const SizedBox(height: 6), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11))]);

  Widget _buildActivityCard(Map act, String key) => Card(margin: const EdgeInsets.only(bottom: 12), child: ListTile(title: Text(act['title'], style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('₱${act['price']} • ${act['description']}'), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () { _activityNameController.text = act['title']; _activityDescController.text = act['description']; _activityPriceController.text = act['price'].toString(); _editingActivityKey = key; _showActivitySheet(); }), IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteActivity(key))])));

  Widget _buildBookingCard(Map booking, String key) {
    Color color = booking['status'] == 'Confirmed' ? Colors.green : (booking['status'] == 'Cancelled' ? Colors.red : Colors.orange);
    int nights = booking['nights'] ?? 1;
    double totalPrice = double.tryParse(booking['totalPrice']?.toString() ?? '') ?? 
                        double.tryParse(booking['price']?.toString() ?? '') ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 16), 
      child: Column(
        children: [
          ListTile(
            title: Text(booking['touristName'], style: const TextStyle(fontWeight: FontWeight.bold)), 
            subtitle: Text(booking['activityTitle']), 
            trailing: Text(booking['status'], style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ), 
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 14, color: Colors.grey), 
                const SizedBox(width: 6), 
                Text('${booking['bookingDate']} • $nights ${nights > 1 ? 'nights' : 'night'}', style: const TextStyle(fontSize: 12)), 
                const Spacer(), 
                Text('Total: ₱${totalPrice.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, color: _brand20)),
              ]
            )
          ), 
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline, color: Colors.blue), 
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChatPage(otherUserUid: booking['touristUid'], otherUserName: booking['touristName'])))
                ),
                const Spacer(),
                if (booking['status'] == 'Pending') ...[
                  TextButton(onPressed: () => _updateBookingStatus(key, 'Cancelled', booking), child: const Text('Decline', style: TextStyle(color: Colors.red))),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: () => _updateBookingStatus(key, 'Confirmed', booking), style: ElevatedButton.styleFrom(backgroundColor: _brand20, foregroundColor: Colors.white), child: const Text('Confirm')),
                ]
              ],
            ),
          )
        ]
      )
    );
  }

  void _showActivitySheet() {
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (context) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24), child: Form(key: _activityFormKey, child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_editingActivityKey != null ? 'Edit' : 'New'), const SizedBox(height: 20), _buildTextField(_activityNameController, 'Title', Icons.local_activity), const SizedBox(height: 12), _buildTextField(_activityDescController, 'Details', Icons.notes, maxLines: 2), const SizedBox(height: 12), _buildTextField(_activityPriceController, 'Price', Icons.payments, keyboardType: TextInputType.number), const SizedBox(height: 24), ElevatedButton(onPressed: _submitActivity, style: ElevatedButton.styleFrom(backgroundColor: _brand20, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)), child: const Text('Save')), const SizedBox(height: 24)]))));
  }

  Widget _buildTextField(TextEditingController c, String l, IconData i, {int maxLines = 1, TextInputType keyboardType = TextInputType.text}) => TextFormField(controller: c, maxLines: maxLines, keyboardType: keyboardType, decoration: InputDecoration(labelText: l, prefixIcon: Icon(i, color: _brand20), border: const OutlineInputBorder()));
}
