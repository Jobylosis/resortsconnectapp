import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, get } from 'firebase/database';
import { X, User, Phone, Mail, CheckCircle2, AlertCircle } from 'lucide-react';

const TouristProfileModal = ({ touristUid, onClose }) => {
  const [profileData, setProfileData] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchProfile = async () => {
      if (!touristUid) return;
      try {
        const snap = await get(ref(db, `users/${touristUid}`));
        if (snap.exists()) {
          setProfileData(snap.val());
        } else {
          // Check tourist_users as fallback
          const tSnap = await get(ref(db, `tourist_users/${touristUid}`));
          if (tSnap.exists()) {
            setProfileData(tSnap.val());
          }
        }
      } catch (error) {
        console.error('Error fetching tourist profile:', error);
      } finally {
        setLoading(false);
      }
    };
    fetchProfile();
  }, [touristUid]);

  return (
    <div className="modal-overlay" style={{ zIndex: 1000, display: 'flex', justifyContent: 'center', alignItems: 'center' }} onClick={onClose}>
      <div className="modal-content view-transition" style={{ maxWidth: '500px', width: '90%', background: 'var(--surface)', borderRadius: '24px', padding: '0', overflow: 'hidden', border: '1px solid var(--border)' }} onClick={e => e.stopPropagation()}>
        <div style={{ padding: '24px', borderBottom: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h3 style={{ margin: 0, fontSize: '20px', fontWeight: 800 }}>Tourist Profile</h3>
          <button className="icon-btn" onClick={onClose}><X size={20} /></button>
        </div>
        
        <div style={{ padding: '24px' }}>
          {loading ? (
            <div style={{ textAlign: 'center', padding: '20px' }}>Loading profile...</div>
          ) : profileData ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
                <div style={{ width: '80px', height: '80px', borderRadius: '24px', background: 'var(--light-bg)', overflow: 'hidden', display: 'flex', justifyContent: 'center', alignItems: 'center' }}>
                  {profileData.profilePicUrl ? (
                    <img src={profileData.profilePicUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                  ) : (
                    <User size={32} color="#9CA3AF" />
                  )}
                </div>
                <div>
                  <h4 style={{ margin: '0 0 4px 0', fontSize: '20px', fontWeight: 800 }}>
                    {profileData.firstName || profileData.name || 'Unknown'} {profileData.lastName || ''}
                  </h4>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    {profileData.idVerificationStatus === 'Verified' ? (
                      <span style={{ display: 'flex', alignItems: 'center', gap: '4px', background: 'rgba(16, 185, 129, 0.1)', color: '#10B981', padding: '4px 10px', borderRadius: '12px', fontSize: '12px', fontWeight: 700 }}>
                        <CheckCircle2 size={14} /> ID Verified
                      </span>
                    ) : (
                      <span style={{ display: 'flex', alignItems: 'center', gap: '4px', background: 'rgba(245, 158, 11, 0.1)', color: '#F59E0B', padding: '4px 10px', borderRadius: '12px', fontSize: '12px', fontWeight: 700 }}>
                        <AlertCircle size={14} /> ID Not Verified
                      </span>
                    )}
                  </div>
                </div>
              </div>
              
              <div style={{ background: 'var(--light-bg)', padding: '20px', borderRadius: '16px', border: '1px solid var(--border)' }}>
                <h5 style={{ margin: '0 0 16px 0', fontSize: '14px', fontWeight: 800, color: 'var(--text-muted)' }}>CONTACT INFORMATION</h5>
                
                <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                    <div style={{ background: 'white', padding: '8px', borderRadius: '10px', boxShadow: '0 2px 5px rgba(0,0,0,0.02)' }}>
                      <Phone size={16} color="var(--primary)" />
                    </div>
                    <div>
                      <div style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 700, textTransform: 'uppercase' }}>Phone Number</div>
                      <div style={{ fontSize: '14px', fontWeight: 600 }}>{profileData.phone || profileData.phoneNumber || 'Not provided'}</div>
                    </div>
                  </div>
                  
                  <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                    <div style={{ background: 'white', padding: '8px', borderRadius: '10px', boxShadow: '0 2px 5px rgba(0,0,0,0.02)' }}>
                      <Mail size={16} color="var(--primary)" />
                    </div>
                    <div>
                      <div style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 700, textTransform: 'uppercase' }}>Email Address</div>
                      <div style={{ fontSize: '14px', fontWeight: 600 }}>{profileData.email || 'Not provided'}</div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          ) : (
            <div style={{ textAlign: 'center', padding: '20px', color: 'var(--text-muted)' }}>
              Could not load tourist profile data.
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default TouristProfileModal;
