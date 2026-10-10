import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../theme.dart';

class HistoricalImportPage extends StatefulWidget {
  final bool isAdmin;
  final String? preselectedPropertyId;

  const HistoricalImportPage({
    super.key,
    this.isAdmin = false,
    this.preselectedPropertyId,
  });

  @override
  State<HistoricalImportPage> createState() => _HistoricalImportPageState();
}

class _HistoricalImportPageState extends State<HistoricalImportPage> {
  final _formKey = GlobalKey<FormState>();

  // Properties list for Admin dropdown
  List<Map<String, dynamic>> _properties = [];
  String? _selectedPropertyId;
  String _selectedPropertyName = '';

  // Form Fields
  String _recordType = 'Room'; // 'Room' | 'Activity'
  bool _maskData = false;

  final _guestNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _nationalityController = TextEditingController(text: 'Filipino');
  final _emailController = TextEditingController();
  final _contactController = TextEditingController();
  final _arrivalDateController = TextEditingController();
  final _departureDateController = TextEditingController();
  final _nightsController = TextEditingController(text: '1');
  final _adultsController = TextEditingController(text: '2');
  final _childrenController = TextEditingController(text: '0');
  final _plateNumberController = TextEditingController();
  final _roomTypeController = TextEditingController();
  final _ratePerNightController = TextEditingController();
  final _totalStayController = TextEditingController();
  final _noteController = TextEditingController();
  final _checkedInByController = TextEditingController();

  // Activity specific
  final _activityTitleController = TextEditingController();
  final _paxController = TextEditingController(text: '1');
  final _pricePerPaxController = TextEditingController();
  final _timeSlotController = TextEditingController(text: '09:00 AM - 10:00 AM');
  final _mealAddonsController = TextEditingController();

  String _bookingSource = 'Walk-in';
  String _paymentMethod = 'Cash';
  String _paymentOption = 'Full Payment';

