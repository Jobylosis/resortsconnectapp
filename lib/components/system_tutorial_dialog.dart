import 'package:flutter/material.dart';
import '../theme.dart';

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

class _SystemTutorialDialogState extends State<SystemTutorialDialog> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  final List<TutorialStep> _steps = const [
    TutorialStep(
      title: '1. Discover Partner Resorts',
      badge: 'Partners (1/6)',
      description: 'Browse verified resorts with real photos, live room pricing, amenities, pet policies, and accurate turn-by-turn directions.',
      icon: Icons.location_on_rounded,
      accent: AppTheme.primaryAccent,
      highlight: 'Tap any resort card to view rooms, interactive routes, and book.',
      tabIndex: 0,
    ),
    TutorialStep(
      title: '2. Save Favorite Resorts',
      badge: 'Favorites (2/6)',
      description: 'Bookmark your top resorts and rooms to quickly compare amenities, prices, and availability whenever you plan your next getaway.',
      icon: Icons.favorite_rounded,
      accent: Color(0xFFEC4899),
      highlight: 'Saved resorts are kept organized here for one-tap booking.',
      tabIndex: 1,
    ),
    TutorialStep(
      title: '3. Direct Chat & AI Concierge',
      badge: 'Chat (3/6)',
      description: 'Chat in real time directly with resort owners for special requests or ask our 24/7 AI Concierge bot for instant answers regarding policies.',
      icon: Icons.chat_bubble_rounded,
      accent: Color(0xFF8B5CF6),
      highlight: 'Real-time messaging keeps you and the resort owners on the same page.',
      tabIndex: 2,
    ),
    TutorialStep(
      title: '4. Manage Bookings & QR Passes',
      badge: 'My Bookings (4/6)',
      description: 'Track all your pending, confirmed, and past stays. Access your official digital QR pass for fast, contactless check-in upon arrival.',
      icon: Icons.calendar_month_rounded,
      accent: Color(0xFF3B82F6),
      highlight: 'Show your digital QR check-in pass at the front desk when you arrive.',
      tabIndex: 3,
    ),
    TutorialStep(
      title: '5. Bill Splitter & Easy Expenses',
      badge: 'Smart Tools (5/6)',
      description: 'Traveling with friends or family? Use our built-in Bill Splitter to divide room and activity costs evenly or by item with direct GCash links.',
      icon: Icons.call_split_rounded,
      accent: Color(0xFF10B981),
      highlight: 'Track every peso in My Expenses and keep finances organized.',
      tabIndex: 4,
    ),
    TutorialStep(
      title: '6. Exclusive Promos & Discounts',
      badge: 'Save More (6/6)',
      description: 'Check out the My Coupons tab for special event discounts, flash deals, and your exclusive WELCOME10 voucher for 10% off your next booking!',
      icon: Icons.local_offer_rounded,
      accent: Color(0xFFF59E0B),
      highlight: 'Copy promo codes directly to apply savings at checkout.',
      tabIndex: 5,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _syncTab(0);
  }

  void _syncTab(int index) {
    if (widget.tabController != null && index >= 0 && index < _steps.length) {
      widget.tabController!.animateTo(_steps[index].tabIndex);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToNext() {
    if (_currentIndex < _steps.length - 1) {
      final nextIdx = _currentIndex + 1;
      _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
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
        duration: const Duration(milliseconds: 280),
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

    return PopScope(
      canPop: false,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Darkened backdrop (85% opacity with touch to dismiss/skip)
            Positioned.fill(
              child: GestureDetector(
                onTap: _skip,
                child: Container(
                  color: const Color(0xD90A0F1D), // 85% dark navy backdrop
                ),
              ),
            ),

            // Top Spotlight Pointer Banner highlighting the active tab
            Positioned(
              top: mediaQuery.padding.top + 36,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: step.accent,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: step.accent.withValues(alpha: 0.45),
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
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Responsive and space-efficient dialog card anchored comfortably
            Align(
              alignment: Alignment.center,
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: step.accent.withValues(alpha: 0.4), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 35,
                          offset: const Offset(0, 15),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header bar with badge and close
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: step.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: step.accent.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            'STEP ${_currentIndex + 1} OF $totalSteps (${_currentIndex + 1}/$totalSteps)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: step.accent,
                              letterSpacing: 0.4,
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
                    const SizedBox(height: 14),

                    // PageView Content with generous height and scroll protection
                    SizedBox(
                      height: 290,
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
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(height: 4),
                                // Icon container
                                Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    color: s.accent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: s.accent.withValues(alpha: 0.4), width: 1.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: s.accent.withValues(alpha: 0.2),
                                        blurRadius: 15,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Icon(s.icon, color: s.accent, size: 28),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  s.title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  child: Text(
                                    s.description,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: s.accent.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: s.accent.withValues(alpha: 0.25)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.auto_awesome_rounded, color: s.accent, size: 14),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          s.highlight,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? Colors.white70 : Colors.black87,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Step indicator dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(totalSteps, (idx) {
                        final active = idx == _currentIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
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

                    const SizedBox(height: 16),

                    // Action buttons
                    Row(
                      children: [
                        if (_currentIndex > 0)
                          OutlinedButton.icon(
                            onPressed: _goToPrev,
                            icon: const Icon(Icons.arrow_back_rounded, size: 15),
                            label: const Text('Back'),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                          )
                        else
                          TextButton(
                            onPressed: _skip,
                            child: const Text('Skip Tour', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _goToNext,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: step.accent,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              padding: const EdgeInsets.symmetric(vertical: 12),
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
