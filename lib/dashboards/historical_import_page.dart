import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../theme.dart';

/// Reusable Date TextInputFormatter that auto-formats digits into MM/DD/YY as the user types
class DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldText = oldValue.text;
    final newText = newValue.text;

    // Handle backspace over '/'
    if (oldText.length > newText.length) {
      if (oldText.endsWith('/') && !newText.endsWith('/')) {
        return TextEditingValue(
          text: newText.substring(0, newText.length - 1),
          selection: TextSelection.collapsed(offset: newText.length - 1),
        );
      }
      return newValue;
    }

    // Keep digits only, max 6 digits for MM DD YY
    final digits = newText.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }

    final truncated = digits.length > 6 ? digits.substring(0, 6) : digits;
    String formatted = '';

    if (truncated.length <= 2) {
      formatted = truncated;
    } else if (truncated.length <= 4) {
      formatted = '${truncated.substring(0, 2)}/${truncated.substring(2)}';
    } else {
      formatted = '${truncated.substring(0, 2)}/${truncated.substring(2, 4)}/${truncated.substring(4)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

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
  String _paymentMethod = 'Cash'; // Cash | GCash | Bank Transfer | Other

  // Optional Attached Photo (Registration Card / Receipt)
  File? _attachedPhotoFile;
  String? _uploadedPhotoUrl;
  bool _isUploadingPhoto = false;
  String? _photoError;

  bool _isLoading = false;
  String? _statusMessage;
  bool _isSuccess = false;

  Future<void> _pickAttachedPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 80);
    if (picked == null) return;

    final file = File(picked.path);
    final ext = picked.path.split('.').last.toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'webp'].contains(ext) || await file.length() > 10 * 1024 * 1024) {
      setState(() => _photoError = 'Photo must be JPG, PNG, or WEBP and under 10 MB.');
      return;
    }

    setState(() {
      _attachedPhotoFile = file;
      _uploadedPhotoUrl = null;
      _isUploadingPhoto = true;
      _photoError = null;
    });

    try {
      final req = http.MultipartRequest('POST',
          Uri.parse('https://api.cloudinary.com/v1_1/dnv6ezitm/image/upload'))
        ..fields['upload_preset'] = 'resort_unsigned'
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final resp = await req.send();
      if (resp.statusCode == 200) {
        final body = await resp.stream.bytesToString();
        _uploadedPhotoUrl = jsonDecode(body)['secure_url'];
      } else {
        _photoError = 'Photo upload failed. Please try again.';
      }
    } catch (e) {
      _photoError = 'Photo upload failed. Check your connection.';
    }
    if (mounted) setState(() => _isUploadingPhoto = false);
  }

  void _showAddPhotoBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAttachedPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAttachedPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _removeAttachedPhoto() {
    setState(() {
      _attachedPhotoFile = null;
      _uploadedPhotoUrl = null;
      _isUploadingPhoto = false;
      _photoError = null;
    });
  }

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

  // Parses MM/DD/YY strictly and checks calendar validity
  DateTime? _parseStrictDateMMDDYY(String input) {
    final trimmed = input.trim();
    final parts = trimmed.split('/');
    if (parts.length != 3) return null;
    if (parts[0].length != 2 || parts[1].length != 2 || parts[2].length != 2) return null;

    final m = int.tryParse(parts[0]);
    final d = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (m == null || d == null || y == null) return null;
    if (m < 1 || m > 12) return null;

    final fullYear = 2000 + y;
    final daysInMonth = DateTime(fullYear, m + 1, 0).day;
    if (d < 1 || d > daysInMonth) return null;

    return DateTime(fullYear, m, d);
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
      final parsed = _parseStrictDateMMDDYY(controller.text);
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
      _recomputeNights();
    }
  }

  void _recomputeNights() {
    final arr = _parseStrictDateMMDDYY(_arrivalDateController.text);
    final dep = _parseStrictDateMMDDYY(_departureDateController.text);
    if (arr != null && dep != null) {
      final diff = dep.difference(arr).inDays;
      if (diff >= 1) {
        setState(() {
          _nightsController.text = diff.toString();
        });
        _recomputeTotal();
      }
    }
  }

  void _recomputeTotal() {
    if (_recordType == 'Room') {
      final rate = double.tryParse(_ratePerNightController.text) ?? 0;
      final nights = int.tryParse(_nightsController.text) ?? 1;
      if (rate > 0) {
        _totalStayController.text = (rate * nights).toStringAsFixed(2).replaceAll('.00', '');
      }
    } else {
      final price = double.tryParse(_pricePerPaxController.text) ?? 0;
      final pax = int.tryParse(_paxController.text) ?? 1;
      if (price > 0) {
        _totalStayController.text = (price * pax).toStringAsFixed(2).replaceAll('.00', '');
      }
    }
  }

  String _cleanSpaced(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _submitRecord({bool addAnother = false}) async {
    if (!_formKey.currentState!.validate()) {
      setState(() {
        _statusMessage = 'Please fix the errors indicated above.';
        _isSuccess = false;
      });
      return;
    }
    if (_selectedPropertyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a target property.')),
      );
      return;
    }

    final arrivalDt = _parseStrictDateMMDDYY(_arrivalDateController.text);
    if (arrivalDt == null) {
      setState(() {
        _statusMessage = 'Invalid Arrival Date. Format must be MM/DD/YY e.g. 10/02/26';
        _isSuccess = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final targetProp = _properties.firstWhere((p) => p['id'] == _selectedPropertyId, orElse: () => {});
      final propName = targetProp['name'] ?? targetProp['title'] ?? _selectedPropertyName;
      final ownerUid = widget.isAdmin
          ? (targetProp['ownerUid'] ?? targetProp['id'] ?? _selectedPropertyId)
          : (currentUid ?? targetProp['ownerUid'] ?? _selectedPropertyId);

      final randSuffix = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
      final syntheticTouristUid = 'walkin_${DateTime.now().millisecondsSinceEpoch}_$randSuffix';

      final guestName = _cleanSpaced(_guestNameController.text);
      String contactNum = _cleanSpaced(_contactController.text);
      String emailStr = _cleanSpaced(_emailController.text).toLowerCase();
      final address = _cleanSpaced(_addressController.text);
      final nationality = _cleanSpaced(_nationalityController.text).isEmpty ? 'Filipino' : _cleanSpaced(_nationalityController.text);
      final note = _cleanSpaced(_noteController.text);
      final checkedInBy = _cleanSpaced(_checkedInByController.text);

      if (_maskData) {
        if (contactNum.isNotEmpty) contactNum = _maskSensitive(contactNum);
        if (emailStr.isNotEmpty) emailStr = _maskSensitive(emailStr);
      }

      final batchId = 'mobile_manual_${DateTime.now().millisecondsSinceEpoch}';

      // Payment method revenue rule:
      // Cash, GCash, Bank Transfer count toward revenue.
      // Other DOES NOT count toward revenue.
      final isRevenueMethod = ['Cash', 'GCash', 'Bank Transfer'].contains(_paymentMethod);
      final countsTowardRevenue = isRevenueMethod;
      final paymentStatus = isRevenueMethod ? 'paid' : 'unpaid';

      if (_recordType == 'Room') {
        int nights = int.tryParse(_nightsController.text) ?? 1;
        DateTime? depDt = _parseStrictDateMMDDYY(_departureDateController.text);
        if (depDt == null) {
          depDt = arrivalDt.add(Duration(days: nights));
        } else {
          final diff = depDt.difference(arrivalDt).inDays;
          if (diff >= 1) nights = diff;
        }

        double rate = double.tryParse(_ratePerNightController.text) ?? 0;
        double totalStay = double.tryParse(_totalStayController.text) ?? 0;
        if (totalStay <= 0 && rate > 0) {
          totalStay = rate * nights;
        }

        final roomType = _cleanSpaced(_roomTypeController.text);
        final plateNumber = _cleanSpaced(_plateNumberController.text).toUpperCase();

        final bookingPayload = {
          'touristUid': syntheticTouristUid,
          'touristName': guestName,
          'touristProfilePic': null,
          'ownerUid': ownerUid,
          'propertyName': propName,
          'roomId': 'historical',
          'roomTitle': roomType,
          'activityId': 'historical',
          'activityTitle': roomType,
          'isActivityBooking': false,
          'pricing': {
            'basePrice': totalStay,
            'addonsTotal': 0,
            'taxes': 0,
            'grandTotal': totalStay,
          },
          'totalPrice': totalStay,
          'amountPaid': isRevenueMethod ? totalStay : 0,
          'nights': nights,
          'bookingDate': DateFormat('MMM dd, yyyy').format(arrivalDt),
          'departureDate': DateFormat('MMM dd, yyyy').format(depDt),
          'checkInDate': DateFormat('MMM dd, yyyy').format(arrivalDt),
          'checkOutDate': DateFormat('MMM dd, yyyy').format(depDt),
          if (_uploadedPhotoUrl != null && _uploadedPhotoUrl!.isNotEmpty) ...{
            'gcashReceipt': _uploadedPhotoUrl,
            'historicalPhotoUrl': _uploadedPhotoUrl,
          },
          'status': 'Completed',
          'paymentStatus': paymentStatus,
          'paymentMethod': _paymentMethod,
          'paymentOption': 'Full Payment',
          'bookingSource': _bookingSource,
          'adults': int.tryParse(_adultsController.text) ?? 1,
          'children': int.tryParse(_childrenController.text) ?? 0,
          'plateNumber': plateNumber,
          'nationality': nationality,
          'address': address,
          'contactNumber': contactNum,
          'email': emailStr,
          'note': note,
          'checkedInBy': checkedInBy,
          'selectedAddons': [],
          'agreedToTerms': true,
          'timestamp': arrivalDt.millisecondsSinceEpoch,
          'createdAt': ServerValue.timestamp,
          // Historical Flags
          'isHistorical': true,
          'countsTowardRevenue': countsTowardRevenue,
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
        final actTitle = _cleanSpaced(_activityTitleController.text);
        bool isBoat = actTitle.toLowerCase().contains('boatride');
        double soloFee = (isBoat && pax == 1) ? 750 : 0;
        double actSubtotal = price * pax;
        double grandTotal = actSubtotal + soloFee;

        List<String> mealAddons = _mealAddonsController.text.trim().isNotEmpty
            ? _mealAddonsController.text.split(';').map((m) => m.trim()).where((m) => m.isNotEmpty).toList()
            : [];

        final actPayload = {
          'touristUid': syntheticTouristUid,
          'touristName': guestName,
          'touristProfilePic': null,
          'ownerUid': ownerUid,
          'propertyName': propName,
          'roomId': 'historical',
          'roomTitle': actTitle,
          'activityId': 'historical',
          'activityTitle': actTitle,
          'isActivityBooking': true,
          'selectedActivities': [
            {
              'id': 'historical_act',
              'title': actTitle,
              'price': price,
              'pax': pax,
              'soloFee': soloFee,
              'timeSlot': _cleanSpaced(_timeSlotController.text),
              'arrivalTime': _cleanSpaced(_timeSlotController.text),
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
          'amountPaid': isRevenueMethod ? grandTotal : 0,
          'nights': 1,
          'bookingDate': DateFormat('MMM dd, yyyy').format(arrivalDt),
          'departureDate': DateFormat('MMM dd, yyyy').format(arrivalDt),
          'checkInDate': DateFormat('MMM dd, yyyy').format(arrivalDt),
          'checkOutDate': DateFormat('MMM dd, yyyy').format(arrivalDt),
          if (_uploadedPhotoUrl != null && _uploadedPhotoUrl!.isNotEmpty) ...{
            'gcashReceipt': _uploadedPhotoUrl,
            'historicalPhotoUrl': _uploadedPhotoUrl,
          },
          'timeSlot': _cleanSpaced(_timeSlotController.text),
          'arrivalTime': _cleanSpaced(_timeSlotController.text),
          'status': 'Completed',
          'paymentStatus': paymentStatus,
          'paymentMethod': _paymentMethod,
          'paymentOption': 'Full Payment',
          'bookingSource': _bookingSource,
          'contactNumber': contactNum,
          'email': emailStr,
          'note': note,
          'selectedAddons': mealAddons,
          'agreedToTerms': true,
          'timestamp': arrivalDt.millisecondsSinceEpoch,
          'createdAt': ServerValue.timestamp,
          // Historical Flags
          'isHistorical': true,
          'countsTowardRevenue': countsTowardRevenue,
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
        _removeAttachedPhoto();
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
                  initialValue: _selectedPropertyId,
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
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\u00C0-\u024F\u1E00-\u1EFF\s.'-]")),
                  LengthLimitingTextInputFormatter(60),
                ],
                decoration: const InputDecoration(labelText: 'Guest Full Name *', hintText: 'e.g. Juan D. Cruz'),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Guest name is required';
                  if (t.length < 2 || t.length > 60) return 'Must be between 2 and 60 characters';
                  if (!RegExp(r"^[a-zA-Z\u00C0-\u024F\u1E00-\u1EFF\s.'-]+$").hasMatch(t)) {
                    return 'Letters, spaces, period, hyphen, apostrophe only';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _contactController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                        LengthLimitingTextInputFormatter(13),
                      ],
                      decoration: const InputDecoration(labelText: 'Contact Number', hintText: '09XXXXXXXXX or +639...'),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return null;
                        if (!RegExp(r'^(09\d{9}|\+639\d{9})$').hasMatch(t)) {
                          return 'Valid Philippine mobile number required';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                        LengthLimitingTextInputFormatter(100),
                      ],
                      decoration: const InputDecoration(labelText: 'Email Address', hintText: 'guest@example.com'),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return null;
                        if (t.length > 100) return 'Max 100 characters';
                        if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(t)) {
                          return 'Valid email format required';
                        }
                        return null;
                      },
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
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s,.\-#]')),
                        LengthLimitingTextInputFormatter(120),
                      ],
                      decoration: const InputDecoration(labelText: 'Address', hintText: 'e.g. Makati City'),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return null;
                        if (t.length > 120) return 'Max 120 characters';
                        if (!RegExp(r'^[a-zA-Z0-9\s,.\-#]+$').hasMatch(t)) {
                          return 'Letters, numbers, spaces, comma, period, hyphen, # only';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _nationalityController,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s-]')),
                        LengthLimitingTextInputFormatter(40),
                      ],
                      decoration: const InputDecoration(labelText: 'Nationality', hintText: 'Filipino'),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return null;
                        if (t.length > 40) return 'Max 40 characters';
                        if (!RegExp(r'^[a-zA-Z\s-]+$').hasMatch(t)) {
                          return 'Letters, spaces, hyphen only';
                        }
                        return null;
                      },
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
                        inputFormatters: [
                          DateInputFormatter(),
                          LengthLimitingTextInputFormatter(8),
                        ],
                        onChanged: (_) => _recomputeNights(),
                        decoration: InputDecoration(
                          labelText: 'Arrival Date *',
                          hintText: 'MM/DD/YY',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.calendar_today_rounded, size: 20),
                            onPressed: () => _pickDate(_arrivalDateController),
                          ),
                        ),
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return 'Arrival date required';
                          if (_parseStrictDateMMDDYY(t) == null) return 'Invalid date (MM/DD/YY)';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _departureDateController,
                        inputFormatters: [
                          DateInputFormatter(),
                          LengthLimitingTextInputFormatter(8),
                        ],
                        onChanged: (_) => _recomputeNights(),
                        decoration: InputDecoration(
                          labelText: 'Departure Date',
                          hintText: 'MM/DD/YY',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.calendar_today_rounded, size: 20),
                            onPressed: () => _pickDate(_departureDateController),
                          ),
                        ),
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return null;
                          final dep = _parseStrictDateMMDDYY(t);
                          if (dep == null) return 'Invalid date (MM/DD/YY)';
                          final arr = _parseStrictDateMMDDYY(_arrivalDateController.text);
                          if (arr != null && dep.isBefore(arr)) {
                            return 'Departure must not be earlier than arrival';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _nightsController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        onChanged: (_) => _recomputeTotal(),
                        decoration: const InputDecoration(labelText: 'No. of Nights', hintText: '1'),
                        validator: (v) {
                          final n = int.tryParse(v?.trim() ?? '');
                          if (n == null || n < 1 || n > 365) return '1-365';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _roomTypeController,
                        style: const TextStyle(fontSize: 13),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s-]')),
                          LengthLimitingTextInputFormatter(40),
                        ],
                        decoration: const InputDecoration(labelText: 'Room Type / No. *', hintText: 'e.g. RY or Rm 001'),
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return 'Room type required';
                          if (t.length > 40) return 'Max 40 characters';
                          if (!RegExp(r'^[a-zA-Z0-9\s-]+$').hasMatch(t)) {
                            return 'Letters, numbers, spaces, hyphen only';
                          }
                          return null;
                        },
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
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                        decoration: const InputDecoration(labelText: 'Adults', hintText: '2'),
                        validator: (v) {
                          final a = int.tryParse(v?.trim() ?? '');
                          if (a == null || a < 0 || a > 50) return '0-50';
                          final c = int.tryParse(_childrenController.text.trim()) ?? 0;
                          if (a + c < 1) return 'Min 1 person';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _childrenController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                        decoration: const InputDecoration(labelText: 'Children', hintText: '0'),
                        validator: (v) {
                          final c = int.tryParse(v?.trim() ?? '');
                          if (c == null || c < 0 || c > 50) return '0-50';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _plateNumberController,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s-]')),
                          LengthLimitingTextInputFormatter(12),
                        ],
                        decoration: const InputDecoration(labelText: 'Plate No.', hintText: 'ABC-1234'),
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return null;
                          if (t.length > 12) return 'Max 12 chars';
                          if (!RegExp(r'^[a-zA-Z0-9\s-]+$').hasMatch(t)) {
                            return 'Letters, numbers, hyphen only';
                          }
                          return null;
                        },
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
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                          LengthLimitingTextInputFormatter(10),
                        ],
                        onChanged: (_) => _recomputeTotal(),
                        decoration: const InputDecoration(labelText: 'Rate / Night (₱)', hintText: '3730'),
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return null;
                          final n = double.tryParse(t);
                          if (n == null || n < 0 || n > 1000000) return '0-1,000,000';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _totalStayController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                          LengthLimitingTextInputFormatter(10),
                        ],
                        decoration: const InputDecoration(labelText: 'Total Stay (₱)', hintText: 'Computed if blank'),
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return null;
                          final n = double.tryParse(t);
                          if (n == null || n < 0 || n > 1000000) return '0-1,000,000';
                          return null;
                        },
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
                        inputFormatters: [
                          DateInputFormatter(),
                          LengthLimitingTextInputFormatter(8),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Activity Date *',
                          hintText: 'MM/DD/YY',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.calendar_today_rounded, size: 20),
                            onPressed: () => _pickDate(_arrivalDateController),
                          ),
                        ),
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return 'Activity date required';
                          if (_parseStrictDateMMDDYY(t) == null) return 'Invalid date (MM/DD/YY)';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _activityTitleController,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(60),
                        ],
                        decoration: const InputDecoration(labelText: 'Activity Title *', hintText: 'Boatride to falls with meal'),
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return 'Title required';
                          if (t.length > 60) return 'Max 60 characters';
                          return null;
                        },
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
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        onChanged: (_) => _recomputeTotal(),
                        decoration: const InputDecoration(labelText: 'Pax', hintText: '1'),
                        validator: (v) {
                          final p = int.tryParse(v?.trim() ?? '');
                          if (p == null || p < 1 || p > 100) return '1-100';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _pricePerPaxController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                          LengthLimitingTextInputFormatter(10),
                        ],
                        onChanged: (_) => _recomputeTotal(),
                        decoration: const InputDecoration(labelText: 'Price / Pax (₱)', hintText: '2000'),
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return null;
                          final p = double.tryParse(t);
                          if (p == null || p < 0 || p > 1000000) return '0-1,000,000';
                          return null;
                        },
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
                      initialValue: _bookingSource,
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
                      initialValue: _paymentMethod,
                      decoration: const InputDecoration(labelText: 'Payment Method'),
                      items: ['Cash', 'GCash', 'Bank Transfer', 'Other']
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
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'[<>{}[\]\\|^`~$%*=+;]')),
                        LengthLimitingTextInputFormatter(200),
                      ],
                      decoration: const InputDecoration(labelText: 'Card Notes / Remarks', hintText: 'e.g. Paid, Agoda paid'),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return null;
                        if (t.length > 200) return 'Max 200 characters';
                        if (RegExp(r'[<>{}[\]\\|^`~$%*=+;]').hasMatch(t) || RegExp(r'<[^>]*>|javascript:', caseSensitive: false).hasMatch(t)) {
                          return 'HTML and special characters are forbidden';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _checkedInByController,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\u00C0-\u024F\u1E00-\u1EFF\s.'-]")),
                        LengthLimitingTextInputFormatter(60),
                      ],
                      decoration: const InputDecoration(labelText: 'Checked In By (Staff)', hintText: 'Staff Maria'),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return null;
                        if (t.length < 2 || t.length > 60) return '2-60 characters';
                        if (!RegExp(r"^[a-zA-Z\u00C0-\u024F\u1E00-\u1EFF\s.'-]+$").hasMatch(t)) {
                          return 'Letters, spaces, period, hyphen only';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Section: Attach Photo (Registration Card / Receipt) - Optional
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.image_outlined, size: 20, color: AppTheme.primaryAccent),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Attach Photo (Registration Card / Receipt) - Optional',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Accepts JPG, PNG, WEBP (Max 10 MB). Stored for record-keeping and audit.',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 14),

                    if (_attachedPhotoFile != null) ...[
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              _attachedPhotoFile!,
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.black.withOpacity(0.65),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                iconSize: 16,
                                icon: const Icon(Icons.close_rounded, color: Colors.white),
                                tooltip: 'Remove',
                                onPressed: _isUploadingPhoto ? null : _removeAttachedPhoto,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_isUploadingPhoto)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              SizedBox(width: 8),
                              Text('Uploading photo...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
                            ],
                          ),
                        )
                      else if (_uploadedPhotoUrl != null)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, size: 16, color: Colors.green),
                              SizedBox(width: 6),
                              Text('Photo uploaded successfully', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                            ],
                          ),
                        ),
                    ] else ...[
                      ElevatedButton.icon(
                        onPressed: _isUploadingPhoto ? null : () => _showAddPhotoBottomSheet(),
                        icon: const Icon(Icons.image_outlined, size: 18),
                        label: const Text('Add Photo', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          foregroundColor: Theme.of(context).colorScheme.primary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],

                    if (_photoError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _photoError!,
                        style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
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
                        onPressed: (_isLoading || _isUploadingPhoto) ? null : () => _submitRecord(addAnother: true),
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
                        onPressed: (_isLoading || _isUploadingPhoto) ? null : () => _submitRecord(addAnother: false),
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
