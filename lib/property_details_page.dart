import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'chat_page.dart';
import 'policies_property_page.dart';
import 'theme_provider.dart';
import 'theme.dart';

class PropertyDetailsPage extends StatefulWidget {
  final String propertyName;
  final Map propertyData;
  final String ownerUid;
  final bool isOwner;

  const PropertyDetailsPage({
    super.key,
    required this.propertyName,
    required this.propertyData,
    required this.ownerUid,
    this.isOwner = false,
  });

  @override
  State<PropertyDetailsPage> createState() => _PropertyDetailsPageState();
}

class _PropertyDetailsPageState extends State<PropertyDetailsPage> {
  final String _cloudName = "dnv6ezitm";
  final String _uploadPreset = "resort_unsigned";

  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isUploading = false;
  bool _isReady = false;

  Map _currentData = {};

  final Map<String, Map<String, dynamic>> _detailedAddons = {
    'Boat ride to falls': {
      'price': 1200,
      'unit': 'trip',
      'desc': 'Guided trip to the falls'
    },
    'Kayak': {
      'price': 1200,
      'unit': 'hour',
      'desc': 'Single/Double kayak rental'
    },
    'Dinner': {'price': 400, 'unit': 'set', 'desc': 'Local cuisine buffet'},
    'Lunch': {'price': 400, 'unit': 'set', 'desc': 'Premium plated lunch'},
    'Breakfast': {'price': 300, 'unit': 'set', 'desc': 'Fresh continental set'},
    'Extra Bed': {
      'price': 200,
      'unit': 'night',
      'desc': 'Foldable mattress set'
    },
  };

  @override
  void initState() {
    super.initState();
    _currentData = widget.propertyData;
    
    if (_currentData['addonPrices'] != null && _currentData['addonPrices'] is Map) {
      Map prices = _currentData['addonPrices'];
      _detailedAddons.forEach((key, value) {
        if (prices[key] != null) {
          value['price'] = int.tryParse(prices[key].toString()) ?? value['price'];
        }
      });
    }

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _isReady = true);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<String> _parseList(dynamic data) {
    if (data == null) return [];
    if (data is List)
      return data.where((e) => e != null).map((e) => e.toString()).toList();
    if (data is Map) {
      var sortedKeys = data.keys.toList()
        ..sort((a, b) => a.toString().compareTo(b.toString()));
      return sortedKeys.map((k) => data[k].toString()).toList();
    }
    return [];
  }

