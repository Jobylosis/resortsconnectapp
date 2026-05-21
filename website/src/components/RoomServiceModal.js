import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, push, onValue, update, serverTimestamp } from 'firebase/database';
import { X, ShoppingBag, Plus, Minus, CheckCircle2, Coffee, Utensils, Bed, Sparkles } from 'lucide-react';

const CATEGORY_ICONS = {
  'Food': <Utensils size={16} />,
  'Drinks': <Coffee size={16} />,
  'Toiletries': <Sparkles size={16} />,
  'Bedding': <Bed size={16} />,
};

const DEFAULT_MENU = {
  Food: [
    { id: 'f1', name: 'Club Sandwich', price: 220, desc: 'Toasted triple-decker sandwich' },
    { id: 'f2', name: 'Pancit Palabok', price: 180, desc: 'Filipino rice noodles in shrimp sauce' },
    { id: 'f3', name: 'Chicken Adobo', price: 200, desc: 'Classic braised chicken' },
    { id: 'f4', name: 'Sinigang na Baboy', price: 220, desc: 'Pork sour broth' },
  ],
  Drinks: [
    { id: 'd1', name: 'Fresh Buko Juice', price: 80, desc: 'Chilled young coconut' },
    { id: 'd2', name: 'Iced Coffee', price: 120, desc: 'Cold brew with milk' },
    { id: 'd3', name: 'Fruit Shake', price: 100, desc: 'Mango, avocado, or strawberry' },
  ],
  Toiletries: [
    { id: 't1', name: 'Towel Set', price: 50, desc: 'Fresh bath & face towels' },
    { id: 't2', name: 'Toiletry Kit', price: 80, desc: 'Soap, shampoo, conditioner' },
    { id: 't3', name: 'Extra Pillow', price: 30, desc: 'Firm or soft' },
  ],
  Bedding: [
    { id: 'b1', name: 'Extra Blanket', price: 40, desc: 'Thick fleece blanket' },
    { id: 'b2', name: 'Baby Cot', price: 150, desc: 'Safe cot for infants' },
  ],
};

