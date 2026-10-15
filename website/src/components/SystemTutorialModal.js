import React, { useState } from 'react';
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
  X 
} from 'lucide-react';

const TUTORIAL_STEPS = [
  {
    title: 'Welcome to Resort Connect!',
    badge: 'Quick Tour',
    description: 'Discover, explore, and instantly book the best accredited resorts and private getaways across Laguna and beyond.',
    icon: Compass,
    accent: '#FB3640',
    highlight: 'Here is your quick guide to get the most out of your stay.'
  },
  {
    title: '1. Discover Partner Resorts',
    badge: 'Partners Tab',
    description: 'Browse verified resorts with real photos, live room pricing, amenities, pet policies, and accurate turn-by-turn directions.',
    icon: MapPin,
    accent: '#1DD3B0',
    highlight: 'Tap any resort card to view rooms, interactive map routes, and book your stay.'
  },
  {
    title: '2. Manage Bookings & QR Passes',
    badge: 'My Bookings',
    description: 'Track all your pending, confirmed, and past stays. Access your official digital QR pass for fast, contactless check-in upon arrival.',
    icon: Calendar,
    accent: '#3B82F6',
    highlight: 'Need to adjust plans? Request a reschedule or view complete payment receipts here.'
  },
  {
    title: '3. Bill Splitter & Easy Expenses',
    badge: 'Smart Tools',
    description: 'Traveling with friends or family? Use our built-in Bill Splitter to divide room and activity costs evenly or by item with direct GCash links.',
    icon: CreditCard,
    accent: '#10B981',
    highlight: 'Track every peso in My Expenses and keep your group finances organized.'
  },
  {
    title: '4. Direct Chat & AI Concierge',
    badge: 'Communication',
    description: 'Chat directly with resort owners for special requests or ask our 24/7 AI Concierge bot for instant answers regarding policies, timings, and FAQs.',
    icon: MessageSquare,
    accent: '#8B5CF6',
    highlight: 'Real-time messaging keeps you and the resort owners on the same page.'
  },
  {
    title: '5. Exclusive Promos & Discounts',
    badge: 'Save More',
    description: 'Check out the My Coupons tab for special event discounts, flash deals, and your exclusive WELCOME10 voucher for 10% off your next booking!',
    icon: Percent,
    accent: '#F59E0B',
    highlight: 'Copy promo codes directly to apply savings at checkout.'
  }
];

