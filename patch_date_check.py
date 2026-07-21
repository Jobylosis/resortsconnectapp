import re

# 1. Update web version
web_file = 'website/src/components/OwnerDashboard.js'
with open(web_file, 'r', encoding='utf-8') as f:
    web_content = f.read()

old_web_btn = '''                    {scannedViaQr ? (
                      <button className="btn" style={{ background: '#4F46E5', color: 'white', width: '100%', fontSize: '13px' }} onClick={() => { initiateUpdateStatus(scannedBooking.id, 'Checked In'); }}>Check In Customer</button>
                    ) : ('''

new_web_btn = '''                    {scannedViaQr ? (
                      (() => {
                        const today = new Date();
                        today.setHours(0, 0, 0, 0);
                        let canCheckIn = true;
                        try {
                          if (scannedBooking.bookingDate) {
                            const bDate = parse(scannedBooking.bookingDate, 'MMM dd, yyyy', new Date());
                            bDate.setHours(0, 0, 0, 0);
                            canCheckIn = today >= bDate;
                          }
                        } catch(e) {}
                        return (
                          <button 
                            className="btn" 
                            style={{ background: canCheckIn ? '#4F46E5' : '#9CA3AF', color: 'white', width: '100%', fontSize: '13px', cursor: canCheckIn ? 'pointer' : 'not-allowed' }} 
                            disabled={!canCheckIn}
                            onClick={() => { initiateUpdateStatus(scannedBooking.id, 'Checked In'); }}
                          >
                            {canCheckIn ? 'Check In Customer' : `Check-in on ${scannedBooking.bookingDate}`}
                          </button>
                        );
                      })()
                    ) : ('''
web_content = web_content.replace(old_web_btn, new_web_btn)

with open(web_file, 'w', encoding='utf-8') as f:
    f.write(web_content)

print("Web version patched.")

# 2. Update app version
app_file = 'lib/dashboards/owner_dashboard.dart'
with open(app_file, 'r', encoding='utf-8') as f:
    app_content = f.read()

old_app_btn = '''                if (status == 'confirmed')
                  scannedViaQr
                      ? ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _showStatusConfirmation(key, 'Checked In', b);
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo),
                          child: const Text('Check In Customer'),
                        )
                      : const Padding('''
                        
new_app_btn = '''                if (status == 'confirmed')
                  scannedViaQr
                      ? (() {
                          bool canCheckIn = true;
                          String? bDateStr = b['bookingDate'];
                          if (bDateStr != null && bDateStr.isNotEmpty) {
                            try {
                              DateTime parsed = DateFormat("MMM dd, yyyy").parse(bDateStr);
                              DateTime today = DateTime.now();
                              DateTime todayMidnight = DateTime(today.year, today.month, today.day);
                              DateTime parsedMidnight = DateTime(parsed.year, parsed.month, parsed.day);
                              if (todayMidnight.isBefore(parsedMidnight)) {
                                canCheckIn = false;
                              }
                            } catch(e) {}
                          }
                          return ElevatedButton(
                            onPressed: canCheckIn ? () {
                              Navigator.pop(context);
                              _showStatusConfirmation(key, 'Checked In', b);
                            } : null,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: canCheckIn ? Colors.indigo : Colors.grey),
                            child: Text(canCheckIn ? 'Check In Customer' : 'Check-in on ${b['bookingDate']}'),
                          );
                        })()
                      : const Padding('''
app_content = app_content.replace(old_app_btn, new_app_btn)

with open(app_file, 'w', encoding='utf-8') as f:
    f.write(app_content)

print("App version patched.")