  bool _isLoading = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadProperties();
  }

  @override
  void dispose() {
    _guestNameController.dispose();
    _addressController.dispose();
    _nationalityController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    _arrivalDateController.dispose();
    _departureDateController.dispose();
    _nightsController.dispose();
    _adultsController.dispose();
    _childrenController.dispose();
    _plateNumberController.dispose();
    _roomTypeController.dispose();
    _ratePerNightController.dispose();
    _totalStayController.dispose();
    _noteController.dispose();
    _checkedInByController.dispose();
    _activityTitleController.dispose();
    _paxController.dispose();
    _pricePerPaxController.dispose();
    _timeSlotController.dispose();
    _mealAddonsController.dispose();
    super.dispose();
  }

  Future<void> _loadProperties() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    try {
      final snap = await FirebaseDatabase.instance.ref('properties').get();
      if (snap.exists && snap.value != null) {
        final Map all = snap.value as Map;
        List<Map<String, dynamic>> list = [];
        all.forEach((k, v) {
          if (v is Map) {
            final p = Map<String, dynamic>.from(v);
            p['id'] = k.toString();
            list.add(p);
          }
        });

        if (!widget.isAdmin && currentUid != null) {
          list = list.where((p) => p['id'] == currentUid || p['ownerUid'] == currentUid).toList();
        }

        setState(() {
          _properties = list;
          if (widget.preselectedPropertyId != null) {
            final matched = list.firstWhere((p) => p['id'] == widget.preselectedPropertyId, orElse: () => list.isNotEmpty ? list.first : {});
            if (matched.isNotEmpty) {
              _selectedPropertyId = matched['id'];
              _selectedPropertyName = matched['name'] ?? matched['title'] ?? 'Property';
            }
          } else if (list.isNotEmpty) {
            _selectedPropertyId = list.first['id'];
            _selectedPropertyName = list.first['name'] ?? list.first['title'] ?? 'Property';
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading properties: $e');
    }
  }

  DateTime? _parseFlexibleDate(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final formats = [
      'MM/dd/yy',
      'MM/dd/yyyy',
      'M/d/yy',
      'M/d/yyyy',
      'yyyy-MM-dd',
      'MMM dd, yyyy',
      'dd/MM/yyyy',
      'dd/MM/yy',
    ];

    for (var f in formats) {
      try {
        DateTime parsed = DateFormat(f).parseStrict(trimmed);
        if (parsed.year < 100) {
          parsed = DateTime(parsed.year + 2000, parsed.month, parsed.day);
        }
        return parsed;
      } catch (_) {}
    }
    return DateTime.tryParse(trimmed);
  }

  String _maskSensitive(String text) {
    final t = text.trim();
    if (t.length <= 4) return t;
    return '${'*' * (t.length - 4)}${t.substring(t.length - 4)}';
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    DateTime initial = DateTime(now.year, now.month, now.day);
    if (controller.text.isNotEmpty) {
      final parsed = _parseFlexibleDate(controller.text);
      if (parsed != null) initial = parsed;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );

    if (picked != null) {
      setState(() {
        controller.text = DateFormat('MM/dd/yy').format(picked);
      });
    }
  }

  Future<void> _submitRecord({bool addAnother = false}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPropertyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a target property.')),
      );
      return;
    }

    final arrivalDt = _parseFlexibleDate(_arrivalDateController.text);
    if (arrivalDt == null) {
      setState(() {
        _statusMessage = 'Invalid date format. Use MM/DD/YY e.g. 10/02/26';
        _isSuccess = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final targetProp = _properties.firstWhere((p) => p['id'] == _selectedPropertyId, orElse: () => {});
      final propName = targetProp['name'] ?? targetProp['title'] ?? _selectedPropertyName;
      final ownerUid = targetProp['ownerUid'] ?? _selectedPropertyId;

      final randSuffix = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
      final syntheticTouristUid = 'walkin_${DateTime.now().millisecondsSinceEpoch}_$randSuffix';

      String contactNum = _contactController.text.trim();
      String emailStr = _emailController.text.trim();
      if (_maskData) {
        if (contactNum.isNotEmpty) contactNum = _maskSensitive(contactNum);
        if (emailStr.isNotEmpty) emailStr = _maskSensitive(emailStr);
      }

      final batchId = 'mobile_manual_${DateTime.now().millisecondsSinceEpoch}';

      if (_recordType == 'Room') {
        int nights = int.tryParse(_nightsController.text) ?? 1;
        DateTime? depDt = _parseFlexibleDate(_departureDateController.text);
        if (depDt == null) {
          depDt = arrivalDt.add(Duration(days: nights));
        } else {
          final diff = depDt.difference(arrivalDt).inDays;
          if (diff > 0) nights = diff;
        }

        double rate = double.tryParse(_ratePerNightController.text) ?? 0;
        double totalStay = double.tryParse(_totalStayController.text) ?? 0;
        if (totalStay <= 0 && rate > 0) {
          totalStay = rate * nights;
        }

        final bookingPayload = {
          'touristUid': syntheticTouristUid,
          'touristName': _guestNameController.text.trim(),
          'touristProfilePic': null,
          'ownerUid': ownerUid,
          'propertyName': propName,
          'roomId': 'historical',
          'roomTitle': _roomTypeController.text.trim(),
          'activityId': 'historical',
          'activityTitle': _roomTypeController.text.trim(),
          'isActivityBooking': false,
          'pricing': {
            'basePrice': totalStay,
            'addonsTotal': 0,
            'taxes': 0,
            'grandTotal': totalStay,
          },
          'totalPrice': totalStay,
          'amountPaid': totalStay,
          'nights': nights,
          'bookingDate': DateFormat('MMM dd, yyyy').format(arrivalDt),
          'departureDate': DateFormat('MMM dd, yyyy').format(depDt),
          'status': 'Completed',
          'paymentStatus': 'paid',
          'paymentMethod': _paymentMethod,
          'paymentOption': _paymentOption,
          'bookingSource': _bookingSource,
          'adults': int.tryParse(_adultsController.text) ?? 2,
          'children': int.tryParse(_childrenController.text) ?? 0,
          'plateNumber': _plateNumberController.text.trim(),
          'nationality': _nationalityController.text.trim(),
          'address': _addressController.text.trim(),
          'contactNumber': contactNum,
          'email': emailStr,
          'note': _noteController.text.trim(),
          'checkedInBy': _checkedInByController.text.trim(),
          'selectedAddons': [],
          'agreedToTerms': true,
          'timestamp': arrivalDt.millisecondsSinceEpoch,
          'createdAt': ServerValue.timestamp,
          // Historical Flags
          'isHistorical': true,
          'importBatchId': batchId,
          'importedBy': currentUid,
          'importedAt': ServerValue.timestamp,
          'dataSource': 'manual_entry',
        };

        await FirebaseDatabase.instance.ref('bookings').push().set(bookingPayload);
      } else {
        // Activity Booking
        int pax = int.tryParse(_paxController.text) ?? 1;
        double price = double.tryParse(_pricePerPaxController.text) ?? 0;
        bool isBoat = _activityTitleController.text.toLowerCase().contains('boatride');
        double soloFee = (isBoat && pax == 1) ? 750 : 0;
        double actSubtotal = price * pax;
        double grandTotal = actSubtotal + soloFee;

        List<String> mealAddons = _mealAddonsController.text.trim().isNotEmpty
            ? _mealAddonsController.text.split(';').map((m) => m.trim()).toList()
            : [];

        final actPayload = {
          'touristUid': syntheticTouristUid,
          'touristName': _guestNameController.text.trim(),
          'touristProfilePic': null,
          'ownerUid': ownerUid,
          'propertyName': propName,
          'roomId': 'historical',
          'roomTitle': _activityTitleController.text.trim(),
          'activityId': 'historical',
          'activityTitle': _activityTitleController.text.trim(),
          'isActivityBooking': true,
          'selectedActivities': [
            {
              'id': 'historical_act',
              'title': _activityTitleController.text.trim(),
              'price': price,
              'pax': pax,
              'soloFee': soloFee,
              'timeSlot': _timeSlotController.text.trim(),
              'arrivalTime': _timeSlotController.text.trim(),
              'total': actSubtotal + soloFee,
            }
          ],
          'pricing': {
            'activitiesSubtotal': actSubtotal,
            'soloSurcharges': soloFee,
            'mealsTotal': 0,
            'grandTotal': grandTotal,
          },
          'totalPrice': grandTotal,
          'amountPaid': grandTotal,
          'nights': 1,
          'bookingDate': DateFormat('MMM dd, yyyy').format(arrivalDt),
          'departureDate': DateFormat('MMM dd, yyyy').format(arrivalDt),
          'timeSlot': _timeSlotController.text.trim(),
          'arrivalTime': _timeSlotController.text.trim(),
          'status': 'Completed',
          'paymentStatus': 'paid',
          'paymentMethod': _paymentMethod,
          'paymentOption': 'Full Payment',
          'bookingSource': _bookingSource,
          'contactNumber': contactNum,
          'note': _noteController.text.trim(),
          'selectedAddons': mealAddons,
          'agreedToTerms': true,
          'timestamp': arrivalDt.millisecondsSinceEpoch,
          'createdAt': ServerValue.timestamp,
          // Historical Flags
          'isHistorical': true,
          'importBatchId': batchId,
          'importedBy': currentUid,
          'importedAt': ServerValue.timestamp,
          'dataSource': 'manual_entry',
        };

        await FirebaseDatabase.instance.ref('bookings').push().set(actPayload);
      }

      setState(() {
        _isLoading = false;
        _isSuccess = true;
        _statusMessage = 'Historical stay saved successfully!';
      });

      if (addAnother) {
        _guestNameController.clear();
        _contactController.clear();
        _emailController.clear();
        _totalStayController.clear();
        _noteController.clear();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Historical registration card recorded successfully!')),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isSuccess = false;
        _statusMessage = 'Failed to save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Historical Data', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F766E), AppTheme.secondaryAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.history_edu_rounded, color: Colors.white, size: 28),
                        SizedBox(width: 10),
                        Text('Registration Card Entry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Load paper walk-in cards into dashboards and revenue charts for panel defense. These past records will be marked as Completed.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Privacy Notice Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.privacy_tip_outlined, color: AppTheme.primaryAccent, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'PH Data Privacy Act: Mask or omit personal contact details if not authorized.',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Mask contact number and email (store last 4 digits only)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      value: _maskData,
                      onChanged: (val) => setState(() => _maskData = val ?? false),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Target Property Selector
              if (_properties.length > 1) ...[
                const Text('TARGET PROPERTY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _selectedPropertyId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  items: _properties.map((p) {
                    final pName = p['name'] ?? p['title'] ?? p['id'];
                    final pType = p['type'] ?? '';
                    return DropdownMenuItem<String>(
                      value: p['id'].toString(),
                      child: Text('$pName ($pType)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedPropertyId = val;
                      final matched = _properties.firstWhere((p) => p['id'] == val, orElse: () => {});
                      _selectedPropertyName = matched['name'] ?? matched['title'] ?? 'Property';
                    });
                  },
                ),
                const SizedBox(height: 20),
              ],

              // Record Type Toggle
              const Text('RECORD TYPE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _recordType == 'Room' ? AppTheme.primaryAccent : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                          foregroundColor: _recordType == 'Room' ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                          minimumSize: const Size(64, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => setState(() => _recordType = 'Room'),
                        icon: const Icon(Icons.hotel_rounded, size: 18),
                        label: const Text('Room Stay', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _recordType == 'Activity' ? AppTheme.primaryAccent : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                          foregroundColor: _recordType == 'Activity' ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                          minimumSize: const Size(64, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => setState(() => _recordType = 'Activity'),
                        icon: const Icon(Icons.kayaking_rounded, size: 18),
                        label: const Text('Activity Booking', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Section 1: Guest Details
              const Text('GUEST DETAILS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.primaryAccent, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _guestNameController,
                decoration: const InputDecoration(labelText: 'Guest Full Name *', hintText: 'e.g. Juan D. Cruz'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Guest name is required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _contactController,
                      decoration: const InputDecoration(labelText: 'Contact Number', hintText: '09XXXXXXXXX'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(labelText: 'Email Address', hintText: 'guest@example.com'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(labelText: 'Address', hintText: 'e.g. Makati City'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _nationalityController,
                      decoration: const InputDecoration(labelText: 'Nationality', hintText: 'Filipino'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Section 2: Reservation / Activity Details
              Text(_recordType == 'Room' ? 'RESERVATION DETAILS' : 'ACTIVITY DETAILS',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.primaryAccent, letterSpacing: 0.5)),
              const SizedBox(height: 12),

              if (_recordType == 'Room') ...[
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _arrivalDateController,
                        decoration: InputDecoration(
                          labelText: 'Arrival Date *',
                          hintText: 'MM/DD/YY',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.calendar_today_rounded, size: 20),
                            onPressed: () => _pickDate(_arrivalDateController),
                          ),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Arrival date required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _departureDateController,
                        decoration: InputDecoration(
                          labelText: 'Departure Date',
                          hintText: 'MM/DD/YY',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.calendar_today_rounded, size: 20),
                            onPressed: () => _pickDate(_departureDateController),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _nightsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'No. of Nights', hintText: '1'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _roomTypeController,
                        decoration: const InputDecoration(labelText: 'Room Type / No. *', hintText: 'e.g. RY or Rm 001'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Room type required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _adultsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Adults', hintText: '2'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _childrenController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Children', hintText: '0'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _plateNumberController,
                        decoration: const InputDecoration(labelText: 'Plate No.', hintText: 'ABC-1234'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _ratePerNightController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Rate / Night (₱)', hintText: '3730'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _totalStayController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Total Stay (₱)', hintText: 'Computed if blank'),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Activity Fields
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _arrivalDateController,
                        decoration: InputDecoration(
                          labelText: 'Activity Date *',
                          hintText: 'MM/DD/YY',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.calendar_today_rounded, size: 20),
                            onPressed: () => _pickDate(_arrivalDateController),
                          ),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Activity date required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _activityTitleController,
                        decoration: const InputDecoration(labelText: 'Activity Title *', hintText: 'Boatride to falls with meal'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Title required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _paxController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Pax', hintText: '1'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _pricePerPaxController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Price / Pax (₱)', hintText: '2000'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _timeSlotController,
                  decoration: const InputDecoration(labelText: 'Time Slot / Schedule', hintText: '09:00 AM - 10:00 AM'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _mealAddonsController,
                  decoration: const InputDecoration(labelText: 'Meal Add-ons (semicolon separated)', hintText: 'Lunch Set Menu (x1)'),
                ),
              ],
              const SizedBox(height: 24),

              // Section 3: Payment & Meta
              const Text('PAYMENT & REMARKS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.primaryAccent, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _bookingSource,
                      decoration: const InputDecoration(labelText: 'Booking Source'),
                      items: ['Walk-in', 'Agoda', 'Booking.com', 'Facebook/Messenger', 'Phone call', 'Website', 'Mobile app', 'Other']
                          .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13))))
                          .toList(),
                      onChanged: (v) => setState(() => _bookingSource = v ?? 'Walk-in'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _paymentMethod,
                      decoration: const InputDecoration(labelText: 'Payment Method'),
                      items: ['Cash', 'GCash', 'Bank transfer', 'OTA prepaid', 'Other']
                          .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13))))
                          .toList(),
                      onChanged: (v) => setState(() => _paymentMethod = v ?? 'Cash'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _noteController,
                      decoration: const InputDecoration(labelText: 'Card Notes / Remarks', hintText: 'e.g. Agoda paid, Paid'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _checkedInByController,
                      decoration: const InputDecoration(labelText: 'Checked In By (Staff)', hintText: 'Staff Maria'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              if (_statusMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isSuccess ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _isSuccess ? Colors.green : Colors.red),
                  ),
                  child: Text(
                    _statusMessage!,
                    style: TextStyle(
                      color: _isSuccess ? Colors.green.shade800 : Colors.red.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Action Buttons
              SizedBox(
                width: double.infinity,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(64, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _isLoading ? null : () => _submitRecord(addAnother: true),
                        child: const Text('Save & Add Another', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryAccent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(64, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _isLoading ? null : () => _submitRecord(addAnother: false),
                        child: _isLoading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save Record', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
