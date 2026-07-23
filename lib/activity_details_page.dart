import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:resortconnectapp/services/ai_service.dart';
import 'theme_provider.dart';
import 'theme.dart';

class ActivityDetailsPage extends StatefulWidget {
  final String activityId;
  final Map activityData;
  final String ownerUid;
  final String propertyName;

  const ActivityDetailsPage({
    super.key,
    required this.activityId,
    required this.activityData,
    required this.ownerUid,
    required this.propertyName,
  });

  @override
  State<ActivityDetailsPage> createState() => _ActivityDetailsPageState();
}

class _ActivityDetailsPageState extends State<ActivityDetailsPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final String _cloudName = "dnv6ezitm";
  final String _uploadPreset = "resort_unsigned";

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
    final data = snap.value;

    if (data == null) return false;

    if (data is Map) {
      allBookings = Map<String, dynamic>.from(data);
    } else if (data is List) {
      for (int i = 0; i < data.length; i++) {
        final item = data[i];
        if (item != null) allBookings[i.toString()] = item;
      }
    }

    DateTime endA = startDate.add(Duration(days: nights));

    for (var b in allBookings.values) {
      if (b is! Map) continue;

      String status = (b['status'] ?? '').toString().trim().toLowerCase();
      if (status != 'confirmed' && status != 'checked in') continue;

      try {
        DateTime startB = DateFormat('MMM dd, yyyy').parse(b['bookingDate']);
        int nightsB = int.tryParse(b['nights'].toString()) ?? 1;
        DateTime endB = startB.add(Duration(days: nightsB));

        if (_isOverlapping(startDate, endA, startB, endB)) return true;
      } catch (e) {/* skip */}
    }
    return false;
  }

  Future<void> _checkAndStartBooking() async {
    final user = FirebaseAuth.instance.currentUser;
    final myBookingCheck = await FirebaseDatabase.instance
        .ref("bookings")
        .orderByChild("touristUid")
        .equalTo(user?.uid)
        .get();
    if (myBookingCheck.exists) {
      Map bookings = myBookingCheck.value as Map;
      bool alreadyBookedByMe = bookings.values.any((b) =>
          b['activityId'] == widget.activityId &&
          (b['status'] == 'Pending' || b['status'] == 'Confirmed'));
      if (alreadyBookedByMe) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('You already have an active booking for this activity!')));
        return;
      }
    }
    _selectBookingDetails();
  }

  Future<void> _selectBookingDetails() async {
    DateTime? selectedDate = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)));
    if (selectedDate == null) return;

    if (!mounted) return;
    bool conflict =
        await _checkBookingConflict(widget.activityId, selectedDate, 1);
    if (conflict) {
      _showOverbookedDialog(widget.activityData['title'],
          DateFormat('MMM dd, yyyy').format(selectedDate));
      return;
    }

    _confirmBooking(selectedDate);
  }

  void _showOverbookedDialog(String title, String date) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Slot Unavailable'),
                content: Text(
                    'Sorry, "$title" is already reserved for $date. Please choose another date.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'))
                ]));
  }

  void _confirmBooking(DateTime date) {
    final dateStr = DateFormat('MMM dd, yyyy').format(date);
    int nights = 1;
    double basePrice =
        double.tryParse(widget.activityData['price'].toString()) ?? 0;
    List<String> selectedAddons = [];
    String? receiptUrl;
    String method = 'GCash (30% Down)';
    bool isUploading = false;
    bool agreedToTerms = false;
    String? extractedRefNo;
    String? ocrStatus;
    String? ocrIssues;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(builder: (context, setS) {
        double baseRoomTotal = basePrice * nights;
        double addonTotal = selectedAddons.length * 500.0; // Dummy price for activity addons
        double taxes = 0;
        double totalPrice = baseRoomTotal + addonTotal + taxes;
        double paymentAmount = method.contains('30%') ? totalPrice * 0.3 : totalPrice;

        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 24),
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Complete Your Booking',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Text(widget.activityData['title'],
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 8),
                  Text('Rate per night: ₱${basePrice.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const Divider(height: 32),
                  const Text('Duration of Stay:',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$nights ${nights > 1 ? 'Nights' : 'Night'}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Row(children: [
                          IconButton(
                              onPressed: nights > 1
                                  ? () => setS(() => nights--)
                                  : null,
                              icon: const Icon(Icons.remove_circle_outline)),
                          IconButton(
                              onPressed: () => setS(() => nights++),
                              icon: const Icon(Icons.add_circle_outline))
                        ])
                      ]),
                  const Divider(height: 32),
                  const Text('Select Add-ons:',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      'Breakfast',
                      'Extra Bed',
                      'Tour Guide',
                      'Equipment Rental'
                    ]
                        .map((addon) => FilterChip(
                              label: Text(addon),
                              selected: selectedAddons.contains(addon),
                              onSelected: (selected) {
                                setS(() {
                                  if (selected) {
                                    selectedAddons.add(addon);
                                  } else {
                                    selectedAddons.remove(addon);
                                  }
                                });
                              },
                            ))
                        .toList(),
                  ),
                  const Divider(height: 32),
                  const Text('Payment via GCash:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const Text('Send to: 09123456789 (Property Admin)',
                      style: TextStyle(fontSize: 13, color: Colors.blueGrey)),
                  const SizedBox(height: 12),
                  if (receiptUrl != null)
                    ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(receiptUrl!,
                            height: 150,
                            width: double.infinity,
                            fit: BoxFit.cover))
                  else
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: isUploading
                            ? null
                            : () async {
                                final picker = ImagePicker();
                                final XFile? file = await picker.pickImage(
                                    source: ImageSource.gallery);
                                if (file != null) {
                                  setS(() => isUploading = true);
                                  
                                  // Strict OCR Validation
                                  bool validationPassed = false;
                                  
                                  try {
                                    final ocrData = await AiService.extractGCashReference(
                                        File(file.path), 
                                        paymentAmount, 
                                        '' // Currently we don't fetch gcashName in ActivityDetailsPage easily, pass empty string or find a way. Let's pass empty string. It will skip recipient validation if expectedRecipient is empty in backend.
                                    );
                                    
                                    if (ocrData != null && ocrData['success'] == true) {
                                      validationPassed = true;
                                      extractedRefNo = ocrData['reference_number'].toString();
                                      ocrStatus = 'Verified';
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Receipt Validated! Ref: $extractedRefNo'), backgroundColor: Colors.green));
                                      }
                                    } else {
                                      ocrStatus = 'Flagged';
                                      ocrIssues = ocrData?['error'] ?? "Could not verify GCash receipt.";
                                      if (mounted) {
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Notice'),
                                            content: Text("$ocrIssues\n\nThe receipt will be sent to the owner for manual review."),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))
                                            ],
                                          )
                                        );
                                      }
                                    }
                                  } catch (e) {
                                    ocrStatus = 'Flagged';
                                    ocrIssues = "OCR Server unreachable.";
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notice: OCR service unreachable. Sent for manual review.')));
                                    }
                                  }

                                  final url = await _uploadToCloudinary(File(file.path));
                                  setS(() {
                                    receiptUrl = url;
                                    isUploading = false;
                                  });
                                }
                              },
                        icon: isUploading
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.upload_file),
                        label: Text(isUploading
                            ? 'Uploading...'
                            : 'Upload Payment Receipt'),
                      ),
                    ),
                  const Divider(height: 32),
                  Row(children: [
                    const Icon(Icons.calendar_today_rounded, size: 16),
                    const SizedBox(width: 12),
                    Text(dateStr)
                  ]),
                  const SizedBox(height: 24),
                          const Text('Price Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text('Activity Base ($nights ${nights == 1 ? "night" : "nights"})', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                            Text('₱${baseRoomTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          ]),
                          if (addonTotal > 0) ...[
                            const SizedBox(height: 6),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              const Text('Add-ons', style: TextStyle(color: Colors.grey, fontSize: 13)),
                              Text('₱${addonTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            ]),
                          ],
                          const Divider(height: 24, style: BorderStyle.none),
                          Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .secondary
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Booking Total',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    Text('₱${totalPrice.toStringAsFixed(2)}',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color:
                                                Theme.of(context).colorScheme.secondary,
                                            fontSize: 20))
                                  ])),
                  const Divider(height: 32),
                  DropdownButtonFormField<String>(
                    value: method,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Payment Method'),
                    items: [
                      DropdownMenuItem(
                          value: 'GCash (30% Down)',
                          child: Text('30% Downpayment (₱${(totalPrice * 0.3).toStringAsFixed(2)})', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(
                          value: 'GCash (100% Full)',
                          child: Text('100% Full Payment (₱${totalPrice.toStringAsFixed(2)})', overflow: TextOverflow.ellipsis))
                    ],
                    onChanged: (v) => setS(() {
                      method = v!;
                      receiptUrl = null;
                    }),
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
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                        onPressed: (isUploading || !agreedToTerms)
                            ? null
                            : () async {
                                if (receiptUrl == null) {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Action Required'),
                                      content: const Text('Please upload your payment receipt before completing the reservation.'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))
                                      ]
                                    )
                                  );
                                  return;
                                }
                                bool conflict = await _checkBookingConflict(
                                    widget.activityId, date, nights);
                                if (conflict) {
                                  if (mounted) {
                                    Navigator.pop(context);
                                    _showOverbookedDialog(
                                        widget.activityData['title'], dateStr);
                                  }
                                  return;
                                }
                                  if (mounted) {
                                    Navigator.pop(context);
                                    _processBooking(dateStr, nights, totalPrice,
                                        selectedAddons, receiptUrl!, method, extractedRefNo, ocrStatus, ocrIssues);
                                  }
                              },
                        child: const Text('SUBMIT BOOKING REQUEST')),
                  ),
                  const SizedBox(height: 32)
                ]),
          ),
        );
      }),
    );
  }

  Future<String?> _uploadToCloudinary(File file) async {
    try {
      final url =
          Uri.parse("https://api.cloudinary.com/v1_1/$_cloudName/image/upload");
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
    }
  }

  Future<void> _processBooking(String date, int nights, double totalPrice,
      List<String> addons, String receipt, String method, String? extractedRefNo, String? ocrStatus, String? ocrIssues) async {
    final user = FirebaseAuth.instance.currentUser;

    if (extractedRefNo != null && extractedRefNo.isNotEmpty) {
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
        
        if (usedReceipts.contains(extractedRefNo)) {
          if (mounted) {
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
        if (usedReceipts.length > 100) {
          usedReceipts = usedReceipts.sublist(usedReceipts.length - 100);
        }
        await FirebaseDatabase.instance.ref("used_receipts/${widget.ownerUid}").set(usedReceipts);
      } catch (e) {
        print("Error checking used receipts: $e");
      }
    }

    final bookingRef = FirebaseDatabase.instance.ref("bookings").push();
    final touristSnapshot =
        await FirebaseDatabase.instance.ref("users/${user?.uid}").get();
    String touristName = "Anonymous";
    String? touristProfilePic;
    if (touristSnapshot.exists) {
      Map data = touristSnapshot.value as Map;
      touristName = "${data['firstName']} ${data['lastName']}";
      touristProfilePic = data['profilePicUrl'];
    }
    double baseRoomTotal = (double.tryParse(widget.activityData['price'].toString()) ?? 0) * nights;
    double addonTotal = addons.length * 500.0;
    double taxes = 0;
    double calculatedTotal = baseRoomTotal + addonTotal + taxes;
    double paymentAmount = method.contains('30%') ? calculatedTotal * 0.3 : calculatedTotal;

    try {
      await bookingRef.set({
        'touristUid': user?.uid,
        'touristName': touristName,
        'touristProfilePic': touristProfilePic,
        'ownerUid': widget.ownerUid,
        'activityId': widget.activityId,
        'propertyName': widget.propertyName,
        'activityTitle': widget.activityData['title'],
        'price': widget.activityData['price'],
        'pricing': {
          'basePrice': baseRoomTotal,
          'addonsTotal': addonTotal,
          'taxes': taxes,
          'grandTotal': calculatedTotal
        },
        'totalPrice': calculatedTotal,
        'amountPaid': paymentAmount,
        'nights': nights,
        'bookingDate': date,
        'selectedAddons': addons,
        'gcashReceipt': receipt,
        'extractedRefNo': extractedRefNo ?? '',
        'ocrStatus': ocrStatus ?? 'Unverified',
        'ocrIssues': ocrIssues ?? '',
        'status': 'Pending',
        'paymentStatus': 'pending',
        'paymentMethod': 'GCash',
        'paymentOption': method.contains('30%') ? '30% Downpayment' : 'Full Payment',
        'agreedToTerms': true,
        'termsAcceptedAt': ServerValue.timestamp,
        'timestamp': ServerValue.timestamp
      });
      await FirebaseDatabase.instance
          .ref("notifications/${widget.ownerUid}")
          .push()
          .set({
        'title': 'New Booking Request',
        'message':
            '$touristName booked "${widget.activityData['title']}" for $nights nights.',
        'type': 'booking_new',
        'isRead': false,
        'timestamp': ServerValue.timestamp
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Booking request sent successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to book: $e'),
            backgroundColor: AppTheme.primaryAccent));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List imageUrls = widget.activityData['imageUrls'] ?? [];
    final themeProvider = Provider.of<ThemeProvider>(context);
    final secondaryColor = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
              expandedHeight: 350,
              pinned: true,
              backgroundColor: Theme.of(context).colorScheme.surface,
              actions: [
                IconButton(
                  icon: Icon(themeProvider.themeMode == ThemeMode.dark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded),
                  onPressed: () => themeProvider.toggleTheme(),
                ),
                const SizedBox(width: 8),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      itemCount: imageUrls.isNotEmpty ? imageUrls.length : 1,
                      onPageChanged: (index) =>
                          setState(() => _currentPage = index),
                      itemBuilder: (context, index) {
                        if (imageUrls.isEmpty) {
                          return Container(
                              color: Theme.of(context).colorScheme.primary,
                              child: const Icon(Icons.local_activity_rounded,
                                  size: 80, color: Colors.white));
                        }
                        return Image.network(imageUrls[index],
                            fit: BoxFit.cover);
                      },
                    ),
                    if (imageUrls.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 40.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                              imageUrls.length,
                              (index) => AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    height: 8,
                                    width: _currentPage == index ? 24 : 8,
                                    decoration: BoxDecoration(
                                        color: _currentPage == index
                                            ? Colors.white
                                            : Colors.white54,
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  )),
                        ),
                      )
                  ],
                ),
              )),
          SliverToBoxAdapter(
              child: Container(
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(30))),
                  transform: Matrix4.translationValues(0, -30, 0),
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.activityData['title'],
                                style:
                                    Theme.of(context).textTheme.headlineMedium),
                            const SizedBox(height: 8),
                            Text('Offered by: ${widget.propertyName}',
                                style: TextStyle(
                                    color: secondaryColor,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 32),
                            Text('About this offer',
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 12),
                            Text(
                                widget.activityData['description'] ??
                                    'No description provided.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(height: 1.5)),
                            const SizedBox(height: 40),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Rate per night',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium),
                                        const SizedBox(height: 4),
                                        Text('₱${widget.activityData['price']}',
                                            style: const TextStyle(
                                                fontSize: 26,
                                                fontWeight: FontWeight.w900)),
                                      ],
                                    ),
                                    ElevatedButton(
                                      onPressed: _checkAndStartBooking,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: secondaryColor,
                                        minimumSize: const Size(140, 54),
                                      ),
                                      child: const Text('Avail Now',
                                          style: TextStyle(fontSize: 16)),
                                    )
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 100),
                          ])))),
        ],
      ),
    );
  }
}
