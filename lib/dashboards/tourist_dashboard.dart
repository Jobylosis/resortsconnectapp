import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:intl/intl.dart';
import '../profile_page.dart';
import '../property_details_page.dart';
import '../notifications_page.dart';

class TouristDashboard extends StatefulWidget {
  const TouristDashboard({super.key});

  @override
  State<TouristDashboard> createState() => _TouristDashboardState();
}

class _TouristDashboardState extends State<TouristDashboard> {
  final List<String> _targetClients = [
    "Nadzville Resort",
    "Casa Del Rio",
    "Hotel Ramiro"
  ];

  late Stream<DatabaseEvent> _userStream;
  late Stream<DatabaseEvent> _propertiesStream;
  late Stream<DatabaseEvent> _notifStream;

  final Color _bg70 = const Color(0xFFF8F9FA);
  final Color _brand20 = const Color(0xFF2196F3);
  final Color _accent10 = const Color(0xFFFF8F00);

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _userStream = FirebaseDatabase.instance.ref("users/${user?.uid}").onValue;
    _propertiesStream = FirebaseDatabase.instance.ref("properties").onValue;
    _notifStream = FirebaseDatabase.instance.ref("notifications/${user?.uid}").onValue;
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                FirebaseAuth.instance.signOut();
              },
              child: const Text('Logout', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final myBookingsQuery = FirebaseDatabase.instance.ref("bookings").orderByChild("touristUid").equalTo(user?.uid);

    return StreamBuilder<DatabaseEvent>(
      stream: _userStream,
      builder: (context, snapshot) {
        String firstName = "Tourist";
        if (snapshot.hasData && snapshot.data!.snapshot.exists) {
          Map data = snapshot.data!.snapshot.value as Map;
          firstName = data['firstName'] ?? "Tourist";
        }

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            backgroundColor: _bg70,
            appBar: AppBar(
              elevation: 0,
              backgroundColor: Colors.white,
              title: Row(
                children: [
                  Icon(Icons.beach_access_rounded, color: _brand20, size: 28),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Resort Connect', style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Tourist: $firstName', style: TextStyle(color: _brand20, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
              actions: [
                StreamBuilder<DatabaseEvent>(
                  stream: _notifStream,
                  builder: (context, snapshot) {
                    int unreadCount = 0;
                    if (snapshot.hasData && snapshot.data!.snapshot.exists) {
                      Map notifs = snapshot.data!.snapshot.value as Map;
                      unreadCount = notifs.values.where((n) => n['isRead'] == false).length;
                    }

                    return Stack(
                      children: [
                        IconButton(
                          icon: Icon(Icons.notifications_none_rounded, color: _brand20), 
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsPage()))
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                              child: Text(
                                '$unreadCount',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    );
                  }
                ),
                IconButton(icon: Icon(Icons.person_outline_rounded, color: _brand20), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfilePage()))),
                IconButton(icon: Icon(Icons.logout_rounded, color: _brand20), onPressed: () => _showLogoutDialog(context)),
              ],
              bottom: TabBar(
                tabs: const [Tab(text: 'Partners'), Tab(text: 'My Bookings')],
                labelColor: _brand20,
                indicatorColor: _brand20,
                indicatorWeight: 3,
              ),
            ),
            body: TabBarView(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hello, $firstName! 👋', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('Where would you like to go?', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: StreamBuilder<DatabaseEvent>(
                        stream: _propertiesStream,
                        builder: (context, propSnapshot) {
                          if (propSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                          Map<String, dynamic> registeredProps = {};
                          if (propSnapshot.hasData && propSnapshot.data!.snapshot.exists) {
                            registeredProps = Map<String, dynamic>.from(propSnapshot.data!.snapshot.value as Map);
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            itemCount: _targetClients.length,
                            itemBuilder: (context, index) {
                              String clientName = _targetClients[index];
                              String ownerUid = "";
                              Map? propData;
                              registeredProps.forEach((key, value) {
                                if (value['name'].toString().toLowerCase().contains(clientName.toLowerCase())) {
                                  ownerUid = key;
                                  propData = value;
                                }
                              });

                              return _buildPartnerButton(clientName, propData, ownerUid);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
                FirebaseAnimatedList(
                  query: myBookingsQuery,
                  padding: const EdgeInsets.all(20),
                  itemBuilder: (context, snapshot, animation, index) {
                    Map booking = snapshot.value as Map;
                    return SizeTransition(sizeFactor: animation, child: _buildMyBookingCard(booking));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPartnerButton(String clientName, Map? propertyData, String ownerUid) {
    bool isRegistered = propertyData != null;
    String? firstImg;
    if (isRegistered && propertyData!['imageUrls'] != null && (propertyData!['imageUrls'] as List).isNotEmpty) {
      firstImg = propertyData!['imageUrls'][0];
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          width: 60, height: 60,
          decoration: BoxDecoration(
            color: _brand20.withOpacity(0.1),
            borderRadius: BorderRadius.circular(15),
            image: firstImg != null ? DecorationImage(image: NetworkImage(firstImg), fit: BoxFit.cover) : null,
          ),
          child: firstImg == null ? Icon(clientName.contains('Hotel') ? Icons.hotel : Icons.beach_access, color: _brand20) : null,
        ),
        title: Text(clientName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        subtitle: Text(isRegistered ? 'Available now' : 'Coming soon', style: TextStyle(color: isRegistered ? Colors.green : Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
        trailing: Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey[300], size: 18),
        onTap: isRegistered 
          ? () => Navigator.push(context, MaterialPageRoute(builder: (context) => PropertyDetailsPage(propertyName: clientName, propertyData: propertyData!, ownerUid: ownerUid)))
          : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$clientName is currently offline.'))),
      ),
    );
  }

  Widget _buildMyBookingCard(Map booking) {
    Color statusColor = _accent10;
    if (booking['status'] == 'Confirmed') statusColor = Colors.green;
    if (booking['status'] == 'Cancelled') statusColor = Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(booking['propertyName'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(booking['status'], style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(booking['activityTitle'], style: const TextStyle(fontSize: 14)),
          Text('${booking['bookingDate']} at ${booking['bookingTime']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const Divider(),
          Text('₱${booking['price']}', style: TextStyle(fontWeight: FontWeight.bold, color: _brand20)),
        ],
      ),
    );
  }
}
