import React, { useState } from 'react';
import { auth, db } from '../firebase';
import { createUserWithEmailAndPassword, updateProfile, sendEmailVerification } from 'firebase/auth';
import { ref, set } from 'firebase/database';
import { Mail, Lock, User, Phone, ArrowLeft, ArrowRight, ShieldCheck } from 'lucide-react';
import logo from '../assets/ResortConnectLogo.png';

const Register = ({ onBackToLogin, onGoHome }) => {
  const [formData, setFormData] = useState({
    firstName: '',
    middleName: '',
    lastName: '',
    email: '',
    phoneNumber: '',
    password: '',
    confirmPassword: ''
  });
  const [errors, setErrors] = useState({});
  const [loading, setLoading] = useState(false);

  const validate = () => {
    const { firstName, lastName, email, phoneNumber, password, confirmPassword } = formData;
    const newErrors = {};

    if (!firstName) newErrors.firstName = 'First Name is required';
    if (!lastName) newErrors.lastName = 'Last Name is required';
    if (!email) newErrors.email = 'Email is required';
    if (!phoneNumber) newErrors.phoneNumber = 'Phone Number is required';
    if (!password) newErrors.password = 'Password is required';
    if (!confirmPassword) newErrors.confirmPassword = 'Confirm Password is required';

    const nameRegex = /^[a-zA-Z\s'-]+$/;
    if (firstName && !nameRegex.test(firstName)) newErrors.firstName = 'Names can only contain letters';
    if (lastName && !nameRegex.test(lastName)) newErrors.lastName = 'Names can only contain letters';

    const emailRegex = /^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$/;
    if (email && !emailRegex.test(email)) newErrors.email = 'Enter a valid email address';

    if (phoneNumber && (phoneNumber.length !== 11 || !phoneNumber.startsWith('09'))) {
      newErrors.phoneNumber = 'Phone number must be 11 digits and start with 09';
    }

    if (password) {
      if (password.length < 8) {
        newErrors.password = 'Password must be at least 8 characters';
      } else if (!/[A-Z]/.test(password)) {
        newErrors.password = 'Add at least one uppercase letter';
      } else if (!/[a-z]/.test(password)) {
        newErrors.password = 'Add at least one lowercase letter';
      } else if (!/[0-9]/.test(password)) {
        newErrors.password = 'Add at least one number';
      } else if (!/[!@#$%^&*(),.?":{}|<>]/.test(password)) {
        newErrors.password = 'Add at least one special character';
      }
    }

    if (confirmPassword && password !== confirmPassword) {
      newErrors.confirmPassword = 'Passwords do not match';
    }

    return Object.keys(newErrors).length > 0 ? newErrors : null;
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
    const validationErrors = validate();
    if (validationErrors) {
      setErrors(validationErrors);
      return;
    }

    setErrors({});
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
      setErrors({ global: err.message });
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
          <div onClick={onGoHome} style={{ cursor: 'pointer', display: 'inline-block' }}>
            <img src={logo} alt="Resort Connect Logo" style={{ width: '280px', height: 'auto', marginBottom: '16px' }} />
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
                  className="input" style={{ paddingLeft: '48px', borderColor: errors.firstName ? '#ef4444' : undefined }} placeholder="Jane"
                  value={formData.firstName} onChange={(e) => { setFormData({...formData, firstName: handleEmojiFilter(e.target.value)}); setErrors({...errors, firstName: null}); }}
                />
              </div>
              {errors.firstName && <div style={{color: '#ef4444', fontSize: '12px', marginTop: '6px', fontWeight: 600}}>⬆ {errors.firstName}</div>}
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
                className="input" style={{ paddingLeft: '48px', borderColor: errors.lastName ? '#ef4444' : undefined }} placeholder="Doe"
                value={formData.lastName} onChange={(e) => { setFormData({...formData, lastName: handleEmojiFilter(e.target.value)}); setErrors({...errors, lastName: null}); }}
              />
            </div>
            {errors.lastName && <div style={{color: '#ef4444', fontSize: '12px', marginTop: '6px', fontWeight: 600}}>⬆ {errors.lastName}</div>}
          </div>

          <div style={{ marginBottom: '20px' }}>
            <label className="input-label">Email Address</label>
            <div style={{ position: 'relative' }}>
              <Mail style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
              <input
                type="email" className="input" style={{ paddingLeft: '48px', borderColor: errors.email ? '#ef4444' : undefined }} placeholder="jane@example.com"
                value={formData.email} onChange={(e) => { setFormData({...formData, email: e.target.value}); setErrors({...errors, email: null}); }}
              />
            </div>
            {errors.email && <div style={{color: '#ef4444', fontSize: '12px', marginTop: '6px', fontWeight: 600}}>⬆ {errors.email}</div>}
          </div>

          <div style={{ marginBottom: '20px' }}>
            <label className="input-label">Phone Number</label>
            <div style={{ position: 'relative' }}>
              <Phone style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
              <input
                type="tel" className="input" style={{ paddingLeft: '48px', borderColor: errors.phoneNumber ? '#ef4444' : undefined }} placeholder="09XX XXX XXXX" maxLength="11"
                value={formData.phoneNumber} onChange={(e) => { setFormData({...formData, phoneNumber: e.target.value.replace(/\D/g, '')}); setErrors({...errors, phoneNumber: null}); }}
              />
            </div>
            {errors.phoneNumber && <div style={{color: '#ef4444', fontSize: '12px', marginTop: '6px', fontWeight: 600}}>⬆ {errors.phoneNumber}</div>}
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px', marginBottom: '32px' }}>
            <div className="form-group">
              <label className="input-label">Password</label>
              <div style={{ position: 'relative' }}>
                <Lock style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
                <input
                  type="password" className="input" style={{ paddingLeft: '48px', borderColor: errors.password ? '#ef4444' : undefined }} placeholder="••••••••"
                  value={formData.password} onChange={(e) => { setFormData({...formData, password: e.target.value}); setErrors({...errors, password: null}); }}
                />
              </div>
              {errors.password && <div style={{color: '#ef4444', fontSize: '12px', marginTop: '6px', fontWeight: 600}}>⬆ {errors.password}</div>}
            </div>
            <div className="form-group">
              <label className="input-label">Confirm</label>
              <div style={{ position: 'relative' }}>
                <Lock style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
                <input
                  type="password" className="input" style={{ paddingLeft: '48px', borderColor: errors.confirmPassword ? '#ef4444' : undefined }} placeholder="••••••••"
                  value={formData.confirmPassword} onChange={(e) => { setFormData({...formData, confirmPassword: e.target.value}); setErrors({...errors, confirmPassword: null}); }}
                />
              </div>
              {errors.confirmPassword && <div style={{color: '#ef4444', fontSize: '12px', marginTop: '6px', fontWeight: 600}}>⬆ {errors.confirmPassword}</div>}
            </div>
          </div>

          {errors.global && (
            <div style={{
              backgroundColor: '#FEF2F2', color: '#B91C1C', padding: '14px',
              borderRadius: '12px', fontSize: '13px', marginBottom: '24px',
              textAlign: 'center', border: '1px solid #FEE2E2', fontWeight: 600
            }}>
              {errors.global}
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
