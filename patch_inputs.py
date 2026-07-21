import re

def patch_admin_js():
    file_path = "website/src/components/AdminCMS.js"
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    # 1. Update handleChange
    old_handleChange = """  const handleChange = (field, value) => {
    setCmsData(prev => ({ ...prev, [field]: value }));
  };"""
    new_handleChange = """  const handleChange = (field, value) => {
    if (field !== 'heroImageUrl' && field !== 'heroImageUrls') {
        value = value.replace(/[^a-zA-Z0-9\\s]/g, '');
    }
    setCmsData(prev => ({ ...prev, [field]: value }));
  };"""
    content = content.replace(old_handleChange, new_handleChange)

    # 2. Update handleContactChange
    old_handleContactChange = """  const handleContactChange = (field, value) => {
    setCmsData(prev => ({ ...prev, contact: { ...prev.contact, [field]: value } }));
  };"""
    new_handleContactChange = """  const handleContactChange = (field, value) => {
    if (field !== 'email' && field !== 'phone') {
        // allowing : / . - for URLs
        value = value.replace(/[^a-zA-Z0-9\\s:/.\\-]/g, '');
    }
    setCmsData(prev => ({ ...prev, contact: { ...prev.contact, [field]: value } }));
  };"""
    content = content.replace(old_handleContactChange, new_handleContactChange)

    # 3. Update handlePromoChange
    old_handlePromoChange = """  const handlePromoChange = (id, field, value) => {
    setCmsData(prev => ({
      ...prev,
      promotions: {
        ...prev.promotions,
        [id]: { ...prev.promotions[id], [field]: value }
      }
    }));
  };"""
    new_handlePromoChange = """  const handlePromoChange = (id, field, value) => {
    if (field === 'title' || field === 'description') {
        value = value.replace(/[^a-zA-Z0-9\\s]/g, '');
    }
    // Note: badge allows special characters, imageUrl is a URL, dates are dates.
    setCmsData(prev => ({
      ...prev,
      promotions: {
        ...prev.promotions,
        [id]: { ...prev.promotions[id], [field]: value }
      }
    }));
  };"""
    content = content.replace(old_handlePromoChange, new_handlePromoChange)

    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)

def patch_admin_dart():
    file_path = "lib/dashboards/admin_cms_page.dart"
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    # We need to apply InputFormatters to text fields in dart, or filter in onChanged.
    # We can use FilteringTextInputFormatter in dart.
    # To do this, we modify _buildTextField
    
    old_build_text_field = """  Widget _buildTextField(TextEditingController controller, String label, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,"""
        
    new_build_text_field = """  import_added_formatters;
    
  Widget _buildTextField(TextEditingController controller, String label, {int maxLines = 1, bool allowSpecial = false, bool isUrl = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        inputFormatters: allowSpecial 
            ? null 
            : (isUrl 
                ? [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\\s:/.\-]'))]
                : [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\\s]'))]
              ),"""
    
    content = content.replace(old_build_text_field, new_build_text_field)
    
    if "import 'package:flutter/services.dart';" not in content:
        content = content.replace("import_added_formatters;", "")
        content = content.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';")
    else:
        content = content.replace("import_added_formatters;\n    ", "")

    # Now update calls to _buildTextField
    content = content.replace("_buildTextField(_emailCtrl, 'Email Address')", "_buildTextField(_emailCtrl, 'Email Address', allowSpecial: true)")
    content = content.replace("_buildTextField(_fbCtrl, 'Facebook URL')", "_buildTextField(_fbCtrl, 'Facebook URL', isUrl: true)")
    content = content.replace("_buildTextField(_twCtrl, 'Twitter URL')", "_buildTextField(_twCtrl, 'Twitter URL', isUrl: true)")
    content = content.replace("_buildTextField(_igCtrl, 'Instagram URL')", "_buildTextField(_igCtrl, 'Instagram URL', isUrl: true)")
    # Note: Badge allows special chars, it's defined directly as a TextFormField in _buildPromoCard
    # But for Title and Description in PromoCard, we need to add formatters.
    
    old_promo_title = """            TextFormField(
              initialValue: promo['title'],
              onChanged: (val) => promo['title'] = val,
              decoration: const InputDecoration(labelText: 'Title'),
            ),"""
    new_promo_title = """            TextFormField(
              initialValue: promo['title'],
              onChanged: (val) => promo['title'] = val,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\\s]'))],
              decoration: const InputDecoration(labelText: 'Title'),
            ),"""
    content = content.replace(old_promo_title, new_promo_title)
    
    old_promo_desc = """            TextFormField(
              initialValue: promo['description'],
              onChanged: (val) => promo['description'] = val,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description'),
            ),"""
    new_promo_desc = """            TextFormField(
              initialValue: promo['description'],
              onChanged: (val) => promo['description'] = val,
              maxLines: 2,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\\s]'))],
              decoration: const InputDecoration(labelText: 'Description'),
            ),"""
    content = content.replace(old_promo_desc, new_promo_desc)

    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)

patch_admin_js()
patch_admin_dart()
print("Patched inputs")
