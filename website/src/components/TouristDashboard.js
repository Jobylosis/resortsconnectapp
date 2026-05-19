import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, onValue, update, remove } from 'firebase/database';
import { Search, Heart, Star, Trash2, QrCode, X, MessageCircle, MapPin, Navigation, Compass, ChevronLeft, ChevronRight, Bot } from 'lucide-react';
import { QRCodeCanvas } from 'qrcode.react';
import { format, addDays, parse } from 'date-fns';
import PropertyDetails from './PropertyDetails';
import BookingModal from './BookingModal';
import RescheduleModal from './RescheduleModal';
import RefundModal from './RefundModal';
import ReviewModal from './ReviewModal';
import AiChatBot from './AiChatBot';
import Chat from './Chat';

const TouristDashboard = ({ profile, uid }) => {
  const [activeTab, setActiveTab] = useState('Partners');
  const [searchQuery, setSearchQuery] = useState('');
  const [properties, setProperties] = useState([]);
  const [favorites, setFavorites] = useState({});
  const [myBookings, setMyBookings] = useState([]);
  const [loading, setLoading] = useState(true);
  const [selectedPropertyId, setSelectedPropertyId] = useState(null);
  const [bookingRoom, setBookingRoom] = useState(null);
  const [selectedChat, setSelectedChat] = useState(null);
  const [reviewBooking, setReviewBooking] = useState(null);
  const [selectedBooking, setSelectedBooking] = useState(null);
  const [rescheduleBooking, setRescheduleBooking] = useState(null);
  const [refundBooking, setRefundBooking] = useState(null);
  const [showAiBot, setShowAiBot] = useState(false);
  const [propertyLimit, setPropertyLimit] = useState(6);
  const [bookingLimit, setBookingLimit] = useState(5);

  useEffect(() => {
    const propsRef = ref(db, 'properties');
    const unsubscribeProps = onValue(propsRef, (snap) => {
      const data = snap.val();
      if (data) {
        const list = Object.entries(data).map(([id, val]) => ({
          id,
          ...val,
          uid: val.ownerUid || val.uid || id
        })).sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));
        setProperties(list);
      } else {
        setProperties([]);
      }
      setLoading(false);
    }, (error) => {
      console.error("Firebase fetch error:", error);
    });

    const favsRef = ref(db, `users/${uid}/favorites`);
    const unsubscribeFavs = onValue(favsRef, (snap) => {
      setFavorites(snap.val() || {});
    });

    const bookingsRef = ref(db, 'bookings');
    const unsubscribeBookings = onValue(bookingsRef, (snap) => {
      const data = snap.val();
      const list = data ? Object.entries(data)
        .map(([id, val]) => ({ id, ...val }))
        .filter(b => b.touristUid === uid)
        .sort((a, b) => {
          const aTime = (typeof a.timestamp === 'number') ? a.timestamp : (a.timestamp && typeof a.timestamp === 'object' ? Date.now() : 0);
          const bTime = (typeof b.timestamp === 'number') ? b.timestamp : (b.timestamp && typeof b.timestamp === 'object' ? Date.now() : 0);
          return bTime - aTime;
        }) : [];
      setMyBookings(list);
    });

    return () => {
      unsubscribeProps();
      unsubscribeFavs();
      unsubscribeBookings();
    };
  }, [uid]);

  const toggleFavorite = async (e, propId) => {
    e.stopPropagation();
    const isFav = favorites[propId];
    if (isFav) {
      await remove(ref(db, `users/${uid}/favorites/${propId}`));
    } else {
      await update(ref(db, `users/${uid}/favorites`), { [propId]: true });
    }
  };

  const requestReschedule = async (bookingId) => {
    const newDate = prompt("Enter new date (MMM dd, yyyy):", format(addDays(new Date(), 1), 'MMM dd, yyyy'));
    if (!newDate) return;

    if (window.confirm(`Request to reschedule this booking to ${newDate}?`)) {
      await update(ref(db, `bookings/${bookingId}`), {
        status: 'Reschedule Requested',
        requestedRescheduleDate: newDate,
      });
      alert('Reschedule request sent.');
    }
  };

  const requestRefund = async (bookingId) => {
    const reason = prompt("Reason for refund request:");
    if (!reason) return;

    if (window.confirm("Submit refund request?")) {
      await update(ref(db, `bookings/${bookingId}`), {
        status: 'Refund Requested',
        refundReason: reason,
      });
      alert('Refund request submitted.');
    }
  };

  if (selectedChat) return <Chat currentUid={uid} otherUserUid={selectedChat.id} otherUserName={selectedChat.name} onBack={() => setSelectedChat(null)} />;

  if (selectedPropertyId) {
    const prop = properties.find(p => p.id === selectedPropertyId);

    return (
      <div className="view-transition">
        <PropertyDetails
          propId={selectedPropertyId}
          propertyData={prop}
          onBack={() => setSelectedPropertyId(null)}
          onBookRoom={(room) => setBookingRoom({ room, property: prop })}
          onChat={(p) => setSelectedChat({ id: p.ownerUid || p.uid || p.id || selectedPropertyId, name: p.name })}
        />
        {bookingRoom && <BookingModal room={bookingRoom.room} property={bookingRoom.property} user={profile} onClose={() => setBookingRoom(null)} />}
      </div>
    );
  }

  const filteredBySearch = properties.filter(p =>
    p.name?.toLowerCase().includes(searchQuery.toLowerCase()) ||
    p.description?.toLowerCase().includes(searchQuery.toLowerCase()) ||
    p.type?.toLowerCase().includes(searchQuery.toLowerCase())
  );

  return (
    <div className="dashboard">
      <div className="tab-container" style={{
        display: 'flex', gap: '8px', marginBottom: '24px',
        background: 'rgba(0,0,0,0.03)', padding: '6px', borderRadius: '40px',
        maxWidth: 'fit-content'
      }}>
        {['Partners', 'Favorites', 'My Bookings'].map(tab => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            style={{
              padding: '10px 24px',
              background: activeTab === tab ? 'white' : 'transparent',
              border: 'none',
              borderRadius: '30px',
              color: activeTab === tab ? 'var(--primary)' : 'var(--text-muted)',
              fontWeight: 700,
              fontSize: '14px',
              cursor: 'pointer',
              boxShadow: activeTab === tab ? '0 4px 12px rgba(0,0,0,0.08)' : 'none',
              transition: 'var(--transition)'
            }}
          >
            {tab}
          </button>
        ))}
      </div>

      {activeTab === 'Partners' && (
        <>
          <div style={{ position: 'relative', marginBottom: '32px' }}>
            <Search style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={20} />
            <input
              type="text"
              placeholder="Where do you want to go?"
              className="input"
              style={{ paddingLeft: '48px', height: '56px', borderRadius: '20px', fontSize: '16px', boxShadow: 'var(--shadow)' }}
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '16px' }}>
            <Compass size={18} color="var(--primary)" />
            <h3 style={{ margin: 0, fontSize: '20px', fontWeight: 800 }}>Explore Destinations</h3>
          </div>

          {loading ? (
             <div style={{ textAlign: 'center', padding: '100px 0' }}><div className="loader" style={{ margin: '0 auto' }}></div></div>
          ) : (
            <>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))', gap: '24px' }}>
                {filteredBySearch.slice(0, propertyLimit).map(prop => (
                  <PropertyCard key={prop.id} prop={prop} isFav={!!favorites[prop.id]} onFav={(e) => toggleFavorite(e, prop.id)} onClick={() => setSelectedPropertyId(prop.id)} />
                ))}
              </div>
              {filteredBySearch.length > propertyLimit && (
                <div style={{ textAlign: 'center', marginTop: '40px' }}>
                  <button className="btn btn-secondary" onClick={() => setPropertyLimit(prev => prev + 6)}>Load More Properties</button>
                </div>
              )}
              {filteredBySearch.length === 0 && <p style={{ textAlign: 'center', gridColumn: '1/-1', color: 'var(--text-muted)', padding: '60px 0' }}>No properties found matching your search.</p>}
            </>
          )}
        </>
      )}

      {activeTab === 'Favorites' && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))', gap: '24px' }}>
          {properties.filter(p => favorites[p.id]).length > 0 ? properties.filter(p => favorites[p.id]).map(prop => (
            <PropertyCard key={prop.id} prop={prop} isFav={true} onFav={(e) => toggleFavorite(e, prop.id)} onClick={() => setSelectedPropertyId(prop.id)} />
          )) : (
            <div style={{ gridColumn: '1/-1', textAlign: 'center', padding: '80px 0', opacity: 0.6 }}>
               <Heart size={48} color="var(--primary)" style={{ marginBottom: '16px' }} />
               <p style={{ fontWeight: 600 }}>Your favorite resorts will appear here.</p>
            </div>
          )}
        </div>
      )}

      {activeTab === 'My Bookings' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', maxWidth: '700px', margin: '0 auto' }}>
          {myBookings.length > 0 ? (
            <>
              {myBookings.slice(0, bookingLimit).map(b => (
                <div key={b.id} className="card" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '20px' }}>
                  <div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '8px' }}>
                      <h4 style={{ margin: 0, fontWeight: 800 }}>{b.propertyName}</h4>
                      <span className={`status-badge status-${(b.status || 'pending').toLowerCase().replace(' ', '-')}`}>{b.status}</span>
                    </div>
                    <div style={{ fontSize: '13px', color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: '6px' }}>
                       <MapPin size={14} /> {b.activityTitle} • {b.bookingDate}
                    </div>
                    <div style={{ marginTop: '8px', display: 'flex', gap: '16px', alignItems: 'baseline' }}>
                       <span style={{ fontWeight: 800, color: 'var(--secondary)', fontSize: '18px' }}>₱{b.totalPrice}</span>
                       {b.totalPrice > b.amountPaid && (
                         <span style={{ fontSize: '12px', color: 'var(--primary)', fontWeight: 700 }}>
                           Balance: ₱{(b.totalPrice - b.amountPaid).toLocaleString()}
                         </span>
                       )}
                    </div>
                    {(b.status === 'Confirmed' || b.status === 'Checked In') && (
                  <div style={{ marginTop: '12px', display: 'flex', gap: '8px' }}>
                    <button className="btn" style={{ padding: '6px 12px', fontSize: '11px', background: '#F3F4F6' }} onClick={() => setRescheduleBooking(b)}>Reschedule</button>
                    <button className="btn" style={{ padding: '6px 12px', fontSize: '11px', background: '#F3F4F6' }} onClick={() => setRefundBooking(b)}>Request Refund</button>
                  </div>
                )}
                  </div>
                  <div style={{ display: 'flex', gap: '12px' }}>
                    {b.status === 'Completed' && !b.isReviewed && (
                      <button className="btn btn-secondary" style={{ padding: '8px 16px', fontSize: '13px' }} onClick={() => setReviewBooking(b)}>Rate</button>
                    )}
                    {(b.status === 'Confirmed' || b.status === 'Checked In') && (
                      <button className="btn btn-primary" style={{ padding: '10px' }} onClick={() => setSelectedBooking(b)}><QrCode size={20} /></button>
                    )}
                    {b.status === 'Pending' && (
                      <button className="btn" style={{ background: '#FEF2F2', color: 'var(--primary)', padding: '10px 16px', fontSize: '13px' }} onClick={async () => { if(window.confirm("Are you sure you want to cancel this booking request?")) await update(ref(db, `bookings/${b.id}`), {status: "Cancelled"}); }}>Cancel</button>
                    )}
                    {(b.status === 'Cancelled' || b.isReviewed) && (
                      <button className="btn" style={{ background: '#F3F4F6', color: 'var(--text-muted)', padding: '10px' }} onClick={async () => { if(window.confirm("Are you sure you want to delete this booking record from your history?")) await remove(ref(db, `bookings/${b.id}`)); }}><Trash2 size={18} /></button>
                    )}
                  </div>
                </div>
              ))}
              {myBookings.length > bookingLimit && (
                <button className="btn" style={{ background: '#F3F4F6', marginTop: '20px' }} onClick={() => setBookingLimit(prev => prev + 5)}>Load More Bookings</button>
              )}
            </>
          ) : (
            <div style={{ textAlign: 'center', padding: '80px 0', opacity: 0.5 }}>
              <Navigation size={48} style={{ marginBottom: '16px' }} />
              <p style={{ fontWeight: 600 }}>You have no booking history yet.</p>
            </div>
          )}
        </div>
      )}

      {selectedBooking && (
        <div className="modal-overlay" onClick={() => setSelectedBooking(null)}>
          <div className="card modal-content" style={{ maxWidth: '380px', textAlign: 'center' }} onClick={e => e.stopPropagation()}>
            <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: '8px' }}>
              <button onClick={() => setSelectedBooking(null)} style={{ background: 'none', border: 'none', cursor: 'pointer' }}><X /></button>
            </div>
            <h3 style={{ fontWeight: 800 }}>Booking QR Code</h3>
            <p style={{ fontSize: '13px', color: 'var(--text-muted)', marginBottom: '20px' }}>Show this to the resort staff at check-in</p>
            <div style={{ background: 'white', padding: '24px', borderRadius: '24px', display: 'inline-block', boxShadow: '0 8px 30px rgba(0,0,0,0.06)', border: '2px solid #F3F4F6' }}>
              <QRCodeCanvas value={`${window.location.origin}/owner?scan=${selectedBooking.id}`} size={220} />
            </div>
            <p style={{ fontSize: '11px', color: '#999', marginTop: '20px', letterSpacing: '1px' }}>ID: {selectedBooking.id}</p>
          </div>
        </div>
      )}
      {reviewBooking && <ReviewModal booking={reviewBooking} onClose={() => setReviewBooking(null)} />}
      {rescheduleBooking && <RescheduleModal booking={rescheduleBooking} onClose={() => setRescheduleBooking(null)} />}
      {refundBooking && <RefundModal booking={refundBooking} onClose={() => setRefundBooking(null)} />}

      {/* AI Bot Toggle */}
      <button
        onClick={() => setShowAiBot(!showAiBot)}
        style={{
          position: 'fixed', bottom: '30px', right: '30px',
          width: '60px', height: '60px', borderRadius: '50%',
          background: 'var(--primary)', color: 'white', border: 'none',
          boxShadow: '0 8px 25px rgba(251, 54, 64, 0.4)',
          display: 'flex', justifyContent: 'center', alignItems: 'center',
          cursor: 'pointer', zIndex: 4500, transition: 'var(--transition)'
        }}
        onMouseOver={e => e.currentTarget.style.transform = 'scale(1.1)'}
        onMouseOut={e => e.currentTarget.style.transform = 'scale(1)'}
      >
        {showAiBot ? <X size={24} /> : <Bot size={28} />}
      </button>

      {showAiBot && <AiChatBot onClose={() => setShowAiBot(false)} />}
    </div>
  );
};