const SystemTutorialModal = ({ isOpen, onClose, onComplete }) => {
  const [currentStep, setCurrentStep] = useState(0);

  if (!isOpen) return null;

  const totalSteps = TUTORIAL_STEPS.length;
  const step = TUTORIAL_STEPS[currentStep];
  const StepIcon = step.icon;
  const isLast = currentStep === totalSteps - 1;

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

  return (
    <div 
      className="modal-overlay" 
      style={{ 
        zIndex: 99999, 
        backdropFilter: 'blur(10px)',
        backgroundColor: 'rgba(15, 23, 42, 0.75)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '16px'
      }}
      onClick={handleSkip}
    >
      <div 
        className="card tutorial-modal-card" 
        style={{ 
          maxWidth: '520px', 
          width: '100%',
          padding: '36px 32px 30px', 
          borderRadius: '28px',
          boxShadow: '0 25px 60px rgba(0,0,0,0.3)',
          border: '1.5px solid var(--border)',
          background: 'var(--surface)',
          position: 'relative',
          overflow: 'hidden'
        }} 
        onClick={e => e.stopPropagation()}
      >
        {/* Decorative Top Accent Glow */}
        <div 
          style={{
            position: 'absolute',
            top: 0,
            left: '10%',
            right: '10%',
            height: '4px',
            background: `linear-gradient(90deg, transparent, ${step.accent}, transparent)`,
            borderRadius: '0 0 10px 10px',
            transition: 'background 0.3s ease'
          }}
        />

        {/* Header Bar with Step Badge & Close */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '24px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <span style={{ 
              background: 'rgba(251, 54, 64, 0.1)', 
              color: 'var(--primary)', 
              fontWeight: 800, 
              fontSize: '12px', 
              padding: '5px 12px', 
              borderRadius: '20px',
              letterSpacing: '0.5px'
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
              width: '32px', 
              height: '32px', 
              borderRadius: '50%',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              cursor: 'pointer',
              transition: 'var(--transition)'
            }}
            title="Skip Tutorial"
          >
            <X size={16} />
          </button>
        </div>

        {/* Animated Icon Avatar */}
        <div style={{ textAlign: 'center', marginBottom: '22px' }}>
          <div 
            style={{ 
              width: '84px', 
              height: '84px', 
              borderRadius: '26px', 
              background: `${step.accent}18`, 
              border: `2px solid ${step.accent}40`,
              display: 'flex', 
              alignItems: 'center', 
              justifyContent: 'center', 
              margin: '0 auto', 
              color: step.accent,
              boxShadow: `0 12px 30px ${step.accent}25`,
              transition: 'all 0.3s ease'
            }}
          >
            <StepIcon size={40} />
          </div>
        </div>

        {/* Content Section */}
        <div style={{ textAlign: 'center', marginBottom: '28px' }}>
          <h2 style={{ margin: '0 0 10px 0', fontSize: '22px', fontWeight: 900, color: 'var(--text-main)', letterSpacing: '-0.3px' }}>
            {step.title}
          </h2>
          <p style={{ margin: '0 0 14px 0', fontSize: '14.5px', color: 'var(--text-muted)', lineHeight: '1.6' }}>
            {step.description}
          </p>
          <div style={{
            background: 'var(--light-bg)',
            border: '1px dashed var(--border)',
            borderRadius: '14px',
            padding: '10px 16px',
            fontSize: '13px',
            color: 'var(--text-main)',
            fontWeight: 600,
            display: 'inline-flex',
            alignItems: 'center',
            gap: '8px'
          }}>
            <Sparkles size={16} color={step.accent} style={{ flexShrink: 0 }} />
            <span>{step.highlight}</span>
          </div>
        </div>

        {/* Step Progress Indicators (Dots) */}
        <div style={{ display: 'flex', justifyContent: 'center', gap: '8px', marginBottom: '26px' }}>
          {TUTORIAL_STEPS.map((_, idx) => (
            <button
              key={idx}
              onClick={() => setCurrentStep(idx)}
              style={{
                width: idx === currentStep ? '28px' : '8px',
                height: '8px',
                borderRadius: '4px',
                background: idx === currentStep ? 'var(--primary)' : 'var(--border)',
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
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '12px' }}>
          {currentStep > 0 ? (
            <button 
              className="btn" 
              onClick={handlePrev}
              style={{ 
                background: 'var(--light-bg)', 
                color: 'var(--text-main)', 
                border: '1px solid var(--border)',
                padding: '12px 18px',
                borderRadius: '14px',
                fontWeight: 700,
                fontSize: '14px',
                display: 'flex',
                alignItems: 'center',
                gap: '6px'
              }}
            >
              <ChevronLeft size={16} /> Back
            </button>
          ) : (
            <button 
              className="btn" 
              onClick={handleSkip}
              style={{ 
                background: 'transparent', 
                color: 'var(--text-muted)', 
                border: 'none',
                padding: '12px 16px',
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
              padding: '13px 24px', 
              borderRadius: '16px', 
              fontWeight: 800, 
              fontSize: '15px',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '8px',
              boxShadow: '0 8px 20px rgba(251, 54, 64, 0.3)'
            }}
          >
            {isLast ? (
              <>
                <CheckCircle2 size={18} /> Got it, Let's Explore!
              </>
            ) : (
              <>
                Next ({currentStep + 1}/{totalSteps}) <ChevronRight size={18} />
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
};

export default SystemTutorialModal;
