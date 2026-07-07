import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

class PriceBreakdownDialog extends StatelessWidget {
  final Map booking;

  const PriceBreakdownDialog({super.key, required this.booking});

  Future<Map> _fetchAddonPrices() async {
    if (booking['propertyId'] == null) return {};
    final snap = await FirebaseDatabase.instance.ref('properties/${booking['propertyId']}/addonPrices').get();
    if (snap.exists && snap.value != null) {
      return snap.value as Map;
    }
    return {};
  }

  @override
  Widget build(BuildContext context) {
    int nights = int.tryParse(booking['nights']?.toString() ?? '1') ?? 1;
    Map? pricing = booking['pricing'] is Map ? booking['pricing'] : null;

    return AlertDialog(
      title: const Text('Price Breakdown', style: TextStyle(fontWeight: FontWeight.bold)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: SingleChildScrollView(
        child: FutureBuilder<Map>(
          future: _fetchAddonPrices(),
          builder: (context, snapshot) {
            Map addonPrices = snapshot.data ?? {};
            double calculatedAddonsTotal = double.tryParse(pricing?['addonsTotal']?.toString() ?? '0') ?? 0;
            bool isOldBooking = pricing == null && booking['selectedAddons'] is List && (booking['selectedAddons'] as List).isNotEmpty;
            
            if (isOldBooking) {
              for (var addonStr in (booking['selectedAddons'] as List)) {
                try {
                  RegExp exp = RegExp(r"(.+?)\s*\(x(\d+)\)");
                  Match? match = exp.firstMatch(addonStr);
                  if (match != null) {
                    String name = match.group(1)!.trim();
                    int qty = int.tryParse(match.group(2)!) ?? 1;
                    double pricePerUnit = double.tryParse(addonPrices[name]?.toString() ?? '0') ?? 0;
                    calculatedAddonsTotal += (pricePerUnit * qty);
                  }
                } catch(e) {}
              }
            }
            
            double grandTotal = double.tryParse(pricing?['grandTotal']?.toString() ?? booking['totalPrice']?.toString() ?? '0') ?? 0;
            double basePrice = double.tryParse(pricing?['basePrice']?.toString() ?? '0') ?? 0;
            
            if (pricing == null) {
                basePrice = grandTotal - calculatedAddonsTotal;
                if (basePrice < 0) basePrice = 0;
            }
            
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRow('Room Base ($nights Night/s)', '₱${basePrice.toStringAsFixed(0)}'),
                
                if (calculatedAddonsTotal > 0 || (booking['selectedAddons'] is List && (booking['selectedAddons'] as List).isNotEmpty)) ...[
                  const Divider(height: 24),
                  const Text('ADD-ONS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  
                  if (pricing != null && pricing['addonsList'] is List && pricing['addonsList'].isNotEmpty)
                    ...(pricing['addonsList'] as List).map((addon) {
                      double total = double.tryParse(addon['total']?.toString() ?? '0') ?? 0;
                      int qty = int.tryParse(addon['quantity']?.toString() ?? '1') ?? 1;
                      double perUnit = qty > 0 ? total / qty : 0;
                      return _buildAddonRow('${addon['name']}: ₱${perUnit.toStringAsFixed(0)} (x$qty)', '₱${total.toStringAsFixed(0)}');
                    })
                  else if (booking['selectedAddons'] is List)
                    ...(booking['selectedAddons'] as List).map((addonStr) {
                      String displayPrice = "Included in subtotal";
                      String displayName = addonStr;
                      
                      try {
                        RegExp exp = RegExp(r"(.+?)\s*\(x(\d+)\)");
                        Match? match = exp.firstMatch(addonStr);
                        if (match != null) {
                          String name = match.group(1)!.trim();
                          int qty = int.tryParse(match.group(2)!) ?? 1;
                          double pricePerUnit = double.tryParse(addonPrices[name]?.toString() ?? '0') ?? 0;
                          if (pricePerUnit > 0) {
                            displayName = '$name: ₱${pricePerUnit.toStringAsFixed(0)} (x$qty)';
                            displayPrice = '₱${(pricePerUnit * qty).toStringAsFixed(0)}';
                          }
                        }
                      } catch(e) {}
                      
                      return _buildAddonRow(displayName, displayPrice);
                    }),
                  
                  const SizedBox(height: 8),
                  _buildRow('Add-ons Subtotal', '₱${calculatedAddonsTotal.toStringAsFixed(0)}', isBold: true),
                ],
                
                const Divider(height: 24, thickness: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Grand Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                      '₱${grandTotal.toStringAsFixed(0)}', 
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.redAccent)
                    ),
                  ],
                ),
                
                if (widget.booking['amountPaid'] != null && (widget.booking['amountPaid'] as num) < grandTotal) ...[
                  const SizedBox(height: 12),
                  _buildRow('Amount Paid (Downpayment)', '₱${(widget.booking['amountPaid'] as num).toStringAsFixed(0)}', color: Colors.grey[700]),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Outstanding Balance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(
                        '₱${(grandTotal - (widget.booking['amountPaid'] as num)).toStringAsFixed(0)}', 
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.orange)
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text('*To be paid upon check-in', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
                  )
                ],
              ],
            );
          }
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildRow(String label, String value, {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color)),
        Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.w600, color: color)),
      ],
    );
  }

  Widget _buildAddonRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey))),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
        ],
      ),
    );
  }
}
