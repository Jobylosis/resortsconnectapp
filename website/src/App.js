import React, { useState, useEffect } from 'react';
import 'leaflet/dist/leaflet.css';
import L from 'leaflet';
import icon from 'leaflet/dist/images/marker-icon.png';
import iconShadow from 'leaflet/dist/images/marker-shadow.png';
import { auth, db } from './firebase';
import { onAuthStateChanged, signOut } from 'firebase/auth';
import { ref, onValue } from 'firebase/database';
import Login from './components/Login';
import Register from './components/Register';
import ForgotPassword from './components/ForgotPassword';
import EditPropertyModal from './components/EditPropertyModal';
import OwnerDashboard from './components/OwnerDashboard';
import TouristDashboard from './components/TouristDashboard';
import AdminDashboard from './components/AdminDashboard';
import Profile from './components/Profile';
import Notifications from './components/Notifications';
import VerifyEmail from './components/VerifyEmail';
import Homepage from './components/Homepage';
import PoliciesPropertyDetails from './components/PoliciesPropertyDetails';
import ResubmitDocuments from './components/ResubmitDocuments';
import { LogOut, Bell, User, LayoutDashboard, Moon, Sun, Home, ShieldAlert } from 'lucide-react';
import logo from './assets/ResortConnectLogo.png';

let DefaultIcon = L.icon({
  iconUrl: icon,
  shadowUrl: iconShadow,
  iconSize: [25, 41],
  iconAnchor: [12, 41],
  popupAnchor: [1, -34],
  tooltipAnchor: [16, -28]
});
L.Marker.prototype.options.icon = DefaultIcon;

