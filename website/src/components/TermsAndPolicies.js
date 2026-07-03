import React, { useEffect, useRef } from 'react';
import { X, ScrollText } from 'lucide-react';

const TermsAndPolicies = ({ onClose, initialScroll }) => {
  const privacyRef = useRef(null);

  useEffect(() => {
    if (initialScroll === 'privacy' && privacyRef.current) {
      setTimeout(() => {
        privacyRef.current.scrollIntoView({ behavior: 'smooth' });
      }, 100);
    }
  }, [initialScroll]);

  return (
    <div className="modal-overlay" style={{ zIndex: 5000, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <div className="modal-content" style={{ background: 'var(--surface)', borderRadius: '24px', maxWidth: '600px', width: '90%', maxHeight: '85vh', overflowY: 'auto', padding: '0', position: 'relative' }}>
        <div style={{ position: 'sticky', top: 0, background: 'var(--surface)', padding: '24px', borderBottom: '1px solid var(--border)', zIndex: 10, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <div style={{ width: '40px', height: '40px', borderRadius: '10px', background: 'var(--primary)', color: 'white', display: 'flex', justifyContent: 'center', alignItems: 'center' }}>
              <ScrollText size={20} />
            </div>
            <h3 style={{ margin: 0, fontSize: '20px', fontWeight: 800 }}>Terms and Policies</h3>
          </div>
          <button onClick={onClose} style={{ background: 'var(--light-bg)', border: 'none', width: '36px', height: '36px', borderRadius: '50%', display: 'flex', justifyContent: 'center', alignItems: 'center', cursor: 'pointer', color: 'var(--text-main)' }}>
            <X size={18} />
          </button>
        </div>

        <div style={{ padding: '24px', color: 'var(--text-main)', fontSize: '14px', lineHeight: 1.6 }}>
          <h4 style={{ fontSize: '16px', fontWeight: 700, marginBottom: '12px', color: 'var(--primary)' }}>1. Booking and Reservations</h4>
          <p style={{ marginBottom: '16px' }}>All bookings must be confirmed through the platform. A valid identification card must be presented upon check-in. The person whose name is on the booking must be present.</p>

          <h4 style={{ fontSize: '16px', fontWeight: 700, marginBottom: '12px', color: 'var(--primary)' }}>2. Check-in and Check-out Policies</h4>
          <p style={{ marginBottom: '16px' }}>Standard check-in time is 2:00 PM, and check-out time is 12:00 PM. Early check-in or late check-out is subject to availability and may incur additional charges.</p>

          <h4 style={{ fontSize: '16px', fontWeight: 700, marginBottom: '12px', color: 'var(--primary)' }}>3. Cancellation and Refund Policy</h4>
          <p style={{ marginBottom: '16px' }}>Cancellations made 48 hours prior to the check-in date may be eligible for a refund, subject to the resort's specific rules. Late cancellations or no-shows are strictly non-refundable. Refunds will be processed through GCash.</p>

          <h4 style={{ fontSize: '16px', fontWeight: 700, marginBottom: '12px', color: 'var(--primary)' }}>4. Resort Rules and Code of Conduct</h4>
          <p style={{ marginBottom: '16px' }}>Guests are expected to behave respectfully. Excessive noise, illegal activities, and damage to property are strictly prohibited. The resort reserves the right to evict guests who violate these terms without a refund.</p>

          <h4 style={{ fontSize: '16px', fontWeight: 700, marginBottom: '12px', color: 'var(--primary)' }}>5. Liability and Security</h4>
          <p style={{ marginBottom: '24px' }}>The resort, hotel, and platform are not responsible for the loss or damage of personal belongings. Please secure your valuables. ResortConnect is merely a facilitator of bookings and does not directly operate the individual properties.</p>

          <hr style={{ border: 'none', borderTop: '1px solid var(--border)', margin: '32px 0' }} />

          <h3 ref={privacyRef} style={{ fontSize: '18px', fontWeight: 800, marginBottom: '16px', color: 'var(--text-main)', scrollMarginTop: '90px' }}>Data Privacy Policy</h3>
          
          <h4 style={{ fontSize: '16px', fontWeight: 700, marginBottom: '12px', color: 'var(--primary)' }}>1. Information We Collect</h4>
          <p style={{ marginBottom: '16px' }}>To facilitate your bookings across our partner properties (2 Resorts and 1 Hotel), we collect your name, contact number, email address, Government ID (for verification), and GCash payment receipts.</p>

          <h4 style={{ fontSize: '16px', fontWeight: 700, marginBottom: '12px', color: 'var(--primary)' }}>2. How We Use Your Data</h4>
          <p style={{ marginBottom: '16px' }}>Your data is strictly used to confirm your identity, process reservations, and ensure secure communication between you and the property hosts. GCash receipts are used exclusively for payment verification.</p>

          <h4 style={{ fontSize: '16px', fontWeight: 700, marginBottom: '12px', color: 'var(--primary)' }}>3. Data Sharing</h4>
          <p style={{ marginBottom: '16px' }}>We only share your booking details and identity verification with the specific resort or hotel you booked. We do not sell or rent your personal information to third parties.</p>

          <h4 style={{ fontSize: '16px', fontWeight: 700, marginBottom: '12px', color: 'var(--primary)' }}>4. Data Security and Retention</h4>
          <p style={{ marginBottom: '16px' }}>Your data is securely stored using industry-standard encryption on Google Cloud (Firebase). You may request account deletion at any time, which will permanently remove your personal identifiable information from our active databases.</p>
        </div>
      </div>
    </div>
  );
};

export default TermsAndPolicies;
