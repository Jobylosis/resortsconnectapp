import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _amenitiesController = TextEditingController();
  final _priceController = TextEditingController();
  
  String _propertyType = 'Resort';
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _amenitiesController.dispose();
    _priceController.dispose();
    super.dispose();
  }

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

  Future<void> _postOffer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;

    try {
      DatabaseReference ref = FirebaseDatabase.instance.ref("offers").push();
      await ref.set({
        'ownerUid': user?.uid,
        'propertyType': _propertyType,
        'propertyName': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'amenities': _amenitiesController.text.trim(),
        'price': _priceController.text.trim(),
        'timestamp': ServerValue.timestamp,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$_propertyType details published!'),
            backgroundColor: Colors.teal[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
        _nameController.clear();
        _descriptionController.clear();
        _amenitiesController.clear();
        _priceController.clear();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userRef = FirebaseDatabase.instance.ref("users/${user?.uid}");

    return StreamBuilder<DatabaseEvent>(
      stream: userRef.onValue,
      builder: (context, snapshot) {
        String firstName = "Owner";
        if (snapshot.hasData && snapshot.data!.snapshot.exists) {
          Map data = snapshot.data!.snapshot.value as Map;
          firstName = data['firstName'] ?? "Owner";
        }

        return Scaffold(
          backgroundColor: Colors.grey[50],
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.white,
            title: Row(
              children: [
                const Icon(Icons.business_center_rounded, color: Colors.teal, size: 28),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Management',
                      style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Owner: $firstName',
                      style: TextStyle(color: Colors.teal[700], fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: Colors.teal[50], shape: BoxShape.circle),
                child: IconButton(
                  icon: const Icon(Icons.logout_rounded, color: Colors.teal),
                  onPressed: () => _showLogoutDialog(context),
                ),
              ),
            ],
          ),
          body: _isLoading 
            ? const Center(child: CircularProgressIndicator(color: Colors.teal))
            : SingleChildScrollView(
                child: Column(
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
                          Text('Welcome back, $firstName! 💼', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black87)),
                          const SizedBox(height: 8),
                          Text('Manage your business details below.', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Property Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                            const SizedBox(height: 16),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'Resort', label: Text('Resort'), icon: Icon(Icons.beach_access)),
                                ButtonSegment(value: 'Hotel', label: Text('Hotel'), icon: Icon(Icons.hotel)),
                              ],
                              selected: {_propertyType},
                              onSelectionChanged: (Set<String> newSelection) => setState(() => _propertyType = newSelection.first),
                            ),
                            const SizedBox(height: 20),
                            _buildTextField(_nameController, _propertyType == 'Resort' ? 'Resort Name' : 'Hotel Name', Icons.drive_file_rename_outline),
                            const SizedBox(height: 16),
                            _buildTextField(_descriptionController, 'Description / Tagline', Icons.description_outlined, maxLines: 2),
                            const SizedBox(height: 16),
                            _buildTextField(_amenitiesController, 'Amenities (Pool, WiFi, etc.)', Icons.featured_play_list_outlined),
                            const SizedBox(height: 16),
                            _buildTextField(_priceController, 'Rate per night (₱)', Icons.payments_outlined, keyboardType: TextInputType.number),
                            const SizedBox(height: 32),
                            ElevatedButton.icon(
                              onPressed: _postOffer,
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Update Listing', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        );
      },
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {int maxLines = 1, TextInputType keyboardType = TextInputType.text}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.teal[300]),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.teal, width: 1.5)),
      ),
      validator: (value) => value!.isEmpty ? 'Field required' : null,
    );
  }
}
