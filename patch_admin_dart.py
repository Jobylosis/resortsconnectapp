import re
import sys

def patch_admin_dart():
    file_path = "lib/dashboards/admin_cms_page.dart"
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    # 1. Update _cmsData to use heroImageUrls
    content = content.replace(
        "'heroImageUrl': '',",
        "'heroImageUrls': <String>[],"
    )

    # 2. Update _loadCmsData
    # Find _cmsData['heroImageUrl'] = data['heroImageUrl'] ?? '';
    old_load = "_cmsData['heroImageUrl'] = data['heroImageUrl'] ?? '';"
    new_load = """if (data['heroImageUrls'] != null) {
            _cmsData['heroImageUrls'] = List<String>.from(data['heroImageUrls']);
          } else if (data['heroImageUrl'] != null && data['heroImageUrl'].isNotEmpty) {
            _cmsData['heroImageUrls'] = [data['heroImageUrl']];
          } else {
            _cmsData['heroImageUrls'] = <String>[];
          }"""
    content = content.replace(old_load, new_load)

    # 3. Add date fields to _addPromo
    old_add_promo = """      _cmsData['promotions'][id] = {
        'title': '',
        'description': '',
        'badge': 'NEW',
        'imageUrl': '',
        'startDate': '',
        'endDate': ''
      };"""
    # Wait, the dart file already has startDate and endDate in _addPromo but it doesn't have text fields for them.
    # Let's add text fields for startDate and endDate.

    old_promo_card = """            TextFormField(
              initialValue: promo['badge'],
              onChanged: (val) => promo['badge'] = val,
              decoration: const InputDecoration(labelText: 'Badge (e.g. 50% OFF)'),
            ),
            const SizedBox(height: 16),
            _buildImagePicker('imageUrl', 'Promo Image', promoId: id),
          ],"""
    new_promo_card = """            TextFormField(
              initialValue: promo['badge'],
              onChanged: (val) => promo['badge'] = val,
              decoration: const InputDecoration(labelText: 'Badge (e.g. 50% OFF)'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: promo['startDate'],
                    onChanged: (val) => promo['startDate'] = val,
                    decoration: const InputDecoration(labelText: 'Start Date (YYYY-MM-DD)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: promo['endDate'],
                    onChanged: (val) => promo['endDate'] = val,
                    decoration: const InputDecoration(labelText: 'End Date (YYYY-MM-DD)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildImagePicker('imageUrl', 'Promo Image', promoId: id),
          ],"""
    content = content.replace(old_promo_card, new_promo_card)

    # 4. Update _buildImagePicker to _buildHeroImagesPicker
    hero_picker = """  Widget _buildHeroImagesPicker() {
    final List<String> urls = _cmsData['heroImageUrls'] as List<String>;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Hero Background Images', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (urls.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: urls.asMap().entries.map((entry) {
              int idx = entry.key;
              String url = entry.value;
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(url, height: 100, width: 100, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton(
                      icon: const Icon(Icons.cancel, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          urls.removeAt(idx);
                        });
                      },
                    ),
                  )
                ],
              );
            }).toList(),
          ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () async {
            final url = await _uploadImage();
            if (url != null) {
              setState(() {
                urls.add(url);
              });
            }
          },
          icon: const Icon(Icons.add_photo_alternate),
          label: const Text('Add Hero Image'),
        ),
      ],
    );
  }"""
    
    content = content.replace(
        "Widget _buildImagePicker(String fieldKey, String label, {String? promoId}) {",
        hero_picker + "\n\n  Widget _buildImagePicker(String fieldKey, String label, {String? promoId}) {"
    )

    # Replace the call to _buildImagePicker for heroImageUrl
    content = content.replace(
        "_buildImagePicker('heroImageUrl', 'Hero Background Image'),",
        "_buildHeroImagesPicker(),"
    )
    
    # 5. Add validation to _saveCmsData
    old_save = """    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    
    _cmsData['heroTitle'] = _heroTitleCtrl.text.trim();"""
    
    new_save = """    if (!_formKey.currentState!.validate()) return;
    
    if (_heroTitleCtrl.text.trim().isEmpty || _heroSubCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hero Title and Subtitle are required')));
      return;
    }
    if ((_cmsData['heroImageUrls'] as List).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('At least one Hero Image is required')));
      return;
    }
    if (_aboutHeadingCtrl.text.trim().isEmpty || _aboutTextCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('About Heading and Text are required')));
      return;
    }

    setState(() => _isSaving = true);
    
    _cmsData['heroTitle'] = _heroTitleCtrl.text.trim();"""
    
    content = content.replace(old_save, new_save)

    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("admin_cms_page.dart patched")

patch_admin_dart()
