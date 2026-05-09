import React, { useEffect, useState, useRef } from 'react';
import { Html5QrcodeScanner } from 'html5-qrcode';
import { X, Loader2 } from 'lucide-react';
import { db } from '../firebase';
import { ref, get } from 'firebase/database';

const QrScanner = ({ onResult, onClose }) => {
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const scannerRef = useRef(null);

  useEffect(() => {
    if (scannerRef.current) return;

    const onScanSuccess = async (decodedText) => {
      console.log("QR Decoded:", decodedText);
      if (scannerRef.current) {
        try {
          await scannerRef.current.clear();
        } catch (e) {
          console.warn("Failed to clear scanner:", e);
        }
      }
      setLoading(true);

      try {
        let bookingId = decodedText.trim();
        // Robust extraction logic to handle various formats
        if (decodedText.includes('scan=')) {
          // Format: domain.com/owner?scan=BOOKING_ID
          const url = new URL(decodedText);
          bookingId = url.searchParams.get('scan');
        } else if (decodedText.startsWith('http')) {
          // Format: domain.com/any/path/BOOKING_ID
          bookingId = decodedText.split('/').pop().split('?')[0];
        }
        // If it's not a URL, it's already considered a pure bookingId

        const snap = await get(ref(db, `bookings/${bookingId}`));
        if (snap.exists()) {
          onResult({ id: bookingId, ...snap.val() });
        } else {
          setError(`Booking ID '${bookingId}' not found in records.`);
          setLoading(false);
        }
      } catch (err) {
        setError('QR Format Error: ' + err.message);
        setLoading(false);
      }
    };

    const onScanError = (err) => {
      // Ignore scan errors as they happen constantly
    };

    const timer = setTimeout(() => {
      try {
        const scanner = new Html5QrcodeScanner('reader', {
          qrbox: { width: 250, height: 250 },
          fps: 10,
        });
        scanner.render(onScanSuccess, onScanError);
        scannerRef.current = scanner;
      } catch (e) {
        console.error("Scanner init error", e);
      }
    }, 500);

    return () => {
      clearTimeout(timer);
      if (scannerRef.current) {
        scannerRef.current.clear().catch(err => console.warn("Failed to clear scanner", err));
        scannerRef.current = null;
      }
    };
  }, [onResult]);

  return (
    <div className="modal-overlay" style={{ zIndex: 5000 }}>
      <div className="card modal-content" style={{ maxWidth: '500px', textAlign: 'center', background: 'white' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
          <h3 style={{ margin: 0, fontWeight: 800 }}>Scan Guest QR Code</h3>
          <button onClick={onClose} style={{ background: '#F3F4F6', border: 'none', width: '36px', height: '36px', borderRadius: '50%', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><X size={20} /></button>
        </div>

        {loading ? (
          <div style={{ padding: '60px 0' }}>
            <Loader2 className="loader" style={{ margin: '0 auto 20px', animation: 'spin 1s linear infinite' }} />
            <p style={{ fontWeight: 600, color: 'var(--text-muted)' }}>Retrieving booking data...</p>
          </div>
        ) : (
          <>
            <div id="reader" style={{ overflow: 'hidden', borderRadius: '20px', border: 'none' }}></div>
            {error && <div style={{ background: '#FEF2F2', color: '#B91C1C', padding: '12px', borderRadius: '12px', marginTop: '20px', fontSize: '14px', fontWeight: 600 }}>{error}</div>}
            <p style={{ fontSize: '13px', color: 'var(--text-muted)', marginTop: '24px', fontWeight: 500 }}>
              Use your camera to scan the guest's digital booking receipt.
            </p>
          </>
        )}
      </div>
      <style>{`
        #reader__dashboard_section_csr button {
          padding: 10px 20px;
          background: var(--primary) !important;
          color: white !important;
          border: none !important;
          border-radius: 10px !important;
          font-weight: 700 !important;
          cursor: pointer !important;
          margin: 10px !important;
        }
        #reader { border: none !important; }
        @keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
      `}</style>
    </div>
  );
};

export default QrScanner;
