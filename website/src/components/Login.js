import React, { useState } from 'react';
import { auth } from '../firebase';
import { signInWithEmailAndPassword } from 'firebase/auth';
import { Mail, Lock, ArrowRight } from 'lucide-react';
import logo from '../assets/ResortConnectLogo.png';

const Login = ({ onShowRegister, onShowForgotPassword }) => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
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

  return (
    <div style={{
      display: 'flex',
      justifyContent: 'center',
      alignItems: 'center',
      minHeight: '100vh',
      width: '100%',
      backgroundImage: 'linear-gradient(rgba(0,15,8,0.7), rgba(0,15,8,0.7)), url("https://images.unsplash.com/photo-1540541338287-41700207dee6?ixlib=rb-4.0.3&auto=format&fit=crop&w=1470&q=80")',
      backgroundSize: 'cover',
      backgroundPosition: 'center',
      padding: '20px',
    }}>
      <div className="card" style={{
        width: '100%',
        maxWidth: '440px',
        padding: '48px 40px',
        backgroundColor: 'rgba(255, 255, 255, 0.98)',
        borderRadius: '32px',
        boxShadow: '0 30px 60px -12px rgba(0,0,0,0.5)',
        border: 'none',
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
          <div style={{
            background: 'white',
            padding: '12px',
            borderRadius: '20px',
            display: 'inline-block',
            boxShadow: '0 10px 20px rgba(0,0,0,0.05)',
            marginBottom: '16px'
          }}>
            <img src={logo} alt="Logo" style={{ width: '200px', height: 'auto' }} />
          </div>
          <h2 style={{ fontSize: '24px', fontWeight: 800, margin: '0 0 8px 0', color: '#000' }}>Welcome Back</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '14px', fontWeight: 500 }}>
            Login to manage your resort connections
          </p>
        </div>

        <form onSubmit={handleSubmit} style={{ textAlign: 'left' }}>
          <div style={{ marginBottom: '24px' }}>
            <label style={{ display: 'block', marginBottom: '8px', fontSize: '13px', fontWeight: 700, color: '#374151' }}>Email Address</label>
            <div style={{ position: 'relative' }}>
              <Mail style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
              <input
                type="email"
                className="input"
                placeholder="name@example.com"
                style={{ paddingLeft: '48px' }}
                value={email} onChange={(e) => setEmail(e.target.value)} required
              />
            </div>
          </div>

          <div style={{ marginBottom: '16px' }}>
            <label style={{ display: 'block', marginBottom: '8px', fontSize: '13px', fontWeight: 700, color: '#374151' }}>Password</label>
            <div style={{ position: 'relative' }}>
              <Lock style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
              <input
                type="password"
                className="input"
                placeholder="••••••••"
                style={{ paddingLeft: '48px' }}
                value={password} onChange={(e) => setPassword(e.target.value)} required
              />
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
            style={{ width: '100%', height: '56px', fontSize: '16px' }}
            disabled={loading}
          >
            {loading ? <div className="loader" style={{ width: '20px', height: '20px', borderTopColor: 'white' }}></div> : (
              <span style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                LOGIN NOW <ArrowRight size={18} />
              </span>
            )}
          </button>

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
