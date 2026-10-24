import 'package:flutter/material.dart';

class TutorialStep {
  final String title;
  final String badge;
  final String description;
  final IconData icon;
  final Color accent;
  final String highlight;
  final int tabIndex;

  const TutorialStep({
    required this.title,
    required this.badge,
    required this.description,
    required this.icon,
    required this.accent,
    required this.highlight,
    required this.tabIndex,
  });
}

class SystemTutorialDialog extends StatefulWidget {
  final VoidCallback onComplete;
  final TabController? tabController;

  const SystemTutorialDialog({
    super.key, 
    required this.onComplete,
    this.tabController,
  });

  @override
  State<SystemTutorialDialog> createState() => _SystemTutorialDialogState();
}

class _SystemTutorialDialogState extends State<SystemTutorialDialog>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  final ScrollController _tabsScrollController = ScrollController();
  late AnimationController _pulseController;
  int _currentIndex = 0;

  final List<TutorialStep> _steps = const [
    TutorialStep(
      title: '1. Discover Partner Resorts',
      badge: 'Partners (1/6)',
      description: 'Browse verified resorts with real photos, live room pricing, amenities, pet policies, and accurate turn-by-turn directions.',
      icon: Icons.location_on_rounded,
      accent: Color(0xFFFB3640), // Red / Coral Red
      highlight: 'Tap any resort card to view rooms, interactive routes, and book.',
      tabIndex: 0,
    ),
    TutorialStep(
      title: '2. Save Favorite Resorts',
      badge: 'Favorites (2/6)',
      description: 'Bookmark your top resorts and rooms to quickly compare amenities, prices, and availability whenever you plan your next getaway.',
      icon: Icons.favorite_rounded,
      accent: Color(0xFFEC4899), // Pink
      highlight: 'Saved resorts are kept organized here for one-tap booking.',
      tabIndex: 1,
    ),
    TutorialStep(
      title: '3. Direct Chat & AI Concierge',
      badge: 'Chat (3/6)',
      description: 'Chat in real time directly with resort owners for special requests or ask our 24/7 AI Concierge bot for instant answers regarding policies.',
      icon: Icons.chat_bubble_rounded,
      accent: Color(0xFF8B5CF6), // Purple
      highlight: 'Real-time messaging keeps you and the resort owners on the same page.',
      tabIndex: 2,
    ),
    TutorialStep(
      title: '4. Manage Bookings & QR Passes',
      badge: 'My Bookings (4/6)',
      description: 'Track all your pending, confirmed, and past stays. Access your official digital QR pass for fast, contactless check-in upon arrival.',
      icon: Icons.calendar_month_rounded,
      accent: Color(0xFF3B82F6), // Blue
      highlight: 'Show your digital QR check-in pass at the front desk when you arrive.',
      tabIndex: 3,
    ),
    TutorialStep(
      title: '5. Bill Splitter & Easy Expenses',
      badge: 'Smart Tools (5/6)',
      description: 'Traveling with friends or family? Use our built-in Bill Splitter to divide room and activity costs evenly or by item with direct GCash links.',
      icon: Icons.call_split_rounded,
      accent: Color(0xFF10B981), // Green
      highlight: 'Track every peso in My Expenses and keep finances organized.',
      tabIndex: 4,
    ),
    TutorialStep(
      title: '6. Exclusive Promos & Discounts',
      badge: 'Discounts (6/6)',
      description: 'Check out the My Coupons tab for special event discounts, flash deals, and your exclusive WELCOME10 voucher for 10% off your next booking!',
      icon: Icons.local_offer_rounded,
      accent: Color(0xFFF59E0B), // Yellow
      highlight: 'Copy promo codes directly to apply savings at checkout.',
      tabIndex: 5,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _syncTab(0);
  }

  void _syncTab(int index) {
    if (widget.tabController != null && index >= 0 && index < _steps.length) {
      widget.tabController!.animateTo(_steps[index].tabIndex);
    }
    // Auto-scroll the preview tab bar to center the active item if needed
    if (_tabsScrollController.hasClients) {
      final approxOffset = (index * 95.0) - 40.0;
      _tabsScrollController.animateTo(
        approxOffset.clamp(0.0, _tabsScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pageController.dispose();
    _tabsScrollController.dispose();
    super.dispose();
  }

  void _goToNext() {
    if (_currentIndex < _steps.length - 1) {
      final nextIdx = _currentIndex + 1;
      _pageController.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOut,
      );
      _syncTab(nextIdx);
    } else {
      widget.onComplete();
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _goToPrev() {
    if (_currentIndex > 0) {
      final prevIdx = _currentIndex - 1;
      _pageController.previousPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOut,
      );
      _syncTab(prevIdx);
    }
  }

  void _skip() {
    widget.onComplete();
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalSteps = _steps.length;
    final step = _steps[_currentIndex];
    final isLast = _currentIndex == totalSteps - 1;
    final mediaQuery = MediaQuery.of(context);
    final tabLabels = const ['Partners', 'Favorites', 'Chat', 'My Bookings', 'Smart Tools', 'Discounts'];

    return PopScope(
      canPop: false,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Darkened backdrop (dismissible via tap)
            Positioned.fill(
              child: GestureDetector(
                onTap: _skip,
                child: Container(
                  color: const Color(0xE0070B16), // 88% dark navy backdrop
                ),
              ),
            ),

            // Top Spotlight Banner & Interactive Highlighted Tab Bar
            Positioned(
              top: mediaQuery.padding.top + 16,
              left: 12,
              right: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pill Banner
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: step.accent,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: step.accent.withValues(alpha: 0.55),
                          blurRadius: 18,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.touch_app_rounded, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Highlighting Tab: ${step.badge}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Spotlight Tab Bar with pulsing circle/capsule ring around the highlighted tab
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xF00D1527),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListView.separated(
                      controller: _tabsScrollController,
                      scrollDirection: Axis.horizontal,
                      shrinkWrap: true,
                      itemCount: tabLabels.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, idx) {
                        final isHighlighted = idx == _currentIndex;
                        final label = tabLabels[idx];
                        final tabColor = _steps[idx].accent;

                        if (isHighlighted) {
                          return AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              final glowSpread = 2.0 + (_pulseController.value * 4.0);
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: tabColor.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(22),
                                  // Prominent circular / capsule colored ring around active tab
                                  border: Border.all(color: tabColor, width: 2.8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: tabColor.withValues(alpha: 0.7),
                                      blurRadius: 12 + (_pulseController.value * 8),
                                      spreadRadius: glowSpread,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: tabColor,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: tabColor,
                                            blurRadius: 6,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Text(
                                      label,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12.5,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        }

                        return GestureDetector(
                          onTap: () {
                            setState(() => _currentIndex = idx);
                            _pageController.animateToPage(
                              idx,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                            );
                            _syncTab(idx);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            alignment: Alignment.center,
                            child: Text(
                              label,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Dialog Card: Space-efficient, non-scrolling buttons, guaranteed visible Next button
            Align(
              alignment: Alignment.center,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 90, left: 16, right: 16, bottom: 16),
                  child: Container(
                    constraints: const BoxConstraints(
                      maxWidth: 380,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: step.accent.withValues(alpha: 0.5), width: 1.8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 35,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Top Header Row with Steps & Close Button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: step.accent.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: step.accent.withValues(alpha: 0.35)),
                              ),
                              child: Text(
                                'STEP ${_currentIndex + 1} OF $totalSteps (${_currentIndex + 1}/$totalSteps)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: step.accent,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.grey[800] : Colors.grey[200],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                step.badge,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: _skip,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.grey[800] : Colors.grey[100],
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.close_rounded, size: 16, color: Colors.grey[600]),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // PageView Content: Compact height (200px) so it never overflows screen
                        SizedBox(
                          height: 205,
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: _steps.length,
                            onPageChanged: (idx) {
                              setState(() => _currentIndex = idx);
                              _syncTab(idx);
                            },
                            itemBuilder: (context, index) {
                              final s = _steps[index];
                              return SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(height: 2),
                                    // Compact Icon
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: s.accent.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: s.accent.withValues(alpha: 0.4), width: 1.5),
                                        boxShadow: [
                                          BoxShadow(
                                            color: s.accent.withValues(alpha: 0.25),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Icon(s.icon, color: s.accent, size: 24),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      s.title,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text(
                                        s.description,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark ? Colors.grey[300] : Colors.grey[700],
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: s.accent.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: s.accent.withValues(alpha: 0.25)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.auto_awesome_rounded, color: s.accent, size: 13),
                                          const SizedBox(width: 5),
                                          Flexible(
                                            child: Text(
                                              s.highlight,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: isDark ? Colors.white70 : Colors.black87,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Step indicator dots
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(totalSteps, (idx) {
                            final active = idx == _currentIndex;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 240),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: active ? 22 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: active
                                    ? step.accent
                                    : (isDark ? Colors.grey[700] : Colors.grey[300]),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            );
                          }),
                        ),

                        const SizedBox(height: 12),

                        // Pinned Action Buttons: Guaranteed 100% visible on every slide & device
                        Row(
                          children: [
                            if (_currentIndex > 0)
                              OutlinedButton.icon(
                                onPressed: _goToPrev,
                                icon: const Icon(Icons.arrow_back_rounded, size: 14),
                                label: const Text('Back'),
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                ),
                              )
                            else
                              TextButton(
                                onPressed: _skip,
                                child: const Text(
                                  'Skip Tour',
                                  style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _goToNext,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: step.accent,
                                  foregroundColor: Colors.white,
                                  elevation: 2,
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: Icon(
                                  isLast ? Icons.check_circle_rounded : Icons.arrow_forward_rounded,
                                  size: 16,
                                ),
                                label: Text(
                                  isLast ? "Got it, Let's Explore!" : "Next (${_currentIndex + 1}/$totalSteps)",
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
