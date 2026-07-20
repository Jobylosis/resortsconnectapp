import re

file_path = 'lib/dashboards/owner_dashboard.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update _disableRoom to prompt for start date
disable_room_old = '''    // Show disable dialog
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
    );'''

disable_room_new = '''    // Show disable dialog
    TextEditingController daysCtrl = TextEditingController();
    DateTime? selectedStartDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Disable Room'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Disable this room for renovations or repairs. It will not appear to tourists.'),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Start Date: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setState(() => selectedStartDate = date);
                      }
                    },
                    child: Text(selectedStartDate != null ? "${selectedStartDate!.year}-${selectedStartDate!.month.toString().padLeft(2, '0')}-${selectedStartDate!.day.toString().padLeft(2, '0')}" : 'Select Date'),
                  )
                ]
              ),
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
                if (days <= 0 || selectedStartDate == null) return;
                Navigator.pop(context);
                await FirebaseDatabase.instance.ref('rooms/$roomId').update({
                  'isDisabled': true,
                  'disabledReason': 'Maintenance',
                  'disabledStart': selectedStartDate!.millisecondsSinceEpoch,
                  'disabledUntil': selectedStartDate!.add(Duration(days: days)).millisecondsSinceEpoch,
                });
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Room disabled.')));
              },
              child: const Text('Disable'),
            )
          ],
        )
      )
    );'''

content = content.replace(disable_room_old, disable_room_new)

# 2. Add Disable button next to Delete Button in Room Card
action_btns_regex = r"(IconButton\(\s*icon:\s*const\s*Icon\(\s*Icons.delete_outline_rounded,\s*color:\s*AppTheme.primaryAccent,\s*size:\s*20\),\s*onPressed:\s*\(\)\s*=>\s*setState\(\(\)\s*=>\s*_deletingRoomKey\s*=\s*key\)\),)"

replacement_btns = r'''\1
                                          IconButton(
                                              icon: Icon(
                                                  act['isDisabled'] == true ? Icons.check_circle_outline : Icons.block,
                                                  color: act['isDisabled'] == true ? Colors.green : Colors.orange,
                                                  size: 20),
                                              onPressed: () =>
                                                  widget.onDisableRoom(key, act)),'''
content = re.sub(action_btns_regex, replacement_btns, content)

# 3. Add Disabled status label to Room Title
# Title is currently: Text(act['title'] ?? 'Room Name', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18), overflow: TextOverflow.ellipsis),
title_regex = r"(Text\(act\['title'\]\s*\?\?\s*'Room Name',\s*style:\s*const\s*TextStyle\(fontWeight:\s*FontWeight.w900,\s*fontSize:\s*18\),\s*overflow:\s*TextOverflow.ellipsis\),)"
replacement_label = r'''\1
                                          if (act['isDisabled'] == true)
                                            Container(
                                              margin: const EdgeInsets.only(top: 4),
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                              child: const Text('Disabled', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ),'''
content = re.sub(title_regex, replacement_label, content)


# 4. Update Unpaid Balances Dialog search logic
unpaid_search_old = '''    if (_searchCtrl.text.isNotEmpty) {
      displayList = _unpaidBookings.where((b) => 
        (b['bookingCode']?.toString().toLowerCase() ?? '').contains(_searchCtrl.text.toLowerCase())
      ).toList();
    }'''

unpaid_search_new = '''    if (_searchCtrl.text.isNotEmpty) {
      displayList = _unpaidBookings.where((b) => 
        (b['bookingCode']?.toString().toLowerCase() ?? '').contains(_searchCtrl.text.toLowerCase()) ||
        (b['touristName']?.toString().toLowerCase() ?? '').contains(_searchCtrl.text.toLowerCase())
      ).toList();
    }'''

content = content.replace(unpaid_search_old, unpaid_search_new)

# 5. Fix Unpaid balances dialog search label
content = content.replace("labelText: 'Search Tourist Booking Code',", "labelText: 'Search Booking Code or Tourist Name',")

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Patch applied.")
