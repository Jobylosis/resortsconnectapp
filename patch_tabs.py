import re

file_path = 'lib/dashboards/owner_dashboard.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update TabController length
content = content.replace("TabController(length: 3", "TabController(length: 4")

# 2. Add Balances to TabBar
tabs_old = '''            const Tab(text: 'Rooms'),
            Tab(
              child: Badge(
                isLabelVisible: _bookingCounts['Pending'] != null && _bookingCounts['Pending']! > 0,
                label: Text('${_bookingCounts['Pending'] ?? 0}'),
                child: const Text('Bookings'),
              ),
            ),
            Tab(
              child: Badge(
                isLabelVisible: _unreadChatCount > 0,
                label: Text('$_unreadChatCount'),
                child: const Text('Chat'),
              ),
            ),'''

tabs_new = '''            const Tab(text: 'Rooms'),
            Tab(
              child: Badge(
                isLabelVisible: _bookingCounts['Pending'] != null && _bookingCounts['Pending']! > 0,
                label: Text('${_bookingCounts['Pending'] ?? 0}'),
                child: const Text('Bookings'),
              ),
            ),
            const Tab(text: 'Balances'),
            Tab(
              child: Badge(
                isLabelVisible: _unreadChatCount > 0,
                label: Text('$_unreadChatCount'),
                child: const Text('Chat'),
              ),
            ),'''
content = content.replace(tabs_old, tabs_new)

# 3. Add BalancesTab to TabBarView
tab_view_old = '''            BookingsTab(
              bookingQuery: _bookingQuery,
              bookingCounts: _bookingCounts,
              onDeleteRecord: (key, name) {},
              onScanQR: _openScanner,
              onTapBooking: (key, booking) =>
                  _showBookingDetailsDialog(key, booking),
            ),
            ChatTab(chatQuery: _chatQuery),'''

tab_view_new = '''            BookingsTab(
              bookingQuery: _bookingQuery,
              bookingCounts: _bookingCounts,
              onDeleteRecord: (key, name) {},
              onScanQR: _openScanner,
              onTapBooking: (key, booking) =>
                  _showBookingDetailsDialog(key, booking),
            ),
            BalancesTab(ownerId: uid),
            ChatTab(chatQuery: _chatQuery),'''
content = content.replace(tab_view_old, tab_view_new)

# 4. Remove Dialog wrapping from UnpaidBalancesDialog and change name to BalancesTab
class_old = "class UnpaidBalancesDialog extends StatefulWidget"
class_new = "class BalancesTab extends StatefulWidget"
content = content.replace(class_old, class_new)

content = content.replace("const UnpaidBalancesDialog(", "const BalancesTab(")
content = content.replace("State<UnpaidBalancesDialog>", "State<BalancesTab>")
content = content.replace("class _UnpaidBalancesDialogState extends State<UnpaidBalancesDialog>", "class _BalancesTabState extends State<BalancesTab>")

dialog_ret_old = '''    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['''

dialog_ret_new = '''    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: ['''
content = content.replace(dialog_ret_old, dialog_ret_new)

dialog_end_old = '''          ],
        ),
      ),
    );
  }
}'''

dialog_end_new = '''        ],
      ),
    );
  }
}'''
content = content.replace(dialog_end_old, dialog_end_new)


# 5. Fix unpaid balances logic
unpaid_logic_old = '''      data.forEach((key, value) {
        if (value['remainingBalance'] != null &&
            value['remainingBalance'] > 0 &&
            (value['status'] == 'confirmed' || value['status'] == 'checked-in' || value['status'] == 'pending')) {
          Map b = Map.from(value);
          b['id'] = key;
          unpaid.add(b);
        }
      });'''

unpaid_logic_new = '''      data.forEach((key, value) {
        String status = (value['status'] ?? '').toString().toLowerCase();
        double remaining = double.tryParse(value['remainingBalance']?.toString() ?? '0') ?? 0;
        bool isPaid = value['isPaid'] == true;
        
        if (remaining > 0 && !isPaid && status != 'cancelled' && status != 'refunded') {
          Map b = Map.from(value);
          b['id'] = key;
          unpaid.add(b);
        }
      });'''
content = content.replace(unpaid_logic_old, unpaid_logic_new)

# 6. Change Unpaid Balances click on Stat card to just jump to the tab
content = content.replace("onTap: widget.onShowUnpaidBalances,", "onTap: () => DefaultTabController.of(context)?.animateTo(2) ?? widget.onShowUnpaidBalances(),")

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Patch applied")
