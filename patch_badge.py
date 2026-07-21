import re

def patch_admin_js():
    file_path = "website/src/components/AdminCMS.js"
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Add badge field to web CMS
    old_promo_ui = """                    <div className="form-group">
                      <label className="label">Promo Title</label>"""
    new_promo_ui = """                    <div className="form-group">
                      <label className="label">Badge (e.g. 50% OFF)</label>
                      <input className="input" value={promo.badge || ''} onChange={e => handlePromoChange(id, 'badge', e.target.value)} />
                    </div>
                    <div className="form-group">
                      <label className="label">Promo Title</label>"""
    content = content.replace(old_promo_ui, new_promo_ui)

    # Allow % for badge in handlePromoChange just in case
    old_handlePromoChange = """  const handlePromoChange = (id, field, value) => {
    if (field === 'title' || field === 'description') {
        value = value.replace(/[^a-zA-Z0-9\\s]/g, '');
    }"""
    new_handlePromoChange = """  const handlePromoChange = (id, field, value) => {
    if (field === 'title' || field === 'description') {
        value = value.replace(/[^a-zA-Z0-9\\s]/g, '');
    } else if (field === 'badge') {
        value = value.replace(/[^a-zA-Z0-9\\s%]/g, '');
    }"""
    content = content.replace(old_handlePromoChange, new_handlePromoChange)
    
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)

def patch_admin_dart():
    file_path = "lib/dashboards/admin_cms_page.dart"
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    # The user says badge shouldn't strip % in app either. Since it had no input formatters, maybe they just want an explicit formatter or their keyboard blocked it? 
    # Let's add an explicit input formatter that allows %.
    old_badge_ui = """            TextFormField(
              initialValue: promo['badge'],
              onChanged: (val) => promo['badge'] = val,
              decoration: const InputDecoration(labelText: 'Badge (e.g. 50% OFF)'),
            ),"""
    new_badge_ui = """            TextFormField(
              initialValue: promo['badge'],
              onChanged: (val) => promo['badge'] = val,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\\s%]'))],
              decoration: const InputDecoration(labelText: 'Badge (e.g. 50% OFF)'),
            ),"""
    content = content.replace(old_badge_ui, new_badge_ui)

    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)

patch_admin_js()
patch_admin_dart()
print("Patched badge")
