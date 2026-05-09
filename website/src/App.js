import React, { useState, useEffect } from 'react';
import { auth, db } from './firebase';
import { onAuthStateChanged, signOut } from 'firebase/auth';
import { ref, onValue } from 'firebase/database';
import Login from './components/Login';
import Register from './components/Register';
import ForgotPassword from './components/ForgotPassword';
import OwnerDashboard from './components/OwnerDashboard';
import TouristDashboard from './components/TouristDashboard';
import AdminDashboard from './components/AdminDashboard';
import Profile from './components/Profile';
import Notifications from './components/Notifications';
import VerifyEmail from './components/VerifyEmail';
import { LogOut, Bell, User, LayoutDashboard, Menu } from 'lucide-react';
import logo from './assets/ResortConnectLogo.png';

function App() {
  const [user, setUser] = useState(null);
  const [profile, setProfile] = useState(null);
  const [loading, setLoading] = useState(true);
  const [authView, setAuthView] = useState('login');
  const [view, setView] = useState('dashboard');
  const [unreadCount, setUnreadCount] = useState(0);

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

    return () => unsubscribe();
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
    if (authView === 'register') return <Register onBackToLogin={() => setAuthView('login')} />;
    if (authView === 'forgotPassword') return <ForgotPassword onBack={() => setAuthView('login')} />;
    return <Login onShowRegister={() => setAuthView('register')} onShowForgotPassword={() => setAuthView('forgotPassword')} />;
  }

  if (!user.emailVerified) {
    return <VerifyEmail />;
  }

  if (profile?.isBanned) {
    return (
      <div className="app-container" style={{ textAlign: 'center', marginTop: '100px' }}>
        <div className="card" style={{ maxWidth: '500px', margin: '0 auto' }}>
          <h1 style={{ color: 'var(--primary)', marginBottom: '16px' }}>Account Suspended</h1>
          <p style={{ color: 'var(--text-muted)', marginBottom: '24px' }}>Please contact admin at resortconnect2026@gmail.com</p>
          <button className="btn btn-primary" onClick={() => signOut(auth)}>Back to Login</button>
        </div>
      </div>
    );
  }

  const role = (profile?.role || 'Tourist').toUpperCase();

  const renderContent = () => {
    if (view === 'profile') return <Profile onBack={() => setView('dashboard')} />;
    if (view === 'notifications') return <Notifications uid={user.uid} onBack={() => setView('dashboard')} />;

    if (role === 'OWNER') return <OwnerDashboard profile={profile} uid={user.uid} />;
    if (role === 'ADMIN') return <AdminDashboard profile={profile} uid={user.uid} />;
    return <TouristDashboard profile={profile} uid={user.uid} />;
  };

  return (
    <div className="app">
      <header style={{
        backgroundColor: 'rgba(255, 255, 255, 0.8)',
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
        <div style={{ display: 'flex', alignItems: 'center', gap: '14px', cursor: 'pointer' }} onClick={() => setView('dashboard')}>
          <div style={{
            background: 'white',
            padding: '6px',
            borderRadius: '12px',
            boxShadow: '0 4px 12px rgba(0,0,0,0.05)',
            display: 'flex',
            alignItems: 'center'
          }}>
            <img src={logo} alt="Logo" style={{ height: '36px', width: 'auto' }} />
          </div>
          <div className="hide-mobile">
            <h2 style={{ margin: 0, fontSize: '18px', fontWeight: 800, color: '#000', letterSpacing: '-0.5px' }}>Resort Connect</h2>
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
            background: '#F3F4F6',
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

            <NavIcon icon={<User size={19} />} active={view === 'profile'} onClick={() => setView('profile')} />
          </div>

          <div style={{ width: '1px', height: '24px', background: '#E5E7EB' }}></div>

          <button
            onClick={handleLogout}
            style={{
              width: '40px', height: '40px', borderRadius: '50%', border: 'none',
              background: '#FEF2F2', color: 'var(--primary)', cursor: 'pointer',
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
        .logout-btn:hover { background: var(--primary); color: white; transform: rotate(10deg); }
        @media (max-width: 600px) {
          .hide-mobile { display: none; }
        }
      `}</style>
    </div>
  );
}

const NavIcon = ({ icon, onClick, active }) => (
  <button
    onClick={onClick}
    style={{
      background: active ? 'white' : 'transparent',
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
