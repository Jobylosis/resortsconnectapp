import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'property_details_page.dart';

class HotDealsPage extends StatelessWidget {
  const HotDealsPage({super.key});

  final Color richBlack = const Color(0xFF000F08);
  final Color imperialRed = const Color(0xFFFB3640);

  @override
  Widget build(BuildContext context) {
    final Query propertiesQuery = FirebaseDatabase.instance.ref("properties");

    return Scaffold(
      backgroundColor: richBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('HOT DEALS', style: TextStyle(color: imperialRed, fontWeight: FontWeight.w900, letterSpacing: 2)),
        centerTitle: true,
        iconTheme: IconThemeData(color: imperialRed),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Exclusive Offers', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Limited time deals for your next escape.', style: TextStyle(color: Colors.white70, fontSize: 16)),
              ],
            ),
          ),
          Expanded(
            child: FirebaseAnimatedList(
              query: propertiesQuery,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemBuilder: (context, snapshot, animation, index) {
                Map data = snapshot.value as Map;
                String ownerUid = snapshot.key!;
                
                // For "Hot Deals", we simulate a discount or featured tag
                return FadeTransition(
                  opacity: animation,
                  child: _buildDealCard(context, data, ownerUid),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDealCard(BuildContext context, Map data, String ownerUid) {
    final List imgs = data['imageUrls'] != null ? (data['imageUrls'] is List ? data['imageUrls'] : (data['imageUrls'] as Map).values.toList()) : [];
    String? firstImg = imgs.isNotEmpty ? imgs[0] : null;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => PropertyDetailsPage(propertyName: data['name'] ?? 'Resort', propertyData: data, ownerUid: ownerUid))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: imperialRed.withOpacity(0.3), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  child: firstImg != null 
                    ? Image.network(firstImg, height: 200, width: double.infinity, fit: BoxFit.cover)
                    : Container(height: 200, width: double.infinity, color: Colors.white10, child: Icon(Icons.hotel, color: imperialRed, size: 40)),
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: imperialRed, borderRadius: BorderRadius.circular(12)),
                    child: const Text('20% OFF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data['name'] ?? 'Resort', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, color: imperialRed, size: 16),
                      const SizedBox(width: 4),
                      Text(data['type'] ?? 'Resort', style: const TextStyle(color: Colors.white60, fontSize: 14)),
                      const Spacer(),
                      Text('Book Now', style: TextStyle(color: imperialRed, fontWeight: FontWeight.bold, fontSize: 14)),
                      Icon(Icons.chevron_right_rounded, color: imperialRed, size: 20),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
