import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, onValue, update, remove } from 'firebase/database';
import { Bell, ShoppingCart, CheckCircle, XCircle, Info, ArrowLeft, Calendar, MessageSquare, Trash2 } from 'lucide-react';
import { format } from 'date-fns';

const Notifications = ({ uid, onBack }) => {
  const [notifications, setNotifications] = useState([]);
  const [loading, setLoading] = useState(true);
  const [selectedNotif, setSelectedNotif] = useState(null);
  const [viewMode, setViewMode] = useState('active');
  const [filterType, setFilterType] = useState('All');
  const [searchQuery, setSearchQuery] = useState('');

  useEffect(() => {
    const notifRef = ref(db, `notifications/${uid}`);
    const unsubscribe = onValue(notifRef, (snapshot) => {
      const data = snapshot.val();
      if (data) {
        const list = Object.entries(data)
          .map(([id, val]) => ({ id, ...val }))
          .sort((a, b) => {
            const aRead = a.isRead ? 1 : 0;
            const bRead = b.isRead ? 1 : 0;
            if (aRead !== bRead) return aRead - bRead;
            if (aRead === 0) {
              return (a.timestamp || 0) - (b.timestamp || 0);
            } else {
              return (b.timestamp || 0) - (a.timestamp || 0);
            }
          });
        setNotifications(list);
      } else {
        setNotifications([]);
      }
      setLoading(false);
    });

    return () => unsubscribe();
  }, [uid]);

  const markAsRead = async (id) => {
    await update(ref(db, `notifications/${uid}/${id}`), { isRead: true });
  };

  const deleteNotification = async (e, id) => {
    e.stopPropagation();
    if (window.confirm("Are you sure you want to permanently delete this notification?")) {
      await remove(ref(db, `notifications/${uid}/${id}`));
      if (selectedNotif?.id === id) setSelectedNotif(null);
    }
  };

  const archiveNotification = async (e, id) => {
    e.stopPropagation();
    await update(ref(db, `notifications/${uid}/${id}`), { isArchived: true });
    if (selectedNotif?.id === id) setSelectedNotif(null);
  };

  const displayedNotifications = notifications.filter(n => {
    const matchesTab = viewMode === 'active' ? !n.isArchived : n.isArchived;
    if (!matchesTab) return false;
    
    if (filterType !== 'All') {
      const titleLower = (n.title || '').toLowerCase();
      const typeLower = filterType.toLowerCase();
      if (!titleLower.includes(typeLower)) return false;
    }
    
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      const t = (n.title || '').toLowerCase();
      const m = (n.message || '').toLowerCase();
      if (!t.includes(q) && !m.includes(q)) return false;
    }
    return true;
  });

  const getIcon = (type) => {
    switch (type) {
      case 'booking_new': return <ShoppingCart size={20} color="#3B82F6" />;
      case 'booking_accepted': return <CheckCircle size={20} color="#10B981" />;
      case 'booking_rejected': return <XCircle size={20} color="var(--primary)" />;
      case 'new_message': return <MessageSquare size={20} color="var(--secondary)" />;
      default: return <Bell size={20} color="var(--secondary)" />;
    }
  };

  if (loading) return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '60vh' }}>
      <div className="loader"></div>
    </div>
  );

  return (
    <div className="view-transition" style={{ maxWidth: '700px', margin: '0 auto', paddingBottom: '60px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: '16px', marginBottom: '32px' }}>
        <button
          onClick={onBack}
          style={{
            background: 'var(--surface)', border: '1px solid var(--border)', width: '44px', height: '44px',
            borderRadius: '14px', display: 'flex', alignItems: 'center',
            justifyContent: 'center', cursor: 'pointer', boxShadow: 'var(--shadow)',
            color: 'var(--text-main)'
          }}
        >
          <ArrowLeft size={22} />
        </button>
        <div>
          <h2 style={{ margin: 0, fontSize: '28px', fontWeight: 800 }}>Activity</h2>
          <p style={{ margin: 0, color: 'var(--text-muted)', fontSize: '14px', fontWeight: 600 }}>Stay updated with your latest alerts</p>
        </div>
      </div>

      <div style={{ display: 'flex', gap: '12px', marginBottom: '16px', background: 'var(--surface)', padding: '6px', borderRadius: '16px', border: '1px solid var(--border)' }}>
        <button onClick={() => setViewMode('active')} style={{ flex: 1, padding: '12px', borderRadius: '12px', border: 'none', background: viewMode === 'active' ? 'var(--primary)' : 'transparent', color: viewMode === 'active' ? 'white' : 'var(--text-main)', fontWeight: 700, cursor: 'pointer', transition: '0.2s' }}>Active</button>
        <button onClick={() => setViewMode('archive')} style={{ flex: 1, padding: '12px', borderRadius: '12px', border: 'none', background: viewMode === 'archive' ? 'var(--primary)' : 'transparent', color: viewMode === 'archive' ? 'white' : 'var(--text-main)', fontWeight: 700, cursor: 'pointer', transition: '0.2s' }}>Archive</button>
      </div>

      <div style={{ display: 'flex', gap: '12px', marginBottom: '24px', flexWrap: 'wrap' }}>
        <div style={{ flex: 1, minWidth: '200px' }}>
          <input 
            type="text" 
            className="input" 
            placeholder="Search by user, room, date..." 
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            style={{ width: '100%', padding: '12px', borderRadius: '12px', border: '1px solid var(--border)' }}
          />
        </div>
        <div style={{ minWidth: '150px' }}>
          <select 
            className="input" 
            value={filterType}
            onChange={(e) => setFilterType(e.target.value)}
            style={{ width: '100%', padding: '12px', borderRadius: '12px', border: '1px solid var(--border)', background: 'var(--surface)' }}
          >
            <option value="All">All Categories</option>
            <option value="Booking">Bookings</option>
            <option value="Refund">Refunds</option>
            <option value="Reschedule">Reschedules</option>
            <option value="Approved">Approved</option>
            <option value="Pending">Pending</option>
            <option value="Declined">Declined</option>
          </select>
        </div>
      </div>

      {displayedNotifications.length > 0 ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
          {displayedNotifications.map(notif => (
            <div
              key={notif.id}
              className={`notification-card ${notif.isRead ? 'read' : 'unread'}`}
              style={{
                display: 'flex', gap: '20px', padding: '20px',
                background: notif.isRead ? 'var(--surface)' : 'linear-gradient(to right, var(--surface), rgba(29, 211, 176, 0.06))',
                borderRadius: '24px',
                cursor: 'pointer',
                border: '1px solid',
                borderColor: notif.isRead ? 'var(--border)' : 'rgba(29, 211, 176, 0.2)',
                boxShadow: notif.isRead ? 'var(--shadow)' : '0 10px 25px -5px rgba(29, 211, 176, 0.1)',
                position: 'relative',
                overflow: 'hidden',
                transition: 'var(--transition)'
              }}
              onClick={() => {
                markAsRead(notif.id);
                setSelectedNotif(notif);
              }}
            >
              {!notif.isRead && (
                <div style={{
                  position: 'absolute', top: 0, left: 0, bottom: 0, width: '4px',
                  background: 'var(--secondary)'
                }}></div>
              )}

              <div style={{
                width: '52px', height: '52px', borderRadius: '16px',
                background: notif.isRead ? 'var(--light-bg)' : 'var(--surface)',
                display: 'flex', justifyContent: 'center', alignItems: 'center',
                boxShadow: '0 4px 10px rgba(0,0,0,0.03)',
                flexShrink: 0,
                border: '1px solid var(--border)'
              }}>
                {getIcon(notif.type)}
              </div>

              <div style={{ flex: 1 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '4px' }}>
                  <h4 style={{
                    margin: 0,
                    fontSize: '16px',
                    fontWeight: notif.isRead ? 700 : 800,
                    color: 'var(--text-main)'
                  }}>
                    {notif.title}
                  </h4>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '4px', color: 'var(--text-muted)', fontSize: '11px', fontWeight: 700 }}>
                    <Calendar size={12} />
                    {notif.timestamp ? format(new Date(notif.timestamp), 'MMM dd, p') : ''}
                  </div>
                </div>
                <p style={{
                  margin: 0,
                  fontSize: '14px',
                  color: 'var(--text-muted)',
                  lineHeight: '1.5',
                  fontWeight: 500,
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                  display: '-webkit-box',
                  WebkitLineClamp: 2,
                  WebkitBoxOrient: 'vertical'
                }}>
                  {notif.message}
                </p>
              </div>

              <div style={{ display: 'flex', alignItems: 'center' }}>
                <button
                  type="button"
                  onClick={(e) => deleteNotification(e, notif.id)}
                  style={{
                    background: 'transparent',
                    border: 'none',
                    color: 'var(--primary)',
                    cursor: 'pointer',
                    padding: '8px',
                    borderRadius: '50%',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    transition: 'background 0.2s'
                  }}
                  onMouseOver={(e) => e.currentTarget.style.background = 'rgba(251, 54, 64, 0.1)'}
                  onMouseOut={(e) => e.currentTarget.style.background = 'transparent'}
                  title="Delete Notification"
                >
                  <Trash2 size={18} />
                </button>
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div style={{ textAlign: 'center', padding: '100px 0' }}>
          <div style={{
            width: '100px', height: '100px', background: 'var(--surface)',
            borderRadius: '40px', display: 'flex', justifyContent: 'center',
            alignItems: 'center', margin: '0 auto 24px', boxShadow: 'var(--shadow)',
            border: '1px solid var(--border)'
          }}>
            <Bell size={48} color="var(--text-muted)" style={{ opacity: 0.3 }} />
          </div>
          <h3 style={{ fontSize: '20px', fontWeight: 800, color: 'var(--text-main)', margin: '0 0 8px 0' }}>All Caught Up!</h3>
          <p style={{ color: 'var(--text-muted)', fontWeight: 600 }}>No new notifications to show right now.</p>
          <button className="btn" style={{ background: 'var(--light-bg)', color: 'var(--text-main)', border: '1px solid var(--border)', margin: '24px auto 0' }} onClick={onBack}>Return Home</button>
        </div>
      )}

      {selectedNotif && (
        <div className="modal-overlay" style={{ zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div className="modal-content" style={{ background: 'var(--surface)', borderRadius: '24px', maxWidth: '440px', width: '90%', padding: '0', position: 'relative', overflow: 'hidden' }}>
            <div style={{ background: 'linear-gradient(135deg, var(--secondary), var(--primary))', padding: '32px 24px', display: 'flex', flexDirection: 'column', alignItems: 'center', color: 'white', position: 'relative' }}>
              <button onClick={() => setSelectedNotif(null)} style={{ position: 'absolute', top: '16px', right: '16px', background: 'rgba(255,255,255,0.2)', border: 'none', borderRadius: '50%', width: '32px', height: '32px', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', color: 'white' }}>
                <XCircle size={20} />
              </button>
              <div style={{ width: '64px', height: '64px', borderRadius: '20px', background: 'rgba(255,255,255,0.2)', display: 'flex', justifyContent: 'center', alignItems: 'center', backdropFilter: 'blur(10px)', marginBottom: '16px' }}>
                {React.cloneElement(getIcon(selectedNotif.type), { size: 32, color: 'white' })}
              </div>
              <h3 style={{ margin: 0, fontSize: '22px', fontWeight: 800, textAlign: 'center' }}>{selectedNotif.title}</h3>
              <span style={{ fontSize: '13px', color: 'rgba(255,255,255,0.8)', fontWeight: 600, marginTop: '8px' }}>
                {selectedNotif.timestamp ? format(new Date(selectedNotif.timestamp), 'MMMM dd, yyyy • hh:mm a') : 'Just now'}
              </span>
            </div>
            <div style={{ padding: '32px 24px' }}>
              <div style={{ background: 'var(--light-bg)', padding: '24px', borderRadius: '16px', border: '1px solid var(--border)', marginBottom: '24px' }}>
                <h4 style={{ margin: '0 0 12px 0', fontSize: '12px', color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '1px', fontWeight: 800 }}>Notification Details</h4>
                <p style={{ margin: 0, fontSize: '16px', color: 'var(--text-main)', lineHeight: '1.7', fontWeight: 500, whiteSpace: 'pre-wrap' }}>
                  {selectedNotif.message}
                </p>
              </div>
              {viewMode === 'active' ? (
                <button 
                  className="btn btn-primary" 
                  style={{ width: '100%', background: 'var(--primary)', border: 'none' }}
                  onClick={(e) => archiveNotification(e, selectedNotif.id)}
                >
                  Move to Archive
                </button>
              ) : (
                <button 
                  className="btn btn-primary" 
                  style={{ width: '100%', background: 'var(--primary)', border: 'none' }}
                  onClick={(e) => deleteNotification(e, selectedNotif.id)}
                >
                  Permanently Delete
                </button>
              )}
            </div>
          </div>
        </div>
      )}

      <style>{`
        .notification-card:hover { transform: translateY(-3px); boxShadow: 0 15px 30px -10px rgba(0,0,0,0.1) !important; }
        .view-transition { animation: fadeIn 0.4s ease-out; }
      `}</style>
    </div>
  );
};

export default Notifications;