function App() {
  const [user, setUser] = useState(null);
  const [profile, setProfile] = useState(null);
  const [loading, setLoading] = useState(true);
  const [authView, setAuthView] = useState('home');
  const [view, setView] = useState('dashboard');
  const [dashboardKey, setDashboardKey] = useState(Date.now());
  const [unreadCount, setUnreadCount] = useState(0);
  const [isDarkMode, setIsDarkMode] = useState(() => {
    const saved = localStorage.getItem('isDarkMode');
    return saved ? JSON.parse(saved) : false;
  });

  useEffect(() => {
    if (isDarkMode) {
      document.documentElement.setAttribute('data-theme', 'dark');
      localStorage.setItem('isDarkMode', 'true');
    } else {
      document.documentElement.removeAttribute('data-theme');
      localStorage.setItem('isDarkMode', 'false');
    }
  }, [isDarkMode]);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, (user) => {
      setUser(user);
      if (user) {
        const userRef = ref(db, `users/${user.uid}`);
        onValue(userRef, (snapshot) => {
          setProfile(snapshot.val());
          setLoading(false);
        });

        const notifRef = ref(db, `notifications/${user.uid}`);
        onValue(notifRef, (snapshot) => {
          const data = snapshot.val();
          if (data) {
            const unread = Object.values(data).filter(n => !n.isRead).length;
            setUnreadCount(unread);
          } else {
            setUnreadCount(0);
          }
        });
      } else {
        setProfile(null);
        setLoading(false);
      }
    });

    const handleGlobalInput = (e) => {
      const target = e.target;
      if (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA') {
        // Skip chat inputs based on class name
        if (target.className && typeof target.className === 'string' && target.className.toLowerCase().includes('chat')) return;

        const emojiRegex = /[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]/gu;
        if (emojiRegex.test(target.value)) {
          const newVal = target.value.replace(emojiRegex, '');
          if (target.value !== newVal) {
            target.value = newVal;
            const event = new Event('input', { bubbles: true });
            
            const nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value")?.set;
            const nativeTextAreaValueSetter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, "value")?.set;
            
            if (target.tagName === 'INPUT' && nativeInputValueSetter) {
                nativeInputValueSetter.call(target, newVal);
            } else if (target.tagName === 'TEXTAREA' && nativeTextAreaValueSetter) {
                nativeTextAreaValueSetter.call(target, newVal);
            }
            target.dispatchEvent(event);
          }
        }
      }
    };

    document.addEventListener('input', handleGlobalInput, true);
    return () => {
      unsubscribe();
      document.removeEventListener('input', handleGlobalInput, true);
    };
  }, []);

  const handleLogout = () => {
    if (window.confirm('Are you sure you want to log out?')) {
      signOut(auth);
      setView('dashboard');
      setAuthView('login');
    }
  };

  if (loading) {
    return (
      <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100vh', background: 'var(--light-bg)' }}>
        <div className="loader"></div>
      </div>
    );
  }

  if (!user) {
    if (authView === 'home') {
      return (
        <Homepage
          onLogin={() => setAuthView('login')}
          onRegister={() => setAuthView('register')}
          isDarkMode={isDarkMode}
          onToggleDark={() => setIsDarkMode(!isDarkMode)}
          onViewPolicies={() => setAuthView('policies')}
        />
      );
    }

    if (authView === 'policies' || (typeof authView === 'object' && authView.name === 'property_policies')) {
      return (
        <PoliciesPropertyDetails 
          property={typeof authView === 'object' ? authView.property : null}
          onBack={() => setAuthView('home')} 
        />
      );
    }

    let authComponent;
    if (authView === 'register') {
      authComponent = <Register onBackToLogin={() => setAuthView('login')} onGoHome={() => setAuthView('home')} />;
    } else if (authView === 'forgotPassword') {
      authComponent = <ForgotPassword onBack={() => setAuthView('login')} onGoHome={() => setAuthView('home')} />;
    } else {
      authComponent = <Login onShowRegister={() => setAuthView('register')} onShowForgotPassword={() => setAuthView('forgotPassword')} onGoHome={() => setAuthView('home')} />;
    }

    return (
      <div style={{ position: 'relative', width: '100%', minHeight: '100vh' }}>
        <button
          onClick={() => setIsDarkMode(!isDarkMode)}
          style={{
            position: 'fixed', top: '20px', right: '20px', width: '44px', height: '44px',
            borderRadius: '50%', border: 'none', background: 'rgba(255,255,255,0.15)',
            backdropFilter: 'blur(10px)', color: 'white', cursor: 'pointer',
            display: 'flex', justifyContent: 'center', alignItems: 'center',
            transition: 'var(--transition)', zIndex: 10000, boxShadow: '0 4px 12px rgba(0,0,0,0.1)'
          }}
          className="theme-toggle-btn"
        >
          {isDarkMode ? <Sun size={20} /> : <Moon size={20} />}
        </button>
        <button
          onClick={() => setAuthView('home')}
          style={{
            position: 'fixed', top: '20px', left: '20px', padding: '10px 18px',
            borderRadius: '50px', border: 'none', background: 'rgba(255,255,255,0.15)',
            backdropFilter: 'blur(10px)', color: 'white', cursor: 'pointer',
            display: 'flex', alignItems: 'center', gap: '8px',
            fontWeight: 700, fontSize: '13px', transition: 'var(--transition)', zIndex: 10000
          }}
          className="theme-toggle-btn"
        >
          ← Home
        </button>
        {authComponent}
        <style>{`
          .theme-toggle-btn:hover { background: rgba(255,255,255,0.25); transform: scale(1.05); }
        `}</style>
      </div>
    );
  }

  const isSocialAuth = user.providerData && user.providerData.some(
    p => p.providerId === 'google.com' || p.providerId === 'facebook.com'
  );

  if (!user.emailVerified && !isSocialAuth) {
    return <VerifyEmail />;
  }

  if (profile?.isBanned) {
    return (
      <div className="app-container" style={{ textAlign: 'center', marginTop: '100px' }}>
        <div className="card" style={{ maxWidth: '500px', margin: '0 auto' }}>
          <h1 style={{ color: 'var(--primary)', marginBottom: '16px' }}>Account Suspended</h1>
          <p style={{ color: 'var(--text-muted)', marginBottom: '24px' }}>Please contact admin at resortconnect2026@gmail.com</p>
          <button
            className="btn btn-primary"
            onClick={handleLogout}
            style={{ marginTop: '20px' }}
          >
            Log out & Go Back
          </button>
        </div>
      </div>
    );
  }

  const isMissingDocs = profile && !profile.idImageUrl && profile.role !== 'Admin' && profile.identityStatus !== 'rejected';
  
  if (user && (!profile || isMissingDocs)) {
    return (
      <div style={{ position: 'relative', width: '100%', minHeight: '100vh' }}>
         <Register onBackToLogin={handleLogout} onGoHome={handleLogout} isCompletingSocial={true} socialUser={user} />
      </div>
    );
  }

  if (profile && profile.identityStatus === 'rejected' && profile.role !== 'Admin') {
    return <ResubmitDocuments user={user} profile={profile} onLogout={handleLogout} />;
  }

  if (profile && profile.role !== 'Admin' && profile.idVerified === false) {
    return (
      <div className="app-container" style={{ textAlign: 'center', marginTop: '100px' }}>
        <div className="card" style={{ maxWidth: '500px', margin: '0 auto' }}>
          <h1 style={{ color: 'var(--primary)', marginBottom: '16px' }}>Pending Verification</h1>
          <p style={{ color: 'var(--text-muted)', marginBottom: '24px' }}>Your account is currently pending Admin verification. Please wait until your Valid ID is approved.</p>
          <button
            className="btn btn-primary"
            onClick={handleLogout}
            style={{ marginTop: '20px' }}
          >
            Log out & Go Back
          </button>
        </div>
      </div>
    );
  }

  const role = (profile?.role || 'Tourist').toUpperCase();

  const renderContent = () => {
    if (view === 'profile') return <Profile onBack={() => setView('dashboard')} />;
    if (view === 'notifications') return <Notifications uid={user.uid} onBack={() => setView('dashboard')} />;
    if (view === 'policies') return <PoliciesPropertyDetails onBack={() => setView('dashboard')} ownerUid={role === 'OWNER' ? user.uid : null} />;
    if (view === 'edit_property') return (
      <>
        <OwnerDashboard profile={profile} uid={user.uid} />
        <EditPropertyModal uid={user.uid} onClose={() => setView('dashboard')} />
      </>
    );

    if (role === 'OWNER') return <OwnerDashboard key={dashboardKey} profile={profile} uid={user.uid} />;
    if (role === 'ADMIN') return <AdminDashboard key={dashboardKey} profile={profile} uid={user.uid} />;
    return <TouristDashboard key={dashboardKey} profile={profile} uid={user.uid} onViewPolicies={(prop) => setView({ name: 'property_policies', property: prop })} />;
  };

  if (view && view.name === 'property_policies') {
    return (
      <div className="app-container">
        <PoliciesPropertyDetails property={view.property} onBack={() => setView('dashboard')} />
      </div>
    );
  }

  return (
    <div className="app">
      <header style={{
        backgroundColor: 'var(--nav-bg)',
        backdropFilter: 'blur(20px)',
        padding: '12px 24px',
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        boxShadow: '0 4px 30px rgba(0,0,0,0.03)',
        position: 'sticky',
        top: 0,
        zIndex: 100,
        borderBottom: '1px solid rgba(0,0,0,0.05)'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
          <div className="logo-home-btn" style={{ cursor: 'pointer', position: 'relative', display: 'flex' }} onClick={() => { setView('dashboard'); setDashboardKey(Date.now()); window.location.hash = ''; }}>
            <img src={logo} alt="Logo" style={{ height: '72px', width: 'auto' }} />
            <div className="logo-hover-overlay" style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, background: 'rgba(255,255,255,0.1)', borderRadius: '12px', opacity: 0, transition: 'var(--transition)', display: 'flex', alignItems: 'center', justifyContent: 'center', pointerEvents: 'none' }}>
              <span style={{ background: 'var(--primary)', color: 'white', padding: '4px 8px', borderRadius: '8px', fontSize: '11px', fontWeight: 'bold', boxShadow: '0 2px 8px rgba(0,0,0,0.2)' }}>Dashboard</span>
            </div>
          </div>
          <div className="hide-mobile">
            <h2 style={{ margin: 0, fontSize: '18px', fontWeight: 800, color: 'var(--nav-title)', letterSpacing: '-0.5px' }}>Resort Connect</h2>
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              <div style={{ width: '6px', height: '6px', borderRadius: '50%', background: 'var(--secondary)' }}></div>
              <p style={{ margin: 0, fontSize: '11px', fontWeight: 700, color: 'var(--secondary)', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                {profile?.firstName} • {role}
              </p>
            </div>
          </div>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <div className="nav-group" style={{
            background: 'var(--nav-group-bg)',
            padding: '4px',
            borderRadius: '30px',
            display: 'flex',
            gap: '4px'
          }}>
            <NavIcon icon={<LayoutDashboard size={19} />} active={view === 'dashboard'} onClick={() => setView('dashboard')} />

            <div style={{ position: 'relative' }}>
              <NavIcon icon={<Bell size={19} />} active={view === 'notifications'} onClick={() => setView('notifications')} />
              {unreadCount > 0 && (
                <span style={{
                  position: 'absolute', top: '4px', right: '4px', background: 'var(--primary)',
                  color: 'white', fontSize: '10px', borderRadius: '50%',
                  minWidth: '16px', height: '16px', display: 'flex',
                  justifyContent: 'center', alignItems: 'center', fontWeight: 800,
                  border: '2px solid white'
                }}>
                  {unreadCount}
                </span>
              )}
            </div>
            <NavIcon icon={<ShieldAlert size={19} />} active={view === 'policies'} onClick={() => setView('policies')} />

            {role === 'OWNER' ? (
              <NavIcon icon={<Home size={19} />} active={view === 'edit_property'} onClick={() => setView('edit_property')} />
            ) : (
              <NavIcon icon={<User size={19} />} active={view === 'profile'} onClick={() => setView('profile')} />
            )}
          </div>

          <div style={{ width: '1px', height: '24px', background: 'var(--nav-divider)' }}></div>

          <button
            onClick={() => setIsDarkMode(!isDarkMode)}
            style={{
              width: '40px', height: '40px', borderRadius: '50%', border: 'none',
              background: 'var(--nav-group-bg)', color: 'var(--text-muted)', cursor: 'pointer',
              display: 'flex', justifyContent: 'center', alignItems: 'center',
              transition: 'var(--transition)'
            }}
          >
            {isDarkMode ? <Sun size={20} /> : <Moon size={20} />}
          </button>

          <button
            onClick={handleLogout}
            style={{
              width: '40px', height: '40px', borderRadius: '50%', border: 'none',
              background: 'var(--logout-bg)', color: 'var(--primary)', cursor: 'pointer',
              display: 'flex', justifyContent: 'center', alignItems: 'center',
              transition: 'var(--transition)'
            }}
            className="logout-btn"
          >
            <LogOut size={19} />
          </button>
        </div>
      </header>

      <main className="app-container">
        {renderContent()}
      </main>

      <style>{`
        .logout-btn:hover { background: var(--primary) !important; color: white !important; transform: rotate(10deg); }
        .logo-home-btn { padding: 4px; border-radius: 12px; transition: var(--transition); }
        .logo-home-btn:hover { background: var(--nav-group-bg); transform: scale(1.02); }
        .logo-home-btn:hover .logo-hover-overlay { opacity: 1 !important; }
        @media (max-width: 600px) {
          .hide-mobile { display: none !important; }
        }
      `}</style>
    </div>
  );
}

const NavIcon = ({ icon, onClick, active }) => (
  <button
    onClick={onClick}
    style={{
      background: active ? 'var(--nav-logo-bg)' : 'transparent',
      border: 'none',
      borderRadius: '50%',
      width: '38px',
      height: '38px',
      display: 'flex',
      justifyContent: 'center',
      alignItems: 'center',
      cursor: 'pointer',
      color: active ? 'var(--primary)' : 'var(--text-muted)',
      transition: 'var(--transition)',
      boxShadow: active ? '0 4px 10px rgba(0,0,0,0.05)' : 'none'
    }}
  >
    {icon}
  </button>
);

export default App;
