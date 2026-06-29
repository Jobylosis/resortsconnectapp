import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, onValue } from 'firebase/database';
import { ArrowLeft, MapPin, Clock, ShieldAlert, CreditCard, Info, AlertTriangle, Dog, CheckCircle, Navigation, Phone, Mail, Building, Map, Key, Hash, Calendar, Car, Bus, Users } from 'lucide-react';
import { MapContainer, TileLayer, Marker, Popup } from 'react-leaflet';

const PoliciesPropertyDetails = ({ property, onBack, ownerUid }) => {
  const [properties, setProperties] = useState([]);
  const [selectedPropId, setSelectedPropId] = useState(property ? property.id || property.uid : null);
  const [loading, setLoading] = useState(!property);

  useEffect(() => {
    if (property) {
      setLoading(false);
      return;
    }
    const propsRef = ref(db, 'properties');
    const unsub = onValue(propsRef, (snap) => {
      const data = snap.val();
      if (data) {
        let list = Object.entries(data).map(([id, val]) => ({ id, uid: val.ownerUid || id, ...val }));
        if (ownerUid) {
          list = list.filter(p => p.id === ownerUid || p.ownerUid === ownerUid);
        }
        setProperties(list);
        if (list.length > 0 && !selectedPropId) {
          setSelectedPropId(list[0].id);
        }
      }
      setLoading(false);
    });
    return () => unsub();
  }, [property, selectedPropId, ownerUid]);

  const currentProperty = property || properties.find(p => p.id === selectedPropId);

  const parseList = (data) => {
    if (!data) return [];
    if (Array.isArray(data)) return data.filter(e => e != null);
    if (typeof data === 'object') return Object.values(data);
    return [];
  };

  return (
    <div className="view-transition" style={{ minHeight: '100vh', background: 'var(--light-bg)', paddingBottom: '80px' }}>
      <div style={{ background: 'var(--nav-bg)', padding: '16px 24px', borderBottom: '1px solid var(--border)', position: 'sticky', top: 0, zIndex: 1000, display: 'flex', alignItems: 'center', gap: '16px' }}>
        {onBack && (
          <button onClick={onBack} className="btn" style={{ background: 'var(--surface)', border: '1px solid var(--border)', padding: '8px 12px' }}>
            <ArrowLeft size={18} />
          </button>
        )}
        <h2 style={{ margin: 0, fontSize: '20px', fontWeight: 800 }}>Policies & Property Information</h2>
      </div>

      <div style={{ maxWidth: '1000px', margin: '32px auto', padding: '0 24px' }}>
        {!property && properties.length > 1 && (
          <div className="card" style={{ marginBottom: '24px', padding: '24px' }}>
            <label style={{ fontWeight: 700, fontSize: '14px', color: 'var(--text-muted)', marginBottom: '8px', display: 'block' }}>Select a Resort to view its policies:</label>
            <select 
              value={selectedPropId || ''} 
              onChange={(e) => setSelectedPropId(e.target.value)}
              className="input"
              style={{ fontSize: '16px', padding: '12px', borderRadius: '12px', border: '2px solid var(--border)', background: 'var(--surface)' }}
            >
              {properties.map(p => (
                <option key={p.id} value={p.id}>{p.name}</option>
              ))}
            </select>
          </div>
        )}

        {loading ? (
          <div style={{ textAlign: 'center', padding: '100px 0' }}><div className="loader" style={{ margin: '0 auto' }}></div></div>
        ) : !currentProperty ? (
          <div style={{ textAlign: 'center', padding: '80px 0', color: 'var(--text-muted)' }}>Property not found.</div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
            {/* Header section */}
            <div className="card" style={{ padding: '32px', background: 'var(--primary)', color: 'white' }}>
              <div style={{ display: 'flex', gap: '12px', alignItems: 'center', marginBottom: '16px' }}>
                <Building size={28} />
                <h1 style={{ margin: 0, fontSize: '28px', fontWeight: 900 }}>{currentProperty.name}</h1>
              </div>
              <p style={{ margin: 0, fontSize: '15px', opacity: 0.9, lineHeight: 1.6 }}>{currentProperty.description || "Experience a wonderful stay with our verified partner resort. Please review the policies and details below to ensure a smooth and enjoyable visit."}</p>
            </div>

            {/* Others / Supplements */}
            {(currentProperty.additionalSupplements || currentProperty.rooms > 5) && (
              <div className="card" style={{ padding: '32px' }}>
                <h3 style={{ margin: '0 0 16px 0', fontSize: '20px', fontWeight: 800 }}>Others</h3>
                <ul style={{ margin: 0, paddingLeft: '20px', color: 'var(--text-main)', fontSize: '15px', lineHeight: 1.6 }}>
                  <li>{currentProperty.additionalSupplements || 'When booking more than 5 rooms, different policies and additional supplements may apply.'}</li>
                </ul>
              </div>
            )}

            {/* Some helpful facts */}
            <div className="card" style={{ padding: '32px' }}>
              <h3 style={{ margin: '0 0 24px 0', fontSize: '22px', fontWeight: 800 }}>Some helpful facts</h3>
              
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(250px, 1fr))', gap: '32px' }}>
                
                {/* Check-in/Check-out Column */}
                <div>
                  <h4 style={{ margin: '0 0 16px 0', fontSize: '16px', fontWeight: 800 }}>Check-in/Check-out</h4>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                      <Users size={20} color="var(--text-muted)" />
                      <span style={{ fontSize: '15px', color: 'var(--text-main)' }}>Check-in from: {currentProperty.checkInTime || '02:00 PM'}</span>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                      <Users size={20} color="var(--text-muted)" />
                      <span style={{ fontSize: '15px', color: 'var(--text-main)' }}>Check-out until: {currentProperty.checkOutTime || '12:00 PM'}</span>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                      <Clock size={20} color="var(--text-muted)" />
                      <span style={{ fontSize: '15px', color: 'var(--text-main)' }}>Reception open until: {currentProperty.receptionOpenUntil || '10:00 PM'}</span>
                    </div>
                  </div>
                </div>

                {/* The property Column */}
                <div>
                  <h4 style={{ margin: '0 0 16px 0', fontSize: '16px', fontWeight: 800 }}>The property</h4>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                      <Calendar size={20} color="var(--text-muted)" />
                      <span style={{ fontSize: '15px', color: 'var(--text-main)' }}>Year property opened: {currentProperty.yearOpened || 'N/A'}</span>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                      <Hash size={20} color="var(--text-muted)" />
                      <span style={{ fontSize: '15px', color: 'var(--text-main)' }}>Number of floors: {currentProperty.numberOfFloors || '1'}</span>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                      <Key size={20} color="var(--text-muted)" />
                      <span style={{ fontSize: '15px', color: 'var(--text-main)' }}>Number of rooms: {currentProperty.rooms || 'N/A'}</span>
                    </div>
                  </div>
                </div>

                {/* Getting around & Parking */}
                <div>
                  <h4 style={{ margin: '0 0 16px 0', fontSize: '16px', fontWeight: 800 }}>Getting around</h4>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', marginBottom: '24px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                      <Bus size={20} color="var(--text-muted)" />
                      <span style={{ fontSize: '15px', color: 'var(--text-main)' }}>Airport transfer available</span>
                    </div>
                  </div>

                  <h4 style={{ margin: '0 0 16px 0', fontSize: '16px', fontWeight: 800 }}>Parking</h4>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                      <Car size={20} color="var(--text-muted)" />
                      <span style={{ fontSize: '15px', color: 'var(--text-main)' }}>On-site parking available</span>
                    </div>
                  </div>
                </div>

              </div>
            </div>

            {/* Policies Grid */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: '24px' }}>
              <div className="card" style={{ padding: '24px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '16px' }}>
                  <ShieldAlert size={20} color="#DC2626" />
                  <h4 style={{ margin: 0, fontSize: '16px', fontWeight: 800 }}>Cancellation & Refunds</h4>
                </div>
                <p style={{ margin: 0, fontSize: '14px', color: 'var(--text-muted)', lineHeight: 1.6, whiteSpace: 'pre-line' }}>
                  {currentProperty.cancellationPolicy?.trim() || "Cancellations made 7 days prior to the check-in date are eligible for a full refund. Cancellations made within 7 days may be subject to a 50% cancellation fee. No-shows will be charged the full amount."}
                </p>
              </div>

              <div className="card" style={{ padding: '24px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '16px' }}>
                  <CreditCard size={20} color="#2563EB" />
                  <h4 style={{ margin: 0, fontSize: '16px', fontWeight: 800 }}>Payment Policies</h4>
                </div>
                <p style={{ margin: 0, fontSize: '14px', color: 'var(--text-muted)', lineHeight: 1.6, whiteSpace: 'pre-line' }}>
                  {currentProperty.paymentPolicy?.trim() || "We only accept GCash as our payment method. A partial deposit may be required to secure your booking. Full payment must be settled upon check-in or through the app before arrival."}
                </p>
              </div>

              <div className="card" style={{ padding: '24px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '16px' }}>
                  <AlertTriangle size={20} color="#D97706" />
                  <h4 style={{ margin: 0, fontSize: '16px', fontWeight: 800 }}>Resort Rules</h4>
                </div>
                <p style={{ margin: 0, fontSize: '14px', color: 'var(--text-muted)', lineHeight: 1.6, whiteSpace: 'pre-line' }}>
                  {currentProperty.resortRules?.trim() || "• No smoking inside rooms. Designated smoking areas are provided.\n• Quiet hours are from 10:00 PM to 7:00 AM.\n• Outside food and drinks may be subject to a corkage fee.\n• Proper swimwear is required in all pool areas."}
                </p>
              </div>

              <div className="card" style={{ padding: '24px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '16px' }}>
                  <Dog size={20} color="#7C3AED" />
                  <h4 style={{ margin: 0, fontSize: '16px', fontWeight: 800 }}>Pet Policy</h4>
                </div>
                <p style={{ margin: 0, fontSize: '14px', color: 'var(--text-muted)', lineHeight: 1.6, whiteSpace: 'pre-line' }}>
                  {currentProperty.petPolicy?.trim() || "Pets are generally allowed in designated pet-friendly rooms only. An additional pet cleaning fee may apply. Pets must be leashed in public areas at all times."}
                </p>
              </div>
              
              <div className="card" style={{ padding: '24px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '16px' }}>
                  <Info size={20} color="#059669" />
                  <h4 style={{ margin: 0, fontSize: '16px', fontWeight: 800 }}>Safety Guidelines</h4>
                </div>
                <p style={{ margin: 0, fontSize: '14px', color: 'var(--text-muted)', lineHeight: 1.6, whiteSpace: 'pre-line' }}>
                  {currentProperty.safetyGuidelines?.trim() || "For your safety and security, please familiarize yourself with the emergency exits. Unaccompanied minors are not allowed in the pool area. Do not leave valuables unattended."}
                </p>
              </div>
            </div>

            {/* Amenities & Contact */}
            <div className="card" style={{ padding: '32px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '24px' }}>
                <Info size={24} color="var(--primary)" />
                <h3 style={{ margin: 0, fontSize: '20px', fontWeight: 800 }}>Property Facilities & Contact</h3>
              </div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '32px' }}>
                <div style={{ flex: '1 1 300px' }}>
                  <h4 style={{ margin: '0 0 12px 0', fontSize: '15px', fontWeight: 700, color: 'var(--text-main)' }}>Amenities</h4>
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: '12px' }}>
                    {parseList(currentProperty.amenities).length > 0 ? parseList(currentProperty.amenities).map((a, i) => (
                      <div key={i} style={{ display: 'flex', alignItems: 'center', gap: '6px', background: 'var(--light-bg)', padding: '6px 12px', borderRadius: '8px', fontSize: '13px', fontWeight: 600 }}>
                        <CheckCircle size={14} color="var(--secondary)" /> {a}
                      </div>
                    )) : (
                      <span style={{ fontSize: '14px', color: 'var(--text-muted)' }}>Amenities not listed.</span>
                    )}
                  </div>
                </div>
                <div style={{ flex: '1 1 300px' }}>
                  <h4 style={{ margin: '0 0 12px 0', fontSize: '15px', fontWeight: 700, color: 'var(--text-main)' }}>Contact Details</h4>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '10px', fontSize: '14px', color: 'var(--text-muted)' }}>
                      <Phone size={16} /> {currentProperty.contactPhone || 'Contact number not provided'}
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '10px', fontSize: '14px', color: 'var(--text-muted)' }}>
                      <Mail size={16} /> {currentProperty.contactEmail || 'Email not provided'}
                    </div>
                  </div>
                </div>
              </div>
            </div>

            {/* Interactive Map */}
            {(currentProperty.latitude !== undefined && currentProperty.longitude !== undefined && currentProperty.latitude !== 0) ? (
              <div className="card" style={{ padding: '32px' }}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '24px', flexWrap: 'wrap', gap: '16px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                    <Map size={24} color="var(--secondary)" />
                    <h3 style={{ margin: 0, fontSize: '20px', fontWeight: 800 }}>Location Map</h3>
                  </div>
                  <a href={`https://www.google.com/maps/dir/?api=1&destination=${currentProperty.latitude},${currentProperty.longitude}`} target="_blank" rel="noreferrer" className="btn btn-primary" style={{ padding: '10px 20px', borderRadius: '12px', display: 'flex', alignItems: 'center', gap: '8px', textDecoration: 'none' }}>
                    <Navigation size={18} /> View Location / Directions
                  </a>
                </div>
                <p style={{ margin: '0 0 16px 0', fontSize: '14px', color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: '6px' }}>
                  <MapPin size={16} /> {currentProperty.address || 'Address not provided by owner.'}
                </p>
                <div style={{ height: '400px', width: '100%', borderRadius: '20px', overflow: 'hidden', border: '1px solid var(--border)', zIndex: 0, boxShadow: 'var(--shadow)' }}>
                  <MapContainer center={[currentProperty.latitude, currentProperty.longitude]} zoom={15} style={{ height: '100%', width: '100%', zIndex: 0 }}>
                    <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" attribution="&copy; OpenStreetMap" />
                    <Marker position={[currentProperty.latitude, currentProperty.longitude]}>
                      <Popup>
                        <strong style={{ fontSize: '14px' }}>{currentProperty.name}</strong><br/>
                        {currentProperty.address}
                      </Popup>
                    </Marker>
                  </MapContainer>
                </div>
              </div>
            ) : (
              <div className="card" style={{ padding: '32px', textAlign: 'center' }}>
                <Map size={48} color="var(--border)" style={{ margin: '0 auto 16px' }} />
                <h4 style={{ margin: '0 0 8px 0', fontSize: '18px', fontWeight: 700 }}>Location Map Unavailable</h4>
                <p style={{ margin: 0, color: 'var(--text-muted)', fontSize: '14px' }}>The exact map coordinates for this property have not been set.</p>
              </div>
            )}

          </div>
        )}
      </div>
    </div>
  );
};

export default PoliciesPropertyDetails;
