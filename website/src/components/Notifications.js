import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, onValue, update } from 'firebase/database';
import { Bell, ShoppingCart, CheckCircle, XCircle, Info, ArrowLeft, Calendar, MessageSquare } from 'lucide-react';
import { format } from 'date-fns';

const Notifications = ({ uid, onBack }) => {
  const [notifications, setNotifications] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const notifRef = ref(db, `notifications/${uid}`);
    const unsubscribe = onValue(notifRef, (snapshot) => {
      const data = snapshot.val();
      if (data) {
        const list = Object.entries(data)
          .map(([id, val]) => ({ id, ...val }))
          .sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0));
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

      {notifications.length > 0 ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
          {notifications.map(notif => (
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
              onClick={() => markAsRead(notif.id)}
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
                  fontWeight: 500
                }}>
                  {notif.message}
                </p>
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

      <style>{`
        .notification-card:hover { transform: translateY(-3px); boxShadow: 0 15px 30px -10px rgba(0,0,0,0.1) !important; }
        .view-transition { animation: fadeIn 0.4s ease-out; }
      `}</style>
    </div>
  );
};

export default Notifications;