const PropertyCard = ({ prop, isFav, onFav, onClick }) => {
  const [rating, setRating] = useState(0);
  const [count, setCount] = useState(0);
  const [imgIndex, setImgIndex] = useState(0);

  const imageUrls = Array.isArray(prop.imageUrls)
    ? prop.imageUrls.filter(u => u)
    : (typeof prop.imageUrls === 'object' && prop.imageUrls !== null
        ? Object.values(prop.imageUrls)
        : []);

  useEffect(() => {
    const reviewRef = ref(db, `reviews/${prop.uid || prop.id}`);
    const unsubscribe = onValue(reviewRef, (snapshot) => {
      const data = snapshot.val();
      if (data) {
        const vals = Object.values(data);
        const avg = vals.reduce((a, b) => a + (b.rating || 0), 0) / vals.length;
        setRating(avg);
        setCount(vals.length);
      }
    });
    return () => unsubscribe();
  }, [prop.uid, prop.id]);

  const nextImg = (e) => {
    e.stopPropagation();
    setImgIndex((prev) => (prev + 1) % imageUrls.length);
  };

  const prevImg = (e) => {
    e.stopPropagation();
    setImgIndex((prev) => (prev - 1 + imageUrls.length) % imageUrls.length);
  };

  return (
    <div className="card" style={{ padding: 0, overflow: 'hidden', cursor: 'pointer' }} onClick={onClick}>
      <div style={{ position: 'relative', height: '220px' }}>
        <img
          src={imageUrls[imgIndex] || 'https://via.placeholder.com/400x300?text=No+Image'}
          alt=""
          style={{ width: '100%', height: '100%', objectFit: 'cover' }}
        />

        {imageUrls.length > 1 && (
          <>
            <button onClick={prevImg} style={{
              position: 'absolute', left: '10px', top: '50%', transform: 'translateY(-50%)',
              background: 'rgba(255,255,255,0.8)', border: 'none', borderRadius: '50%',
              width: '30px', height: '30px', display: 'flex', alignItems: 'center', justifyContent: 'center',
              cursor: 'pointer', boxShadow: '0 2px 8px rgba(0,0,0,0.1)'
            }}>
              <ChevronLeft size={18} />
            </button>
            <button onClick={nextImg} style={{
              position: 'absolute', right: '10px', top: '50%', transform: 'translateY(-50%)',
              background: 'rgba(255,255,255,0.8)', border: 'none', borderRadius: '50%',
              width: '30px', height: '30px', display: 'flex', alignItems: 'center', justifyContent: 'center',
              cursor: 'pointer', boxShadow: '0 2px 8px rgba(0,0,0,0.1)'
            }}>
              <ChevronRight size={18} />
            </button>
            <div style={{
              position: 'absolute', bottom: '12px', left: '50%', transform: 'translateX(-50%)',
              display: 'flex', gap: '6px'
            }}>
              {imageUrls.map((_, i) => (
                <div key={i} style={{
                  width: '6px', height: '6px', borderRadius: '50%',
                  background: i === imgIndex ? 'white' : 'rgba(255,255,255,0.5)',
                  boxShadow: '0 1px 2px rgba(0,0,0,0.2)'
                }}></div>
              ))}
            </div>
          </>
        )}

        <div style={{
          position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
          background: 'linear-gradient(to bottom, rgba(0,0,0,0.2), transparent 40%, rgba(0,0,0,0.4))',
          pointerEvents: 'none'
        }}></div>

        <button onClick={onFav} style={{
          position: 'absolute', top: '16px', right: '16px',
          background: 'rgba(255,255,255,0.9)', backdropFilter: 'blur(4px)',
          borderRadius: '14px', border: 'none', padding: '10px',
          cursor: 'pointer', display: 'flex', boxShadow: '0 4px 12px rgba(0,0,0,0.1)'
        }}>
          <Heart size={20} fill={isFav ? 'var(--primary)' : 'none'} color={isFav ? 'var(--primary)' : '#4B5563'} />
        </button>

        <div style={{
          position: 'absolute', top: '16px', left: '16px',
          background: 'var(--primary)', color: 'white',
          padding: '6px 14px', borderRadius: '10px', fontSize: '11px', fontWeight: 800,
          textTransform: 'uppercase', letterSpacing: '0.5px'
        }}>
          {prop.type || 'Resort'}
        </div>

        <div style={{ position: 'absolute', bottom: '16px', left: '16px', display: 'flex', alignItems: 'center', gap: '6px' }}>
           <div style={{
             background: 'rgba(255,255,255,0.95)', padding: '4px 10px',
             borderRadius: '8px', display: 'flex', alignItems: 'center', gap: '4px',
             fontSize: '13px', fontWeight: 700, boxShadow: '0 4px 10px rgba(0,0,0,0.1)'
           }}>
             <Star size={14} fill="#FFD700" color="#FFD700" />
             {rating > 0 ? rating.toFixed(1) : "0.0"}
           </div>
           <span style={{ color: 'white', textShadow: '0 2px 4px rgba(0,0,0,0.5)', fontSize: '11px', fontWeight: 700 }}>({count} Reviews)</span>
        </div>
      </div>

      <div style={{ padding: '20px' }}>
        <h4 style={{ margin: '0 0 8px 0', fontSize: '18px', fontWeight: 800 }}>{prop.name}</h4>
        <p style={{ fontSize: '14px', color: 'var(--text-muted)', margin: '0 0 16px 0', height: '3em', overflow: 'hidden', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical' }}>
          {prop.description}
        </p>

        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderTop: '1px solid #F3F4F6', paddingTop: '16px' }}>
           <div style={{ display: 'flex', gap: '12px', fontSize: '12px', color: 'var(--text-muted)', fontWeight: 600 }}>
              <span style={{ display: 'flex', alignItems: 'center', gap: '4px' }}><Navigation size={14} color="var(--secondary)" /> Explore</span>
           </div>
           <button className="btn btn-primary" style={{ padding: '8px 16px', borderRadius: '10px', fontSize: '13px' }}>View Details</button>
        </div>
      </div>
    </div>
  );
};

export default TouristDashboard;
