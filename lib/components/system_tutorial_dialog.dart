import 'package:flutter/material.dart';
import '../theme.dart';

class TutorialStep {
  final String title;
  final String badge;
  final String description;
  final IconData icon;
  final Color accent;
  final String highlight;

  const TutorialStep({
    required this.title,
    required this.badge,
    required this.description,
    required this.icon,
    required this.accent,
    required this.highlight,
  });
}

class SystemTutorialDialog extends StatefulWidget {
  final VoidCallback onComplete;

  const SystemTutorialDialog({super.key, required this.onComplete});

  @override
  State<SystemTutorialDialog> createState() => _SystemTutorialDialogState();
}

class _SystemTutorialDialogState extends State<SystemTutorialDialog> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  final List<TutorialStep> _steps = const [
    TutorialStep(
      title: 'Welcome to Resort Connect!',
      badge: 'Quick Tour',
      description: 'Discover, explore, and instantly book accredited resorts and private getaways across Laguna and nearby paradises.',
      icon: Icons.explore_rounded,
      accent: AppTheme.primaryAccent,
      highlight: 'Here is your quick guide to get the most out of your stay.',
    ),
    TutorialStep(
      title: '1. Discover Partner Resorts',
      badge: 'Partners Tab',
      description: 'Browse verified resorts with real photos, live room pricing, amenities, pet policies, and accurate turn-by-turn directions.',
      icon: Icons.location_on_rounded,
      accent: Color(0xFF1DD3B0),
      highlight: 'Tap any resort card to view rooms, interactive routes, and book.',
    ),
    TutorialStep(
      title: '2. Manage Bookings & QR Passes',
      badge: 'My Bookings',
      description: 'Track all your pending and confirmed bookings. Access your digital QR pass for fast, contactless check-in upon arrival.',
      icon: Icons.calendar_month_rounded,
      accent: Color(0xFF3B82F6),
      highlight: 'Need to adjust plans? Request a reschedule or view receipts here.',
    ),
    TutorialStep(
      title: '3. Bill Splitter & Easy Expenses',
      badge: 'Smart Tools',
      description: 'Traveling in a group? Use our built-in Bill Splitter to divide room and activity costs evenly or by item with direct GCash links.',
      icon: Icons.call_split_rounded,
      accent: Color(0xFF10B981),
      highlight: 'Track every peso in My Expenses and keep finances organized.',
    ),
    TutorialStep(
      title: '4. Direct Chat & AI Concierge',
      badge: 'Communication',
      description: 'Chat directly with resort owners for special requests or ask our 24/7 AI Concierge bot for instant answers regarding policies and FAQs.',
      icon: Icons.chat_bubble_rounded,
      accent: Color(0xFF8B5CF6),
      highlight: 'Real-time messaging keeps you and the resort owners on the same page.',
    ),
    TutorialStep(
      title: '5. Exclusive Promos & Discounts',
      badge: 'Save More',
      description: 'Check out the My Coupons tab for special event discounts, flash deals, and your exclusive WELCOME10 voucher for 10% off your next booking!',
      icon: Icons.local_offer_rounded,
      accent: Color(0xFFF59E0B),
      highlight: 'Copy promo codes directly to apply savings at checkout.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToNext() {
    if (_currentIndex < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      widget.onComplete();
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _goToPrev() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
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

    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: Theme.of(context).cardColor,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
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
                      color: AppTheme.primaryAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'STEP ${_currentIndex + 1} OF $totalSteps (${_currentIndex + 1}/$totalSteps)',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryAccent,
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
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[800] : Colors.grey[100],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close_rounded, size: 18, color: Colors.grey[600]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // PageView Content
              SizedBox(
                height: 290,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _steps.length,
                  onPageChanged: (idx) => setState(() => _currentIndex = idx),
                  itemBuilder: (context, index) {
                    final s = _steps[index];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Icon circle
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: s.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(color: s.accent.withValues(alpha: 0.4), width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: s.accent.withValues(alpha: 0.2),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Icon(s.icon, color: s.accent, size: 40),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          s.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            s.description,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.grey[300] : Colors.grey[700],
                              height: 1.45,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 14),

              // Step indicator dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(totalSteps, (idx) {
                  final active = idx == _currentIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 24 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: active
                          ? AppTheme.primaryAccent
                          : (isDark ? Colors.grey[700] : Colors.grey[300]),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 20),

              // Action buttons
              Row(
                children: [
                  if (_currentIndex > 0)
                    OutlinedButton.icon(
                      onPressed: _goToPrev,
                      icon: const Icon(Icons.arrow_back_rounded, size: 16),
                      label: const Text('Back'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    )
                  else
                    TextButton(
                      onPressed: _skip,
                      child: const Text('Skip Tour', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _goToNext,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryAccent,
                        foregroundColor: Colors.white,
                        elevation: 3,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: Icon(
                        isLast ? Icons.check_circle_rounded : Icons.arrow_forward_rounded,
                        size: 18,
                      ),
                      label: Text(
                        isLast ? "Got it, Let's Explore!" : "Next (${_currentIndex + 1}/$totalSteps)",
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
