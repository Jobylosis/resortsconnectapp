import re

file_path = 'lib/dashboards/owner_dashboard.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add UnpaidBalancesDialog class at the bottom
if 'class UnpaidBalancesDialog' not in content:
    content += '''

class UnpaidBalancesDialog extends StatefulWidget {
  final String ownerId;
  const UnpaidBalancesDialog({super.key, required this.ownerId});

  @override
  State<UnpaidBalancesDialog> createState() => _UnpaidBalancesDialogState();
}

class _UnpaidBalancesDialogState extends State<UnpaidBalancesDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map> _unpaidBookings = [];
  bool _isLoading = true;

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
        if (value['remainingBalance'] != null &&
            value['remainingBalance'] > 0 &&
            (value['status'] == 'confirmed' || value['status'] == 'checked-in' || value['status'] == 'pending')) {
          Map b = Map.from(value);
          b['id'] = key;
          unpaid.add(b);
        }
      });
    }

    setState(() {
      _unpaidBookings = unpaid;
      _isLoading = false;
    });
  }

  void _markAsPaid(Map booking) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Payment'),
        content: Text('Mark booking ${booking['bookingCode']} as fully paid?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(context);
              
              // Update booking
              await FirebaseDatabase.instance.ref('bookings/${booking['id']}').update({
                'remainingBalance': 0,
                'isPaid': true,
              });

              // Add to revenue
              final statsRef = FirebaseDatabase.instance.ref('owner_stats/${widget.ownerId}');
              final sSnap = await statsRef.get();
              double currentRev = 0;
              if (sSnap.exists) {
                final sData = sSnap.value as Map;
                currentRev = (sData['totalRevenue'] ?? 0).toDouble();
              }
              await statsRef.update({
                'totalRevenue': currentRev + booking['remainingBalance']
              });

              // Also add a revenue report entry
              final revenueRef = FirebaseDatabase.instance.ref('revenue_reports/${widget.ownerId}').push();
              await revenueRef.set({
                'bookingId': booking['id'],
                'amount': booking['remainingBalance'],
                'date': ServerValue.timestamp,
                'description': 'Balance paid for ${booking['bookingCode']}',
                'type': 'balance_payment'
              });

              _fetchUnpaidBookings();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as paid.')));
            },
            child: const Text('Confirm'),
          )
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Map> displayList = _unpaidBookings;
    if (_searchCtrl.text.isNotEmpty) {
      displayList = _unpaidBookings.where((b) => 
        (b['bookingCode']?.toString().toLowerCase() ?? '').contains(_searchCtrl.text.toLowerCase())
      ).toList();
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Unpaid Balances', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent)),
            const SizedBox(height: 16),
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'Search Tourist Booking Code',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => setState(() {}),
            ),
            const SizedBox(height: 16),
            _isLoading
              ? const CircularProgressIndicator()
              : displayList.isEmpty
                ? const Padding(padding: EdgeInsets.all(20), child: Text('No unpaid balances found.'))
                : Expanded(
                    child: ListView.builder(
                      itemCount: displayList.length,
                      itemBuilder: (context, i) {
                        final b = displayList[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            title: Text('Code: ${b['bookingCode'] ?? 'N/A'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Tourist: ${b['touristName'] ?? 'N/A'}\\nOwes: ₱${b['remainingBalance']}'),
                            trailing: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                              onPressed: () => _markAsPaid(b),
                              child: const Text('Mark Paid'),
                            ),
                          ),
                        );
                      }
                    )
                  ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            )
          ],
        )
      )
    );
  }
}
'''

# 2. Add onDisableRoom and onShowUnpaidBalances to RoomsTab
content = content.replace(
    'final VoidCallback onGoToBookings;',
    'final VoidCallback onGoToBookings;\n  final VoidCallback onShowUnpaidBalances;\n  final Function(String, Map) onDisableRoom;'
)
content = content.replace(
    'required this.onGoToBookings,',
    'required this.onGoToBookings,\n      required this.onShowUnpaidBalances,\n      required this.onDisableRoom,'
)

# 3. Add to _buildRoomsTab constructor call
content = content.replace(
    'onGoToBookings: () => setState(() => _currentTab = 3),',
    'onGoToBookings: () => setState(() => _currentTab = 3),\n          onShowUnpaidBalances: _showUnpaidBalancesDialog,\n          onDisableRoom: _disableRoom,'
)

