import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, onValue } from 'firebase/database';
import { Star, MapPin, ArrowRight, Shield, Compass, Users, ChevronLeft, ChevronRight, Moon, Sun, Zap } from 'lucide-react';
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

const Homepage = ({ onLogin, onRegister, isDarkMode, onToggleDark, onViewPolicies }) => {
  const [properties, setProperties] = useState([]);
  const [heroIdx, setHeroIdx] = useState(0);
  const [loading, setLoading] = useState(true);
  const [showTerms, setShowTerms] = useState(false);

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
    return () => unsub();
  }, []);

  useEffect(() => {
    const timer = setInterval(() => setHeroIdx(i => (i + 1) % HERO_IMAGES.length), 5000);
    return () => clearInterval(timer);
  }, []);

  return (
    <div style={{ minHeight: '100vh', background: 'var(--light-bg)', overflowX: 'hidden' }}>
      {/* ── NAV ── */}
      <nav style={{
        position: 'fixed', top: 0, left: 0, right: 0, zIndex: 1000,
        background: 'var(--nav-bg)', backdropFilter: 'blur(20px)',
        borderBottom: '1px solid var(--border)',
        padding: '14px 32px', display: 'flex', justifyContent: 'space-between', alignItems: 'center'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <img src={logo} alt="Resort Connect" style={{ height: '60px', width: 'auto' }} />
          <div>
            <div style={{ fontWeight: 900, fontSize: '17px', color: 'var(--nav-title)', letterSpacing: '-0.5px' }}>Resort Connect</div>
            <div style={{ fontSize: '10px', fontWeight: 700, color: 'var(--secondary)', textTransform: 'uppercase', letterSpacing: '0.5px' }}>Discover & Book</div>
          </div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <button onClick={onToggleDark} style={{ background: 'var(--nav-group-bg)', border: 'none', borderRadius: '50%', width: '38px', height: '38px', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', color: 'var(--text-muted)', transition: 'var(--transition)' }}>
            {isDarkMode ? <Sun size={18} /> : <Moon size={18} />}
          </button>
          <button onClick={onLogin} style={{ background: 'var(--nav-group-bg)', border: '1px solid var(--border)', borderRadius: '12px', padding: '9px 20px', fontWeight: 700, fontSize: '14px', cursor: 'pointer', color: 'var(--text-main)', transition: 'var(--transition)' }}
            onMouseOver={e => e.currentTarget.style.background = 'var(--surface)'}
            onMouseOut={e => e.currentTarget.style.background = 'var(--nav-group-bg)'}
          >Sign In</button>
          <button onClick={onRegister} className="btn btn-primary" style={{ padding: '9px 20px', borderRadius: '12px', fontSize: '14px' }}>
            Get Started <ArrowRight size={15} />
          </button>
        </div>
      </nav>

      {/* ── HERO ── */}
      <div style={{ position: 'relative', height: '100vh', overflow: 'hidden' }}>
        {HERO_IMAGES.map((item, i) => (
          <div key={i} style={{
            position: 'absolute', inset: 0,
            backgroundImage: `url(${item.src})`,
            backgroundSize: 'cover', backgroundPosition: 'center',
            opacity: i === heroIdx ? 1 : 0,
            transition: 'opacity 1.2s ease-in-out'
          }}>
            <div style={{ position: 'absolute', bottom: '60px', left: '32px', background: 'rgba(0,0,0,0.6)', padding: '10px 20px', borderRadius: '12px', backdropFilter: 'blur(10px)', color: 'white', fontWeight: 700, fontSize: '15px', display: 'flex', alignItems: 'center', gap: '8px', zIndex: 11, border: '1px solid rgba(255,255,255,0.1)' }}>
              <Compass size={16} color="#1DD3B0" /> Featured: {item.title}
            </div>
          </div>
        ))}
        <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(to bottom, rgba(0,15,8,0.55) 0%, rgba(0,15,8,0.35) 50%, rgba(0,15,8,0.75) 100%)', zIndex: 1 }} />

        <div style={{ position: 'relative', zIndex: 10, height: '100%', display: 'flex', flexDirection: 'column', justifyContent: 'center', alignItems: 'center', textAlign: 'center', padding: '0 20px' }}>
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: '8px', background: 'rgba(29,211,176,0.15)', border: '1px solid rgba(29,211,176,0.3)', backdropFilter: 'blur(8px)', borderRadius: '50px', padding: '8px 20px', marginBottom: '28px' }}>
            <Zap size={14} color="#1DD3B0" />
            <span style={{ fontSize: '13px', fontWeight: 700, color: '#1DD3B0', letterSpacing: '0.5px' }}>Instant Booking Available</span>
          </div>
          <h1 style={{ color: 'white', fontSize: 'clamp(36px, 6vw, 72px)', fontWeight: 900, margin: '0 0 20px 0', lineHeight: 1.1, letterSpacing: '-2px', maxWidth: '900px' }}>
            Your Perfect Resort<br />
            <span style={{ color: '#1DD3B0' }}>Awaits You</span>
          </h1>
          <p style={{ color: 'rgba(255,255,255,0.8)', fontSize: 'clamp(15px, 2vw, 20px)', fontWeight: 500, maxWidth: '560px', lineHeight: 1.6, marginBottom: '40px' }}>
            Discover and book verified partner resorts with ease. Real-time availability, instant confirmation.
          </p>
          <div style={{ display: 'flex', gap: '16px', flexWrap: 'wrap', justifyContent: 'center' }}>
            <button onClick={() => document.getElementById('featured-resorts').scrollIntoView({ behavior: 'smooth' })} className="btn btn-secondary" style={{ height: '56px', padding: '0 36px', fontSize: '16px', borderRadius: '16px' }}>
              <Compass size={20} /> Explore Resorts
            </button>
            <button onClick={onLogin} style={{ height: '56px', padding: '0 36px', fontSize: '16px', borderRadius: '16px', background: 'rgba(255,255,255,0.12)', border: '1px solid rgba(255,255,255,0.25)', backdropFilter: 'blur(8px)', color: 'white', fontWeight: 700, cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '10px', transition: 'var(--transition)' }}
              onMouseOver={e => e.currentTarget.style.background = 'rgba(255,255,255,0.2)'}
              onMouseOut={e => e.currentTarget.style.background = 'rgba(255,255,255,0.12)'}
            >
              Sign In <ArrowRight size={18} />
            </button>
          </div>
        </div>

        {/* Dot navigation */}
        <div style={{ position: 'absolute', bottom: '32px', left: '50%', transform: 'translateX(-50%)', display: 'flex', gap: '10px', zIndex: 10 }}>
          {HERO_IMAGES.map((_, i) => (
            <button key={i} onClick={() => setHeroIdx(i)} style={{ width: i === heroIdx ? '24px' : '8px', height: '8px', borderRadius: '4px', background: i === heroIdx ? '#1DD3B0' : 'rgba(255,255,255,0.4)', border: 'none', cursor: 'pointer', transition: 'all 0.3s ease', padding: 0 }} />
          ))}
        </div>
      </div>

      {/* ── STATS BAR ── */}
      <div style={{ background: 'var(--secondary)', padding: '28px 32px' }}>
        <div style={{ maxWidth: '900px', margin: '0 auto', display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '20px', textAlign: 'center' }}>
          {[['3', 'Partner Resorts'], ['100%', 'Verified Listings'], ['0', 'Hidden Fees']].map(([val, label]) => (
            <div key={label}>
              <div style={{ fontSize: '36px', fontWeight: 900, color: '#002D24', letterSpacing: '-1px' }}>{val}</div>
              <div style={{ fontSize: '13px', fontWeight: 700, color: '#004D3C', textTransform: 'uppercase', letterSpacing: '0.5px' }}>{label}</div>
            </div>
          ))}
        </div>
      </div>

      {/* ── FEATURED RESORTS ── */}
      <div id="featured-resorts" style={{ maxWidth: '1120px', margin: '0 auto', padding: '80px 24px' }}>
        <div style={{ textAlign: 'center', marginBottom: '56px' }}>
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: '8px', background: 'var(--secondary-soft)', borderRadius: '50px', padding: '8px 20px', marginBottom: '16px' }}>
            <Compass size={14} color="var(--secondary)" />
            <span style={{ fontSize: '12px', fontWeight: 800, color: 'var(--secondary)', textTransform: 'uppercase', letterSpacing: '1px' }}>Featured Destinations</span>
          </div>
          <h2 style={{ fontSize: 'clamp(28px, 4vw, 48px)', fontWeight: 900, margin: '0 0 16px 0', letterSpacing: '-1px', color: 'var(--text-main)' }}>Explore Our Partner Resorts</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '17px', maxWidth: '500px', margin: '0 auto' }}>Hand-picked, verified resorts ready for your next getaway</p>
        </div>

        {loading ? (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))', gap: '24px' }}>
            {[1,2,3].map(i => <div key={i} className="shimmer" style={{ height: '360px', borderRadius: '20px' }} />)}
          </div>
        ) : (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))', gap: '24px' }}>
            {properties.map(prop => <PublicPropertyCard key={prop.id} prop={prop} onCta={onRegister} />)}
          </div>
        )}

        <div style={{ textAlign: 'center', marginTop: '48px' }}>
          <button onClick={onRegister} className="btn btn-primary" style={{ height: '56px', padding: '0 40px', fontSize: '16px', borderRadius: '16px' }}>
            Create Account to Book <ArrowRight size={18} />
          </button>
        </div>
      </div>

      {/* ── FEATURES ── */}
      <div style={{ background: 'var(--surface)', padding: '80px 24px', borderTop: '1px solid var(--border)' }}>
        <div style={{ maxWidth: '1000px', margin: '0 auto' }}>
          <div style={{ textAlign: 'center', marginBottom: '56px' }}>
            <h2 style={{ fontSize: 'clamp(26px, 4vw, 44px)', fontWeight: 900, margin: '0 0 12px 0', letterSpacing: '-1px' }}>Why Choose Resort Connect?</h2>
            <p style={{ color: 'var(--text-muted)', fontSize: '16px' }}>Everything you need for a seamless resort experience</p>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: '28px' }}>
            {[
              { icon: <Shield size={28} color="var(--secondary)" />, title: 'Verified Partners', desc: 'Every resort is personally verified by our team for quality and safety.' },
              { icon: <Compass size={28} color="var(--primary)" />, title: 'Interactive Maps', desc: 'Find resorts on a live map and get directions with one tap.' },
              { icon: <Users size={28} color="#7C3AED" />, title: 'Bill Splitting', desc: 'Easily split the bill with friends directly from your booking.' },
            ].map(f => (
              <div key={f.title} className="card" style={{ padding: '32px', textAlign: 'center' }}>
                <div style={{ width: '64px', height: '64px', borderRadius: '20px', background: 'var(--light-bg)', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 20px' }}>{f.icon}</div>
                <h3 style={{ fontWeight: 800, fontSize: '18px', margin: '0 0 10px 0' }}>{f.title}</h3>
                <p style={{ color: 'var(--text-muted)', fontSize: '14px', lineHeight: '1.6', margin: 0 }}>{f.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* ── CTA BANNER ── */}
      <div style={{ background: 'linear-gradient(135deg, #000F08 0%, #002D24 100%)', padding: '80px 24px', textAlign: 'center' }}>
        <h2 style={{ color: 'white', fontSize: 'clamp(28px, 4vw, 48px)', fontWeight: 900, margin: '0 0 16px 0', letterSpacing: '-1px' }}>
          Ready to Book Your Stay?
        </h2>
        <p style={{ color: 'rgba(255,255,255,0.7)', fontSize: '17px', marginBottom: '36px' }}>Join thousands of travelers who trust Resort Connect.</p>
        <div style={{ display: 'flex', gap: '16px', justifyContent: 'center', flexWrap: 'wrap' }}>
          <button onClick={onRegister} className="btn btn-secondary" style={{ height: '56px', padding: '0 40px', fontSize: '16px', borderRadius: '16px' }}>Create Free Account</button>
          <button onClick={onLogin} style={{ height: '56px', padding: '0 32px', fontSize: '16px', borderRadius: '16px', background: 'rgba(255,255,255,0.08)', border: '1px solid rgba(255,255,255,0.2)', color: 'white', fontWeight: 700, cursor: 'pointer', transition: 'var(--transition)' }}
            onMouseOver={e => e.currentTarget.style.background = 'rgba(255,255,255,0.15)'}
            onMouseOut={e => e.currentTarget.style.background = 'rgba(255,255,255,0.08)'}
          >Sign In</button>
        </div>
      </div>

      {/* ── FOOTER ── */}
      <footer style={{ background: '#000F08', padding: '28px 24px', textAlign: 'center', borderTop: '1px solid rgba(255,255,255,0.05)' }}>
        <div style={{ marginBottom: '16px', display: 'flex', gap: '16px', justifyContent: 'center', flexWrap: 'wrap' }}>
          <button onClick={onViewPolicies} style={{ background: 'none', border: 'none', color: 'rgba(255,255,255,0.7)', fontSize: '14px', cursor: 'pointer', textDecoration: 'underline' }}>
            Policies & Property Information
          </button>
          <button onClick={() => setShowTerms(true)} style={{ background: 'none', border: 'none', color: 'rgba(255,255,255,0.7)', fontSize: '14px', cursor: 'pointer', textDecoration: 'underline' }}>
            Platform Terms & Policies
          </button>
        </div>
        <p style={{ color: 'rgba(255,255,255,0.4)', fontSize: '13px', margin: 0, fontWeight: 600 }}>
          © 2026 Resort Connect · All rights reserved
        </p>
      </footer>

      {showTerms && <TermsAndPolicies onClose={() => setShowTerms(false)} />}
    </div>
  );
};

const defaultImageMap = {
  'Hotel Ramiro': HotelRamiro1,
  'Nadzville Resort': NadzvilleResort1,
  'Casa DelRio': CasaDelRio1,
};

const PublicPropertyCard = ({ prop, onCta }) => {
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
    <div className="card" style={{ padding: 0, overflow: 'hidden', cursor: 'pointer' }}
      onClick={onCta}
      onMouseOver={e => e.currentTarget.style.transform = 'translateY(-6px)'}
      onMouseOut={e => e.currentTarget.style.transform = 'translateY(0)'}
    >
      <div style={{ position: 'relative', height: '220px' }}>
        <img src={displayImage} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
        <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(to bottom, transparent 50%, rgba(0,0,0,0.5))' }} />
        <div style={{ position: 'absolute', top: '14px', left: '14px', background: 'var(--primary)', color: 'white', padding: '5px 12px', borderRadius: '8px', fontSize: '10px', fontWeight: 800, textTransform: 'uppercase' }}>{prop.type || 'Resort'}</div>
        <div style={{ position: 'absolute', bottom: '14px', left: '14px', background: 'rgba(255,255,255,0.95)', color: '#000', padding: '4px 10px', borderRadius: '8px', display: 'flex', alignItems: 'center', gap: '4px', fontSize: '13px', fontWeight: 800 }}>
          <Star size={13} fill="#FFD700" color="#FFD700" /> {rating > 0 ? rating.toFixed(1) : '0.0'}
          <span style={{ color: '#888', fontWeight: 500, fontSize: '11px' }}>({count || 0})</span>
        </div>
      </div>
      <div style={{ padding: '20px' }}>
        <h4 style={{ margin: '0 0 6px 0', fontSize: '17px', fontWeight: 800 }}>{prop.name}</h4>
        <div style={{ display: 'flex', alignItems: 'center', gap: '6px', color: 'var(--text-muted)', fontSize: '13px', marginBottom: '16px' }}>
          <MapPin size={13} color="var(--primary)" /> {prop.description?.slice(0, 60)}{prop.description?.length > 60 ? '…' : ''}
        </div>
        <button className="btn btn-primary" style={{ width: '100%', borderRadius: '10px', fontSize: '13px', padding: '10px' }}>
          View & Book <ArrowRight size={14} />
        </button>
      </div>
    </div>
  );
};

export default Homepage;
