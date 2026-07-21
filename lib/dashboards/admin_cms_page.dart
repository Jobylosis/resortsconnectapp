import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
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
    'promotions': <String, dynamic>{},
  };

  final _formKey = GlobalKey<FormState>();

  final _heroTitleCtrl = TextEditingController();
  final _heroSubCtrl = TextEditingController();
  final _aboutHeadingCtrl = TextEditingController();
  final _aboutTextCtrl = TextEditingController();
  
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _fbCtrl = TextEditingController();
  final _twCtrl = TextEditingController();
  final _igCtrl = TextEditingController();

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
          
          if (data['contact'] is Map) {
            final c = Map<String, dynamic>.from(data['contact']);
            _cmsData['contact'] = {
              'email': c['email'] ?? '',
              'phone': c['phone'] ?? '',
              'address': c['address'] ?? '',
              'facebook': c['facebook'] ?? '',
              'twitter': c['twitter'] ?? '',
              'instagram': c['instagram'] ?? '',
            };
          }

          if (data['promotions'] is Map) {
            final p = Map<String, dynamic>.from(data['promotions']);
            _cmsData['promotions'] = p.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
          }
          
          _heroTitleCtrl.text = _cmsData['heroTitle'];
          _heroSubCtrl.text = _cmsData['heroSubtitle'];
          _aboutHeadingCtrl.text = _cmsData['aboutHeading'];
          _aboutTextCtrl.text = _cmsData['aboutText'];
          
          _emailCtrl.text = _cmsData['contact']['email'];
          _phoneCtrl.text = _cmsData['contact']['phone'];
          _addressCtrl.text = _cmsData['contact']['address'];
          _fbCtrl.text = _cmsData['contact']['facebook'];
          _twCtrl.text = _cmsData['contact']['twitter'];
          _igCtrl.text = _cmsData['contact']['instagram'];
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
    }

    setState(() => _isSaving = true);
    
    _cmsData['heroTitle'] = _heroTitleCtrl.text.trim();
    _cmsData['heroSubtitle'] = _heroSubCtrl.text.trim();
    _cmsData['aboutHeading'] = _aboutHeadingCtrl.text.trim();
    _cmsData['aboutText'] = _aboutTextCtrl.text.trim();
    
    _cmsData['contact']['email'] = _emailCtrl.text.trim();
    _cmsData['contact']['phone'] = _phoneCtrl.text.trim();
    _cmsData['contact']['address'] = _addressCtrl.text.trim();
    _cmsData['contact']['facebook'] = _fbCtrl.text.trim();
    _cmsData['contact']['twitter'] = _twCtrl.text.trim();
    _cmsData['contact']['instagram'] = _igCtrl.text.trim();

    try {
      await FirebaseDatabase.instance.ref('cms/homepage').set(_cmsData);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CMS Content saved successfully!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: \$e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
        'badge': 'NEW',
        'imageUrl': '',
        'startDate': '',
        'endDate': ''
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
            
            _buildSectionHeader(Icons.contact_mail, 'Contact Information'),
            _buildTextField(_emailCtrl, 'Email Address'),
            _buildTextField(_phoneCtrl, 'Phone Number'),
            _buildTextField(_addressCtrl, 'Physical Address', maxLines: 2),
            _buildTextField(_fbCtrl, 'Facebook URL'),
            _buildTextField(_twCtrl, 'Twitter URL'),
            _buildTextField(_igCtrl, 'Instagram URL'),
            const SizedBox(height: 24),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionHeader(Icons.local_offer, 'Promotions'),
                IconButton(icon: const Icon(Icons.add_circle, color: AppTheme.primaryAccent), onPressed: _addPromo),
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

  Widget _buildTextField(TextEditingController controller, String label, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
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
        const Text('Hero Background Images', style: TextStyle(fontWeight: FontWeight.bold)),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Promotion', style: TextStyle(fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deletePromo(id)),
              ],
            ),
            TextFormField(
              initialValue: promo['title'],
              onChanged: (val) => promo['title'] = val,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: promo['description'],
              onChanged: (val) => promo['description'] = val,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 8),
            TextFormField(
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
          ],
        ),
      ),
    );
  }
}