  Future<String?> _uploadToCloudinary(File file, {bool isVideo = false}) async {
    if (!mounted) return null;
    setState(() => _isUploading = true);
    try {
      final String resourceType = isVideo ? "video" : "image";
      final url = Uri.parse(
          "https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/upload");
      final request = http.MultipartRequest("POST", url)
        ..fields['upload_preset'] = _uploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', file.path));
      final response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        return jsonDecode(responseData)['secure_url'];
      }
      return null;
    } catch (e) {
      return null;
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickAndUploadMedia({bool isVideo = false}) async {
    final picker = ImagePicker();
    final user = FirebaseAuth.instance.currentUser;
    if (isVideo) {
      final XFile? file = await picker.pickVideo(source: ImageSource.gallery);
      if (file != null) {
        final String? url =
            await _uploadToCloudinary(File(file.path), isVideo: true);
        if (url != null) {
          List<String> vids = _parseList(_currentData['videoUrls']);
          vids.add(url);
          await FirebaseDatabase.instance
              .ref("properties/${user?.uid}")
              .update({'videoUrls': vids});
        }
      }
    } else {
      final List<XFile> files = await picker.pickMultiImage(imageQuality: 70);
      if (files.isNotEmpty) {
        List<String> imgs = _parseList(_currentData['imageUrls']);
        for (var file in files) {
          final String? url = await _uploadToCloudinary(File(file.path));
          if (url != null) imgs.add(url);
        }
        await FirebaseDatabase.instance
            .ref("properties/${user?.uid}")
            .update({'imageUrls': imgs});
      }
    }
  }

  Future<bool> _hasActiveBooking(String activityId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final snap = await FirebaseDatabase.instance
        .ref("bookings")
        .orderByChild("touristUid")
        .equalTo(user.uid)
        .get();
    if (snap.exists && snap.value is Map) {
      Map bookings = snap.value as Map;
      return bookings.values.any((b) =>
          b['activityId'] == activityId &&
          (b['status'] == 'Pending' || b['status'] == 'Confirmed'));
    }
    return false;
  }

  void _showRoomDetailsSheet(String activityId, Map activity) {
    List<String> roomImages = _parseList(activity['imageUrls']);
    String? roomVideo = activity['videoUrl'];
    final List<Map<String, dynamic>> roomMedia = [
      ...roomImages.map((u) => {'url': u, 'type': 'image'}),
      if (roomVideo != null) {'url': roomVideo, 'type': 'video'}
    ];

    int localPage = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[600],
                      borderRadius: BorderRadius.circular(2))),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    if (roomMedia.isNotEmpty)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: SizedBox(
                              height: 250,
                              child: PageView.builder(
                                itemCount: roomMedia.length,
                                onPageChanged: (idx) =>
                                    setModalState(() => localPage = idx),
                                itemBuilder: (context, i) => GestureDetector(
                                  onTap: () =>
                                      _openFullScreenMedia(roomMedia, i),
                                  child: roomMedia[i]['type'] == 'video'
                                      ? VideoPlayerWidget(
                                          url: roomMedia[i]['url'])
                                      : Image.network(roomMedia[i]['url'],
                                          fit: BoxFit.cover,
                                          errorBuilder: (c, e, s) => Container(
                                              color: Colors.grey[200],
                                              child: const Icon(
                                                  Icons.broken_image))),
                                ),
                              ),
                            ),
                          ),
                          if (roomMedia.length > 1)
                            Positioned(
                              top: 16,
                              right: 16,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(20)),
                                child: Text(
                                  "${localPage + 1} / ${roomMedia.length}",
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: Text(activity['title'] ?? 'Room Details',
                                style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5))),
                        Text('₱${activity['price']}',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.secondary,
                                fontWeight: FontWeight.w900,
                                fontSize: 22)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (activity['category'] != null)
                          _buildSmallChip(context, activity['category']),
                        if (activity['location'] != null)
                          _buildSmallChip(context, activity['location']),
                        if (activity['maxPax'] != null)
                          _buildSmallChip(
                              context, "Max Pax: ${activity['maxPax']}"),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[100],
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.secondary.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.people, size: 18, color: Theme.of(context).colorScheme.secondary),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('CAPACITY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey)),
                                      Text('${activity['maxPax'] ?? '—'} Persons', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                                    ],
                                  ),
                                )
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[100],
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.info_outline, size: 18, color: Colors.blue),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('PAYMENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey)),
                                      Text('GCash Available', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                                    ],
                                  ),
                                )
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    const Text('ABOUT THIS ROOM',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 0.8)),
                    const SizedBox(height: 10),
                    Text(
                        (activity['description'] == null || activity['description'].toString().trim().isEmpty)
                            ? 'Experience a relaxing stay with premium amenities. Perfect for unwinding and creating wonderful memories.'
                            : activity['description'],
                        style: const TextStyle(fontSize: 14, height: 1.6, color: Colors.grey)),
                    const SizedBox(height: 32),
                    const Text("WHAT'S INCLUDED",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 0.8)),
                    const SizedBox(height: 12),
                    Builder(
                      builder: (context) {
                        List<String> amenities = _parseList(activity['amenities'] ?? activity['inclusions']);
                        if (amenities.isEmpty) {
                          amenities = ['Air Conditioning', 'Free WiFi', 'Private Bathroom', 'Basic Toiletries'];
                        }
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 3.5,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: amenities.length,
                          itemBuilder: (context, i) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[100],
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle, size: 16, color: Theme.of(context).colorScheme.secondary),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(amenities[i], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                            );
                          },
                        );
                      }
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PoliciesPropertyPage(
                              propertyData: widget.propertyData,
                              propertyId: widget.ownerUid,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.info),
                      label: const Text('View Resort Policies & Info', style: TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryAccent,
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text("AVAILABLE ADD-ONS",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 0.8)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        'Boat ride (₱1200)',
                        'Kayak (₱1200)',
                        'Meals (From ₱300)',
                        'Extra Bed (₱200)'
                      ].map((addon) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[100],
                          border: Border.all(color: Colors.grey.withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(addon, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey)),
                      )).toList(),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
              if (!widget.isOwner)
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _checkAndStartBooking(activityId, activity);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 60),
                    ),
                    child: const Text('BOOK THIS ROOM NOW',
                        style: TextStyle(letterSpacing: 1.2)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showManageMediaSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(builder: (context, setModalState) {
        final imgs = _parseList(_currentData['imageUrls']);
        final vids = _parseList(_currentData['videoUrls']);
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(5)),
                    margin: const EdgeInsets.only(bottom: 20)),
                const Text('Manage Media',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      if (imgs.isNotEmpty) ...[
                        const Text("Photos",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8),
                          itemCount: imgs.length,
                          itemBuilder: (context, i) => Stack(children: [
                            ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(imgs[i],
                                    fit: BoxFit.cover,
                                    height: 100,
                                    width: 100,
                                    errorBuilder: (c, e, s) =>
                                        Container(color: Colors.grey[200]))),
                            Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                    onTap: () async {
                                      imgs.removeAt(i);
                                      await FirebaseDatabase.instance
                                          .ref("properties/${widget.ownerUid}")
                                          .update({'imageUrls': imgs});
                                      setModalState(() {});
                                    },
                                    child: const CircleAvatar(
                                        radius: 10,
                                        backgroundColor: AppTheme.primaryAccent,
                                        child: Icon(Icons.close,
                                            size: 12, color: Colors.white)))),
                          ]),
                        ),
                      ],
                      if (vids.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text("Videos",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                  childAspectRatio: 1.5),
                          itemCount: vids.length,
                          itemBuilder: (context, i) => Stack(children: [
                            Container(
                                decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(12)),
                                child: const Center(
                                    child: Icon(Icons.play_circle,
                                        color: Colors.white, size: 30))),
                            Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                    onTap: () async {
                                      vids.removeAt(i);
                                      await FirebaseDatabase.instance
                                          .ref("properties/${widget.ownerUid}")
                                          .update({'videoUrls': vids});
                                      setModalState(() {});
                                    },
                                    child: const CircleAvatar(
                                        radius: 10,
                                        backgroundColor: AppTheme.primaryAccent,
                                        child: Icon(Icons.close,
                                            size: 12, color: Colors.white)))),
                          ]),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  void _editTextField(String field, String label, String currentVal,
      {int maxLines = 1, bool isNumber = false}) {
    final controller = TextEditingController(text: currentVal);
    final formKey = GlobalKey<FormState>();
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('Edit $label'),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: controller,
                  maxLines: maxLines,
                  keyboardType:
                      isNumber ? TextInputType.number : TextInputType.text,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(
                        r'[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]',
                        unicode: true))
                  ],
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    dynamic val = isNumber
                        ? (int.tryParse(controller.text) ?? 0)
                        : controller.text.trim();
                    await FirebaseDatabase.instance
                        .ref("properties/${widget.ownerUid}")
                        .update({field: val});
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryAccent),
                  child: const Text('Save'),
                )
              ],
            ));
  }

  bool _isOverlapping(
      DateTime startA, DateTime endA, DateTime startB, DateTime endB) {
    return startA.isBefore(endB) && endA.isAfter(startB);
  }

  Future<bool> _checkBookingConflict(
      String activityId, DateTime startDate, int nights) async {
    final snap = await FirebaseDatabase.instance
        .ref("bookings")
        .orderByChild("activityId")
        .equalTo(activityId)
        .get();

    if (!snap.exists) return false;

    Map<String, dynamic> allBookings = {};

    final value = snap.value;

    if (value is Map) {
      allBookings = Map<String, dynamic>.from(value);
    } else if (value is List) {
      for (int i = 0; i < value.length; i++) {
        final item = value[i];
        if (item != null) {
          allBookings[i.toString()] = item;
        }
      }
    }

    DateTime endA = startDate.add(Duration(days: nights));

    for (var b in allBookings.values) {
      if (b is! Map) continue;

      String status = (b['status'] ?? '').toString().trim().toLowerCase();
      // Only 'confirmed' (and 'checked in') block new bookings
      if (status != 'confirmed' && status != 'checked in') continue;

      try {
        DateTime startB = DateFormat('MMM dd, yyyy').parse(b['bookingDate']);
        int nightsB = int.tryParse(b['nights'].toString()) ?? 1;
        DateTime endB = startB.add(Duration(days: nightsB));

        if (_isOverlapping(startDate, endA, startB, endB)) {
          return true;
        }
      } catch (e) {/* skip malformed */}
    }
    return false;
  }

  Future<List<DateTime>> _fetchBookedDates(String activityId) async {
    final snap = await FirebaseDatabase.instance
        .ref("bookings")
        .orderByChild("activityId")
        .equalTo(activityId)
        .get();

    List<DateTime> bookedDates = [];
    if (snap.exists) {
      Map allBookings = {};
      final value = snap.value;
      if (value is Map) {
        allBookings = value;
      } else if (value is List) {
        for (int i = 0; i < value.length; i++) {
          if (value[i] != null) allBookings[i.toString()] = value[i];
        }
      }

      for (var b in allBookings.values) {
        if (b is! Map) continue;
        String status = (b['status'] ?? '').toString().trim().toLowerCase();
        if (status != 'confirmed' && status != 'checked in') continue;

        try {
          DateTime start = DateFormat('MMM dd, yyyy').parse(b['bookingDate']);
          int nights = int.tryParse(b['nights'].toString()) ?? 1;
          for (int i = 0; i < nights; i++) {
            bookedDates.add(DateUtils.dateOnly(start.add(Duration(days: i))));
          }
        } catch (e) {}
      }
    }
    return bookedDates;
  }

  Future<void> _checkAndStartBooking(String activityId, Map activity) async {
    if (widget.isOwner) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    List<DateTime> bookedDates = [];
    try {
      bookedDates = await _fetchBookedDates(activityId);
    } catch (e) {
      // Ignore error, allow booking with empty booked dates
    } finally {
      if (mounted) Navigator.pop(context); // hide loading
    }

    DateTime firstDate = DateUtils.dateOnly(DateTime.now());
    DateTime initialDate = firstDate;

    // Ensure initial date is not already booked
    while (bookedDates.any((d) => DateUtils.isSameDay(d, initialDate))) {
      initialDate = initialDate.add(const Duration(days: 1));
    }

    if (!mounted) return;

    DateTime? date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: firstDate.add(const Duration(days: 365)),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      selectableDayPredicate: (day) {
        // Disable dates that are already booked
        return !bookedDates.any((d) => DateUtils.isSameDay(d, day));
      },
      builder: (context, child) {
        final brightness = Theme.of(context).brightness;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: brightness == Brightness.dark
                ? const ColorScheme.dark(
                    primary: AppTheme.secondaryAccent,
                    onPrimary: Colors.black,
                    surface: AppTheme.darkSurface,
                    onSurface: Colors.white,
                  )
                : const ColorScheme.light(
                    primary: AppTheme.primaryAccent,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Colors.black,
                  ),
            dialogTheme: DialogThemeData(
                backgroundColor: brightness == Brightness.dark
                    ? AppTheme.darkBg
                    : Colors.white),
          ),
          child: child!,
        );
      },
    );

    if (date != null) {
      // Preliminary conflict check for the selected range (1 night initially)
      bool conflict = await _checkBookingConflict(activityId, date, 1);
      if (conflict) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Room Unavailable'),
            content: Text(
                'This room is already reserved for ${DateFormat('MMM dd, yyyy').format(date)}. Please choose another date.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'))
            ],
          ),
        );
        return;
      }
      _confirmBooking(activityId, activity, date);
    }
  }

  void _confirmBooking(String activityId, Map activity, DateTime date) {
    int nights = 1;
    String method = 'GCash (30% Down)';
    String? receipt;
    Map<String, int> selectedAddons = {}; // Addon Name -> Quantity

    showDialog(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, setS) {
              double baseRoomTotal =
                  (double.tryParse(activity['price'].toString()) ?? 0) * nights;

              double addonTotal = 0;
              selectedAddons.forEach((name, qty) {
                addonTotal += (_detailedAddons[name]!['price'] as int) * qty;
              });

              double total = baseRoomTotal + addonTotal;
              double paymentAmount =
                  method.contains('30%') ? total * 0.3 : total;

              return AlertDialog(
                title: const Text('Confirm Booking'),
                content: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.9,
                  child: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(activity['title'] ?? 'Room',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 18)),
                          const SizedBox(height: 16),
                          const Text('Duration of Stay:',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                    onPressed: nights > 1
                                        ? () => setS(() => nights--)
                                        : null,
                                    icon: const Icon(
                                        Icons.remove_circle_outline)),
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16),
                                    child: Text('$nights Nights',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold))),
                                IconButton(
                                    onPressed: () async {
                                      if (nights >= 10) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content: Text(
                                                      'Maximum booking duration is 10 nights.')));
                                        }
                                        return;
                                      }
                                      bool conflict =
                                          await _checkBookingConflict(
                                              activityId, date, nights + 1);
                                      if (conflict) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content: Text(
                                                      'Cannot extend stay: Date range overlaps with another booking.')));
                                        }
                                      } else {
                                        setS(() => nights++);
                                      }
                                    },
                                    icon: const Icon(Icons.add_circle_outline)),
                              ]),
                          const Divider(height: 32),
                          const Text('Available Add-ons:',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 8),
                          ..._detailedAddons.entries.map((entry) {
                            String name = entry.key;
                            Map<String, dynamic> info = entry.value;
                            int qty = selectedAddons[name] ?? 0;
                            int maxQty = name == 'Extra Bed' ? 3 : 10;

                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(name,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14)),
                                            Text(
                                                '${info['desc']} (₱${info['price']}/${info['unit']})',
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey)),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                              iconSize: 20,
                                              onPressed: qty > 0
                                                  ? () => setS(() =>
                                                      selectedAddons[name] =
                                                          qty - 1)
                                                  : null,
                                              icon: const Icon(
                                                  Icons.remove_circle_outline)),
                                          Text('$qty',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold)),
                                          IconButton(
                                              iconSize: 20,
                                              onPressed: qty < maxQty
                                                  ? () => setS(() =>
                                                      selectedAddons[name] =
                                                          qty + 1)
                                                  : null,
                                              icon: const Icon(
                                                  Icons.add_circle_outline)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                          const Divider(height: 32),
                          DropdownButtonFormField<String>(
                            initialValue: method,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Payment Method'),
                            items: [
                              DropdownMenuItem(
                                  value: 'GCash (30% Down)',
                                  child: Text(
                                      '30% Downpayment (₱${(total * 0.3).toStringAsFixed(2)})',
                                      overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(
                                  value: 'GCash (100% Full)',
                                  child: Text(
                                      '100% Full Payment (₱${total.toStringAsFixed(2)})',
                                      overflow: TextOverflow.ellipsis))
                            ],
                            onChanged: (v) => setS(() {
                              method = v!;
                              receipt = null;
                            }),
                          ),
                          const SizedBox(height: 16),
                          Text('Pay ₱${paymentAmount.toStringAsFixed(2)} to:'),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .secondary
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12)),
                            child: SelectableText(
                                'GCash: ${_currentData['gcashNumber'] ?? 'N/A'}\nName: ${_currentData['gcashName'] ?? 'N/A'}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            method.contains('30%')
                                ? 'Remaining balance of ₱${(total * 0.7).toStringAsFixed(2)} to be paid at the resort.'
                                : 'Full payment of ₱${total.toStringAsFixed(2)} covered.',
                            style: const TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: Colors.grey),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final XFile? file = await ImagePicker()
                                  .pickImage(source: ImageSource.gallery);
                              if (file != null) {
                                final url =
                                    await _uploadToCloudinary(File(file.path));
                                if (url != null) setS(() => receipt = url);
                              }
                            },
                            icon: const Icon(Icons.upload_file),
                            label: Text(receipt == null
                                ? 'Upload Receipt'
                                : 'Receipt Uploaded'),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total:',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18)),
                              Text('₱${total.toStringAsFixed(2)}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary)),
                            ],
                          ),
                        ]),
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  ElevatedButton(
                    onPressed: receipt == null
                        ? null
                        : () async {
                            // Final overlap check before writing to database
                            bool conflict = await _checkBookingConflict(
                                activityId, date, nights);
                            if (conflict) {
                              if (context.mounted) {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Booking Conflict'),
                                    content: const Text(
                                        'The selected date range overlaps with an existing confirmed booking. Please try different dates.'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('OK'))
                                    ],
                                  ),
                                );
                              }
                              return;
                            }

                            final user = FirebaseAuth.instance.currentUser;
                            final snap = await FirebaseDatabase.instance
                                .ref("users/${user?.uid}")
                                .get();
                            String name = "Anonymous";
                            String? profilePic;
                            if (snap.exists && snap.value is Map) {
                              final userData = snap.value as Map;
                              name =
                                  "${userData['firstName']} ${userData['lastName']}";
                              profilePic = userData['profilePicUrl'];
                            }

                            List<String> finalAddons = [];
                            selectedAddons.forEach((addon, qty) {
                              if (qty > 0) {
                                finalAddons.add("$addon (x$qty)");
                              }
                            });

                            DatabaseReference newBookingRef = FirebaseDatabase.instance.ref("bookings").push();
                            await newBookingRef.set({
                              'touristUid': user?.uid,
                              'touristName': name,
                              'touristProfilePic': profilePic,
                              'ownerUid': widget.ownerUid,
                              'activityId': activityId,
                              'propertyName': widget.propertyName,
                              'activityTitle': activity['title'],
                              'price': activity['price'],
                              'totalPrice': total,
                              'amountPaid': paymentAmount,
                              'nights': nights,
                              'bookingDate':
                                  DateFormat('MMM dd, yyyy').format(date),
                              'status': 'Pending',
                              'paymentMethod': 'GCash',
                              'paymentOption': method,
                              'gcashReceipt': receipt,
                              'timestamp': ServerValue.timestamp,
                              'selectedAddons': finalAddons,
                            });
                            
                            await FirebaseDatabase.instance
                                .ref("notifications/${widget.ownerUid}")
                                .push()
                                .set({
                              'title': 'New Booking Request',
                              'message':
                                  '$name has requested to book ${activity['title']}.',
                              'type': 'new_booking',
                              'isRead': false,
                              'timestamp': ServerValue.timestamp,
                              'bookingId': newBookingRef.key,
                            });

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Booking request sent successfully!')));
                            }
                          },
                    style: ElevatedButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).colorScheme.secondary,
                        foregroundColor: Colors.black),
                    child: const Text('Book Now'),
                  )
                ],
              );
            }));
  }

  void _openFullScreenMedia(List<Map<String, dynamic>> media, int index) {
    if (media.isEmpty) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => Scaffold(
                  backgroundColor: Colors.black,
                  appBar: AppBar(
                      backgroundColor: Colors.black,
                      iconTheme: const IconThemeData(color: Colors.white)),
                  body: PageView.builder(
                    itemCount: media.length,
                    controller: PageController(initialPage: index),
                    itemBuilder: (context, i) => Center(
                        child: media[i]['type'] == 'video'
                            ? VideoPlayerWidget(url: media[i]['url'])
                            : InteractiveViewer(
                                child: Image.network(media[i]['url'],
                                    errorBuilder: (c, e, s) => const Icon(
                                        Icons.broken_image,
                                        color: Colors.white,
                                        size: 50)))),
                  ),
                )));
  }

  Future<void> _openMaps() async {
    final double? lat =
        double.tryParse(_currentData['latitude']?.toString() ?? '');
    final double? lng =
        double.tryParse(_currentData['longitude']?.toString() ?? '');

    if (lat == null || lng == null || (lat == 0 && lng == 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location not set by owner.')));
      return;
    }

    final String googleMapsUrl =
        "https://www.google.com/maps/search/?api=1&query=$lat,$lng";
    final Uri url = Uri.parse(googleMapsUrl);

    final bool canLaunch = await canLaunchUrl(url);
    if (!mounted) return;
    if (canLaunch) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not open maps.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return StreamBuilder<DatabaseEvent>(
        stream: FirebaseDatabase.instance
            .ref("properties/${widget.ownerUid}")
            .onValue,
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.snapshot.exists) {
            _currentData = snapshot.data!.snapshot.value as Map;
          }
          final combined = [
            ..._parseList(_currentData['imageUrls'])
                .map((u) => {'url': u, 'type': 'image'}),
            ..._parseList(_currentData['videoUrls'])
                .map((u) => {'url': u, 'type': 'video'})
          ];

          return Scaffold(
            floatingActionButton: widget.isOwner
                ? null
                : FloatingActionButton.extended(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => ChatPage(
                                otherUserUid: widget.ownerUid,
                                otherUserName: widget.propertyName))),
                    label: const Text('Chat with Owner'),
                    icon: const Icon(Icons.message_rounded),
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    foregroundColor: Colors.black,
                  ),
            body: CustomScrollView(slivers: [
              SliverAppBar(
                expandedHeight: 350,
                pinned: true,
                backgroundColor: Theme.of(context).colorScheme.surface,
                actions: [
                  if (widget.isOwner) ...[
                    IconButton(
                        icon: const Icon(Icons.photo_library),
                        onPressed: _showManageMediaSheet),
                    IconButton(
                        icon: const Icon(Icons.add_a_photo),
                        onPressed: () => _pickAndUploadMedia()),
                    IconButton(
                        icon: const Icon(Icons.video_call),
                        onPressed: () => _pickAndUploadMedia(isVideo: true)),
                  ],
                  IconButton(
                    icon: Icon(themeProvider.themeMode == ThemeMode.dark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded),
                    onPressed: () => themeProvider.toggleTheme(),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(fit: StackFit.expand, children: [
                    if (_isReady && combined.isNotEmpty)
                      PageView.builder(
                        itemCount: combined.length,
                        onPageChanged: (i) => setState(() => _currentPage = i),
                        itemBuilder: (context, i) => GestureDetector(
                          onTap: () => _openFullScreenMedia(combined, i),
                          child: combined[i]['type'] == 'video'
                              ? VideoPlayerWidget(url: combined[i]['url']!)
                              : Image.network(combined[i]['url']!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (c, e, s) =>
                                      Container(color: Colors.grey[200])),
                        ),
                      )
                    else if (_currentData['name']?.toString().contains('Casa Delrio') == true || _currentData['name']?.toString().contains('Casa DelRio') == true)
                      Image.asset('assets/CasaDelRio5.webp', fit: BoxFit.cover)
                    else if (_currentData['name']?.toString().contains('Hotel Ramiro') == true)
                      Image.asset('assets/HotelRamiro5.webp', fit: BoxFit.cover)
                    else if (_currentData['name']?.toString().contains('Nadzville Resort') == true)
                      Image.asset('assets/NadzvilleResort1.jpg', fit: BoxFit.cover)
                    else
                      Container(
                          color: Theme.of(context).colorScheme.primary,
                          child: const Icon(Icons.beach_access_rounded,
                              size: 80, color: Colors.white)),
                    if (_isUploading)
                      const Center(
                          child:
                              CircularProgressIndicator(color: Colors.white)),
                    if (combined.length > 1)
                      Positioned(
                          bottom: 40,
                          left: 0,
                          right: 0,
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                  combined.length,
                                  (i) => Container(
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 4),
                                      height: 8,
                                      width: _currentPage == i ? 24 : 8,
                                      decoration: BoxDecoration(
                                          color: _currentPage == i
                                              ? Colors.white
                                              : Colors.white54,
                                          borderRadius:
                                              BorderRadius.circular(12))))))
                  ]),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(30))),
                  transform: Matrix4.translationValues(0, -30, 0),
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                  child: Text(
                                      _currentData['name'] ??
                                          widget.propertyName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium)),
                              if (widget.isOwner)
                                IconButton(
                                    icon: const Icon(Icons.edit_rounded),
                                    onPressed: () => _editTextField('name',
                                        'Name', _currentData['name'] ?? ''))
                              else
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.map_rounded,
                                          color: Colors.blue),
                                      onPressed: _openMaps,
                                      tooltip: 'View on Map',
                                    ),
                                    StreamBuilder<DatabaseEvent>(
                                      stream: FirebaseDatabase.instance
                                          .ref("reviews/${widget.ownerUid}")
                                          .onValue,
                                      builder: (context, rSnap) {
                                        double rating = 0.0;
                                        int count = 0;
                                        if (rSnap.hasData &&
                                            rSnap.data!.snapshot.exists) {
                                          Map reviews =
                                              rSnap.data!.snapshot.value as Map;
                                          double sum = 0;
                                          reviews.forEach((k, v) =>
                                              sum += (v['rating'] ?? 0));
                                          rating = sum / reviews.length;
                                          count = reviews.length;
                                        }
                                        return Row(
                                          children: [
                                            Icon(Icons.star_rounded,
                                                color: count > 0
                                                    ? Colors.amber
                                                    : Colors.grey,
                                                size: 24),
                                            const SizedBox(width: 4),
                                            Text(
                                                count > 0
                                                    ? rating.toStringAsFixed(1)
                                                    : "0.0",
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 18,
                                                    color: count > 0
                                                        ? null
                                                        : Colors.grey)),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                            ]),
                        const SizedBox(height: 16),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          _chip(_currentData['type'] ?? 'Resort', Colors.blue,
                              'type'),
                          _chip('${_currentData['rooms']} Rooms', Colors.orange,
                              'rooms',
                              isNum: true),
                          _chip('${_currentData['staffCount']} Staff',
                              Colors.green, 'staffCount',
                              isNum: true),
                          if (_currentData['maxCapacity'] != null &&
                              _currentData['maxCapacity'] > 0)
                            _buildSmallChip(context,
                                'Max Capacity: ${_currentData['maxCapacity']}',
                                icon: Icons.people_outline_rounded),
                        ]),
                        const SizedBox(height: 32),
                        Row(children: [
                          Text('About',
                              style: Theme.of(context).textTheme.titleLarge),
                          if (widget.isOwner)
                            IconButton(
                                icon: const Icon(Icons.edit_rounded, size: 20),
                                onPressed: () => _editTextField(
                                    'description',
                                    'Description',
                                    _currentData['description'] ?? '',
                                    maxLines: 4))
                        ]),
                        const SizedBox(height: 12),
                        Text(
                            _currentData['description'] ??
                                'No description provided.',
                            style: Theme.of(context).textTheme.bodyLarge),
                        const SizedBox(height: 32),
                        if (_currentData['latitude'] != null &&
                            _currentData['longitude'] != null &&
                            _currentData['latitude'] != 0 &&
                            _currentData['longitude'] != 0) ...[
                          Row(
                            children: [
                              Icon(Icons.location_on,
                                  color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text('Where you\'ll be',
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            height: 250,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Stack(
                                children: [
                                  FlutterMap(
                                    options: MapOptions(
                                      initialCenter: LatLng(
                                          (_currentData['latitude'] as num)
                                              .toDouble(),
                                          (_currentData['longitude'] as num)
                                              .toDouble()),
                                      initialZoom: 14.0,
                                    ),
                                    children: [
                                      TileLayer(
                                        urlTemplate:
                                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                        userAgentPackageName:
                                            'com.resortsconnectapp',
                                      ),
                                      MarkerLayer(
                                        markers: [
                                          Marker(
                                            point: LatLng(
                                                (_currentData['latitude']
                                                        as num)
                                                    .toDouble(),
                                                (_currentData['longitude']
                                                        as num)
                                                    .toDouble()),
                                            width: 40,
                                            height: 40,
                                            child: const Icon(
                                                Icons.location_pin,
                                                color: Colors.red,
                                                size: 40),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  Positioned(
                                    bottom: 16,
                                    right: 16,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        elevation: 4,
                                      ),
                                      onPressed: () async {
                                        final lat = _currentData['latitude'];
                                        final lng = _currentData['longitude'];
                                        final url = Uri.parse(
                                            'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
                                        if (await canLaunchUrl(url)) {
                                          await launchUrl(url,
                                              mode: LaunchMode
                                                  .externalApplication);
                                        }
                                      },
                                      icon: const Icon(Icons.navigation_rounded,
                                          size: 18),
                                      label: const Text('Get Directions',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                        if (_currentData['amenities'] != null) ...[
                          Text('Amenities',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _parseList(_currentData['amenities'])
                                .map((amenity) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withOpacity(0.05),
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      child: Text(amenity,
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600)),
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 32),
                        ],
                        if (_currentData['checkInTime'] != null ||
                            _currentData['checkOutTime'] != null) ...[
                          Text('House Rules & Policy',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              if (_currentData['checkInTime'] != null)
                                Expanded(
                                    child: _policyItem(
                                        Icons.login_rounded,
                                        'Check-in',
                                        _currentData['checkInTime'])),
                              if (_currentData['checkOutTime'] != null)
                                Expanded(
                                    child: _policyItem(
                                        Icons.logout_rounded,
                                        'Check-out',
                                        _currentData['checkOutTime'])),
                            ],
                          ),
                          if (_currentData['bookingInstructions'] != null &&
                              _currentData['bookingInstructions']
                                  .toString()
                                  .isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                  color: Colors.grey.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(16)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Instructions',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                  const SizedBox(height: 8),
                                  Text(_currentData['bookingInstructions'],
                                      style: const TextStyle(
                                          fontSize: 14, height: 1.4)),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PoliciesPropertyPage(
                                      propertyData: _currentData,
                                      propertyId: widget.ownerUid,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.policy),
                              label: const Text('View Full Policies & Details', style: TextStyle(fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                foregroundColor: Theme.of(context).colorScheme.primary,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                        Text('Available Rooms',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 16),
                      ]),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: StreamBuilder<DatabaseEvent>(
                    stream: FirebaseDatabase.instance
                        .ref("properties/${widget.ownerUid}/roomInventory")
                        .onValue,
                    builder: (context, snap) {
                      if (!snap.hasData || snap.data!.snapshot.value == null)
                        return const SliverToBoxAdapter(
                            child: Center(
                                child: Padding(
                                    padding: EdgeInsets.all(20),
                                    child: Text("No rooms available yet."))));

                      Map<String, dynamic> acts = {};

                      final rawActs = snap.data?.snapshot.value;

                      if (rawActs is Map) {
                        acts = Map<String, dynamic>.from(rawActs);
                      } else if (rawActs is List) {
                        for (int i = 0; i < rawActs.length; i++) {
                          if (rawActs[i] != null) {
                            acts[i.toString()] = rawActs[i];
                          }
                        }
                      }

                      return SliverList(
                          delegate: SliverChildBuilderDelegate((context, i) {
                        String key = acts.keys.toList()[i];
                        Map act = acts[key];

                        return _buildRoomCard(context, key, act);
                      }, childCount: acts.length));
                    }),
              ),
              if (_currentData['contactPhone'] != null ||
                  _currentData['contactEmail'] != null)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: Colors.grey.withOpacity(0.2))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Contact Information',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 16),
                        if (_currentData['contactPhone'] != null &&
                            _currentData['contactPhone'].toString().isNotEmpty)
                          _detailItem(Icons.phone_rounded, "Phone",
                              _currentData['contactPhone']),
                        if (_currentData['contactEmail'] != null &&
                            _currentData['contactEmail'].toString().isNotEmpty)
                          _detailItem(Icons.email_rounded, "Email",
                              _currentData['contactEmail']),
                      ],
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
                  child: Text('Guest Reviews',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: StreamBuilder<DatabaseEvent>(
                  stream: FirebaseDatabase.instance
                      .ref("reviews/${widget.ownerUid}")
                      .onValue,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || !snapshot.data!.snapshot.exists) {
                      return const SliverToBoxAdapter(
                          child: Center(
                              child: Padding(
                                  padding: EdgeInsets.all(40),
                                  child: Text("No reviews yet.",
                                      style: TextStyle(color: Colors.grey)))));
                    }
                    Map data = snapshot.data!.snapshot.value as Map;
                    List reviews = data.values.toList();
                    reviews.sort((a, b) =>
                        (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));

                    return SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        Map r = reviews[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(r['touristName'] ?? 'Guest',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    Row(
                                      children: List.generate(
                                          5,
                                          (i) => Icon(Icons.star_rounded,
                                              size: 16,
                                              color: i < (r['rating'] ?? 0)
                                                  ? Colors.amber
                                                  : Colors.grey[300])),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(r['comment'] ?? '',
                                    style: const TextStyle(fontSize: 14)),
                                const SizedBox(height: 8),
                                Text(
                                  r['timestamp'] != null
                                      ? DateFormat('MMM dd, yyyy').format(
                                          DateTime.fromMillisecondsSinceEpoch(
                                              r['timestamp']))
                                      : '',
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        );
                      }, childCount: reviews.length),
                    );
                  },
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ]),
          );
        });
  }

  Widget _buildRoomCard(BuildContext context, String key, Map act) {
    List<String> roomImages = _parseList(act['imageUrls']);
    if (roomImages.isEmpty) roomImages = [];
    List<String> amenities = _parseList(act['amenities'] ?? act['inclusions']);

    return StatefulBuilder(builder: (context, setCardState) {
      int cardPage = 0;
      final PageController cardController = PageController();

      return StatefulBuilder(builder: (context, setImageState) {
        return Card(
          margin: const EdgeInsets.only(bottom: 20),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image Carousel
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: SizedBox(
                  height: 200,
                  child: roomImages.isEmpty
                      ? Container(
                          color: Colors.grey[200],
                          child: const Center(child: Icon(Icons.hotel, size: 48, color: Colors.grey)),
                        )
                      : Stack(
                          children: [
                            PageView.builder(
                              controller: cardController,
                              itemCount: roomImages.length,
                              onPageChanged: (i) => setImageState(() => cardPage = i),
                              itemBuilder: (context, i) => Image.network(
                                roomImages[i],
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (c, e, s) => Container(
                                    color: Colors.grey[200],
                                    child: const Icon(Icons.broken_image, color: Colors.grey)),
                              ),
                            ),
                            // Price badge
                            Positioned(
                              bottom: 12,
                              left: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.65),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '₱${act['price']} / night',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                                ),
                              ),
                            ),
                            // Photo counter
                            if (roomImages.length > 1)
                              Positioned(
                                top: 12,
                                left: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.55),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${cardPage + 1} / ${roomImages.length}',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            // Dot indicators
                            if (roomImages.length > 1)
                              Positioned(
                                bottom: 12,
                                right: 12,
                                child: Row(
                                  children: List.generate(roomImages.length, (i) => AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    margin: const EdgeInsets.symmetric(horizontal: 2),
                                    width: i == cardPage ? 16 : 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: i == cardPage ? Colors.white : Colors.white54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  )),
                                ),
                              ),
                          ],
                        ),
                ),
              ),

              // Card Body
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(act['title'] ?? 'Room',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                    const SizedBox(height: 10),

                    // Tags
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (act['category'] != null) _buildSmallChip(context, act['category']),
                        if (act['location'] != null) _buildSmallChip(context, act['location']),
                        if (act['maxPax'] != null) _buildSmallChip(context, 'Max Pax: ${act['maxPax']}'),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Quick stats
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.people, size: 15, color: Theme.of(context).colorScheme.secondary),
                                const SizedBox(width: 6),
                                Text('${act['maxPax'] ?? '—'} Guests',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.star, size: 15, color: Color(0xFFFFD700)),
                                SizedBox(width: 6),
                                Text('GCash', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Amenities preview
                    if (amenities.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ...amenities.take(3).map((a) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('✓ $a', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.secondary)),
                          )),
                          if (amenities.length > 3)
                            Text('+${amenities.length - 3} more',
                                style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),

                    // View Room Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => _showRoomDetailsSheet(key, act),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.secondary,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: const Text('VIEW ROOM',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      });
    });
  }

  Widget _buildSmallChip(BuildContext context, String label, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Colors.grey[600]),
            const SizedBox(width: 4)
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700])),
        ],
      ),
    );
  }

  Widget _chip(String l, Color c, String f, {bool isNum = false}) =>
      GestureDetector(
        onTap: widget.isOwner
            ? () => _editTextField(f, l, (_currentData[f] ?? '').toString(),
                isNumber: isNum)
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
              color: c.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.withValues(alpha: 0.2))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(l,
                style: TextStyle(
                    color: c, fontWeight: FontWeight.bold, fontSize: 12)),
            if (widget.isOwner) ...[
              const SizedBox(width: 4),
              Icon(Icons.edit_rounded, size: 12, color: c)
            ]
          ]),
        ),
      );

  Widget _policyItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
      ],
    );
  }

  Widget _detailItem(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon,
                size: 18, color: Theme.of(context).colorScheme.secondary),
            const SizedBox(width: 12),
            Text("$label: ",
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            Text(value, style: const TextStyle(fontSize: 14)),
          ],
        ),
      );
}

class VideoPlayerWidget extends StatefulWidget {
  final String url;
  const VideoPlayerWidget({super.key, required this.url});
  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _vpc;
  ChewieController? _cc;
  @override
  void initState() {
    super.initState();
    _vpc = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _vpc.initialize().then((_) {
      if (mounted) {
        setState(() {
          _cc = ChewieController(
            videoPlayerController: _vpc,
            aspectRatio: _vpc.value.aspectRatio,
            autoPlay: false,
            looping: false,
            materialProgressColors: ChewieProgressColors(
              playedColor: AppTheme.secondaryAccent,
              handleColor: AppTheme.secondaryAccent,
              backgroundColor: Colors.grey,
              bufferedColor: Colors.white54,
            ),
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _vpc.dispose();
    _cc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _cc != null
        ? Chewie(controller: _cc!)
        : const Center(child: CircularProgressIndicator());
  }
}
