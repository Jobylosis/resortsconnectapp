import React, { useState, useEffect } from 'react';
import { auth, db } from '../firebase';
import { ref, onValue, update } from 'firebase/database';
import { User, Phone, BadgeCheck, Camera, Save, ArrowLeft, Mail, Wallet, UserCircle } from 'lucide-react';

const Profile = ({ onBack }) => {
  const [profile, setProfile] = useState({
    firstName: '',
    middleName: '',
    lastName: '',
    phoneNumber: '',
    gcashNumber: '',
    gcashName: '',
    profilePicUrl: ''
  });
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);

  useEffect(() => {
    const user = auth.currentUser;
    if (!user) return;

    const userRef = ref(db, `users/${user.uid}`);
    const unsubscribe = onValue(userRef, (snapshot) => {
      if (snapshot.exists()) {
        setProfile(snapshot.val());
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
      alert('Upload failed');
    } finally {
      setUploading(false);
    }
  };

  const handleSave = async (e) => {
    e.preventDefault();
    setSaving(true);
    try {
      const user = auth.currentUser;
      await update(ref(db, `users/${user.uid}`), profile);

      if (profile.role === 'Owner') {
        await update(ref(db, `properties/${user.uid}`), {
          gcashNumber: profile.gcashNumber,
          gcashName: profile.gcashName
        });
      }
      alert('Profile updated successfully!');
      if (onBack) onBack();
    } catch (error) {
      alert('Update failed: ' + error.message);
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
          background: 'white', border: 'none', cursor: 'pointer',
          marginBottom: '32px', color: 'var(--text-main)',
          fontWeight: 700, padding: '10px 18px', borderRadius: '14px',
          boxShadow: 'var(--shadow)'
        }}
      >
        <ArrowLeft size={18} /> Back to Dashboard
      </button>

      <div style={{ textAlign: 'center', marginBottom: '40px' }}>
        <div style={{ position: 'relative', display: 'inline-block' }}>
          <div style={{
            width: '140px', height: '140px', borderRadius: '45px', overflow: 'hidden',
            background: 'white', border: '5px solid white', boxShadow: '0 15px 35px rgba(0,0,0,0.1)',
            transform: 'rotate(-3deg)'
          }}>
            {profile.profilePicUrl ? (
              <img src={profile.profilePicUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
            ) : (
              <div style={{ width: '100%', height: '100%', display: 'flex', justifyContent: 'center', alignItems: 'center', color: '#E5E7EB', background: '#F9FAFB' }}>
                <User size={72} />
              </div>
            )}
          </div>
          <label style={{
            position: 'absolute', bottom: '0px', right: '-10px',
            background: 'var(--secondary)', color: '#002D24', borderRadius: '18px',
            width: '44px', height: '44px', display: 'flex', justifyContent: 'center',
            alignItems: 'center', cursor: 'pointer', border: '4px solid white',
            boxShadow: '0 8px 15px rgba(29, 211, 176, 0.3)',
            transition: 'var(--transition)'
          }} className="camera-btn">
            {uploading ? <div className="loader small" style={{ width: '16px', height: '16px' }}></div> : <Camera size={20} />}
            <input type="file" hidden accept="image/*" onChange={handleUpload} disabled={uploading} />
          </label>
        </div>
        <h2 style={{ marginTop: '24px', marginBottom: '4px', fontSize: '28px', fontWeight: 800 }}>{profile.firstName} {profile.lastName}</h2>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px', color: 'var(--text-muted)', fontSize: '14px', fontWeight: 600 }}>
           <Mail size={14} /> {profile.email}
        </div>
      </div>

      <form onSubmit={handleSave}>
        <div className="card" style={{ padding: '32px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '24px' }}>
             <UserCircle size={22} color="var(--primary)" />
             <h4 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>Personal Details</h4>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px', marginBottom: '20px' }}>
            <div className="form-group">
              <label className="label">First Name</label>
              <input className="input" value={profile.firstName} onChange={e => setProfile({...profile, firstName: e.target.value})} required />
            </div>
            <div className="form-group">
              <label className="label">Last Name</label>
              <input className="input" value={profile.lastName} onChange={e => setProfile({...profile, lastName: e.target.value})} required />
            </div>
          </div>
          <div className="form-group">
            <label className="label">Phone Number</label>
            <div style={{ position: 'relative' }}>
               <Phone size={18} style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
               <input className="input" style={{ paddingLeft: '48px' }} value={profile.phoneNumber} onChange={e => setProfile({...profile, phoneNumber: e.target.value})} placeholder="09XX XXX XXXX" />
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
              <input className="input" value={profile.gcashNumber} onChange={e => setProfile({...profile, gcashNumber: e.target.value})} placeholder="09XX XXX XXXX" />
            </div>
            <div className="form-group">
              <label className="label">Registered Name</label>
              <input className="input" value={profile.gcashName} onChange={e => setProfile({...profile, gcashName: e.target.value})} placeholder="Full Name" />
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
    </div>
  );
};

export default Profile;