const RoomServiceModal = ({ onClose, booking, ownerUid }) => {
  const [menu, setMenu] = useState(DEFAULT_MENU);
  const [activeCategory, setActiveCategory] = useState('Food');
  const [cart, setCart] = useState({});
  const [step, setStep] = useState(1); // 1: menu, 2: success
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!ownerUid) return;
    const menuRef = ref(db, `properties/${ownerUid}/roomServiceMenu`);
    const unsub = onValue(menuRef, (snap) => {
      if (snap.exists()) {
        const data = snap.val();
        const parsed = {};
        Object.entries(data).forEach(([cat, items]) => {
          parsed[cat] = Object.entries(items).map(([id, item]) => ({ id, ...item }));
        });
        if (Object.keys(parsed).length > 0) setMenu(parsed);
      }
    });
    return () => unsub();
  }, [ownerUid]);

  const updateCart = (itemId, delta, item) => {
    setCart(prev => {
      const current = prev[itemId]?.qty || 0;
      const next = Math.max(0, Math.min(10, current + delta));
      if (next === 0) {
        const updated = { ...prev };
        delete updated[itemId];
        return updated;
      }
      return { ...prev, [itemId]: { ...item, qty: next } };
    });
  };

  const cartTotal = Object.values(cart).reduce((sum, i) => sum + i.price * i.qty, 0);
  const cartCount = Object.values(cart).reduce((sum, i) => sum + i.qty, 0);

  const handleSubmit = async () => {
    if (cartCount === 0) return;
    setSubmitting(true);
    try {
      const orderId = push(ref(db, `room_service_orders`)).key;
      const orderData = {
        bookingId: booking?.id || 'unknown',
        ownerUid: ownerUid,
        guestName: booking?.touristName || 'Guest',
        roomTitle: booking?.activityTitle || booking?.roomTitle || 'Room',
        items: Object.values(cart).map(i => ({ name: i.name, qty: i.qty, price: i.price, total: i.price * i.qty })),
        totalAmount: cartTotal,
        status: 'Pending',
        timestamp: serverTimestamp(),
      };
      await update(ref(db, `room_service_orders/${orderId}`), orderData);

      // Notify owner
      if (ownerUid) {
        await push(ref(db, `notifications/${ownerUid}`), {
          title: 'New Room Service Order',
          message: `${orderData.guestName} ordered ${cartCount} item(s) for ${orderData.roomTitle}. Total: ₱${cartTotal.toLocaleString()}`,
          type: 'room_service',
          isRead: false,
          timestamp: serverTimestamp(),
        });
      }
      setStep(2);
    } catch (err) {
      alert('Failed to place order: ' + err.message);
    } finally {
      setSubmitting(false);
    }
  };

  if (step === 2) {
    return (
      <div className="modal-overlay" style={{ zIndex: 5000 }}>
        <div className="card modal-content" style={{ maxWidth: '380px', textAlign: 'center', padding: '48px 32px' }}>
          <div style={{ width: '80px', height: '80px', background: '#ECFDF5', borderRadius: '50%', display: 'flex', justifyContent: 'center', alignItems: 'center', margin: '0 auto 24px' }}>
            <CheckCircle2 size={40} color="#10B981" />
          </div>
          <h3 style={{ fontWeight: 800, fontSize: '22px', margin: '0 0 12px 0' }}>Order Placed!</h3>
          <p style={{ color: 'var(--text-muted)', lineHeight: '1.6', marginBottom: '32px' }}>
            Your room service order has been sent. Our staff will deliver it shortly to your room.
          </p>
          <button onClick={onClose} className="btn btn-primary" style={{ width: '100%' }}>Done</button>
        </div>
      </div>
    );
  }

  const categories = Object.keys(menu);

  return (
    <div className="modal-overlay" style={{ zIndex: 5000 }}>
      <div className="card modal-content" onClick={e => e.stopPropagation()} style={{ maxWidth: '500px', borderRadius: '32px', padding: 0, overflow: 'hidden', display: 'flex', flexDirection: 'column', maxHeight: '90vh' }}>
        {/* Header */}
        <div style={{ padding: '24px 28px', borderBottom: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexShrink: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <div style={{ background: 'rgba(251,54,64,0.1)', padding: '10px', borderRadius: '14px' }}>
              <ShoppingBag size={22} color="var(--primary)" />
            </div>
            <div>
              <h3 style={{ margin: 0, fontWeight: 800, fontSize: '20px' }}>Room Service</h3>
              <p style={{ margin: 0, fontSize: '12px', color: 'var(--text-muted)', fontWeight: 600 }}>{booking?.activityTitle || 'Your Room'}</p>
            </div>
          </div>
          <button onClick={onClose} className="close-btn"><X size={20} /></button>
        </div>

        {/* Category Tabs */}
        <div style={{ display: 'flex', gap: '8px', padding: '16px 20px', background: 'var(--light-bg)', flexShrink: 0, overflowX: 'auto' }}>
          {categories.map(cat => (
            <button key={cat} onClick={() => setActiveCategory(cat)} style={{
              display: 'flex', alignItems: 'center', gap: '6px', padding: '9px 16px',
              borderRadius: '12px', border: 'none', whiteSpace: 'nowrap',
              background: activeCategory === cat ? 'var(--surface)' : 'transparent',
              color: activeCategory === cat ? 'var(--primary)' : 'var(--text-muted)',
              fontWeight: 700, fontSize: '13px', cursor: 'pointer',
              boxShadow: activeCategory === cat ? 'var(--shadow)' : 'none',
              transition: 'var(--transition)'
            }}>
              {CATEGORY_ICONS[cat] || <ShoppingBag size={14} />} {cat}
            </button>
          ))}
        </div>

        {/* Menu Items */}
        <div style={{ flex: 1, overflowY: 'auto', padding: '16px 20px' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
            {(menu[activeCategory] || []).map(item => {
              const qty = cart[item.id]?.qty || 0;
              return (
                <div key={item.id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '16px', background: 'var(--light-bg)', borderRadius: '16px', border: qty > 0 ? '1.5px solid var(--secondary)' : '1px solid var(--border)', transition: 'var(--transition)' }}>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontWeight: 800, fontSize: '14px', marginBottom: '2px' }}>{item.name}</div>
                    <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 500 }}>{item.desc}</div>
                    <div style={{ fontWeight: 800, color: 'var(--secondary)', fontSize: '15px', marginTop: '4px' }}>₱{item.price}</div>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginLeft: '12px' }}>
                    {qty > 0 ? (
                      <>
                        <button onClick={() => updateCart(item.id, -1, item)} style={{ width: '32px', height: '32px', borderRadius: '10px', border: '1px solid var(--border)', background: 'var(--surface)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--primary)' }}><Minus size={14} /></button>
                        <span style={{ fontWeight: 900, fontSize: '16px', minWidth: '20px', textAlign: 'center' }}>{qty}</span>
                        <button onClick={() => updateCart(item.id, 1, item)} style={{ width: '32px', height: '32px', borderRadius: '10px', border: 'none', background: 'var(--secondary)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#002D24' }}><Plus size={14} /></button>
                      </>
                    ) : (
                      <button onClick={() => updateCart(item.id, 1, item)} className="btn btn-primary" style={{ padding: '8px 16px', fontSize: '13px', borderRadius: '10px' }}>Add</button>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Cart Footer */}
        {cartCount > 0 && (
          <div style={{ padding: '20px 24px', borderTop: '1px solid var(--border)', background: 'var(--surface)', flexShrink: 0 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '12px' }}>
              <span style={{ fontWeight: 700, color: 'var(--text-muted)' }}>{cartCount} item{cartCount !== 1 ? 's' : ''} in order</span>
              <span style={{ fontWeight: 900, fontSize: '18px', color: 'var(--secondary)' }}>₱{cartTotal.toLocaleString()}</span>
            </div>
            <button onClick={handleSubmit} className="btn btn-primary" style={{ width: '100%', height: '52px', fontSize: '15px' }} disabled={submitting}>
              {submitting ? <div className="loader" style={{ width: '20px', height: '20px', borderTopColor: 'white' }} /> : `Place Order · ₱${cartTotal.toLocaleString()}`}
            </button>
          </div>
        )}
      </div>
    </div>
  );
};

export default RoomServiceModal;
