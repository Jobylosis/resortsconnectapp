import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';
import '../profile_page.dart';
import '../notifications_page.dart';
import '../chat_page.dart';
import '../property_details_page.dart';

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  final String _cloudName = "dnv6ezitm"; 
  final String _uploadPreset = "resort_unsigned"; 

  final _profileFormKey = GlobalKey<FormState>();
  final _activityFormKey = GlobalKey<FormState>();

  final _propNameController = TextEditingController();
  final _propDescController = TextEditingController();
  final _roomsController = TextEditingController();
  final _staffController = TextEditingController();
  final _gcashNumberController = TextEditingController();
  final _gcashNameController = TextEditingController();
  String _propertyType = 'Resort';
  List<String> _imageUrls = [];
  List<String> _propVideoUrls = [];

  final _activityNameController = TextEditingController();
  final _activityDescController = TextEditingController();
  final _activityPriceController = TextEditingController();
  List<String> _activityImageUrls = [];
  String? _activityVideoUrl;

  bool _isSubmitting = false;
  String? _editingActivityKey;
  late Stream<DatabaseEvent> _notifStream;

  final Color _brandPrimary = const Color(0xFF00796B); 
  final Color _accentColor = const Color(0xFFFF8F00); 

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _notifStream = FirebaseDatabase.instance.ref("notifications/${user?.uid}").onValue.asBroadcastStream();
  }

  @override
  void dispose() {
    _propNameController.dispose();
    _propDescController.dispose();
    _roomsController.dispose();
    _staffController.dispose();
    _gcashNumberController.dispose();
    _gcashNameController.dispose();
    _activityNameController.dispose();
    _activityDescController.dispose();
    _activityPriceController.dispose();
    super.dispose();
  }

  List<String> _parseList(dynamic data) {
    if (data == null) return [];
    if (data is List) return data.map((e) => e.toString()).toList();
    if (data is Map) {
      var sortedKeys = data.keys.toList()..sort((a, b) => a.toString().compareTo(b.toString()));
      return sortedKeys.map((k) => data[k].toString()).toList();
    }
    return [];
  }

  Future<String?> _uploadToCloudinary(File file, {bool isVideo = false}) async {
    try {
      final String resourceType = isVideo ? "video" : "image";
      final url = Uri.parse("https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/upload");
      final request = http.MultipartRequest("POST", url)
        ..fields['upload_preset'] = _uploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', file.path));
      final response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        return jsonDecode(responseData)['secure_url'];
      }
      return null;
    } catch (e) { return null; }
  }

  Future<void> _pickAndUploadImages({bool isActivity = false}) async {
    final picker = ImagePicker();
    final List<XFile> pickedFiles = await picker.pickMultiImage(imageQuality: 70);
    if (pickedFiles.isNotEmpty) {
      setState(() => _isSubmitting = true);
      for (var file in pickedFiles) {
        final url = await _uploadToCloudinary(File(file.path));
        if (url != null) {
          setState(() { if (isActivity) _activityImageUrls.add(url); else _imageUrls.add(url); });
        }
      }
      setState(() => _isSubmitting = false);
    }
  }

  Future<void> _pickAndUploadVideo({bool isActivity = false}) async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickVideo(source: ImageSource.gallery);
    if (file != null) {
      setState(() => _isSubmitting = true);
      final url = await _uploadToCloudinary(File(file.path), isVideo: true);
      if (url != null) {
        setState(() { if (isActivity) _activityVideoUrl = url; else _propVideoUrls.add(url); });
      }
      setState(() => _isSubmitting = false);
    }
  }

  void _removeImage(int index, {bool isActivity = false}) {
    setState(() { if (isActivity) _activityImageUrls.removeAt(index); else _imageUrls.removeAt(index); });
  }

  String _decryptMessage(String encryptedBase64, String touristUid) {
    try {
      final currentUid = FirebaseAuth.instance.currentUser!.uid;
      List<String> ids = [currentUid, touristUid]; ids.sort();
      String chatId = ids.join("_");
      final keyBytes = sha256.convert(utf8.encode(chatId)).bytes;
      final key = encrypt.Key(Uint8List.fromList(keyBytes));
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final ivBytes = md5.convert(utf8.encode(chatId.split('').reversed.join())).bytes;
      final iv = encrypt.IV(Uint8List.fromList(ivBytes));
      return encrypter.decrypt64(encryptedBase64, iv: iv);
    } catch (e) { return "[Encrypted Message]"; }
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: const Text('Logout?'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), TextButton(onPressed: () { Navigator.pop(context); FirebaseAuth.instance.signOut(); }, child: const Text('Logout', style: TextStyle(color: Colors.red)))],));
  }

  void _showResetRevenueDialog() {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reset All Data?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your password to reset all bookings and revenue data.'),
            const SizedBox(height: 16),
            TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final user = FirebaseAuth.instance.currentUser;
              if (user == null || user.email == null) return;
              final cred = EmailAuthProvider.credential(email: user.email!, password: passwordController.text);
              try {
                await user.reauthenticateWithCredential(cred);
                await FirebaseDatabase.instance.ref("bookings").orderByChild("ownerUid").equalTo(user.uid).get().then((snap) {
                  if (snap.exists) {
                    Map bookings = snap.value as Map;
                    bookings.forEach((k, v) => FirebaseDatabase.instance.ref("bookings/$k").remove());
                  }
                });
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Revenue reset.'), backgroundColor: Colors.green));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification failed. Wrong password.'), backgroundColor: Colors.red));
              }
            }, 
            child: const Text('Confirm & Reset', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;
    if (_imageUrls.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one photo.'))); return; }
    setState(() => _isSubmitting = true);
    final user = FirebaseAuth.instance.currentUser;
    try {
      await FirebaseDatabase.instance.ref("properties/${user?.uid}").set({
        'name': _propNameController.text.trim(),
        'description': _propDescController.text.trim(),
        'type': _propertyType,
        'rooms': int.tryParse(_roomsController.text) ?? 0,
        'staffCount': int.tryParse(_staffController.text) ?? 0,
        'gcashNumber': _gcashNumberController.text.trim(),
        'gcashName': _gcashNameController.text.trim(),
        'imageUrls': _imageUrls,
        'videoUrls': _propVideoUrls,
        'ownerUid': user?.uid,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) { } finally { if (mounted) setState(() => _isSubmitting = false); }
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
        'imageUrls': _activityImageUrls,
        'videoUrl': _activityVideoUrl,
        'timestamp': ServerValue.timestamp,
      });
      _clearActivityForm();
      Navigator.pop(context);
    } catch (e) { } finally { if (mounted) setState(() => _isSubmitting = false); }
  }

  void _clearActivityForm() {
    _activityNameController.clear();
    _activityDescController.clear();
    _activityPriceController.clear();
    _activityImageUrls = [];
    _activityVideoUrl = null;
    _editingActivityKey = null;
  }

  void _updateBookingStatus(String key, String status, Map booking) async {
    await FirebaseDatabase.instance.ref("bookings/$key").update({'status': status});
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
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(title: const Text('Business Setup'), centerTitle: true, elevation: 0, backgroundColor: Colors.white, foregroundColor: _brandPrimary),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _profileFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Showcase with Photos & Video', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _imageUrls.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _imageUrls.length) return GestureDetector(onTap: () => _pickAndUploadImages(), child: Container(width: 100, margin: const EdgeInsets.only(right: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: _brandPrimary.withOpacity(0.3))), child: Icon(Icons.add_a_photo, color: _brandPrimary)));
                    return Stack(children: [Container(width: 100, margin: const EdgeInsets.only(right: 12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), image: DecorationImage(image: NetworkImage(_imageUrls[index]), fit: BoxFit.cover))), Positioned(top: 5, right: 17, child: GestureDetector(onTap: () => _removeImage(index), child: const CircleAvatar(radius: 10, backgroundColor: Colors.red, child: Icon(Icons.close, size: 12, color: Colors.white))))]);
                  },
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: () => _pickAndUploadVideo(), icon: Icon(Icons.video_call, color: _brandPrimary), label: Text(_propVideoUrls.isNotEmpty ? 'Videos Attached' : 'Add Property Video'), style: OutlinedButton.styleFrom(foregroundColor: _brandPrimary)),
              const SizedBox(height: 24),
              SegmentedButton<String>(segments: const [ButtonSegment(value: 'Resort', label: Text('Resort')), ButtonSegment(value: 'Hotel', label: Text('Hotel'))], selected: {_propertyType}, onSelectionChanged: (s) => setState(() => _propertyType = s.first)),
              const SizedBox(height: 16),
              _buildTextField(_propNameController, 'Business Name', Icons.business),
              const SizedBox(height: 16),
              _buildTextField(_propDescController, 'Description', Icons.description, maxLines: 3),
              const SizedBox(height: 16),
              Row(children: [Expanded(child: _buildTextField(_roomsController, 'Rooms', Icons.room, keyboardType: TextInputType.number)), const SizedBox(width: 16), Expanded(child: _buildTextField(_staffController, 'Staff', Icons.groups, keyboardType: TextInputType.number))]),
              const SizedBox(height: 16),
              const Text('GCash Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              _buildTextField(_gcashNumberController, 'GCash Number', Icons.phone_android, keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              _buildTextField(_gcashNameController, 'GCash Name', Icons.badge),
              const SizedBox(height: 32),
              ElevatedButton(onPressed: _isSubmitting ? null : _saveProfile, style: ElevatedButton.styleFrom(backgroundColor: _accentColor, foregroundColor: Colors.white, padding: const EdgeInsets.all(16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: const Text('COMPLETE SETUP', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainDashboard(Map propData, double totalRevenue) {
    final user = FirebaseAuth.instance.currentUser;
    final activityQuery = FirebaseDatabase.instance.ref("activities/${user?.uid}");
    final chatRoomsQuery = FirebaseDatabase.instance.ref("chat_rooms/${user?.uid}").orderByChild("timestamp");
    final List imgs = _parseList(propData['imageUrls']);
    String? firstImg = imgs.isNotEmpty ? imgs[0] : null;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          toolbarHeight: 80,
          elevation: 0, backgroundColor: Colors.white,
          title: Row(
            children: [
              CircleAvatar(radius: 24, backgroundImage: firstImg != null ? NetworkImage(firstImg) : null, child: firstImg == null ? const Icon(Icons.business) : null), 
              const SizedBox(width: 12), 
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(propData['name'] ?? 'Business', overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w900)), 
                    Text(propData['type'] ?? '', style: TextStyle(color: _brandPrimary, fontSize: 12, fontWeight: FontWeight.bold))
                  ]
                ),
              )
            ]
          ),
          actions: [
            _appBarAction(Icons.edit_note_rounded, () {
              _propNameController.text = propData['name'] ?? '';
              _propDescController.text = propData['description'] ?? '';
              _roomsController.text = (propData['rooms'] ?? 0).toString();
              _staffController.text = (propData['staffCount'] ?? 0).toString();
              _gcashNumberController.text = propData['gcashNumber'] ?? '';
              _gcashNameController.text = propData['gcashName'] ?? '';
              _imageUrls = _parseList(propData['imageUrls']);
              _propVideoUrls = _parseList(propData['videoUrls']);
              _propertyType = propData['type'] ?? 'Resort';
              _showEditPropertySheet();
            }),
            _appBarAction(Icons.logout_rounded, () => _showLogoutDialog(context), isLogout: true),
          ],
          bottom: TabBar(
            tabs: const [Tab(text: 'Offers'), Tab(text: 'Bookings'), Tab(text: 'Chat')], 
            labelColor: _brandPrimary, unselectedLabelColor: Colors.grey, indicatorColor: _brandPrimary, indicatorWeight: 4, indicatorSize: TabBarIndicatorSize.label,
          ),
        ),
        body: TabBarView(
          children: [
            ListView(padding: const EdgeInsets.symmetric(vertical: 20), children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20), 
                padding: const EdgeInsets.all(24), 
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 10))]), 
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround, 
                  children: [
                    Expanded(child: _buildStatItem('Rooms', propData['rooms'].toString(), Icons.meeting_room_rounded)), 
                    Expanded(child: _buildStatItem('Staff', propData['staffCount'].toString(), Icons.badge_rounded)), 
                    Expanded(
                      child: GestureDetector(
                        onLongPress: _showResetRevenueDialog,
                        child: _buildStatItem('Revenue', '₱${totalRevenue.toStringAsFixed(0)}', Icons.payments_rounded),
                      ),
                    ),
                  ]
                )
              ),
              const SizedBox(height: 32),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Manage Offers', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)), ElevatedButton.icon(onPressed: () { _clearActivityForm(); _showActivitySheet(); }, icon: const Icon(Icons.add, size: 18), label: const Text('Add New'), style: ElevatedButton.styleFrom(backgroundColor: _brandPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))])),
              FirebaseAnimatedList(query: activityQuery, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.all(20), itemBuilder: (context, snapshot, animation, index) => FadeTransition(opacity: animation, child: _buildActivityCard(snapshot.value as Map, snapshot.key!))),
            ]),
            _buildBookingsTab(),
            _buildChatTab(chatRoomsQuery),
          ],
        ),
      ),
    );
  }

  Widget _appBarAction(IconData icon, VoidCallback onTap, {bool isLogout = false}) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(color: isLogout ? Colors.red.withOpacity(0.05) : _brandPrimary.withOpacity(0.05), shape: BoxShape.circle),
    child: IconButton(icon: Icon(icon, color: isLogout ? Colors.red : _brandPrimary, size: 22), onPressed: onTap),
  );

  Widget _buildStatItem(String label, String value, IconData icon) => Column(children: [Icon(icon, color: _brandPrimary, size: 24), const SizedBox(height: 8), Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)), Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5))]);

  Widget _buildActivityCard(Map act, String key) {
    final List imgs = _parseList(act['imageUrls']);
    String? firstImg = imgs.isNotEmpty ? imgs[0] : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 16), 
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0, color: Colors.white,
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: ClipRRect(borderRadius: BorderRadius.circular(16), child: firstImg != null ? Image.network(firstImg, width: 60, height: 60, fit: BoxFit.cover) : Container(width: 60, height: 60, color: Colors.grey[100], child: const Icon(Icons.local_activity))),
        title: Text(act['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), 
        subtitle: Text('₱${act['price']}', style: TextStyle(color: _brandPrimary, fontWeight: FontWeight.w900)), 
        trailing: Row(
          mainAxisSize: MainAxisSize.min, 
          children: [
            IconButton(icon: const Icon(Icons.edit_rounded, color: Colors.blue, size: 20), onPressed: () { 
              _activityNameController.text = act['title'] ?? ''; _activityDescController.text = act['description'] ?? ''; _activityPriceController.text = (act['price'] ?? '').toString(); 
              _activityImageUrls = _parseList(act['imageUrls']); _activityVideoUrl = act['videoUrl']; _editingActivityKey = key; _showActivitySheet(); 
            }), 
            IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20), onPressed: () => _showDeleteActivityDialog(key, act['title'] ?? '')),
          ]
        )
      )
    );
  }

  Widget _buildBookingsTab() {
    final user = FirebaseAuth.instance.currentUser;
    final query = FirebaseDatabase.instance.ref("bookings").orderByChild("ownerUid").equalTo(user?.uid);
    return FirebaseAnimatedList(query: query, padding: const EdgeInsets.all(20), itemBuilder: (context, snapshot, animation, index) {
      Map booking = snapshot.value as Map;
      return FadeTransition(opacity: animation, child: _buildBookingCard(booking, snapshot.key!));
    });
  }

  Widget _buildBookingCard(Map booking, String key) {
    Color color = booking['status'] == 'Confirmed' ? Colors.green : (booking['status'] == 'Cancelled' ? Colors.red : Colors.orange);
    String? receipt = booking['gcashReceipt'];
    String? cancelNote = booking['cancellationReason'];

    return Container(
      margin: const EdgeInsets.only(bottom: 16), 
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 8))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(booking['touristName'] ?? 'Tourist', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), 
            subtitle: Text("${booking['activityTitle']}\nPayment: ${booking['paymentMethod']}"), 
            isThreeLine: true,
            trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)), child: Text(booking['status'] ?? 'Pending', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10))),
          ), 
          if (cancelNote != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text("Cancellation Reason: $cancelNote", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12))),
          if (receipt != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextButton.icon(onPressed: () => _viewReceipt(receipt), icon: const Icon(Icons.receipt_long, size: 16), label: const Text('View Proof of Payment'))),
          if (booking['status'] == 'Pending') Padding(padding: const EdgeInsets.all(16), child: Row(children: [Expanded(child: OutlinedButton(onPressed: () => _updateBookingStatus(key, 'Cancelled', booking), style: OutlinedButton.styleFrom(foregroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Decline'))), const SizedBox(width: 12), Expanded(child: ElevatedButton(onPressed: () => _updateBookingStatus(key, 'Confirmed', booking), style: ElevatedButton.styleFrom(backgroundColor: _brandPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Confirm')))]))
        ]
      )
    );
  }

  void _viewReceipt(String url) {
    showDialog(context: context, builder: (context) => Dialog(child: Column(mainAxisSize: MainAxisSize.min, children: [Image.network(url), TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))])));
  }

  Widget _buildChatTab(Query query) {
    return FirebaseAnimatedList(
      query: query, padding: const EdgeInsets.all(16),
      itemBuilder: (context, snapshot, animation, index) {
        Map room = snapshot.value as Map;
        String uid = snapshot.key!;
        return FadeTransition(opacity: animation, child: Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), margin: const EdgeInsets.only(bottom: 12), child: ListTile(leading: CircleAvatar(backgroundColor: _brandPrimary.withOpacity(0.1), child: const Icon(Icons.person)), title: Text(room['otherUserName'] ?? 'Tourist', style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text('Tap to open chat', style: TextStyle(fontSize: 12)), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChatPage(otherUserUid: uid, otherUserName: room['otherUserName'] ?? 'Tourist'))))));
      },
    );
  }

  void _showEditPropertySheet() {
    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24), 
          child: Form(
            key: _profileFormKey, 
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min, 
                children: [
                  const Text('Edit Business Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), 
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _imageUrls.length + 1,
                      itemBuilder: (context, index) {
                        if (index == _imageUrls.length) return GestureDetector(onTap: () async { await _pickAndUploadImages(); setModalState(() {}); }, child: Container(width: 80, margin: const EdgeInsets.only(right: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: _brandPrimary.withOpacity(0.3))), child: Icon(Icons.add_a_photo, color: _brandPrimary, size: 20)));
                        return Stack(children: [Container(width: 80, margin: const EdgeInsets.only(right: 12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), image: DecorationImage(image: NetworkImage(_imageUrls[index]), fit: BoxFit.cover))), Positioned(top: 2, right: 14, child: GestureDetector(onTap: () { _removeImage(index); setModalState(() {}); }, child: const CircleAvatar(radius: 8, backgroundColor: Colors.red, child: Icon(Icons.close, size: 10, color: Colors.white))))]);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(onPressed: () async { await _pickAndUploadVideo(); setModalState(() {}); }, icon: Icon(Icons.video_call, color: _brandPrimary), label: Text(_propVideoUrls.isNotEmpty ? 'Videos Attached (Change)' : 'Add Property Video')),
                  const SizedBox(height: 16),
                  _buildTextField(_propNameController, 'Name', Icons.business),
                  const SizedBox(height: 12),
                  _buildTextField(_propDescController, 'Description', Icons.description, maxLines: 2),
                  const SizedBox(height: 12),
                  Row(children: [Expanded(child: _buildTextField(_roomsController, 'Rooms', Icons.room, keyboardType: TextInputType.number)), const SizedBox(width: 12), Expanded(child: _buildTextField(_staffController, 'Staff', Icons.groups, keyboardType: TextInputType.number))]),
                  const SizedBox(height: 12),
                  _buildTextField(_gcashNumberController, 'GCash Number', Icons.phone_android, keyboardType: TextInputType.phone),
                  const SizedBox(height: 12),
                  _buildTextField(_gcashNameController, 'GCash Name', Icons.badge),
                  const SizedBox(height: 24),
                  ElevatedButton(onPressed: _isSubmitting ? null : _saveProfile, style: ElevatedButton.styleFrom(backgroundColor: _brandPrimary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: const Text('UPDATE PROFILE')),
                  const SizedBox(height: 24),
                ]
              ),
            )
          )
        )
      )
    );
  }

  void _showActivitySheet() {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))), builder: (context) => StatefulBuilder(builder: (context, setS) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24), child: Form(key: _activityFormKey, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_editingActivityKey != null ? 'Edit Offer' : 'New Offer', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 24), SizedBox(height: 80, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: _activityImageUrls.length + 1, itemBuilder: (context, i) { if (i == _activityImageUrls.length) return GestureDetector(onTap: () async { await _pickAndUploadImages(isActivity: true); setS((){}); }, child: Container(width: 80, margin: const EdgeInsets.only(right: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: _brandPrimary.withOpacity(0.3))), child: Icon(Icons.add_a_photo, color: _brandPrimary, size: 20))); return Stack(children: [Container(width: 80, margin: const EdgeInsets.only(right: 12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), image: DecorationImage(image: NetworkImage(_activityImageUrls[i]), fit: BoxFit.cover))), Positioned(top: 2, right: 14, child: GestureDetector(onTap: () { _removeImage(i, isActivity: true); setS((){}); }, child: const CircleAvatar(radius: 8, backgroundColor: Colors.red, child: Icon(Icons.close, size: 10, color: Colors.white))))]); })), const SizedBox(height: 12), OutlinedButton.icon(onPressed: () async { await _pickAndUploadVideo(isActivity: true); setS((){}); }, icon: const Icon(Icons.video_call), label: Text(_activityVideoUrl != null ? 'Video Added' : 'Add Video'), style: OutlinedButton.styleFrom(foregroundColor: _brandPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))), const SizedBox(height: 20), _buildTextField(_activityNameController, 'Title', Icons.local_activity), const SizedBox(height: 12), _buildTextField(_activityDescController, 'Details', Icons.notes, maxLines: 2), const SizedBox(height: 12), _buildTextField(_activityPriceController, 'Price (₱)', Icons.payments, keyboardType: TextInputType.number), const SizedBox(height: 32), ElevatedButton(onPressed: _submitActivity, style: ElevatedButton.styleFrom(backgroundColor: _brandPrimary, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text('SAVE OFFER', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1))), const SizedBox(height: 32)]))))));
  }

  void _showDeleteActivityDialog(String key, String title) {
    final user = FirebaseAuth.instance.currentUser;
    showDialog(context: context, builder: (context) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: const Text('Delete Offer?'), content: Text('Remove "$title" permanently?'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), TextButton(onPressed: () async { Navigator.pop(context); await FirebaseDatabase.instance.ref("activities/${user?.uid}/$key").remove(); }, child: const Text('Delete', style: TextStyle(color: Colors.red)))],));
  }

  Widget _buildTextField(TextEditingController c, String l, IconData i, {int maxLines = 1, TextInputType keyboardType = TextInputType.text}) => TextFormField(
    controller: c, 
    maxLines: maxLines, 
    keyboardType: keyboardType, 
    inputFormatters: keyboardType == TextInputType.number || keyboardType == TextInputType.phone ? [FilteringTextInputFormatter.digitsOnly] : null,
    decoration: InputDecoration(labelText: l, prefixIcon: Icon(i, color: _brandPrimary), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)), contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16))
  );
}
