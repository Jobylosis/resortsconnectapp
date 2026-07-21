import re

file_path = 'lib/dashboards/owner_dashboard.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update _fetchUnpaidBookings logic
old_fetch = '''    if (snapshot.exists) {
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
    }'''

new_fetch = '''    if (snapshot.exists) {
      final data = snapshot.value as Map;
      data.forEach((key, value) {
        String status = (value['status'] ?? '').toString().toLowerCase();
        
        double remaining = 0;
        if (value['isPaid'] == true || value['remainingBalance']?.toString() == '0' || value['paymentStatus'] == 'fully_paid') {
          remaining = 0;
        } else if (value['remainingBalance'] != null) {
          remaining = double.tryParse(value['remainingBalance'].toString()) ?? 0;
        } else {
          double total = double.tryParse(value['totalPrice']?.toString() ?? '0') ?? 0;
          String paymentOption = (value['paymentOption'] ?? '').toString();
          double paid = double.tryParse(value['amountPaid']?.toString() ?? '0') ?? 0;
          if (value['amountPaid'] == null) {
             paid = paymentOption.contains('30%') ? total * 0.3 : total;
          }
          remaining = total - paid;
        }

        if (remaining > 0 && (status == 'pending' || status == 'confirmed' || status == 'checked in' || status == 'checked-in')) {
          Map b = Map.from(value);
          b['id'] = key;
          b['calculatedBalance'] = remaining;
          unpaid.add(b);
        }
      });
    }'''
content = content.replace(old_fetch, new_fetch)

# 2. Update _processPaymentForBookings
old_process = '''    double newlyPaid = 0;
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
    }'''

new_process = '''    double newlyPaid = 0;
    for (var booking in bookingsToPay) {
      double bal = double.tryParse(booking['calculatedBalance']?.toString() ?? '0') ?? 0;
      newlyPaid += bal;
      
      // Update primary booking
      await FirebaseDatabase.instance.ref('bookings/${booking['id']}').update({
        'remainingBalance': 0,
        'isPaid': true,
        'paymentStatus': 'fully_paid'
      });
      
      // Update tourist user booking record if exists
      if (booking['touristUid'] != null) {
        await FirebaseDatabase.instance.ref('tourist_users/${booking['touristUid']}/bookings/${booking['id']}').update({
          'remainingBalance': 0,
          'isPaid': true,
          'paymentStatus': 'fully_paid'
        });
      }

      await FirebaseDatabase.instance.ref('revenue_reports/${widget.ownerId}').push().set({
        'bookingId': booking['id'],
        'amount': bal,
        'date': ServerValue.timestamp,
        'description': 'Balance paid for ${booking['bookingCode'] ?? 'Unknown'}',
        'type': 'balance_payment'
      });
    }'''
content = content.replace(old_process, new_process)

# 3. Update UI to use calculatedBalance instead of remainingBalance
old_calc1 = '''double totalAmount = 0;
    for (var b in bookingsToPay) {
      totalAmount += double.tryParse(b['remainingBalance']?.toString() ?? '0') ?? 0;
    }'''
new_calc1 = '''double totalAmount = 0;
    for (var b in bookingsToPay) {
      totalAmount += double.tryParse(b['calculatedBalance']?.toString() ?? '0') ?? 0;
    }'''
content = content.replace(old_calc1, new_calc1)

old_calc2 = '''double totalUnpaid = items.fold(0.0, (sum, item) => sum + (double.tryParse(item['remainingBalance']?.toString() ?? '0') ?? 0));'''
new_calc2 = '''double totalUnpaid = items.fold(0.0, (sum, item) => sum + (double.tryParse(item['calculatedBalance']?.toString() ?? '0') ?? 0));'''
content = content.replace(old_calc2, new_calc2)

old_calc3 = '''Text('Balance: ₱${b['remainingBalance']}', style: const TextStyle(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 13)),'''
new_calc3 = '''Text('Balance: ₱${b['calculatedBalance']}', style: const TextStyle(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 13)),'''
content = content.replace(old_calc3, new_calc3)


with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Patch applied for calculation")
