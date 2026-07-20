import re

file_path = 'lib/dashboards/owner_dashboard.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add import for notifications
if "import 'package:resortsconnectapp/notifications_page.dart';" not in content:
    content = content.replace(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\nimport 'package:resortsconnectapp/notifications_page.dart';"
    )

# 2. Add notification icon before theme toggle
notification_icon = '''          IconButton(
            icon: const Icon(Icons.notifications_active_rounded),
            color: Theme.of(context).colorScheme.primary,
            onPressed: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const NotificationsPage(userRole: 'owner')));
            },
          ),
          IconButton(
            icon: Icon(themeProvider.themeMode == ThemeMode.dark'''

content = content.replace(
    '''          IconButton(
            icon: Icon(themeProvider.themeMode == ThemeMode.dark''',
    notification_icon
)

# 3. Remove Delete Button in BookingCard
# The positioned block starts at "Positioned(\n              top: 4,\n              right: 4,\n              child: _deletingBookingKey == key"
# and ends with "setState(() => _deletingBookingKey = key))),\n        ]));\n  }\n}"

delete_btn_pattern = r"Positioned\(\s*top:\s*4,\s*right:\s*4,\s*child:\s*_deletingBookingKey.*?_deletingBookingKey\s*=\s*key\)\)\),"

content = re.sub(delete_btn_pattern, "", content, flags=re.DOTALL)


with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Patch successfully applied!")
