import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, onValue, update, remove } from 'firebase/database';
import { Search, Heart, Star, Trash2, QrCode, X, MapPin, Navigation, Compass, ChevronLeft, ChevronRight, Bot, Split, ShoppingBag, CalendarDays, CreditCard, Map as MapIcon, List as ListIcon } from 'lucide-react';
import { QRCodeCanvas } from 'qrcode.react';
// date-fns unused imports removed
import { MapContainer, TileLayer, Marker, Popup } from 'react-leaflet';
import PropertyDetails from './PropertyDetails';
import BookingModal from './BookingModal';
import RescheduleModal from './RescheduleModal';
import RefundModal from './RefundModal';
import ReviewModal from './ReviewModal';
import AiChatBot from './AiChatBot';
import Chat from './Chat';
import BillSplitterModal from './BillSplitterModal';
import RoomServiceModal from './RoomServiceModal';
import QrScanner from './QrScanner';
import TermsAndPolicies from './TermsAndPolicies';

const TouristDashboard = ({ profile, uid, onViewPolicies }) => {
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
  const [confirmCancelId, setConfirmCancelId] = useState(null);
  const [confirmDeleteId, setConfirmDeleteId] = useState(null);
  const [propertyLimit, setPropertyLimit] = useState(6);
  const [bookingLimit, setBookingLimit] = useState(5);
  const [detailBooking, setDetailBooking] = useState(null);
  const [billSplitterBooking, setBillSplitterBooking] = useState(null);
  const [roomServiceBooking, setRoomServiceBooking] = useState(null);
  const [showGlobalSplitter, setShowGlobalSplitter] = useState(false);
  const [showScanner, setShowScanner] = useState(false);
  const [scannedBillData, setScannedBillData] = useState(null);
  const [viewMode, setViewMode] = useState('list'); // 'list' or 'map'
  const [showTerms, setShowTerms] = useState(false);

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
          onViewPolicies={onViewPolicies}
        />
        {bookingRoom && <BookingModal room={bookingRoom.room} property={bookingRoom.property} user={profile} onClose={() => setBookingRoom(null)} onViewPolicies={onViewPolicies} />}
        
        <footer style={{ marginTop: '40px', paddingTop: '20px', paddingBottom: '20px', textAlign: 'center', borderTop: '1px solid var(--border)' }}>
          <button onClick={() => setShowTerms(true)} style={{ background: 'none', border: 'none', color: 'var(--text-muted)', fontSize: '13px', textDecoration: 'underline', cursor: 'pointer' }}>
            Platform Terms & Policies
          </button>
        </footer>
        {showTerms && <TermsAndPolicies onClose={() => setShowTerms(false)} />}
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
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px', flexWrap: 'wrap', gap: '12px' }}>
        <div className="tab-container" style={{
          display: 'flex', gap: '8px',
          background: 'rgba(0,0,0,0.03)', padding: '6px', borderRadius: '40px',
          maxWidth: 'fit-content'
        }}>
          {['Partners', 'Favorites', 'My Bookings'].map(tab => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              style={{
                padding: '10px 24px',
                background: activeTab === tab ? 'var(--surface)' : 'transparent',
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

          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '16px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
              <Compass size={18} color="var(--primary)" />
              <h3 style={{ margin: 0, fontSize: '20px', fontWeight: 800 }}>Explore Destinations</h3>
            </div>
            
            {/* View Mode Toggle */}
            <div style={{ display: 'flex', background: 'rgba(0,0,0,0.05)', borderRadius: '12px', padding: '4px' }}>
              <button
                className="btn"
                style={{ padding: '8px 12px', borderRadius: '10px', background: viewMode === 'list' ? 'white' : 'transparent', color: viewMode === 'list' ? 'var(--primary)' : 'var(--text-muted)', border: 'none', boxShadow: viewMode === 'list' ? '0 2px 8px rgba(0,0,0,0.1)' : 'none', display: 'flex', alignItems: 'center', gap: '6px' }}
                onClick={() => setViewMode('list')}
              >
                <ListIcon size={16} /> <span style={{ fontSize: '13px', fontWeight: 700 }}>List</span>
              </button>
              <button
                className="btn"
                style={{ padding: '8px 12px', borderRadius: '10px', background: viewMode === 'map' ? 'white' : 'transparent', color: viewMode === 'map' ? 'var(--primary)' : 'var(--text-muted)', border: 'none', boxShadow: viewMode === 'map' ? '0 2px 8px rgba(0,0,0,0.1)' : 'none', display: 'flex', alignItems: 'center', gap: '6px' }}
                onClick={() => setViewMode('map')}
              >
                <MapIcon size={16} /> <span style={{ fontSize: '13px', fontWeight: 700 }}>Map</span>
              </button>
            </div>
          </div>

          {loading ? (
             <div style={{ textAlign: 'center', padding: '100px 0' }}><div className="loader" style={{ margin: '0 auto' }}></div></div>
          ) : (
            <>
              {viewMode === 'map' ? (
                <div style={{ height: '600px', width: '100%', borderRadius: '24px', overflow: 'hidden', border: '1px solid var(--border)', zIndex: 0, boxShadow: 'var(--shadow)', position: 'relative' }}>
                  <MapContainer center={[12.8797, 121.7740]} zoom={6} style={{ height: '100%', width: '100%', zIndex: 0 }}>
                    <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" attribution="&copy; OpenStreetMap" />
                    {filteredBySearch.map(prop => {
                      if (prop.latitude && prop.longitude && prop.latitude !== 0) {
                        return (
                          <Marker key={prop.id} position={[prop.latitude, prop.longitude]}>
                            <Popup>
                              <div style={{ textAlign: 'center' }}>
                                <strong style={{ fontSize: '14px', display: 'block', marginBottom: '4px' }}>{prop.name}</strong>
                                <button 
                                  className="btn btn-primary" 
                                  style={{ padding: '6px 12px', fontSize: '12px', borderRadius: '8px', marginTop: '8px' }}
                                  onClick={() => setSelectedPropertyId(prop.id)}
                                >
                                  View Details
                                </button>
                              </div>
                            </Popup>
                          </Marker>
                        );
                      }
                      return null;
                    })}
                  </MapContainer>
                </div>
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
          <button className="btn" style={{ background: 'var(--surface)', color: 'var(--text-main)', border: '1px solid var(--border)', padding: '12px 20px', width: '100%', display: 'flex', justifyContent: 'center', marginBottom: '8px' }} onClick={() => setShowScanner(true)}>
            <QrCode size={18} /> Scan Split Bill
          </button>
          {myBookings.length > 0 ? (
            <>
              {myBookings.slice(0, bookingLimit).map(b => {
                const st = (b.status || 'pending').toLowerCase().replace(/ /g, '-');
                const isActive = b.status === 'Confirmed' || b.status === 'Checked In';
                return (
                  <div key={b.id} className="card" style={{ padding: '20px', cursor: 'pointer', transition: 'var(--transition)' }}
                    onClick={() => setDetailBooking(b)}
                    onMouseOver={e => e.currentTarget.style.transform = 'translateY(-3px)'}
                    onMouseOut={e => e.currentTarget.style.transform = 'translateY(0)'}
                  >
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                      <div style={{ flex: 1 }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '6px' }}>
                          <h4 style={{ margin: 0, fontWeight: 800, fontSize: '16px' }}>{b.propertyName}</h4>
                          <span className={`status-badge status-${st}`}>{b.status}</span>
                        </div>
                        <div style={{ fontSize: '13px', color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: '6px', marginBottom: '6px' }}>
                          <MapPin size={13} /> {b.activityTitle} &bull; {b.bookingDate}
                        </div>
                        <span style={{ fontWeight: 800, color: 'var(--secondary)', fontSize: '17px' }}>₱{Number(b.totalPrice || 0).toLocaleString()}</span>
                      </div>
                      <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', alignItems: 'flex-end' }} onClick={e => e.stopPropagation()}>
                        {isActive && <button className="btn btn-primary" style={{ padding: '8px 12px', fontSize: '12px', display: 'flex', alignItems: 'center', gap: '6px' }} onClick={() => setSelectedBooking(b)}><QrCode size={16} /> QR</button>}
                        {isActive && <button className="btn" style={{ padding: '6px 10px', fontSize: '11px', background: '#F5F3FF', color: '#7C3AED', border: '1px solid rgba(124,58,237,0.2)', display: 'flex', alignItems: 'center', gap: '5px' }} onClick={() => setBillSplitterBooking(b)}><Split size={13} /> Split Bill</button>}
                        {b.status === 'Checked In' && <button className="btn" style={{ padding: '6px 10px', fontSize: '11px', background: '#FEF3F2', color: 'var(--primary)', border: '1px solid rgba(251,54,64,0.2)', display: 'flex', alignItems: 'center', gap: '5px' }} onClick={() => setRoomServiceBooking(b)}><ShoppingBag size={13} /> Room Service</button>}
                        {(b.status === 'Confirmed' || b.status === 'Pending') && <button className="btn" style={{ padding: '6px 10px', fontSize: '11px', background: '#F0FDF4', color: '#16A34A', border: '1px solid rgba(22,163,74,0.2)', display: 'flex', alignItems: 'center', gap: '5px' }} onClick={() => setRescheduleBooking(b)}><CalendarDays size={13} /> Reschedule</button>}
                        {b.status === 'Completed' && !b.isReviewed && <button className="btn btn-secondary" style={{ padding: '7px 12px', fontSize: '12px' }} onClick={() => setReviewBooking(b)}>Rate</button>}
                        {b.status === 'Pending' && (confirmCancelId === b.id
                          ? <div style={{ display: 'flex', gap: '6px' }}>
                              <button className="btn" style={{ padding: '5px 10px', fontSize: '11px', background: 'var(--surface)', color: 'var(--text-muted)', border: '1px solid var(--border)' }} onClick={() => setConfirmCancelId(null)}>Back</button>
                              <button className="btn" style={{ padding: '5px 10px', fontSize: '11px', background: '#DC2626', color: 'white' }} onClick={async () => { await update(ref(db, `bookings/${b.id}`), {status:'Cancelled'}); setConfirmCancelId(null); }}>Confirm</button>
                            </div>
                          : <button className="btn" style={{ padding: '6px 12px', fontSize: '12px', background: '#FEF2F2', color: 'var(--primary)', border: '1px solid #FECACA' }} onClick={() => setConfirmCancelId(b.id)}>Cancel</button>
                        )}
                        {(b.status === 'Cancelled' || b.isReviewed || b.status === 'Refund Approved' || b.status === 'Refund Declined') && (confirmDeleteId === b.id
                          ? <div style={{ display: 'flex', gap: '6px' }}>
                              <button className="btn" style={{ padding: '5px 10px', fontSize: '11px', background: 'var(--surface)', color: 'var(--text-muted)', border: '1px solid var(--border)' }} onClick={() => setConfirmDeleteId(null)}>Back</button>
                              <button className="btn" style={{ padding: '5px 10px', fontSize: '11px', background: '#DC2626', color: 'white' }} onClick={async () => { await remove(ref(db, `bookings/${b.id}`)); setConfirmDeleteId(null); }}>Delete</button>
                            </div>
                          : <button className="btn" style={{ padding: '7px', background: 'var(--light-bg)', color: 'var(--text-muted)', border: '1px solid var(--border)' }} onClick={() => setConfirmDeleteId(b.id)}><Trash2 size={16} /></button>
                        )}
                      </div>
                    </div>
                  </div>
                );
              })}
              {myBookings.length > bookingLimit && (
                <button className="btn" style={{ background: 'var(--light-bg)', color: 'var(--text-main)', border: '1px solid var(--border)', marginTop: '8px' }} onClick={() => setBookingLimit(prev => prev + 5)}>Load More Bookings</button>
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
              <button onClick={() => setSelectedBooking(null)} className="close-btn"><X size={18} /></button>
            </div>
            <h3 style={{ fontWeight: 800 }}>Booking QR Code</h3>
            <p style={{ fontSize: '13px', color: 'var(--text-muted)', marginBottom: '20px' }}>Show this to the resort staff at check-in</p>
            <div style={{ background: 'var(--surface)', padding: '24px', borderRadius: '24px', display: 'inline-block', boxShadow: '0 8px 30px rgba(0,0,0,0.06)', border: '2px solid var(--border)' }}>
              <QRCodeCanvas value={`${window.location.origin}/owner?scan=${selectedBooking.id}`} size={220} />
            </div>
            <p style={{ fontSize: '11px', color: '#999', marginTop: '20px', letterSpacing: '1px' }}>ID: {selectedBooking.id}</p>
          </div>
        </div>
      )}

      {detailBooking && (
        <div className="modal-overlay" onClick={() => setDetailBooking(null)}>
          <div className="card modal-content" style={{ maxWidth: '480px', padding: '32px', borderRadius: '28px' }} onClick={e => e.stopPropagation()}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
              <h3 style={{ margin: 0, fontWeight: 900, fontSize: '20px' }}>{detailBooking.propertyName}</h3>
              <button onClick={() => setDetailBooking(null)} className="close-btn"><X size={18} /></button>
            </div>
            <span className={`status-badge status-${(detailBooking.status||'pending').toLowerCase().replace(/ /g,'-')}`} style={{ marginBottom: '20px', display: 'inline-flex' }}>{detailBooking.status}</span>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '14px', marginTop: '12px' }}>
              {[['Room', detailBooking.activityTitle || detailBooking.roomTitle || 'N/A'],
                ['Check-in Date', detailBooking.bookingDate || 'N/A'],
                ['Nights', detailBooking.nights || '1'],
                ['Guest Name', detailBooking.touristName || 'N/A'],
                ['Payment Method', detailBooking.paymentMethod || 'N/A'],
                ['Total Amount', `₱${Number(detailBooking.totalPrice||0).toLocaleString()}`],
                ['Amount Paid', `₱${Number(detailBooking.amountPaid||0).toLocaleString()}`],
                ['Balance', `₱${Math.max(0, Number(detailBooking.totalPrice||0) - Number(detailBooking.amountPaid||0)).toLocaleString()}`],
              ].map(([label, val]) => (
                <div key={label} style={{ display: 'flex', justifyContent: 'space-between', padding: '10px 0', borderBottom: '1px solid var(--border)' }}>
                  <span style={{ fontSize: '13px', color: 'var(--text-muted)', fontWeight: 600 }}>{label}</span>
                  <span style={{ fontSize: '14px', fontWeight: 800 }}>{val}</span>
                </div>
              ))}
            </div>
            {detailBooking.selectedAddons?.length > 0 && (
              <div style={{ marginTop: '14px', padding: '12px', background: 'var(--light-bg)', borderRadius: '12px' }}>
                <div style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-muted)', marginBottom: '6px' }}>ADD-ONS</div>
                <div style={{ fontSize: '14px', fontWeight: 600 }}>{detailBooking.selectedAddons.join(', ')}</div>
              </div>
            )}
            <div style={{ marginTop: '20px', display: 'flex', gap: '10px', flexWrap: 'wrap' }}>
              {(detailBooking.status === 'Confirmed' || detailBooking.status === 'Checked In') && (
                <>
                  <button className="btn btn-primary" style={{ flex: 1, minWidth: '120px' }} onClick={() => { setDetailBooking(null); setSelectedBooking(detailBooking); }}><QrCode size={16} /> Show QR</button>
                  <button className="btn" style={{ flex: 1, minWidth: '120px', background: '#F5F3FF', color: '#7C3AED', border: '1px solid rgba(124,58,237,0.2)' }} onClick={() => { setDetailBooking(null); setBillSplitterBooking(detailBooking); }}><Split size={14} /> Split Bill</button>
                </>
              )}
              {(detailBooking.status === 'Confirmed' || detailBooking.status === 'Pending') && (
                <div style={{ width: '100%', display: 'flex', gap: '10px' }}>
                  <button className="btn" style={{ flex: 1, background: 'var(--surface)', color: 'var(--secondary)', border: '1px solid var(--secondary)' }} onClick={() => { setDetailBooking(null); setRescheduleBooking(detailBooking); }}><CalendarDays size={14} /> Reschedule</button>
                  <button className="btn" style={{ flex: 1, background: 'var(--surface)', color: '#DC2626', border: '1px solid #DC2626' }} onClick={() => { setDetailBooking(null); setRefundBooking(detailBooking); }}><CreditCard size={14} /> Refund</button>
                </div>
              )}
              {detailBooking.status === 'Checked In' && (
                <button className="btn" style={{ flex: 1, minWidth: '120px', background: '#FEF3F2', color: 'var(--primary)', border: '1px solid rgba(251,54,64,0.2)' }} onClick={() => { setDetailBooking(null); setRoomServiceBooking(detailBooking); }}><ShoppingBag size={14} /> Room Service</button>
              )}
            </div>
          </div>
        </div>
      )}

      {reviewBooking && <ReviewModal booking={reviewBooking} onClose={() => setReviewBooking(null)} />}
      {rescheduleBooking && <RescheduleModal booking={rescheduleBooking} onClose={() => setRescheduleBooking(null)} />}
      {refundBooking && <RefundModal booking={refundBooking} onClose={() => setRefundBooking(null)} />}
      {billSplitterBooking && (
        <BillSplitterModal 
          onClose={() => setBillSplitterBooking(null)} 
          initialAmount={billSplitterBooking.totalPrice} 
          resortGCash={(() => {
            const prop = properties.find(p => p.id === billSplitterBooking.propertyId);
            return prop && prop.gcashNumber ? `GCash ${prop.gcashNumber} - ${prop.gcashName || 'Resort'}` : null;
          })()}
        />
      )}
      {roomServiceBooking && <RoomServiceModal onClose={() => setRoomServiceBooking(null)} booking={roomServiceBooking} ownerUid={roomServiceBooking.ownerUid} />}
      {showGlobalSplitter && <BillSplitterModal onClose={() => setShowGlobalSplitter(false)} />}
      
      {showScanner && (
        <QrScanner
          rawMode={true}
          title="Scan Split Bill"
          subtitle="Use your camera to scan a friend's Bill Breakdown QR Code."
          onResult={(text) => { 
            setShowScanner(false); 
            if (text.includes('Bill Split Summary') || text.includes('Bill Breakdown') || text.includes('Personal Bill')) {
              setScannedBillData(text); 
            } else {
              alert("Security Check: Invalid QR Code. This scanner is only for Split Bills.");
            }
          }}
          onClose={() => setShowScanner(false)}
        />
      )}

      {scannedBillData && (
        <div className="modal-overlay" style={{ zIndex: 6000 }}>
          <div className="card modal-content" style={{ maxWidth: '400px', background: 'var(--surface)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
              <h3 style={{ margin: 0, fontWeight: 800 }}>Split Bill Breakdown</h3>
              <button onClick={() => setScannedBillData(null)} className="close-btn"><X size={20} /></button>
            </div>
            <div style={{ background: 'var(--light-bg)', padding: '24px', borderRadius: '16px', whiteSpace: 'pre-wrap', fontFamily: 'monospace', fontSize: '15px', lineHeight: '1.6' }}>
              {scannedBillData.replace(/\\n/g, '\n')}
            </div>
          </div>
        </div>
      )}

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
      
      {activeTab === 'Partners' && (
        <footer style={{ marginTop: '40px', paddingTop: '20px', paddingBottom: '20px', textAlign: 'center', borderTop: '1px solid var(--border)' }}>
          <button onClick={() => setShowTerms(true)} style={{ background: 'none', border: 'none', color: 'var(--text-muted)', fontSize: '13px', textDecoration: 'underline', cursor: 'pointer' }}>
            Platform Terms & Policies
          </button>
        </footer>
      )}
      {showTerms && <TermsAndPolicies onClose={() => setShowTerms(false)} />}
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
             fontSize: '13px', fontWeight: 800, color: '#000', boxShadow: '0 4px 10px rgba(0,0,0,0.1)'
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

        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderTop: '1px solid var(--border)', paddingTop: '16px' }}>
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
