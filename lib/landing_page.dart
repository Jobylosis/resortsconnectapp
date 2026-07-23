import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'theme_provider.dart';
import 'theme.dart';
import 'login_page.dart';
import 'register_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  int _heroIdx = 0;
  Timer? _timer;
  Map? _cmsData;
  List<Map> _properties = [];
  List<Map> _recentReviews = [];
  bool _isLoading = true;
  int _currentSectionIndex = 0;
  final List<GlobalKey> _sectionKeys = List.generate(6, (index) => GlobalKey());
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, String>> _heroImages = [
    {'src': 'assets/CasaDelRio5.webp', 'title': 'Casa DelRio'},
    {'src': 'assets/HotelRamiro5.webp', 'title': 'Hotel Ramiro'},
    {'src': 'assets/NadzvilleResort1.jpg', 'title': 'Nadzville Resort'},
  ];

  @override
  void initState() {
    super.initState();
    _startTimer();
    _fetchData();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    int activeIndex = 0;
    for (int i = 0; i < _sectionKeys.length; i++) {
      final key = _sectionKeys[i];
      if (key.currentContext != null) {
        final box = key.currentContext!.findRenderObject() as RenderBox;
        final offset = box.localToGlobal(Offset.zero, ancestor: context.findRenderObject());
        if (offset.dy <= MediaQuery.of(context).size.height / 2) {
          activeIndex = i;
        }
      }
    }
    if (_currentSectionIndex != activeIndex) {
      setState(() => _currentSectionIndex = activeIndex);
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        setState(() {
          int maxImages = _heroImages.length;
          if (_cmsData != null) {
            if (_cmsData!['heroImageUrls'] != null && (_cmsData!['heroImageUrls'] as List).isNotEmpty) {
              maxImages = (_cmsData!['heroImageUrls'] as List).length;
            } else if (_cmsData!['heroImageUrl'] != null && _cmsData!['heroImageUrl'].toString().isNotEmpty) {
              maxImages = _heroImages.length + 1;
            }
          }
          _heroIdx = (_heroIdx + 1) % maxImages;
        });
      }
    });
  }

  void _fetchData() {
    FirebaseDatabase.instance.ref('cms/homepage').onValue.listen((event) {
      if (mounted && event.snapshot.exists) {
        setState(() => _cmsData = event.snapshot.value as Map);
      }
    });

    FirebaseDatabase.instance.ref('properties').onValue.listen((event) {
      if (mounted && event.snapshot.exists) {
        final data = event.snapshot.value as Map;
        List<Map> props = [];
        data.forEach((key, value) {
          if (value['name'] != null) {
            props.add({'id': key, ...value});
          }
        });
        // Sort similar to website
        final priorityNames = ['Hotel Ramiro', 'Nadzville Resort', 'Casa DelRio'];
        props.sort((a, b) {
          final aIndex = priorityNames.indexOf(a['name']);
          final bIndex = priorityNames.indexOf(b['name']);
          if (aIndex > -1 && bIndex > -1) return aIndex.compareTo(bIndex);
          if (aIndex > -1) return -1;
          if (bIndex > -1) return 1;
          return 0;
        });
        setState(() {
          _properties = props.take(6).toList();
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    });

    FirebaseDatabase.instance.ref('reviews').onValue.listen((event) {
      if (mounted && event.snapshot.exists) {
        final data = event.snapshot.value as Map;
        List<Map> reviews = [];
        data.forEach((resortId, userReviews) {
          (userReviews as Map).forEach((userId, revData) {
            reviews.add(revData as Map);
          });
        });
        reviews.sort((a, b) => (b['createdAt'] ?? 0).compareTo(a['createdAt'] ?? 0));
        setState(() {
          _recentReviews = reviews.take(3).toList();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _navigateTo(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

  void _handleTourNext() {
    int nextIndex = _currentSectionIndex + 1;
    if (nextIndex >= _sectionKeys.length) {
      nextIndex = 0;
    }
    
    if (nextIndex == 0) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
      return;
    }

    final key = _sectionKeys[nextIndex];
    if (key.currentContext != null) {
      final box = key.currentContext!.findRenderObject() as RenderBox;
      final offset = box.localToGlobal(Offset.zero, ancestor: context.findRenderObject());
      final targetScroll = _scrollController.offset + offset.dy - 80.0;
      
      _scrollController.animateTo(
        targetScroll,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.themeMode == ThemeMode.dark;
    
    // Combine CMS hero image with defaults if available
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
    }

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          _buildSliverAppBar(isDark, themeProvider),
          SliverToBoxAdapter(
            child: Column(
              children: [
                Container(key: _sectionKeys[0], child: _buildHeroSection(currentHeroImages)),
                Container(
                  key: _sectionKeys[1],
                  child: Column(
                    children: [
                      _buildPromotionsSection(),
                      _buildAboutSection(),
                      _buildStatsBar(),
                    ],
                  ),
                ),
                Container(
                  key: _sectionKeys[2], 
                  child: Column(
                    children: [
                      _buildFeaturedResorts(),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 32),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final key = _sectionKeys[3];
                            if (key.currentContext != null) {
                              final box = key.currentContext!.findRenderObject() as RenderBox;
                              final offset = box.localToGlobal(Offset.zero, ancestor: context.findRenderObject());
                              _scrollController.animateTo(_scrollController.offset + offset.dy - 80.0, duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic);
                            }
                          },
                          icon: const Icon(Icons.arrow_downward, size: 18),
                          label: const Text('Next: Why Choose Us', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                        ),
                      ),
                    ]
                  )
                ),
                Container(
                  key: _sectionKeys[3], 
                  child: Column(
                    children: [
                      _buildFeaturesSection(),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 32),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final key = _sectionKeys[4];
                            if (key.currentContext != null) {
                              final box = key.currentContext!.findRenderObject() as RenderBox;
                              final offset = box.localToGlobal(Offset.zero, ancestor: context.findRenderObject());
                              _scrollController.animateTo(_scrollController.offset + offset.dy - 80.0, duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic);
                            }
                          },
                          icon: const Icon(Icons.arrow_downward, size: 18),
                          label: const Text('Next: Real Reviews', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                        ),
                      ),
                    ]
                  )
                ),
                Container(
                  key: _sectionKeys[4], 
                  child: Column(
                    children: [
                      _buildReviewsSection(),
                      if (_recentReviews.isNotEmpty) Padding(
                        padding: const EdgeInsets.only(bottom: 32),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final key = _sectionKeys[5];
                            if (key.currentContext != null) {
                              final box = key.currentContext!.findRenderObject() as RenderBox;
                              final offset = box.localToGlobal(Offset.zero, ancestor: context.findRenderObject());
                              _scrollController.animateTo(_scrollController.offset + offset.dy - 80.0, duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic);
                            }
                          },
                          icon: const Icon(Icons.arrow_downward, size: 18),
                          label: const Text('Next: Book Now', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                        ),
                      ),
                    ]
                  )
                ),
                Container(
                  key: _sectionKeys[5],
                  child: Column(
                    children: [
                      _buildCtaSection(),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 32, top: 16),
                        child: ElevatedButton.icon(
                          onPressed: () => _scrollController.animateTo(0, duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic),
                          icon: const Icon(Icons.vertical_align_top, size: 18),
                          label: const Text('Back to Top', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30), side: BorderSide(color: (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary).withOpacity(0.5)))),
                        ),
                      ),
                      _buildFooter(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(bool isDark, ThemeProvider themeProvider) {
    return SliverAppBar(
      pinned: true,
      floating: false,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      elevation: 1,
      titleSpacing: 16,
      title: Row(
        children: [
          Image.asset('assets/ResortConnectLogo.png', height: 40),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Resort Connect', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
              const Text('DISCOVER & BOOK', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent)),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, color: isDark ? Colors.grey[400] : Colors.grey[600]),
          onPressed: () => themeProvider.toggleTheme(),
        ),
        TextButton(
          onPressed: () => _navigateTo(const LoginPage()),
          child: Text('Sign In', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16.0, left: 8.0, top: 10, bottom: 10),
          child: ElevatedButton(
            onPressed: () => _navigateTo(const RegisterPage()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Get Started', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroSection(List<Map<String, String>> images) {
    final hero = images.isNotEmpty ? images[_heroIdx % images.length] : null;
    
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hero != null)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 1500),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: SizedBox(
                key: ValueKey<String>(hero['src']!),
                width: double.infinity,
                height: double.infinity,
                child: hero.containsKey('isNetwork') 
                  ? Image.network(hero['src']!, fit: BoxFit.cover)
                  : Image.asset(hero['src']!, fit: BoxFit.cover),
              ),
            ),
              
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.4),
                  Colors.black.withOpacity(0.3),
                  Colors.black.withOpacity(0.8),
                ],
              ),
            ),
          ),
          
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent.withOpacity(0.15),
                      border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.bolt, color: AppTheme.primaryAccent, size: 16),
                        SizedBox(width: 8),
                        Text('Instant Booking Available', style: TextStyle(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _cmsData?['heroTitle'] ?? 'Your Perfect Resort\nAwaits You',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _cmsData?['heroSubtitle'] ?? 'Discover and book verified partner resorts with ease. Real-time availability, instant confirmation.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          final key = _sectionKeys[1];
                          if (key.currentContext != null) {
                            final box = key.currentContext!.findRenderObject() as RenderBox;
                            final offset = box.localToGlobal(Offset.zero, ancestor: context.findRenderObject());
                            final targetScroll = _scrollController.offset + offset.dy - 80.0;
                            _scrollController.animateTo(targetScroll, duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.arrow_downward, size: 18),
                            SizedBox(width: 8),
                            Text('Start Tour', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () => _navigateTo(const LoginPage()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.15),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          side: BorderSide(color: Colors.white.withOpacity(0.3)),
                        ),
                        child: const Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
          
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(images.length, (index) {
                return Container(
                  width: _heroIdx == index ? 24 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: _heroIdx == index ? AppTheme.primaryAccent : Colors.white.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPromotionsSection() {
    if (_cmsData == null || _cmsData!['promotions'] == null) return const SizedBox.shrink();
    
    Map promos = _cmsData!['promotions'] as Map;
    List activePromos = promos.values.where((p) => p['active'] == true).toList();
    
    if (activePromos.isEmpty) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: activePromos.map((promo) {
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primaryAccent.withOpacity(0.1), Colors.transparent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (promo['imageUrl'] != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(promo['imageUrl'], width: 80, height: 80, fit: BoxFit.cover),
                  ),
                if (promo['imageUrl'] != null) const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryAccent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('SPECIAL PROMO', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 8),
                      Text(promo['title'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(promo['description'] ?? '', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAboutSection() {
    if (_cmsData == null || (_cmsData!['aboutTitle'] == null && _cmsData!['aboutText'] == null)) {
      return const SizedBox.shrink();
    }
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.secondaryAccent.withOpacity(0.15),
            AppTheme.primaryAccent.withOpacity(0.08)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 60),
      child: Column(
        children: [
          Text(
            _cmsData!['aboutTitle'] ?? 'About Us',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),
          Text(
            _cmsData!['aboutText'] ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[600], height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    final isDark = Provider.of<ThemeProvider>(context).themeMode == ThemeMode.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.secondaryAccent,
            Color(0xFF009378)
          ],
        ),
        boxShadow: [
          BoxShadow(color: AppTheme.secondaryAccent.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))
        ]
      ),
      padding: const EdgeInsets.only(top: 50, bottom: 40, left: 16, right: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem('3', 'Partner Resorts', isDark),
              _buildStatItem('100%', 'Verified Listings', isDark),
              _buildStatItem('0', 'Hidden Fees', isDark),
            ],
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: () {
              final key = _sectionKeys[2];
              if (key.currentContext != null) {
                final box = key.currentContext!.findRenderObject() as RenderBox;
                final offset = box.localToGlobal(Offset.zero, ancestor: context.findRenderObject());
                _scrollController.animateTo(_scrollController.offset + offset.dy - 80.0, duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic);
              }
            },
            icon: const Icon(Icons.arrow_downward, size: 18),
            label: const Text('Next: Featured Resorts', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF009378),
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label, bool isDark) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white)),
        const SizedBox(height: 4),
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFE0FBF5), letterSpacing: 1.2)),
      ],
    );
  }

  Widget _buildFeaturedResorts() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.secondaryAccent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.explore, color: AppTheme.secondaryAccent, size: 16),
                SizedBox(width: 8),
                Text('FEATURED DESTINATIONS', style: TextStyle(color: AppTheme.secondaryAccent, fontWeight: FontWeight.bold, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Explore Our Partner Resorts', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('Hand-picked, verified resorts ready for your next getaway', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.grey[600])),
          const SizedBox(height: 32),
          
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_properties.isEmpty)
            const Text('No properties available at the moment.')
          else
            Column(
              children: _properties.map((prop) => _buildPropertyCard(prop)).toList(),
            ),
            
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () => _navigateTo(const RegisterPage()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('Create Account to Book', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPropertyCard(Map prop) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isDark = themeProvider.themeMode == ThemeMode.dark;
    
    List images = [];
    if (prop['imageUrls'] != null) {
      if (prop['imageUrls'] is List) {
        images = prop['imageUrls'];
      } else if (prop['imageUrls'] is Map) {
        images = (prop['imageUrls'] as Map).values.toList();
      }
    }
    String mainImage = images.isNotEmpty ? images.first : 'https://via.placeholder.com/400x300';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Image.network(mainImage, height: 200, width: double.infinity, fit: BoxFit.cover),
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '${prop['rating'] ?? 5.0}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              if (prop['type'] != null)
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      prop['type'],
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(prop['name'] ?? 'Property Name', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.grey[500], size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${prop['address'] ?? 'General Luna'}${prop['city'] != null ? ', ${prop['city']}' : ''}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  prop['description'] ?? '',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14, height: 1.4),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _navigateTo(const LoginPage()),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppTheme.primaryAccent.withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Sign in to View & Book', style: TextStyle(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildFeaturesSection() {
    final isDark = Provider.of<ThemeProvider>(context).themeMode == ThemeMode.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark ? [AppTheme.darkSurface, AppTheme.darkBg] : [const Color(0xFFF4F7F6), const Color(0xFFE8F0FE)]
        )
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 80),
      child: Column(
        children: [
          const Text('Why Choose Resort Connect?', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Text('Everything you need for a seamless resort experience', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey[600])),
          const SizedBox(height: 48),
          _buildFeatureCard(Icons.verified_user, 'Verified Partners', 'Every resort is personally verified by our team for quality and safety.', AppTheme.secondaryAccent),
          const SizedBox(height: 24),
          _buildFeatureCard(Icons.map, 'Interactive Maps', 'Find resorts on a live map and get directions with one tap.', AppTheme.primaryAccent),
          const SizedBox(height: 24),
          _buildFeatureCard(Icons.people, 'Bill Splitting', 'Easily split the bill with friends directly from your booking.', const Color(0xFF7C3AED)),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(IconData icon, String title, String desc, Color iconColor) {
    final isDark = Provider.of<ThemeProvider>(context).themeMode == ThemeMode.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 30, offset: const Offset(0, 10))
        ]
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: iconColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: iconColor.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))
              ]
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(desc, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600], fontSize: 14, height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildReviewsSection() {
    if (_recentReviews.isEmpty) return const SizedBox.shrink();
    final isDark = Provider.of<ThemeProvider>(context).themeMode == ThemeMode.dark;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 80),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.15),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.star, color: Colors.amber, size: 16),
                SizedBox(width: 8),
                Text('WHAT OUR GUESTS SAY', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Real Reviews from Real Guests', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 48),
          Column(
            children: _recentReviews.map((rev) => Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: isDark ? null : Border.all(color: Colors.grey.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: List.generate(5, (index) => Icon(
                      index < (rev['rating'] ?? 5) ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 16,
                    )),
                  ),
                  const SizedBox(height: 16),
                  Text('"${rev['comment'] ?? ''}"', style: const TextStyle(fontSize: 15, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.grey[800],
                        radius: 16,
                        child: const Icon(Icons.person, size: 16, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Text(rev['userName'] ?? 'Guest', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                ],
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCtaSection() {
    final isDark = Provider.of<ThemeProvider>(context).themeMode == ThemeMode.dark;
    return Container(
      width: double.infinity,
      color: isDark ? AppTheme.darkSurface : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 80),
      child: Column(
        children: [
          Text('Ready to Book Your Stay?', textAlign: TextAlign.center, style: TextStyle(color: isDark ? Colors.white : isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary, fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Text('Join thousands of travelers who trust Resort Connect.', textAlign: TextAlign.center, style: TextStyle(color: isDark ? Colors.white.withOpacity(0.8) : isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary, fontSize: 16)),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () => _navigateTo(const RegisterPage()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Create Free Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => _navigateTo(const LoginPage()),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppTheme.primaryAccent.withOpacity(0.3)),
              foregroundColor: AppTheme.primaryAccent,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFooter() {
    final isDark = Provider.of<ThemeProvider>(context).themeMode == ThemeMode.dark;
    
    final contact = _cmsData != null && _cmsData!['contact'] is Map ? _cmsData!['contact'] : null;
    final String? email = contact != null ? contact['email'] : null;
    final String? phone = contact != null ? contact['phone'] : null;
    final String? facebook = contact != null ? contact['facebook'] : null;

    return Container(
      color: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/ResortConnectLogo.png', height: 40),
              const SizedBox(width: 12),
              Text('Resort Connect', style: TextStyle(color: isDark ? Colors.white : isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'The easiest way to discover, book, and manage your resort experiences. Built for tourists and resort owners.',
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 32),
          if (email != null && email.isNotEmpty || phone != null && phone.isNotEmpty || facebook != null && facebook.isNotEmpty) ...[
            Text('Contact Us', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            if (email != null && email.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.email, size: 16, color: AppTheme.primaryAccent),
                    const SizedBox(width: 8),
                    Text(email, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 14)),
                  ],
                ),
              ),
            if (phone != null && phone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.phone, size: 16, color: AppTheme.primaryAccent),
                    const SizedBox(width: 8),
                    Text(phone, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 14)),
                  ],
                ),
              ),
            if (facebook != null && facebook.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.facebook, size: 16, color: AppTheme.primaryAccent),
                    const SizedBox(width: 8),
                    Text('Facebook', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 14)),
                  ],
                ),
              ),
            const SizedBox(height: 24),
          ],
          Divider(color: isDark ? const Color(0xFF1E293B) : Colors.grey[300]),
          const SizedBox(height: 24),
          Text(
            '© ${DateTime.now().year} Resort Connect. All rights reserved.',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        ],
      ),
    );
  }
}
