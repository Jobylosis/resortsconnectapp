import React, { useState } from 'react';
import { auth } from '../firebase';
import { confirmPasswordReset } from 'firebase/auth';
import { ArrowLeft, Lock, CheckCircle, Eye, EyeOff } from 'lucide-react';
import logo from '../assets/ResortConnectLogo.png';

const ResetPassword = ({ oobCode, onBackToLogin }) => {
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [error, setError] = useState('');
  const [success, setSuccess] = useState(false);
  const [loading, setLoading] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);

  const validate = () => {
    if (password.length < 8) return 'Password must be at least 8 characters';
    if (!/[A-Z]/.test(password)) return 'Add at least one uppercase letter';
    if (!/[a-z]/.test(password)) return 'Add at least one lowercase letter';
    if (!/[0-9]/.test(password)) return 'Add at least one number';
    if (!/[!@#$%^&*(),.?":{}|<>]/.test(password)) return 'Add at least one special character';
    if (password !== confirmPassword) return 'Passwords do not match';
    return null;
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
      await confirmPasswordReset(auth, oobCode, password);
      setSuccess(true);
    } catch (err) {
      setError(err.message.includes('auth/invalid-action-code') 
        ? 'This reset link is invalid or has expired. Please request a new one.' 
        : 'An error occurred. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{
      display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '100vh', width: '100%',
      backgroundImage: 'linear-gradient(rgba(0,15,8,0.7), rgba(0,15,8,0.7)), url("https://images.unsplash.com/photo-1540541338287-41700207dee6?ixlib=rb-4.0.3&auto=format&fit=crop&w=1470&q=80")',
      backgroundSize: 'cover', backgroundPosition: 'center', padding: '20px',
    }}>
      <div className="card view-transition" style={{
        width: '100%', maxWidth: '440px', padding: '48px 40px',
        backgroundColor: 'var(--surface)',
        borderRadius: '32px', boxShadow: '0 30px 60px -12px rgba(0,0,0,0.5)',
        border: '1px solid var(--border)', position: 'relative', overflow: 'hidden', textAlign: 'center'
      }}>
        {/* Accent Bar */}
        <div style={{
          position: 'absolute', top: 0, left: 0, right: 0, height: '6px',
          background: 'linear-gradient(to right, var(--primary), var(--secondary))'
        }}></div>

        <button
          onClick={onBackToLogin}
          style={{
            background: 'none', border: 'none', cursor: 'pointer', display: 'flex',
            alignItems: 'center', gap: '8px', color: 'var(--text-muted)',
            marginBottom: '32px', fontWeight: 700, fontSize: '14px', padding: 0
          }}
        >
          <ArrowLeft size={18} /> Back to Login
        </button>

        <div style={{ marginBottom: '32px' }}>
          <img src={logo} alt="Logo" style={{ width: '280px', height: 'auto', marginBottom: '20px' }} />
        </div>

        {success ? (
          <div className="view-transition">
            <div style={{
              width: '80px', height: '80px', background: 'rgba(16, 185, 129, 0.1)',
              borderRadius: '28px', display: 'flex', justifyContent: 'center',
              alignItems: 'center', margin: '0 auto 24px'
            }}>
              <CheckCircle size={40} color="#10B981" />
            </div>
            <h2 style={{ fontSize: '24px', fontWeight: 800, margin: '0 0 12px 0', color: 'var(--text-main)' }}>Success!</h2>
            <p style={{ color: 'var(--text-muted)', fontSize: '15px', lineHeight: '1.6', marginBottom: '32px' }}>
              Your password has been reset successfully.<br/>You can now log in.
            </p>
            <button className="btn btn-primary" style={{ width: '100%', height: '56px' }} onClick={onBackToLogin}>
              PROCEED TO LOGIN
            </button>
          </div>
        ) : (
          <>
            <h2 style={{ fontSize: '24px', fontWeight: 800, margin: '0 0 12px 0', color: 'var(--text-main)' }}>New Password</h2>
            <p style={{ color: 'var(--text-muted)', fontSize: '14px', fontWeight: 500, marginBottom: '32px' }}>
              Enter your new secure password below.
            </p>

            <form onSubmit={handleSubmit} style={{ textAlign: 'left' }}>
              
              <div style={{ marginBottom: '20px' }}>
                <label className="input-label">New Password</label>
                <div style={{ position: 'relative' }}>
                  <Lock style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
                  <input
                    type={showPassword ? 'text' : 'password'} className="input" style={{ paddingLeft: '48px', paddingRight: '48px' }} placeholder="••••••••"
                    value={password} onChange={(e) => { setPassword(e.target.value); setError(''); }} required
                  />
                  <button type="button" onClick={() => setShowPassword(p => !p)} tabIndex={-1}
                    style={{ position: 'absolute', right: '14px', top: '50%', transform: 'translateY(-50%)', background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)', display: 'flex', alignItems: 'center', padding: '4px' }}>
                    {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                  </button>
                </div>
              </div>

              <div style={{ marginBottom: '32px' }}>
                <label className="input-label">Confirm Password</label>
                <div style={{ position: 'relative' }}>
                  <Lock style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
                  <input
                    type={showConfirmPassword ? 'text' : 'password'} className="input" style={{ paddingLeft: '48px', paddingRight: '48px' }} placeholder="••••••••"
                    value={confirmPassword} onChange={(e) => { setConfirmPassword(e.target.value); setError(''); }} required
                  />
                  <button type="button" onClick={() => setShowConfirmPassword(p => !p)} tabIndex={-1}
                    style={{ position: 'absolute', right: '14px', top: '50%', transform: 'translateY(-50%)', background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)', display: 'flex', alignItems: 'center', padding: '4px' }}>
                    {showConfirmPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                  </button>
                </div>
              </div>

              {error && (
                <div style={{
                  backgroundColor: 'rgba(239, 68, 68, 0.1)', color: '#B91C1C', padding: '14px',
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
                disabled={loading || !password || !confirmPassword}
              >
                {loading ? <div className="loader" style={{ width: '20px', height: '20px', borderTopColor: 'white' }}></div> : 'RESET PASSWORD'}
              </button>
            </form>
          </>
        )}
      </div>
      <style>{`
        .input-label { display: block; font-size: 12px; font-weight: 800; color: var(--text-main); margin-bottom: 8px; text-transform: uppercase; letter-spacing: 0.5px; }
        .view-transition { animation: fadeIn 0.4s ease-out; }
      `}</style>
    </div>
  );
};

export default ResetPassword;
