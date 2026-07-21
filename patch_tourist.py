import re

# 1. Update web version
web_file = 'website/src/components/TouristDashboard.js'
with open(web_file, 'r', encoding='utf-8') as f:
    web_content = f.read()

# Replace the reduce logic
old_reduce = '''myBookings.reduce((sum, b) => sum + Math.max(0, Number(b.totalPrice || 0) - Number(b.amountPaid || 0)), 0)'''
new_reduce = '''myBookings.reduce((sum, b) => {
                  if (['Cancelled', 'Declined', 'Refunded', 'Refund Approved', 'Completed'].includes(b.status)) return sum;
                  return sum + Math.max(0, Number(b.totalPrice || 0) - Number(b.amountPaid || 0));
                }, 0)'''
web_content = web_content.replace(old_reduce, new_reduce)

# Update individual booking card balance display
old_card_balance = '''Math.max(0, Number(b.totalPrice || 0) - Number(b.amountPaid || 0)).toLocaleString()'''
new_card_balance = '''(['Cancelled', 'Declined', 'Refunded', 'Refund Approved', 'Completed'].includes(b.status) ? 0 : Math.max(0, Number(b.totalPrice || 0) - Number(b.amountPaid || 0))).toLocaleString()'''
web_content = web_content.replace(old_card_balance, new_card_balance)

# Update breakdown balance display
old_breakdown_balance = '''['Balance', `₱${Math.max(0, Number(detailBooking.totalPrice || 0) - Number(detailBooking.amountPaid || 0)).toLocaleString()}`],'''
new_breakdown_balance = '''['Balance', `₱${(['Cancelled', 'Declined', 'Refunded', 'Refund Approved', 'Completed'].includes(detailBooking.status) ? 0 : Math.max(0, Number(detailBooking.totalPrice || 0) - Number(detailBooking.amountPaid || 0))).toLocaleString()}`],'''
web_content = web_content.replace(old_breakdown_balance, new_breakdown_balance)


with open(web_file, 'w', encoding='utf-8') as f:
    f.write(web_content)

print("Web version patched.")

# 2. Update app version
app_file = 'lib/dashboards/tourist_dashboard.dart'
with open(app_file, 'r', encoding='utf-8') as f:
    app_content = f.read()

old_app_balance = '''                        double balance = totalPrice - amountPaid;
                        if (balance < 0) balance = 0;'''
                        
new_app_balance = '''                        double balance = totalPrice - amountPaid;
                        if (balance < 0) balance = 0;
                        String bStatus = (booking['status'] ?? '').toString().toLowerCase();
                        if (bStatus == 'cancelled' || bStatus == 'declined' || bStatus == 'refunded' || bStatus == 'refund approved' || bStatus == 'completed') {
                          balance = 0;
                        }'''
app_content = app_content.replace(old_app_balance, new_app_balance)

old_stat_balance = '''      totalUnpaid += (double.tryParse((val['totalPrice'] ?? val['price'] ?? '0').toString().replaceAll(',', '')) ?? 0) -
          (double.tryParse((val['amountPaid'] ?? '0').toString().replaceAll(',', '')) ?? 0);'''

new_stat_balance = '''      String bStatus = (val['status'] ?? '').toString().toLowerCase();
      if (bStatus != 'cancelled' && bStatus != 'declined' && bStatus != 'refunded' && bStatus != 'refund approved' && bStatus != 'completed') {
        totalUnpaid += (double.tryParse((val['totalPrice'] ?? val['price'] ?? '0').toString().replaceAll(',', '')) ?? 0) -
            (double.tryParse((val['amountPaid'] ?? '0').toString().replaceAll(',', '')) ?? 0);
      }'''
app_content = app_content.replace(old_stat_balance, new_stat_balance)

with open(app_file, 'w', encoding='utf-8') as f:
    f.write(app_content)

print("App version patched.")
