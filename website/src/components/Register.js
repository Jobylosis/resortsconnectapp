import React, { useState } from 'react';
import { auth, db } from '../firebase';
import { createUserWithEmailAndPassword, updateProfile, sendEmailVerification } from 'firebase/auth';
import { ref, set } from 'firebase/database';
import { Mail, Lock, User, Phone, ArrowLeft, ArrowRight, ShieldCheck } from 'lucide-react';
import logo from '../assets/ResortConnectLogo.png';

const Register = ({ onBackToLogin }) => {
  const [formData, setFormData] = useState({
    firstName: '',
    middleName: '',
    lastName: '',
    email: '',
    phoneNumber: '',
    password: '',
    confirmPassword: ''
  });
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const validate = () => {
    const { firstName, lastName, email, phoneNumber, password, confirmPassword } = formData;

    if (!firstName || !lastName || !email || !phoneNumber || !password || !confirmPassword) {
      return 'All fields except Middle Name are required';
    }

    const nameRegex = /^[a-zA-Z\s'-]+$/;
    if (!nameRegex.test(firstName) || !nameRegex.test(lastName)) {
      return 'Names can only contain letters';
    }

    const emailRegex = /^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$/;
    if (!emailRegex.test(email)) {
      return 'Enter a valid email address';
    }

    if (phoneNumber.length !== 11 || !phoneNumber.startsWith('09')) {
      return 'Phone number must be 11 digits and start with 09';
    }

    if (password.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!/[A-Z]/.test(password)) return 'Add at least one uppercase letter';
    if (!/[a-z]/.test(password)) return 'Add at least one lowercase letter';
    if (!/[0-9]/.test(password)) return 'Add at least one number';
    if (!/[!@#$%^&*(),.?":{}|<>]/.test(password)) return 'Add at least one special character';

    if (password !== confirmPassword) {
      return 'Passwords do not match';
    }

    return null;
  };

  const generateCustomId = () => {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let id = '';
    for (let i = 0; i < 6; i++) {
      id += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return `RC-${id}`;
  };

  const handleEmojiFilter = (value) => {
    // Regex for various emoji ranges
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
      const userCredential = await createUserWithEmailAndPassword(auth, formData.email, formData.password);
      const user = userCredential.user;

      await sendEmailVerification(user);

      await updateProfile(user, {
        displayName: `${formData.firstName} ${formData.lastName}`
      });

      const customId = generateCustomId();

      await set(ref(db, `users/${user.uid}`), {
        firstName: formData.firstName,
        middleName: formData.middleName,
        lastName: formData.lastName,
        email: formData.email,
        phoneNumber: formData.phoneNumber,
        role: 'Tourist',
        uid: user.uid,
        customId: customId,
        isBanned: false,
        createdAt: Date.now()
      });

      alert('Registration Successful! Please check your email to verify your account.');
      onBackToLogin();
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{
      display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '100vh', width: '100%',
      backgroundImage: 'linear-gradient(rgba(0,15,8,0.7), rgba(0,15,8,0.7)), url("https://images.unsplash.com/photo-1540541338287-41700207dee6?ixlib=rb-4.0.3&auto=format&fit=crop&w=1470&q=80")',
      backgroundSize: 'cover', backgroundPosition: 'center', backgroundAttachment: 'fixed', padding: '40px 20px',
    }}>
      <div className="card view-transition" style={{
        width: '100%', maxWidth: '520px', padding: '48px 40px',
        backgroundColor: 'var(--surface)',
        borderRadius: '32px', boxShadow: '0 30px 60px -12px rgba(0,0,0,0.5)',
        border: '1px solid var(--border)', position: 'relative', overflow: 'hidden'
      }}>
        {/* Accent Bar */}
        <div style={{
          position: 'absolute', top: 0, left: 0, right: 0, height: '6px',
          background: 'linear-gradient(to right, var(--secondary), var(--primary))'
        }}></div>

        <button
          onClick={onBackToLogin}
          style={{
            background: 'none', border: 'none', cursor: 'pointer', display: 'flex',
            alignItems: 'center', gap: '8px', color: 'var(--text-muted)',
            marginBottom: '32px', fontWeight: 700, fontSize: '14px'
          }}
        >
          <ArrowLeft size={18} /> Back to Login
        </button>

        <div style={{ textAlign: 'center', marginBottom: '40px' }}>
          <div style={{
            background: 'var(--card-hover-bg)', padding: '10px', borderRadius: '16px',
            display: 'inline-block', boxShadow: '0 8px 20px rgba(0,0,0,0.05)',
            marginBottom: '16px', border: '1px solid var(--border)'
          }}>
            <img src={logo} alt="Resort Connect Logo" style={{ width: '140px', height: 'auto' }} />
          </div>
          <h2 style={{ margin: 0, fontSize: '26px', fontWeight: 800, color: 'var(--text-main)' }}>Join Resort Connect</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '14px', marginTop: '4px', fontWeight: 500 }}>Start your premium stay experience</p>
        </div>

        <form onSubmit={handleSubmit}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px', marginBottom: '20px' }}>
            <div className="form-group">
              <label className="input-label">First Name</label>
              <div style={{ position: 'relative' }}>
                <User style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
                <input
                  className="input" style={{ paddingLeft: '48px' }} placeholder="Jane"
                  value={formData.firstName} onChange={(e) => setFormData({...formData, firstName: handleEmojiFilter(e.target.value)})} required
                />
              </div>
            </div>
            <div className="form-group">
              <label className="input-label">Middle Name</label>
              <div style={{ position: 'relative' }}>
                <User style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} size={18} />
                <input
                  className="input" style={{ paddingLeft: '48px' }} placeholder="Optional"
                  value={formData.middleName} onChange={(e) => setFormData({...formData, middleName: handleEmojiFilter(e.target.value)})}
                />
              </div>
            </div>
          </div>

          <div style={{ marginBottom: '20px' }}>
            <label className="input-label">Last Name</label>
            <div style={{ position: 'relative' }}>
              <User style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
              <input
                className="input" style={{ paddingLeft: '48px' }} placeholder="Doe"
                value={formData.lastName} onChange={(e) => setFormData({...formData, lastName: handleEmojiFilter(e.target.value)})} required
              />
            </div>
          </div>

          <div style={{ marginBottom: '20px' }}>
            <label className="input-label">Email Address</label>
            <div style={{ position: 'relative' }}>
              <Mail style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
              <input
                type="email" className="input" style={{ paddingLeft: '48px' }} placeholder="jane@example.com"
                value={formData.email} onChange={(e) => setFormData({...formData, email: e.target.value})} required
              />
            </div>
          </div>

          <div style={{ marginBottom: '20px' }}>
            <label className="input-label">Phone Number</label>
            <div style={{ position: 'relative' }}>
              <Phone style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
              <input
                type="tel" className="input" style={{ paddingLeft: '48px' }} placeholder="09XX XXX XXXX" maxLength="11"
                value={formData.phoneNumber} onChange={(e) => setFormData({...formData, phoneNumber: e.target.value.replace(/\D/g, '')})} required
              />
            </div>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px', marginBottom: '32px' }}>
            <div className="form-group">
              <label className="input-label">Password</label>
              <div style={{ position: 'relative' }}>
                <Lock style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
                <input
                  type="password" className="input" style={{ paddingLeft: '48px' }} placeholder="••••••••"
                  value={formData.password} onChange={(e) => setFormData({...formData, password: e.target.value})} required
                />
              </div>
            </div>
            <div className="form-group">
              <label className="input-label">Confirm</label>
              <div style={{ position: 'relative' }}>
                <Lock style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
                <input
                  type="password" className="input" style={{ paddingLeft: '48px' }} placeholder="••••••••"
                  value={formData.confirmPassword} onChange={(e) => setFormData({...formData, confirmPassword: e.target.value})} required
                />
              </div>
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
            {loading ? <div className="loader" style={{ width: '20px', height: '20px', borderTopColor: 'white' }}></div> : (
              <span style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                CREATE MY ACCOUNT <ShieldCheck size={18} />
              </span>
            )}
          </button>

          <p style={{ textAlign: 'center', marginTop: '32px', fontSize: '13px', color: 'var(--text-muted)', fontWeight: 500 }}>
             By registering, you agree to our <strong>Terms</strong> and <strong>Privacy Policy</strong>.
          </p>
        </form>
      </div>
      <style>{`
        .input-label { display: block; font-size: 12px; font-weight: 800; color: var(--text-main); margin-bottom: 8px; text-transform: uppercase; letter-spacing: 0.5px; }
        .view-transition { animation: fadeIn 0.4s ease-out; }
      `}</style>
    </div>
  );
};

export default Register;
