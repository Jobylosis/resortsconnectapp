import re
import sys

def patch_landing_dart():
    file_path = "lib/landing_page.dart"
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    # 1. Update _timer logic
    old_timer = """        setState(() {
          int maxImages = _cmsData != null && _cmsData!['heroImageUrl'] != null ? _heroImages.length + 1 : _heroImages.length;
          _heroIdx = (_heroIdx + 1) % maxImages;
        });"""
        
    new_timer = """        setState(() {
          int maxImages = _heroImages.length;
          if (_cmsData != null) {
            if (_cmsData!['heroImageUrls'] != null && (_cmsData!['heroImageUrls'] as List).isNotEmpty) {
              maxImages = (_cmsData!['heroImageUrls'] as List).length;
            } else if (_cmsData!['heroImageUrl'] != null && _cmsData!['heroImageUrl'].toString().isNotEmpty) {
              maxImages = _heroImages.length + 1;
            }
          }
          _heroIdx = (_heroIdx + 1) % maxImages;
        });"""
    content = content.replace(old_timer, new_timer)

    # 2. Update currentHeroImages
    old_current = """    // Combine CMS hero image with defaults if available
    List<Map<String, String>> currentHeroImages = [];
    if (_cmsData != null && _cmsData!['heroImageUrl'] != null) {
      currentHeroImages.add({
        'src': _cmsData!['heroImageUrl'],
        'title': _cmsData!['heroTitle'] ?? 'Featured',
        'isNetwork': 'true'
      });
    }
    currentHeroImages.addAll(_heroImages);"""
    
    new_current = """    // Combine CMS hero image with defaults if available
    List<Map<String, String>> currentHeroImages = [];
    if (_cmsData != null) {
      if (_cmsData!['heroImageUrls'] != null && (_cmsData!['heroImageUrls'] as List).isNotEmpty) {
        for (var url in _cmsData!['heroImageUrls']) {
          currentHeroImages.add({
            'src': url.toString(),
            'title': _cmsData!['heroTitle'] ?? 'Featured',
            'isNetwork': 'true'
          });
        }
      } else if (_cmsData!['heroImageUrl'] != null && _cmsData!['heroImageUrl'].toString().isNotEmpty) {
        currentHeroImages.add({
          'src': _cmsData!['heroImageUrl'],
          'title': _cmsData!['heroTitle'] ?? 'Featured',
          'isNetwork': 'true'
        });
        currentHeroImages.addAll(_heroImages);
      } else {
        currentHeroImages.addAll(_heroImages);
      }
    } else {
      currentHeroImages.addAll(_heroImages);
    }"""
    content = content.replace(old_current, new_current)

    # 3. Update Promotions filter
    # Look for how promotions are parsed
    old_promo_filter = """      if (data['promotions'] is Map) {
        final promos = Map<String, dynamic>.from(data['promotions']);
        _activePromotions = promos.values
            .where((p) => p['active'] == true)
            .map((p) => Map<String, dynamic>.from(p as Map))
            .toList();
      }"""
      
    new_promo_filter = """      if (data['promotions'] is Map) {
        final promos = Map<String, dynamic>.from(data['promotions']);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        
        _activePromotions = promos.values.where((p) {
          if (p['active'] != true) return false;
          if (p['endDate'] != null && p['endDate'].toString().isNotEmpty) {
            try {
              final end = DateTime.parse(p['endDate']);
              if (today.isAfter(end)) return false;
            } catch (e) {
              // Ignore parse error
            }
          }
          return true;
        }).map((p) => Map<String, dynamic>.from(p as Map)).toList();
      }"""
      
    content = content.replace(old_promo_filter, new_promo_filter)

    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("landing_page.dart patched")

patch_landing_dart()
