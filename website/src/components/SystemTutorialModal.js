import React, { useState, useEffect } from 'react';
import { 
  Compass, 
  MapPin, 
  Calendar, 
  CreditCard, 
  MessageSquare, 
  Percent, 
  Sparkles, 
  ChevronRight, 
  ChevronLeft, 
  CheckCircle2, 
  X,
  Target
} from 'lucide-react';

const TUTORIAL_STEPS = [
  {
    targetId: 'tourist-tab-partners',
    tabName: 'Partners',
    title: '1. View & Discover Properties',
    badge: 'Partners (1/6)',
    description: 'Explore our accredited partner resorts, private villas, and hot springs across Laguna. Tap any resort to view transparent rates, room amenities, and available dates.',
    icon: MapPin,
    accent: '#FB3640',
    highlight: 'Explore accredited resorts, review verified photos, and start booking.'
  },
  {
    targetId: 'tourist-tab-favorites',
    tabName: 'Favorites',
    title: '2. Save Your Favorite Spots',
    badge: 'Favorites (2/6)',
    description: 'Heart any resort or room that catches your eye! Access them anytime right here in your Favorites tab for quick comparison and easy future reservations.',
    icon: Compass,
    accent: '#EC4899',
    highlight: 'Bookmark your dream getaways and access them in one tap.'
  },
  {
    targetId: 'tourist-tab-chat',
    tabName: 'Chat',
    title: '3. Direct Messaging & Concierge',
    badge: 'Chat (3/6)',
    description: 'Chat in real time directly with resort owners for special requests, check-in questions, or pool inquiries. Our 24/7 AI Concierge is also available to help.',
    icon: MessageSquare,
    accent: '#8B5CF6',
    highlight: 'Message resort owners directly and get instant answers.'
  },
  {
    targetId: 'tourist-tab-my-bookings',
    tabName: 'My Bookings',
    title: '4. My Bookings & QR Passes',
    badge: 'My Bookings (4/6)',
    description: 'Track your pending, confirmed, and past stays. Access your official digital QR pass for fast contactless check-in, request reschedules, or download official receipts.',
    icon: Calendar,
    accent: '#3B82F6',
    highlight: 'Show your digital QR check-in pass at the front desk when you arrive.'
  },
  {
    targetId: 'tourist-tab-my-expenses',
    tabName: 'My Expenses',
    title: '5. Bill Splitter & Group Expenses',
    badge: 'Smart Tools (5/6)',
    description: 'Heading out with friends or family? Split room rates, food, and activity costs evenly or by item. Generate itemized breakdowns and scan QR receipts seamlessly.',
    icon: CreditCard,
    accent: '#10B981',
    highlight: 'Keep group travel budgets fair, transparent, and hassle-free.'
  },
  {
    targetId: 'tourist-tab-my-coupons',
    tabName: 'My Coupons',
    title: '6. Exclusive Promos & Discounts',
    badge: 'Save More (6/6)',
    description: 'Unlock exclusive seasonal discounts, flash vouchers, and your WELCOME10 coupon code to save instantly on your upcoming resort reservations.',
    icon: Percent,
    accent: '#F59E0B',
    highlight: 'Copy discount codes and apply them at checkout to save money.'
  }
];

