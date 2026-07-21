import re

file_path = 'lib/dashboards/owner_dashboard.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace the entire BalancesTab and its State

old_tab_pattern = re.compile(r'class BalancesTab extends StatefulWidget \{.*?(?=\nclass [A-Z]|$)', re.DOTALL)

new_tab_code = '''class BalancesTab extends StatefulWidget {
  final String ownerId;
  const BalancesTab({super.key, required this.ownerId});

  @override
  State<BalancesTab> createState() => _BalancesTabState();
}

class _BalancesTabState extends State<BalancesTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map> _unpaidBookings = [];
  bool _isLoading = true;
  Set<String> _selectedBookingIds = {};

  @override
  void initState() {
    super.initState();
    _fetchUnpaidBookings();
  }

  Future<void> _fetchUnpaidBookings() async {
    setState(() => _isLoading = true);
    final snapshot = await FirebaseDatabase.instance
        .ref('bookings')
        .orderByChild('ownerId')
        .equalTo(widget.ownerId)
        .get();

    List<Map> unpaid = [];
    if (snapshot.exists) {
      final data = snapshot.value as Map;
      data.forEach((key, value) {
        String status = (value['status'] ?? '').toString().toLowerCase();
        double remaining = double.tryParse(value['remainingBalance']?.toString() ?? '0') ?? 0;
        bool isPaid = value['isPaid'] == true;
        
        if (remaining > 0 && !isPaid && status != 'cancelled' && status != 'refunded') {
          Map b = Map.from(value);
          b['id'] = key;
          unpaid.add(b);
        }
      });
    }

    if (mounted) {
      setState(() {
        _unpaidBookings = unpaid;
        _isLoading = false;
      });
    }
  }

  Future<void> _processPaymentForBookings(List<Map> bookingsToPay) async {
    double totalAmount = 0;
    for (var b in bookingsToPay) {
      totalAmount += double.tryParse(b['remainingBalance']?.toString() ?? '0') ?? 0;
    }

    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Payment'),
        content: Text('Mark ${bookingsToPay.length} booking(s) as fully paid (Total: ₱${totalAmount.toStringAsFixed(0)})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          )
        ],
      )
    ) ?? false;

    if (!confirm) return;

    // Process all updates
    final statsRef = FirebaseDatabase.instance.ref('owner_stats/${widget.ownerId}');
    final sSnap = await statsRef.get();
    double currentRev = 0;
    if (sSnap.exists) {
      final sData = sSnap.value as Map;
      currentRev = (sData['totalRevenue'] ?? 0).toDouble();
    }

    double newlyPaid = 0;
    for (var booking in bookingsToPay) {
      double bal = double.tryParse(booking['remainingBalance']?.toString() ?? '0') ?? 0;
      newlyPaid += bal;
      
      await FirebaseDatabase.instance.ref('bookings/${booking['id']}').update({
        'remainingBalance': 0,
        'isPaid': true,
      });

      await FirebaseDatabase.instance.ref('revenue_reports/${widget.ownerId}').push().set({
        'bookingId': booking['id'],
        'amount': bal,
        'date': ServerValue.timestamp,
        'description': 'Balance paid for ${booking['bookingCode'] ?? 'Unknown'}',
        'type': 'balance_payment'
      });
    }

    await statsRef.update({
      'totalRevenue': currentRev + newlyPaid
    });

    setState(() {
      _selectedBookingIds.removeAll(bookingsToPay.map((b) => b['id'].toString()));
    });
    
    _fetchUnpaidBookings();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payments recorded successfully.')));
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    DateTime d = DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp.toString()));
    return "${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][d.month-1]} ${d.day}, ${d.year}";
  }

  @override
  Widget build(BuildContext context) {
    List<Map> displayList = _unpaidBookings;
    if (_searchCtrl.text.isNotEmpty) {
      displayList = _unpaidBookings.where((b) => 
        (b['bookingCode']?.toString().toLowerCase() ?? '').contains(_searchCtrl.text.toLowerCase()) ||
        (b['touristName']?.toString().toLowerCase() ?? '').contains(_searchCtrl.text.toLowerCase())
      ).toList();
    }

    // Group by tourist
    Map<String, List<Map>> grouped = {};
    for (var b in displayList) {
      String tName = (b['touristName'] ?? 'Unknown Tourist').toString().trim();
      if (tName.isEmpty) tName = 'Unknown Tourist';
      grouped.putIfAbsent(tName, () => []).add(b);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100], // light background like web
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Row(
              children: [
                const Icon(Icons.credit_card, color: AppTheme.primaryAccent),
                const SizedBox(width: 8),
                const Text('Unpaid Balances', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search tourist name or booking ID',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (val) => setState(() {}),
            ),
            const SizedBox(height: 16),
            _isLoading
              ? const Center(child: CircularProgressIndicator())
              : grouped.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('No unpaid balances found.')))
                : Expanded(
                    child: ListView.builder(
                      itemCount: grouped.keys.length,
                      itemBuilder: (context, i) {
                        String tName = grouped.keys.elementAt(i);
                        List<Map> items = grouped[tName]!;
                        double totalUnpaid = items.fold(0.0, (sum, item) => sum + (double.tryParse(item['remainingBalance']?.toString() ?? '0') ?? 0));
                        
                        List<Map> selectedItems = items.where((b) => _selectedBookingIds.contains(b['id'].toString())).toList();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 24),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                            ]
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(tName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                                        const SizedBox(height: 4),
                                        Text('Total Unpaid Balance: ₱${totalUnpaid.toStringAsFixed(0)}', style: const TextStyle(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blueAccent, 
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                                        ),
                                        onPressed: selectedItems.isEmpty ? null : () => _processPaymentForBookings(selectedItems),
                                        child: const Text('Mark Selected Paid', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF00C853), // Green
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                                        ),
                                        onPressed: () => _processPaymentForBookings(items),
                                        child: const Text('Mark All Paid', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      ),
                                    ]
                                  )
                                ],
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Divider(color: Colors.black12, thickness: 1, height: 1),
                              ),
                              // Booking Items
                              ...items.map((b) {
                                bool isSelected = _selectedBookingIds.contains(b['id'].toString());
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.blue.withOpacity(0.05) : Colors.grey[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: isSelected ? Colors.blue.withOpacity(0.3) : Colors.grey[200]!)
                                  ),
                                  child: Row(
                                    children: [
                                      Checkbox(
                                        value: isSelected,
                                        activeColor: Colors.blueAccent,
                                        onChanged: (val) {
                                          setState(() {
                                            if (val == true) _selectedBookingIds.add(b['id'].toString());
                                            else _selectedBookingIds.remove(b['id'].toString());
                                          });
                                        }
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('Room ${b['roomName'] ?? b['roomId'] ?? 'Unknown'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                              const SizedBox(height: 4),
                                              Text('Booking Ref: ${b['bookingCode']} • ${_formatDate(b['createdAt'] ?? b['timestamp'])}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                              const SizedBox(height: 4),
                                              Text('Balance: ₱${b['remainingBalance']}', style: const TextStyle(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                            ],
                                          )
                                        )
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: TextButton(
                                          style: TextButton.styleFrom(
                                            backgroundColor: Colors.green.withOpacity(0.1),
                                            foregroundColor: Colors.green[700],
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                                          ),
                                          onPressed: () => _processPaymentForBookings([b]),
                                          child: const Text('Mark as Paid', style: TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      )
                                    ],
                                  ),
                                );
                              }).toList()
                            ],
                          )
                        );
                      }
                    )
                  ),
          ],
        ),
    );
  }
}
'''

content = old_tab_pattern.sub(new_tab_code, content)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Patch applied")
