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
  List<String> _timeSlots = ['09:00 AM'];
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
      
      if (act['timeSlots'] is List) {
        _timeSlots = List<String>.from(act['timeSlots']);
      }
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

  void _addTimeSlot() {
    setState(() {
      _timeSlots.add('12:00 PM');
    });
  }
  
  void _updateTimeSlot(int index, String value) {
    setState(() {
      _timeSlots[index] = value;
    });
  }

  void _removeTimeSlot(int index) {
    setState(() {
      _timeSlots.removeAt(index);
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
    final pax = int.tryParse(paxStr);
    
    if (pax == null || pax <= 0 || pax > 999) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Max capacity must be between 1 and 999.')));
      return;
    }

    if (_imageUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please upload at least one image.')));
      return;
    }

    if (_timeSlots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add at least one time slot.')));
      return;
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
        'timeSlots': _timeSlots,
        'timestamp': ServerValue.timestamp,
      });

      if (mounted) {
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
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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

                  const Text('AVAILABLE TIME SLOTS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const Text('Guests will choose one of these times.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ..._timeSlots.asMap().entries.map((e) {
                        final idx = e.key;
                        return Container(
                          width: 140,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  initialValue: e.value,
                                  onChanged: (val) => _updateTimeSlot(idx, val),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 8),
                                  ),
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _removeTimeSlot(idx),
                              )
                            ],
                          ),
                        );
                      }),
                      OutlinedButton.icon(
                        onPressed: _addTimeSlot,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Time'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
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
            color: Colors.grey[50],
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
