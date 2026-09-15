import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../theme.dart';

class AdminCmsPage extends StatefulWidget {
  const AdminCmsPage({super.key});

  @override
  State<AdminCmsPage> createState() => _AdminCmsPageState();
}

class _AdminCmsPageState extends State<AdminCmsPage> {
  bool _isLoading = true;
  bool _isSaving = false;

  final Map<String, dynamic> _cmsData = {
    'heroTitle': '',
    'heroSubtitle': '',
    'heroImageUrls': <String>[],
    'aboutHeading': '',
    'aboutText': '',
    'contact': {
      'email': '',
      'phone': '',
      'address': '',
      'facebook': '',
      'twitter': '',
      'instagram': '',
    },
    'contact_platforms': <Map<String, dynamic>>[],
    'promotions': <String, dynamic>{},
  };

  final List<String> _availableRoomCategories = [
    'Standard',
    'Deluxe',
    'Suite',
    'Villa',
    'Family',
    'Dormitory',
    '2-Pax Rooms',
    '4-Pax Rooms',
  ];

  final _formKey = GlobalKey<FormState>();

  final _heroTitleCtrl = TextEditingController();
  final _heroSubCtrl = TextEditingController();
  final _aboutHeadingCtrl = TextEditingController();
  final _aboutTextCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCmsData();
  }

  Future<void> _loadCmsData() async {
    try {
      final snap = await FirebaseDatabase.instance.ref('cms/homepage').get();
      if (snap.exists && snap.value != null) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        setState(() {
          _cmsData['heroTitle'] = data['heroTitle'] ?? '';
          _cmsData['heroSubtitle'] = data['heroSubtitle'] ?? '';
          if (data['heroImageUrls'] != null) {
            _cmsData['heroImageUrls'] = List<String>.from(data['heroImageUrls']);
          } else if (data['heroImageUrl'] != null && data['heroImageUrl'].isNotEmpty) {
            _cmsData['heroImageUrls'] = <String>[data['heroImageUrl'].toString()];
          } else {
            _cmsData['heroImageUrls'] = <String>[];
          }
          _cmsData['aboutHeading'] = data['aboutHeading'] ?? '';
          _cmsData['aboutText'] = data['aboutText'] ?? '';
          
          if (data['contact_platforms'] != null) {
            if (data['contact_platforms'] is List) {
              _cmsData['contact_platforms'] = (data['contact_platforms'] as List)
                  .where((e) => e != null)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
            } else if (data['contact_platforms'] is Map) {
              final cpMap = data['contact_platforms'] as Map;
              _cmsData['contact_platforms'] = cpMap.entries
                  .map((e) => Map<String, dynamic>.from(e.value as Map))
                  .toList();
            }
          } else if (data['contact'] is Map) {
            final c = Map<String, dynamic>.from(data['contact']);
            _cmsData['contact_platforms'] = [
              {'id': '1', 'platform_name': 'Facebook', 'platform_url_or_handle': c['facebook'] ?? '', 'order': 1},
              {'id': '2', 'platform_name': 'Email', 'platform_url_or_handle': c['email'] ?? '', 'order': 2},
              {'id': '3', 'platform_name': 'Phone', 'platform_url_or_handle': c['phone'] ?? '', 'order': 3},
            ];
          }

          if (data['promotions'] is Map) {
            final p = Map<String, dynamic>.from(data['promotions']);
            final today = DateTime.now();
            final todayStart = DateTime(today.year, today.month, today.day);
            Map<String, Object?> expiredUpdates = {};

            final mappedPromos = p.map((k, v) {
              final promoMap = Map<String, dynamic>.from(v as Map);
              if (promoMap['active'] == true && promoMap['endDate'] != null) {
                final end = DateTime.tryParse(promoMap['endDate'].toString().trim());
                if (end != null) {
                  final endDay = DateTime(end.year, end.month, end.day);
                  if (todayStart.isAfter(endDay)) {
                    promoMap['active'] = false;
                    expiredUpdates['cms/homepage/promotions/$k/active'] = false;
                  }
                }
              }
              return MapEntry(k, promoMap);
            });

            if (expiredUpdates.isNotEmpty) {
              FirebaseDatabase.instance.ref().update(expiredUpdates).catchError((err) {
                debugPrint("Error syncing expired promos from Admin CMS: $err");
              });
            }

            _cmsData['promotions'] = mappedPromos;
          }
          
          _heroTitleCtrl.text = _cmsData['heroTitle'];
          _heroSubCtrl.text = _cmsData['heroSubtitle'];
          _aboutHeadingCtrl.text = _cmsData['aboutHeading'];
          _aboutTextCtrl.text = _cmsData['aboutText'];
        });
      }
    } catch (e) {
      debugPrint("Error loading CMS data: \$e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveCmsData() async {
    if (!_formKey.currentState!.validate()) return;
    
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
    
    _cmsData['heroTitle'] = _heroTitleCtrl.text.trim();
    _cmsData['heroSubtitle'] = _heroSubCtrl.text.trim();
    _cmsData['aboutHeading'] = _aboutHeadingCtrl.text.trim();
    _cmsData['aboutText'] = _aboutTextCtrl.text.trim();
    
    // Maintain legacy contact fields from platforms
    final platforms = _cmsData['contact_platforms'] as List<Map<String, dynamic>>? ?? [];
    for (var p in platforms) {
      final name = (p['platform_name'] ?? '').toString().toLowerCase();
      final val = (p['platform_url_or_handle'] ?? '').toString().trim();
      if (name == 'facebook') _cmsData['contact']['facebook'] = val;
      if (name == 'email') _cmsData['contact']['email'] = val;
      if (name == 'phone') _cmsData['contact']['phone'] = val;
    }

    // Auto-disable any promotions whose end date has passed before saving & enforce percentage
    if (_cmsData['promotions'] is Map) {
      final promos = _cmsData['promotions'] as Map;
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      promos.forEach((key, val) {
        if (val is Map) {
          val['discountType'] = 'percentage';
          if (val['active'] == true && val['endDate'] != null) {
            final end = DateTime.tryParse(val['endDate'].toString().trim());
            if (end != null) {
              final endDay = DateTime(end.year, end.month, end.day);
              if (todayStart.isAfter(endDay)) {
                val['active'] = false;
              }
            }
          }
        }
      });
    }

    try {
      await FirebaseDatabase.instance.ref('cms/homepage').set(_cmsData);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Landing page saved successfully!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _addPlatform() {
    setState(() {
      final list = (_cmsData['contact_platforms'] as List<Map<String, dynamic>>);
      list.add({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'platform_name': 'Instagram',
        'platform_url_or_handle': '',
        'order': list.length + 1,
      });
    });
  }

  void _deletePlatform(int index) {
    setState(() {
      final list = (_cmsData['contact_platforms'] as List<Map<String, dynamic>>);
      list.removeAt(index);
    });
  }

  void _movePlatform(int index, int direction) {
    setState(() {
      final list = (_cmsData['contact_platforms'] as List<Map<String, dynamic>>);
      final newIndex = index + direction;
      if (newIndex < 0 || newIndex >= list.length) return;
      final item = list.removeAt(index);
      list.insert(newIndex, item);
      for (int i = 0; i < list.length; i++) {
        list[i]['order'] = i + 1;
      }
    });
  }

  Future<String?> _uploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile == null) return null;

    final url = Uri.parse("https://api.cloudinary.com/v1_1/dnv6ezitm/image/upload");
    final request = http.MultipartRequest("POST", url)
      ..fields['upload_preset'] = 'resort_unsigned'
      ..files.add(await http.MultipartFile.fromPath('file', pickedFile.path));

    try {
      final response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        return jsonDecode(responseData)['secure_url'];
      }
    } catch (e) {
      debugPrint("Upload error: \$e");
    }
    return null;
  }

  void _addPromo() {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    setState(() {
      _cmsData['promotions'][id] = {
        'title': '',
        'description': '',
        'code': '',
        'discountType': 'percentage',
        'discountValue': 10,
        'isEvent': false,
        'applicableRooms': ['ALL'],
        'badge': 'NEW',
        'imageUrl': '',
        'active': false,
        'startDate': '',
        'endDate': ''
      };
    });
  }

  void _addPromoEvent() {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final now = DateTime.now();
    final nextWeek = now.add(const Duration(days: 7));
    setState(() {
      _cmsData['promotions'][id] = {
        'title': 'Special Event Promo',
        'description': 'Enjoy automatic event discount on selected rooms during this period.',
        'code': 'EVENT${now.month}${now.day}',
        'discountType': 'percentage',
        'discountValue': 10,
        'isEvent': true,
        'applicableRooms': ['ALL'],
        'badge': '10% OFF',
        'imageUrl': '',
        'active': true,
        'startDate': now.toIso8601String().split('T')[0],
        'endDate': nextWeek.toIso8601String().split('T')[0]
      };
    });
  }

  void _deletePromo(String id) {
    setState(() {
      _cmsData['promotions'].remove(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Content Management'),
        actions: [
          IconButton(
            icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
            onPressed: _isSaving ? null : _saveCmsData,
          )
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionHeader(Icons.image, 'Hero Section'),
            _buildTextField(_heroTitleCtrl, 'Hero Title'),
            _buildTextField(_heroSubCtrl, 'Hero Subtitle'),
            _buildHeroImagesPicker(),
            const SizedBox(height: 24),
            
            _buildSectionHeader(Icons.info_outline, 'About Section'),
            _buildTextField(_aboutHeadingCtrl, 'About Heading'),
            _buildTextField(_aboutTextCtrl, 'About Text', maxLines: 4),
            const SizedBox(height: 24),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionHeader(Icons.contact_mail, 'Contact & Social Platforms'),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: AppTheme.primaryAccent),
                  onPressed: _addPlatform,
                  tooltip: 'Add Platform',
                ),
              ],
            ),
            const Text(
              'Manage dynamic contact channels shown on public footers (Instagram, Viber, TikTok, Facebook, etc.)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ...((_cmsData['contact_platforms'] as List<Map<String, dynamic>>).asMap().entries.map((entry) {
              final idx = entry.key;
              final plat = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Column(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_upward, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: idx == 0 ? null : () => _movePlatform(idx, -1),
                          ),
                          const SizedBox(height: 4),
                          IconButton(
                            icon: const Icon(Icons.arrow_downward, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: idx == (_cmsData['contact_platforms'] as List).length - 1 ? null : () => _movePlatform(idx, 1),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          initialValue: plat['platform_name'] ?? '',
                          onChanged: (v) => plat['platform_name'] = v,
                          decoration: const InputDecoration(labelText: 'Platform (e.g. Viber, Instagram)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          initialValue: plat['platform_url_or_handle'] ?? '',
                          onChanged: (v) => plat['platform_url_or_handle'] = v,
                          decoration: const InputDecoration(labelText: 'URL, Handle, or Value'),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deletePlatform(idx),
                      ),
                    ],
                  ),
                ),
              );
            })),
            const SizedBox(height: 24),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionHeader(Icons.local_offer, 'Promotions & Events'),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.event, size: 16, color: Colors.deepPurple),
                      label: const Text('+ Promo Event', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                      onPressed: _addPromoEvent,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: AppTheme.primaryAccent),
                      tooltip: 'Add Promo Code',
                      onPressed: _addPromo,
                    ),
                  ],
                ),
              ],
            ),
            ...(_cmsData['promotions'] as Map<String, dynamic>).entries.map((e) => _buildPromoCard(e.key, e.value)),
            const SizedBox(height: 40),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _saveCmsData,
        label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
        icon: const Icon(Icons.save),
        backgroundColor: AppTheme.primaryAccent,
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryAccent),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent)),
        ],
      ),
    );
  }

  
    
  Widget _buildTextField(TextEditingController controller, String label, {int maxLines = 1, bool allowSpecial = false, bool isUrl = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        inputFormatters: allowSpecial 
            ? null 
            : (isUrl 
                ? [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s:/.\-]'))]
                : [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s]'))]
              ),
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Theme.of(context).cardColor,
        ),
      ),
    );
  }

    Widget _buildHeroImagesPicker() {
    final List<dynamic> urls = _cmsData['heroImageUrls'] as List<dynamic>;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Hero Background Images (Recommended: 1080 x 1920 px)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (urls.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: urls.asMap().entries.map((entry) {
              int idx = entry.key;
              String url = entry.value.toString();
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
  }

  Widget _buildImagePicker(String fieldKey, String label, {String? promoId}) {
    String currentUrl = promoId == null 
        ? _cmsData[fieldKey] 
        : _cmsData['promotions'][promoId][fieldKey];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (currentUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(currentUrl, height: 150, width: double.infinity, fit: BoxFit.cover),
          ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () async {
            final url = await _uploadImage();
            if (url != null) {
              setState(() {
                if (promoId == null) {
                  _cmsData[fieldKey] = url;
                } else {
                  _cmsData['promotions'][promoId][fieldKey] = url;
                }
              });
            }
          },
          icon: const Icon(Icons.upload),
          label: const Text('Upload Image'),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPromoCard(String id, Map<String, dynamic> promo) {
    final bool isActive = promo['active'] == true;
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    
    bool isExpired = false;
    if (promo['endDate'] != null && promo['endDate'].toString().trim().isNotEmpty) {
      final end = DateTime.tryParse(promo['endDate'].toString().trim());
      if (end != null) {
        final endDay = DateTime(end.year, end.month, end.day);
        isExpired = todayStart.isAfter(endDay);
      }
    }

    bool isScheduled = false;
    if (promo['startDate'] != null && promo['startDate'].toString().trim().isNotEmpty) {
      final start = DateTime.tryParse(promo['startDate'].toString().trim());
      if (start != null) {
        final startDay = DateTime(start.year, start.month, start.day);
        isScheduled = todayStart.isBefore(startDay);
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Switch(
                        value: isActive,
                        activeColor: AppTheme.primaryAccent,
                        onChanged: (val) {
                          setState(() {
                            promo['active'] = val;
                          });
                        },
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isActive ? 'Active' : 'Inactive',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      if (isExpired)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.withOpacity(0.3)),
                          ),
                          child: const Text(
                            'Expired (Auto-off)',
                            style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        )
                      else if (isScheduled)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.withOpacity(0.3)),
                          ),
                          child: Text(
                            'Scheduled (${promo['startDate']})',
                            style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        )
                      else if (isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.withOpacity(0.3)),
                          ),
                          child: const Text(
                            'Live on App & Web',
                            style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deletePromo(id)),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: promo['title'],
              onChanged: (val) => promo['title'] = val,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s]'))],
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: promo['description'],
              onChanged: (val) => promo['description'] = val,
              maxLines: 2,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s]'))],
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: promo['code'] ?? '',
                    onChanged: (val) => promo['code'] = val.toUpperCase().trim(),
                    decoration: const InputDecoration(labelText: 'Promo Code (e.g. SUMMER20)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: promo['badge'] ?? '',
                    onChanged: (val) => promo['badge'] = val,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9%]')), LengthLimitingTextInputFormatter(4)],
                    decoration: const InputDecoration(labelText: 'Badge (e.g. 50% OFF)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: 'percentage',
                    decoration: const InputDecoration(labelText: 'Discount Type'),
                    items: const [
                      DropdownMenuItem(value: 'percentage', child: Text('Percentage (%) Only')),
                    ],
                    onChanged: null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: (promo['discountValue'] ?? 10).toString(),
                    keyboardType: TextInputType.number,
                    onChanged: (val) {
                      promo['discountType'] = 'percentage';
                      promo['discountValue'] = double.tryParse(val) ?? 0;
                    },
                    decoration: const InputDecoration(labelText: 'Discount (%)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Automated Date-Driven Event', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              subtitle: const Text('Auto-apply discount during active dates without promo code', style: TextStyle(fontSize: 11)),
              value: promo['isEvent'] == true,
              onChanged: (val) => setState(() => promo['isEvent'] = val),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Applicable Room Types', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: ['ALL', ..._availableRoomCategories].map((cat) {
                List rooms = promo['applicableRooms'] is List ? List.from(promo['applicableRooms']) : ['ALL'];
                final isSelected = rooms.contains(cat);
                return FilterChip(
                  label: Text(cat == 'ALL' ? 'All Rooms' : cat, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : null)),
                  selected: isSelected,
                  selectedColor: AppTheme.primaryAccent,
                  onSelected: (selected) {
                    setState(() {
                      if (cat == 'ALL') {
                        promo['applicableRooms'] = ['ALL'];
                      } else {
                        rooms.remove('ALL');
                        if (selected) {
                          rooms.add(cat);
                        } else {
                          rooms.remove(cat);
                        }
                        if (rooms.isEmpty) rooms = ['ALL'];
                        promo['applicableRooms'] = rooms;
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: promo['startDate'],
                    onChanged: (val) => promo['startDate'] = val,
                    decoration: const InputDecoration(labelText: 'Start Date (Auto-activate)'),
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
          ],
        ),
      ),
    );
  }
}
