import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class ActivityEditSheet extends StatefulWidget {
  final Map? existingActivity;
  final String? activityKey;

  const ActivityEditSheet({
    super.key,
    this.existingActivity,
    this.activityKey,
  });

  @override
  State<ActivityEditSheet> createState() => _ActivityEditSheetState();
}

class _ActivityEditSheetState extends State<ActivityEditSheet> {
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _maxPaxController = TextEditingController();
  final _descController = TextEditingController();

  List<String> _imageUrls = [];
  bool _is24Hours = false;
  TimeOfDay _availableFrom = const TimeOfDay(hour: 7, minute: 0); // 07:00 AM default
  TimeOfDay _availableUntil = const TimeOfDay(hour: 16, minute: 0); // 04:00 PM default
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingActivity != null) {
      final act = widget.existingActivity!;
      _titleController.text = act['title'] ?? '';
      _priceController.text = (act['price'] ?? '').toString();
      _maxPaxController.text = (act['maxPax'] ?? '').toString();
      _descController.text = act['description'] ?? '';
      
      if (act['imageUrls'] is List) {
        _imageUrls = List<String>.from(act['imageUrls']);
      }
      
      _is24Hours = act['is24Hours'] == true;

      final fromStr = act['availableFrom']?.toString();
      final toStr = act['availableTo']?.toString();
      if (fromStr != null && fromStr.isNotEmpty) {
        _availableFrom = _parseTimeString(fromStr) ?? _availableFrom;
      }
      if (toStr != null && toStr.isNotEmpty) {
        _availableUntil = _parseTimeString(toStr) ?? _availableUntil;
      }

      // Fallback: parse from existing timeSlots if availableFrom/To not present
      if (fromStr == null && act['timeSlots'] is List && (act['timeSlots'] as List).isNotEmpty) {
        final slots = List<String>.from(act['timeSlots']);
        if (slots.length == 1) {
          _availableFrom = _parseTimeString(slots.first) ?? _availableFrom;
        } else if (slots.length >= 2) {
          _availableFrom = _parseTimeString(slots.first) ?? _availableFrom;
          _availableUntil = _parseTimeString(slots.last) ?? _availableUntil;
        }
      }

      // If title or description indicates 24/7 or 12:00 AM - 11:59 PM
      if (_availableFrom.hour == 0 && _availableFrom.minute == 0 &&
          _availableUntil.hour == 23 && _availableUntil.minute == 59) {
        _is24Hours = true;
      }
    }
  }

  static TimeOfDay? _parseTimeString(String s) {
    try {
      final trimmed = s.trim().toUpperCase();
      final parts = trimmed.split(' ');
      if (parts.length != 2) return null;
      final timeParts = parts[0].split(':');
      int hour = int.parse(timeParts[0]);
      int minute = int.parse(timeParts[1]);
      final period = parts[1];
      if (period == 'PM' && hour < 12) hour += 12;
      if (period == 'AM' && hour == 12) hour = 0;
      return TimeOfDay(hour: hour, minute: minute);
    } catch (_) {
      return null;
    }
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final hourOfPeriod = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    final hStr = hourOfPeriod.toString().padLeft(2, '0');
    final mStr = t.minute.toString().padLeft(2, '0');
    return '$hStr:$mStr $period';
  }

  int _timeToMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _pickFromTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _availableFrom,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _availableFrom = picked);
    }
  }

  Future<void> _pickUntilTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _availableUntil,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _availableUntil = picked);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _maxPaxController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _uploadImages() async {
    final picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage();
    if (images.isEmpty) return;

    setState(() => _isLoading = true);
    
    List<String> newUrls = List.from(_imageUrls);
    
    for (var image in images) {
      try {
        final request = http.MultipartRequest('POST', Uri.parse('https://api.cloudinary.com/v1_1/dnv6ezitm/image/upload'))
          ..fields['upload_preset'] = 'resort_unsigned'
          ..files.add(await http.MultipartFile.fromPath('file', image.path));

        final response = await request.send().timeout(const Duration(seconds: 30));
        if (response.statusCode == 200) {
          final resData = await response.stream.bytesToString();
          final data = json.decode(resData);
          newUrls.add(data['secure_url']);
        }
      } catch (e) {
        debugPrint("Error uploading image: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image upload failed: $e')));
        }
      }
    }

    if (mounted) {
      setState(() {
        _imageUrls = newUrls;
        _isLoading = false;
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _imageUrls.removeAt(index);
    });
  }

  Future<void> _saveActivity() async {
    final title = _titleController.text.trim();
    final priceStr = _priceController.text.trim();
    final paxStr = _maxPaxController.text.trim();
    final desc = _descController.text.trim();

    if (title.isEmpty || priceStr.isEmpty || paxStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill in title, price, and max capacity.')));
      return;
    }

    final price = num.tryParse(priceStr);
    if (price == null || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid non-negative price.')));
      return;
    }

    final pax = int.tryParse(paxStr);
    if (pax == null || pax <= 0 || pax > 999) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Max capacity must be between 1 and 999.')));
      return;
    }

    if (_imageUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please upload at least one image.')));
      return;
    }

    // Time validation
    String savedFrom;
    String savedUntil;
    List<String> savedTimeSlots;

    if (_is24Hours) {
      savedFrom = '12:00 AM';
      savedUntil = '11:59 PM';
      savedTimeSlots = ['12:00 AM', '11:59 PM'];
    } else {
      final fromMin = _timeToMinutes(_availableFrom);
      final untilMin = _timeToMinutes(_availableUntil);

      if (fromMin == untilMin) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Available From and Available Until cannot be equal.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (untilMin < fromMin) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Available Until cannot be earlier than Available From. For overnight activities, please use the "Available 24/7" switch.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      savedFrom = _formatTimeOfDay(_availableFrom);
      savedUntil = _formatTimeOfDay(_availableUntil);
      savedTimeSlots = [savedFrom, savedUntil];
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);

    try {
      final actRef = widget.activityKey != null 
        ? FirebaseDatabase.instance.ref('properties/$uid/activities/${widget.activityKey}')
        : FirebaseDatabase.instance.ref('properties/$uid/activities').push();

      await actRef.update({
        'title': title,
        'description': desc,
        'price': price,
        'maxPax': pax,
        'imageUrls': _imageUrls,
        'is24Hours': _is24Hours,
        'availableFrom': savedFrom,
        'availableTo': savedUntil,
        'timeSlots': savedTimeSlots,
        'timestamp': ServerValue.timestamp,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.activityKey != null ? 'Activity updated successfully!' : 'Activity added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving activity: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.activityKey != null ? 'Edit Activity' : 'Add New Activity',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ACTIVITY PHOTOS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ..._imageUrls.asMap().entries.map((e) {
                        final idx = e.key;
                        final url = e.value;
                        return Stack(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () => _removeImage(idx),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                                ),
                              ),
                            )
                          ],
                        );
                      }),
                      GestureDetector(
                        onTap: _isLoading ? null : _uploadImages,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[400]!, style: BorderStyle.solid),
                          ),
                          child: _isLoading
                              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                              : const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.upload, color: Colors.grey),
                                    Text('Add Photo', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  const Text('ACTIVITY TITLE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'e.g. Island Hopping Boat Ride',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('PRICE PER PERSON', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _priceController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: '0',
                                prefixText: '₱ ',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('MAX CAPACITY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _maxPaxController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: 'e.g. 10',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 24/7 Availability Switch
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.grey[300]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Available 24/7',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                _is24Hours
                                    ? 'Activity is available all day (e.g., Karaoke, 24-hr access)'
                                    : 'Specific operating hours apply',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _is24Hours,
                          activeColor: Theme.of(context).colorScheme.primary,
                          onChanged: (val) {
                            setState(() => _is24Hours = val);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (!_is24Hours) ...[
                    const Text('ACTIVITY OPERATING HOURS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 4),
                    const Text('Tap each field to choose hours with the time picker.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Available From', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: _pickFromTime,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey[400]!),
                                    borderRadius: BorderRadius.circular(10),
                                    color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _formatTimeOfDay(_availableFrom),
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                      ),
                                      const Icon(Icons.access_time, size: 18, color: Colors.grey),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Available Until', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: _pickUntilTime,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey[400]!),
                                    borderRadius: BorderRadius.circular(10),
                                    color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _formatTimeOfDay(_availableUntil),
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                      ),
                                      const Icon(Icons.access_time, size: 18, color: Colors.grey),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Available all day (24/7, 12:00 AM - 11:59 PM)',
                              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  const Text('DESCRIPTION', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Describe the activity...',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Container(
            padding: const EdgeInsets.all(16.0),
            color: isDark ? theme.cardColor : Colors.grey[50],
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveActivity,
                    child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Save Activity'),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
