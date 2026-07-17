import React, { useState, useEffect } from 'react';
import { auth, db } from '../firebase';
import { ref, onValue, update } from 'firebase/database';
import { User, Phone, BadgeCheck, Camera, Save, ArrowLeft, Mail, Wallet, UserCircle, ShieldAlert } from 'lucide-react';

const Profile = ({ onBack }) => {
  const [profile, setProfile] = useState({
    firstName: '',
    middleName: '',
    lastName: '',
    phoneNumber: '',
    gcashNumber: '',
    gcashName: '',
    profilePicUrl: '',
    customId: ''
  });
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);

  const [toast, setToast] = useState(null);

  const showToast = (message, isError = false) => {
    setToast({ message, isError });
    setTimeout(() => setToast(null), 3000);
  };

  useEffect(() => {
    const user = auth.currentUser;
    if (!user) return;

    const userRef = ref(db, `users/${user.uid}`);
    const unsubscribe = onValue(userRef, (snapshot) => {
      if (snapshot.exists()) {
        const data = snapshot.val();
        setProfile(prev => ({ ...prev, ...data }));
      }
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  const handleUpload = async (e) => {
    const file = e.target.files[0];
    if (!file) return;

    setUploading(true);
    const formData = new FormData();
    formData.append('file', file);
    formData.append('upload_preset', 'resort_unsigned');

    try {
      const response = await fetch('https://api.cloudinary.com/v1_1/dnv6ezitm/image/upload', {
        method: 'POST',
        body: formData,
      });
      const data = await response.json();
      setProfile({ ...profile, profilePicUrl: data.secure_url });
    } catch (error) {
      showToast('Upload failed', true);
    } finally {
      setUploading(false);
    }
  };

  const handleEmojiFilter = (value) => {
    const emojiRegex = /[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]/gu;
    return value.replace(emojiRegex, '');
  };

  const validate = () => {
    const { firstName, lastName, phoneNumber, gcashNumber } = profile;
    const nameRegex = /^[a-zA-Z\s]+$/;
    if (!firstName || !firstName.trim() || !lastName || !lastName.trim()) return 'First and last names are required';
    if (firstName.length < 2 || lastName.length < 2) return 'Names must be at least 2 characters';
    if (!nameRegex.test(firstName) || !nameRegex.test(lastName)) return 'Names can only contain letters and spaces';

    if (phoneNumber && (phoneNumber.length !== 11 || !phoneNumber.startsWith('09'))) {
      return 'Phone number must be 11 digits and start with 09';
    }

    if (gcashNumber && (gcashNumber.length !== 11 || !gcashNumber.startsWith('09'))) {
      return 'GCash number must be 11 digits and start with 09';
    }

    return null;
  };

  const handleSave = async (e) => {
    e.preventDefault();
    const validationError = validate();
    if (validationError) {
      showToast(validationError, true);
      return;
    }
    setSaving(true);
    try {
      const user = auth.currentUser;
      const updatePayload = {
        firstName: profile.firstName || '',
        lastName: profile.lastName || '',
        phoneNumber: profile.phoneNumber || '',
        gcashNumber: profile.gcashNumber || '',
        gcashName: profile.gcashName || '',
        profilePicUrl: profile.profilePicUrl || ''
      };

      await update(ref(db, `users/${user.uid}`), updatePayload);

      if (profile.role === 'Owner') {
        await update(ref(db, `properties/${user.uid}`), {
          gcashNumber: profile.gcashNumber || '',
          gcashName: profile.gcashName || ''
        });
      }
      showToast('Profile updated successfully!');
      // if (onBack) setTimeout(() => onBack(), 1000); // Only auto-back if needed, maybe not
    } catch (error) {
      showToast('Update failed: ' + error.message, true);
    } finally {
      setSaving(false);
    }
  };

  if (loading) return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '60vh' }}>
      <div className="loader"></div>
    </div>
  );

  return (
    <div className="view-transition" style={{ maxWidth: '650px', margin: '0 auto', paddingBottom: '60px' }}>
      <button
        onClick={onBack}
        style={{
          display: 'flex', alignItems: 'center', gap: '8px',
          background: 'var(--surface)', cursor: 'pointer',
          marginBottom: '32px', color: 'var(--text-main)',
          fontWeight: 700, padding: '10px 18px', borderRadius: '14px',
          boxShadow: 'var(--shadow)', border: '1px solid var(--border)'
        }}
      >
        <ArrowLeft size={18} /> Back to Dashboard
      </button>

      <div style={{ textAlign: 'center', marginBottom: '40px' }}>
        <div style={{ position: 'relative', display: 'inline-block' }}>
          <div style={{
            width: '140px', height: '140px', borderRadius: '45px', overflow: 'hidden',
            background: 'var(--surface)', border: '5px solid var(--surface)', boxShadow: '0 15px 35px rgba(0,0,0,0.1)',
            transform: 'rotate(-3deg)'
          }}>
            {profile.profilePicUrl ? (
              <img src={profile.profilePicUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
            ) : (
              <div style={{ width: '100%', height: '100%', display: 'flex', justifyContent: 'center', alignItems: 'center', color: 'var(--text-muted)', background: 'var(--light-bg)' }}>
                <User size={72} />
              </div>
            )}
          </div>
          <label style={{
            position: 'absolute', bottom: '0px', right: '-10px',
            background: 'var(--secondary)', color: '#002D24', borderRadius: '18px',
            width: '44px', height: '44px', display: 'flex', justifyContent: 'center',
            alignItems: 'center', cursor: 'pointer', border: '4px solid var(--surface)',
            boxShadow: '0 8px 15px rgba(29, 211, 176, 0.3)',
            transition: 'var(--transition)'
          }} className="camera-btn">
            {uploading ? <div className="loader small" style={{ width: '16px', height: '16px' }}></div> : <Camera size={20} />}
            <input type="file" hidden accept="image/*" onChange={handleUpload} disabled={uploading} />
          </label>
        </div>
        <h2 style={{ marginTop: '24px', marginBottom: '4px', fontSize: '28px', fontWeight: 800 }}>{profile.firstName} {profile.lastName}</h2>
        {profile.customId && (
          <div style={{ color: 'var(--secondary)', fontWeight: 800, fontSize: '18px', marginBottom: '8px', letterSpacing: '1px' }}>
            {profile.customId}
          </div>
        )}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px', color: 'var(--text-muted)', fontSize: '14px', fontWeight: 600 }}>
           <Mail size={14} /> {profile.email}
        </div>
        {profile.totalOutstandingBalance !== undefined && profile.totalOutstandingBalance > 0 && (
          <div style={{ marginTop: '20px', background: 'rgba(239, 68, 68, 0.1)', padding: '12px 24px', borderRadius: '20px', border: '1px solid rgba(239, 68, 68, 0.2)', display: 'inline-flex', alignItems: 'center', gap: '12px', boxShadow: '0 4px 12px rgba(239, 68, 68, 0.05)' }}>
            <div style={{ background: 'rgba(239, 68, 68, 0.1)', padding: '10px', borderRadius: '50%' }}>
              <Wallet size={24} color="#DC2626" />
            </div>
            <div style={{ textAlign: 'left' }}>
              <p style={{ margin: 0, fontSize: '11px', fontWeight: 800, color: '#EF4444', textTransform: 'uppercase', letterSpacing: '0.5px' }}>Outstanding Balance</p>
              <h3 style={{ margin: '2px 0 0 0', fontSize: '22px', fontWeight: 900, color: '#DC2626' }}>₱{profile.totalOutstandingBalance.toLocaleString()}</h3>
            </div>
          </div>
        )}
      </div>

      <form onSubmit={handleSave}>
        {profile.identityStatus === 'rejected' && (
          <div className="card" style={{ padding: '32px', marginBottom: '24px', background: 'rgba(239, 68, 68, 0.05)', border: '1px solid rgba(239, 68, 68, 0.2)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '8px' }}>
               <ShieldAlert size={22} color="#EF4444" />
               <h4 style={{ margin: 0, fontSize: '18px', fontWeight: 800, color: '#DC2626' }}>ID Verification Rejected</h4>
            </div>
            <p style={{ fontSize: '14px', color: '#B91C1C', marginBottom: '20px' }}>
              <strong>Reason:</strong> {profile.idRejectionReason || 'Your ID could not be verified.'}
            </p>
            <div className="form-group">
              <label className="label">Upload New ID (Government Issued)</label>
              <div style={{ display: 'flex', gap: '10px', alignItems: 'center' }}>
                <label className="btn btn-secondary" style={{ cursor: 'pointer', padding: '10px 20px', fontSize: '14px' }}>
                  {uploading ? 'Uploading...' : 'Choose File'}
                  <input type="file" hidden accept="image/*" onChange={async (e) => {
                    const file = e.target.files[0];
                    if (!file) return;
                    setUploading(true);
                    const formData = new FormData();
                    formData.append('file', file);
                    formData.append('upload_preset', 'resort_unsigned');
                    try {
                      const res = await fetch('https://api.cloudinary.com/v1_1/dnv6ezitm/image/upload', { method: 'POST', body: formData });
                      const data = await res.json();
                      await update(ref(db, `users/${auth.currentUser.uid}`), { idImageUrl: data.secure_url, identityStatus: 'pending' });
                      setProfile({ ...profile, identityStatus: 'pending' });
                      showToast('ID resubmitted successfully!');
                    } catch (err) {
                      showToast('Upload failed', true);
                    }
                    setUploading(false);
                  }} disabled={uploading} />
                </label>
                <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Required for booking verification</span>
              </div>
            </div>
          </div>
        )}

        {profile.identityStatus === 'pending' && (
          <div className="card" style={{ padding: '20px', marginBottom: '24px', background: 'rgba(245, 158, 11, 0.05)', border: '1px dashed rgba(245, 158, 11, 0.4)', display: 'flex', alignItems: 'center', gap: '12px' }}>
             <ShieldAlert size={20} color="#F59E0B" />
             <div style={{ fontSize: '14px', color: '#D97706', fontWeight: 600 }}>Your ID verification is currently pending review.</div>
          </div>
        )}

        <div className="card" style={{ padding: '32px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '24px' }}>
             <UserCircle size={22} color="var(--primary)" />
             <h4 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>Personal Details</h4>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px', marginBottom: '20px' }}>
            <div className="form-group">
              <label className="label">First Name</label>
              <input className="input" value={profile.firstName} onChange={e => setProfile({...profile, firstName: handleEmojiFilter(e.target.value)})} required maxLength="50" />
            </div>
            <div className="form-group">
              <label className="label">Last Name</label>
              <input className="input" value={profile.lastName} onChange={e => setProfile({...profile, lastName: handleEmojiFilter(e.target.value)})} required maxLength="50" />
            </div>
          </div>
          <div className="form-group">
            <label className="label">Phone Number</label>
            <div style={{ position: 'relative' }}>
               <Phone size={18} style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
               <input className="input" style={{ paddingLeft: '48px' }} value={profile.phoneNumber} onChange={e => setProfile({...profile, phoneNumber: handleEmojiFilter(e.target.value.replace(/\D/g, ''))})} placeholder="09XX XXX XXXX" maxLength="11" />
            </div>
          </div>
        </div>

        <div className="card" style={{ padding: '32px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '8px' }}>
             <Wallet size={22} color="var(--secondary)" />
             <h4 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>Payment Settings</h4>
          </div>
          <p style={{ fontSize: '13px', color: 'var(--text-muted)', marginBottom: '24px', fontWeight: 500 }}>Used for booking verifications and GCash payments.</p>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px' }}>
            <div className="form-group">
              <label className="label">GCash Number</label>
              <input className="input" value={profile.gcashNumber} onChange={e => setProfile({...profile, gcashNumber: handleEmojiFilter(e.target.value.replace(/\D/g, ''))})} placeholder="09XX XXX XXXX" maxLength="11" />
            </div>
            <div className="form-group">
              <label className="label">Registered Name</label>
              <input className="input" value={profile.gcashName} onChange={e => setProfile({...profile, gcashName: handleEmojiFilter(e.target.value)})} placeholder="Full Name" maxLength="50" />
            </div>
          </div>
        </div>

        <button
          type="submit"
          className="btn btn-primary"
          style={{ width: '100%', height: '60px', borderRadius: '20px', fontSize: '16px' }}
          disabled={saving || uploading}
        >
          {saving ? <div className="loader" style={{ width: '20px', height: '20px', borderTopColor: 'white' }}></div> : <><Save size={20} /> Update My Profile</>}
        </button>
      </form>

      <style>{`
        .label { display: block; font-size: 12px; font-weight: 800; margin-bottom: 8px; color: var(--text-main); text-transform: uppercase; letter-spacing: 0.5px; }
        .camera-btn:hover { transform: scale(1.1) rotate(5deg) !important; }
        .view-transition { animation: fadeIn 0.4s ease-out; }
      `}</style>
      
      {toast && (
        <div style={{
          position: 'fixed',
          bottom: '30px',
          left: '50%',
          transform: 'translateX(-50%)',
          background: toast.isError ? '#EF4444' : '#10B981',
          color: 'white',
          padding: '14px 24px',
          borderRadius: '12px',
          boxShadow: '0 8px 24px rgba(0,0,0,0.15)',
          fontWeight: 700,
          zIndex: 9999,
          display: 'flex',
          alignItems: 'center',
          gap: '10px',
          animation: 'slideUp 0.3s ease-out'
        }}>
          {toast.message}
        </div>
      )}
    </div>
  );
};

export default Profile;
