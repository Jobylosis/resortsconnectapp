import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:resortconnectapp/services/ai_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/gestures.dart';
import 'chat_page.dart';
import 'policies_property_page.dart';
import 'terms_and_policies_page.dart';
import 'theme_provider.dart';
import 'theme.dart';
import 'mock_gcash_payment_page.dart';
import 'services/email_service.dart';
import 'activity_details_page.dart';

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

  final Map<String, Map<String, dynamic>> _detailedAddons = {};

  @override
  void initState() {
    super.initState();
    _currentData = widget.propertyData;

    final Map<String, Map<String, dynamic>> baseDetails = {
      'Boat ride to falls': {'unit': 'trip', 'desc': 'Guided trip to the falls'},
      'Boat ride': {'unit': 'trip', 'desc': 'Island hopping tour'},
      'Kayak': {'unit': 'hour', 'desc': 'Single kayak rental'},
      'Meals': {'unit': 'pax', 'desc': 'Daily meals'},
      'Dinner': {'unit': 'set', 'desc': 'Local cuisine buffet'},
      'Lunch': {'unit': 'set', 'desc': 'Premium plated lunch'},
      'Extra Bed': {'unit': 'night', 'desc': 'Foldable mattress set'},
    };

    if (_currentData['addonPrices'] != null && _currentData['addonPrices'] is Map) {
      Map prices = _currentData['addonPrices'];
      prices.forEach((key, priceVal) {
        _detailedAddons[key.toString()] = {
          'price': int.tryParse(priceVal.toString()) ?? 0,
          'unit': baseDetails[key]?['unit'] ?? 'item',
          'desc': baseDetails[key]?['desc'] ?? 'Optional Add-on'
        };
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

  Future<void> _saveBooking(
      String activityId,
      Map activity,
      DateTime date,
      int nights,
      String receiptUrl,
      String method,
      double total,
      Map<String, int> addons,
      double paymentAmount,
      String? extractedRefNo) async {
    final user = FirebaseAuth.instance.currentUser;
    final snap = await FirebaseDatabase.instance
        .ref("users/${user?.uid}")
        .get();
    String name = "Anonymous";
    String? profilePic;
    if (snap.exists && snap.value is Map) {
      final userData = snap.value as Map;
      name = "${userData['firstName']} ${userData['lastName']}";
      profilePic = userData['profilePicUrl'];
    }

    List<String> finalAddonsList = [];
    addons.forEach((addon, qty) {
      if (qty > 0) finalAddonsList.add("$addon (x$qty)");
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
      'totalPrice': total,
      'amountPaid': paymentAmount,
      'nights': nights,
      'bookingDate': DateFormat('MMM dd, yyyy').format(date),
      'selectedAddons': finalAddonsList,
      'gcashReceipt': receiptUrl,
      'extractedRefNo': extractedRefNo,
      'status': 'Pending',
      'paymentStatus': 'pending',
      'paymentMethod': 'GCash',
      'paymentOption': method.contains('30%') ? '30% Downpayment' : 'Full Payment',
      'agreedToTerms': true,
      'termsAcceptedAt': ServerValue.timestamp,
      'timestamp': ServerValue.timestamp,
    });
    
    await FirebaseDatabase.instance
        .ref("notifications/${widget.ownerUid}")
        .push()
        .set({
      'title': 'New Booking Request',
      'message': '$name has requested to book ${activity['title']}.',
      'type': 'new_booking',
      'isRead': false,
      'timestamp': ServerValue.timestamp,
      'bookingId': newBookingRef.key,
    });
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("AVAILABLE ADD-ONS",
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 0.8)),
                        if (widget.isOwner)
                          IconButton(
                            icon: const Icon(Icons.edit_rounded, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: _editAddonsDialog,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _detailedAddons.entries.map((entry) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[100],
                          border: Border.all(color: Colors.grey.withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${entry.key} (₱${entry.value['price']})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey)),
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

  void _editAddonsDialog() {
    List<Map<String, dynamic>> localAddons = _detailedAddons.entries.map((e) => {
      'id': UniqueKey().toString(),
      'name': e.key,
      'price': e.value['price']
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Edit Add-ons'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  ...localAddons.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              key: Key('${item['id']}_name'),
                              initialValue: item['name'],
                              maxLength: 30,
                              inputFormatters: [
                                FilteringTextInputFormatter.deny(RegExp(
                                    r'[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]',
                                    unicode: true))
                              ],
                              decoration: const InputDecoration(labelText: 'Name', isDense: true, counterText: ''),
                              onChanged: (val) => item['name'] = val,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              key: Key('${item['id']}_price'),
                              initialValue: item['price'].toString(),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                MaxIntInputFormatter(10000)
                              ],
                              decoration: const InputDecoration(labelText: 'Price', isDense: true, prefixText: '₱'),
                              onChanged: (val) {
                                int p = int.tryParse(val) ?? 0;
                                item['price'] = p;
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle, color: Colors.red),
                            onPressed: () {
                              setDialogState(() {
                                localAddons.removeWhere((element) => element['id'] == item['id']);
                              });
                            },
                          )
                        ],
                      ),
                    );
                  }).toList(),
                  TextButton.icon(
                    onPressed: () {
                      setDialogState(() {
                        localAddons.add({
                          'id': UniqueKey().toString(),
                          'name': 'New Add-on',
                          'price': 0
                        });
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add Add-on'),
                  )
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  Map<String, int> finalAddons = {};
                  for (var item in localAddons) {
                    String name = item['name'].toString().trim();
                    if (name.isNotEmpty) {
                      finalAddons[name] = item['price'];
                    }
                  }
                  await FirebaseDatabase.instance
                      .ref("properties/${widget.ownerUid}")
                      .update({'addonPrices': finalAddons});
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Add-ons updated!')));
                  }
                },
                child: const Text('Save'),
              )
            ],
          );
        });
      }
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
    try {
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
    } catch (e) {
      return false;
    }
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

  Future<void> _confirmBooking(String activityId, Map activity, DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    int nights = prefs.getInt('bp_nights_$activityId') ?? 1;
    String method = prefs.getString('bp_method_$activityId') ?? 'GCash (30% Down)';
    String? receipt = prefs.getString('bp_receipt_$activityId');
    Map<String, int> selectedAddons = {};
    String? addonsStr = prefs.getString('bp_addons_$activityId');
    if (addonsStr != null) {
      try {
        final decoded = jsonDecode(addonsStr) as Map<String, dynamic>;
        selectedAddons = decoded.map((k, v) => MapEntry(k, v as int));
      } catch(e) {}
    }
    bool showQR = false;
    bool agreedToTerms = prefs.getBool('bp_agreed_$activityId') ?? false;
    String? extractedRefNo = prefs.getString('bp_ref_$activityId');
    String? ocrStatus = prefs.getString('bp_ocrStatus_$activityId');
    String? ocrIssues = prefs.getString('bp_ocrIssues_$activityId');

    // Promo Code & Auto Event State
    final TextEditingController promoCodeController = TextEditingController();
    Map<String, dynamic>? appliedPromo;
    String? promoError;
    Map<String, dynamic>? activeEventPromo;

    // Fetch CMS promos for event & coupon matching
    try {
      final cmsSnap = await FirebaseDatabase.instance.ref('cms/homepage/promotions').get();
      if (cmsSnap.exists && cmsSnap.value != null) {
        final promosMap = Map<String, dynamic>.from(cmsSnap.value as Map);
        final nowStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final roomCat = (activity['category'] ?? '').toString().toLowerCase();
        final roomTitle = (activity['title'] ?? '').toString().toLowerCase();

        for (var entry in promosMap.entries) {
          final p = Map<String, dynamic>.from(entry.value as Map);
          p['id'] = entry.key;
          if (p['active'] == true && p['isEvent'] == true) {
            if (p['startDate'] != null && p['startDate'].toString().isNotEmpty && nowStr.compareTo(p['startDate'].toString()) < 0) continue;
            if (p['endDate'] != null && p['endDate'].toString().isNotEmpty && nowStr.compareTo(p['endDate'].toString()) > 0) continue;

            List appRooms = p['applicableRooms'] is List ? p['applicableRooms'] : ['ALL'];
            bool eligible = appRooms.contains('ALL') || appRooms.any((r) {
              final rStr = r.toString().toLowerCase();
              return roomCat.contains(rStr) || roomTitle.contains(rStr);
            });

            if (eligible) {
              activeEventPromo = p;
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error loading promos: $e");
    }

    void saveDraft() {
      prefs.setInt('bp_nights_$activityId', nights);
      prefs.setString('bp_method_$activityId', method);
      if (receipt != null) prefs.setString('bp_receipt_$activityId', receipt!); else prefs.remove('bp_receipt_$activityId');
      prefs.setString('bp_addons_$activityId', jsonEncode(selectedAddons));
      prefs.setBool('bp_agreed_$activityId', agreedToTerms);
      if (extractedRefNo != null) prefs.setString('bp_ref_$activityId', extractedRefNo!); else prefs.remove('bp_ref_$activityId');
      if (ocrStatus != null) prefs.setString('bp_ocrStatus_$activityId', ocrStatus!); else prefs.remove('bp_ocrStatus_$activityId');
      if (ocrIssues != null) prefs.setString('bp_ocrIssues_$activityId', ocrIssues!); else prefs.remove('bp_ocrIssues_$activityId');
    }

    void clearDraft() {
      prefs.remove('bp_nights_$activityId');
      prefs.remove('bp_method_$activityId');
      prefs.remove('bp_receipt_$activityId');
      prefs.remove('bp_addons_$activityId');
      prefs.remove('bp_agreed_$activityId');
      prefs.remove('bp_ref_$activityId');
      prefs.remove('bp_ocrStatus_$activityId');
      prefs.remove('bp_ocrIssues_$activityId');
    }

    if (!mounted) return;
    showDialog(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, setS) {
              saveDraft();
              double baseRoomTotal =
                  (double.tryParse(activity['price'].toString()) ?? 0) * nights;

              double addonTotal = 0;
              selectedAddons.forEach((name, qty) {
                addonTotal += (_detailedAddons[name]!['price'] as int) * qty;
              });

              // Calculate discount - strictly percentage based
              double promoDiscount = 0;
              String promoDiscountLabel = '';
              final effectivePromo = appliedPromo ?? activeEventPromo;
              if (effectivePromo != null) {
                final dVal = (double.tryParse(effectivePromo['discountValue'].toString()) ?? 0);
                promoDiscount = baseRoomTotal * (dVal / 100);
                promoDiscountLabel = '${dVal.toStringAsFixed(0)}% OFF';
              }

              double grossSubtotal = baseRoomTotal + addonTotal;
              double taxes = 0;
              double total = (grossSubtotal - promoDiscount).clamp(0, double.infinity) + taxes;
              // 30% downpayment is calculated on gross total (capped at total)
              double downpaymentAmount = double.parse(((grossSubtotal * 0.3).clamp(0, total)).toStringAsFixed(2));
              double paymentAmount = double.parse((method.contains('30%') ? downpaymentAmount : total).toStringAsFixed(2));
              double remainingAtCheckIn = double.parse(((total - downpaymentAmount).clamp(0, double.infinity)).toStringAsFixed(2));

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
                                        ? () => setS(() { nights--; receipt = null; ocrStatus = null; extractedRefNo = null; })
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
                                        setS(() { nights++; receipt = null; ocrStatus = null; extractedRefNo = null; });
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
                            int capacity = int.tryParse(activity['maxPax']?.toString() ?? activity['capacity']?.toString() ?? '2') ?? 2;
                            bool isFood = name.toLowerCase().contains('breakfast') || 
                                          name.toLowerCase().contains('lunch') || 
                                          name.toLowerCase().contains('dinner') || 
                                          name.toLowerCase().contains('meal');
                            int maxQty = name == 'Extra Bed' ? 3 : (isFood ? (capacity * nights) : capacity);

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
                                                  ? () => setS(() {
                                                      selectedAddons[name] = qty - 1;
                                                      receipt = null; ocrStatus = null; extractedRefNo = null;
                                                    })
                                                  : null,
                                              icon: const Icon(
                                                  Icons.remove_circle_outline)),
                                          Text('$qty',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold)),
                                          IconButton(
                                              iconSize: 20,
                                              onPressed: qty < maxQty
                                                  ? () => setS(() {
                                                      selectedAddons[name] = qty + 1;
                                                      receipt = null; ocrStatus = null; extractedRefNo = null;
                                                    })
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
                          const Text('Promo Code / Event', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 8),
                          if (activeEventPromo != null && appliedPromo == null) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.teal.shade300),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.auto_awesome, size: 16, color: Colors.teal),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Auto-applied Event: ${activeEventPromo['title']} ($promoDiscountLabel)',
                                      style: TextStyle(fontSize: 12, color: Colors.teal.shade900, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (appliedPromo != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.green),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('✓ Code Applied: ${appliedPromo?['code'] ?? ''}', style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.bold, fontSize: 13)),
                                  TextButton(
                                    onPressed: () => setS(() {
                                      appliedPromo = null;
                                      promoCodeController.clear();
                                      promoError = null;
                                    }),
                                    child: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 12)),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: promoCodeController,
                                    textCapitalization: TextCapitalization.characters,
                                    decoration: const InputDecoration(
                                      hintText: 'e.g. SUMMER20',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () async {
                                    setS(() => promoError = null);
                                    final code = promoCodeController.text.trim().toUpperCase();
                                    if (code.isEmpty) return;

                                    final cmsSnap = await FirebaseDatabase.instance.ref('cms/homepage/promotions').get();
                                    if (cmsSnap.exists && cmsSnap.value != null) {
                                      final promosMap = cmsSnap.exists && cmsSnap.value != null ? Map<String, dynamic>.from(cmsSnap.value as Map) : <String, dynamic>{};
                                      Map<String, dynamic>? matched;
                                      for (var e in promosMap.entries) {
                                        final p = Map<String, dynamic>.from(e.value as Map);
                                        p['id'] = e.key;
                                        if ((p['code'] ?? '').toString().trim().toUpperCase() == code) {
                                          matched = p;
                                          break;
                                        }
                                      }

                                      // Also check user personal coupons if not in CMS
                                      final currentUser = FirebaseAuth.instance.currentUser;
                                      if (matched == null && currentUser?.uid != null) {
                                        try {
                                          final uCouponSnap = await FirebaseDatabase.instance.ref('user_coupons/${currentUser!.uid}/$code').get();
                                          if (uCouponSnap.exists && uCouponSnap.value != null) {
                                            final uMap = Map<String, dynamic>.from(uCouponSnap.value as Map);
                                            if (uMap['used'] == true) {
                                              setS(() => promoError = 'This coupon has already been used');
                                              return;
                                            }
                                            uMap['id'] = code;
                                            matched = uMap;
                                          }
                                        } catch (e) {
                                          debugPrint('Coupon fetch error: $e');
                                        }
                                      }

                                      if (matched == null) {
                                        setS(() => promoError = 'Invalid promo code');
                                        return;
                                      }
                                      if (matched['active'] == false) {
                                        setS(() => promoError = 'This promo is inactive');
                                        return;
                                      }

                                      final nowStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
                                      if (matched['startDate'] != null && matched['startDate'].toString().isNotEmpty && nowStr.compareTo(matched['startDate'].toString()) < 0) {
                                        setS(() => promoError = 'Valid starting ${matched!['startDate']}');
                                        return;
                                      }
                                      if (matched['endDate'] != null && matched['endDate'].toString().isNotEmpty && nowStr.compareTo(matched['endDate'].toString()) > 0) {
                                        setS(() => promoError = 'Promo expired on ${matched!['endDate']}');
                                        return;
                                      }

                                      List appRooms = matched['applicableRooms'] is List ? matched['applicableRooms'] : ['ALL'];
                                      final roomCat = (activity['category'] ?? '').toString().toLowerCase();
                                      final roomTitle = (activity['title'] ?? '').toString().toLowerCase();
                                      bool eligible = appRooms.contains('ALL') || appRooms.any((r) {
                                        final rStr = r.toString().toLowerCase();
                                        return roomCat.contains(rStr) || roomTitle.contains(rStr);
                                      });

                                      if (!eligible) {
                                        setS(() => promoError = 'Not applicable to this room type (${appRooms.join(', ')})');
                                        return;
                                      }

                                      setS(() {
                                        appliedPromo = matched;
                                        promoError = null;
                                      });
                                    }
                                  },
                                  child: const Text('Apply'),
                                ),
                              ],
                            ),
                          ],
                          if (promoError != null) ...[
                            const SizedBox(height: 4),
                            Text(promoError!, style: const TextStyle(color: Colors.red, fontSize: 11)),
                          ],
                          const Divider(height: 32),
                          const Text('Price Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text('Room Base ($nights ${nights == 1 ? "night" : "nights"})', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                            Text('₱${baseRoomTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          ]),
                          if (addonTotal > 0) ...[
                            const SizedBox(height: 6),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              const Text('Add-ons', style: TextStyle(color: Colors.grey, fontSize: 13)),
                              Text('₱${addonTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            ]),
                          ],
                          if (promoDiscount > 0) ...[
                            const SizedBox(height: 6),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Text('Promo Discount ($promoDiscountLabel)', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                              Text('-₱${promoDiscount.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                            ]),
                          ],
                          const SizedBox(height: 6),
                          const Divider(height: 24, color: Colors.transparent),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            const Text('Booking Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text('₱${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                          ]),
                          const Divider(height: 32),
                          DropdownButtonFormField<String>(
                            value: method,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Payment Method'),
                            items: [
                              DropdownMenuItem(
                                  value: 'GCash (30% Down)',
                                  child: Text(
                                      '30% Downpayment (₱${downpaymentAmount.toStringAsFixed(2)})',
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
                                ? 'Remaining balance of ₱${remainingAtCheckIn.toStringAsFixed(2)} to be paid at the resort.'
                                : 'Full payment of ₱${total.toStringAsFixed(2)} covered.',
                            style: const TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: Colors.grey),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: OutlinedButton.icon(
                              onPressed: () => setS(() => showQR = !showQR),
                              icon: const Icon(Icons.qr_code_2),
                              label: Text(showQR ? 'Hide GCash QR' : 'View GCash QR'),
                            ),
                          ),
                          if (showQR) ...[
                            const SizedBox(height: 12),
                            Center(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _currentData['gcashQrUrl'] != null && _currentData['gcashQrUrl'].toString().isNotEmpty
                                    ? Image.network(_currentData['gcashQrUrl'], width: 200, fit: BoxFit.contain)
                                    : Image.asset('assets/gcashqr1.jpg', width: 200, fit: BoxFit.contain),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Center(
                            child: Column(
                              children: [
                                // Step 1: Open GCash button
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final Uri gcashUrl = Uri.parse("https://m.gcash.com");
                                    try {
                                      await launchUrl(gcashUrl, mode: LaunchMode.externalApplication);
                                    } catch (e) {
                                      // ignore if it fails to launch
                                    }
                                  },
                                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                  label: const Text('Open GCash App'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF0038A8),
                                    side: const BorderSide(color: Color(0xFF0038A8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '⚠️ Only send the exact amount so that the AI checker works perfectly and the booking process goes smoothly.',
                                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900, fontWeight: FontWeight.w600),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // Step 2: Upload Screenshot
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    setS(() {
                                      receipt = null;
                                      extractedRefNo = null;
                                      ocrStatus = null;
                                      ocrIssues = null;
                                    });
                                    final picker = ImagePicker();
                                    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                                    if (picked == null) return;

                                    setS(() {
                                      receipt = 'UPLOADING';
                                      extractedRefNo = null;
                                      ocrStatus = null;
                                      ocrIssues = null;
                                    });

                                    final File imgFile = File(picked.path);

                                    // Strict OCR Validation
                                    bool validationPassed = false;
                                    try {
                                      final ocrData = await AiService.extractGCashReference(
                                        imgFile,
                                        paymentAmount,
                                        _currentData['gcashName'] ?? ''
                                      );
                                      if (ocrData != null && ocrData['success'] == true) {
                                        String tempRefNo = ocrData['reference_number'].toString();
                                        
                                        // Immediate duplicate check
                                        final usedRefSnap = await FirebaseDatabase.instance.ref("used_receipts/${widget.ownerUid}").get();
                                        List<dynamic> tempUsedReceipts = [];
                                        if (usedRefSnap.exists && usedRefSnap.value != null) {
                                          if (usedRefSnap.value is List) {
                                            tempUsedReceipts = List.from(usedRefSnap.value as List);
                                          } else if (usedRefSnap.value is Map) {
                                            tempUsedReceipts = (usedRefSnap.value as Map).values.toList();
                                          }
                                        }
                                        
                                        if (tempUsedReceipts.map((e) => e.toString()).contains(tempRefNo)) {
                                          if (mounted) {
                                            showDialog(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text('Duplicate Receipt'),
                                                content: const Text('This receipt reference number has already been used. Upload blocked.'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(ctx),
                                                    child: const Text('OK'),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }
                                          setS(() {
                                            receipt = null;
                                            extractedRefNo = null;
                                            ocrStatus = null;
                                          });
                                          return;
                                        }

                                        validationPassed = true;
                                        extractedRefNo = tempRefNo;
                                        ocrStatus = 'Verified';
                                        print("OCR Validated. Ref: $extractedRefNo, Amount: ${ocrData['amount']}");
                                      } else {
                                        ocrStatus = 'Flagged';
                                        ocrIssues = ocrData?['error'] ?? "Could not verify GCash receipt.";
                                        if (!mounted) return;
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Notice'),
                                            content: Text("$ocrIssues\n\nBecause of this issue, the booking will be automatically declined."),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(ctx),
                                                child: const Text('OK'),
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      print("OCR extraction failed: $e");
                                      ocrStatus = 'Flagged';
                                      ocrIssues = "OCR Server unreachable.";
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notice: OCR service unreachable. Booking will be declined.')));
                                    }

                                    // Upload to Cloudinary (always upload)
                                    String? cloudinaryUrl;
                                    try {
                                      final cloudUri = Uri.parse('https://api.cloudinary.com/v1_1/dnv6ezitm/image/upload');
                                      final cloudReq = http.MultipartRequest('POST', cloudUri);
                                      cloudReq.fields['upload_preset'] = 'resort_unsigned';
                                      cloudReq.files.add(await http.MultipartFile.fromPath('file', imgFile.path));
                                      final cloudResp = await cloudReq.send();
                                      if (cloudResp.statusCode == 200) {
                                        final respStr = await cloudResp.stream.bytesToString();
                                        final json = jsonDecode(respStr);
                                        cloudinaryUrl = json['secure_url'];
                                      }
                                    } catch (e) {
                                      print("Cloudinary upload failed: $e");
                                    }

                                    if (!mounted) return;

                                    setS(() {
                                      receipt = cloudinaryUrl ?? 'MANUAL_GCASH_PAYMENT';
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(validationPassed ? 'Receipt Validated! Ref: $extractedRefNo' : 'Receipt flagged. Booking will be declined.'),
                                        backgroundColor: validationPassed ? Colors.green : Colors.orange,
                                      ),
                                    );
                                  },
                                  icon: Icon(receipt == 'UPLOADING'
                                      ? Icons.hourglass_top_rounded
                                      : receipt != null
                                          ? (ocrStatus == 'Verified' ? Icons.check_circle_rounded : Icons.warning_amber_rounded)
                                          : Icons.upload_file_rounded),
                                  label: Text(receipt == 'UPLOADING'
                                      ? 'Scanning Receipt...'
                                      : receipt != null
                                          ? (ocrStatus == 'Verified' ? 'Verified (Ref: $extractedRefNo)' : 'Flagged (Auto-Decline)')
                                          : 'Upload Payment Screenshot'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: receipt != null && receipt != 'UPLOADING'
                                        ? (ocrStatus == 'Verified' ? Colors.green : Colors.orange[700])
                                        : const Color(0xFF0038A8),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: agreedToTerms,
                                  onChanged: (val) {
                                    setS(() => agreedToTerms = val ?? false);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    children: [
                                      const TextSpan(text: 'I agree to the '),
                                      TextSpan(
                                        text: 'Terms & Conditions',
                                        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                        recognizer: TapGestureRecognizer()..onTap = () {
                                          Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsAndPoliciesPage()));
                                        },
                                      ),
                                      const TextSpan(text: ' and '),
                                      TextSpan(
                                        text: 'Data Privacy Policy',
                                        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                        recognizer: TapGestureRecognizer()..onTap = () {
                                          Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsAndPoliciesPage(scrollToPrivacy: true)));
                                        },
                                      ),
                                      const TextSpan(text: '. I understand my booking is subject to resort policies.'),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total:',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18)),
                              Text('₱${paymentAmount.toStringAsFixed(2)}',
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
                    onPressed: !agreedToTerms || receipt == null || receipt == 'UPLOADING' ? null : () async {
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
                            if (extractedRefNo != null && extractedRefNo!.isNotEmpty) {
                              try {
                                final usedRefSnap = await FirebaseDatabase.instance.ref("used_receipts/${widget.ownerUid}").get();
                                List<dynamic> usedReceipts = [];
                                if (usedRefSnap.exists && usedRefSnap.value != null) {
                                  if (usedRefSnap.value is List) {
                                    usedReceipts = List.from(usedRefSnap.value as List);
                                  } else if (usedRefSnap.value is Map) {
                                    usedReceipts = (usedRefSnap.value as Map).values.toList();
                                  }
                                }
                                
                                if (usedReceipts.map((e) => e.toString()).contains(extractedRefNo)) {
                                  if (context.mounted) {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Duplicate Receipt'),
                                        content: const Text('This receipt reference number has already been used for another booking.'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context),
                                            child: const Text('OK')
                                          )
                                        ],
                                      ),
                                    );
                                  }
                                  return;
                                }
                                
                                usedReceipts.add(extractedRefNo);
                                if (usedReceipts.length > 500) {
                                  usedReceipts = usedReceipts.sublist(usedReceipts.length - 500);
                                }
                                await FirebaseDatabase.instance.ref("used_receipts/${widget.ownerUid}").set(usedReceipts);
                              } catch (e) {
                                print("Error checking used receipts: $e");
                              }
                            }

                            DatabaseReference newBookingRef = FirebaseDatabase.instance.ref("bookings").push();
                            await newBookingRef.set({
                              'touristUid': user?.uid,
                              'touristName': name,
                              'touristProfilePic': profilePic,
                              'ownerUid': widget.ownerUid,
                              'activityId': activityId,
                              'propertyName': widget.propertyName,
                              'activityTitle': activity['title'],
                              'pricing': {
                                'basePrice': baseRoomTotal,
                                'addonsTotal': addonTotal,
                                'taxes': taxes,
                                'grandTotal': total
                              },
                              'totalPrice': total,
                              'amountPaid': paymentAmount,
                              'nights': nights,
                              'bookingDate': DateFormat('MMM dd, yyyy').format(date),
                              'status': 'Pending',
                              'paymentStatus': 'pending',
                              'paymentMethod': 'GCash',
                              'paymentOption': method.contains('30%') ? '30% Downpayment' : 'Full Payment',
                              'gcashReceipt': receipt,
                              'extractedRefNo': extractedRefNo ?? '',
                              'ocrStatus': ocrStatus ?? 'Unverified',
                              'promoCode': (appliedPromo?['code'] ?? activeEventPromo?['code']),
                              'promoDiscount': promoDiscount,
                              'promoName': (appliedPromo?['title'] ?? activeEventPromo?['title']),
                              'agreedToTerms': true,
                              'termsAcceptedAt': ServerValue.timestamp,
                              'timestamp': ServerValue.timestamp,
                              'selectedAddons': finalAddons,
                            });

                            // If user applied a personal coupon (e.g. WELCOME10), mark it as used
                            if (appliedPromo?['code'] != null && user?.uid != null) {
                              try {
                                await FirebaseDatabase.instance
                                    .ref("user_coupons/${user!.uid}/${appliedPromo!['code']}")
                                    .update({
                                  'used': true,
                                  'usedAt': ServerValue.timestamp,
                                  'bookingId': newBookingRef.key,
                                });
                              } catch (e) {
                                debugPrint('Could not update coupon status: $e');
                              }
                            }

                            // EmailJS Booking Confirmation Trigger
                            if (user?.email != null) {
                              EmailService.sendBookingConfirmation(
                                toEmail: user!.email!,
                                toName: name,
                                bookingId: newBookingRef.key ?? 'N/A',
                                propertyName: widget.propertyName,
                                roomName: activity['title'] ?? 'Room',
                                checkInDate: DateFormat('MMM dd, yyyy').format(date),
                                nights: nights,
                                amountPaid: paymentAmount,
                                grandTotal: total,
                                paymentMethod: 'GCash',
                                paymentOption: method.contains('30%') ? '30% Downpayment' : 'Full Payment',
                              ).catchError((err) {
                                debugPrint('[EmailJS] Booking confirmation error: $err');
                                return false;
                              });
                            }

                            // EmailJS Alert to Admin
                            EmailService.sendAdminAlert(
                              title: 'New Booking Created (Mobile)',
                              message: '$name created a booking for ${activity['title']} at ${widget.propertyName}.',
                              details: {
                                'bookingId': newBookingRef.key,
                                'tourist': name,
                                'amount': total,
                              },
                            ).catchError((err) {
                              debugPrint('[EmailJS] Admin alert error: $err');
                              return false;
                            });
                            
                            await FirebaseDatabase.instance
                                .ref("notifications/${widget.ownerUid}")
                                .push()
                                .set({
                              'title': ocrStatus == 'Flagged' ? 'Auto-declined Booking' : 'New Booking Request',
                              'message': ocrStatus == 'Flagged'
                                  ? '$name\'s booking was auto-declined due to invalid payment.'
                                  : '$name has requested to book ${activity['title']}.',
                              'type': 'new_booking',
                              'isRead': false,
                              'timestamp': ServerValue.timestamp,
                              'bookingId': newBookingRef.key,
                            });

                            if (context.mounted) {
                              clearDraft();
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          ocrStatus == 'Flagged' 
                                            ? 'Booking automatically declined due to invalid payment proof.'
                                            : 'Booking request sent successfully!')));
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

  Future<void> _showMultiActivityBookingSheet() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to book activities.')),
      );
      return;
    }

    final firstDate = DateUtils.dateOnly(DateTime.now());
    final date = await showDatePicker(
      context: context,
      initialDate: firstDate,
      firstDate: firstDate,
      lastDate: firstDate.add(const Duration(days: 365)),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
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

    if (date == null || !mounted) return;

    // Load available activities from database
    final actsSnap = await FirebaseDatabase.instance.ref("properties/${widget.ownerUid}/activities").get();
    Map<String, Map<String, dynamic>> availableActs = {};
    if (actsSnap.exists && actsSnap.value != null) {
      final val = actsSnap.value;
      if (val is Map) {
        val.forEach((k, v) {
          if (v is Map) {
            availableActs[k.toString()] = Map<String, dynamic>.from(v);
          }
        });
      } else if (val is List) {
        for (int i = 0; i < val.length; i++) {
          if (val[i] != null && val[i] is Map) {
            availableActs[i.toString()] = Map<String, dynamic>.from(val[i]);
          }
        }
      }
    }

    // Fallback standard catalog if owner has no activities loaded
    if (availableActs.isEmpty) {
      availableActs = {
        'act_kayak': {
          'title': 'Kayak',
          'price': 300,
          'maxPax': 1,
          'description': 'Enjoy a peaceful paddle across scenic waters with our standard single kayak.',
        },
        'act_paddle': {
          'title': 'Paddle Board',
          'price': 300,
          'maxPax': 1,
          'description': 'Stand up paddle board adventure along calm resort waters.',
        },
        'act_boat': {
          'title': 'Boatride to falls',
          'price': 1450,
          'maxPax': 3,
          'minPax': 1,
          'description': 'Scenic boat journey to the falls (+₱750 surcharge if solo).',
        },
        'act_boat_meal': {
          'title': 'Boatride to falls with meal',
          'price': 2000,
          'maxPax': 3,
          'minPax': 1,
          'description': 'Scenic boat journey with fresh resort meal (+₱750 surcharge if solo).',
        },
        'act_karaoke': {
          'title': 'Karaoke',
          'price': 750,
          'maxPax': 10,
          'description': 'Complete karaoke setup with sound system and wireless mics.',
        },
      };
    }

    // State for booking modal
    Map<String, bool> selectedActIds = {};
    Map<String, int> actPax = {};
    for (var k in availableActs.keys) {
      selectedActIds[k] = false;
      actPax[k] = 1;
    }

    // Default first activity selected
    if (availableActs.isNotEmpty) {
      selectedActIds[availableActs.keys.first] = true;
    }

    // Food add-on meals
    final addonPrices = _currentData['addonPrices'] is Map ? _currentData['addonPrices'] as Map : {};
    Map<String, int> mealCounts = {};
    for (var key in addonPrices.keys) {
      mealCounts[key.toString()] = 0;
    }

    String method = 'GCash (30% Down)';
    String? receipt;
    String? extractedRefNo;
    String? ocrStatus;
    String? ocrIssues;
    bool agreedToTerms = false;
    bool showQR = false;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setS) {
          // Calculate activities subtotal & surcharges
          double activitiesSubtotal = 0;
          double soloSurcharges = 0;
          List<Map<String, dynamic>> chosenItems = [];

          availableActs.forEach((id, act) {
            if (selectedActIds[id] == true) {
              final double price = (double.tryParse(act['price']?.toString() ?? '') ?? 0);
              final int pax = actPax[id] ?? 1;
              final String title = act['title'] ?? 'Activity';
              final bool isBoat = title.toLowerCase().contains('boatride');
              
              double actCost = price * pax;
              double soloFee = 0;
              if (isBoat && pax == 1) {
                soloFee = 750.0;
                soloSurcharges += soloFee;
              }
              activitiesSubtotal += actCost;
              chosenItems.add({
                'id': id,
                'title': title,
                'price': price,
                'pax': pax,
                'soloFee': soloFee,
                'total': actCost + soloFee,
              });
            }
          });

          double mealsTotal = 0;
          mealCounts.forEach((key, count) {
            double price = double.tryParse(addonPrices[key]?.toString() ?? '') ?? 0.0;
            mealsTotal += price * count;
          });
          double grandTotal = activitiesSubtotal + soloSurcharges + mealsTotal;
          double downpaymentAmount = double.parse(((grandTotal * 0.3).clamp(0, grandTotal)).toStringAsFixed(2));
          double paymentAmount = double.parse((method.contains('30%') ? downpaymentAmount : grandTotal).toStringAsFixed(2));
          double remainingAtCheckIn = double.parse(((grandTotal - downpaymentAmount).clamp(0, double.infinity)).toStringAsFixed(2));

          final gcashNum = _currentData['gcashNumber'] ?? '09123456789';
          final gcashName = _currentData['gcashName'] ?? widget.propertyName;
          final gcashQr = _currentData['gcashQrUrl'];

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.kayaking, color: AppTheme.primaryAccent),
                const SizedBox(width: 8),
                const Expanded(child: Text('Book Activities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(dialogCtx),
                ),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.95,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.access_time_filled_rounded, size: 20, color: Colors.amber.shade800),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Operating Schedule: 8:00 AM - 5:00 PM',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Date: ${DateFormat('MMMM dd, yyyy').format(date)} (Operating hours apply for all booked activities)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.brown.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Select Activities (Add Multiple):',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    ...availableActs.entries.map((entry) {
                      final id = entry.key;
                      final act = entry.value;
                      final isSelected = selectedActIds[id] == true;
                      final title = act['title'] ?? 'Activity';
                      final price = act['price'] ?? 0;
                      final maxPax = act['maxPax'] ?? 1;
                      final isBoat = title.toLowerCase().contains('boatride');
                      final currentPax = actPax[id] ?? 1;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? AppTheme.primaryAccent : Colors.grey.shade300,
                            width: isSelected ? 1.5 : 1,
                          ),
                          color: isSelected ? AppTheme.primaryAccent.withOpacity(0.04) : null,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Checkbox(
                                    value: isSelected,
                                    activeColor: AppTheme.primaryAccent,
                                    onChanged: (val) {
                                      setS(() {
                                        selectedActIds[id] = val ?? false;
                                        receipt = null;
                                        extractedRefNo = null;
                                      });
                                    },
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        Text(
                                          '₱$price/pax • Max $maxPax pax',
                                          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '₱$price',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 14),
                                  ),
                                ],
                              ),
                              if (isSelected && maxPax > 1) ...[
                                const Divider(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Passengers ($currentPax pax):', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    Row(
                                      children: [
                                        IconButton(
                                          iconSize: 18,
                                          onPressed: currentPax > 1 ? () => setS(() => actPax[id] = currentPax - 1) : null,
                                          icon: const Icon(Icons.remove_circle_outline),
                                        ),
                                        Text('$currentPax', style: const TextStyle(fontWeight: FontWeight.bold)),
                                        IconButton(
                                          iconSize: 18,
                                          onPressed: currentPax < maxPax ? () => setS(() => actPax[id] = currentPax + 1) : null,
                                          icon: const Icon(Icons.add_circle_outline),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                              if (isSelected && isBoat && currentPax == 1)
                                Container(
                                  margin: const EdgeInsets.only(top: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    '+₱750 solo boatride charge applied (Total: ₱2,200/₱2,750)',
                                    style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const Divider(height: 28),
                    if ((_currentData['enableCustomMenuUpload'] == true || _currentData['enableCustomMenuUpload'] == 'true') && _currentData['foodMenuUrls'] != null && _parseList(_currentData['foodMenuUrls']).isNotEmpty) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.restaurant_menu, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 8),
                                Text('Food Menu Available', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text('Lunch & Dinner options are available at this property. No advance booking required.', style: TextStyle(fontSize: 13, color: Colors.grey)),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  _showMenuGallery(context, _parseList(_currentData['foodMenuUrls']));
                                },
                                icon: const Icon(Icons.image_search, size: 18),
                                label: const Text('View Menus', style: TextStyle(fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (addonPrices.entries.where((e) {
                      bool isCustomMenuEnabled = _currentData['enableCustomMenuUpload'] == true || _currentData['enableCustomMenuUpload'] == 'true';
                      if (!isCustomMenuEnabled) return true;
                      String n = e.key.toString().toLowerCase();
                      return !(n.contains('breakfast') || n.contains('lunch') || n.contains('dinner') || n.contains('meal'));
                    }).isNotEmpty) ...[
                      const Text('Extras & Add-ons:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 8),
                      ...addonPrices.entries.where((e) {
                        bool isCustomMenuEnabled = _currentData['enableCustomMenuUpload'] == true || _currentData['enableCustomMenuUpload'] == 'true';
                        if (!isCustomMenuEnabled) return true;
                        String n = e.key.toString().toLowerCase();
                        return !(n.contains('breakfast') || n.contains('lunch') || n.contains('dinner') || n.contains('meal'));
                      }).map((entry) {
                        final String mealName = entry.key.toString();
                        final double price = double.tryParse(entry.value?.toString() ?? '') ?? 0.0;
                        final int currentCount = mealCounts[mealName] ?? 0;
                        
                        return Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('$mealName Set Menu', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text('₱${price.toStringAsFixed(0)} / meal set', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  iconSize: 18,
                                  onPressed: currentCount > 0 ? () => setS(() => mealCounts[mealName] = currentCount - 1) : null,
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                Text('$currentCount', style: const TextStyle(fontWeight: FontWeight.bold)),
                                IconButton(
                                  iconSize: 18,
                                  onPressed: () => setS(() => mealCounts[mealName] = currentCount + 1),
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                              ],
                            ),
                          ],
                        );
                      }).toList(),
                    ],
                    const Divider(height: 28),
                    const Text('Price Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Activities Subtotal (${chosenItems.length} selected)', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        Text('₱${activitiesSubtotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      ],
                    ),
                    if (soloSurcharges > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Solo Boatride Surcharge (+₱750)', style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold)),
                          Text('+₱${soloSurcharges.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange)),
                        ],
                      ),
                    ],
                    if (mealsTotal > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Meals & Catering', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          Text('₱${mealsTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        ],
                      ),
                    ],
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Activities Bill', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text('₱${grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                      ],
                    ),
                    const Divider(height: 28),
                    DropdownButtonFormField<String>(
                      value: method,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Payment Option', border: OutlineInputBorder()),
                      items: [
                        DropdownMenuItem(
                          value: 'GCash (30% Down)',
                          child: Text('30% Downpayment (₱${downpaymentAmount.toStringAsFixed(2)})'),
                        ),
                        DropdownMenuItem(
                          value: 'GCash (100% Full)',
                          child: Text('100% Full Payment (₱${grandTotal.toStringAsFixed(2)})'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setS(() => method = val);
                      },
                    ),
                    if (method.contains('30%')) ...[
                      const SizedBox(height: 6),
                      Text('Remaining balance on arrival: ₱${remainingAtCheckIn.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                    const Divider(height: 28),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0038A8).withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF0038A8).withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('GCash Payment Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0038A8))),
                              Text('₱${paymentAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0038A8))),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Number: $gcashNum', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          Text('Account Name: $gcashName', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          if (gcashQr != null && gcashQr.toString().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => setS(() => showQR = !showQR),
                              icon: Icon(showQR ? Icons.visibility_off : Icons.qr_code, size: 16),
                              label: Text(showQR ? 'Hide GCash QR' : 'Show GCash QR Code', style: const TextStyle(fontSize: 12)),
                            ),
                            if (showQR)
                              Center(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(gcashQr.toString(), height: 180, fit: BoxFit.contain),
                                ),
                              ),
                          ],
                          const SizedBox(height: 12),
                          Center(
                            child: Column(
                              children: [
                                // Step 1: Open GCash button
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final Uri gcashUrl = Uri.parse("https://m.gcash.com");
                                    try {
                                      await launchUrl(gcashUrl, mode: LaunchMode.externalApplication);
                                    } catch (e) {
                                      // ignore if it fails to launch
                                    }
                                  },
                                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                  label: const Text('Open GCash App'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF0038A8),
                                    side: const BorderSide(color: Color(0xFF0038A8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '⚠️ Only send the exact amount so that the AI checker works perfectly and the booking process goes smoothly.',
                                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900, fontWeight: FontWeight.w600),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // Step 2: Upload Screenshot
                                ElevatedButton.icon(
                                  onPressed: receipt == 'UPLOADING' ? null : () async {
                                    final picker = ImagePicker();
                              final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                              if (picked == null) return;
                              final imgFile = File(picked.path);

                                    setS(() {
                                      receipt = 'UPLOADING';
                                      extractedRefNo = null;
                                      ocrStatus = null;
                                      ocrIssues = null;
                                    });

                              bool validationPassed = false;
                              try {
                                final ocrData = await AiService.extractGCashReference(
                                  imgFile,
                                  paymentAmount,
                                  gcashName,
                                );
                                if (ocrData != null && ocrData['success'] == true) {
                                  String tempRefNo = ocrData['reference_number'].toString();
                                  final usedRefSnap = await FirebaseDatabase.instance.ref("used_receipts/${widget.ownerUid}").get();
                                  List<dynamic> tempUsedReceipts = [];
                                  if (usedRefSnap.exists && usedRefSnap.value != null) {
                                    if (usedRefSnap.value is List) {
                                      tempUsedReceipts = List.from(usedRefSnap.value as List);
                                    } else if (usedRefSnap.value is Map) {
                                      tempUsedReceipts = (usedRefSnap.value as Map).values.toList();
                                    }
                                  }

                                  if (tempUsedReceipts.map((e) => e.toString()).contains(tempRefNo)) {
                                    if (context.mounted) {
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Duplicate Receipt'),
                                          content: const Text('This receipt reference number has already been used. Upload blocked.'),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
                                          ],
                                        ),
                                      );
                                    }
                                    setS(() {
                                      receipt = null;
                                      extractedRefNo = null;
                                      ocrStatus = null;
                                    });
                                    return;
                                  }

                                  validationPassed = true;
                                  extractedRefNo = tempRefNo;
                                  ocrStatus = 'Verified';
                                } else {
                                  ocrStatus = 'Flagged';
                                  ocrIssues = ocrData?['error'] ?? "Could not verify GCash receipt.";
                                  if (context.mounted) {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Notice'),
                                        content: Text("$ocrIssues\n\nBecause of this issue, the booking will be automatically declined."),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
                                        ],
                                      )
                                    );
                                  }
                                }
                              } catch (e) {
                                ocrStatus = 'Flagged';
                                ocrIssues = "OCR Service unreachable.";
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notice: OCR service unreachable. Booking will be declined.')));
                                }
                              }

                              // Cloudinary upload
                              String? cloudinaryUrl;
                              try {
                                final cloudUri = Uri.parse('https://api.cloudinary.com/v1_1/dnv6ezitm/image/upload');
                                final cloudReq = http.MultipartRequest('POST', cloudUri);
                                cloudReq.fields['upload_preset'] = 'resort_unsigned';
                                cloudReq.files.add(await http.MultipartFile.fromPath('file', imgFile.path));
                                final cloudResp = await cloudReq.send();
                                if (cloudResp.statusCode == 200) {
                                  final respStr = await cloudResp.stream.bytesToString();
                                  final json = jsonDecode(respStr);
                                  cloudinaryUrl = json['secure_url'];
                                }
                              } catch (e) {}

                              if (!mounted) return;
                              setS(() {
                                receipt = cloudinaryUrl ?? 'MANUAL_GCASH_PAYMENT';
                              });
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(validationPassed ? 'Receipt Validated! Ref: $extractedRefNo' : 'Receipt flagged. Booking will be declined.'),
                                    backgroundColor: validationPassed ? Colors.green : Colors.orange,
                                  ),
                                );
                              }
                            },
                            icon: Icon(receipt == 'UPLOADING'
                                ? Icons.hourglass_top_rounded
                                : receipt != null
                                    ? (ocrStatus == 'Verified' ? Icons.check_circle_rounded : Icons.warning_amber_rounded)
                                    : Icons.upload_file_rounded),
                            label: Text(receipt == 'UPLOADING'
                                ? 'Scanning Receipt...'
                                : receipt != null
                                    ? (ocrStatus == 'Verified' ? 'Verified (Ref: $extractedRefNo)' : 'Flagged (Auto-Decline)')
                                    : 'Upload Payment Screenshot'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: receipt != null && receipt != 'UPLOADING'
                                  ? (ocrStatus == 'Verified' ? Colors.green : Colors.orange[700])
                                  : const Color(0xFF0038A8),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: agreedToTerms,
                            onChanged: (val) => setS(() => agreedToTerms = val ?? false),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                              children: [
                                const TextSpan(text: 'I agree to the '),
                                TextSpan(
                                  text: 'Terms & Conditions',
                                  style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                  recognizer: TapGestureRecognizer()..onTap = () {
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsAndPoliciesPage()));
                                  },
                                ),
                                const TextSpan(text: ' and '),
                                TextSpan(
                                  text: 'Data Privacy Policy',
                                  style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                  recognizer: TapGestureRecognizer()..onTap = () {
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsAndPoliciesPage(scrollToPrivacy: true)));
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: (!agreedToTerms || receipt == null || receipt == 'UPLOADING' || chosenItems.isEmpty)
                    ? null
                    : () async {
                        final uSnap = await FirebaseDatabase.instance.ref("users/${user.uid}").get();
                        String touristName = "Anonymous";
                        String? touristPic;
                        if (uSnap.exists && uSnap.value is Map) {
                          final uData = uSnap.value as Map;
                          touristName = "${uData['firstName']} ${uData['lastName']}";
                          touristPic = uData['profilePicUrl'];
                        }

                        // Save used receipt reference
                        if (extractedRefNo != null && extractedRefNo!.isNotEmpty) {
                          try {
                            final usedRefSnap = await FirebaseDatabase.instance.ref("used_receipts/${widget.ownerUid}").get();
                            List<dynamic> usedReceipts = [];
                            if (usedRefSnap.exists && usedRefSnap.value != null) {
                              if (usedRefSnap.value is List) {
                                usedReceipts = List.from(usedRefSnap.value as List);
                              } else if (usedRefSnap.value is Map) {
                                usedReceipts = (usedRefSnap.value as Map).values.toList();
                              }
                            }
                            usedReceipts.add(extractedRefNo);
                            if (usedReceipts.length > 500) {
                              usedReceipts = usedReceipts.sublist(usedReceipts.length - 500);
                            }
                            await FirebaseDatabase.instance.ref("used_receipts/${widget.ownerUid}").set(usedReceipts);
                          } catch (e) {}
                        }

                        // Push booking record
                        final newBookingRef = FirebaseDatabase.instance.ref("bookings").push();
                        final String firstTitle = chosenItems.first['title'];
                        final String bookingTitle = chosenItems.length == 1
                            ? firstTitle
                            : "$firstTitle + ${chosenItems.length - 1} other activities";

                        List<String> selectedAddonsList = [];
                        mealCounts.forEach((key, count) {
                          if (count > 0) selectedAddonsList.add('$key Set Menu (x$count)');
                        });

                        await newBookingRef.set({
                          'touristUid': user.uid,
                          'touristName': touristName,
                          'touristProfilePic': touristPic,
                          'ownerUid': widget.ownerUid,
                          'activityId': chosenItems.first['id'],
                          'isActivityBooking': true,
                          'propertyName': widget.propertyName,
                          'activityTitle': bookingTitle,
                          'selectedActivities': chosenItems,
                          'pricing': {
                            'activitiesSubtotal': activitiesSubtotal,
                            'soloSurcharges': soloSurcharges,
                            'mealsTotal': mealsTotal,
                            'grandTotal': grandTotal,
                          },
                          'totalPrice': grandTotal,
                          'amountPaid': paymentAmount,
                          'nights': 1,
                          'hours': 1,
                          'bookingDate': DateFormat('MMM dd, yyyy').format(date),
                          'status': 'Pending',
                          'paymentStatus': 'pending',
                          'paymentMethod': 'GCash',
                          'paymentOption': method.contains('30%') ? '30% Downpayment' : 'Full Payment',
                          'gcashReceipt': receipt,
                          'extractedRefNo': extractedRefNo ?? '',
                          'ocrStatus': ocrStatus ?? 'Unverified',
                          'agreedToTerms': true,
                          'termsAcceptedAt': ServerValue.timestamp,
                          'timestamp': ServerValue.timestamp,
                          'selectedAddons': selectedAddonsList,
                        });

                        // Notification to Owner
                        await FirebaseDatabase.instance.ref("notifications/${widget.ownerUid}").push().set({
                          'title': ocrStatus == 'Flagged' ? 'Auto-declined Activity Booking' : 'New Activity Booking',
                          'message': ocrStatus == 'Flagged'
                              ? '$touristName\'s activity booking was auto-declined due to invalid payment.'
                              : '$touristName booked activities ($bookingTitle) for ${DateFormat('MMM dd, yyyy').format(date)}.',
                          'type': 'new_booking',
                          'isRead': false,
                          'timestamp': ServerValue.timestamp,
                          'bookingId': newBookingRef.key,
                        });

                        if (context.mounted) {
                          Navigator.pop(dialogCtx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(ocrStatus == 'Flagged'
                                  ? 'Activity booking auto-declined due to invalid payment proof.'
                                  : 'Activity booking submitted successfully!'),
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Confirm & Book'),
              ),
            ],
          );
        },
      ),
    );
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
    final double? lat = double.tryParse(_currentData['latitude']?.toString() ?? '');
    final double? lng = double.tryParse(_currentData['longitude']?.toString() ?? '');

    if (lat == null || lng == null || (lat == 0 && lng == 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location not set by owner.')));
      return;
    }

    final String googleMapsUrl = "https://www.google.com/maps/search/?api=1&query=$lat,$lng";
    final Uri url = Uri.parse(googleMapsUrl);

    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open maps.')));
      }
    }
  }

  void _showMenuGallery(BuildContext context, List<String> menuUrls) {
    if (menuUrls.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text('Food Menu', style: TextStyle(color: Colors.white)),
          ),
          body: PageView.builder(
            itemCount: menuUrls.length,
            itemBuilder: (context, i) => InteractiveViewer(
              child: Center(
                child: Image.network(
                  menuUrls[i],
                  fit: BoxFit.contain,
                  errorBuilder: (c, e, s) => const Icon(Icons.broken_image, color: Colors.white, size: 50),
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 2,
                              ),
                              onPressed: () async {
                                final lat = _currentData['latitude'];
                                final lng = _currentData['longitude'];
                                final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
                                try {
                                  await launchUrl(url, mode: LaunchMode.externalApplication);
                                } catch (e) {
                                  // ignore
                                }
                              },
                              icon: const Icon(Icons.directions, size: 24),
                              label: const Text('Get Directions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                        if ((_currentData['enableCustomMenuUpload'] == true || _currentData['enableCustomMenuUpload'] == 'true') && _currentData['foodMenuUrls'] != null && _parseList(_currentData['foodMenuUrls']).isNotEmpty) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 24),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.restaurant_menu, color: Theme.of(context).colorScheme.primary),
                                    const SizedBox(width: 8),
                                    Text('Food Menu Available', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text('Lunch & Dinner options are available at this property. No advance booking required.', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      _showMenuGallery(context, _parseList(_currentData['foodMenuUrls']));
                                    },
                                    icon: const Icon(Icons.image_search, size: 18),
                                    label: const Text('View Menus', style: TextStyle(fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Theme.of(context).colorScheme.primary,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
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
                        if (_currentData['showActivities'] != false && _currentData['showActivities'] != 'false') ...[
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            runSpacing: 10,
                            children: [
                              Text(
                                'Available Activities',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _showMultiActivityBookingSheet,
                                icon: const Icon(Icons.kayaking, size: 18),
                                label: const Text('Book Activities',
                                    style: TextStyle(fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryAccent,
                                  foregroundColor: Colors.white,
                                  elevation: 2,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ]),
                ),
              ),
              if (_currentData['showActivities'] != false && _currentData['showActivities'] != 'false')
                SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: StreamBuilder<DatabaseEvent>(
                  stream: FirebaseDatabase.instance
                      .ref("properties/${widget.ownerUid}/activities")
                      .onValue,
                  builder: (context, snap) {
                    if (!snap.hasData || snap.data!.snapshot.value == null) {
                      return const SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text("No separate activities listed yet.", style: TextStyle(color: Colors.grey)),
                          ),
                        ),
                      );
                    }

                    Map<String, dynamic> acts = {};
                    final raw = snap.data!.snapshot.value;
                    if (raw is Map) {
                      acts = Map<String, dynamic>.from(raw);
                    } else if (raw is List) {
                      for (int i = 0; i < raw.length; i++) {
                        if (raw[i] != null) acts[i.toString()] = raw[i];
                      }
                    }

                    if (acts.isEmpty) {
                      return const SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text("No separate activities listed yet.", style: TextStyle(color: Colors.grey)),
                          ),
                        ),
                      );
                    }

                    final keys = acts.keys.toList();
                    return SliverList(
                      delegate: SliverChildBuilderDelegate((context, i) {
                        final actId = keys[i];
                        final actData = Map<String, dynamic>.from(acts[actId] as Map);
                        final title = actData['title'] ?? 'Activity';
                        final price = actData['price'] ?? 0;
                        final desc = actData['description'] ?? '';
                        final maxPax = actData['maxPax'] ?? 0;
                        final List imgList = actData['imageUrls'] is List ? actData['imageUrls'] : [];
                        final firstImg = imgList.isNotEmpty ? imgList.first.toString() : null;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          clipBehavior: Clip.antiAlias,
                          elevation: 2,
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ActivityDetailsPage(
                                    activityId: actId,
                                    activityData: actData,
                                    ownerUid: widget.ownerUid,
                                    propertyName: widget.propertyName,
                                    propertyData: _currentData,
                                  ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (firstImg != null) ...[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(
                                        firstImg,
                                        height: 160,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        errorBuilder: (c, e, s) => Container(
                                          height: 160,
                                          color: Colors.grey[200],
                                          child: const Icon(Icons.kayaking, size: 48, color: Colors.grey),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(title,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('₱$price/pax',
                                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.amber)),
                                    ],
                                  ),
                                  if (desc.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                                  ],
                                  if (maxPax > 0) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Max $maxPax pax',
                                        style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => ActivityDetailsPage(
                                              activityId: actId,
                                              activityData: actData,
                                              ownerUid: widget.ownerUid,
                                              propertyName: widget.propertyName,
                                              propertyData: _currentData,
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.calendar_month, size: 18),
                                      label: const Text('BOOK ACTIVITY', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.amber[700],
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        elevation: 0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }, childCount: keys.length),
                    );
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
                  child: Text('Available Rooms',
                      style: Theme.of(context).textTheme.titleLarge),
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

                      final activeKeys = acts.keys.where((k) => acts[k]['isAvailable'] != false && acts[k]['isDisabled'] != true).toList();

                      if (activeKeys.isEmpty) {
                        return const SliverToBoxAdapter(
                            child: Center(
                                child: Padding(
                                    padding: EdgeInsets.all(40),
                                    child: Text("No rooms available yet.", style: TextStyle(color: Colors.grey)))));
                      }

                      return SliverList(
                          delegate: SliverChildBuilderDelegate((context, i) {
                        String key = activeKeys[i];
                        Map act = acts[key];

                        return _buildRoomCard(context, key, act);
                      }, childCount: activeKeys.length));
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
    List<String> amenities = {
      ..._parseList(act['amenities']),
      ..._parseList(act['inclusions'])
    }.toList();

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

class MaxIntInputFormatter extends TextInputFormatter {
  final int max;
  MaxIntInputFormatter(this.max);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    int? val = int.tryParse(newValue.text);
    if (val != null && val > max) {
      return TextEditingValue(
        text: max.toString(),
        selection: TextSelection.collapsed(offset: max.toString().length),
      );
    }
    return newValue;
  }
}
