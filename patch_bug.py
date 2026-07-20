import re

file_path = 'lib/dashboards/owner_dashboard.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

total_rev_old = '''                                    double totalRevenue = 0;
                                    Map bookings = {};
                                    int totalBookings = 0;'''

total_rev_new = '''                                    double totalRevenue = 0;
                                    double totalPending = 0;
                                    Map bookings = {};
                                    int totalBookings = 0;'''

content = content.replace(total_rev_old, total_rev_new)


loop_old = '''                                            if (status == 'confirmed' ||
                                                status == 'completed' ||
                                                status == 'checked in') {
                                              totalRevenue += double.tryParse(
                                                      (value['totalPrice'] ??
                                                              value['total'] ??
                                                              value['amount'] ??
                                                              value['payment'] ??
                                                              value['price'] ??
                                                              '0')
                                                          .toString()
                                                          .replaceAll(',', '')) ??
                                                  0;
                                            }'''

loop_new = '''                                            if (status == 'confirmed' ||
                                                status == 'completed' ||
                                                status == 'checked in') {
                                              totalRevenue += double.tryParse(
                                                      (value['totalPrice'] ??
                                                              value['total'] ??
                                                              value['amount'] ??
                                                              value['payment'] ??
                                                              value['price'] ??
                                                              '0')
                                                          .toString()
                                                          .replaceAll(',', '')) ??
                                                  0;
                                            }
                                            if (value['remainingBalance'] != null && (value['isPaid'] == null || value['isPaid'] == false) && status != 'cancelled' && status != 'refunded') {
                                              totalPending += double.tryParse(value['remainingBalance'].toString()) ?? 0;
                                            }'''

content = content.replace(loop_old, loop_new)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Bug patched.")
