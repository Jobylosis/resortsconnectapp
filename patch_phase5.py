import re
import glob

# 1. Update _buildTextField in owner_dashboard.dart
file_path = 'lib/dashboards/owner_dashboard.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

old_input_formatters = r'''      inputFormatters: [
        ...?inputFormatters,
        FilteringTextInputFormatter.deny(RegExp(
            r'[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]',
            unicode: true)),
      ],'''

new_input_formatters = r'''      inputFormatters: [
        ...?inputFormatters,
        FilteringTextInputFormatter.deny(RegExp(
            r'[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]',
            unicode: true)),
        FilteringTextInputFormatter.deny(RegExp(r'[!#^&*+={}\[\]|\\<>\/~]')),
      ],'''

content = content.replace(old_input_formatters, new_input_formatters)
with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

# 2. Modernize _showLogoutDialog in admin_dashboard, owner_dashboard, tourist_dashboard
modern_logout_dialog = '''        builder: (context) => Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 10))]
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.logout_rounded, size: 48, color: Colors.redAccent),
                    const SizedBox(height: 16),
                    const Text('Logout', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Are you sure you want to log out?', textAlign: TextAlign.center, style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 14)
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel')
                          )
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 14)
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              FirebaseAuth.instance.signOut();
                            },
                            child: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold))
                          )
                        )
                      ]
                    )
                  ]
                )
              )
            ));'''

files_to_patch = [
    'lib/dashboards/admin_dashboard.dart',
    'lib/dashboards/owner_dashboard.dart',
    'lib/dashboards/tourist_dashboard.dart'
]

for fp in files_to_patch:
    with open(fp, 'r', encoding='utf-8') as f:
        c = f.read()
    
    # We replace the body of _showLogoutDialog.
    # To be safe, we use regex to find the method and replace it.
    pattern = re.compile(r'void _showLogoutDialog\(BuildContext context\) \{\s*showDialog\(\s*context:\s*context,\s*builder:\s*\(context\)\s*=>\s*AlertDialog\(.*?\),\s*\);\s*\}', re.DOTALL)
    
    new_method = '''void _showLogoutDialog(BuildContext context) {
    showDialog(
        context: context,
''' + modern_logout_dialog + '''
  }'''
    
    c = pattern.sub(new_method, c)
    with open(fp, 'w', encoding='utf-8') as f:
        f.write(c)

print('Patch applied successfully')
