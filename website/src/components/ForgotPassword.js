import React, { useState } from 'react';
import { auth } from '../firebase';
import { sendPasswordResetEmail } from 'firebase/auth';
import { ArrowLeft, Mail, CheckCircle, HelpCircle } from 'lucide-react';
import logo from '../assets/ResortConnectLogo.png';

const ForgotPassword = ({ onBack }) => {
  const [email, setEmail] = useState('');
  const [error, setError] = useState('');
  const [success, setSuccess] = useState(false);
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      await sendPasswordResetEmail(auth, email);
      setSuccess(true);
    } catch (err) {
      setError(err.message.includes('auth/user-not-found')
        ? 'No account found with this email.'
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
          onClick={onBack}
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
              width: '80px', height: '80px', background: '#ECFDF5',
              borderRadius: '28px', display: 'flex', justifyContent: 'center',
              alignItems: 'center', margin: '0 auto 24px'
            }}>
              <CheckCircle size={40} color="#10B981" />
            </div>
            <h2 style={{ fontSize: '24px', fontWeight: 800, margin: '0 0 12px 0', color: 'var(--text-main)' }}>Check Your Email</h2>
            <p style={{ color: 'var(--text-muted)', fontSize: '15px', lineHeight: '1.6', marginBottom: '32px' }}>
              We've sent a password recovery link to <br/><strong>{email}</strong>
            </p>
            <button className="btn btn-primary" style={{ width: '100%', height: '56px' }} onClick={onBack}>
              RETURN TO LOGIN
            </button>
          </div>
        ) : (
          <>
            <h2 style={{ fontSize: '24px', fontWeight: 800, margin: '0 0 12px 0', color: 'var(--text-main)' }}>Recovery</h2>
            <p style={{ color: 'var(--text-muted)', fontSize: '14px', fontWeight: 500, marginBottom: '32px' }}>
              Enter your email address to receive a <br/>password reset link.
            </p>

            <form onSubmit={handleSubmit} style={{ textAlign: 'left' }}>
              <div style={{ marginBottom: '32px' }}>
                <label className="input-label">Email Address</label>
                <div style={{ position: 'relative' }}>
                  <Mail style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
                  <input
                    type="email" className="input" style={{ paddingLeft: '48px' }}
                    placeholder="name@example.com"
                    value={email} onChange={(e) => setEmail(e.target.value)} required
                  />
                </div>
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
                {loading ? <div className="loader" style={{ width: '20px', height: '20px', borderTopColor: 'white' }}></div> : 'SEND RECOVERY LINK'}
              </button>

              <div style={{ marginTop: '32px', display: 'flex', gap: '10px', alignItems: 'center', justifyContent: 'center', opacity: 0.6 }}>
                 <HelpCircle size={14} />
                 <span style={{ fontSize: '12px', fontWeight: 600 }}>Need help? Contact support</span>
              </div>
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

export default ForgotPassword;
