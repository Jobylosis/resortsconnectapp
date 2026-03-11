import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'chat_page.dart';

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
  // --- CLOUDINARY CONFIG ---
  final String _cloudName = "dnv6ezitm";
  final String _uploadPreset = "resort_unsigned";

  final Color _brandPrimary = const Color(0xFF2196F3);
  final Color _brandAccent = const Color(0xFFFF8F00);
  final Color _bgColor = const Color(0xFFF8F9FA);
  
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isUploading = false;

  Map _currentData = {};

  @override
  void initState() {
    super.initState();
    _currentData = widget.propertyData;
  }

  @override
  void dispose() {
    _pageController.dispose();
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

  // --- CLOUDINARY UPLOAD ---
  Future<String?> _uploadToCloudinary(File file, {bool isVideo = false}) async {
    if (!mounted) return null;
    setState(() => _isUploading = true);
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
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Upload failed. Check settings.")));
        return null;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
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
        final String? url = await _uploadToCloudinary(File(file.path), isVideo: true);
        if (url != null) {
          List<String> vids = _parseList(_currentData['videoUrls']);
          vids.add(url);
          await FirebaseDatabase.instance.ref("properties/${user?.uid}").update({'videoUrls': vids});
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
        await FirebaseDatabase.instance.ref("properties/${user?.uid}").update({'imageUrls': imgs});
      }
    }
  }

  void _showManageMediaSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
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
                Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(5)), margin: const EdgeInsets.only(bottom: 20)),
                const Text('Manage Property Media', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Expanded(
                  child: (imgs.isEmpty && vids.isEmpty)
                    ? const Center(child: Text("No media to manage."))
                    : ListView(
                        controller: scrollController,
                        children: [
                          if (imgs.isNotEmpty) ...[
                            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text("Photos", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
                              itemCount: imgs.length,
                              itemBuilder: (context, i) => _buildMediaGridItem(imgs[i], true, () async {
                                final confirm = await _showConfirmDelete();
                                if (confirm == true) {
                                  imgs.removeAt(i);
                                  setModalState(() {});
                                  await FirebaseDatabase.instance.ref("properties/${widget.ownerUid}").update({'imageUrls': imgs});
                                }
                              }),
                            ),
                          ],
                          if (vids.isNotEmpty) ...[
                            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text("Videos", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.5),
                              itemCount: vids.length,
                              itemBuilder: (context, i) => _buildMediaGridItem(vids[i], false, () async {
                                final confirm = await _showConfirmDelete();
                                if (confirm == true) {
                                  vids.removeAt(i);
                                  setModalState(() {});
                                  await FirebaseDatabase.instance.ref("properties/${widget.ownerUid}").update({'videoUrls': vids});
                                }
                              }),
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

  Widget _buildMediaGridItem(String url, bool isImg, VoidCallback onDelete) => Stack(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: isImg 
          ? Image.network(url, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
          : Container(color: Colors.black, child: const Center(child: Icon(Icons.play_circle_outline, color: Colors.white, size: 30))),
      ),
      Positioned(top: 4, right: 4, child: GestureDetector(onTap: onDelete, child: const CircleAvatar(radius: 12, backgroundColor: Colors.red, child: Icon(Icons.close, size: 14, color: Colors.white)))),
    ],
  );

  Future<bool?> _showConfirmDelete() => showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Delete Media?'), content: const Text('This action cannot be undone.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red)))]));

  void _editTextField(String field, String label, String currentVal, {int maxLines = 1, bool isNumber = false}) {
    final controller = TextEditingController(text: currentVal);
    showDialog(context: context, builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Edit $label'),
      content: TextField(controller: controller, maxLines: maxLines, keyboardType: isNumber ? TextInputType.number : TextInputType.text, decoration: InputDecoration(hintText: "Enter $label", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () async {
        dynamic val = isNumber ? (int.tryParse(controller.text) ?? 0) : controller.text.trim();
        await FirebaseDatabase.instance.ref("properties/${widget.ownerUid}").update({field: val});
        if (mounted) Navigator.pop(context);
      }, style: ElevatedButton.styleFrom(backgroundColor: _brandPrimary, foregroundColor: Colors.white), child: const Text('Save'))],
    ));
  }

  // --- BOOKING LOGIC ---
  Future<void> _checkAndStartBooking(String activityId, Map activity) async {
    if (widget.isOwner) return;
    final user = FirebaseAuth.instance.currentUser;
    final myBookingCheck = await FirebaseDatabase.instance.ref("bookings").orderByChild("touristUid").equalTo(user?.uid).get();
    if (myBookingCheck.exists) {
      Map bookings = myBookingCheck.value as Map;
      // Check for active (Pending or Confirmed) bookings for this specific activity
      bool hasActive = bookings.values.any((b) => 
        b['activityId'] == activityId && 
        (b['status'] == 'Pending' || b['status'] == 'Confirmed')
      );
      
      if (hasActive) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You have an active booking for this!'), backgroundColor: Colors.orange));
        return;
      }
    }
    _selectBookingDetails(activityId, activity);
  }

  Future<void> _selectBookingDetails(String activityId, Map activity) async {
    DateTime? date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (date == null) return;
    TimeOfDay? time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    final dateStr = DateFormat('MMM dd, yyyy').format(date);
    final timeStr = time.format(context);
    final snap = await FirebaseDatabase.instance.ref("bookings").orderByChild("ownerUid").equalTo(widget.ownerUid).get();
    if (snap.exists) {
      Map all = snap.value as Map;
      bool taken = all.values.any((b) => b['activityId'] == activityId && b['bookingDate'] == dateStr && b['bookingTime'] == timeStr && (b['status'] == 'Pending' || b['status'] == 'Confirmed'));
      if (taken) { if (mounted) _showOverbooked(activity['title'], dateStr, timeStr); return; }
    }
    if (mounted) _confirmBooking(activityId, activity, date, time);
  }

  void _showOverbooked(String t, String d, String tm) => showDialog(context: context, builder: (context) => AlertDialog(title: const Text('Unavailable'), content: Text('"$t" is reserved for $d at $tm.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));

  void _confirmBooking(String activityId, Map activity, DateTime date, TimeOfDay time) {
    final dateStr = DateFormat('MMM dd, yyyy').format(date);
    final timeStr = time.format(context);
    int nights = 1;
    double basePrice = double.tryParse(activity['price'].toString()) ?? 0;
    String paymentMethod = 'Onsite';
    String? gcashReceipt;

    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setS) {
      double total = basePrice * nights;
      double downPayment = total * 0.30;

      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Text('Confirm Booking'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(activity['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('₱${basePrice.toStringAsFixed(2)} per night'),
            const Divider(height: 32),
            const Text('Duration:', style: TextStyle(fontWeight: FontWeight.w600)),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(onPressed: nights > 1 ? () => setS(() => nights--):null, icon: const Icon(Icons.remove_circle_outline)),
              Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(12)), child: Text('$nights Nights', style: const TextStyle(fontWeight: FontWeight.bold))),
              IconButton(onPressed: () => setS(() => nights++), icon: const Icon(Icons.add_circle_outline)),
            ]),
            const SizedBox(height: 20),
            const Text('Payment Method:', style: TextStyle(fontWeight: FontWeight.w600)),
            DropdownButton<String>(
              value: paymentMethod,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'Onsite', child: Text('Pay Onsite (Full)')),
                DropdownMenuItem(value: 'GCash', child: Text('GCash (30% Down Payment)')),
              ],
              onChanged: (val) => setS(() => paymentMethod = val!),
            ),
            if (paymentMethod == 'GCash') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Owner GCash Details:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  Text('Number: ${widget.propertyData['gcashNumber'] ?? 'N/A'}'),
                  Text('Name: ${widget.propertyData['gcashName'] ?? 'N/A'}'),
                  const SizedBox(height: 8),
                  Text('Down Payment: ₱${downPayment.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                ]),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  final picker = ImagePicker();
                  final XFile? file = await picker.pickImage(source: ImageSource.gallery);
                  if (file != null) {
                    final url = await _uploadToCloudinary(File(file.path));
                    if (url != null) setS(() => gcashReceipt = url);
                  }
                },
                icon: const Icon(Icons.upload_file),
                label: Text(gcashReceipt != null ? 'Receipt Uploaded' : 'Upload Proof of Payment'),
                style: ElevatedButton.styleFrom(backgroundColor: gcashReceipt != null ? Colors.green : Colors.blue),
              ),
            ],
            const Divider(height: 32),
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(15)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Total:', style: TextStyle(fontWeight: FontWeight.bold)), Text('₱${total.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 20))])),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: (paymentMethod == 'GCash' && gcashReceipt == null) ? null : () {
              Navigator.pop(context);
              _processBooking(activityId, activity, dateStr, timeStr, nights, total, paymentMethod, gcashReceipt);
            },
            style: ElevatedButton.styleFrom(backgroundColor: _brandPrimary, foregroundColor: Colors.white),
            child: const Text('Book Now'),
          )
        ],
      );
    }));
  }

  Future<void> _processBooking(String id, Map act, String d, String t, int n, double tp, String method, String? receipt) async {
    final user = FirebaseAuth.instance.currentUser;
    final snap = await FirebaseDatabase.instance.ref("users/${user?.uid}").get();
    String name = "Guest";
    if (snap.exists) { Map u = snap.value as Map; name = "${u['firstName']} ${u['lastName']}"; }
    try {
      await FirebaseDatabase.instance.ref("bookings").push().set({
        'touristUid': user?.uid,
        'touristName': name,
        'ownerUid': widget.ownerUid,
        'activityId': id,
        'propertyName': widget.propertyName,
        'activityTitle': act['title'],
        'price': act['price'],
        'totalPrice': tp,
        'nights': n,
        'bookingDate': d,
        'bookingTime': t,
        'status': 'Pending',
        'paymentMethod': method,
        'gcashReceipt': receipt,
        'timestamp': ServerValue.timestamp
      });
      await FirebaseDatabase.instance.ref("notifications/${widget.ownerUid}").push().set({'title': 'New Booking', 'message': '$name booked "${act['title']}"', 'type': 'booking_new', 'isRead': false, 'timestamp': ServerValue.timestamp});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking request sent!'), backgroundColor: Colors.green));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
  }

  void _openFullScreenMedia(List<Map<String, dynamic>> combinedMedia, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenMediaViewer(media: combinedMedia, initialIndex: initialIndex),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref("properties/${widget.ownerUid}").onValue,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.snapshot.exists) { _currentData = snapshot.data!.snapshot.value as Map; }
        final imgs = _parseList(_currentData['imageUrls']);
        final vids = _parseList(_currentData['videoUrls']);
        final List<Map<String, dynamic>> combined = [
          ...imgs.map((url) => {'url': url, 'type': 'image'}),
          ...vids.map((url) => {'url': url, 'type': 'video'}),
        ];

        return Scaffold(
          backgroundColor: _bgColor,
          floatingActionButton: widget.isOwner ? null : FloatingActionButton.extended(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChatPage(otherUserUid: widget.ownerUid, otherUserName: widget.propertyName))),
            label: const Text('Chat with Owner', style: TextStyle(fontWeight: FontWeight.bold)),
            icon: const Icon(Icons.message_rounded),
            backgroundColor: _brandPrimary,
          ),
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 350,
                pinned: true,
                elevation: 0,
                backgroundColor: _brandPrimary,
                leading: Container(margin: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context))),
                actions: widget.isOwner ? [
                  _appBarAction(Icons.photo_library, _showManageMediaSheet),
                  _appBarAction(Icons.add_a_photo, () => _pickAndUploadMedia(isVideo: false)),
                  _appBarAction(Icons.video_call, () => _pickAndUploadMedia(isVideo: true)),
                ] : null,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (combined.isNotEmpty)
                        PageView.builder(
                          controller: _pageController,
                          itemCount: combined.length,
                          onPageChanged: (index) => setState(() => _currentPage = index),
                          itemBuilder: (context, index) {
                            final m = combined[index];
                            final String? url = m['url'] as String?;
                            if (url == null) return Container(color: Colors.grey);
                            return GestureDetector(
                              onTap: () => _openFullScreenMedia(combined, index),
                              child: m['type'] == 'video' 
                                ? VideoPlayerWidget(url: url) 
                                : Image.network(url, fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(color: Colors.grey[300], child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)))),
                            );
                          },
                        )
                      else
                        Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_brandPrimary, _brandPrimary.withOpacity(0.7)])), child: const Center(child: Icon(Icons.beach_access, size: 100, color: Colors.white))),
                      
                      const IgnorePointer(
                        child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.center, colors: [Colors.black54, Colors.transparent]))),
                      ),
                      
                      if (_isUploading) const Center(child: CircularProgressIndicator(color: Colors.white)),
                      
                      if (combined.length > 1)
                        Positioned(bottom: 20, left: 0, right: 0, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(combined.length, (index) => AnimatedContainer(duration: const Duration(milliseconds: 300), margin: const EdgeInsets.symmetric(horizontal: 4), height: 8, width: _currentPage == index ? 24 : 8, decoration: BoxDecoration(color: _currentPage == index ? Colors.white : Colors.white54, borderRadius: BorderRadius.circular(12)))))),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  transform: Matrix4.translationValues(0, -30, 0),
                  decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(35))),
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Text(_currentData['name'] ?? widget.propertyName, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5))),
                        if (widget.isOwner) IconButton(icon: const Icon(Icons.edit_outlined, size: 22, color: Colors.blue), onPressed: () => _editTextField('name', 'Name', _currentData['name'] ?? ''))
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        _infoChip(_currentData['type'] ?? 'Resort', Icons.category, Colors.blue),
                        const SizedBox(width: 8),
                        _infoChip('${_currentData['rooms']} Rooms', Icons.meeting_room, Colors.orange),
                        const SizedBox(width: 8),
                        _infoChip('${_currentData['staffCount']} Staff', Icons.groups, Colors.green),
                      ]),
                      const SizedBox(height: 32),
                      Row(children: [
                        const Text('Description', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        if (widget.isOwner) IconButton(icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.blue), onPressed: () => _editTextField('description', 'Description', _currentData['description'] ?? '', maxLines: 4))
                      ]),
                      const SizedBox(height: 12),
                      Text(_currentData['description'] ?? 'No description available.', style: TextStyle(color: Colors.grey[700], fontSize: 15, height: 1.6)),
                      const SizedBox(height: 40),
                      const Text('Offers & Services', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: StreamBuilder<DatabaseEvent>(
                  stream: FirebaseDatabase.instance.ref("activities/${widget.ownerUid}").onValue,
                  builder: (snapContext, snap) {
                    if (!snap.hasData || snap.data!.snapshot.value == null) return const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(20), child: Center(child: Text("No offers yet."))));
                    Map activities = snap.data!.snapshot.value as Map;
                    List<MapEntry> items = activities.entries.toList();
                    return SliverList(delegate: SliverChildBuilderDelegate((context, i) => _buildActivityCard(items[i].value as Map, items[i].key), childCount: items.length));
                  }
                ),
              ),
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(24, 40, 24, 16), child: Text('User Reviews', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.5)))),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: StreamBuilder<DatabaseEvent>(
                  stream: FirebaseDatabase.instance.ref("reviews/${widget.ownerUid}").onValue,
                  builder: (context, snap) {
                    if (!snap.hasData || snap.data!.snapshot.exists == false) return const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(20), child: Center(child: Text("No reviews yet."))));
                    Map reviews = snap.data!.snapshot.value as Map;
                    List items = reviews.values.toList();
                    return SliverList(delegate: SliverChildBuilderDelegate((context, i) => _buildReviewCard(items[i]), childCount: items.length));
                  },
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        );
      },
    );
  }

  Widget _appBarAction(IconData icon, VoidCallback onTap) => Container(margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: IconButton(icon: Icon(icon, color: Colors.white, size: 20), onPressed: onTap));

  Widget _infoChip(String label, IconData icon, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
    child: Row(children: [Icon(icon, size: 14, color: color), const SizedBox(width: 6), Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12))]),
  );

  Widget _buildActivityCard(Map act, String id) {
    final imgs = _parseList(act['imageUrls']);
    final vid = act['videoUrl'];
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 10))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (vid != null) ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(24)), child: SizedBox(height: 200, child: VideoPlayerWidget(url: vid)))
          else if (imgs.isNotEmpty) ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(24)), child: Image.network(imgs[0], height: 180, width: double.infinity, fit: BoxFit.cover))
          else Container(height: 100, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: const BorderRadius.vertical(top: Radius.circular(24))), child: const Center(child: Icon(Icons.image_outlined, color: Colors.grey))),
          
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Text(act['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                Text('₱${act['price']}', style: TextStyle(fontWeight: FontWeight.w900, color: _brandPrimary, fontSize: 20)),
              ]),
              const SizedBox(height: 8),
              Text(act['description'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 14, height: 1.4)),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => _checkAndStartBooking(id, act), style: ElevatedButton.styleFrom(backgroundColor: widget.isOwner ? Colors.grey[200] : _brandAccent, foregroundColor: widget.isOwner ? Colors.grey : Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: Text(widget.isOwner ? 'PREVIEW ONLY' : 'BOOK NOW', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)))),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(Map review) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey[100]!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(review['touristName'] ?? 'Tourist', style: const TextStyle(fontWeight: FontWeight.bold)),
              Row(children: List.generate(5, (index) => Icon(Icons.star_rounded, size: 16, color: index < (review['rating'] ?? 0) ? Colors.amber : Colors.grey[300]))),
            ],
          ),
          const SizedBox(height: 8),
          Text(review['comment'] ?? '', style: TextStyle(color: Colors.grey[700], height: 1.4)),
          const SizedBox(height: 12),
          Text(DateFormat('MMM dd, yyyy').format(DateTime.fromMillisecondsSinceEpoch(review['timestamp'] ?? 0)), style: TextStyle(color: Colors.grey[400], fontSize: 11)),
        ],
      ),
    );
  }
}

