import React, { useState, useEffect } from 'react';
import { X, Upload, Plus, Trash2 } from 'lucide-react';
import { db } from '../firebase';
import { ref, push, set } from 'firebase/database';

const AddActivityModal = ({ uid, activities, activityToEdit, onClose }) => {
  const [formData, setFormData] = useState({
    title: '',
    description: '',
    price: '',
    maxPax: '',
    imageUrls: [],
    timeSlots: ['09:00 AM'] // Default slot
  });
  const [loading, setLoading] = useState(false);
  const uploadPreset = 'ResortsConnectImages';
  const cloudName = 'dnv6ezitm';

  useEffect(() => {
    if (activityToEdit) {
      setFormData({
        title: activityToEdit.title || '',
        description: activityToEdit.description || '',
        price: activityToEdit.price || '',
        maxPax: activityToEdit.maxPax || '',
        imageUrls: Array.isArray(activityToEdit.imageUrls) ? activityToEdit.imageUrls : [],
        timeSlots: Array.isArray(activityToEdit.timeSlots) ? activityToEdit.timeSlots : ['09:00 AM']
      });
    }
  }, [activityToEdit]);

  const handleUploadImage = async (e) => {
    const files = Array.from(e.target.files);
    if (!files.length) return;
    setLoading(true);
    try {
      const uploadPromises = files.map(async file => {
        const formDataUpload = new FormData();
        formDataUpload.append('file', file);
        formDataUpload.append('upload_preset', uploadPreset);
        const res = await fetch(`https://api.cloudinary.com/v1_1/${cloudName}/image/upload`, {
          method: 'POST', body: formDataUpload
        });
        const data = await res.json();
        return data.secure_url;
      });
      const urls = await Promise.all(uploadPromises);
      setFormData(prev => ({ ...prev, imageUrls: [...prev.imageUrls, ...urls] }));
    } catch (err) {
      alert("Image upload failed");
    } finally {
      setLoading(false);
    }
  };

  const removeImage = (index) => {
    setFormData(prev => ({
      ...prev,
      imageUrls: prev.imageUrls.filter((_, i) => i !== index)
    }));
  };

  const addTimeSlot = () => {
    setFormData(prev => ({ ...prev, timeSlots: [...prev.timeSlots, '12:00 PM'] }));
  };

  const updateTimeSlot = (index, value) => {
    const newSlots = [...formData.timeSlots];
    newSlots[index] = value;
    setFormData(prev => ({ ...prev, timeSlots: newSlots }));
  };

  const removeTimeSlot = (index) => {
    setFormData(prev => ({
      ...prev,
      timeSlots: prev.timeSlots.filter((_, i) => i !== index)
    }));
  };

  const handleSave = async () => {
    if (!formData.title || !formData.price || !formData.maxPax) {
      return alert("Please fill in the title, price, and max capacity.");
    }
    if (formData.timeSlots.length === 0) {
      return alert("Please add at least one available time slot.");
    }
    if (formData.imageUrls.length === 0) {
      return alert("Please upload at least one image.");
    }

    setLoading(true);
    try {
      const activityRef = activityToEdit
        ? ref(db, `properties/${uid}/activities/${activityToEdit.id}`)
        : push(ref(db, `properties/${uid}/activities`));

      await set(activityRef, {
        ...formData,
        price: Number(formData.price),
        maxPax: Number(formData.maxPax),
        timestamp: Date.now()
      });
      onClose();
    } catch (error) {
      alert("Error saving activity: " + error.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 9999, padding: '24px' }}>
      <div style={{ background: 'var(--surface)', width: '100%', maxWidth: '800px', maxHeight: '90vh', borderRadius: '24px', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        <div style={{ padding: '24px 32px', borderBottom: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h2 style={{ margin: 0, fontSize: '24px', fontWeight: 800 }}>{activityToEdit ? 'Edit Activity' : 'Add New Activity'}</h2>
          <button onClick={onClose} style={{ background: 'var(--light-bg)', border: 'none', width: '40px', height: '40px', borderRadius: '50%', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <X size={20} />
          </button>
        </div>

        <div style={{ padding: '32px', overflowY: 'auto', flex: 1 }}>
          <div style={{ display: 'grid', gap: '24px' }}>
            {/* Gallery */}
            <div>
              <label className="input-label">Activity Photos</label>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(120px, 1fr))', gap: '16px' }}>
                {formData.imageUrls.map((url, i) => (
                  <div key={i} style={{ position: 'relative', aspectRatio: '1', borderRadius: '12px', overflow: 'hidden' }}>
                    <img src={url} alt={`Photo ${i+1}`} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                    <button onClick={() => removeImage(i)} style={{ position: 'absolute', top: '8px', right: '8px', background: 'rgba(0,0,0,0.5)', color: 'white', border: 'none', borderRadius: '50%', width: '28px', height: '28px', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}><X size={14} /></button>
                  </div>
                ))}
                <label style={{ aspectRatio: '1', border: '2px dashed var(--border)', borderRadius: '12px', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', background: 'var(--light-bg)' }}>
                  {loading ? <div className="loader" style={{ width: '24px', height: '24px' }}></div> : (
                    <>
                      <Upload size={24} style={{ color: 'var(--text-muted)', marginBottom: '8px' }} />
                      <span style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 600 }}>Add Photo</span>
                    </>
                  )}
                  <input type="file" multiple accept="image/*" onChange={handleUploadImage} style={{ display: 'none' }} disabled={loading} />
                </label>
              </div>
            </div>

            {/* Basic Info */}
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
              <div>
                <label className="input-label">Activity Title</label>
                <input type="text" className="input-field" placeholder="e.g. Island Hopping Boat Ride" value={formData.title} onChange={e => setFormData({ ...formData, title: e.target.value })} />
              </div>
              <div>
                <label className="input-label">Price per person (₱)</label>
                <input type="number" className="input-field" placeholder="0" value={formData.price} onChange={e => setFormData({ ...formData, price: e.target.value })} />
              </div>
            </div>

            {/* Capacity */}
            <div>
              <label className="input-label">Maximum Capacity (Pax per slot)</label>
              <input type="number" className="input-field" placeholder="e.g. 10" value={formData.maxPax} onChange={e => setFormData({ ...formData, maxPax: e.target.value })} />
            </div>

            {/* Time Slots */}
            <div>
              <label className="input-label">Available Time Slots</label>
              <p style={{ fontSize: '12px', color: 'var(--text-muted)', margin: '0 0 12px 0' }}>Tourists will book a specific date and choose one of these exact times (Available slots must be between 7:00 AM and 3:30 PM).</p>
              
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '12px', marginBottom: '12px' }}>
                {formData.timeSlots.map((slot, index) => (
                  <div key={index} style={{ display: 'flex', alignItems: 'center', background: 'var(--light-bg)', border: '1px solid var(--border)', borderRadius: '8px', overflow: 'hidden' }}>
                    <input 
                      type="text" 
                      value={slot} 
                      onChange={(e) => updateTimeSlot(index, e.target.value)} 
                      style={{ border: 'none', background: 'transparent', padding: '8px 12px', width: '100px', fontWeight: 600, outline: 'none' }}
                      placeholder="e.g. 09:00 AM"
                    />
                    <button type="button" onClick={() => removeTimeSlot(index)} style={{ background: '#FEE2E2', color: '#EF4444', border: 'none', padding: '8px', cursor: 'pointer', display: 'flex', alignItems: 'center' }}>
                      <Trash2 size={16} />
                    </button>
                  </div>
                ))}
              </div>
              
              <button type="button" onClick={addTimeSlot} className="btn" style={{ background: 'var(--light-bg)', color: 'var(--text-main)', border: '1px dashed var(--border)' }}>
                <Plus size={16} style={{ marginRight: '8px' }} /> Add Time Slot
              </button>
            </div>

            {/* Description */}
            <div>
              <label className="input-label">Description</label>
              <textarea className="input-field" rows={4} placeholder="Describe the activity..." value={formData.description} onChange={e => setFormData({ ...formData, description: e.target.value })}></textarea>
            </div>
          </div>
        </div>

        <div style={{ padding: '24px 32px', borderTop: '1px solid var(--border)', display: 'flex', gap: '12px', justifyContent: 'flex-end', background: 'var(--light-bg)' }}>
          <button type="button" className="btn" style={{ background: 'white', border: '1px solid var(--border)', color: 'var(--text-main)' }} onClick={onClose}>Cancel</button>
          <button type="button" className="btn btn-primary" onClick={handleSave} disabled={loading}>
            {loading ? 'Saving...' : 'Save Activity'}
          </button>
        </div>
      </div>
    </div>
  );
};

export default AddActivityModal;
