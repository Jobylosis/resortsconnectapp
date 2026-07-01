import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme.dart';
import 'theme_provider.dart';
import 'package:provider/provider.dart';

class PoliciesPropertyPage extends StatefulWidget {
  final Map? propertyData;
  final String? propertyId;

  const PoliciesPropertyPage({super.key, this.propertyData, this.propertyId});

  @override
  State<PoliciesPropertyPage> createState() => _PoliciesPropertyPageState();
}

class _PoliciesPropertyPageState extends State<PoliciesPropertyPage> {
  Map? _currentProperty;
  String? _selectedPropertyId;
  List<Map<String, dynamic>> _allProperties = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.propertyData != null) {
      _currentProperty = widget.propertyData;
      _selectedPropertyId = widget.propertyId ?? _currentProperty?['id'] ?? _currentProperty?['uid'];
      _isLoading = false;
    } else {
      _fetchAllProperties();
    }
  }

  Future<void> _fetchAllProperties() async {
    try {
      final snap = await FirebaseDatabase.instance.ref("properties").get();
      if (snap.exists && snap.value is Map) {
        final data = snap.value as Map;
        List<Map<String, dynamic>> list = [];
        data.forEach((key, value) {
          if (value is Map) {
            list.add({'id': key, ...value});
          }
        });
        setState(() {
          _allProperties = list;
          if (list.isNotEmpty) {
            _selectedPropertyId = list.first['id'];
            _currentProperty = list.first;
          }
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _onPropertySelected(String? id) {
    if (id == null) return;
    setState(() {
      _selectedPropertyId = id;
      _currentProperty = _allProperties.firstWhere((p) => p['id'] == id);
    });
  }

  List<String> _parseList(dynamic data) {
    if (data == null) return [];
    if (data is List) return data.where((e) => e != null).map((e) => e.toString()).toList();
    if (data is Map) return data.values.map((e) => e.toString()).toList();
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.themeMode == ThemeMode.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        title: const Text('Policies & Property Info', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentProperty == null
              ? const Center(child: Text("Property not found."))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.propertyData == null && _allProperties.isNotEmpty) ...[
                        Text("Select a Resort to view its policies:", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.grey[400] : Colors.grey[700])),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.darkSurface : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedPropertyId,
                              isExpanded: true,
                              dropdownColor: isDark ? AppTheme.darkSurface : Colors.white,
                              items: _allProperties.map((p) => DropdownMenuItem<String>(
                                value: p['id'],
                                child: Text(p['name'] ?? 'Unknown Resort', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                              )).toList(),
                              onChanged: _onPropertySelected,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      
                      // Header
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryAccent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.business, color: Colors.white, size: 28),
                                const SizedBox(width: 12),
                                Expanded(child: Text(_currentProperty?['name'] ?? 'Resort Name', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(_currentProperty?['description'] ?? "Experience a wonderful stay with our verified partner resort. Please review the policies and details below to ensure a smooth and enjoyable visit.", style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Others / Supplements
                      if ((_currentProperty?['additionalSupplements'] != null && _currentProperty!['additionalSupplements'].toString().isNotEmpty) || ((_currentProperty?['rooms'] ?? 0) > 5))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: _buildSectionCard(
                            title: "Others",
                            icon: Icons.list_alt,
                            iconColor: AppTheme.secondaryAccent,
                            isDark: isDark,
                            child: Text(
                              _currentProperty?['additionalSupplements'] ?? 'When booking more than 5 rooms, different policies and additional supplements may apply.',
                              style: TextStyle(fontSize: 14, color: isDark ? Colors.grey[300] : Colors.grey[800], height: 1.5),
                            ),
                          ),
                        ),

                      // Some helpful facts
                      _buildSectionCard(
                        title: "Some helpful facts",
                        icon: Icons.lightbulb,
                        iconColor: Colors.amber,
                        isDark: isDark,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Check-in/Check-out
                            Text("Check-in/Check-out", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                            const SizedBox(height: 12),
                            _buildFactRow(Icons.person, "Check-in from: ${_currentProperty?['checkInTime'] ?? '02:00 PM'}", isDark),
                            _buildFactRow(Icons.person_outline, "Check-out until: ${_currentProperty?['checkOutTime'] ?? '12:00 PM'}", isDark),
                            _buildFactRow(Icons.access_time, "Reception open until: ${_currentProperty?['receptionOpenUntil'] ?? '10:00 PM'}", isDark),
                            const SizedBox(height: 20),

                            // The property
                            Text("The property", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                            const SizedBox(height: 12),
                            _buildFactRow(Icons.calendar_month, "Year property opened: ${_currentProperty?['yearOpened'] ?? 'N/A'}", isDark),
                            _buildFactRow(Icons.stairs, "Number of floors: ${_currentProperty?['numberOfFloors'] ?? '1'}", isDark),
                            _buildFactRow(Icons.meeting_room, "Number of rooms: ${_currentProperty?['rooms'] ?? 'N/A'}", isDark),
                            const SizedBox(height: 20),


                            Text("Parking", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                            const SizedBox(height: 12),
                            _buildFactRow(Icons.local_parking, "On-site parking available", isDark),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Policies
                      _buildPolicyItem(Icons.gavel, Colors.red, "Cancellation & Refunds", 
                        (_currentProperty?['cancellationPolicy']?.toString().isNotEmpty ?? false) ? _currentProperty!['cancellationPolicy'] : "Cancellations made 7 days prior to the check-in date are eligible for a full refund. Cancellations made within 7 days may be subject to a 50% cancellation fee. No-shows will be charged the full amount.", isDark),
                      const SizedBox(height: 12),
                      _buildPolicyItem(Icons.payment, Colors.blue, "Payment Policies", 
                        (_currentProperty?['paymentPolicy']?.toString().isNotEmpty ?? false) ? _currentProperty!['paymentPolicy'] : "We only accept GCash as our payment method. A partial deposit may be required to secure your booking. Full payment must be settled upon check-in or through the app before arrival.", isDark),
                      const SizedBox(height: 12),
                      _buildPolicyItem(Icons.warning, Colors.orange, "Resort Rules", 
                        (_currentProperty?['resortRules']?.toString().isNotEmpty ?? false) ? _currentProperty!['resortRules'] : "• No smoking inside rooms.\n• Quiet hours are from 10:00 PM to 7:00 AM.\n• Outside food/drinks may have a corkage fee.\n• Proper swimwear is required in pools.", isDark),
                      const SizedBox(height: 12),
                      _buildPolicyItem(Icons.pets, Colors.purple, "Pet Policy", 
                        (_currentProperty?['petPolicy']?.toString().isNotEmpty ?? false) ? _currentProperty!['petPolicy'] : "Pets are generally allowed in designated pet-friendly rooms only. An additional pet cleaning fee may apply. Pets must be leashed in public areas at all times.", isDark),
                      const SizedBox(height: 12),
                      _buildPolicyItem(Icons.security, Colors.green, "Safety Guidelines", 
                        (_currentProperty?['safetyGuidelines']?.toString().isNotEmpty ?? false) ? _currentProperty!['safetyGuidelines'] : "For your safety and security, please familiarize yourself with the emergency exits. Unaccompanied minors are not allowed in the pool area. Do not leave valuables unattended.", isDark),
                      const SizedBox(height: 20),

                      // Amenities & Contact
                      _buildSectionCard(
                        title: "Property Facilities & Contact",
                        icon: Icons.info,
                        iconColor: AppTheme.primaryAccent,
                        isDark: isDark,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Amenities", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _parseList(_currentProperty?['amenities']).map((a) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.grey[800] : Colors.grey[200],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.check_circle, size: 14, color: AppTheme.secondaryAccent),
                                    const SizedBox(width: 6),
                                    Text(a, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                                  ],
                                ),
                              )).toList(),
                            ),
                            if (_parseList(_currentProperty?['amenities']).isEmpty)
                              Text("Amenities not listed.", style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])),
                            const SizedBox(height: 24),
                            Text("Contact Details", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(Icons.phone, size: 16, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                                const SizedBox(width: 8),
                                Text(_currentProperty?['contactPhone'] ?? 'Contact number not provided', style: TextStyle(color: isDark ? Colors.grey[300] : Colors.grey[800])),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.email, size: 16, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                                const SizedBox(width: 8),
                                Text(_currentProperty?['contactEmail'] ?? 'Email not provided', style: TextStyle(color: isDark ? Colors.grey[300] : Colors.grey[800])),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Map
                      _buildMapSection(isDark),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Color iconColor, required bool isDark, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black))),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _buildFactRow(IconData icon, String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: isDark ? Colors.grey[400] : Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[300] : Colors.grey[800],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeBox(String label, String time, String desc, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(time, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 4),
          Text(desc, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildPolicyItem(IconData icon, Color iconColor, String title, String desc, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black))),
            ],
          ),
          const SizedBox(height: 12),
          Text(desc, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], height: 1.5, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildMapSection(bool isDark) {
    final lat = double.tryParse(_currentProperty?['latitude']?.toString() ?? '');
    final lng = double.tryParse(_currentProperty?['longitude']?.toString() ?? '');
    
    if (lat == null || lng == null || (lat == 0 && lng == 0)) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Icon(Icons.map, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text("Location Map Unavailable", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
            const SizedBox(height: 8),
            Text("The exact map coordinates for this property have not been set.", textAlign: TextAlign.center, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])),
          ],
        ),
      );
    }

    final pos = LatLng(lat, lng);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.map, color: AppTheme.secondaryAccent),
              const SizedBox(width: 10),
              Expanded(child: Text("Location Map", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black))),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.location_on, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(child: Text(_currentProperty?['address'] ?? 'Address not provided by owner.', style: TextStyle(color: isDark ? Colors.grey[300] : Colors.grey[700]))),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 250,
              width: double.infinity,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: pos,
                  initialZoom: 15.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.resortsconnectapp',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: pos,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_pin, color: Colors.red, size: 40),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                }
              },
              icon: const Icon(Icons.navigation),
              label: const Text('View Directions'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
