import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, onValue } from 'firebase/database';
import { ArrowLeft, MapPin, Users, Info, Star, MessageCircle, AlertCircle, Home, Users as UsersIcon, ShieldCheck, ChevronLeft, ChevronRight } from 'lucide-react';

const RoomCard = ({ room, onBookRoom, parseList }) => {
  const [imgIndex, setImgIndex] = useState(0);
  const images = parseList(room.imageUrls);

  const next = (e) => { e.stopPropagation(); setImgIndex(p => (p + 1) % images.length); };
  const prev = (e) => { e.stopPropagation(); setImgIndex(p => (p - 1 + images.length) % images.length); };

  return (
    <div className="card" style={{ padding: '16px', display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div style={{ position: 'relative', height: '200px', marginBottom: '20px', overflow: 'hidden', borderRadius: '16px' }}>
         <img
           src={images[imgIndex] || 'https://via.placeholder.com/400x300?text=Cozy+Room'}
           alt=""
           style={{ width: '100%', height: '100%', objectFit: 'cover' }}
         />

         {images.length > 1 && (
           <>
             <button onClick={prev} style={{ position: 'absolute', left: '8px', top: '50%', transform: 'translateY(-50%)', background: 'rgba(255,255,255,0.8)', border: 'none', borderRadius: '50%', width: '28px', height: '28px', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
               <ChevronLeft size={16} />
             </button>
             <button onClick={next} style={{ position: 'absolute', right: '8px', top: '50%', transform: 'translateY(-50%)', background: 'rgba(255,255,255,0.8)', border: 'none', borderRadius: '50%', width: '28px', height: '28px', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
               <ChevronRight size={16} />
             </button>
             <div style={{ position: 'absolute', bottom: '8px', left: '50%', transform: 'translateX(-50%)', display: 'flex', gap: '4px' }}>
                {images.map((_, i) => <div key={i} style={{ width: '5px', height: '5px', borderRadius: '50%', background: i === imgIndex ? 'white' : 'rgba(255,255,255,0.5)' }}></div>)}
             </div>
           </>
         )}

         <div style={{ position: 'absolute', top: '12px', right: '12px', background: 'rgba(255,255,255,0.95)', padding: '6px 14px', borderRadius: '12px', fontWeight: 800, color: 'var(--secondary)', boxShadow: '0 4px 12px rgba(0,0,0,0.1)' }}>
            ₱{room.price}
         </div>
      </div>

      <div style={{ flex: 1 }}>
        <h4 style={{ margin: '0 0 8px 0', fontSize: '20px', fontWeight: 800 }}>{room.title}</h4>
        <div style={{ display: 'flex', gap: '8px', marginBottom: '16px', flexWrap: 'wrap' }}>
          <span style={{ fontSize: '12px', color: 'var(--text-muted)', background: 'var(--light-bg)', padding: '4px 10px', borderRadius: '6px', fontWeight: 700 }}>{room.category}</span>
          <span style={{ fontSize: '12px', color: 'var(--text-muted)', background: 'var(--light-bg)', padding: '4px 10px', borderRadius: '6px', fontWeight: 700 }}>{room.location}</span>
          <span style={{ fontSize: '12px', color: 'var(--text-muted)', background: 'var(--light-bg)', padding: '4px 10px', borderRadius: '6px', fontWeight: 700 }}>Max Pax: {room.maxPax}</span>
        </div>
        <p style={{ fontSize: '14px', color: '#6B7280', marginBottom: '24px', lineHeight: '1.6', height: '3.2em', overflow: 'hidden' }}>{room.description}</p>
      </div>

      <button
        className="btn btn-primary"
        style={{ width: '100%', height: '52px' }}
        onClick={() => onBookRoom(room)}
      >
        Reserve Now
      </button>
    </div>
  );
};

const PropertyDetails = ({ propId, propertyData, onBack, onBookRoom, onChat }) => {
  const [property, setProperty] = useState(propertyData || null);
  const [rooms, setRooms] = useState([]);
  const [loading, setLoading] = useState(!propertyData);
  const [error, setError] = useState(null);
  const [ratingInfo, setRatingInfo] = useState({ rating: 0, count: 0 });
  const [galleryIndex, setGalleryIndex] = useState(0);

  const parseList = (data) => {
    if (!data) return [];
    if (Array.isArray(data)) return data.filter(e => e != null);
    if (typeof data === 'object') {
      return Object.keys(data).sort().map(k => data[k]);
    }
    return [];
  };

  useEffect(() => {
    if (!propId) return;

    const propRef = ref(db, `properties/${propId}`);
    const unsubscribeProp = onValue(propRef, (snapshot) => {
      const data = snapshot.val();
      if (data) {
        const uid = data.ownerUid || data.uid || (propertyData && propertyData.uid) || propId;
        setProperty({ ...data, id: propId, uid });
        setLoading(false);
        setError(null);
      } else if (!property && !propertyData) {
        setError('Property details currently unavailable.');
        setLoading(false);
      }
    }, (err) => {
      console.error("Property fetch error:", err);
      if (!property && !propertyData) {
        setError("Access denied or connection error.");
        setLoading(false);
      }
    });

    return () => {
      unsubscribeProp();
    };
  }, [propId, propertyData]);

  useEffect(() => {
    const currentProperty = property || propertyData;
    const ownerUid = currentProperty?.uid || propId;

    if (!ownerUid) return;

    const roomsRef = ref(db, `properties/${ownerUid}/roomInventory`);
    const unsubscribeRooms = onValue(roomsRef, (snapshot) => {
      const data = snapshot.val();
      let list = [];
      if (data) {
        list = Object.entries(data).map(([id, val]) => ({ id, ...val }));
      }
      setRooms(list);
    }, (err) => {
      console.error("Rooms fetch error:", err);
    });

    const reviewRef = ref(db, `reviews/${ownerUid}`);
    const unsubscribeReviews = onValue(reviewRef, (snapshot) => {
      const data = snapshot.val();
      if (data) {
        const vals = Object.values(data);
        const avg = vals.reduce((a, b) => a + (b.rating || 0), 0) / vals.length;
        setRatingInfo({ rating: avg, count: vals.length });
      } else {
        setRatingInfo({ rating: 0, count: 0 });
      }
    });

    return () => {
      unsubscribeRooms();
      unsubscribeReviews();
    };
  }, [propId, property, propertyData]);

  const currentProperty = property || propertyData;

  if (loading && !currentProperty) {
    return (
      <div style={{ padding: '100px 0', textAlign: 'center' }}>
        <div className="loader" style={{ margin: '0 auto 20px' }}></div>
        <p style={{ color: 'var(--text-muted)', fontWeight: 600 }}>Loading sanctuary...</p>
      </div>
    );
  }

  if (error && !currentProperty) {
    return (
      <div className="app-container" style={{ textAlign: 'center', paddingTop: '60px' }}>
        <div className="card" style={{ maxWidth: '500px', margin: '0 auto' }}>
          <AlertCircle size={64} color="var(--primary)" style={{ marginBottom: '24px' }} />
          <h3 style={{ fontSize: '24px', fontWeight: 800, margin: '0 0 12px 0' }}>Notice</h3>
          <p style={{ color: 'var(--text-muted)', marginBottom: '32px' }}>{error}</p>
          <button className="btn btn-primary" onClick={onBack} style={{ marginInline: 'auto' }}>
            Back to Search
          </button>
        </div>
      </div>
    );
  }

  if (!currentProperty) return null;

  const imageUrls = parseList(currentProperty.imageUrls);

  return (
    <div className="property-details" style={{ position: 'relative', paddingBottom: '100px' }}>
      <button
        onClick={onBack}
        style={{
          display: 'flex', alignItems: 'center', gap: '8px', background: 'white',
          border: 'none', cursor: 'pointer', marginBottom: '24px', color: 'var(--text-main)',
          fontWeight: 700, padding: '10px 18px', borderRadius: '14px', boxShadow: 'var(--shadow)'
        }}
      >
        <ArrowLeft size={18} /> Back to Explore
      </button>

      <div className="card" style={{ padding: 0, overflow: 'hidden', border: 'none', position: 'relative' }}>
        <div
          id="main-gallery"
          onScroll={(e) => {
            const index = Math.round(e.target.scrollLeft / e.target.offsetWidth);
            if (index !== galleryIndex) setGalleryIndex(index);
          }}
          style={{
            height: '450px', display: 'flex', overflowX: 'auto',
            scrollSnapType: 'x mandatory', scrollbarWidth: 'none', msOverflowStyle: 'none',
            background: '#f0f0f0', scrollBehavior: 'smooth'
          }}
        >
          {(imageUrls.length > 0 ? imageUrls : ['https://via.placeholder.com/1200x600?text=Welcome+to+Resort+Connect']).map((url, i) => (
            <img key={i} src={url} alt="" style={{ height: '100%', minWidth: '100%', objectFit: 'cover', scrollSnapAlign: 'start' }} />
          ))}
        </div>

        {imageUrls.length > 1 && (
          <>
            <button
              onClick={(e) => {
                e.stopPropagation();
                const el = document.getElementById('main-gallery');
                el.scrollBy({ left: -el.offsetWidth, behavior: 'smooth' });
              }}
              style={{
                position: 'absolute', left: '20px', top: '50%', transform: 'translateY(-50%)',
                background: 'white', border: 'none', borderRadius: '50%',
                width: '48px', height: '48px', display: 'flex', alignItems: 'center', justifyContent: 'center',
                cursor: 'pointer', boxShadow: '0 4px 15px rgba(0,0,0,0.2)', zIndex: 10,
                color: 'var(--primary)'
              }}
            >
              <ChevronLeft size={28} strokeWidth={3} />
            </button>
            <button
              onClick={(e) => {
                e.stopPropagation();
                const el = document.getElementById('main-gallery');
                el.scrollBy({ left: el.offsetWidth, behavior: 'smooth' });
              }}
              style={{
                position: 'absolute', right: '20px', top: '50%', transform: 'translateY(-50%)',
                background: 'white', border: 'none', borderRadius: '50%',
                width: '48px', height: '48px', display: 'flex', alignItems: 'center', justifyContent: 'center',
                cursor: 'pointer', boxShadow: '0 4px 15px rgba(0,0,0,0.2)', zIndex: 10,
                color: 'var(--primary)'
              }}
            >
              <ChevronRight size={28} strokeWidth={3} />
            </button>
            <div style={{
              position: 'absolute', bottom: '60px', left: '50%', transform: 'translateX(-50%)',
              display: 'flex', gap: '10px', zIndex: 10, background: 'rgba(0,0,0,0.3)',
              padding: '6px 12px', borderRadius: '20px', backdropFilter: 'blur(4px)'
            }}>
              {imageUrls.map((_, i) => (
                <div key={i} onClick={() => {
                  const el = document.getElementById('main-gallery');
                  el.scrollTo({ left: i * el.offsetWidth, behavior: 'smooth' });
                }} style={{
                  width: '8px', height: '8px', borderRadius: '50%', cursor: 'pointer',
                  background: i === galleryIndex ? 'white' : 'rgba(255,255,255,0.5)',
                  transition: 'all 0.3s ease'
                }}></div>
              ))}
            </div>
          </>
        )}

        <div style={{ padding: '32px', position: 'relative', marginTop: '-40px', background: 'white', borderRadius: '40px 40px 0 0', borderTop: '1px solid rgba(0,0,0,0.03)' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: '20px' }}>
            <div style={{ flex: 1, minWidth: '300px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '12px' }}>
                <span style={{ background: 'var(--primary)', color: 'white', padding: '4px 12px', borderRadius: '8px', fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>{currentProperty.type}</span>
                <span style={{ display: 'flex', alignItems: 'center', gap: '4px', color: 'var(--secondary)', fontSize: '13px', fontWeight: 700 }}>
                   <ShieldCheck size={14} /> Verified Partner
                </span>
              </div>
              <h1 style={{ margin: '0 0 12px 0', fontSize: '36px', fontWeight: 800, letterSpacing: '-1px' }}>{currentProperty.name}</h1>
              <div style={{ display: 'flex', gap: '20px', color: 'var(--text-muted)', fontSize: '15px', fontWeight: 600 }}>
                <span style={{ display: 'flex', alignItems: 'center', gap: '6px' }}><MapPin size={18} color="var(--primary)" /> {currentProperty.type} Location</span>
                <span style={{ display: 'flex', alignItems: 'center', gap: '6px' }}><UsersIcon size={18} color="var(--secondary)" /> {currentProperty.staffCount} Dedicated Staff</span>
              </div>
            </div>

            <div style={{ textAlign: 'right', background: 'var(--light-bg)', padding: '16px 24px', borderRadius: '24px' }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: '6px', fontSize: '24px', fontWeight: 800, color: 'var(--text-main)' }}>
                <Star size={24} fill="#FFD700" color="#FFD700" />
                {ratingInfo.rating > 0 ? ratingInfo.rating.toFixed(1) : "5.0"}
              </div>
              <span style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '1px' }}>{ratingInfo.count || "12"} Synced Reviews</span>
            </div>
          </div>

          <div style={{ marginTop: '40px' }}>
            <h4 style={{ display: 'flex', alignItems: 'center', gap: '10px', margin: '0 0 16px 0', fontSize: '20px', fontWeight: 800 }}>
               <Info size={20} color="var(--primary)" /> About this sanctuary
            </h4>
            <p style={{ lineHeight: '1.8', color: '#4B5563', fontSize: '16px', maxWidth: '800px' }}>{currentProperty.description}</p>
          </div>

          <div style={{ display: 'flex', gap: '12px', marginTop: '32px', flexWrap: 'wrap' }}>
             <div style={{ background: '#EFF6FF', color: '#1D4ED8', padding: '10px 20px', borderRadius: '14px', fontSize: '14px', fontWeight: 700, display: 'flex', alignItems: 'center', gap: '8px' }}>
                <Home size={18} /> {currentProperty.rooms} Total Units
             </div>
             <div style={{ background: '#ECFDF5', color: '#047857', padding: '10px 20px', borderRadius: '14px', fontSize: '14px', fontWeight: 700, display: 'flex', alignItems: 'center', gap: '8px' }}>
                <ShieldCheck size={18} /> Instant Booking
             </div>
          </div>
        </div>
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: '12px', margin: '48px 0 24px 0' }}>
         <div style={{ width: '6px', height: '24px', background: 'var(--secondary)', borderRadius: '10px' }}></div>
         <h3 style={{ margin: 0, fontSize: '24px', fontWeight: 800 }}>Available Units</h3>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(340px, 1fr))', gap: '24px', marginBottom: '40px' }}>
        {rooms.length > 0 ? rooms.map(room => (
          <RoomCard key={room.id} room={room} onBookRoom={onBookRoom} parseList={parseList} />
        )) : (
          <div style={{ gridColumn: '1/-1', textAlign: 'center', padding: '60px 0', background: 'white', borderRadius: '24px', border: '2px dashed #E5E7EB' }}>
            <p style={{ color: 'var(--text-muted)', fontWeight: 700, margin: 0 }}>No rooms available at this time.</p>
          </div>
        )}
      </div>

      <button
        onClick={() => onChat(currentProperty)}
        style={{
          position: 'fixed', bottom: '30px', right: '30px',
          padding: '18px 32px', borderRadius: '50px',
          background: 'var(--secondary)', color: '#002D24', border: 'none',
          boxShadow: '0 20px 40px rgba(29, 211, 176, 0.4)',
          display: 'flex', alignItems: 'center', gap: '12px',
          fontWeight: 800, cursor: 'pointer', zIndex: 99,
          fontSize: '15px', transition: 'var(--transition)'
        }}
        onMouseOver={(e) => e.currentTarget.style.transform = 'translateY(-5px) scale(1.05)'}
        onMouseOut={(e) => e.currentTarget.style.transform = 'translateY(0) scale(1)'}
      >
        <MessageCircle size={22} /> Chat with Host
      </button>
    </div>
  );
};

export default PropertyDetails;