const SystemTutorialModal = ({ isOpen, onClose, onComplete }) => {
  const [currentStep, setCurrentStep] = useState(0);
  const [targetRect, setTargetRect] = useState(null);

  const totalSteps = TUTORIAL_STEPS.length;
  const step = TUTORIAL_STEPS[currentStep];
  const StepIcon = step.icon;
  const isLast = currentStep === totalSteps - 1;

  // Measure and track highlighted button position
  useEffect(() => {
    if (!isOpen) return;

    const updateTargetPosition = () => {
      const el = document.getElementById(step.targetId);
      if (el) {
        // Bring tab smoothly into horizontal view if needed
        el.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' });
        const rect = el.getBoundingClientRect();
        setTargetRect({
          top: rect.top,
          left: rect.left,
          width: rect.width,
          height: rect.height,
          bottom: rect.bottom,
          right: rect.right
        });
      } else {
        setTargetRect(null);
      }
    };

    updateTargetPosition();
    const timer = setTimeout(updateTargetPosition, 80);
    window.addEventListener('resize', updateTargetPosition);
    window.addEventListener('scroll', updateTargetPosition, true);

    return () => {
      clearTimeout(timer);
      window.removeEventListener('resize', updateTargetPosition);
      window.removeEventListener('scroll', updateTargetPosition, true);
    };
  }, [isOpen, currentStep, step.targetId]);

  if (!isOpen) return null;

  const handleNext = () => {
    if (isLast) {
      if (onComplete) onComplete();
      else if (onClose) onClose();
    } else {
      setCurrentStep(prev => prev + 1);
    }
  };

  const handlePrev = () => {
    if (currentStep > 0) {
      setCurrentStep(prev => prev - 1);
    }
  };

  const handleSkip = () => {
    if (onComplete) onComplete();
    else if (onClose) onClose();
  };

  const padding = 8;
  const highlightBox = targetRect ? {
    top: Math.max(0, targetRect.top - padding),
    left: Math.max(0, targetRect.left - padding),
    width: targetRect.width + padding * 2,
    height: targetRect.height + padding * 2,
    borderRadius: '34px'
  } : null;

  return (
    <div 
      className="tutorial-spotlight-wrapper"
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 99999,
        overflow: 'hidden',
        pointerEvents: 'auto'
      }}
    >
      {/* ── SPOTLIGHT CUTOUT / DARKENED BACKDROP ── */}
      {highlightBox ? (
        <>
          {/* Spotlight hole using SVG mask for crisp edges */}
          <svg
            style={{
              position: 'fixed',
              inset: 0,
              width: '100vw',
              height: '100vh',
              pointerEvents: 'none',
              zIndex: 1
            }}
          >
            <defs>
              <mask id="tutorial-spotlight-mask">
                <rect width="100%" height="100%" fill="white" />
                <rect 
                  x={highlightBox.left} 
                  y={highlightBox.top} 
                  width={highlightBox.width} 
                  height={highlightBox.height} 
                  rx={22} 
                  ry={22} 
                  fill="black" 
                />
              </mask>
            </defs>
            <rect 
              width="100%" 
              height="100%" 
              fill="rgba(10, 15, 29, 0.82)" 
              mask="url(#tutorial-spotlight-mask)" 
            />
          </svg>

          {/* Animated Pulsing Spotlight Ring around the highlighted button */}
          <div
            style={{
              position: 'fixed',
              top: highlightBox.top,
              left: highlightBox.left,
              width: highlightBox.width,
              height: highlightBox.height,
              borderRadius: highlightBox.borderRadius,
              border: `3px solid ${step.accent}`,
              boxShadow: `0 0 0 4px rgba(255, 255, 255, 0.4), 0 0 25px ${step.accent}`,
              pointerEvents: 'none',
              zIndex: 2,
              transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
              animation: 'spotlightPulse 2s infinite ease-in-out'
            }}
          />

          {/* Floating Pointer Indicator */}
          <div
            style={{
              position: 'fixed',
              top: Math.min(window.innerHeight - 30, highlightBox.top + highlightBox.height + 6),
              left: Math.max(16, highlightBox.left + highlightBox.width / 2 - 50),
              background: step.accent,
              color: 'white',
              padding: '4px 12px',
              borderRadius: '20px',
              fontSize: '11px',
              fontWeight: 800,
              display: 'flex',
              alignItems: 'center',
              gap: '5px',
              boxShadow: '0 4px 12px rgba(0,0,0,0.3)',
              zIndex: 3,
              pointerEvents: 'none',
              transition: 'all 0.3s ease'
            }}
          >
            <Target size={12} /> {step.tabName}
          </div>
        </>
      ) : (
        <div 
          style={{
            position: 'fixed',
            inset: 0,
            backgroundColor: 'rgba(10, 15, 29, 0.82)',
            zIndex: 1
          }} 
        />
      )}

      {/* ── COMPACT, RESPONSIVE EXPLANATION CARD ── */}
      <div 
        style={{
          position: 'fixed',
          inset: 0,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: highlightBox && highlightBox.top < 180 ? 'flex-end' : 'center',
          padding: '16px',
          paddingBottom: highlightBox && highlightBox.top < 180 ? '36px' : '16px',
          zIndex: 10,
          pointerEvents: 'none'
        }}
      >
        <div 
          className="card tutorial-modal-card" 
          style={{ 
            maxWidth: '460px', 
            width: '100%',
            padding: '24px 24px 20px', 
            borderRadius: '24px',
            boxShadow: '0 25px 60px rgba(0,0,0,0.45)',
            border: `1.5px solid ${step.accent}55`,
            background: 'var(--surface)',
            position: 'relative',
            overflow: 'hidden',
            pointerEvents: 'auto',
            transition: 'all 0.3s ease'
          }} 
          onClick={e => e.stopPropagation()}
        >
          {/* Decorative Top Accent Glow */}
          <div 
            style={{
              position: 'absolute',
              top: 0,
              left: '15%',
              right: '15%',
              height: '4px',
              background: `linear-gradient(90deg, transparent, ${step.accent}, transparent)`,
              borderRadius: '0 0 10px 10px'
            }}
          />

          {/* Header Bar with Step Badge & Close */}
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '16px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <span style={{ 
                background: `${step.accent}18`, 
                color: step.accent, 
                fontWeight: 800, 
                fontSize: '11.5px', 
                padding: '4px 12px', 
                borderRadius: '20px',
                letterSpacing: '0.4px',
                border: `1px solid ${step.accent}30`
              }}>
                STEP {currentStep + 1} OF {totalSteps} ({currentStep + 1}/{totalSteps})
              </span>
              <span style={{
                background: 'var(--light-bg)',
                color: 'var(--text-muted)',
                fontSize: '11px',
                fontWeight: 700,
                padding: '4px 10px',
                borderRadius: '12px'
              }}>
                {step.badge}
              </span>
            </div>

            <button 
              onClick={handleSkip}
              style={{ 
                background: 'var(--light-bg)', 
                border: 'none', 
                color: 'var(--text-muted)', 
                width: '30px', 
                height: '30px', 
                borderRadius: '50%',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                cursor: 'pointer',
                transition: 'var(--transition)'
              }}
              title="Skip Tutorial"
            >
              <X size={15} />
            </button>
          </div>

          {/* Content Row: Icon Avatar + Title & Description (Space Efficient) */}
          <div style={{ display: 'flex', gap: '16px', alignItems: 'flex-start', marginBottom: '16px' }}>
            <div 
              style={{ 
                width: '54px', 
                height: '54px', 
                borderRadius: '18px', 
                background: `${step.accent}18`, 
                border: `2px solid ${step.accent}40`,
                display: 'flex', 
                alignItems: 'center', 
                justifyContent: 'center', 
                color: step.accent,
                boxShadow: `0 8px 20px ${step.accent}25`,
                flexShrink: 0
              }}
            >
              <StepIcon size={28} />
            </div>

            <div style={{ flex: 1, minWidth: 0 }}>
              <h2 style={{ margin: '0 0 6px 0', fontSize: '18px', fontWeight: 900, color: 'var(--text-main)', letterSpacing: '-0.3px', lineHeight: '1.25' }}>
                {step.title}
              </h2>
              <p style={{ margin: 0, fontSize: '13px', color: 'var(--text-muted)', lineHeight: '1.5' }}>
                {step.description}
              </p>
            </div>
          </div>

          {/* Highlight Callout Box */}
          <div style={{
            background: 'var(--light-bg)',
            border: '1px dashed var(--border)',
            borderRadius: '12px',
            padding: '8px 14px',
            fontSize: '12.5px',
            color: 'var(--text-main)',
            fontWeight: 600,
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            marginBottom: '18px'
          }}>
            <Sparkles size={15} color={step.accent} style={{ flexShrink: 0 }} />
            <span>{step.highlight}</span>
          </div>

          {/* Step Progress Indicators (Dots) */}
          <div style={{ display: 'flex', justifyContent: 'center', gap: '6px', marginBottom: '18px' }}>
            {TUTORIAL_STEPS.map((_, idx) => (
              <button
                key={idx}
                onClick={() => setCurrentStep(idx)}
                style={{
                  width: idx === currentStep ? '24px' : '7px',
                  height: '7px',
                  borderRadius: '4px',
                  background: idx === currentStep ? step.accent : 'var(--border)',
                  border: 'none',
                  cursor: 'pointer',
                  padding: 0,
                  transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)'
                }}
                aria-label={`Go to step ${idx + 1}`}
              />
            ))}
          </div>

          {/* Footer Actions */}
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '10px' }}>
            {currentStep > 0 ? (
              <button 
                className="btn" 
                onClick={handlePrev}
                style={{ 
                  background: 'var(--light-bg)', 
                  color: 'var(--text-main)', 
                  border: '1px solid var(--border)',
                  padding: '10px 16px',
                  borderRadius: '12px',
                  fontWeight: 700,
                  fontSize: '13px',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '5px'
                }}
              >
                <ChevronLeft size={15} /> Back
              </button>
            ) : (
              <button 
                className="btn" 
                onClick={handleSkip}
                style={{ 
                  background: 'transparent', 
                  color: 'var(--text-muted)', 
                  border: 'none',
                  padding: '10px 12px',
                  fontWeight: 600,
                  fontSize: '13px'
                }}
              >
                Skip Tour
              </button>
            )}

            <button 
              className="btn btn-primary" 
              onClick={handleNext}
              style={{ 
                flex: 1, 
                padding: '11px 20px', 
                borderRadius: '14px', 
                fontWeight: 800, 
                fontSize: '14px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '8px',
                background: step.accent,
                borderColor: step.accent,
                boxShadow: `0 6px 18px ${step.accent}40`
              }}
            >
              {isLast ? (
                <>
                  <CheckCircle2 size={16} /> Got it, Let's Explore!
                </>
              ) : (
                <>
                  Next ({currentStep + 1}/{totalSteps}) <ChevronRight size={16} />
                </>
              )}
            </button>
          </div>
        </div>
      </div>

      {/* Global CSS Animation for Spotlight Ring & Compact Responsiveness */}
      <style>{`
        @keyframes spotlightPulse {
          0%, 100% {
            transform: scale(1);
            opacity: 1;
          }
          50% {
            transform: scale(1.02);
            opacity: 0.85;
          }
        }

        @media (max-width: 520px) {
          .tutorial-modal-card {
            padding: 16px 14px 14px !important;
            border-radius: 18px !important;
            max-width: 95% !important;
          }
          .tutorial-modal-card h2 {
            font-size: 15px !important;
          }
          .tutorial-modal-card p {
            font-size: 11.5px !important;
            line-height: 1.4 !important;
          }
        }
      `}</style>
    </div>
  );
};

export default SystemTutorialModal;
