import React, { useState } from 'react';
import { auth, db } from '../firebase';
import { signInWithEmailAndPassword, GoogleAuthProvider, FacebookAuthProvider, signInWithPopup } from 'firebase/auth';
import { ref, get, set } from 'firebase/database';
import { Mail, Lock, ArrowRight, Eye, EyeOff } from 'lucide-react';
import logo from '../assets/ResortConnectLogo.png';
import bgImage from '../assets/commercial_login.jpg';

const Login = ({ onShowRegister, onShowForgotPassword, onGoHome }) => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [showPassword, setShowPassword] = useState(false);

  const validate = () => {
    if (!email || !email.trim() || !password || !password.trim()) return 'Please enter both email and password';
    const emailRegex = /^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$/;
    if (!emailRegex.test(email)) return 'Enter a valid email address';
    return null;
  };

  const handleEmojiFilter = (value) => {
    const emojiRegex = /[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]/gu;
    return value.replace(emojiRegex, '');
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    const validationError = validate();
    if (validationError) {
      setError(validationError);
      return;
    }

    setError('');
    setLoading(true);
    try {
      await signInWithEmailAndPassword(auth, email, password);
    } catch (err) {
      setError(err.message.includes('auth/invalid-credential')
        ? 'Invalid email or password'
        : 'An error occurred. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  const handleSocialLogin = async (providerName) => {
    setError('');
    setLoading(true);
    let provider;
    if (providerName === 'google') {
      provider = new GoogleAuthProvider();
    } else if (providerName === 'facebook') {
      provider = new FacebookAuthProvider();
    }
    
    try {
      const result = await signInWithPopup(auth, provider);
      const user = result.user;
      
      const userRef = ref(db, `users/${user.uid}`);
      const snapshot = await get(userRef);
      
      if (!snapshot.exists()) {
        // App.js will detect missing profile and route to complete registration
      }
    } catch (err) {
      setError(err.message || 'An error occurred during social login.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{
      display: 'flex',
      justifyContent: 'center',
      alignItems: 'center',
      minHeight: '100vh',
      width: '100%',
      backgroundImage: `linear-gradient(rgba(0,15,8,0.7), rgba(0,15,8,0.7)), url(${bgImage})`,
      backgroundSize: 'cover',
      backgroundPosition: 'center',
      padding: '20px',
    }}>
      <div className="card" style={{
        width: '100%',
        maxWidth: '440px',
        padding: '48px 40px',
        backgroundColor: 'var(--surface)',
        borderRadius: '32px',
        boxShadow: '0 30px 60px -12px rgba(0,0,0,0.5)',
        border: '1px solid var(--border)',
        textAlign: 'center',
        position: 'relative',
        overflow: 'hidden'
      }}>
        {/* Accent Bar */}
        <div style={{
          position: 'absolute', top: 0, left: 0, right: 0, height: '6px',
          background: 'linear-gradient(to right, var(--primary), var(--secondary))'
        }}></div>

        <div style={{ marginBottom: '40px' }}>
          <div onClick={onGoHome} style={{ cursor: 'pointer', display: 'inline-block' }}>
            <img src={logo} alt="Logo" style={{ width: '280px', height: 'auto', marginBottom: '16px' }} />
          </div>
          <h2 style={{ fontSize: '24px', fontWeight: 800, margin: '0 0 8px 0', color: 'var(--text-main)' }}>Welcome Back</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '14px', fontWeight: 500 }}>
            Login to manage your resort connections
          </p>
        </div>

        <form onSubmit={handleSubmit} style={{ textAlign: 'left' }}>
          <div style={{ marginBottom: '24px' }}>
            <label style={{ display: 'block', marginBottom: '8px', fontSize: '13px', fontWeight: 700, color: 'var(--text-main)' }}>Email Address</label>
            <div style={{ position: 'relative' }}>
              <Mail style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
              <input
                type="email"
                className="input"
                placeholder="name@example.com"
                style={{ paddingLeft: '48px' }}
                value={email} onChange={(e) => setEmail(handleEmojiFilter(e.target.value))} required
              />
            </div>
          </div>

          <div style={{ marginBottom: '16px' }}>
            <label style={{ display: 'block', marginBottom: '8px', fontSize: '13px', fontWeight: 700, color: 'var(--text-main)' }}>Password</label>
            <div style={{ position: 'relative' }}>
              <Lock style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
              <input
                type={showPassword ? 'text' : 'password'}
                className="input"
                placeholder="••••••••"
                style={{ paddingLeft: '48px', paddingRight: '48px' }}
                value={password} onChange={(e) => setPassword(handleEmojiFilter(e.target.value))} required
              />
              <button
                type="button"
                onClick={() => setShowPassword(p => !p)}
                style={{ position: 'absolute', right: '14px', top: '50%', transform: 'translateY(-50%)', background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)', display: 'flex', alignItems: 'center', padding: '4px' }}
                tabIndex={-1}
              >
                {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
              </button>
            </div>
          </div>

          <div style={{ textAlign: 'right', marginBottom: '32px' }}>
            <button
              type="button"
              onClick={onShowForgotPassword}
              style={{ background: 'none', border: 'none', color: 'var(--primary)', fontSize: '13px', cursor: 'pointer', fontWeight: 700 }}
            >
              Forgot Password?
            </button>
          </div>

          {error && (
            <div style={{
              backgroundColor: '#FEF2F2', color: '#B91C1C', padding: '14px',
              borderRadius: '12px', fontSize: '13px', marginBottom: '24px',
              textAlign: 'center', border: '1px solid #FEE2E2', fontWeight: 600
            }}>
              {error}
            </div>
          )}

          <button
            type="submit"
            className="btn btn-primary"
            style={{ width: '100%', height: '56px', fontSize: '16px', marginBottom: '16px' }}
            disabled={loading}
          >
            {loading ? <div className="loader" style={{ width: '20px', height: '20px', borderTopColor: 'white' }}></div> : (
              <span style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                LOGIN NOW <ArrowRight size={18} />
              </span>
            )}
          </button>

          <div style={{ display: 'flex', alignItems: 'center', margin: '24px 0' }}>
            <div style={{ flex: 1, height: '1px', background: 'var(--border)' }}></div>
            <span style={{ padding: '0 16px', color: 'var(--text-muted)', fontSize: '12px', fontWeight: 600 }}>OR CONTINUE WITH</span>
            <div style={{ flex: 1, height: '1px', background: 'var(--border)' }}></div>
          </div>

          <div style={{ display: 'flex', gap: '16px' }}>
            <button
              type="button"
              onClick={() => handleSocialLogin('google')}
              style={{
                flex: 1, height: '48px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '10px',
                background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: '12px',
                color: 'var(--text-main)', fontSize: '14px', fontWeight: 600, cursor: 'pointer', transition: 'var(--transition)'
              }}
              onMouseOver={e => e.currentTarget.style.background = 'var(--light-bg)'}
              onMouseOut={e => e.currentTarget.style.background = 'var(--surface)'}
            >
              <img src="https://www.svgrepo.com/show/475656/google-color.svg" alt="Google" style={{ width: '20px', height: '20px' }} />
              Google
            </button>
            <button
              type="button"
              onClick={() => handleSocialLogin('facebook')}
              style={{
                flex: 1, height: '48px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '10px',
                background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: '12px',
                color: 'var(--text-main)', fontSize: '14px', fontWeight: 600, cursor: 'pointer', transition: 'var(--transition)'
              }}
              onMouseOver={e => e.currentTarget.style.background = 'var(--light-bg)'}
              onMouseOut={e => e.currentTarget.style.background = 'var(--surface)'}
            >
              <img src="https://www.svgrepo.com/show/475647/facebook-color.svg" alt="Facebook" style={{ width: '20px', height: '20px' }} />
              Facebook
            </button>
          </div>

          <div style={{ textAlign: 'center', marginTop: '32px' }}>
            <p style={{ color: 'var(--text-muted)', fontSize: '14px' }}>
              Don't have an account? {' '}
              <button
                type="button"
                onClick={onShowRegister}
                style={{
                  background: 'none', border: 'none', color: 'var(--secondary)',
                  cursor: 'pointer', fontWeight: 800, fontSize: '14px'
                }}
              >
                Create Account
              </button>
            </p>
          </div>
        </form>
      </div>
    </div>
  );
};

export default Login;
