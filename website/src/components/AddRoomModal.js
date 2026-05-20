import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, push, set, onValue } from 'firebase/database';
import { X, Upload, Plus, ArrowLeft, Info, DollarSign, Users, MapPin, Tag, Edit2 } from 'lucide-react';

const AddRoomModal = ({ uid, rooms, roomToEdit, onClose }) => {
  const [formData, setFormData] = useState({
    title: '',
    nickname: '',
    description: '',
    price: '',
    maxPax: '',
    category: 'Standard',
    location: 'Riverside (R)',
    activity: 'Swimming',
    inclusions: [],
    imageUrls: [],
    videoUrl: ''
  });
  const [activityOptions, setActivityOptions] = useState(['Swimming', 'Kayaking', 'Camping', 'Island Hopping', 'None']);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [uploading, setUploading] = useState(false);

  const parseList = (data) => {
    if (!data) return [];
    if (Array.isArray(data)) return data.filter(e => e != null);
    if (typeof data === 'object') {
      return Object.keys(data).sort().map(k => data[k]);
    }
    return [];
  };

  const inclusionOptions = [
    'Refrigerator', 'Air Conditioning', 'Smart Tv', 'Free Wifi', 'Bathroom essentials',
    'Heater', 'Sofa', 'Cabinet', 'Ceiling fan', 'Swimming Pool'
  ];

  useEffect(() => {
    if (roomToEdit) {
      setFormData({
        title: roomToEdit.title || '',
        nickname: roomToEdit.nickname || '',
        description: roomToEdit.description || '',
        price: roomToEdit.price || '',
        maxPax: roomToEdit.maxPax || '',
        category: roomToEdit.category || 'Standard',
        location: roomToEdit.location || 'Riverside (R)',
        activity: roomToEdit.activity || 'Swimming',
        inclusions: parseList(roomToEdit.inclusions),
        imageUrls: parseList(roomToEdit.imageUrls),
        videoUrl: roomToEdit.videoUrl || ''
      });
    } else {
      // Auto-generate name for a new room based on default location
      generateRoomName('Riverside (R)');
    }

    // Fetch activity options from DB
    const actRef = ref(db, 'master_data/activities');
    const unsubscribe = onValue(actRef, (snap) => {
      if (snap.exists()) {
        const val = snap.val();
        const list = Array.isArray(val) ? val.filter(e => e) : Object.values(val);
        setActivityOptions(list);
      }
    }, (err) => {
      console.warn("Activity options fetch failed", err);
    });
    return () => unsubscribe();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [roomToEdit]);

  const generateRoomName = (location) => {
    let prefix = "R";
    if (location.includes("(P)")) prefix = "P";
    else if (location.includes("(B)")) prefix = "B";

    let maxNum = 0;
    if (rooms && Array.isArray(rooms)) {
      rooms.forEach(r => {
        if (r.location === location) {
          const t = r.title || "";
          if (t.includes("-")) {
            const numPart = t.split("-").pop();
            const n = parseInt(numPart);
            if (!isNaN(n) && n > maxNum) maxNum = n;
          }
        }
      });
    }
    const newTitle = `${prefix}-${(maxNum + 1).toString().padStart(3, '0')}`;
    setFormData(prev => ({ ...prev, location, title: newTitle }));
  };

  const handleImageUpload = async (e) => {
    const files = Array.from(e.target.files);
    if (files.length === 0) return;

    setUploading(true);
    const newUrls = [...formData.imageUrls];

    for (const file of files) {
      const data = new FormData();
      data.append('file', file);
      data.append('upload_preset', 'resort_unsigned');

      try {
        const response = await fetch('https://api.cloudinary.com/v1_1/dnv6ezitm/image/upload', {
          method: 'POST',
          body: data,
        });
        const res = await response.json();
        if (res.secure_url) newUrls.push(res.secure_url);
      } catch (error) {
        console.error('Upload failed', error);
      }
    }

    setFormData({ ...formData, imageUrls: newUrls });
    setUploading(false);
  };

  const toggleInclusion = (item) => {
    const newInclusions = formData.inclusions.includes(item)
      ? formData.inclusions.filter(i => i !== item)
      : [...formData.inclusions, item];
    setFormData({ ...formData, inclusions: newInclusions });
  };

  const validate = () => {
    const { price, maxPax, imageUrls } = formData;
    if (!price || parseFloat(price) <= 0) return 'Please enter a valid price greater than 0';
    if (!maxPax || parseInt(maxPax) <= 0) return 'Max occupancy must be at least 1';
    if (imageUrls.length === 0) return 'Please add at least one photo for this room.';
    return null;
  };

  const handleEmojiFilter = (value) => {
    const emojiRegex = /[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]/gu;
    return value.replace(emojiRegex, '');
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    const validationError = validate();
    if (validationError) {
      alert(validationError);
      return;
    }

    setIsSubmitting(true);
    try {
      const roomRef = roomToEdit
        ? ref(db, `properties/${uid}/roomInventory/${roomToEdit.id}`)
        : push(ref(db, `properties/${uid}/roomInventory`));

      await set(roomRef, {
        ...formData,
        timestamp: Date.now()
      });

      onClose();
    } catch (error) {
      alert('Error saving room: ' + error.message);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="modal-overlay" style={{ zIndex: 3000 }}>
      <div className="card modal-content view-transition" style={{ maxWidth: '650px', borderRadius: '32px', padding: '32px', background: 'var(--surface)', border: '1px solid var(--border)' }}>
        <button
          onClick={onClose}
          style={{
            display: 'flex', alignItems: 'center', gap: '8px',
            background: 'var(--light-bg)', border: '1px solid var(--border)', cursor: 'pointer',
            marginBottom: '24px', color: 'var(--text-main)',
            fontWeight: 700, padding: '10px 18px', borderRadius: '14px',
          }}
        >
          <ArrowLeft size={18} /> Back to Dashboard
        </button>

        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '32px' }}>
          <h2 style={{ margin: 0, fontSize: '24px', fontWeight: 800 }}>{roomToEdit ? 'Update Room' : 'Add New Room'}</h2>
          <button onClick={onClose} className="close-btn"><X size={20} /></button>
        </div>

        <form onSubmit={handleSubmit}>
          {/* Media Section */}
          <div style={{ marginBottom: '32px' }}>
            <label className="input-label">Room Gallery</label>
            <div style={{ display: 'flex', gap: '12px', overflowX: 'auto', paddingBottom: '12px', scrollbarWidth: 'none' }}>
              {formData.imageUrls.map((url, i) => (
                <div key={i} style={{ position: 'relative', minWidth: '110px', height: '110px' }}>
                  <img src={url} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover', borderRadius: '20px' }} />
                  <button
                    type="button"
                    onClick={() => setFormData({...formData, imageUrls: formData.imageUrls.filter((_, idx) => idx !== i)})}
                    style={{ position: 'absolute', top: '6px', right: '6px', background: 'rgba(0,0,0,0.5)', color: 'white', border: 'none', borderRadius: '50%', width: '24px', height: '24px', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', backdropFilter: 'blur(4px)' }}
                  >
                    <X size={14} />
                  </button>
                </div>
              ))}
              <label className="media-upload-btn">
                {uploading ? <div className="loader small" style={{ width: '20px', height: '20px' }}></div> : <Plus color="var(--secondary)" size={24} />}
                <input type="file" multiple hidden accept="image/*" onChange={handleImageUpload} disabled={uploading} />
              </label>
            </div>
          </div>

          <div style={{ background: 'var(--light-bg)', padding: '24px', borderRadius: '24px', marginBottom: '24px', border: '1px solid var(--border)' }}>
             <div style={{ marginBottom: '20px' }}>
                <label className="input-label">Primary Activity</label>
                <div style={{ position: 'relative' }}>
                   <select
                     className="input"
                     style={{ background: 'var(--surface)' }}
                     value={formData.activity}
                     onChange={e => setFormData({...formData, activity: e.target.value})}
                   >
                     {activityOptions.map(a => <option key={a} value={a}>{a}</option>)}
                   </select>
                </div>
             </div>

             <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px', marginBottom: '20px' }}>
                <div className="form-group">
                  <label className="input-label">Automated Room ID</label>
                  <div style={{ position: 'relative' }}>
                    <Tag size={18} style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
                    <input className="input" style={{ paddingLeft: '48px', background: 'var(--card-hover-bg)', cursor: 'not-allowed' }} value={formData.title} readOnly />
                  </div>
                </div>
                <div className="form-group">
                  <label className="input-label">Price / Night</label>
                  <div style={{ position: 'relative' }}>
                    <DollarSign size={18} style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} />
                    <input type="number" className="input" style={{ paddingLeft: '48px' }} placeholder="0.00" value={formData.price} onChange={e => setFormData({...formData, price: handleEmojiFilter(e.target.value)})} required min="1" max="999999" />
                  </div>
                </div>
             </div>

             <div style={{ marginBottom: '20px' }}>
                <label className="input-label">Room Nickname (Optional)</label>
                <div style={{ position: 'relative' }}>
                  <Edit2 size={18} style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
                  <input className="input" style={{ paddingLeft: '48px' }} placeholder="e.g. Sunset Paradise" value={formData.nickname} onChange={e => setFormData({...formData, nickname: handleEmojiFilter(e.target.value)})} maxLength="50" />
                </div>
             </div>

             <div style={{ marginBottom: '20px' }}>
                <label className="input-label">Primary Activity</label>
                <div style={{ position: 'relative' }}>
                   <select
                     className="input"
                     style={{ background: 'var(--surface)' }}
                     value={formData.activity}
                     onChange={e => setFormData({...formData, activity: e.target.value})}
                   >
                     {activityOptions.map(a => <option key={a} value={a}>{a}</option>)}
                   </select>
                </div>
             </div>

             <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px', marginBottom: '20px' }}>
                <div className="form-group">
                  <label className="input-label">Room Category</label>
                  <div style={{ position: 'relative' }}>
                    <select
                      className="input"
                      style={{ paddingRight: '40px', background: 'var(--surface)' }}
                      value={formData.category}
                      onChange={e => setFormData({...formData, category: e.target.value})}
                    >
                      <option value="Standard">Standard Room</option>
                      <option value="Family">Family Suite</option>
                      <option value="Deluxe">Premium Deluxe</option>
                    </select>
                  </div>
                </div>
                <div className="form-group">
                  <label className="input-label">Max Occupancy</label>
                  <div style={{ position: 'relative' }}>
                    <Users size={18} style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
                    <input type="number" className="input" style={{ paddingLeft: '48px' }} value={formData.maxPax} onChange={e => setFormData({...formData, maxPax: handleEmojiFilter(e.target.value)})} required min="1" max="99" />
                  </div>
                </div>
             </div>

             <div className="form-group">
                <label className="input-label">Location in Resort</label>
                <div style={{ position: 'relative' }}>
                   <MapPin size={18} style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--primary)', zIndex: 1 }} />
                   <select
                     className="input"
                     style={{ paddingLeft: '48px', background: 'var(--surface)' }}
                     value={formData.location}
                     onChange={e => generateRoomName(e.target.value)}
                     disabled={!!roomToEdit}
                   >
                     <option value="Riverside (R)">Riverside (R)</option>
                     <option value="Poolside (P)">Poolside (P)</option>
                     <option value="Basement (B)">Basement (B)</option>
                   </select>
                </div>
             </div>
          </div>

          <div style={{ marginBottom: '32px' }}>
            <label className="input-label">Inclusions & Amenities</label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: '10px', marginTop: '12px' }}>
              {inclusionOptions.map(item => (
                <button
                  key={item} type="button"
                  onClick={() => toggleInclusion(item)}
                  className={`inclusion-pill ${formData.inclusions.includes(item) ? 'active' : ''}`}
                  style={{
                    padding: '8px 16px',
                    borderRadius: '12px',
                    border: '2px solid var(--border)',
                    background: formData.inclusions.includes(item) ? 'rgba(29, 211, 176, 0.1)' : 'var(--surface)',
                    fontSize: '13px',
                    fontWeight: 700,
                    color: formData.inclusions.includes(item) ? 'var(--secondary)' : 'var(--text-muted)',
                    cursor: 'pointer'
                  }}
                >
                  {item}
                </button>
              ))}
            </div>
          </div>

          <div style={{ marginBottom: '32px' }}>
            <label className="input-label">Room Description</label>
            <textarea
              className="input" style={{ height: '100px', paddingTop: '14px', resize: 'none' }}
              placeholder="Tell guests about this specific room..."
              value={formData.description} onChange={e => setFormData({...formData, description: handleEmojiFilter(e.target.value)})}
              maxLength="500"
            />
          </div>

          <button
            type="submit"
            className="btn btn-primary"
            style={{ width: '100%', height: '60px', borderRadius: '20px' }}
            disabled={isSubmitting || uploading}
          >
            {isSubmitting ? <div className="loader" style={{ width: '20px', height: '20px', borderTopColor: 'white' }}></div> : 'SAVE & PUBLISH'}
          </button>
        </form>
      </div>

      <style>{`
        .input-label { display: block; font-size: 11px; font-weight: 800; color: var(--text-muted); margin-bottom: 8px; text-transform: uppercase; letter-spacing: 1px; }
        .media-upload-btn { min-width: 110px; height: 110px; border: 2px dashed var(--border-dashed); border-radius: 20px; display: flex; justify-content: center; align-items: center; cursor: pointer; transition: var(--transition); background: var(--light-bg); }
        .media-upload-btn:hover { border-color: var(--secondary); background: var(--surface); }
        .close-btn { background: var(--light-bg); border: none; width: 36px; height: 36px; border-radius: 50%; display: flex; align-items: center; justify-content: center; cursor: pointer; color: var(--text-main); transition: var(--transition); border: 1px solid var(--border); }
        .close-btn:hover { background: var(--surface); transform: rotate(90deg); }
        .view-transition { animation: fadeIn 0.4s ease-out; }
      `}</style>
    </div>
  );
};

export default AddRoomModal;
