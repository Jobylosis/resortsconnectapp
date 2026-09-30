import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, onValue, update } from 'firebase/database';
import { Star, MapPin, ArrowRight, ArrowDown, Shield, Compass, Users, ChevronLeft, ChevronRight, Moon, Sun, Zap } from 'lucide-react';
import logo from '../assets/ResortConnectLogo.png';
import TermsAndPolicies from './TermsAndPolicies';

import CasaDelRio1 from '../assets/CasaDelRio1.jpg';
import HotelRamiro1 from '../assets/HotelRamiro1.jpg';
import NadzvilleResort1 from '../assets/NadzvilleResort1.jpg';
import CasaDelRio5 from '../assets/CasaDelRio5.webp';
import HotelRamiro5 from '../assets/HotelRamiro5.webp';

const HERO_IMAGES = [
  { src: CasaDelRio5, title: 'Casa DelRio' },
  { src: HotelRamiro5, title: 'Hotel Ramiro' },
  { src: NadzvilleResort1, title: 'Nadzville Resort' },
];

const SECTION_IDS = [
  'hero-section',
  'tour-stop-1',
  'featured-resorts',
  'features-section',
  'reviews-section',
  'cta-section'
];

const Homepage = ({ onLogin, onRegister, isDarkMode, onToggleDark, onViewPolicies }) => {
  const [properties, setProperties] = useState([]);
  const [heroIdx, setHeroIdx] = useState(0);
  const [loading, setLoading] = useState(true);
  const [showTerms, setShowTerms] = useState(false);
  const [recentReviews, setRecentReviews] = useState([]);
  const [cmsData, setCmsData] = useState(null);
  const [loadingCms, setLoadingCms] = useState(true);
  const [currentSectionIndex, setCurrentSectionIndex] = useState(0);

  const handleTourNext = () => {
    let nextIndex = currentSectionIndex + 1;
    if (nextIndex >= SECTION_IDS.length) {
      nextIndex = 0;
    }
    
    if (nextIndex === 0) {
      window.scrollTo({ top: 0, behavior: 'smooth' });
      return;
    }

    const el = document.getElementById(SECTION_IDS[nextIndex]);
    if (el) {
      const y = el.getBoundingClientRect().top + window.scrollY - 80;
      window.scrollTo({ top: y, behavior: 'smooth' });
    }
  };

  // Sync scroll position with currentSectionIndex
  useEffect(() => {
    const handleScroll = () => {
      let activeIndex = 0;
      for (let i = 0; i < SECTION_IDS.length; i++) {
        const el = document.getElementById(SECTION_IDS[i]);
        if (el) {
          const rect = el.getBoundingClientRect();
          // Offset 100px so it registers the active section a bit early
          if (rect.top <= window.innerHeight / 2) {
            activeIndex = i;
          }
        }
      }
      if (currentSectionIndex !== activeIndex) {
        setCurrentSectionIndex(activeIndex);
      }
    };

    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, [currentSectionIndex]);


  useEffect(() => {
    const propsRef = ref(db, 'properties');
    const fallbackProperties = [
      { id: 'fallback-1', name: 'Hotel Ramiro', description: 'A beautiful hotel located in the heart of the city.', type: 'Hotel' },
      { id: 'fallback-2', name: 'Nadzville Resort', description: 'Experience the ultimate resort life with our premium amenities.', type: 'Resort' },
      { id: 'fallback-3', name: 'Casa DelRio', description: 'Your home away from home with stunning views.', type: 'Resort' }
    ];

    const unsub = onValue(propsRef, (snap) => {
      const data = snap.val();
      let list = [];
      if (data) {
        list = Object.entries(data)
          .map(([id, val]) => ({ id, ...val }))
          .filter(p => p.name);
      }
      
      if (list.length === 0) {
        list = fallbackProperties;
      }

      const priorityNames = ['Hotel Ramiro', 'Nadzville Resort', 'Casa DelRio'];
      list.sort((a, b) => {
        const aIndex = priorityNames.indexOf(a.name);
        const bIndex = priorityNames.indexOf(b.name);
        if (aIndex > -1 && bIndex > -1) return aIndex - bIndex;
        if (aIndex > -1) return -1;
        if (bIndex > -1) return 1;
        return 0;
      });

      setProperties(list.slice(0, 6));
      setLoading(false);
    }, (error) => {
      console.error("Error fetching properties:", error);
      setProperties(fallbackProperties);
      setLoading(false);
    });

    const revRef = ref(db, 'reviews');
    const unsubRevs = onValue(revRef, (snap) => {
      const data = snap.val();
      if (data) {
        let allRevs = [];
        Object.entries(data).forEach(([ownerUid, reviews]) => {
          Object.values(reviews).forEach(r => {
            allRevs.push({ ...r, ownerUid });
          });
        });
        allRevs.sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0));
        setRecentReviews(allRevs.slice(0, 4));
      }
    });

    const cmsRef = ref(db, 'cms/homepage');
    const unsubCms = onValue(cmsRef, (snap) => {
      if (snap.exists()) {
        const val = snap.val() || {};
        if (val.promotions) {
          const today = new Date();
          const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
          const updates = {};
          Object.entries(val.promotions).forEach(([id, promo]) => {
            if (promo && promo.active && promo.endDate) {
              const parts = promo.endDate.split('-');
              if (parts.length === 3) {
                const endTimestamp = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2])).getTime();
                if (todayStart > endTimestamp) {
                  updates[`cms/homepage/promotions/${id}/active`] = false;
                  promo.active = false;
                }
              }
            }
          });
          if (Object.keys(updates).length > 0) {
            update(ref(db), updates).catch(e => console.warn("Could not auto-expire promo in DB:", e));
          }
        }
        setCmsData(val);
      } else {
        setCmsData({});
      }
      setLoadingCms(false);
    });

    return () => { unsub(); unsubRevs(); unsubCms(); };
  }, []);

  const getHeroImages = () => {
    if (loadingCms) return [];
    let urls = [];
    if (cmsData?.heroImageUrls) {
      if (Array.isArray(cmsData.heroImageUrls)) urls = cmsData.heroImageUrls.filter(Boolean);
      else if (typeof cmsData.heroImageUrls === 'object') urls = Object.values(cmsData.heroImageUrls).filter(Boolean);
    }
    if (urls.length > 0) return urls.map(url => ({ src: url, title: cmsData.heroTitle || 'Featured' }));
    if (cmsData?.heroImageUrl) return [{ src: cmsData.heroImageUrl, title: cmsData.heroTitle || 'Featured' }];
    return HERO_IMAGES;
  };
  const activeHeroImages = getHeroImages();

  useEffect(() => {
    if (activeHeroImages.length <= 1) {
      setHeroIdx(0);
      return;
    }
    const timer = setInterval(() => setHeroIdx(i => (i + 1) % activeHeroImages.length), 5000);
    return () => clearInterval(timer);
  }, [activeHeroImages.length]);

  return (
    <div style={{ minHeight: '100vh', background: 'var(--light-bg)', overflowX: 'hidden', width: '100%' }}>
      {/* ── NAV ── */}
      <nav style={{
        position: 'fixed', top: 0, left: 0, right: 0, zIndex: 1000,
        background: 'var(--nav-bg)', backdropFilter: 'blur(20px)',
        borderBottom: '1px solid var(--border)',
        padding: '12px 20px', display: 'flex', justifyContent: 'space-between', alignItems: 'center',
        boxSizing: 'border-box', width: '100%'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <img src={logo} alt="Resort Connect" style={{ height: '48px', width: 'auto' }} />
          <div>
            <div style={{ fontWeight: 900, fontSize: '16px', color: 'var(--nav-title)', letterSpacing: '-0.5px' }}>Resort Connect</div>
            <div style={{ fontSize: '9.5px', fontWeight: 700, color: 'var(--secondary)', textTransform: 'uppercase', letterSpacing: '0.5px' }}>Discover & Book</div>
          </div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          <button onClick={onToggleDark} style={{ background: 'var(--nav-group-bg)', border: 'none', borderRadius: '50%', width: '36px', height: '36px', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', color: 'var(--text-muted)', transition: 'var(--transition)' }}>
            {isDarkMode ? <Sun size={17} /> : <Moon size={17} />}
          </button>
          <button onClick={onLogin} style={{ background: 'var(--nav-group-bg)', border: '1px solid var(--border)', borderRadius: '12px', padding: '8px 14px', fontWeight: 700, fontSize: '13px', cursor: 'pointer', color: 'var(--text-main)', transition: 'var(--transition)' }}
            onMouseOver={e => e.currentTarget.style.background = 'var(--surface)'}
            onMouseOut={e => e.currentTarget.style.background = 'var(--nav-group-bg)'}
          >Sign In</button>
          <button onClick={onRegister} className="btn btn-primary" style={{ padding: '8px 16px', borderRadius: '12px', fontSize: '13px' }}>
            Get Started <ArrowRight size={14} />
          </button>
        </div>
      </nav>

      {/* ── HERO ── */}
      <div id="hero-section" style={{ position: 'relative', height: '100vh', width: '100%', maxWidth: '100%', overflow: 'hidden', boxSizing: 'border-box' }}>
        {activeHeroImages.map((item, i) => (
          <div key={i} style={{
            position: 'absolute', inset: 0,
            backgroundImage: `url(${item.src})`,
            backgroundSize: 'cover', backgroundPosition: 'center',
            opacity: i === heroIdx ? 1 : 0,
            transition: 'opacity 1.2s ease-in-out'
          }}>
            <div style={{ position: 'absolute', bottom: '60px', left: '20px', background: 'rgba(11,19,43,0.75)', padding: '10px 18px', borderRadius: '12px', backdropFilter: 'blur(10px)', color: 'white', fontWeight: 700, fontSize: '14px', display: 'flex', alignItems: 'center', gap: '8px', zIndex: 11, border: '1px solid rgba(255,255,255,0.1)' }}>
              <Compass size={16} color="#0D9488" /> Featured: {item.title}
            </div>
          </div>
        ))}
        <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(to bottom, rgba(11,19,43,0.65) 0%, rgba(11,19,43,0.45) 50%, rgba(11,19,43,0.85) 100%)', zIndex: 1 }} />

        <div style={{ position: 'relative', zIndex: 10, height: '100%', display: 'flex', flexDirection: 'column', justifyContent: 'center', alignItems: 'center', textAlign: 'center', padding: '0 20px', boxSizing: 'border-box' }}>
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: '8px', background: 'rgba(13,148,136,0.2)', border: '1px solid rgba(13,148,136,0.4)', backdropFilter: 'blur(8px)', borderRadius: '50px', padding: '8px 20px', marginBottom: '24px' }}>
            <Zap size={14} color="#14B8A6" />
            <span style={{ fontSize: '13px', fontWeight: 700, color: '#14B8A6', letterSpacing: '0.5px' }}>Instant Booking Available</span>
          </div>
          <h1 style={{ color: 'white', fontSize: 'clamp(32px, 6vw, 68px)', fontWeight: 900, margin: '0 0 18px 0', lineHeight: 1.15, letterSpacing: '-1.5px', maxWidth: '850px' }}>
            {cmsData?.heroTitle || (
              <>Your Perfect Resort<br /><span style={{ color: '#14B8A6' }}>Awaits You</span></>
            )}
          </h1>
          <p style={{ color: 'rgba(255,255,255,0.88)', fontSize: 'clamp(14px, 2vw, 19px)', fontWeight: 500, maxWidth: '560px', lineHeight: 1.6, marginBottom: '36px' }}>
            {cmsData?.heroSubtitle || 'Discover and book verified partner resorts with ease. Real-time availability, instant confirmation.'}
          </p>
          <div style={{ display: 'flex', gap: '14px', flexWrap: 'wrap', justifyContent: 'center' }}>
            <button 
              onClick={() => {
                const el = document.getElementById('tour-stop-1');
                if (el) {
                  const y = el.getBoundingClientRect().top + window.scrollY - 80;
                  window.scrollTo({ top: y, behavior: 'smooth' });
                }
              }} 
              className="btn btn-secondary" 
              style={{ height: '52px', padding: '0 32px', fontSize: '15px', borderRadius: '16px' }}
            >
              <ArrowDown size={18} /> Start Tour
            </button>
            <button onClick={onLogin} style={{ height: '52px', padding: '0 32px', fontSize: '15px', borderRadius: '16px', background: 'rgba(255,255,255,0.12)', border: '1px solid rgba(255,255,255,0.25)', backdropFilter: 'blur(8px)', color: 'white', fontWeight: 700, cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '10px', transition: 'var(--transition)' }}
              onMouseOver={e => e.currentTarget.style.background = 'rgba(255,255,255,0.2)'}
              onMouseOut={e => e.currentTarget.style.background = 'rgba(255,255,255,0.12)'}
            >
              Sign In <ArrowRight size={17} />
            </button>
          </div>
        </div>

        {/* Dot navigation */}
        <div style={{ position: 'absolute', bottom: '28px', left: '50%', transform: 'translateX(-50%)', display: 'flex', gap: '10px', zIndex: 10 }}>
          {activeHeroImages.length > 1 && activeHeroImages.map((_, i) => (
            <button key={i} onClick={() => setHeroIdx(i)} style={{ width: i === heroIdx ? '24px' : '8px', height: '8px', borderRadius: '4px', background: i === heroIdx ? '#0D9488' : 'rgba(255,255,255,0.4)', border: 'none', cursor: 'pointer', transition: 'all 0.3s ease', padding: 0 }} />
          ))}
        </div>
      </div>

      {/* ── TOUR STOP 1: PROMO / ABOUT / STATS ── */}
      <div id="tour-stop-1"></div>

      {/* ── PROMOTIONS SECTION ── */}
      {cmsData?.promotions && Object.values(cmsData.promotions).filter(p => {
        if (!p.active) return false;
        if (!p.endDate) return true;
        const parts = p.endDate.split('-');
        if (parts.length === 3) {
          const endTs = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2])).getTime();
          const today = new Date();
          const todayTs = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
          return todayTs <= endTs;
        }
        return true;
      }).length > 0 && (
        <div id="promo-section" style={{ padding: '40px 20px', maxWidth: '1120px', margin: '0 auto', width: '100%', boxSizing: 'border-box' }}>
          <div style={{ maxWidth: '1000px', margin: '0 auto' }}>
            {Object.values(cmsData.promotions).filter(p => {
              if (!p.active) return false;
              if (!p.endDate) return true;
              const parts = p.endDate.split('-');
              if (parts.length === 3) {
                const endTs = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2])).getTime();
                const today = new Date();
                const todayTs = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
                return todayTs <= endTs;
              }
              return true;
            }).map((promo, i) => (
              <div key={i} style={{ display: 'flex', gap: '20px', alignItems: 'center', background: isDarkMode ? 'var(--surface)' : 'white', borderRadius: '24px', border: '1px solid var(--border)', padding: '24px', marginBottom: '20px', flexWrap: 'wrap', boxShadow: 'var(--shadow)' }}>
                {promo.imageUrl && (
                  <div style={{ width: '200px', height: '120px', borderRadius: '16px', overflow: 'hidden', flexShrink: 0 }}>
                    <img src={promo.imageUrl} alt={promo.title} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                  </div>
                )}
                <div style={{ flex: 1 }}>
                  <div style={{ display: 'inline-block', background: 'var(--secondary)', color: 'white', padding: '4px 10px', borderRadius: '8px', fontSize: '11px', fontWeight: 800, textTransform: 'uppercase', marginBottom: '8px' }}>Special Promo</div>
                  <h3 style={{ margin: '0 0 8px 0', fontSize: '22px', fontWeight: 900, color: 'var(--text-main)' }}>{promo.title}</h3>
                  <p style={{ margin: 0, color: 'var(--text-muted)' }}>{promo.description}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* ── ABOUT SECTION (CMS) ── */}
      {(cmsData?.aboutTitle || cmsData?.aboutText) && (
        <div id="about-section" style={{ background: isDarkMode ? 'var(--dark-surface)' : '#F1F5F9', padding: '70px 20px', textAlign: 'center', borderTop: '1px solid var(--border)', width: '100%', boxSizing: 'border-box' }}>
          <div style={{ maxWidth: '800px', margin: '0 auto', background: 'var(--surface)', padding: '48px 32px', borderRadius: '32px', boxShadow: 'var(--shadow)', border: '1px solid var(--border)', position: 'relative', overflow: 'hidden' }}>
            <div style={{ position: 'absolute', top: 0, left: 0, width: '100%', height: '6px', background: 'linear-gradient(90deg, var(--primary) 0%, var(--secondary) 100%)' }} />
            <h2 style={{ fontSize: 'clamp(26px, 4vw, 40px)', fontWeight: 900, margin: '0 0 18px 0', color: 'var(--text-main)' }}>
              {cmsData.aboutTitle}
            </h2>
            <p style={{ color: 'var(--text-muted)', fontSize: '16px', lineHeight: 1.8 }}>
              {cmsData.aboutText}
            </p>
          </div>
        </div>
      )}

      {/* ── STATS BAR ── */}
      <div id="stats-section" style={{ background: 'linear-gradient(135deg, #1B365D 0%, #0D9488 100%)', padding: '50px 20px 45px', position: 'relative', boxShadow: '0 10px 30px rgba(27, 54, 93, 0.2)', width: '100%', boxSizing: 'border-box' }}>
        <div style={{ maxWidth: '900px', margin: '0 auto', display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '20px', textAlign: 'center', marginBottom: '32px' }}>
          {[['3', 'Partner Resorts'], ['100%', 'Verified Listings'], ['0', 'Hidden Fees']].map(([val, label]) => (
            <div key={label}>
              <div style={{ fontSize: '42px', fontWeight: 900, color: 'white', letterSpacing: '-1px', textShadow: '0 2px 10px rgba(0,0,0,0.15)' }}>{val}</div>
              <div style={{ fontSize: '13px', fontWeight: 800, color: 'rgba(255,255,255,0.9)', textTransform: 'uppercase', letterSpacing: '1px' }}>{label}</div>
            </div>
          ))}
        </div>
        
        <div style={{ textAlign: 'center' }}>
          <button 
            onClick={() => {
              const el = document.getElementById('featured-resorts');
              if (el) window.scrollTo({ top: el.getBoundingClientRect().top + window.scrollY - 80, behavior: 'smooth' });
            }} 
            className="btn btn-secondary" 
            style={{ padding: '12px 28px', borderRadius: '50px', fontSize: '15px', background: 'white', color: '#1B365D', boxShadow: '0 4px 14px rgba(0,0,0,0.1)' }}
          >
            Next: Featured Resorts <ArrowDown size={16} />
          </button>
        </div>
      </div>

      {/* ── FEATURED RESORTS ── */}
      <div id="featured-resorts" style={{ maxWidth: '1120px', margin: '0 auto', padding: '70px 20px', width: '100%', boxSizing: 'border-box' }}>
        <div style={{ textAlign: 'center', marginBottom: '48px' }}>
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: '8px', background: 'var(--secondary-soft)', borderRadius: '50px', padding: '8px 20px', marginBottom: '16px' }}>
            <Compass size={14} color="var(--secondary)" />
            <span style={{ fontSize: '12px', fontWeight: 800, color: 'var(--secondary)', textTransform: 'uppercase', letterSpacing: '1px' }}>Featured Destinations</span>
          </div>
          <h2 style={{ fontSize: 'clamp(28px, 4vw, 44px)', fontWeight: 900, margin: '0 0 14px 0', letterSpacing: '-1px', color: 'var(--text-main)' }}>Explore Our Partner Resorts</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '16px', maxWidth: '500px', margin: '0 auto' }}>Hand-picked, verified resorts ready for your next getaway</p>
        </div>

        {loading ? (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '24px' }}>
            {[1,2,3].map(i => <div key={i} className="shimmer" style={{ height: '360px', borderRadius: '20px' }} />)}
          </div>
        ) : (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '24px' }}>
            {properties.map((prop, idx) => <PublicPropertyCard key={prop.id} prop={prop} onCta={() => onViewPolicies(prop)} isDarkMode={isDarkMode} index={idx} />)}
          </div>
        )}

        <div style={{ textAlign: 'center', marginTop: '48px', display: 'flex', gap: '16px', justifyContent: 'center', flexWrap: 'wrap' }}>
          <button onClick={onRegister} className="btn btn-primary" style={{ height: '52px', padding: '0 36px', fontSize: '15px', borderRadius: '16px' }}>
            Create Account to Book <ArrowRight size={17} />
          </button>
          <button 
            onClick={() => {
              const el = document.getElementById('features-section');
              if (el) window.scrollTo({ top: el.getBoundingClientRect().top + window.scrollY - 80, behavior: 'smooth' });
            }} 
            className="btn btn-secondary" 
            style={{ height: '52px', padding: '0 36px', fontSize: '15px', borderRadius: '16px' }}
          >
            Next: Why Choose Us <ArrowDown size={17} />
          </button>
        </div>
      </div>

      {/* ── FEATURES ── */}
      <div id="features-section" style={{ background: isDarkMode ? 'var(--dark-surface)' : '#F8FAFC', padding: '70px 20px', borderTop: '1px solid var(--border)', width: '100%', boxSizing: 'border-box' }}>
        <div style={{ maxWidth: '1000px', margin: '0 auto' }}>
          <div style={{ textAlign: 'center', marginBottom: '48px' }}>
            <h2 style={{ fontSize: 'clamp(26px, 4vw, 40px)', fontWeight: 900, margin: '0 0 12px 0', letterSpacing: '-1px', color: 'var(--text-main)' }}>Why Choose Resort Connect?</h2>
            <p style={{ color: 'var(--text-muted)', fontSize: '16px' }}>Everything you need for a seamless resort experience</p>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))', gap: '24px' }}>
            {[
              { icon: <Shield size={28} color="white" />, bg: 'var(--primary)', title: 'Verified Partners', desc: 'Every resort is personally verified by our team for quality and safety.' },
              { icon: <Compass size={28} color="white" />, bg: 'var(--secondary)', title: 'Interactive Maps', desc: 'Find resorts on a live map and get directions with one tap.' },
              { icon: <Users size={28} color="white" />, bg: '#1E3A8A', title: 'Bill Splitting', desc: 'Easily split the bill with friends directly from your booking.' },
            ].map(f => (
              <div key={f.title} className="card" style={{ padding: '32px 24px', textAlign: 'center', background: 'var(--surface)', border: '1px solid var(--border)', boxShadow: 'var(--shadow)' }}>
                <div style={{ width: '60px', height: '60px', borderRadius: '18px', background: f.bg, display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 20px', boxShadow: `0 8px 20px rgba(27,54,93,0.2)` }}>{f.icon}</div>
                <h3 style={{ fontWeight: 800, fontSize: '18px', margin: '0 0 10px 0', color: 'var(--text-main)' }}>{f.title}</h3>
                <p style={{ color: 'var(--text-muted)', fontSize: '14px', lineHeight: '1.6', margin: 0 }}>{f.desc}</p>
              </div>
            ))}
          </div>
          <div style={{ textAlign: 'center', marginTop: '44px' }}>
            <button 
              onClick={() => {
                const el = document.getElementById('reviews-section');
                if (el) window.scrollTo({ top: el.getBoundingClientRect().top + window.scrollY - 80, behavior: 'smooth' });
              }} 
              className="btn btn-secondary" 
              style={{ padding: '12px 28px', borderRadius: '50px', fontSize: '15px' }}
            >
              Next: Real Reviews <ArrowDown size={16} />
            </button>
          </div>
        </div>
      </div>

      {/* ── REVIEWS ── */}
      {recentReviews.length > 0 && (
        <div id="reviews-section" style={{ padding: '70px 20px', maxWidth: '1120px', margin: '0 auto', width: '100%', boxSizing: 'border-box' }}>
          <div style={{ maxWidth: '1000px', margin: '0 auto' }}>
            <div style={{ textAlign: 'center', marginBottom: '48px' }}>
              <div style={{ display: 'inline-flex', alignItems: 'center', gap: '8px', background: 'rgba(13,148,136,0.12)', borderRadius: '50px', padding: '8px 20px', marginBottom: '16px' }}>
                <Star size={14} color="#0D9488" fill="#0D9488" />
                <span style={{ fontSize: '12px', fontWeight: 800, color: '#0D9488', textTransform: 'uppercase', letterSpacing: '1px' }}>What Our Guests Say</span>
              </div>
              <h2 style={{ fontSize: 'clamp(26px, 4vw, 40px)', fontWeight: 900, margin: '0 0 12px 0', letterSpacing: '-1px', color: 'var(--text-main)' }}>Real Reviews from Real Guests</h2>
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))', gap: '24px' }}>
              {recentReviews.map((rev, idx) => {
                return (
                  <div key={idx} className="card" style={{ padding: '24px', display: 'flex', flexDirection: 'column', gap: '16px', background: 'var(--surface)', border: '1px solid var(--border)', boxShadow: 'var(--shadow)' }}>
                    <div style={{ display: 'flex', gap: '4px' }}>
                      {[...Array(5)].map((_, i) => (
                        <Star key={i} size={16} fill={i < rev.rating ? "#0D9488" : "none"} color={i < rev.rating ? "#0D9488" : "#CBD5E1"} />
                      ))}
                    </div>
                    <p style={{ margin: 0, fontStyle: 'italic', color: 'var(--text-main)', lineHeight: 1.6, fontSize: '14px' }}>"{rev.comment}"</p>
                    <div style={{ marginTop: 'auto', display: 'flex', alignItems: 'center', gap: '12px' }}>
                      <div style={{ width: '38px', height: '38px', borderRadius: '50%', background: 'var(--light-bg)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--secondary)' }}>
                        <Users size={18} />
                      </div>
                      <div>
                        <h4 style={{ margin: 0, fontSize: '14px', fontWeight: 800, color: 'var(--text-main)' }}>{rev.touristName || 'Guest'}</h4>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
            <div style={{ textAlign: 'center', marginTop: '48px' }}>
              <button 
                onClick={() => {
                  const el = document.getElementById('cta-section');
                  if (el) window.scrollTo({ top: el.getBoundingClientRect().top + window.scrollY - 80, behavior: 'smooth' });
                }} 
                className="btn btn-primary" 
                style={{ padding: '12px 28px', borderRadius: '50px', fontSize: '15px' }}
              >
                Next: Book Now <ArrowDown size={16} />
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── CTA BANNER ── */}
      <div id="cta-section" style={{ background: 'linear-gradient(rgba(0, 15, 8, 0.7), rgba(0, 15, 8, 0.8)), url("https://images.unsplash.com/photo-1499793983690-e29da59ef1c2?ixlib=rb-4.0.3&auto=format&fit=crop&w=2000&q=80") center/cover fixed', padding: '100px 24px', textAlign: 'center' }}>
        <h2 style={{ color: 'white', fontSize: 'clamp(32px, 5vw, 56px)', fontWeight: 900, margin: '0 0 16px 0', letterSpacing: '-1px', textShadow: '0 4px 20px rgba(0,0,0,0.5)' }}>
          Ready to Book Your Stay?
        </h2>
        <p style={{ color: 'rgba(255,255,255,0.9)', fontSize: '18px', marginBottom: '40px' }}>Join thousands of travelers who trust Resort Connect.</p>
        <div style={{ display: 'flex', gap: '16px', justifyContent: 'center', flexWrap: 'wrap' }}>
          <button onClick={onRegister} className="btn btn-primary" style={{ height: '56px', padding: '0 40px', fontSize: '16px', borderRadius: '16px', boxShadow: '0 10px 25px rgba(251,54,64,0.4)' }}>Create Free Account</button>
          <button onClick={onLogin} style={{ height: '56px', padding: '0 32px', fontSize: '16px', borderRadius: '16px', background: 'rgba(255,255,255,0.15)', border: '1px solid rgba(255,255,255,0.3)', color: 'white', fontWeight: 700, cursor: 'pointer', backdropFilter: 'blur(10px)', transition: 'all 0.3s' }}
            onMouseOver={e => e.currentTarget.style.background = 'rgba(255,255,255,0.25)'}
            onMouseOut={e => e.currentTarget.style.background = 'rgba(255,255,255,0.15)'}
          >Sign In</button>
        </div>
        <div style={{ textAlign: 'center', marginTop: '56px' }}>
          <button 
            onClick={() => window.scrollTo({ top: 0, behavior: 'smooth' })} 
            style={{ padding: '12px 28px', borderRadius: '50px', fontSize: '15px', background: 'rgba(255,255,255,0.1)', border: '1px solid rgba(255,255,255,0.2)', color: 'white', cursor: 'pointer', backdropFilter: 'blur(10px)', display: 'inline-flex', alignItems: 'center', gap: '8px', transition: 'all 0.3s' }}
            onMouseOver={e => e.currentTarget.style.background = 'rgba(255,255,255,0.2)'}
            onMouseOut={e => e.currentTarget.style.background = 'rgba(255,255,255,0.1)'}
          >
            <ArrowRight size={16} style={{ transform: 'rotate(-90deg)' }} /> Back to Top
          </button>
        </div>
      </div>

      {/* ── FOOTER ── */}
      <footer id="footer-section" style={{ background: 'var(--light-bg)', padding: '40px 24px 28px', textAlign: 'center', borderTop: '1px solid var(--border)' }}>
        <div style={{ marginBottom: '24px', display: 'flex', gap: '24px', justifyContent: 'center', flexWrap: 'wrap', color: 'var(--text-muted)', fontSize: '14px' }}>
          {cmsData?.contact_platforms && cmsData.contact_platforms.length > 0 ? (
            cmsData.contact_platforms.map((platform, idx) => {
              if (!platform.platform_url_or_handle) return null;
              const name = platform.platform_name || 'Channel';
              const rawVal = platform.platform_url_or_handle.trim();
              let href = rawVal;
              if (name.toLowerCase() === 'email' && !rawVal.startsWith('mailto:')) {
                href = `mailto:${rawVal}`;
              } else if (name.toLowerCase() === 'phone' && !rawVal.startsWith('tel:')) {
                href = `tel:${rawVal}`;
              } else if (!/^https?:\/\//i.test(rawVal) && !rawVal.includes(':')) {
                href = `https://${rawVal}`;
              }

              return (
                <span key={platform.id || idx} style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                  <strong>{name}:</strong>
                  <a href={href} target="_blank" rel="noreferrer" style={{ color: 'var(--primary)', textDecoration: 'underline' }}>
                    {rawVal}
                  </a>
                </span>
              );
            })
          ) : (
            <>
              {cmsData?.contact?.facebook && (
                <span style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                  Facebook: <a href={cmsData.contact.facebook} target="_blank" rel="noreferrer" style={{ color: 'var(--primary)', textDecoration: 'underline' }}>{cmsData.contact.facebook}</a>
                </span>
              )}
              {cmsData?.contact?.email && (
                <span style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                  Email: <a href={`mailto:${cmsData.contact.email}`} style={{ color: 'var(--primary)', textDecoration: 'underline' }}>{cmsData.contact.email}</a>
                </span>
              )}
              {cmsData?.contact?.phone && (
                <span style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                  Phone: <a href={`tel:${cmsData.contact.phone}`} style={{ color: 'var(--primary)', textDecoration: 'underline' }}>{cmsData.contact.phone}</a>
                </span>
              )}
            </>
          )}
        </div>
        <div style={{ marginBottom: '16px', display: 'flex', gap: '16px', justifyContent: 'center', flexWrap: 'wrap' }}>
          <button onClick={onViewPolicies} style={{ background: 'none', border: 'none', color: 'var(--text-muted)', fontSize: '14px', cursor: 'pointer', textDecoration: 'underline' }}>
            Policies & Property Information
          </button>
          <button onClick={() => setShowTerms(true)} style={{ background: 'none', border: 'none', color: 'var(--text-muted)', fontSize: '14px', cursor: 'pointer', textDecoration: 'underline' }}>
            Platform Terms & Policies
          </button>
        </div>
        <p style={{ color: 'var(--text-muted)', fontSize: '13px', margin: 0, fontWeight: 600 }}>
          © 2026 Resort Connect · All rights reserved
        </p>
      </footer>

      {showTerms && <TermsAndPolicies onClose={() => setShowTerms(false)} />}
      
      {/* ── VERTICAL DOT NAVIGATION (TOUR GUIDE) ── */}
      <div style={{
        position: 'fixed',
        right: '24px',
        top: '50%',
        transform: 'translateY(-50%)',
        display: 'flex',
        flexDirection: 'column',
        gap: '16px',
        zIndex: 9999,
      }}>
        {SECTION_IDS.map((id, i) => {
          const labels = ['Welcome', 'Promotions', 'Featured Resorts', 'Why Choose Us', 'Reviews', 'Book Now'];
          const isActive = currentSectionIndex === i;
          return (
            <div 
              key={id}
              title={labels[i]}
              onClick={() => {
                if (i === 0) {
                  window.scrollTo({ top: 0, behavior: 'smooth' });
                } else {
                  const el = document.getElementById(id);
                  if (el) {
                    const y = el.getBoundingClientRect().top + window.scrollY - 80;
                    window.scrollTo({ top: y, behavior: 'smooth' });
                  }
                }
              }}
              style={{
                width: '12px',
                height: '12px',
                borderRadius: '50%',
                background: isActive ? 'var(--primary)' : 'rgba(128,128,128,0.3)',
                border: isActive ? '2px solid white' : 'none',
                boxShadow: isActive ? '0 0 10px rgba(29,211,176,0.5)' : 'none',
                cursor: 'pointer',
                transition: 'all 0.3s ease',
                transform: isActive ? 'scale(1.3)' : 'scale(1)',
              }}
            />
          );
        })}
      </div>
    </div>
  );
};

const defaultImageMap = {
  'Hotel Ramiro': HotelRamiro1,
  'Nadzville Resort': NadzvilleResort1,
  'Casa DelRio': CasaDelRio1,
};

const PublicPropertyCard = ({ prop, onCta, isDarkMode, index = 0 }) => {
  const [rating, setRating] = useState(0);
  const [count, setCount] = useState(0);
  const imageUrls = Array.isArray(prop.imageUrls) ? prop.imageUrls.filter(Boolean) : (typeof prop.imageUrls === 'object' && prop.imageUrls ? Object.values(prop.imageUrls) : []);

  useEffect(() => {
    const uid = prop.ownerUid || prop.uid || prop.id;
    const reviewRef = ref(db, `reviews/${uid}`);
    const unsub = onValue(reviewRef, (snap) => {
      const data = snap.val();
      if (data) {
        const vals = Object.values(data);
        setRating(vals.reduce((a, b) => a + (b.rating || 0), 0) / vals.length);
        setCount(vals.length);
      }
    });
    return () => unsub();
  }, [prop]);

  const defaultImg = defaultImageMap[prop.name] || CasaDelRio1;
  const displayImage = (imageUrls && imageUrls.length > 0 && imageUrls[0]) ? imageUrls[0] : defaultImg;

  return (
    <div className="card" style={{ padding: 0, overflow: 'hidden', cursor: 'pointer', background: 'var(--surface)', border: '1px solid var(--border)', boxShadow: 'var(--shadow)', borderRadius: '20px' }}
      onClick={onCta}
      onMouseOver={e => e.currentTarget.style.transform = 'translateY(-6px)'}
      onMouseOut={e => e.currentTarget.style.transform = 'translateY(0)'}
    >
      <div style={{ position: 'relative', height: '220px' }}>
        <img src={displayImage} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
        <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(to bottom, transparent 50%, rgba(11,19,43,0.6))' }} />
        <div style={{ position: 'absolute', top: '14px', left: '14px', background: 'var(--primary)', color: 'white', padding: '5px 12px', borderRadius: '8px', fontSize: '10px', fontWeight: 800, textTransform: 'uppercase', letterSpacing: '0.5px' }}>{prop.type || 'Resort'}</div>
        <div style={{ position: 'absolute', bottom: '14px', left: '14px', background: 'rgba(255,255,255,0.95)', color: '#1B365D', padding: '4px 10px', borderRadius: '8px', display: 'flex', alignItems: 'center', gap: '4px', fontSize: '13px', fontWeight: 800 }}>
          <Star size={13} fill="#0D9488" color="#0D9488" /> {rating > 0 ? rating.toFixed(1) : '0.0'}
          <span style={{ color: '#64748B', fontWeight: 500, fontSize: '11px' }}>({count || 0})</span>
        </div>
      </div>
      <div style={{ padding: '20px' }}>
        <h4 style={{ margin: '0 0 6px 0', fontSize: '17px', fontWeight: 800, color: 'var(--text-main)' }}>{prop.name}</h4>
        <div style={{ display: 'flex', alignItems: 'center', gap: '6px', color: 'var(--text-muted)', fontSize: '13px', marginBottom: '16px' }}>
          <MapPin size={13} color="var(--secondary)" /> {prop.description?.slice(0, 60)}{prop.description?.length > 60 ? '…' : ''}
        </div>
        <button className="btn btn-primary" style={{ width: '100%', borderRadius: '10px', fontSize: '13px', padding: '10px' }}>
          Know More <ArrowRight size={14} />
        </button>
      </div>
    </div>
  );
};

export default Homepage;
