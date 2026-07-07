import React, { useEffect, useState } from 'react';
import { auth } from '../firebase';
import { sendEmailVerification, signOut } from 'firebase/auth';
import { Mail, RotateCw, LogOut, BadgeCheck } from 'lucide-react';

const VerifyEmail = () => {
  const [resending, setResending] = useState(false);
  const [message, setMessage] = useState('');
  const [verified, setVerified] = useState(false);

  useEffect(() => {
    let interval;
    if (!verified) {
      interval = setInterval(async () => {
        if (auth.currentUser) {
          await auth.currentUser.reload();
          if (auth.currentUser.emailVerified) {
            clearInterval(interval);
            setVerified(true);
          }
        }
      }, 3000);
    }
    return () => { if (interval) clearInterval(interval); };
  }, [verified]);

  const handleResend = async () => {
    if (resending) return;
    setResending(true);
    try {
      await sendEmailVerification(auth.currentUser);
      setMessage('Verification email resent! Please check your inbox.');
      setTimeout(() => setMessage(''), 5000);
    } catch (error) {
      console.error(error);
      setMessage('Too many requests. Please try again later.');
    } finally {
      setResending(false);
    }
  };

  if (verified) {
    return (
      <div className="app-container" style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '80vh' }}>
        <div className="card view-transition" style={{ maxWidth: '480px', textAlign: 'center', padding: '48px 32px' }}>
          <div style={{
            width: '80px', height: '80px', background: 'rgba(16, 185, 129, 0.1)',
            borderRadius: '24px', display: 'flex', justifyContent: 'center',
            alignItems: 'center', margin: '0 auto 32px'
          }}>
            <BadgeCheck size={40} color="#10B981" />
          </div>

          <h2 style={{ fontSize: '28px', fontWeight: 800, marginBottom: '16px', letterSpacing: '-0.5px' }}>Email Verified!</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '16px', lineHeight: '1.6', marginBottom: '32px' }}>
            Welcome to Resort Connect! Your email has been successfully verified. You can now log in and start exploring amazing resorts.
          </p>

          <button
            className="btn btn-primary"
            style={{ width: '100%' }}
            onClick={() => signOut(auth)}
          >
            PROCEED TO LOGIN
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="app-container" style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '80vh' }}>
      <div className="card view-transition" style={{ maxWidth: '480px', textAlign: 'center', padding: '48px 32px' }}>
        <div style={{
          width: '80px', height: '80px', background: 'rgba(29, 211, 176, 0.1)',
          borderRadius: '24px', display: 'flex', justifyContent: 'center',
          alignItems: 'center', margin: '0 auto 32px'
        }}>
          <Mail size={40} color="var(--secondary)" />
        </div>

        <h2 style={{ fontSize: '28px', fontWeight: 800, marginBottom: '16px', letterSpacing: '-0.5px' }}>Verify your email</h2>
        <p style={{ color: 'var(--text-muted)', fontSize: '16px', lineHeight: '1.6', marginBottom: '32px' }}>
          We've sent a verification link to <strong>{auth.currentUser?.email}</strong>.
          Please click the link in that email to confirm your account and continue.
        </p>

        {message && (
          <div style={{
            background: 'rgba(29, 211, 176, 0.1)', color: '#065F46',
            padding: '12px', borderRadius: '12px', marginBottom: '24px',
            fontSize: '14px', fontWeight: 600
          }}>
            {message}
          </div>
        )}

        <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', color: 'var(--secondary)', fontWeight: 700, marginBottom: '20px' }}>
             <RotateCw size={16} className="loader" style={{ animation: 'spin 2s linear infinite' }} />
             Waiting for verification...
          </div>

          <button
            className="btn btn-primary"
            style={{ width: '100%' }}
            onClick={handleResend}
            disabled={resending}
          >
            {resending ? 'RESENDING...' : 'RESEND VERIFICATION EMAIL'}
          </button>

          <button
            className="btn"
            style={{ width: '100%', background: 'var(--light-bg)', color: 'var(--text-main)', border: '1px solid var(--border)' }}
            onClick={() => signOut(auth)}
          >
            <LogOut size={18} /> BACK TO LOGIN
          </button>
        </div>
      </div>
      <style>{`
        @keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
      `}</style>
    </div>
  );
};

export default VerifyEmail;
