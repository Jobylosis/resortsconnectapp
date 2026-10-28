import 'package:flutter/material.dart';

class TutorialStep {
  final String title;
  final String titleTl;
  final String badge;
  final String description;
  final String descriptionTl;
  final IconData icon;
  final Color accent;
  final String highlight;
  final String highlightTl;
  final int tabIndex;

  const TutorialStep({
    required this.title,
    required this.titleTl,
    required this.badge,
    required this.description,
    required this.descriptionTl,
    required this.icon,
    required this.accent,
    required this.highlight,
    required this.highlightTl,
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
      titleTl: '1. Tuklasin ang Partner Resorts',
      badge: 'Partners (1/6)',
      description: 'Browse verified resorts with real photos, live room pricing, amenities, pet policies, and accurate turn-by-turn directions.',
      descriptionTl: 'Mag-browse ng mga beripikadong resort na may totoong litrato, presyo ng kwarto, amenities, pet policy, at direksyon.',
      icon: Icons.location_on_rounded,
      accent: Color(0xFFFB3640), // Red / Coral Red
      highlight: 'Tap any resort card to view rooms, interactive routes, and book.',
      highlightTl: 'I-tap ang kahit aling resort card para makita ang mga kwarto, ruta, at mag-book.',
      tabIndex: 0,
    ),
    TutorialStep(
      title: '2. Save Favorite Resorts',
      titleTl: '2. I-save ang Paboritong Resorts',
      badge: 'Favorites (2/6)',
      description: 'Bookmark your top resorts and rooms to quickly compare amenities, prices, and availability whenever you plan your next getaway.',
      descriptionTl: 'I-bookmark ang mga napupusuang resort at kwarto para madaling mapaghambing ang amenities at presyo sa susunod na bakasyon.',
      icon: Icons.favorite_rounded,
      accent: Color(0xFFEC4899), // Pink
      highlight: 'Saved resorts are kept organized here for one-tap booking.',
      highlightTl: 'Naka-organisa rito ang iyong mga paboritong resort para sa mabilisang pag-book.',
      tabIndex: 1,
    ),
    TutorialStep(
      title: '3. Direct Chat & AI Concierge',
      titleTl: '3. Direktang Chat at AI Concierge',
      badge: 'Chat (3/6)',
      description: 'Chat in real time directly with resort owners for special requests or ask our 24/7 AI Concierge bot for instant answers regarding policies.',
      descriptionTl: 'Makausap nang live ang resort owners para sa mga espesyal na kahilingan, o magtanong sa aming 24/7 AI Concierge tungkol sa mga patakaran.',
      icon: Icons.chat_bubble_rounded,
      accent: Color(0xFF8B5CF6), // Purple
      highlight: 'Real-time messaging keeps you and the resort owners on the same page.',
      highlightTl: 'Mabilisang pagmemensahe upang laging konektado ang bisita at ang may-ari ng resort.',
      tabIndex: 2,
    ),
    TutorialStep(
      title: '4. Manage Bookings & QR Passes',
      titleTl: '4. Pamahalaan ang Bookings at QR Pass',
      badge: 'My Bookings (4/6)',
      description: 'Track all your pending, confirmed, and past stays. Access your official digital QR pass for fast, contactless check-in upon arrival.',
      descriptionTl: 'Subaybayan ang iyong pending, kumpirmado, at nakaraang bakasyon. Gamitin ang iyong opisyal na digital QR pass para sa mabilis na check-in pagdating.',
      icon: Icons.calendar_month_rounded,
      accent: Color(0xFF3B82F6), // Blue
      highlight: 'Show your digital QR check-in pass at the front desk when you arrive.',
      highlightTl: 'Ipakita ang iyong digital QR check-in pass sa front desk pagdating mo sa resort.',
      tabIndex: 3,
    ),
    TutorialStep(
      title: '5. Bill Splitter & Easy Expenses',
      titleTl: '5. Bill Splitter at Pagsubaybay sa Gastusin',
      badge: 'Smart Tools (5/6)',
      description: 'Traveling with friends or family? Use our built-in Bill Splitter to divide room and activity costs evenly or by item with direct GCash links.',
      descriptionTl: 'May kasamang barkada o pamilya? Gamitin ang Bill Splitter upang madaling hatiin ang bayarin sa kwarto at aktibidad gamit ang GCash.',
      icon: Icons.call_split_rounded,
      accent: Color(0xFF10B981), // Green
      highlight: 'Track every peso in My Expenses and keep finances organized.',
      highlightTl: 'Subaybayan ang bawat piso sa My Expenses upang manatiling maayos ang badyet.',
      tabIndex: 4,
    ),
    TutorialStep(
      title: '6. Exclusive Promos & Discounts',
      titleTl: '6. Eksklusibong Promos at Diskwento',
      badge: 'Discounts (6/6)',
      description: 'Check out the My Coupons tab for special event discounts, flash deals, and your exclusive WELCOME10 voucher for 10% off your next booking!',
      descriptionTl: 'Tingnan ang My Coupons tab para sa mga seasonal na diskwento, flash deals, at ang iyong WELCOME10 voucher para sa 10% diskwento sa susunod na booking!',
      icon: Icons.local_offer_rounded,
      accent: Color(0xFFF59E0B), // Yellow
      highlight: 'Copy promo codes directly to apply savings at checkout.',
      highlightTl: 'Kopyahin ang promo code at ilagay sa checkout para makatipid agad.',
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

            // Main layout in SafeArea: Top bar + Center dialog card + Fixed Bottom Navigation Bar
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 8),

                  // Pill Banner
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                        const Icon(Icons.touch_app_rounded, color: Colors.white, size: 15),
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

                  const SizedBox(height: 10),

                  // Spotlight Tab Bar with pulsing circle/capsule ring around the highlighted tab
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xF00D1527),
                        borderRadius: BorderRadius.circular(24),
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
                                final glowSpread = 1.5 + (_pulseController.value * 3.5);
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: tabColor.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: tabColor, width: 2.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: tabColor.withValues(alpha: 0.65),
                                        blurRadius: 10 + (_pulseController.value * 6),
                                        spreadRadius: glowSpread,
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          color: tabColor,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: tabColor,
                                              blurRadius: 5,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        label,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12,
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
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              alignment: Alignment.center,
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Center Content Area: Scrollable PageView inside Card
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          constraints: const BoxConstraints(
                            maxWidth: 390,
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
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              // Top Header Row with Steps & Close/Skip Button
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: step.accent.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: step.accent.withValues(alpha: 0.35)),
                                    ),
                                    child: Text(
                                      'STEP ${_currentIndex + 1} OF $totalSteps (${_currentIndex + 1}/$totalSteps)',
                                      style: TextStyle(
                                        fontSize: 10.5,
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
                                        fontSize: 10.5,
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
                                      child: Icon(Icons.close_rounded, size: 15, color: Colors.grey[600]),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 6),

                              // PageView Content: Takes available space inside Card and scrolls if long
                              Expanded(
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

                                          // English Title
                                          Text(
                                            s.title,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -0.2,
                                            ),
                                          ),
                                          // Tagalog Title
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              s.titleTl,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                                              ),
                                            ),
                                          ),

                                          const SizedBox(height: 8),

                                          // English Description
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                            child: Text(
                                              s.description,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isDark ? Colors.white : Colors.black87,
                                                height: 1.35,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          // Tagalog Description
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                                            child: Text(
                                              s.descriptionTl,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                                                height: 1.3,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),

                                          const SizedBox(height: 8),

                                          // Bilingual Highlight Box
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: s.accent.withValues(alpha: 0.08),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: s.accent.withValues(alpha: 0.25)),
                                            ),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Icon(Icons.auto_awesome_rounded, color: s.accent, size: 14),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.center,
                                                    children: [
                                                      Text(
                                                        s.highlight,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w600,
                                                          color: isDark ? Colors.white70 : Colors.black87,
                                                        ),
                                                        textAlign: TextAlign.center,
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        s.highlightTl,
                                                        style: TextStyle(
                                                          fontSize: 10.5,
                                                          fontWeight: FontWeight.w500,
                                                          fontStyle: FontStyle.italic,
                                                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                                                        ),
                                                        textAlign: TextAlign.center,
                                                      ),
                                                    ],
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
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Fixed Bottom Navigation Bar: Shared by all pages, guaranteed 100% visible
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 400),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.1),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Left: Back button (or Skip when on page 1)
                          Flexible(
                            flex: 4,
                            child: SizedBox(
                              height: 48,
                              child: _currentIndex > 0
                                  ? OutlinedButton.icon(
                                      onPressed: _goToPrev,
                                      icon: const Icon(Icons.arrow_back_rounded, size: 15),
                                      label: const FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          'Back / Bumalik',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                      ),
                                    )
                                  : TextButton(
                                      onPressed: _skip,
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                      ),
                                      child: const FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          'Skip / Laktawan',
                                          style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(width: 4),

                          // Center: Step indicator dots
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(totalSteps, (idx) {
                              final active = idx == _currentIndex;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 240),
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                width: active ? 16 : 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: active
                                      ? step.accent
                                      : (isDark ? Colors.grey[700] : Colors.grey[300]),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              );
                            }),
                          ),

                          const SizedBox(width: 4),

                          // Right: Next / Done button (at least 48px touch target height)
                          Flexible(
                            flex: 5,
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: _goToNext,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: step.accent,
                                  foregroundColor: Colors.white,
                                  elevation: 2,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: Icon(
                                  isLast ? Icons.check_circle_rounded : Icons.arrow_forward_rounded,
                                  size: 16,
                                ),
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    isLast ? "Done / Tapos na" : "Next / Susunod",
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