class FullScreenMediaViewer extends StatefulWidget {
  final List<Map<String, dynamic>> media;
  final int initialIndex;
  const FullScreenMediaViewer({super.key, required this.media, required this.initialIndex});
  @override
  State<FullScreenMediaViewer> createState() => _FullScreenMediaViewerState();
}

class _FullScreenMediaViewerState extends State<FullScreenMediaViewer> {
  late PageController _pc;
  late int _idx;
  @override
  void initState() { super.initState(); _idx = widget.initialIndex; _pc = PageController(initialPage: widget.initialIndex); }
  @override
  void dispose() { _pc.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white), title: Text('${_idx + 1} / ${widget.media.length}', style: const TextStyle(color: Colors.white))),
      body: PageView.builder(
        controller: _pc,
        itemCount: widget.media.length,
        onPageChanged: (i) => setState(() => _idx = i),
        itemBuilder: (context, i) {
          final m = widget.media[i];
          return m['type'] == 'video' ? Center(child: VideoPlayerWidget(url: m['url'])) : Center(child: InteractiveViewer(child: Image.network(m['url'], fit: BoxFit.contain)));
        },
      ),
    );
  }
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
    _vpc.initialize().then((_) { if (mounted) setState(() { _cc = ChewieController(videoPlayerController: _vpc, aspectRatio: _vpc.value.aspectRatio, autoPlay: false, looping: false, placeholder: const Center(child: CircularProgressIndicator())); }); });
  }
  @override
  void dispose() { _vpc.dispose(); _cc?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) { return _cc != null && _vpc.value.isInitialized ? Chewie(controller: _cc!) : const Center(child: CircularProgressIndicator()); }
}
