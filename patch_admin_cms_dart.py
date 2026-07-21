import re
import sys

def patch_admin_cms_dart():
    file_path = "lib/dashboards/admin_cms_page.dart"
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    old_validation = """    if (_aboutHeadingCtrl.text.trim().isEmpty || _aboutTextCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('About Heading and Text are required')));
      return;
    }"""
    
    new_validation = """    if (_aboutHeadingCtrl.text.trim().isEmpty || _aboutTextCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('About Heading and Text are required')));
      return;
    }
    
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email address is required')));
      return;
    }
    final emailRegex = RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$");
    if (!emailRegex.hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid email address')));
      return;
    }

    String phone = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone number is required')));
      return;
    }
    if (phone.length != 11 || !phone.startsWith('09')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone number must be 11 digits and start with 09')));
      return;
    }"""
    
    content = content.replace(old_validation, new_validation)

    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("admin_cms_page.dart patched")

patch_admin_cms_dart()
