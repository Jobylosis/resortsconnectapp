import React, { useState, useEffect, useMemo } from 'react';
import { db } from '../firebase';
import { ref, onValue, update, remove, get } from 'firebase/database';
import { Plus, Trash2, Edit3, MessageSquare, Eye, User, QrCode, TrendingUp, Users, Home as HomeIcon, X, BarChart2, AlertCircle, Calendar, MapPin, CreditCard, PlusSquare } from 'lucide-react';
import Chat from './Chat';
import AddRoomModal from './AddRoomModal';
import EditPropertyModal from './EditPropertyModal';
import QrScanner from './QrScanner';
import { format, parse, addDays, isBefore, isAfter } from 'date-fns';

const ChatRoomItem = ({ room, onClick }) => {
  const [photo, setPhoto] = useState(room.otherProfilePic || null);

  useEffect(() => {
    if (room.otherProfilePic) return;

    const fetchPhoto = async () => {
      try {
        const propSnap = await get(ref(db, `properties/${room.otherUid}`));
        if (propSnap.exists()) {
          const data = propSnap.val();
          const imgs = Array.isArray(data.imageUrls) ? data.imageUrls : (data.imageUrls ? Object.values(data.imageUrls) : []);
          if (imgs.length > 0) setPhoto(imgs[0]);
        } else {
          const userSnap = await get(ref(db, `users/${room.otherUid}`));
          if (userSnap.exists() && userSnap.val().profilePicUrl) {
            setPhoto(userSnap.val().profilePicUrl);
          }
        }
      } catch (e) {
        console.error("Chat photo fetch error", e);
      }
    };
    fetchPhoto();
  }, [room.otherUid, room.otherProfilePic]);

  return (
    <div
      className="card chat-room-card"
      style={{ cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '16px', padding: '16px', transition: 'var(--transition)' }}
      onClick={() => onClick(room)}
    >
      <div style={{
        width: '52px', height: '52px', borderRadius: '18px',
        background: '#F3F4F6', overflow: 'hidden',
        display: 'flex', justifyContent: 'center', alignItems: 'center', color: '#1D4ED8'
      }}>
        {photo ? (
          <img src={photo} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
        ) : (
          <User size={28} />
        )}
      </div>
      <div style={{ flex: 1 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <h4 style={{ margin: 0, fontWeight: 800 }}>{room.otherUserName}</h4>
          <span style={{ fontSize: '10px', color: 'var(--text-muted)' }}>{room.timestamp ? format(new Date(room.timestamp), 'p') : ''}</span>
        </div>
        <p style={{ margin: '4px 0 0 0', fontSize: '13px', color: 'var(--text-muted)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
          Tap to view conversation
        </p>
      </div>
    </div>
  );
};

const OwnerDashboard = ({ profile, uid }) => {
  const [activeTab, setActiveTab] = useState('Rooms');
  const [rooms, setRooms] = useState([]);
  const [bookings, setBookings] = useState([]);
  const [chatRooms, setChatRooms] = useState([]);
  const [loading, setLoading] = useState(true);
  const [selectedChat, setSelectedChat] = useState(null);
  const [showAddRoom, setShowAddRoom] = useState(false);
  const [showEditProperty, setShowEditProperty] = useState(false);
  const [showScanner, setShowScanner] = useState(false);
  const [showRevenue, setShowRevenue] = useState(false);
  const [roomToEdit, setRoomToEdit] = useState(null);
  const [scannedBooking, setScannedBooking] = useState(null);

  useEffect(() => {
    if (!uid) return;

    // Rooms listener
    const roomsRef = ref(db, `properties/${uid}/roomInventory`);
    const unsubscribeRooms = onValue(roomsRef, (snapshot) => {
      const data = snapshot.val();
      const list = data ? Object.entries(data).map(([id, val]) => ({ id, ...val })) : [];
      setRooms(list);
    });

    // Bookings listener
    const bookingsRef = ref(db, 'bookings');
    const unsubscribeBookings = onValue(bookingsRef, (snapshot) => {
      const data = snapshot.val();
      const list = data ? Object.entries(data)
        .map(([id, val]) => ({ id, ...val }))
        .filter(b => b.ownerUid === uid)
        .sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0)) : [];
      setBookings(list);
    });

    // Chat Rooms listener
    const chatRoomsRef = ref(db, `chat_rooms/${uid}`);
    const unsubscribeChats = onValue(chatRoomsRef, (snapshot) => {
      const data = snapshot.val();
      const list = data ? Object.entries(data).map(([otherUid, val]) => ({
        otherUid,
        ...val
      })).sort((a, b) => {
        const aTime = a.timestamp;
        const bTime = b.timestamp;
        const aNum = (typeof aTime === 'number') ? aTime : (aTime && typeof aTime === 'object' ? Date.now() : 0);
        const bNum = (typeof bTime === 'number') ? bTime : (bTime && typeof bTime === 'object' ? Date.now() : 0);
        return bNum - aNum;
      }) : [];
      setChatRooms(list);
      setLoading(false);
    });

    return () => {
      unsubscribeRooms();
      unsubscribeBookings();
      unsubscribeChats();
    };
  }, [uid]);

  const stats = useMemo(() => {
    let totalRevenue = 0;
    const monthlyRevenue = {};
    const roomSales = {};

    bookings.forEach(b => {
      const status = (b.status || '').toLowerCase();
      if (['confirmed', 'completed', 'checked in'].includes(status)) {
        const amount = parseFloat(b.totalPrice || b.amount || 0);
        totalRevenue += amount;

        try {
          const dateStr = b.bookingDate || b.checkInDate || b.date;
          if (dateStr) {
            let date;
            if (dateStr.includes('T')) {
              date = new Date(dateStr);
            } else {
              date = parse(dateStr, 'MMM dd, yyyy', new Date());
            }
            const monthKey = format(date, 'MMMM yyyy');
            monthlyRevenue[monthKey] = (monthlyRevenue[monthKey] || 0) + amount;

            const room = b.activityTitle || b.roomTitle || 'Unknown Room';
            roomSales[room] = (roomSales[room] || 0) + 1;
          }
        } catch (e) {}
      }
    });

    const bestSeller = Object.keys(roomSales).length > 0
      ? Object.entries(roomSales).reduce((a, b) => a[1] > b[1] ? a : b)[0]
      : "No sales yet";

    return { totalRevenue, monthlyRevenue, bestSeller, roomCount: rooms.length, bookingCount: bookings.length };
  }, [bookings, rooms.length]);

  const checkConflict = (targetBooking, allBookings) => {
    try {
      const startA = parse(targetBooking.bookingDate, 'MMM dd, yyyy', new Date());
      const endA = addDays(startA, parseInt(targetBooking.nights) || 1);

      return allBookings.some(b => {
        if (b.id === targetBooking.id) return false;
        if (b.activityId !== targetBooking.activityId) return false;

        const status = (b.status || '').toLowerCase();
        if (status !== 'confirmed' && status !== 'checked in') return false;

        const startB = parse(b.bookingDate, 'MMM dd, yyyy', new Date());
        const endB = addDays(startB, parseInt(b.nights) || 1);

        return isBefore(startA, endB) && isAfter(endA, startB);
      });
    } catch (e) {
      console.error("Conflict check error:", e);
      return false;
    }
  };

  const updateStatus = async (bookingId, newStatus) => {
    try {
      if (newStatus === 'Confirmed') {
        const target = bookings.find(b => b.id === bookingId);
        if (target && checkConflict(target, bookings)) {
          alert("Cannot confirm: This booking overlaps with an existing confirmed reservation for the same room.");
          return;
        }
      }

      if (newStatus === 'Completed') {
        if (!window.confirm("Are you sure you want to complete the check-out for this guest?")) {
          return;
        }
      }

      const bookingRef = ref(db, `bookings/${bookingId}`);
      await update(bookingRef, { status: newStatus });
    } catch (err) {
      alert("Status update failed: " + err.message);
    }
  };

  const deleteBooking = async (id) => {
    if (window.confirm('Are you sure you want to delete this booking record?')) {
      await remove(ref(db, `bookings/${id}`));
    }
  };

  const deleteRoom = async (id) => {
    if (window.confirm('Delete this room permanently?')) {
      await remove(ref(db, `properties/${uid}/roomInventory/${id}`));
    }
  };

  if (selectedChat) {
    return (
      <Chat
        currentUid={uid}
        otherUserUid={selectedChat.otherUid}
        otherUserName={selectedChat.otherUserName}
        onBack={() => setSelectedChat(null)}
      />
    );
  }

  return (
    <div className="owner-dashboard">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '32px' }}>
        <div className="tab-container" style={{
          display: 'flex', gap: '8px', background: 'rgba(0,0,0,0.03)',
          padding: '6px', borderRadius: '40px'
        }}>
          {['Rooms', 'Bookings', 'Chat'].map(tab => (
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
        <div style={{ display: 'flex', gap: '12px' }}>
          <button
            className="btn btn-primary"
            style={{ padding: '12px', borderRadius: '16px', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }}
            onClick={() => { setShowScanner(true); }}
            title="Scan Booking QR"
          >
            <QrCode size={22} />
          </button>
        </div>
      </div>

      {activeTab === 'Rooms' && (
        <section className="view-transition">
          {/* Dashboard Stats */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '20px', marginBottom: '32px' }}>
            <div className="card" style={{ textAlign: 'center', padding: '24px', margin: 0 }}>
               <div style={{ background: 'rgba(29, 211, 176, 0.1)', padding: '12px', borderRadius: '16px', display: 'inline-block', marginBottom: '12px' }}>
                  <HomeIcon color="var(--secondary)" size={24} />
               </div>
              <div style={{ fontSize: '24px', fontWeight: 800 }}>{stats.roomCount}</div>
              <div style={{ fontSize: '13px', color: 'var(--text-muted)', fontWeight: 600 }}>Rooms</div>
            </div>

            <div className="card" style={{ textAlign: 'center', padding: '24px', margin: 0 }}>
               <div style={{ background: 'rgba(251, 54, 64, 0.1)', padding: '12px', borderRadius: '16px', display: 'inline-block', marginBottom: '12px' }}>
                  <Calendar color="var(--primary)" size={24} />
               </div>
              <div style={{ fontSize: '24px', fontWeight: 800 }}>{stats.bookingCount}</div>
              <div style={{ fontSize: '13px', color: 'var(--text-muted)', fontWeight: 600 }}>Bookings</div>
            </div>

            <div
              className="card"
              onClick={() => setShowRevenue(true)}
              style={{ cursor: 'pointer', textAlign: 'center', padding: '24px', margin: 0, transition: 'var(--transition)' }}
            >
               <div style={{ background: 'rgba(29, 211, 176, 0.1)', padding: '12px', borderRadius: '16px', display: 'inline-block', marginBottom: '12px' }}>
                  <TrendingUp color="var(--secondary)" size={24} />
               </div>
              <div style={{ fontSize: '24px', fontWeight: 800 }}>₱{stats.totalRevenue.toLocaleString()}</div>
              <div style={{ fontSize: '13px', color: 'var(--text-muted)', fontWeight: 600 }}>Earnings</div>
            </div>
          </div>

          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
              <h3 style={{ margin: 0, fontSize: '22px', fontWeight: 800 }}>Room Inventory</h3>
              <button
                className="btn"
                style={{ background: '#F3F4F6', color: 'var(--text-muted)', padding: '8px', borderRadius: '10px' }}
                onClick={() => setShowEditProperty(true)}
              >
                <Edit3 size={16} />
              </button>
            </div>
            <button
              className="btn btn-secondary"
              onClick={() => { setRoomToEdit(null); setShowAddRoom(true); }}
              style={{ borderRadius: '14px', padding: '10px 20px', cursor: 'pointer' }}
            >
              <Plus size={18} /> Add New Room
            </button>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))', gap: '24px' }}>
            {rooms.length > 0 ? rooms.map(room => (
              <div key={room.id} className="card" style={{ padding: 0, overflow: 'hidden' }}>
                <div style={{ position: 'relative', height: '180px' }}>
                  <img
                    src={(Array.isArray(room.imageUrls) ? room.imageUrls[0] : Object.values(room.imageUrls || {})[0]) || 'https://via.placeholder.com/400x200?text=No+Photo'}
                    alt={room.title}
                    style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                  />
                  <div style={{ position: 'absolute', top: '12px', right: '12px', background: 'rgba(255,255,255,0.95)', padding: '6px 12px', borderRadius: '10px', fontWeight: 800, color: 'var(--primary)', fontSize: '14px' }}>
                    ₱{room.price}
                  </div>
                </div>
                <div style={{ padding: '20px' }}>
                  <h4 style={{ margin: '0 0 4px 0', fontSize: '18px', fontWeight: 800 }}>
                    {room.title} {room.nickname && <span style={{ color: 'var(--text-muted)', fontWeight: 400, fontSize: '14px' }}>• {room.nickname}</span>}
                  </h4>
                  <p style={{ fontSize: '13px', color: 'var(--text-muted)', marginBottom: '16px', fontWeight: 600 }}>{room.category} • {room.location}</p>

                  <div style={{ display: 'flex', gap: '10px', borderTop: '1px solid #F3F4F6', paddingTop: '16px' }}>
                    <button className="btn" style={{ flex: 1, padding: '8px', background: '#F3F4F6', color: 'var(--text-main)', borderRadius: '10px' }} onClick={() => { setRoomToEdit(room); setShowAddRoom(true); }}>
                      <Edit3 size={16} /> Edit
                    </button>
                    <button className="btn" style={{ flex: 1, padding: '8px', background: '#FEF2F2', color: 'var(--primary)', borderRadius: '10px' }} onClick={() => deleteRoom(room.id)}>
                      <Trash2 size={16} /> Delete
                    </button>
                  </div>
                </div>
              </div>
            )) : (
              <div style={{ gridColumn: '1/-1', textAlign: 'center', padding: '80px 0', opacity: 0.5 }}>
                 <HomeIcon size={48} style={{ marginBottom: '16px' }} />
                 <p style={{ fontWeight: 600 }}>No rooms in your inventory yet.</p>
              </div>
            )}
          </div>
        </section>
      )}

      {activeTab === 'Bookings' && (
        <section className="view-transition">
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '24px' }}>
             <Calendar size={20} color="var(--primary)" />
             <h3 style={{ margin: 0, fontSize: '22px', fontWeight: 800 }}>Reservations</h3>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', maxWidth: '800px' }}>
            {bookings.length > 0 ? bookings.map(booking => (
              <BookingCard
                key={booking.id}
                booking={booking}
                onDelete={() => deleteBooking(booking.id)}
                onUpdateStatus={updateStatus}
                hasConflict={booking.status === 'Pending' && checkConflict(booking, bookings)}
              />
            )) : <p style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '60px 0' }}>No bookings found.</p>}
          </div>
        </section>
      )}

      {activeTab === 'Chat' && (
        <section className="view-transition">
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '24px' }}>
             <MessageSquare size={20} color="var(--secondary)" />
             <h3 style={{ margin: 0, fontSize: '22px', fontWeight: 800 }}>Inquiries</h3>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(350px, 1fr))', gap: '16px' }}>
            {chatRooms.length > 0 ? chatRooms.map(room => (
              <ChatRoomItem key={room.otherUid} room={room} onClick={setSelectedChat} />
            )) : (
              <div style={{ gridColumn: '1/-1', textAlign: 'center', padding: '80px 0', opacity: 0.5 }}>
                <MessageSquare size={48} style={{ marginBottom: '16px' }} />
                <p style={{ fontWeight: 600 }}>No active conversations.</p>
              </div>
            )}
          </div>
        </section>
      )}

      {showRevenue && (
        <div className="modal-overlay" onClick={() => setShowRevenue(false)} style={{ zIndex: 2000 }}>
          <div className="card modal-content" onClick={e => e.stopPropagation()} style={{ maxWidth: '450px', borderRadius: '32px', padding: '32px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
              <h3 style={{ margin: 0, fontWeight: 800 }}>Earnings Analytics</h3>
              <button onClick={() => setShowRevenue(false)} className="close-btn"><X size={20} /></button>
            </div>

            <div style={{ background: 'var(--light-bg)', padding: '24px', borderRadius: '24px', marginBottom: '32px', textAlign: 'center' }}>
              <p style={{ color: 'var(--text-muted)', fontSize: '13px', fontWeight: 700, textTransform: 'uppercase', marginBottom: '8px' }}>Top Performing Room</p>
              <h2 style={{ color: 'var(--secondary)', margin: 0, fontSize: '24px', fontWeight: 800 }}>{stats.bestSeller}</h2>
            </div>

            <h4 style={{ fontSize: '16px', fontWeight: 800, marginBottom: '16px' }}>Monthly Breakdown</h4>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
              {Object.entries(stats.monthlyRevenue).length > 0 ? Object.entries(stats.monthlyRevenue).map(([month, rev]) => (
                <div key={month} style={{ display: 'flex', justifyContent: 'space-between', padding: '16px', borderRadius: '16px', background: '#F9FAFB', border: '1px solid #F3F4F6' }}>
                  <span style={{ fontWeight: 600 }}>{month}</span>
                  <span style={{ fontWeight: 800, color: 'var(--secondary)' }}>₱{rev.toLocaleString()}</span>
                </div>
              )) : <p style={{ textAlign: 'center', color: 'var(--text-muted)', fontSize: '14px' }}>No revenue data yet.</p>}
            </div>
          </div>
        </div>
      )}

      {showAddRoom && (
        <AddRoomModal
          uid={uid}
          rooms={rooms}
          roomToEdit={roomToEdit}
          onClose={() => { setShowAddRoom(false); setRoomToEdit(null); }}
        />
      )}

      {showEditProperty && <EditPropertyModal uid={uid} onClose={() => setShowEditProperty(false)} />}

      {showScanner && (
        <QrScanner
          onResult={(booking) => { setShowScanner(false); setScannedBooking(booking); }}
          onClose={() => setShowScanner(false)}
        />
      )}

      {scannedBooking && (
        <div className="modal-overlay" onClick={() => setScannedBooking(null)} style={{ zIndex: 4000 }}>
          <div className="card modal-content view-transition" onClick={e => e.stopPropagation()} style={{ maxWidth: '550px', borderRadius: '32px', padding: '32px', background: 'white' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
              <h3 style={{ margin: 0, fontWeight: 800, fontSize: '24px' }}>Verification Result</h3>
              <button onClick={() => setScannedBooking(null)} className="close-btn"><X size={20} /></button>
            </div>

            <div style={{ background: '#F9FAFB', padding: '24px', borderRadius: '24px', border: '1px solid #F3F4F6' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '16px', marginBottom: '24px', paddingBottom: '20px', borderBottom: '1px solid #E5E7EB' }}>
                <div style={{ width: '60px', height: '60px', borderRadius: '18px', background: 'white', display: 'flex', justifyContent: 'center', alignItems: 'center', boxShadow: '0 4px 12px rgba(0,0,0,0.05)', overflow: 'hidden' }}>
                  <User size={32} color="var(--secondary)" />
                </div>
                <div>
                   <h4 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>{scannedBooking.touristName}</h4>
                   <p style={{ margin: '2px 0 0 0', fontSize: '13px', color: 'var(--text-muted)', fontWeight: 600 }}>Guest Verification</p>
                </div>
              </div>

              <div style={{ display: 'grid', gap: '16px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                   <HomeIcon size={18} color="var(--primary)" />
                   <div>
                     <p style={{ margin: 0, fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Booked Room</p>
                     <p style={{ margin: 0, fontSize: '15px', fontWeight: 800 }}>{scannedBooking.activityTitle || scannedBooking.roomTitle}</p>
                   </div>
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                   <Calendar size={18} color="var(--secondary)" />
                   <div>
                     <p style={{ margin: 0, fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Check-in / Check-out</p>
                     <p style={{ margin: 0, fontSize: '15px', fontWeight: 800 }}>
                        {scannedBooking.bookingDate} - {format(addDays(parse(scannedBooking.bookingDate, 'MMM dd, yyyy', new Date()), parseInt(scannedBooking.nights) || 1), 'MMM dd, yyyy')}
                        <span style={{ color: 'var(--text-muted)', fontWeight: 600, fontSize: '13px', marginLeft: '8px' }}>({scannedBooking.nights} Night/s)</span>
                     </p>
                   </div>
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                   <TrendingUp size={18} color="#10B981" />
                   <div style={{ flex: 1 }}>
                     <p style={{ margin: 0, fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Payment Breakdown</p>
                     <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: '4px' }}>
                        <span style={{ fontSize: '13px', fontWeight: 600 }}>Total:</span>
                        <span style={{ fontSize: '13px', fontWeight: 700 }}>₱{scannedBooking.totalPrice?.toLocaleString()}</span>
                     </div>
                     <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <span style={{ fontSize: '13px', fontWeight: 600, color: '#059669' }}>Paid:</span>
                        <span style={{ fontSize: '13px', fontWeight: 800, color: '#059669' }}>₱{(scannedBooking.amountPaid || (scannedBooking.paymentOption?.includes('30%') ? scannedBooking.totalPrice * 0.3 : scannedBooking.totalPrice))?.toLocaleString()}</span>
                     </div>
                     <div style={{ display: 'flex', justifyContent: 'space-between', borderTop: '1px dashed #E5E7EB', marginTop: '4px', paddingTop: '4px' }}>
                        <span style={{ fontSize: '13px', fontWeight: 700 }}>Balance:</span>
                        <span style={{ fontSize: '15px', fontWeight: 900, color: 'var(--primary)' }}>
                          ₱{(scannedBooking.totalPrice - (scannedBooking.amountPaid || (scannedBooking.paymentOption?.includes('30%') ? scannedBooking.totalPrice * 0.3 : scannedBooking.totalPrice)))?.toLocaleString()}
                        </span>
                     </div>
                   </div>
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                   <CreditCard size={18} color="#1D4ED8" />
                   <div>
                     <p style={{ margin: 0, fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Payment Details</p>
                     <p style={{ margin: 0, fontSize: '14px', fontWeight: 700 }}>{scannedBooking.paymentOption || 'Full Payment'} via {scannedBooking.paymentMethod || 'GCash'}</p>
                   </div>
                </div>

                {scannedBooking.selectedAddons && scannedBooking.selectedAddons.length > 0 && (
                   <div style={{ display: 'flex', alignItems: 'flex-start', gap: '12px' }}>
                      <PlusSquare size={18} color="var(--primary)" style={{ marginTop: '2px' }} />
                      <div>
                        <p style={{ margin: 0, fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Add-ons</p>
                        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px', marginTop: '4px' }}>
                          {scannedBooking.selectedAddons.map((a, i) => (
                            <span key={i} style={{ background: 'white', padding: '4px 10px', borderRadius: '8px', fontSize: '12px', fontWeight: 700, border: '1px solid #E5E7EB' }}>{a}</span>
                          ))}
                        </div>
                      </div>
                   </div>
                )}
              </div>
            </div>

            <div style={{ display: 'flex', gap: '12px', marginTop: '32px' }}>
               <button className="btn" style={{ flex: 1, background: '#F3F4F6' }} onClick={() => setScannedBooking(null)}>Close</button>
               {scannedBooking.status === 'Confirmed' && (
                 <button className="btn btn-primary" style={{ flex: 2 }} onClick={() => { updateStatus(scannedBooking.id, 'Checked In'); setScannedBooking(null); }}>VERIFY CHECK-IN</button>
               )}
               {scannedBooking.status === 'Checked In' && (
                 <button className="btn btn-secondary" style={{ flex: 2 }} onClick={() => { updateStatus(scannedBooking.id, 'Completed'); setScannedBooking(null); }}>VERIFY CHECK-OUT</button>
               )}
            </div>
          </div>
        </div>
      )}

      <style>{`
        .close-btn { background: #F3F4F6; border: none; width: 36px; height: 36px; border-radius: 50%; display: flex; align-items: center; justify-content: center; cursor: pointer; color: var(--text-main); transition: var(--transition); }
        .close-btn:hover { background: #E5E7EB; transform: rotate(90deg); }
        .view-transition { animation: fadeIn 0.4s ease-out; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
      `}</style>
    </div>
  );
};

const BookingCard = ({ booking, onDelete, onUpdateStatus, hasConflict }) => {
  const [photo, setPhoto] = useState(null);

  useEffect(() => {
    const fetchTouristPhoto = async () => {
      if (!booking.touristUid) return;
      try {
        const userSnap = await get(ref(db, `users/${booking.touristUid}`));
        if (userSnap.exists() && userSnap.val().profilePicUrl) {
          setPhoto(userSnap.val().profilePicUrl);
        }
      } catch (e) {
        console.error("Tourist photo fetch error", e);
      }
    };
    fetchTouristPhoto();
  }, [booking.touristUid]);

  return (
    <div className="card" style={{
      position: 'relative',
      marginBottom: '0',
      border: hasConflict ? '2px solid var(--primary)' : '1px solid rgba(0,0,0,0.05)',
      padding: '20px'
    }}>
      <button
        onClick={onDelete}
        style={{ position: 'absolute', top: '20px', right: '20px', background: '#F3F4F6', border: 'none', cursor: 'pointer', color: '#9CA3AF', width: '32px', height: '32px', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center' }}
      >
        <Trash2 size={16} />
      </button>
      <div style={{ display: 'flex', gap: '20px' }}>
        <div style={{ flex: 1 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '12px' }}>
            <div style={{
              width: '44px', height: '44px', borderRadius: '14px',
              background: '#F3F4F6', overflow: 'hidden',
              display: 'flex', justifyContent: 'center', alignItems: 'center', color: 'var(--secondary)'
            }}>
              {photo ? (
                <img src={photo} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
              ) : (
                <User size={22} />
              )}
            </div>
            <div>
              <h4 style={{ margin: 0, fontSize: '16px', fontWeight: 800 }}>{booking.touristName}</h4>
              <span className={`status-badge status-${(booking.status || 'pending').toLowerCase().replace(' ', '-')}`}>
                {booking.status || 'Pending'}
              </span>
            </div>
          </div>

          <div style={{ background: '#F9FAFB', padding: '16px', borderRadius: '16px', marginBottom: '20px' }}>
            <p style={{ margin: '0 0 4px 0', fontWeight: 800, fontSize: '15px' }}>{booking.activityTitle || booking.roomTitle}</p>
            <div style={{ fontSize: '13px', color: 'var(--text-muted)', display: 'flex', gap: '12px', flexWrap: 'wrap' }}>
              <span style={{ fontWeight: 700 }}>
                {booking.bookingDate} - {format(addDays(parse(booking.bookingDate, 'MMM dd, yyyy', new Date()), parseInt(booking.nights) || 1), 'MMM dd, yyyy')}
              </span>
              <span>•</span>
              <span>{booking.nights} Night/s</span>
              <span>•</span>
              <span style={{ fontWeight: 800, color: 'var(--secondary)' }}>₱{booking.totalPrice}</span>
            </div>
            {booking.paymentOption && (
               <div style={{ marginTop: '8px', fontSize: '12px', fontWeight: 700, color: 'var(--primary)', display: 'flex', alignItems: 'center', gap: '4px' }}>
                  <CreditCard size={14} /> {booking.paymentOption}
               </div>
            )}
          </div>

          {hasConflict && (
            <div style={{ color: 'var(--primary)', fontSize: '12px', display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '16px', background: '#FEF2F2', padding: '10px', borderRadius: '10px', fontWeight: 600 }}>
              <AlertCircle size={16} /> Overlaps with an existing reservation.
            </div>
          )}

          <div style={{ display: 'flex', gap: '12px' }}>
            {booking.gcashReceipt && (
              <a href={booking.gcashReceipt} target="_blank" rel="noopener noreferrer" className="btn" style={{ background: '#EFF6FF', color: '#1D4ED8', padding: '10px 16px', fontSize: '13px', flex: 0.5 }}>
                <Eye size={16} /> Receipt
              </a>
            )}

            <div style={{ display: 'flex', gap: '10px', flex: 1 }}>
              {(booking.status || 'Pending').toLowerCase() === 'pending' && (
                <>
                  <button className="btn" style={{ background: '#FEF2F2', color: 'var(--primary)', flex: 1, fontSize: '13px' }} onClick={() => onUpdateStatus(booking.id, 'Cancelled')}>Decline</button>
                  <button className="btn btn-primary" style={{ flex: 1.5, fontSize: '13px' }} onClick={() => onUpdateStatus(booking.id, 'Confirmed')}>Confirm</button>
                </>
              )}
              {(booking.status || '').toLowerCase() === 'confirmed' && (
                <button className="btn" style={{ background: '#4F46E5', color: 'white', width: '100%', fontSize: '13px' }} onClick={() => onUpdateStatus(booking.id, 'Checked In')}>CHECK IN</button>
              )}
              {(booking.status || '').toLowerCase() === 'checked in' && (
                <button className="btn" style={{ background: 'var(--secondary)', color: '#002D24', width: '100%', fontSize: '13px' }} onClick={() => onUpdateStatus(booking.id, 'Completed')}>CHECK OUT</button>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default OwnerDashboard;
