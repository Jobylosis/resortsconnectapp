import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, update, get } from 'firebase/database';
import { X, Upload, Plus, Camera, Video, ArrowLeft, Business, Info, Wallet, Image as ImageIcon, PlusSquare } from 'lucide-react';
import { MapContainer, TileLayer, Marker, useMapEvents } from 'react-leaflet';

const LocationPicker = ({ position, setPosition }) => {
  const map = useMapEvents({
    click(e) {
      setPosition({ lat: e.latlng.lat, lng: e.latlng.lng });
    },
  });
  
  useEffect(() => {
    if (position.lat !== 0 && position.lng !== 0) {
      map.setView([position.lat, position.lng], map.getZoom());
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []); // Only on mount

  return (position.lat === 0 && position.lng === 0) ? null : <Marker position={[position.lat, position.lng]} />;
};

const EditPropertyModal = ({ uid, onClose }) => {
  const [formData, setFormData] = useState({
    name: '',
    description: '',
    type: 'Resort',
    rooms: 0,
    staffCount: 0,
    maxCapacity: 0,
    checkInTime: '',
    checkOutTime: '',
    bookingInstructions: '',
    latitude: 0,
    longitude: 0,
    contactPhone: '',
    contactEmail: '',
    amenities: [],
    gcashNumber: '',
    gcashName: '',
    gcashQrUrl: '',
    imageUrls: [],
    videoUrls: [],
    cancellationPolicy: '',
    paymentPolicy: '',
    resortRules: '',
    petPolicy: '',
    safetyGuidelines: '',
    receptionOpenUntil: '',
    yearOpened: '',
    numberOfFloors: '',
    additionalSupplements: '',
    addonPrices: {
      'Boat ride to falls': 1200,
      'Kayak': 1200,
      'Dinner': 400,
      'Lunch': 400,
      'Breakfast': 300,
      'Extra Bed': 200
    }
  });
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [uploading, setUploading] = useState(false);

  useEffect(() => {
    const loadProperty = async () => {
      const snap = await get(ref(db, `properties/${uid}`));
      if (snap.exists()) {
        const data = snap.val();
        setFormData({
          name: data.name || '',
          description: data.description || '',
          type: data.type || 'Resort',
          rooms: data.rooms || 0,
          staffCount: data.staffCount || 0,
          maxCapacity: data.maxCapacity || 0,
          checkInTime: data.checkInTime || '',
          checkOutTime: data.checkOutTime || '',
          bookingInstructions: data.bookingInstructions || '',
          latitude: data.latitude || 0,
          longitude: data.longitude || 0,
          contactPhone: data.contactPhone || '',
          contactEmail: data.contactEmail || '',
          amenities: Array.isArray(data.amenities) ? data.amenities : (data.amenities ? Object.values(data.amenities) : []),
          gcashNumber: data.gcashNumber || '',
          gcashName: data.gcashName || '',
          gcashQrUrl: data.gcashQrUrl || '',
          imageUrls: data.imageUrls || [],
          videoUrls: data.videoUrls || [],
          cancellationPolicy: data.cancellationPolicy || '',
          paymentPolicy: data.paymentPolicy || '',
          resortRules: data.resortRules || '',
          petPolicy: data.petPolicy || '',
          safetyGuidelines: data.safetyGuidelines || '',
          receptionOpenUntil: data.receptionOpenUntil || '',
          yearOpened: data.yearOpened || '',
          numberOfFloors: data.numberOfFloors || '',
          additionalSupplements: data.additionalSupplements || '',
          addonPrices: data.addonPrices || {
            'Boat ride': 1200,
            'Kayak': 1200,
            'Meals': 300,
            'Dinner': 500,
            'Lunch': 400,
            'Breakfast': 300,
            'Extra Bed': 200
          }
        });
      }
    };
    loadProperty();
  }, [uid]);

  const handleUpload = async (e, type = 'image') => {
    const files = Array.from(e.target.files);
    if (files.length === 0) return;

    setUploading(true);
    const newUrls = type === 'image' ? [...formData.imageUrls] : [...formData.videoUrls];

    for (const file of files) {
      const data = new FormData();
      data.append('file', file);
      data.append('upload_preset', 'resort_unsigned');
      const resourceType = type === 'video' ? 'video' : 'image';

      try {
        const response = await fetch(`https://api.cloudinary.com/v1_1/dnv6ezitm/${resourceType}/upload`, {
          method: 'POST',
          body: data,
        });
        const res = await response.json();
        newUrls.push(res.secure_url);
      } catch (error) {
        console.error('Upload failed', error);
      }
    }

    setFormData({ ...formData, [type === 'image' ? 'imageUrls' : 'videoUrls']: newUrls });
    setUploading(false);
  };

  const handleQrUpload = async (e) => {
    const file = e.target.files[0];
    if (!file) return;

    setUploading(true);
    const data = new FormData();
    data.append('file', file);
    data.append('upload_preset', 'resort_unsigned');

    try {
      const response = await fetch(`https://api.cloudinary.com/v1_1/dnv6ezitm/image/upload`, {
        method: 'POST',
        body: data,
      });
      const res = await response.json();
      setFormData({ ...formData, gcashQrUrl: res.secure_url });
    } catch (error) {
      console.error('QR Upload failed', error);
    }
    setUploading(false);
  };

  const validate = () => {
    const { name, gcashNumber, description } = formData;
    if (!name || name.trim().length < 3) return 'Property name must be at least 3 characters';
    if (description && description.length > 1000) return 'Description is too long (max 1000 characters)';
    if (gcashNumber && (gcashNumber.length !== 11 || !gcashNumber.startsWith('09'))) {
      return 'GCash number must be 11 digits and start with 09';
    }
    const { rooms, maxCapacity, gcashName } = formData;
    if (rooms && parseInt(rooms) < 0) return 'Total rooms cannot be negative';
    if (rooms && parseInt(rooms) > 9999) return 'Total rooms cannot exceed 9,999';
    if (maxCapacity && parseInt(maxCapacity) < 0) return 'Total guest capacity cannot be negative';
    if (maxCapacity && parseInt(maxCapacity) > 99999) return 'Total guest capacity cannot exceed 99,999';
    
    const gName = gcashName ? gcashName.trim() : '';
    if (gName && !/^[a-zA-Z\s\.]+$/.test(gName)) {
      return 'GCash account name can only contain letters, spaces, and periods.';
    }
    
    return null;
  };

  const amenityOptions = [
    'Swimming Pool', 'Free WiFi', 'Parking', 'Restaurant', 'Bar', 'Gym',
    'Spa', 'Beachfront', 'Air Conditioning', 'Pet Friendly', 'Laundry Service'
  ];

  const handleEmojiFilter = (value) => {
    return value.replace(/[^\w\s.,'()?:-]/g, '');
  };

  const toggleAmenity = (item) => {
    const next = formData.amenities.includes(item)
      ? formData.amenities.filter(a => a !== item)
      : [...formData.amenities, item];
    setFormData({ ...formData, amenities: next });
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
      await update(ref(db, `properties/${uid}`), {
        ...formData,
        updatedAt: Date.now()
      });
      onClose();
    } catch (error) {
      alert('Error updating property: ' + error.message);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="modal-overlay">
      <div className="card modal-content view-transition" style={{ maxWidth: '650px', borderRadius: '32px', padding: '32px' }}>
        <button
          onClick={onClose}
          style={{
            display: 'flex', alignItems: 'center', gap: '8px',
            background: 'var(--surface)', border: '1px solid var(--border)', cursor: 'pointer',
            marginBottom: '24px', color: 'var(--text-main)',
            fontWeight: 700, padding: '10px 18px', borderRadius: '14px',
            boxShadow: 'var(--shadow)'
          }}
        >
          <ArrowLeft size={18} /> Back to Dashboard
        </button>

        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '32px' }}>
          <h2 style={{ margin: 0, fontSize: '24px', fontWeight: 800 }}>Business Profile</h2>
          <button onClick={onClose} className="close-btn"><X size={20} /></button>
        </div>

        <form onSubmit={handleSubmit}>
          {/* Photos Section */}
          <div style={{ marginBottom: '32px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '16px' }}>
               <ImageIcon size={20} color="var(--primary)" />
               <label className="input-label" style={{ marginBottom: 0 }}>Gallery & Media</label>
            </div>
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
                <Camera color="var(--secondary)" size={24} />
                <input type="file" multiple hidden accept="image/*" onChange={(e) => handleUpload(e, 'image')} disabled={uploading} />
              </label>
            </div>
          </div>

          {/* Videos Section */}
          <div style={{ marginBottom: '32px' }}>
            <div style={{ display: 'flex', gap: '12px', overflowX: 'auto', paddingBottom: '12px', scrollbarWidth: 'none' }}>
              {formData.videoUrls.map((url, i) => (
                <div key={i} style={{ position: 'relative', minWidth: '140px', height: '90px', background: '#000', borderRadius: '20px', display: 'flex', justifyContent: 'center', alignItems: 'center', overflow: 'hidden' }}>
                  <Video color="white" />
                  <button
                    type="button"
                    onClick={() => setFormData({...formData, videoUrls: formData.videoUrls.filter((_, idx) => idx !== i)})}
                    style={{ position: 'absolute', top: '6px', right: '6px', background: 'rgba(0,0,0,0.5)', color: 'white', border: 'none', borderRadius: '50%', width: '24px', height: '24px', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', backdropFilter: 'blur(4px)' }}
                  >
                    <X size={14} />
                  </button>
                </div>
              ))}
              <label className="media-upload-btn" style={{ minWidth: '140px', height: '90px' }}>
                <Video color="var(--primary)" size={24} />
                <input type="file" multiple hidden accept="video/*" onChange={(e) => handleUpload(e, 'video')} disabled={uploading} />
              </label>
            </div>
          </div>

          <div style={{ background: 'var(--light-bg)', padding: '24px', borderRadius: '24px', marginBottom: '24px', border: '1px solid var(--border)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '20px' }}>
               <Info size={20} color="var(--secondary)" />
               <h4 style={{ margin: 0, fontSize: '16px', fontWeight: 800 }}>General Information</h4>
            </div>

            <div className="marginBottom-20">
              <label className="input-label">Property Name</label>
              <input className="input" value={formData.name} onChange={e => setFormData({...formData, name: handleEmojiFilter(e.target.value)})} required maxLength="50" />
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px', marginBottom: '20px' }}>
              <div>
                <label className="input-label">Check-in Time</label>
                <input type="time" className="input" placeholder="e.g. 2:00 PM" value={formData.checkInTime} onChange={e => setFormData({...formData, checkInTime: handleEmojiFilter(e.target.value)})} />
              </div>
              <div>
                <label className="input-label">Check-out Time</label>
                <input type="time" className="input" placeholder="e.g. 12:00 PM" value={formData.checkOutTime} onChange={e => setFormData({...formData, checkOutTime: handleEmojiFilter(e.target.value)})} />
              </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '20px', marginBottom: '20px' }}>
              <div>
                <label className="input-label">Reception Open Until</label>
                <input className="input" placeholder="e.g. 10:00 AM" value={formData.receptionOpenUntil} onChange={e => setFormData({...formData, receptionOpenUntil: handleEmojiFilter(e.target.value)})} />
              </div>
              <div>
                <label className="input-label">Year Opened</label>
                <input className="input" type="number" placeholder="e.g. 2012" value={formData.yearOpened} onChange={e => setFormData({...formData, yearOpened: e.target.value})} />
              </div>
              <div>
                <label className="input-label">Number of Floors</label>
                <input className="input" type="number" placeholder="e.g. 2" value={formData.numberOfFloors} onChange={e => setFormData({...formData, numberOfFloors: e.target.value})} />
              </div>
            </div>

            <div style={{ marginBottom: '20px' }}>
              <label className="input-label">Booking Instructions / Rules</label>
              <textarea className="input" style={{ height: '80px', resize: 'none' }} placeholder="House rules, booking process, etc." value={formData.bookingInstructions} onChange={e => setFormData({...formData, bookingInstructions: handleEmojiFilter(e.target.value)})} maxLength="1000" />
            </div>

            <div style={{ marginBottom: '20px' }}>
              <label className="input-label">Additional Supplements (Others)</label>
              <textarea className="input" style={{ height: '80px', resize: 'none' }} placeholder="e.g. When booking more than 5 rooms, different policies and additional supplements may apply." value={formData.additionalSupplements} onChange={e => setFormData({...formData, additionalSupplements: handleEmojiFilter(e.target.value)})} maxLength="1000" />
            </div>

            <div style={{ marginBottom: '20px' }}>
              <label className="input-label" style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span>Pin Location on Map</span>
                <span>{formData.latitude !== 0 ? `${parseFloat(formData.latitude).toFixed(5)}, ${parseFloat(formData.longitude).toFixed(5)}` : 'Click map to drop pin'}</span>
              </label>
              <div style={{ height: '250px', width: '100%', borderRadius: '16px', overflow: 'hidden', border: '1px solid var(--border)', background: '#e0e0e0' }}>
                <MapContainer center={[12.8797, 121.7740]} zoom={5} style={{ height: '100%', width: '100%', zIndex: 0 }}>
                  <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" attribution="&copy; OpenStreetMap" />
                  <LocationPicker 
                    position={{ lat: formData.latitude || 0, lng: formData.longitude || 0 }} 
                    setPosition={(pos) => setFormData({...formData, latitude: pos.lat, longitude: pos.lng})} 
                  />
                </MapContainer>
              </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px', marginBottom: '20px' }}>
              <div>
                <label className="input-label">Total Rooms</label>
                <input type="number" className="input" value={formData.rooms} onChange={e => setFormData({...formData, rooms: parseInt(e.target.value) || 0})} min="0" max="9999" />
              </div>
              <div>
                <label className="input-label">Total Guest Capacity</label>
                <input type="number" className="input" value={formData.maxCapacity} onChange={e => setFormData({...formData, maxCapacity: parseInt(e.target.value) || 0})} min="0" max="9999" />
              </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px', marginBottom: '20px' }}>
              <div>
                <label className="input-label">Contact Phone</label>
                <input className="input" placeholder="09XX XXX XXXX" value={formData.contactPhone} onChange={e => setFormData({...formData, contactPhone: e.target.value.replace(/\D/g, '')})} maxLength="11" />
              </div>
              <div>
                <label className="input-label">Contact Email</label>
                <input type="email" className="input" placeholder="resort@example.com" value={formData.contactEmail} onChange={e => setFormData({...formData, contactEmail: e.target.value})} />
              </div>
            </div>

            <div>
              <label className="input-label">About the property</label>
              <textarea className="input" style={{ height: '120px', resize: 'none' }} value={formData.description} onChange={e => setFormData({...formData, description: handleEmojiFilter(e.target.value)})} maxLength="1000" />
            </div>
          </div>

          <div style={{ background: 'var(--light-bg)', padding: '24px', borderRadius: '24px', marginBottom: '24px', border: '1px solid var(--border)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '20px' }}>
               <PlusSquare size={20} color="var(--primary)" />
               <h4 style={{ margin: 0, fontSize: '16px', fontWeight: 800 }}>Amenities</h4>
            </div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: '10px' }}>
              {amenityOptions.map(a => (
                <button
                  key={a} type="button"
                  onClick={() => toggleAmenity(a)}
                  className={`inclusion-pill ${formData.amenities.includes(a) ? 'active' : ''}`}
                  style={{
                    padding: '8px 16px', borderRadius: '12px', border: '2px solid var(--border)',
                    background: formData.amenities.includes(a) ? 'rgba(29, 211, 176, 0.1)' : 'var(--surface)',
                    fontSize: '13px', fontWeight: 700, color: formData.amenities.includes(a) ? 'var(--secondary)' : 'var(--text-muted)',
                    cursor: 'pointer'
                  }}
                >
                  {a}
                </button>
              ))}
            </div>
          </div>

          {/* Policies Section */}
          <div style={{ background: 'var(--light-bg)', padding: '24px', borderRadius: '24px', marginBottom: '24px', border: '1px solid var(--border)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '20px' }}>
               <Info size={20} color="var(--primary)" />
               <h4 style={{ margin: 0, fontSize: '16px', fontWeight: 800 }}>Policies & Guidelines</h4>
            </div>
            
            <div style={{ marginBottom: '20px' }}>
              <label className="input-label">Cancellation & Refund Policy</label>
              <textarea className="input" style={{ height: '80px', resize: 'none' }} placeholder="e.g. Full refund if cancelled 7 days prior." value={formData.cancellationPolicy} onChange={e => setFormData({...formData, cancellationPolicy: handleEmojiFilter(e.target.value)})} maxLength="500" />
            </div>
            
            <div style={{ marginBottom: '20px' }}>
              <label className="input-label">Payment Policies</label>
              <textarea className="input" style={{ height: '80px', resize: 'none' }} placeholder="e.g. Partial deposit required upon booking." value={formData.paymentPolicy} onChange={e => setFormData({...formData, paymentPolicy: handleEmojiFilter(e.target.value)})} maxLength="500" />
            </div>
            
            <div style={{ marginBottom: '20px' }}>
              <label className="input-label">Resort Rules</label>
              <textarea className="input" style={{ height: '80px', resize: 'none' }} placeholder="e.g. No smoking inside rooms, quiet hours." value={formData.resortRules} onChange={e => setFormData({...formData, resortRules: handleEmojiFilter(e.target.value)})} maxLength="1000" />
            </div>
            
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px', marginBottom: '20px' }}>
              <div>
                <label className="input-label">Pet Policy</label>
                <textarea className="input" style={{ height: '80px', resize: 'none' }} placeholder="e.g. Pets allowed in designated rooms." value={formData.petPolicy} onChange={e => setFormData({...formData, petPolicy: handleEmojiFilter(e.target.value)})} maxLength="300" />
              </div>
              <div>
                <label className="input-label">Safety Guidelines</label>
                <textarea className="input" style={{ height: '80px', resize: 'none' }} placeholder="e.g. Pool safety, emergency exits." value={formData.safetyGuidelines} onChange={e => setFormData({...formData, safetyGuidelines: handleEmojiFilter(e.target.value)})} maxLength="300" />
              </div>
            </div>
          </div>

          <div style={{ background: 'var(--light-bg)', padding: '24px', borderRadius: '24px', marginBottom: '32px', border: '1px solid var(--border)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '20px' }}>
               <Wallet size={20} color="var(--primary)" />
               <h4 style={{ margin: 0, fontSize: '16px', fontWeight: 800 }}>Add-ons & Extras Prices</h4>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(260px, 1fr))', gap: '16px' }}>
              {Object.keys(formData.addonPrices).map(addon => (
                <div key={addon} style={{ display: 'flex', flexDirection: 'column', gap: '8px', background: 'var(--surface)', padding: '16px', borderRadius: '16px', border: '1px solid var(--border)', boxShadow: '0 2px 8px rgba(0,0,0,0.05)' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '4px' }}>
                    <span style={{ fontWeight: 800, fontSize: '13px', color: 'var(--text-muted)', textTransform: 'uppercase' }}>Add-on Name</span>
                    <button
                      type="button"
                      onClick={() => {
                        const newAddonPrices = { ...formData.addonPrices };
                        delete newAddonPrices[addon];
                        setFormData({ ...formData, addonPrices: newAddonPrices });
                      }}
                      style={{ background: 'rgba(239, 68, 68, 0.1)', color: '#EF4444', border: 'none', borderRadius: '50%', width: '28px', height: '28px', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}
                      title="Remove Add-on"
                    >
                      <X size={14} strokeWidth={3} />
                    </button>
                  </div>
                  <input
                    type="text"
                    className="input"
                    defaultValue={addon}
                    maxLength="30"
                    onChange={e => { e.target.value = handleEmojiFilter(e.target.value); }}
                    onBlur={e => {
                      let newName = handleEmojiFilter(e.target.value).trim();
                      if (newName && newName !== addon && formData.addonPrices[newName] === undefined) {
                        const newAddonPrices = { ...formData.addonPrices };
                        newAddonPrices[newName] = newAddonPrices[addon];
                        delete newAddonPrices[addon];
                        setFormData({ ...formData, addonPrices: newAddonPrices });
                      } else {
                        e.target.value = addon; // Revert if empty or duplicate
                      }
                    }}
                  />
                  <span style={{ fontWeight: 800, fontSize: '13px', color: 'var(--text-muted)', textTransform: 'uppercase', marginTop: '8px' }}>Price (₱)</span>
                  <div style={{ position: 'relative' }}>
                    <span style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)', fontWeight: 700 }}>₱</span>
                    <input
                      type="number"
                      className="input"
                      value={formData.addonPrices[addon]}
                      onChange={e => {
                        let val = parseInt(e.target.value) || 0;
                        if (val > 10000) val = 10000;
                        setFormData({
                          ...formData,
                          addonPrices: {
                            ...formData.addonPrices,
                            [addon]: val
                          }
                        });
                      }}
                      min="0"
                      max="10000"
                      style={{ paddingLeft: '28px', width: '100%' }}
                    />
                  </div>
                </div>
              ))}
            </div>

            <div style={{ marginTop: '20px', display: 'flex', gap: '10px' }}>
              <input 
                 type="text" 
                 id="newAddonName" 
                 className="input" 
                 placeholder="Custom Add-on Name" 
                 maxLength="30"
                 onChange={e => { e.target.value = handleEmojiFilter(e.target.value); }}
                 style={{ flex: 1 }} 
              />
              <button 
                 type="button" 
                 className="btn-primary" 
                 style={{ padding: '0 20px', whiteSpace: 'nowrap' }}
                 onClick={() => {
                   const inputEl = document.getElementById('newAddonName');
                   const name = handleEmojiFilter(inputEl.value).trim();
                   if (name && !formData.addonPrices[name]) {
                     setFormData({
                       ...formData,
                       addonPrices: { ...formData.addonPrices, [name]: 0 }
                     });
                     document.getElementById('newAddonName').value = '';
                   }
                 }}
              >
                + Add
              </button>
            </div>
          </div>

          <div style={{ background: 'var(--light-bg)', padding: '24px', borderRadius: '24px', marginBottom: '32px', border: '1px solid var(--border)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '20px' }}>
               <Wallet size={20} color="var(--primary)" />
               <h4 style={{ margin: 0, fontSize: '16px', fontWeight: 800 }}>Payment Settings</h4>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px' }}>
              <div>
                <label className="input-label">GCash Number</label>
                <input className="input" value={formData.gcashNumber} onChange={e => setFormData({...formData, gcashNumber: handleEmojiFilter(e.target.value.replace(/\D/g, ''))})} placeholder="09XX XXX XXXX" maxLength="11" />
              </div>
              <div>
                <label className="input-label">Account Name</label>
                <input className="input" value={formData.gcashName} onChange={e => setFormData({...formData, gcashName: e.target.value.replace(/[^a-zA-Z\s\.]/g, '')})} placeholder="Registered Name" maxLength="50" />
              </div>
            </div>
            
            <div style={{ marginTop: '20px' }}>
              <label className="input-label">GCash QR Code Photo</label>
              <div style={{ display: 'flex', gap: '16px', alignItems: 'center' }}>
                {formData.gcashQrUrl ? (
                  <div style={{ position: 'relative', width: '120px', height: '120px' }}>
                    <img src={formData.gcashQrUrl} alt="GCash QR" style={{ width: '100%', height: '100%', objectFit: 'contain', borderRadius: '12px', border: '1px solid var(--border)' }} />
                    <button
                      type="button"
                      onClick={() => setFormData({...formData, gcashQrUrl: ''})}
                      style={{ position: 'absolute', top: '-8px', right: '-8px', background: 'var(--error, #EF4444)', color: 'white', border: 'none', borderRadius: '50%', width: '24px', height: '24px', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}
                    >
                      <X size={14} />
                    </button>
                  </div>
                ) : (
                  <label className="media-upload-btn" style={{ minWidth: '120px', height: '120px', margin: 0 }}>
                    <Camera color="var(--primary)" size={24} />
                    <span style={{ fontSize: '11px', marginTop: '4px', fontWeight: 600 }}>Upload QR</span>
                    <input type="file" hidden accept="image/*" onChange={handleQrUpload} disabled={uploading} />
                  </label>
                )}
                <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Upload your GCash QR code so guests can scan it directly when booking.</span>
              </div>
            </div>
          </div>

          <button type="submit" className="btn btn-primary" style={{ width: '100%', height: '60px', borderRadius: '20px' }} disabled={isSubmitting || uploading}>
            {isSubmitting ? <div className="loader" style={{ width: '20px', height: '20px', borderTopColor: 'white' }}></div> : 'PUBLISH CHANGES'}
          </button>
        </form>
      </div>

      <style>{`
        .input-label { display: block; font-size: 11px; font-weight: 800; color: var(--text-muted); margin-bottom: 8px; text-transform: uppercase; letter-spacing: 1px; }
        .media-upload-btn { min-width: 110px; height: 110px; border: 2px dashed var(--border-dashed); border-radius: 20px; display: flex; flex-direction: column; justify-content: center; align-items: center; cursor: pointer; transition: var(--transition); background: var(--light-bg); }
        .media-upload-btn:hover { border-color: var(--secondary); background: var(--surface); }
        .close-btn { background: var(--light-bg); border: none; width: 36px; height: 36px; border-radius: 50%; display: flex; align-items: center; justify-content: center; cursor: pointer; color: var(--text-main); transition: var(--transition); border: 1px solid var(--border); }
        .close-btn:hover { background: var(--surface); transform: rotate(90deg); }
      `}</style>
    </div>
  );
};

export default EditPropertyModal;
