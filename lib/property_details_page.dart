import 'package:flutter/material.dart';
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
import 'chat_page.dart';
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
      }
      return null;
    } catch (e) { return null; }
    finally { if (mounted) setState(() => _isUploading = false); }
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
                const Text('Manage Media', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      if (imgs.isNotEmpty) ...[
                        const Text("Photos", style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
                          itemCount: imgs.length,
                          itemBuilder: (context, i) => Stack(children: [
                            ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(imgs[i], fit: BoxFit.cover, height: 100, width: 100)),
                            Positioned(top: 4, right: 4, child: GestureDetector(onTap: () async {
                              imgs.removeAt(i);
                              await FirebaseDatabase.instance.ref("properties/${widget.ownerUid}").update({'imageUrls': imgs});
                              setModalState(() {});
                            }, child: const CircleAvatar(radius: 10, backgroundColor: AppTheme.primaryAccent, child: Icon(Icons.close, size: 12, color: Colors.white)))),
                          ]),
                        ),
                      ],
                      if (vids.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text("Videos", style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.5),
                          itemCount: vids.length,
                          itemBuilder: (context, i) => Stack(children: [
                            Container(decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)), child: const Center(child: Icon(Icons.play_circle, color: Colors.white, size: 30))),
                            Positioned(top: 4, right: 4, child: GestureDetector(onTap: () async {
                              vids.removeAt(i);
                              await FirebaseDatabase.instance.ref("properties/${widget.ownerUid}").update({'videoUrls': vids});
                              setModalState(() {});
                            }, child: const CircleAvatar(radius: 10, backgroundColor: AppTheme.primaryAccent, child: Icon(Icons.close, size: 12, color: Colors.white)))),
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

  void _editTextField(String field, String label, String currentVal, {int maxLines = 1, bool isNumber = false}) {
    final controller = TextEditingController(text: currentVal);
    showDialog(context: context, builder: (context) => AlertDialog(
      title: Text('Edit $label'),
      content: TextField(controller: controller, maxLines: maxLines, keyboardType: isNumber ? TextInputType.number : TextInputType.text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), 
        ElevatedButton(
          onPressed: () async {
            dynamic val = isNumber ? (int.tryParse(controller.text) ?? 0) : controller.text.trim();
            await FirebaseDatabase.instance.ref("properties/${widget.ownerUid}").update({field: val});
            Navigator.pop(context);
          }, 
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
          child: const Text('Save'),
        )
      ],
    ));
  }

  Future<void> _checkAndStartBooking(String activityId, Map activity) async {
    if (widget.isOwner) return;
    final user = FirebaseAuth.instance.currentUser;
    final snap = await FirebaseDatabase.instance.ref("bookings").orderByChild("touristUid").equalTo(user?.uid).get();
    if (snap.exists) {
      Map bookings = snap.value as Map;
      bool hasActive = bookings.values.any((b) => b['activityId'] == activityId && (b['status'] == 'Pending' || b['status'] == 'Confirmed'));
      if (hasActive) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You have an active booking!')));
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
    _confirmBooking(activityId, activity, date, time);
  }

  void _confirmBooking(String activityId, Map activity, DateTime date, TimeOfDay time) {
    int nights = 1;
    String method = 'Onsite';
    String? receipt;
    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setS) {
      double total = (double.tryParse(activity['price'].toString()) ?? 0) * nights;
      return AlertDialog(
        title: const Text('Confirm Booking'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(activity['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(onPressed: nights > 1 ? () => setS(() => nights--) : null, icon: const Icon(Icons.remove_circle_outline)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('$nights Nights', style: const TextStyle(fontWeight: FontWeight.bold))),
              IconButton(onPressed: () => setS(() => nights++), icon: const Icon(Icons.add_circle_outline)),
            ]),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: method, 
              decoration: const InputDecoration(labelText: 'Payment Method'),
              items: const [DropdownMenuItem(value: 'Onsite', child: Text('Onsite')), DropdownMenuItem(value: 'GCash', child: Text('GCash (30% Down)'))], 
              onChanged: (v) => setS(() => method = v!),
            ),
            if (method == 'GCash') ...[
              const SizedBox(height: 16),
              Text('Pay ₱${(total * 0.3).toStringAsFixed(2)} to:'),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: SelectableText('GCash: ${_currentData['gcashNumber'] ?? 'N/A'}\nName: ${_currentData['gcashName'] ?? 'N/A'}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final XFile? file = await ImagePicker().pickImage(source: ImageSource.gallery);
                  if (file != null) {
                    final url = await _uploadToCloudinary(File(file.path));
                    if (url != null) setS(() => receipt = url);
                  }
                }, 
                icon: const Icon(Icons.upload_file),
                label: Text(receipt == null ? 'Upload Receipt' : 'Receipt Uploaded'),
              ),
            ],
            const SizedBox(height: 24),
            Text('Total: ₱${total.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Theme.of(context).colorScheme.secondary)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), 
          ElevatedButton(
            onPressed: (method == 'GCash' && receipt == null) ? null : () async {
              final user = FirebaseAuth.instance.currentUser;
              final snap = await FirebaseDatabase.instance.ref("users/${user?.uid}").get();
              String name = "${(snap.value as Map)['firstName']} ${(snap.value as Map)['lastName']}";
              await FirebaseDatabase.instance.ref("bookings").push().set({
                'touristUid': user?.uid, 'touristName': name, 'ownerUid': widget.ownerUid, 'activityId': activityId, 'propertyName': widget.propertyName,
                'activityTitle': activity['title'], 'price': activity['price'], 'totalPrice': total, 'nights': nights,
                'bookingDate': DateFormat('MMM dd, yyyy').format(date), 'bookingTime': time.format(context), 'status': 'Pending',
                'paymentMethod': method, 'gcashReceipt': receipt, 'timestamp': ServerValue.timestamp
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking request sent successfully!')));
            }, 
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.secondary, foregroundColor: Colors.black),
            child: const Text('Book Now'),
          )
        ],
      );
    }));
  }

  void _openFullScreenMedia(List<Map<String, dynamic>> media, int index) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
      body: PageView.builder(
        itemCount: media.length, controller: PageController(initialPage: index),
        itemBuilder: (context, i) => Center(child: media[i]['type'] == 'video' ? VideoPlayerWidget(url: media[i]['url']) : InteractiveViewer(child: Image.network(media[i]['url']))),
      ),
    )));
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref("properties/${widget.ownerUid}").onValue,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.snapshot.exists) { _currentData = snapshot.data!.snapshot.value as Map; }
        final combined = [..._parseList(_currentData['imageUrls']).map((u) => {'url': u, 'type': 'image'}), ..._parseList(_currentData['videoUrls']).map((u) => {'url': u, 'type': 'video'})];
        
        return Scaffold(
          floatingActionButton: widget.isOwner ? null : FloatingActionButton.extended(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChatPage(otherUserUid: widget.ownerUid, otherUserName: widget.propertyName))), 
            label: const Text('Chat with Owner'), 
            icon: const Icon(Icons.message_rounded), 
            backgroundColor: Theme.of(context).colorScheme.secondary,
            foregroundColor: Colors.black,
          ),
          body: CustomScrollView(slivers: [
            SliverAppBar(
              expandedHeight: 350, 
              pinned: true, 
              backgroundColor: Theme.of(context).colorScheme.background,
              actions: [
                if (widget.isOwner) ...[
                  IconButton(icon: const Icon(Icons.photo_library), onPressed: _showManageMediaSheet),
                  IconButton(icon: const Icon(Icons.add_a_photo), onPressed: () => _pickAndUploadMedia()),
                  IconButton(icon: const Icon(Icons.video_call), onPressed: () => _pickAndUploadMedia(isVideo: true)),
                ],
                IconButton(
                  icon: Icon(themeProvider.themeMode == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
                  onPressed: () => themeProvider.toggleTheme(),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(fit: StackFit.expand, children: [
                  if (combined.isNotEmpty) PageView.builder(
                    itemCount: combined.length, 
                    onPageChanged: (i) => setState(() => _currentPage = i), 
                    itemBuilder: (context, i) => GestureDetector(
                      onTap: () => _openFullScreenMedia(combined, i), 
                      child: combined[i]['type'] == 'video' ? VideoPlayerWidget(url: combined[i]['url']!) : Image.network(combined[i]['url']!, fit: BoxFit.cover),
                    ),
                  )
                  else Container(color: Theme.of(context).colorScheme.primary, child: const Icon(Icons.beach_access_rounded, size: 80, color: Colors.white)),
                  if (_isUploading) const Center(child: CircularProgressIndicator(color: Colors.white)),
                  if (combined.length > 1) Positioned(bottom: 40, left: 0, right: 0, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(combined.length, (i) => Container(margin: const EdgeInsets.symmetric(horizontal: 4), height: 8, width: _currentPage == i ? 24 : 8, decoration: BoxDecoration(color: _currentPage == i ? Colors.white : Colors.white54, borderRadius: BorderRadius.circular(12))))))
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.background, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))), 
                transform: Matrix4.translationValues(0, -30, 0),
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24), 
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Expanded(child: Text(_currentData['name'] ?? widget.propertyName, style: Theme.of(context).textTheme.headlineMedium)), 
                    if (widget.isOwner) IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => _editTextField('name', 'Name', _currentData['name'] ?? ''))
                  ]),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _chip(_currentData['type'] ?? 'Resort', Colors.blue, 'type'),
                    _chip('${_currentData['rooms']} Rooms', Colors.orange, 'rooms', isNum: true),
                    _chip('${_currentData['staffCount']} Staff', Colors.green, 'staffCount', isNum: true)
                  ]),
                  const SizedBox(height: 32),
                  Row(children: [Text('About', style: Theme.of(context).textTheme.titleLarge), if (widget.isOwner) IconButton(icon: const Icon(Icons.edit_rounded, size: 20), onPressed: () => _editTextField('description', 'Description', _currentData['description'] ?? '', maxLines: 4))]),
                  const SizedBox(height: 12),
                  Text(_currentData['description'] ?? 'No description provided.', style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 40),
                  Text('Available Offers', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24), 
              sliver: StreamBuilder<DatabaseEvent>(
                stream: FirebaseDatabase.instance.ref("activities/${widget.ownerUid}").onValue, 
                builder: (context, snap) {
                  if (!snap.hasData || snap.data!.snapshot.value == null) return const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(20), child: Text("No offers available yet."))));
                  Map acts = snap.data!.snapshot.value as Map;
                  return SliverList(delegate: SliverChildBuilderDelegate((context, i) {
                    String key = acts.keys.toList()[i];
                    Map act = acts[key];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(act['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), 
                        subtitle: Text('₱${act['price']}', style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.w900, fontSize: 18)), 
                        trailing: ElevatedButton(
                          onPressed: () => _checkAndStartBooking(key, act), 
                          style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.secondary, foregroundColor: Colors.black, minimumSize: const Size(100, 45)),
                          child: const Text('Book'),
                        ),
                      ),
                    );
                  }, childCount: acts.length));
                }
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ]),
        );
      }
    );
  }

  Widget _chip(String l, Color c, String f, {bool isNum = false}) => GestureDetector(
    onTap: widget.isOwner ? () => _editTextField(f, l, (_currentData[f] ?? '').toString(), isNumber: isNum) : null, 
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), 
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withOpacity(0.2))), 
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(l, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 12)), 
        if (widget.isOwner) ...[const SizedBox(width: 4), Icon(Icons.edit_rounded, size: 12, color: c)]
      ]),
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
      if (mounted) setState(() { 
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
    });
  }
  @override
  void dispose() { _vpc.dispose(); _cc?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) { return _cc != null ? Chewie(controller: _cc!) : const Center(child: CircularProgressIndicator()); }
}