# 4. Add _showUnpaidBalancesDialog and _disableRoom to _OwnerDashboardState
if '_showUnpaidBalancesDialog' not in content:
    idx = content.find('void _showResetRevenueDialog(')
    insert_code = '''
  void _showUnpaidBalancesDialog() {
    showDialog(
      context: context,
      builder: (context) => UnpaidBalancesDialog(ownerId: FirebaseAuth.instance.currentUser!.uid),
    );
  }

  void _disableRoom(String roomId, Map roomData) async {
    // Check conflicts
    final snapshot = await FirebaseDatabase.instance.ref('bookings').orderByChild('roomId').equalTo(roomId).get();
    bool hasConflict = false;
    if (snapshot.exists) {
      final data = snapshot.value as Map;
      for (var b in data.values) {
        if (b['status'] == 'pending' || b['status'] == 'confirmed' || b['status'] == 'checked-in') {
          hasConflict = true;
          break;
        }
      }
    }

    if (hasConflict) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cannot Disable Room'),
            content: const Text('This room has active or pending bookings. Please cancel or complete them before disabling the room.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          )
        );
      }
      return;
    }

    bool isCurrentlyDisabled = roomData['isDisabled'] == true;
    if (isCurrentlyDisabled) {
      // Re-enable
      await FirebaseDatabase.instance.ref('rooms/$roomId').update({
        'isDisabled': false,
        'disabledReason': null,
        'disabledUntil': null,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Room re-enabled.')));
      return;
    }

    // Show disable dialog
    TextEditingController daysCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disable Room'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Disable this room for renovations or repairs. It will not appear to tourists.'),
            const SizedBox(height: 16),
            TextField(
              controller: daysCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Duration (Days)', border: OutlineInputBorder()),
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              int days = int.tryParse(daysCtrl.text) ?? 0;
              if (days <= 0) return;
              Navigator.pop(context);
              await FirebaseDatabase.instance.ref('rooms/$roomId').update({
                'isDisabled': true,
                'disabledReason': 'Maintenance',
                'disabledUntil': DateTime.now().add(Duration(days: days)).millisecondsSinceEpoch,
              });
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Room disabled.')));
            },
            child: const Text('Disable'),
          )
        ],
      )
    );
  }
'''
    content = content[:idx] + insert_code + content[idx:]


# 5. Add UI to RoomsTab (Unpaid Balances Card)
revenue_card_regex = r"Expanded\(\s*child:\s*_buildStatCard\(\s*'Revenue',\s*'₱\$\{revenue.toStringAsFixed\(2\)\}',\s*Icons.attach_money,\s*color:\s*Colors.green,\s*onTap:\s*widget.onShowRevenue,\s*\),\s*\),"
replacement = '''Expanded(
                        child: _buildStatCard(
                          'Revenue',
                          '₱${revenue.toStringAsFixed(2)}',
                          Icons.attach_money,
                          color: Colors.green,
                          onTap: widget.onShowRevenue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'Unpaid',
                          'Balances',
                          Icons.warning_amber_rounded,
                          color: Colors.orange,
                          onTap: widget.onShowUnpaidBalances,
                        ),
                      ),'''
content = re.sub(revenue_card_regex, replacement, content)


# 6. Add Disable button to Room Card
action_btns_regex = r"(IconButton\(\s*icon:\s*const\s*Icon\(Icons.edit,\s*color:\s*AppTheme.primaryAccent\),\s*onPressed:\s*\(\)\s*=>\s*widget.onEditRoom\(roomId,\s*roomData\),\s*\),)"
replacement_btns = r'''\1
                            IconButton(
                              icon: Icon(roomData['isDisabled'] == true ? Icons.check_circle_outline : Icons.block, color: roomData['isDisabled'] == true ? Colors.green : Colors.orange),
                              onPressed: () => widget.onDisableRoom(roomId, roomData),
                            ),'''
content = re.sub(action_btns_regex, replacement_btns, content)

# 7. Add Disabled status label
title_regex = r"(Text\(\s*roomName,\s*style:\s*const\s*TextStyle\(\s*fontSize:\s*18,\s*fontWeight:\s*FontWeight.bold\),\s*maxLines:\s*1,\s*overflow:\s*TextOverflow.ellipsis,\s*\),)"
replacement_label = r'''\1
                                if (roomData['isDisabled'] == true)
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                    child: const Text('Disabled', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),'''
content = re.sub(title_regex, replacement_label, content)


with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Patch successfully applied!")
