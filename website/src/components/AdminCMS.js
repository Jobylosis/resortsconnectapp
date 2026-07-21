import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, onValue, update } from 'firebase/database';
import { LayoutDashboard, Save, Camera, Plus, Trash2, Calendar, Link, Mail, Phone, Tag } from 'lucide-react';

const AdminCMS = () => {
  const [cmsData, setCmsData] = useState({
    heroTitle: 'Find Your Perfect Getaway',
    heroSubtitle: 'Discover exclusive resorts and book your dream vacation today.',
    heroImageUrls: [],
    aboutTitle: 'About Resort Connect',
    aboutText: 'We connect you with the best resort experiences across the country.',
    contact: {
      facebook: '',
      email: '',
      phone: ''
    },
    promotions: {}
  });

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [uploadingImage, setUploadingImage] = useState('');
  const [toast, setToast] = useState(null);

  const showToast = (message, isError = false) => {
    setToast({ message, isError });
    setTimeout(() => setToast(null), 3000);
  };

  useEffect(() => {
    const cmsRef = ref(db, 'cms/homepage');
    const unsubscribe = onValue(cmsRef, (snapshot) => {
      if (snapshot.exists()) {
        const data = snapshot.val();
        setCmsData(prev => ({
          ...prev,
          ...data,
          contact: { ...prev.contact, ...(data.contact || {}) },
          heroImageUrls: data.heroImageUrls || (data.heroImageUrl ? [data.heroImageUrl] : []),
          promotions: data.promotions || {}
        }));
      }
      setLoading(false);
    }, (error) => {
      console.error("Error fetching CMS data:", error);
      setLoading(false);
    });
    return () => unsubscribe();
  }, []);

  const handleUpload = async (e, fieldPath) => {
    const file = e.target.files[0];
    if (!file) return;

    setUploadingImage(fieldPath);
    const formData = new FormData();
    formData.append('file', file);
    formData.append('upload_preset', 'resort_unsigned');

    try {
      const response = await fetch('https://api.cloudinary.com/v1_1/dnv6ezitm/image/upload', {
        method: 'POST',
        body: formData,
      });
      const data = await response.json();
      
      if (fieldPath.startsWith('promo_')) {
        const promoId = fieldPath.split('_')[1];
        handlePromoChange(promoId, 'imageUrl', data.secure_url);
      } else if (fieldPath === 'heroImageUrls') {
        setCmsData(prev => ({ ...prev, heroImageUrls: [...(prev.heroImageUrls || []), data.secure_url] }));
      } else {
        handleChange(fieldPath, data.secure_url);
      }
    } catch (error) {
      showToast('Image upload failed', true);
    } finally {
      setUploadingImage('');
    }
  };

  const removeHeroImage = (indexToRemove) => {
    setCmsData(prev => ({
      ...prev,
      heroImageUrls: prev.heroImageUrls.filter((_, idx) => idx !== indexToRemove)
    }));
  };

  const handleChange = (field, value) => {
    if (field !== 'heroImageUrl' && field !== 'heroImageUrls') {
        value = value.replace(/[^a-zA-Z0-9\s]/g, '');
    }
    setCmsData(prev => ({ ...prev, [field]: value }));
  };

  const handleContactChange = (field, value) => {
    if (field !== 'email' && field !== 'phone') {
        // allowing : / . - for URLs
        value = value.replace(/[^a-zA-Z0-9\s:/.\-]/g, '');
    }
    setCmsData(prev => ({ ...prev, contact: { ...prev.contact, [field]: value } }));
  };

  const handlePromoChange = (id, field, value) => {
    if (field === 'title' || field === 'description') {
        value = value.replace(/[^a-zA-Z0-9\s]/g, '');
    } else if (field === 'badge') {
        value = value.replace(/[^a-zA-Z0-9\s%]/g, '');
    }
    // Note: badge allows special characters, imageUrl is a URL, dates are dates.
    setCmsData(prev => ({
      ...prev,
      promotions: {
        ...prev.promotions,
        [id]: { ...prev.promotions[id], [field]: value }
      }
    }));
  };

  const addPromo = () => {
    const newId = Date.now().toString();
    setCmsData(prev => ({
      ...prev,
      promotions: {
        ...prev.promotions,
        [newId]: {
          title: 'New Promo',
          description: '',
          imageUrl: '',
          active: false,
          startDate: '',
          endDate: ''
        }
      }
    }));
  };

  const deletePromo = (id) => {
    setCmsData(prev => {
      const newPromos = { ...prev.promotions };
      delete newPromos[id];
      return { ...prev, promotions: newPromos };
    });
  };

  const handleSave = async (e) => {
    e.preventDefault();
    
    
    if (!cmsData.heroTitle?.trim() || !cmsData.heroSubtitle?.trim()) {
      showToast('Hero Title and Subtitle are required', true);
      return;
    }
    if (!cmsData.heroImageUrls || cmsData.heroImageUrls.length === 0) {
      showToast('At least one Hero Background Image is required', true);
      return;
    }
    if (!cmsData.aboutTitle?.trim() || !cmsData.aboutText?.trim()) {
      showToast('About Title and Text are required', true);
      return;
    }
    
    for (const [id, promo] of Object.entries(cmsData.promotions)) {
      if (!promo.title?.trim() || !promo.description?.trim()) {
        showToast('All promotions must have a title and description', true);
        return;
      }
      if (!promo.startDate || !promo.endDate) {
        showToast(`Please specify start and end dates for promotion "${promo.title || 'Untitled'}"`, true);
        return;
      }
      if (new Date(promo.startDate) > new Date(promo.endDate)) {
        showToast(`Start date cannot be after end date for promotion "${promo.title}"`, true);
        return;
      }
    }

    // Contact Info Validation
    let { facebook, email, phone } = cmsData.contact;
    if (facebook) {
      facebook = facebook.trim();
      if (!/^https?:\/\//i.test(facebook)) {
        showToast('Facebook link must be a valid URL starting with http:// or https://', true);
        return;
      }
      cmsData.contact.facebook = facebook;
    }
    if (!email || !email.trim()) {
      showToast('Email address is required', true);
      return;
    }
    email = email.trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      showToast('Please enter a valid email address', true);
      return;
    }
    cmsData.contact.email = email;

    if (!phone) {
      showToast('Phone number is required', true);
      return;
    }
    phone = phone.replace(/\D/g, '');
    if (phone.length !== 11 || !phone.startsWith('09')) {
      showToast('Phone number must be 11 digits and start with 09', true);
      return;
    }
    cmsData.contact.phone = phone;

    setSaving(true);
    try {
      await update(ref(db, 'cms/homepage'), cmsData);
      showToast('CMS Content saved successfully!');
    } catch (error) {
      showToast('Failed to save CMS data', true);
    } finally {
      setSaving(false);
    }
  };

  if (loading) return <div className="loader" style={{ margin: 'auto' }}></div>;

  return (
    <div className="view-transition" style={{ maxWidth: '900px', margin: '0 auto', paddingBottom: '40px' }}>
      
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
        <div>
          <h2 style={{ margin: 0, fontSize: '24px', fontWeight: 800, display: 'flex', alignItems: 'center', gap: '10px' }}>
            <LayoutDashboard size={28} color="var(--primary)" /> Homepage CMS
          </h2>
          <p style={{ margin: '4px 0 0', color: 'var(--text-muted)' }}>Manage all content, banners, and promotions visible on the landing page.</p>
        </div>
        <button className="btn btn-primary" onClick={handleSave} disabled={saving} style={{ padding: '10px 20px', borderRadius: '12px' }}>
          {saving ? 'Saving...' : <><Save size={18} /> Save All Changes</>}
        </button>
      </div>

      <div className="card" style={{ marginBottom: '24px' }}>
        <h3 style={{ borderBottom: '1px solid var(--border)', paddingBottom: '12px', marginBottom: '20px' }}>Hero Section</h3>
        <div style={{ display: 'flex', gap: '20px', flexWrap: 'wrap' }}>
          <div style={{ flex: 1, minWidth: '300px' }}>
            <div className="form-group">
              <label className="label">Hero Title</label>
              <input className="input" value={cmsData.heroTitle} onChange={e => handleChange('heroTitle', e.target.value)} />
            </div>
            <div className="form-group">
              <label className="label">Hero Subtitle</label>
              <textarea className="input" rows="3" value={cmsData.heroSubtitle} onChange={e => handleChange('heroSubtitle', e.target.value)}></textarea>
            </div>
          </div>
          <div style={{ width: '300px' }}>
            <label className="label">Hero Background Image</label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: '10px', marginBottom: '10px' }}>
              {(cmsData.heroImageUrls || []).map((url, idx) => (
                <div key={idx} style={{ position: 'relative', width: '120px', height: '80px', borderRadius: '8px', overflow: 'hidden', border: '1px solid var(--border)' }}>
                  <img src={url} alt="Hero" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                  <button 
                    onClick={() => removeHeroImage(idx)} 
                    style={{ position: 'absolute', top: '4px', right: '4px', background: 'rgba(239, 68, 68, 0.9)', color: 'white', border: 'none', borderRadius: '4px', padding: '4px', cursor: 'pointer', zIndex: 10 }}
                  >
                    <Trash2 size={14} />
                  </button>
                </div>
              ))}
              
              <label style={{
                width: '120px', height: '80px', borderRadius: '8px', background: 'var(--light-bg)',
                border: '2px dashed var(--border)', display: 'flex', justifyContent: 'center', alignItems: 'center',
                cursor: 'pointer', color: 'var(--text-muted)'
              }}>
                {uploadingImage === 'heroImageUrls' ? <div className="loader small"></div> : <div style={{textAlign: 'center'}}><Plus size={20} /><div style={{fontSize: '10px'}}>Add Image</div></div>}
                <input type="file" hidden accept="image/*" onChange={(e) => handleUpload(e, 'heroImageUrls')} />
              </label>
            </div>
          </div>
        </div>
      </div>

      <div className="card" style={{ marginBottom: '24px' }}>
        <h3 style={{ borderBottom: '1px solid var(--border)', paddingBottom: '12px', marginBottom: '20px' }}>About Section</h3>
        <div className="form-group">
          <label className="label">About Title</label>
          <input className="input" value={cmsData.aboutTitle} onChange={e => handleChange('aboutTitle', e.target.value)} />
        </div>
        <div className="form-group">
          <label className="label">About Text</label>
          <textarea className="input" rows="4" value={cmsData.aboutText} onChange={e => handleChange('aboutText', e.target.value)}></textarea>
        </div>
      </div>

      <div className="card" style={{ marginBottom: '24px' }}>
        <h3 style={{ borderBottom: '1px solid var(--border)', paddingBottom: '12px', marginBottom: '20px' }}>Contact Information (Footer)</h3>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '16px' }}>
          <div className="form-group">
            <label className="label"><Link size={14}/> Facebook Link</label>
            <input className="input" placeholder="https://facebook.com/..." value={cmsData.contact.facebook} onChange={e => handleContactChange('facebook', e.target.value)} />
          </div>
          <div className="form-group">
            <label className="label"><Mail size={14}/> Email Address</label>
            <input className="input" type="email" placeholder="contact@resorts.com" value={cmsData.contact.email} onChange={e => handleContactChange('email', e.target.value)} />
          </div>
          <div className="form-group">
            <label className="label"><Phone size={14}/> Phone Number</label>
            <input className="input" placeholder="09XX XXX XXXX" maxLength={11} value={cmsData.contact.phone} onChange={e => handleContactChange('phone', e.target.value.replace(/\D/g, ''))} />
          </div>
        </div>
      </div>

      <div className="card" style={{ marginBottom: '24px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid var(--border)', paddingBottom: '12px', marginBottom: '20px' }}>
          <h3 style={{ margin: 0 }}><Tag size={20} style={{ marginRight: '8px', verticalAlign: 'middle' }}/> Promotions & Events</h3>
          <button className="btn" style={{ background: 'var(--light-bg)', color: 'var(--primary)' }} onClick={addPromo}>
            <Plus size={16} /> Add Promo
          </button>
        </div>

        {Object.keys(cmsData.promotions).length === 0 ? (
          <p style={{ color: 'var(--text-muted)', textAlign: 'center', padding: '20px 0' }}>No active promotions. Click 'Add Promo' to create one.</p>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
            {Object.entries(cmsData.promotions).map(([id, promo]) => (
              <div key={id} style={{ border: '1px solid var(--border)', borderRadius: '12px', padding: '20px', background: 'var(--light-bg)' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '16px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                    <label style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer', fontWeight: 700 }}>
                      <input 
                        type="checkbox" 
                        checked={promo.active} 
                        onChange={(e) => handlePromoChange(id, 'active', e.target.checked)} 
                        style={{ width: '18px', height: '18px', accentColor: 'var(--primary)' }}
                      />
                      Active (Display on Homepage)
                    </label>
                  </div>
                  <button onClick={() => deletePromo(id)} style={{ background: 'none', border: 'none', color: '#EF4444', cursor: 'pointer' }}>
                    <Trash2 size={18} />
                  </button>
                </div>

                <div style={{ display: 'flex', gap: '20px', flexWrap: 'wrap' }}>
                  <div style={{ flex: 1, minWidth: '250px' }}>
                    <div className="form-group">
                      <label className="label">Badge (e.g. 50% OFF)</label>
                      <input className="input" value={promo.badge || ''} onChange={e => handlePromoChange(id, 'badge', e.target.value)} />
                    </div>
                    <div className="form-group">
                      <label className="label">Promo Title</label>
                      <input className="input" value={promo.title} onChange={e => handlePromoChange(id, 'title', e.target.value)} />
                    </div>
                    <div className="form-group">
                      <label className="label">Description</label>
                      <input className="input" value={promo.description} onChange={e => handlePromoChange(id, 'description', e.target.value)} />
                    </div>
                    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                      <div className="form-group">
                        <label className="label">Start Date (Optional)</label>
                        <input type="date" className="input" value={promo.startDate} onChange={e => handlePromoChange(id, 'startDate', e.target.value)} />
                      </div>
                      <div className="form-group">
                        <label className="label">End Date (Optional)</label>
                        <input type="date" className="input" value={promo.endDate} onChange={e => handlePromoChange(id, 'endDate', e.target.value)} />
                      </div>
                    </div>
                  </div>
                  <div style={{ width: '200px' }}>
                    <label className="label">Promo Image</label>
                    <div style={{
                      width: '100%', height: '140px', borderRadius: '12px', background: 'var(--surface)',
                      position: 'relative', overflow: 'hidden', border: '1px solid var(--border)',
                      display: 'flex', justifyContent: 'center', alignItems: 'center'
                    }}>
                      {promo.imageUrl ? (
                        <img src={promo.imageUrl} alt="Promo" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                      ) : (
                        <span style={{ color: 'var(--text-muted)', fontSize: '12px' }}>No Image</span>
                      )}
                      <label style={{
                        position: 'absolute', bottom: '8px', right: '8px',
                        background: 'var(--surface)', padding: '6px', borderRadius: '6px',
                        cursor: 'pointer', boxShadow: 'var(--shadow)'
                      }}>
                        {uploadingImage === `promo_${id}` ? <div className="loader small"></div> : <Camera size={14} />}
                        <input type="file" hidden accept="image/*" onChange={(e) => handleUpload(e, `promo_${id}`)} />
                      </label>
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {toast && (
        <div style={{
          position: 'fixed', bottom: '30px', left: '50%', transform: 'translateX(-50%)',
          background: toast.isError ? '#EF4444' : '#10B981', color: 'white',
          padding: '14px 24px', borderRadius: '12px', boxShadow: '0 8px 24px rgba(0,0,0,0.15)',
          fontWeight: 700, zIndex: 9999, display: 'flex', alignItems: 'center', gap: '10px',
          animation: 'slideUp 0.3s ease-out'
        }}>
          {toast.message}
        </div>
      )}
      <style>{`
        .label { display: block; font-size: 12px; font-weight: 800; margin-bottom: 8px; color: var(--text-main); text-transform: uppercase; letter-spacing: 0.5px; }
      `}</style>
    </div>
  );
};

export default AdminCMS;
