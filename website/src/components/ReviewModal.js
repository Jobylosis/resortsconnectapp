import React, { useState, useRef } from 'react';
import { db } from '../firebase';
import { ref, push, update, serverTimestamp } from 'firebase/database';
import { X, Star, Heart, MessageCircle, Camera, Image, Trash2 } from 'lucide-react';

const ReviewModal = ({ booking, onClose }) => {
  const [rating, setRating] = useState(5);
  const [comment, setComment] = useState('');
  const [photoFile, setPhotoFile] = useState(null);
  const [photoPreview, setPhotoPreview] = useState(null);
  const [submitting, setSubmitting] = useState(false);
  const fileInputRef = useRef(null);

  const handlePhotoSelect = (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    if (!file.type.startsWith('image/')) {
      alert('Please select a valid image file.');
      return;
    }

    if (file.size > 8 * 1024 * 1024) {
      alert('Photo file size exceeds 8MB limit.');
      return;
    }

    setPhotoFile(file);
    setPhotoPreview(URL.createObjectURL(file));
  };

  const handleRemovePhoto = () => {
    setPhotoFile(null);
    setPhotoPreview(null);
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!comment.trim()) {
      alert('Please share a few words about your experience.');
      return;
    }

    setSubmitting(true);
    try {
      let uploadedPhotoUrl = null;

      if (photoFile) {
        const data = new FormData();
        data.append('file', photoFile);
        data.append('upload_preset', 'resort_unsigned');

        const uploadRes = await fetch('https://api.cloudinary.com/v1_1/dnv6ezitm/image/upload', {
          method: 'POST',
          body: data
        });
        const uploadJson = await uploadRes.json();
        if (uploadJson.secure_url) {
          uploadedPhotoUrl = uploadJson.secure_url;
        }
      }

      const reviewRef = ref(db, `reviews/${booking.ownerUid}`);
      await push(reviewRef, {
        touristUid: booking.touristUid,
        touristName: booking.touristName,
        rating: rating,
        comment: comment.trim(),
        photoUrl: uploadedPhotoUrl,
        timestamp: serverTimestamp()
      });

      // Mark booking as reviewed
      await update(ref(db, `bookings/${booking.id}`), {
        isReviewed: true
      });

      onClose();
      alert('Thank you for your feedback! It helps others discover great places.');
    } catch (error) {
      alert('Error submitting review: ' + error.message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="modal-overlay">
      <div className="card modal-content view-transition" style={{ maxWidth: '440px', textAlign: 'center', padding: '40px 32px', borderRadius: '32px' }}>
        <div style={{ display: 'flex', justifyContent: 'flex-end', position: 'absolute', top: '24px', right: '24px' }}>
          <button onClick={onClose} className="close-btn"><X size={20} /></button>
        </div>

        <div style={{ marginBottom: '32px' }}>
           <div style={{
             width: '72px', height: '72px', background: 'rgba(255, 215, 0, 0.1)',
             borderRadius: '24px', display: 'flex', justifyContent: 'center',
             alignItems: 'center', margin: '0 auto 20px'
           }}>
              <Heart size={32} color="#FFD700" fill="#FFD700" />
           </div>
           <h3 style={{ margin: 0, fontSize: '22px', fontWeight: 800 }}>How was your stay?</h3>
           <p style={{ color: 'var(--text-muted)', fontSize: '14px', marginTop: '8px', fontWeight: 600 }}>
             Share your experience at <strong>{booking.propertyName}</strong>
           </p>
        </div>

        <form onSubmit={handleSubmit}>
          <div style={{ display: 'flex', justifyContent: 'center', gap: '10px', marginBottom: '32px' }}>
            {[1, 2, 3, 4, 5].map((star) => (
              <button
                key={star}
                type="button"
                onClick={() => setRating(star)}
                style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 0, transition: 'var(--transition)' }}
                onMouseOver={(e) => e.currentTarget.style.transform = 'scale(1.2)'}
                onMouseOut={(e) => e.currentTarget.style.transform = 'scale(1)'}
              >
                <Star
                  size={44}
                  fill={star <= rating ? '#FFD700' : 'none'}
                  color={star <= rating ? '#FFD700' : '#E5E7EB'}
                  strokeWidth={star <= rating ? 0 : 2}
                />
              </button>
            ))}
          </div>

          <div style={{ position: 'relative', marginBottom: '20px' }}>
             <MessageCircle size={18} style={{ position: 'absolute', left: '16px', top: '16px', color: 'var(--text-muted)' }} />
             <textarea
               className="input"
               placeholder="Tell us what you liked (or what could be better)..."
               style={{ height: '120px', paddingLeft: '48px', paddingTop: '14px', borderRadius: '20px', resize: 'none' }}
               value={comment}
               onChange={(e) => setComment(e.target.value)}
               maxLength="500"
             />
          </div>

          {/* Photo Attachment Section */}
          <div style={{ marginBottom: '28px', textAlign: 'left' }}>
            <input
              type="file"
              accept="image/*"
              ref={fileInputRef}
              style={{ display: 'none' }}
              onChange={handlePhotoSelect}
            />

            {photoPreview ? (
              <div style={{ position: 'relative', display: 'inline-block', borderRadius: '16px', overflow: 'hidden', border: '1px solid var(--border)' }}>
                <img src={photoPreview} alt="Review attachment" style={{ width: '120px', height: '120px', objectFit: 'cover', display: 'block' }} />
                <button
                  type="button"
                  onClick={handleRemovePhoto}
                  style={{
                    position: 'absolute', top: '6px', right: '6px',
                    background: 'rgba(239, 68, 68, 0.9)', color: 'white',
                    border: 'none', borderRadius: '50%', width: '26px', height: '26px',
                    display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer'
                  }}
                  title="Remove photo"
                >
                  <Trash2 size={14} />
                </button>
              </div>
            ) : (
              <button
                type="button"
                onClick={() => fileInputRef.current?.click()}
                style={{
                  display: 'flex', alignItems: 'center', gap: '8px',
                  background: 'var(--light-bg)', border: '1.5px dashed var(--border)',
                  borderRadius: '16px', padding: '10px 16px', color: 'var(--text-muted)',
                  fontSize: '13px', fontWeight: 700, cursor: 'pointer', transition: 'var(--transition)'
                }}
                onMouseOver={(e) => { e.currentTarget.style.borderColor = 'var(--primary)'; e.currentTarget.style.color = 'var(--primary)'; }}
                onMouseOut={(e) => { e.currentTarget.style.borderColor = 'var(--border)'; e.currentTarget.style.color = 'var(--text-muted)'; }}
              >
                <Camera size={16} />
                <span>Attach a Photo (Optional)</span>
              </button>
            )}
          </div>

          <button
            type="submit"
            className="btn btn-primary"
            style={{ width: '100%', height: '56px', fontSize: '16px' }}
            disabled={submitting}
          >
            {submitting ? <div className="loader" style={{ width: '20px', height: '20px', borderTopColor: 'white' }}></div> : 'SUBMIT REVIEW'}
          </button>

          <button
            type="button"
            onClick={onClose}
            style={{ background: 'none', border: 'none', marginTop: '20px', color: 'var(--text-muted)', fontWeight: 700, fontSize: '13px', cursor: 'pointer' }}
          >
            Maybe Later
          </button>
        </form>
      </div>

      <style>{`
        .close-btn { background: var(--light-bg); border: none; width: 36px; height: 36px; borderRadius: 50%; display: flex; align-items: center; justify-content: center; cursor: pointer; color: var(--text-main); transition: var(--transition); border: 1px solid var(--border); }
        .close-btn:hover { background: var(--surface); transform: rotate(90deg); }
        .view-transition { animation: fadeIn 0.4s ease-out; }
      `}</style>
    </div>
  );
};

export default ReviewModal;
