import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:resortconnectapp/services/ai_service.dart';
import 'package:flutter/gestures.dart';
import 'theme_provider.dart';
import 'theme.dart';
import 'terms_and_policies_page.dart';

class ActivityDetailsPage extends StatefulWidget {
  final String activityId;
  final Map activityData;
  final String ownerUid;
  final String propertyName;
  final Map propertyData;

  const ActivityDetailsPage({
    super.key,
    required this.activityId,
    required this.activityData,
    required this.ownerUid,
    required this.propertyName,
    required this.propertyData,
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
    final firstDate = DateUtils.dateOnly(DateTime.now());
    DateTime? selectedDate = await showDatePicker(
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
    if (selectedDate == null) return;

    if (!mounted) return;
    int nights = 1;
    final DateTime bookingDate = selectedDate;
    bool conflict =
        await _checkBookingConflict(widget.activityId, bookingDate, nights);
    if (conflict) {
      _showOverbookedDialog(widget.activityData['title'],
          DateFormat('MMM dd, yyyy').format(bookingDate));
      return;
    }

    _confirmBooking(bookingDate);
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
    int nights = 1;
    final DateTime bookingDate = date;
    final dateStr = DateFormat('MMM dd, yyyy').format(bookingDate);
    int paxCount = 1;
    int lunchMeals = 0;
    int dinnerMeals = 0;
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
    bool showQR = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(builder: (context, setS) {
        final String actTitle = (widget.activityData['title'] ?? '').toString();
        final bool isBoat = actTitle.toLowerCase().contains('boatride');
        final int maxPax = int.tryParse(widget.activityData['maxPax']?.toString() ?? '') ?? 1;
        double soloSurcharge = (isBoat && paxCount == 1) ? 750.0 : 0.0;
        double baseRoomTotal = (basePrice * paxCount) + soloSurcharge;
        double addonTotal = (lunchMeals * 400.0) + (dinnerMeals * 400.0);
        double taxes = 0;
        double totalPrice = baseRoomTotal + addonTotal + taxes;
        double paymentAmount = double.parse((method.contains('30%') ? (totalPrice * 0.3) : totalPrice).toStringAsFixed(2));
        
        final String gcashNum = widget.propertyData['gcashNumber']?.toString() ?? '';
        final String gcashName = widget.propertyData['gcashName']?.toString() ?? '';
        final dynamic gcashQr = widget.propertyData['gcashQr'];

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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.access_time_filled_rounded, size: 18, color: Colors.amber.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Activity Schedule: 8:00 AM - 5:00 PM • ₱${basePrice.toStringAsFixed(2)}/pax',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Number of Passengers ($paxCount pax):',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        Row(children: [
                          IconButton(
                              onPressed: paxCount > 1
                                  ? () => setS(() => paxCount--)
                                  : null,
                              icon: const Icon(Icons.remove_circle_outline)),
                          Text('$paxCount', style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                              onPressed: paxCount < maxPax
                                  ? () => setS(() => paxCount++)
                                  : null,
                              icon: const Icon(Icons.add_circle_outline))
                        ])
                      ]),
                  if (soloSurcharge > 0) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Note: Solo passenger rate includes a ₱750 boatride charge (Total: ₱2,200/₱2,750).',
                        style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  if ((widget.propertyData['enableCustomMenuUpload'] == true || widget.propertyData['enableCustomMenuUpload'] == 'true') && widget.propertyData['foodMenuUrls'] != null && widget.propertyData['foodMenuUrls'] is List && (widget.propertyData['foodMenuUrls'] as List).isNotEmpty) ...[
                    const Divider(height: 24),
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
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
                          const Text('Lunch & Dinner options are available on-site. No advance booking required.', style: TextStyle(fontSize: 13, color: Colors.grey)),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                final urls = List<String>.from(widget.propertyData['foodMenuUrls']);
                                showDialog(
                                  context: context,
                                  builder: (ctx) {
                                    final pageController = PageController();
                                    return Dialog(
                                      backgroundColor: Colors.transparent,
                                      insetPadding: EdgeInsets.zero,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          PageView.builder(
                                            controller: pageController,
                                            itemCount: urls.length,
                                            itemBuilder: (context, index) {
                                              return InteractiveViewer(
                                                child: Image.network(urls[index], fit: BoxFit.contain),
                                              );
                                            },
                                          ),
                                          Positioned(
                                            top: 40,
                                            right: 20,
                                            child: IconButton(
                                              icon: const Icon(Icons.close, color: Colors.white, size: 30),
                                              onPressed: () => Navigator.pop(ctx),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                );
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
                  const Divider(height: 24),
                  if (!(widget.propertyData['enableCustomMenuUpload'] == true || widget.propertyData['enableCustomMenuUpload'] == 'true')) ...[
                    const Text('Meal & Food Add-ons:',
                        style:
                            TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Lunch Set Menu (₱400/meal):', style: TextStyle(fontSize: 13)),
                        Row(
                          children: [
                            IconButton(
                              onPressed: lunchMeals > 0 ? () => setS(() => lunchMeals--) : null,
                              icon: const Icon(Icons.remove_circle_outline, size: 20),
                            ),
                            Text('$lunchMeals', style: const TextStyle(fontWeight: FontWeight.bold)),
                            IconButton(
                              onPressed: () => setS(() => lunchMeals++),
                              icon: const Icon(Icons.add_circle_outline, size: 20),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Dinner Set Menu (₱400/meal):', style: TextStyle(fontSize: 13)),
                        Row(
                          children: [
                            IconButton(
                              onPressed: dinnerMeals > 0 ? () => setS(() => dinnerMeals--) : null,
                              icon: const Icon(Icons.remove_circle_outline, size: 20),
                            ),
                            Text('$dinnerMeals', style: const TextStyle(fontWeight: FontWeight.bold)),
                            IconButton(
                              onPressed: () => setS(() => dinnerMeals++),
                              icon: const Icon(Icons.add_circle_outline, size: 20),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                  const Divider(height: 32),
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
                  if (receiptUrl != null) ...[
                    ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(receiptUrl!,
                            height: 150,
                            width: double.infinity,
                            fit: BoxFit.cover)),
                    const SizedBox(height: 12),
                  ],
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
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: isUploading
                                  ? null
                                  : () async {
                                final picker = ImagePicker();
                                final XFile? file = await picker.pickImage(
                                    source: ImageSource.gallery, imageQuality: 85);
                                if (file == null) return;

                                setS(() {
                                  isUploading = true;
                                  receiptUrl = null;
                                  extractedRefNo = null;
                                  ocrStatus = null;
                                  ocrIssues = null;
                                });

                                try {
                                  // Strict OCR Validation
                                  bool validationPassed = false;
                                  
                                  try {
                                    final ocrData = await AiService.extractGCashReference(
                                        File(file.path), 
                                        paymentAmount, 
                                        widget.propertyData['gcashName']?.toString() ?? ''
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
                                              content: const Text('This receipt reference number has already been used. Please upload a valid, unused receipt.'),
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
                                          receiptUrl = null;
                                          extractedRefNo = null;
                                          ocrStatus = null;
                                          ocrIssues = null;
                                        });
                                        return;
                                      }

                                      validationPassed = true;
                                      extractedRefNo = tempRefNo;
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
                                            title: const Text('Receipt Flagged'),
                                            content: Text("$ocrIssues\n\nYou can re-upload a clear and correct receipt screenshot, or submit this receipt for manual review (which may be declined)."),
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
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notice: OCR service unreachable. You may re-upload or proceed with caution.')));
                                    }
                                  }

                                  final url = await _uploadToCloudinary(File(file.path));
                                  setS(() {
                                    receiptUrl = url;
                                  });
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e. Please try again.')));
                                  }
                                } finally {
                                  setS(() {
                                    isUploading = false;
                                  });
                                }
                              },
                        icon: Icon(isUploading
                            ? Icons.hourglass_top_rounded
                            : receiptUrl != null
                                ? (ocrStatus == 'Verified' ? Icons.check_circle_rounded : Icons.warning_amber_rounded)
                                : Icons.upload_file_rounded),
                        label: Text(isUploading
                            ? 'Scanning Receipt...'
                            : receiptUrl != null
                                ? (ocrStatus == 'Verified' ? 'Verified (Ref: $extractedRefNo) - Tap to Change' : 'Flagged - Tap to Re-upload')
                                : 'Upload Payment Receipt'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: receiptUrl != null && !isUploading
                              ? (ocrStatus == 'Verified' ? Colors.green : Colors.orange[700])
                              : const Color(0xFF0038A8),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
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
                            Text('Activity Base ($nights ${nights == 1 ? "hour" : "hours"})', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                            Text('₱${baseRoomTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          ]),
                          if (addonTotal > 0) ...[
                            const SizedBox(height: 6),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              const Text('Add-ons', style: TextStyle(color: Colors.grey, fontSize: 13)),
                              Text('₱${addonTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            ]),
                          ],
                          const Divider(height: 24),
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
                                    List<String> mealAddons = [];
                                    if (lunchMeals > 0) mealAddons.add('Lunch Set Menu (x$lunchMeals)');
                                    if (dinnerMeals > 0) mealAddons.add('Dinner Set Menu (x$dinnerMeals)');

                                    _processBooking(
                                      date: dateStr,
                                      paxCount: paxCount,
                                      basePrice: basePrice,
                                      soloSurcharge: soloSurcharge,
                                      mealsTotal: addonTotal,
                                      totalPrice: totalPrice,
                                      addons: mealAddons,
                                      receipt: receiptUrl!,
                                      method: method,
                                      extractedRefNo: extractedRefNo,
                                      ocrStatus: ocrStatus,
                                      ocrIssues: ocrIssues,
                                    );
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

  Future<void> _processBooking({
    required String date,
    required int paxCount,
    required double basePrice,
    required double soloSurcharge,
    required double mealsTotal,
    required double totalPrice,
    required List<String> addons,
    required String receipt,
    required String method,
    String? extractedRefNo,
    String? ocrStatus,
    String? ocrIssues,
  }) async {
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
        
        if (usedReceipts.map((e) => e.toString()).contains(extractedRefNo)) {
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
        if (usedReceipts.length > 500) {
          usedReceipts = usedReceipts.sublist(usedReceipts.length - 500);
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
    double paymentAmount = double.parse((method.contains('30%') ? (totalPrice * 0.3) : totalPrice).toStringAsFixed(2));

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
          'basePrice': basePrice * paxCount,
          'soloSurcharge': soloSurcharge,
          'addonsTotal': mealsTotal,
          'grandTotal': totalPrice
        },
        'totalPrice': totalPrice,
        'amountPaid': paymentAmount,
        'pax': paxCount,
        'nights': 1,
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
        'title': ocrStatus == 'Flagged' ? 'Auto-declined Activity Booking' : 'New Booking Request',
        'message': ocrStatus == 'Flagged'
            ? '$touristName\'s activity booking was auto-declined due to invalid payment.'
            : '$touristName booked "${widget.activityData['title']}" for 1 hour.',
        'type': 'booking_new',
        'isRead': false,
        'timestamp': ServerValue.timestamp
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ocrStatus == 'Flagged' ? 'Activity booking auto-declined due to invalid payment proof.' : 'Booking request sent successfully!'),
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
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: secondaryColor.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: secondaryColor.withOpacity(0.3)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.schedule, color: secondaryColor, size: 22),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Operating Hours & Schedule',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '• Kayak, Boat ride to Pagsanjan falls, & Paddle board: 7:00 AM – 3:30 PM\n• Bar, Karaoke, & Dinner: 7:00 AM – 10:00 PM',
                                          style: TextStyle(
                                            fontSize: 13,
                                            height: 1.4,
                                            color: Theme.of(context).textTheme.bodyMedium?.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),
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
                                        Text('Rate per hour',
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
