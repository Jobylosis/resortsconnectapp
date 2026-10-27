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
    title: '1. Discover Partner Resorts',
    titleTl: '1. Tuklasin ang Partner Resorts',
    badge: 'Partners (1/6)',
    description: 'Browse verified resorts with real photos, live room pricing, amenities, pet policies, and accurate turn-by-turn directions.',
    descriptionTl: 'Mag-browse ng mga beripikadong resort na may totoong litrato, presyo ng kwarto, amenities, pet policy, at direksyon.',
    icon: MapPin,
    accent: '#FB3640',
    highlight: 'Tap any resort card to view rooms, interactive routes, and book.',
    highlightTl: 'I-tap ang kahit aling resort card para makita ang mga kwarto, ruta, at mag-book.'
  },
  {
    targetId: 'tourist-tab-favorites',
    tabName: 'Favorites',
    title: '2. Save Favorite Resorts',
    titleTl: '2. I-save ang Paboritong Resorts',
    badge: 'Favorites (2/6)',
    description: 'Bookmark your top resorts and rooms to quickly compare amenities, prices, and availability whenever you plan your next getaway.',
    descriptionTl: 'I-bookmark ang mga napupusuang resort at kwarto para madaling mapaghambing ang amenities at presyo sa susunod na bakasyon.',
    icon: Compass,
    accent: '#EC4899',
    highlight: 'Saved resorts are kept organized here for one-tap booking.',
    highlightTl: 'Naka-organisa rito ang iyong mga paboritong resort para sa mabilisang pag-book.'
  },
  {
    targetId: 'tourist-tab-chat',
    tabName: 'Chat',
    title: '3. Direct Chat & AI Concierge',
    titleTl: '3. Direktang Chat at AI Concierge',
    badge: 'Chat (3/6)',
    description: 'Chat in real time directly with resort owners for special requests or ask our 24/7 AI Concierge bot for instant answers regarding policies.',
    descriptionTl: 'Makausap nang live ang resort owners para sa mga espesyal na kahilingan, o magtanong sa aming 24/7 AI Concierge tungkol sa mga patakaran.',
    icon: MessageSquare,
    accent: '#8B5CF6',
    highlight: 'Real-time messaging keeps you and the resort owners on the same page.',
    highlightTl: 'Mabilisang pagmemensahe upang laging konektado ang bisita at ang may-ari ng resort.'
  },
  {
    targetId: 'tourist-tab-my-bookings',
    tabName: 'My Bookings',
    title: '4. Manage Bookings & QR Passes',
    titleTl: '4. Pamahalaan ang Bookings at QR Pass',
    badge: 'My Bookings (4/6)',
    description: 'Track all your pending, confirmed, and past stays. Access your official digital QR pass for fast, contactless check-in upon arrival.',
    descriptionTl: 'Subaybayan ang iyong pending, kumpirmado, at nakaraang bakasyon. Gamitin ang iyong opisyal na digital QR pass para sa mabilis na check-in pagdating.',
    icon: Calendar,
    accent: '#3B82F6',
    highlight: 'Show your digital QR check-in pass at the front desk when you arrive.',
    highlightTl: 'Ipakita ang iyong digital QR check-in pass sa front desk pagdating mo sa resort.'
  },
  {
    targetId: 'tourist-tab-my-expenses',
    tabName: 'My Expenses',
    title: '5. Bill Splitter & Easy Expenses',
    titleTl: '5. Bill Splitter at Pagsubaybay sa Gastusin',
    badge: 'Smart Tools (5/6)',
    description: 'Traveling with friends or family? Use our built-in Bill Splitter to divide room and activity costs evenly or by item with direct GCash links.',
    descriptionTl: 'May kasamang barkada o pamilya? Gamitin ang Bill Splitter upang madaling hatiin ang bayarin sa kwarto at aktibidad gamit ang GCash.',
    icon: CreditCard,
    accent: '#10B981',
    highlight: 'Track every peso in My Expenses and keep finances organized.',
    highlightTl: 'Subaybayan ang bawat piso sa My Expenses upang manatiling maayos ang badyet.'
  },
  {
    targetId: 'tourist-tab-my-coupons',
    tabName: 'My Coupons',
    title: '6. Exclusive Promos & Discounts',
    titleTl: '6. Eksklusibong Promos at Diskwento',
    badge: 'Discounts (6/6)',
    description: 'Check out the My Coupons tab for special event discounts, flash deals, and your exclusive WELCOME10 voucher for 10% off your next booking!',
    descriptionTl: 'Tingnan ang My Coupons tab para sa mga seasonal na diskwento, flash deals, at ang iyong WELCOME10 voucher para sa 10% diskwento sa susunod na booking!',
    icon: Percent,
    accent: '#F59E0B',
    highlight: 'Copy promo codes directly to apply savings at checkout.',
    highlightTl: 'Kopyahin ang promo code at ilagay sa checkout para makatipid agad.'
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
            maxWidth: '440px', 
            width: '100%',
            maxHeight: 'calc(100vh - 100px)',
            display: 'flex',
            flexDirection: 'column',
            padding: '22px 22px 18px', 
            borderRadius: '22px',
            boxShadow: '0 25px 60px rgba(0,0,0,0.45)',
            border: `1.5px solid ${step.accent}55`,
            background: 'var(--surface)',
            position: 'relative',
            overflowY: 'auto',
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
              <h2 style={{ margin: '0 0 2px 0', fontSize: '17px', fontWeight: 900, color: 'var(--text-main)', letterSpacing: '-0.3px', lineHeight: '1.25' }}>
                {step.title}
              </h2>
              {step.titleTl && (
                <div style={{ margin: '0 0 6px 0', fontSize: '13.5px', fontWeight: 700, color: 'var(--text-muted)', lineHeight: '1.25' }}>
                  {step.titleTl}
                </div>
              )}
              <p style={{ margin: '0 0 4px 0', fontSize: '13px', color: 'var(--text-main)', lineHeight: '1.45' }}>
                {step.description}
              </p>
              {step.descriptionTl && (
                <p style={{ margin: 0, fontSize: '12px', color: 'var(--text-muted)', lineHeight: '1.4', fontStyle: 'italic' }}>
                  {step.descriptionTl}
                </p>
              )}
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
            alignItems: 'flex-start',
            gap: '8px',
            marginBottom: '18px'
          }}>
            <Sparkles size={15} color={step.accent} style={{ flexShrink: 0, marginTop: '2px' }} />
            <div style={{ display: 'flex', flexDirection: 'column', gap: '2px' }}>
              <span>{step.highlight}</span>
              {step.highlightTl && (
                <span style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 500, fontStyle: 'italic' }}>
                  {step.highlightTl}
                </span>
              )}
            </div>
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
                <ChevronLeft size={15} /> Back / Bumalik
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
                Skip / Laktawan
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
                  <CheckCircle2 size={16} /> Done / Tapos na
                </>
              ) : (
                <>
                  Next / Susunod ({currentStep + 1}/{totalSteps}) <ChevronRight size={16} />
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
