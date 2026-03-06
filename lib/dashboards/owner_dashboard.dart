import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../profile_page.dart';

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  final _profileFormKey = GlobalKey<FormState>();
  final _activityFormKey = GlobalKey<FormState>();

  // Profile Controllers
  final _propNameController = TextEditingController();
  final _propDescController = TextEditingController();
  final _roomsController = TextEditingController();
  final _staffController = TextEditingController();
  String _propertyType = 'Resort';
  String? _imageUrl;

  // Activity Controllers
  final _activityNameController = TextEditingController();
  final _activityDescController = TextEditingController();
  final _activityPriceController = TextEditingController();

  bool _isSubmitting = false;
  String? _editingActivityKey;

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

  // --- ImgBB Image Upload Logic ---
  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

    if (pickedFile != null) {
      setState(() => _isSubmitting = true);
      try {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('https://api.imgbb.com/1/upload?key=bbe2a79d18422542881211147631b619'),
        );
        request.files.add(await http.MultipartFile.fromPath('image', pickedFile.path));
        
        final response = await request.send();
        if (response.statusCode == 200) {
          final responseData = await response.stream.bytesToString();
          final json = jsonDecode(responseData);
          setState(() {
            _imageUrl = json['data']['url'];
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image uploaded!')));
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      } finally {
        setState(() => _isSubmitting = false);
      }
    }
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

  Future<void> _saveProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    final user = FirebaseAuth.instance.currentUser;
    try {
      await FirebaseDatabase.instance.ref("properties/${user?.uid}").set({
        'name': _propNameController.text.trim(),
        'description': _propDescController.text.trim(),
        'type': _propertyType,
        'rooms': int.tryParse(_roomsController.text) ?? 0,
        'staffCount': int.tryParse(_staffController.text) ?? 0,
        'imageUrl': _imageUrl,
        'ownerUid': user?.uid,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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

  Future<void> _updateBookingStatus(String bookingKey, String status) async {
    await FirebaseDatabase.instance.ref("bookings/$bookingKey").update({'status': status});
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final propRef = FirebaseDatabase.instance.ref("properties/${user?.uid}");

    return StreamBuilder<DatabaseEvent>(
      stream: propRef.onValue,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!snapshot.hasData || !snapshot.data!.snapshot.exists) {
          return _buildProfileSetupScreen();
        }
        Map propData = snapshot.data!.snapshot.value as Map;
        return _buildMainDashboard(propData);
      },
    );
  }

  Widget _buildProfileSetupScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Property Setup'),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => _showLogoutDialog(context))],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _profileFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image Picker UI
              GestureDetector(
                onTap: _pickAndUploadImage,
                child: Container(
                  height: 150,
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey[300]!)),
                  child: _imageUrl != null 
                    ? ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.network(_imageUrl!, fit: BoxFit.cover))
                    : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo, size: 40, color: Colors.grey), Text('Add Property Photo')]),
                ),
              ),
              const SizedBox(height: 24),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Resort', label: Text('Resort'), icon: Icon(Icons.beach_access)),
                  ButtonSegment(value: 'Hotel', label: Text('Hotel'), icon: Icon(Icons.hotel)),
                ],
                selected: {_propertyType},
                onSelectionChanged: (Set<String> newSelection) => setState(() => _propertyType = newSelection.first),
              ),
              const SizedBox(height: 24),
              _buildTextField(_propNameController, 'Business Name', Icons.business),
              const SizedBox(height: 16),
              _buildTextField(_propDescController, 'Description', Icons.description, maxLines: 3),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildTextField(_roomsController, 'Total Rooms', Icons.room, keyboardType: TextInputType.number)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildTextField(_staffController, 'Total Staff', Icons.people, keyboardType: TextInputType.number)),
                ],
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _saveProfile,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text('Complete Setup'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainDashboard(Map propData) {
    final user = FirebaseAuth.instance.currentUser;
    final activityQuery = FirebaseDatabase.instance.ref("activities/${user?.uid}");
    final bookingsQuery = FirebaseDatabase.instance.ref("bookings").orderByChild("ownerUid").equalTo(user?.uid);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          title: Row(
            children: [
              if (propData['imageUrl'] != null)
                CircleAvatar(backgroundImage: Image.network(propData['imageUrl']).image, radius: 18)
              else
                const Icon(Icons.business, color: Colors.teal),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(propData['name'], style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(propData['type'], style: const TextStyle(color: Colors.grey, fontSize: 10)),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(icon: const Icon(Icons.person_outline, color: Colors.teal), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfilePage()))),
            IconButton(icon: const Icon(Icons.logout, color: Colors.teal), onPressed: () => _showLogoutDialog(context)),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Activities'), Tab(text: 'Bookings')], labelColor: Colors.teal, indicatorColor: Colors.teal),
        ),
        body: TabBarView(
          children: [
            // Activities Tab
            Column(
              children: [
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Manage Activities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      TextButton.icon(onPressed: () { _clearActivityForm(); _showActivitySheet(); }, icon: const Icon(Icons.add), label: const Text('Add New')),
                    ],
                  ),
                ),
                Expanded(
                  child: FirebaseAnimatedList(
                    query: activityQuery,
                    padding: const EdgeInsets.all(20),
                    itemBuilder: (context, snapshot, animation, index) {
                      Map act = snapshot.value as Map;
                      return _buildActivityCard(act, snapshot.key!);
                    },
                  ),
                ),
              ],
            ),
            // Bookings Tab
            FirebaseAnimatedList(
              query: bookingsQuery,
              padding: const EdgeInsets.all(20),
              itemBuilder: (context, snapshot, animation, index) {
                Map booking = snapshot.value as Map;
                return _buildBookingCard(booking, snapshot.key!);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityCard(Map act, String key) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(act['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('₱${act['price']} - ${act['description']}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () {
              _activityNameController.text = act['title'];
              _activityDescController.text = act['description'];
              _activityPriceController.text = act['price'].toString();
              _editingActivityKey = key;
              _showActivitySheet();
            }),
            IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteActivity(key)),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingCard(Map booking, String key) {
    Color statusColor = booking['status'] == 'Confirmed' ? Colors.green : (booking['status'] == 'Cancelled' ? Colors.red : Colors.orange);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(booking['touristName'], style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(booking['status'], style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text('Activity: ${booking['activityTitle']}'),
            Text('Date: ${booking['bookingDate']} at ${booking['bookingTime']}'),
            if (booking['status'] == 'Pending')
              Row(
                children: [
                  TextButton(onPressed: () => _updateBookingStatus(key, 'Cancelled'), child: const Text('Decline', style: TextStyle(color: Colors.red))),
                  const Spacer(),
                  ElevatedButton(onPressed: () => _updateBookingStatus(key, 'Confirmed'), style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white), child: const Text('Confirm')),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _showActivitySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Form(
          key: _activityFormKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_editingActivityKey != null ? 'Edit Activity' : 'Add Activity', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              _buildTextField(_activityNameController, 'Title', Icons.local_activity),
              const SizedBox(height: 12),
              _buildTextField(_activityDescController, 'Description', Icons.notes, maxLines: 2),
              const SizedBox(height: 12),
              _buildTextField(_activityPriceController, 'Price (₱)', Icons.payments, keyboardType: TextInputType.number),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _submitActivity, style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.all(16)), child: Text(_editingActivityKey != null ? 'Save' : 'Publish')),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {int maxLines = 1, TextInputType keyboardType = TextInputType.text}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
      validator: (value) => value!.isEmpty ? 'Required' : null,
    );
  }
}
