import re

file_path = 'lib/dashboards/owner_dashboard.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

old_loop = '''                                          if (status == 'confirmed' ||
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
                                        }
                                      });'''

new_loop = '''                                          if (status == 'confirmed' ||
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
                                          
                                          // Calculate pending balance
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
                                            totalPending += remaining;
                                          }
                                        }
                                      });'''

content = content.replace(old_loop, new_loop)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Patch applied for totalPending")
