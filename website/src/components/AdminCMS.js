import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, onValue, update } from 'firebase/database';
import { LayoutDashboard, Save, Camera, Plus, Trash2, Calendar, Link, Mail, Phone, Tag, ArrowUp, ArrowDown, Share2, Check } from 'lucide-react';

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
    contact_platforms: [
      { id: '1', platform_name: 'Facebook', platform_url_or_handle: '', order: 1 },
      { id: '2', platform_name: 'Email', platform_url_or_handle: '', order: 2 },
      { id: '3', platform_name: 'Phone', platform_url_or_handle: '', order: 3 }
    ],
    promotions: {}
  });

  const [availableRoomCategories, setAvailableRoomCategories] = useState(['Standard', 'Deluxe', 'Suite', 'Villa', 'Family', 'Dormitory']);
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
        let platforms = [];
        if (data.contact_platforms) {
          platforms = Array.isArray(data.contact_platforms)
            ? data.contact_platforms
            : Object.entries(data.contact_platforms).map(([k, v]) => ({ id: k, ...v }));
          platforms.sort((a, b) => (a.order || 0) - (b.order || 0));
        } else {
          platforms = [
            { id: '1', platform_name: 'Facebook', platform_url_or_handle: data.contact?.facebook || '', order: 1 },
            { id: '2', platform_name: 'Email', platform_url_or_handle: data.contact?.email || '', order: 2 },
            { id: '3', platform_name: 'Phone', platform_url_or_handle: data.contact?.phone || '', order: 3 }
          ];
        }

        setCmsData(prev => ({
          ...prev,
          ...data,
          contact: { ...prev.contact, ...(data.contact || {}) },
          contact_platforms: platforms,
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

  // Contact Platforms Handler
  const handlePlatformChange = (id, field, value) => {
    setCmsData(prev => ({
      ...prev,
      contact_platforms: prev.contact_platforms.map(p => p.id === id ? { ...p, [field]: value } : p)
    }));
  };

  const addPlatform = () => {
    const newPlatform = {
      id: Date.now().toString(),
      platform_name: 'Instagram',
      platform_url_or_handle: '',
      order: (cmsData.contact_platforms?.length || 0) + 1
    };
    setCmsData(prev => ({
      ...prev,
      contact_platforms: [...(prev.contact_platforms || []), newPlatform]
    }));
  };

  const deletePlatform = (id) => {
    setCmsData(prev => ({
      ...prev,
      contact_platforms: prev.contact_platforms.filter(p => p.id !== id)
    }));
  };

  const movePlatform = (index, direction) => {
    const list = [...(cmsData.contact_platforms || [])];
    const targetIndex = index + direction;
    if (targetIndex < 0 || targetIndex >= list.length) return;
    const temp = list[index];
    list[index] = list[targetIndex];
    list[targetIndex] = temp;
    list.forEach((item, idx) => item.order = idx + 1);
    setCmsData(prev => ({ ...prev, contact_platforms: list }));
  };

  const handlePromoChange = (id, field, value) => {
    if (field === 'title' || field === 'description') {
        value = value.replace(/[^a-zA-Z0-9\s]/g, '');
    } else if (field === 'badge') {
        value = value.replace(/[^0-9%]/g, '').slice(0, 4);
    } else if (field === 'code') {
        value = value.toUpperCase().replace(/[^A-Z0-9_-]/g, '');
    }
    setCmsData(prev => ({
      ...prev,
      promotions: {
        ...prev.promotions,
        [id]: { ...prev.promotions[id], [field]: value }
      }
    }));
  };

  const togglePromoRoom = (id, roomType) => {
    setCmsData(prev => {
      const promo = prev.promotions[id] || {};
      let rooms = Array.isArray(promo.applicableRooms) ? [...promo.applicableRooms] : ['ALL'];
      
      if (roomType === 'ALL') {
        rooms = ['ALL'];
      } else {
        rooms = rooms.filter(r => r !== 'ALL');
        if (rooms.includes(roomType)) {
          rooms = rooms.filter(r => r !== roomType);
          if (rooms.length === 0) rooms = ['ALL'];
        } else {
          rooms.push(roomType);
        }
      }

      return {
        ...prev,
        promotions: {
          ...prev.promotions,
          [id]: { ...promo, applicableRooms: rooms }
        }
      };
    });
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
          code: '',
          discountType: 'percentage',
          discountValue: 10,
          isEvent: false,
          applicableRooms: ['ALL'],
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
    
    // Allow Hero fields to be empty so they fall back to the defaults
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

    // Sync legacy contact object from platforms list if available
    const fbItem = cmsData.contact_platforms?.find(p => p.platform_name.toLowerCase() === 'facebook');
    const emailItem = cmsData.contact_platforms?.find(p => p.platform_name.toLowerCase() === 'email');
    const phoneItem = cmsData.contact_platforms?.find(p => p.platform_name.toLowerCase() === 'phone');

    if (fbItem) cmsData.contact.facebook = fbItem.platform_url_or_handle.trim();
    if (emailItem) cmsData.contact.email = emailItem.platform_url_or_handle.trim();
    if (phoneItem) cmsData.contact.phone = phoneItem.platform_url_or_handle.trim();

    setSaving(true);
    try {
      await update(ref(db, 'cms/homepage'), cmsData);
      showToast('Landing page saved successfully!');
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
            <LayoutDashboard size={28} color="var(--primary)" /> Landing Page
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
              <label className="label">Hero Title <span style={{ fontSize: '10px', color: 'var(--text-muted)', fontWeight: 'normal', textTransform: 'none' }}>(Leave blank for default)</span></label>
              <input className="input" placeholder="Your Perfect Resort Awaits You" value={cmsData.heroTitle} onChange={e => handleChange('heroTitle', e.target.value)} />
            </div>
            <div className="form-group">
              <label className="label">Hero Subtitle <span style={{ fontSize: '10px', color: 'var(--text-muted)', fontWeight: 'normal', textTransform: 'none' }}>(Leave blank for default)</span></label>
              <textarea className="input" rows="3" placeholder="Discover and book verified partner resorts with ease..." style={{ resize: 'none' }} value={cmsData.heroSubtitle} onChange={e => handleChange('heroSubtitle', e.target.value)}></textarea>
            </div>
          </div>
          <div style={{ width: '300px' }}>
            <label className="label">Hero Background Image <span style={{ fontSize: '10px', color: 'var(--text-muted)', fontWeight: 'normal', textTransform: 'none' }}>(Recommended: 1920 x 1080 px. Leave blank for default)</span></label>
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
          <textarea className="input" rows="4" style={{ resize: 'none' }} value={cmsData.aboutText} onChange={e => handleChange('aboutText', e.target.value)}></textarea>
        </div>
      </div>

      <div className="card" style={{ marginBottom: '24px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid var(--border)', paddingBottom: '12px', marginBottom: '20px' }}>
          <div>
            <h3 style={{ margin: 0, display: 'flex', alignItems: 'center', gap: '8px' }}>
              <Share2 size={20} color="var(--primary)" /> Dynamic Social & Contact Channels
            </h3>
            <p style={{ margin: '4px 0 0', color: 'var(--text-muted)', fontSize: '13px' }}>
              Add, configure, reorder, or remove social handles and direct contact channels visible on public footers.
            </p>
          </div>
          <button type="button" className="btn" style={{ background: 'var(--light-bg)', color: 'var(--primary)', display: 'flex', alignItems: 'center', gap: '6px', fontWeight: 700 }} onClick={addPlatform}>
            <Plus size={16} /> Add Platform
          </button>
        </div>

        {(!cmsData.contact_platforms || cmsData.contact_platforms.length === 0) ? (
          <p style={{ color: 'var(--text-muted)', textAlign: 'center', padding: '16px 0' }}>No channels added. Click '+ Add Platform' to add one.</p>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
            {cmsData.contact_platforms.map((plat, idx) => (
              <div key={plat.id || idx} style={{
                display: 'flex',
                alignItems: 'center',
                gap: '12px',
                padding: '12px 16px',
                background: 'var(--light-bg)',
                borderRadius: '12px',
                border: '1px solid var(--border)'
              }}>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '2px' }}>
                  <button
                    type="button"
                    disabled={idx === 0}
                    onClick={() => movePlatform(idx, -1)}
                    style={{ background: 'none', border: 'none', cursor: idx === 0 ? 'default' : 'pointer', opacity: idx === 0 ? 0.3 : 0.8, padding: '2px' }}
                  >
                    <ArrowUp size={16} />
                  </button>
                  <button
                    type="button"
                    disabled={idx === cmsData.contact_platforms.length - 1}
                    onClick={() => movePlatform(idx, 1)}
                    style={{ background: 'none', border: 'none', cursor: idx === cmsData.contact_platforms.length - 1 ? 'default' : 'pointer', opacity: idx === cmsData.contact_platforms.length - 1 ? 0.3 : 0.8, padding: '2px' }}
                  >
                    <ArrowDown size={16} />
                  </button>
                </div>

                <div style={{ width: '180px' }}>
                  <label className="label" style={{ marginBottom: '4px', fontSize: '11px' }}>Platform</label>
                  <input
                    className="input"
                    placeholder="e.g. Instagram, Viber, TikTok"
                    value={plat.platform_name || ''}
                    onChange={e => handlePlatformChange(plat.id, 'platform_name', e.target.value)}
                  />
                </div>

                <div style={{ flex: 1 }}>
                  <label className="label" style={{ marginBottom: '4px', fontSize: '11px' }}>URL, Handle, or Value</label>
                  <input
                    className="input"
                    placeholder="https://... or @handle or phone number"
                    value={plat.platform_url_or_handle || ''}
                    onChange={e => handlePlatformChange(plat.id, 'platform_url_or_handle', e.target.value)}
                  />
                </div>

                <button
                  type="button"
                  onClick={() => deletePlatform(plat.id)}
                  title="Remove Platform"
                  style={{ background: 'none', border: 'none', color: '#EF4444', cursor: 'pointer', padding: '8px', marginTop: '16px' }}
                >
                  <Trash2 size={18} />
                </button>
              </div>
            ))}
          </div>
        )}
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
                    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                      <div className="form-group">
                        <label className="label">Promo Code (For Checkout)</label>
                        <input className="input" placeholder="e.g. SUMMER20" value={promo.code || ''} onChange={e => handlePromoChange(id, 'code', e.target.value)} />
                      </div>
                      <div className="form-group">
                        <label className="label">Badge (e.g. 50% OFF)</label>
                        <input className="input" maxLength="4" value={promo.badge || ''} onChange={e => handlePromoChange(id, 'badge', e.target.value)} />
                      </div>
                    </div>

                    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                      <div className="form-group">
                        <label className="label">Discount Type</label>
                        <select className="input" value={promo.discountType || 'percentage'} onChange={e => handlePromoChange(id, 'discountType', e.target.value)}>
                          <option value="percentage">Percentage (%)</option>
                          <option value="fixed">Fixed Amount (₱)</option>
                        </select>
                      </div>
                      <div className="form-group">
                        <label className="label">Discount Value ({promo.discountType === 'fixed' ? '₱' : '%'})</label>
                        <input type="number" min="0" className="input" value={promo.discountValue || ''} onChange={e => handlePromoChange(id, 'discountValue', parseFloat(e.target.value) || 0)} />
                      </div>
                    </div>

                    <div className="form-group" style={{ margin: '12px 0' }}>
                      <label style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer', fontWeight: 600, fontSize: '13px' }}>
                        <input
                          type="checkbox"
                          checked={promo.isEvent || false}
                          onChange={e => handlePromoChange(id, 'isEvent', e.target.checked)}
                          style={{ width: '16px', height: '16px', accentColor: 'var(--primary)' }}
                        />
                        <span><strong>Automated Date-Driven Event:</strong> Auto-apply discount during active dates without promo code</span>
                      </label>
                    </div>

                    <div className="form-group" style={{ marginBottom: '16px' }}>
                      <label className="label">Applicable Room Types</label>
                      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '8px', marginTop: '6px' }}>
                        {['ALL', ...availableRoomCategories].map(cat => {
                          const rooms = Array.isArray(promo.applicableRooms) ? promo.applicableRooms : ['ALL'];
                          const isSelected = rooms.includes(cat);
                          return (
                            <button
                              key={cat}
                              type="button"
                              onClick={() => togglePromoRoom(id, cat)}
                              style={{
                                padding: '6px 14px',
                                borderRadius: '20px',
                                fontSize: '12px',
                                fontWeight: 700,
                                border: `1px solid ${isSelected ? 'var(--primary)' : 'var(--border)'}`,
                                background: isSelected ? 'var(--primary)' : 'var(--surface)',
                                color: isSelected ? 'white' : 'var(--text-main)',
                                cursor: 'pointer',
                                display: 'flex',
                                alignItems: 'center',
                                gap: '4px'
                              }}
                            >
                              {isSelected && <Check size={12} />}
                              {cat === 'ALL' ? 'All Rooms' : cat}
                            </button>
                          );
                        })}
                      </div>
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
                        <label className="label">Start Date (Auto-activate)</label>
                        <input type="date" className="input" value={promo.startDate} onChange={e => handlePromoChange(id, 'startDate', e.target.value)} />
                      </div>
                      <div className="form-group">
                        <label className="label">End Date</label>
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
