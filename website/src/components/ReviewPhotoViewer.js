import React, { useState, useEffect, useCallback } from 'react';
import { X, ChevronLeft, ChevronRight, Star, Users } from 'lucide-react';

/**
 * Fullscreen in-page lightbox modal for reviewing guest photos.
 * Supports single or multiple photos, arrow key navigation, backdrop click, Escape key, and scroll-lock.
 */
export const ReviewPhotoViewer = ({ photos = [], initialIndex = 0, onClose }) => {
  const [currentIndex, setCurrentIndex] = useState(initialIndex);

  const photoList = Array.isArray(photos) ? photos.filter(Boolean) : (photos ? [photos] : []);
  const total = photoList.length;

  const handlePrev = useCallback(() => {
    setCurrentIndex((prev) => (prev > 0 ? prev - 1 : total - 1));
  }, [total]);

  const handleNext = useCallback(() => {
    setCurrentIndex((prev) => (prev < total - 1 ? prev + 1 : 0));
  }, [total]);

  useEffect(() => {
    // Lock background scrolling
    const originalOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';

    // Push dummy history entry so browser back button closes lightbox instead of leaving page
    const stateObj = { reviewLightbox: true };
    window.history.pushState(stateObj, '');

    const handlePopState = () => {
      onClose();
    };

    const handleKeyDown = (e) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        onClose();
      } else if (e.key === 'ArrowLeft' && total > 1) {
        e.preventDefault();
        handlePrev();
      } else if (e.key === 'ArrowRight' && total > 1) {
        e.preventDefault();
        handleNext();
      }
    };

    window.addEventListener('popstate', handlePopState);
    window.addEventListener('keydown', handleKeyDown);

    return () => {
      document.body.style.overflow = originalOverflow;
      window.removeEventListener('popstate', handlePopState);
      window.removeEventListener('keydown', handleKeyDown);
      // Clean up history state if closed via button / backdrop rather than back button
      if (window.history.state && window.history.state.reviewLightbox) {
        window.history.back();
      }
    };
  }, [onClose, total, handlePrev, handleNext]);

  if (total === 0) return null;

  const currentPhoto = photoList[currentIndex];

  return (
    <div
      className="modal-overlay"
      onClick={onClose}
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 99999,
        background: 'rgba(0, 0, 0, 0.88)',
        backdropFilter: 'blur(8px)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '16px',
        boxSizing: 'border-box',
        animation: 'fadeIn 0.2s ease-out'
      }}
    >
      {/* Top Bar with Counter and Close Button */}
      <div
        style={{
          position: 'absolute',
          top: '20px',
          left: '24px',
          right: '24px',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          zIndex: 100000,
          pointerEvents: 'none'
        }}
      >
        <span
          style={{
            color: 'white',
            background: 'rgba(0, 0, 0, 0.5)',
            padding: '6px 14px',
            borderRadius: '20px',
            fontSize: '13px',
            fontWeight: 700,
            letterSpacing: '0.5px'
          }}
        >
          {total > 1 ? `${currentIndex + 1} / ${total}` : 'Photo Preview'}
        </span>

        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation();
            onClose();
          }}
          title="Close (Esc)"
          aria-label="Close"
          style={{
            pointerEvents: 'auto',
            background: 'rgba(255, 255, 255, 0.15)',
            border: '1px solid rgba(255, 255, 255, 0.25)',
            color: 'white',
            width: '40px',
            height: '40px',
            borderRadius: '50%',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            cursor: 'pointer',
            transition: 'var(--transition)'
          }}
          onMouseOver={(e) => { e.currentTarget.style.background = 'rgba(255, 255, 255, 0.3)'; }}
          onMouseOut={(e) => { e.currentTarget.style.background = 'rgba(255, 255, 255, 0.15)'; }}
        >
          <X size={22} />
        </button>
      </div>

      {/* Prev Button */}
      {total > 1 && (
        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation();
            handlePrev();
          }}
          title="Previous (Left Arrow)"
          aria-label="Previous image"
          style={{
            position: 'absolute',
            left: '20px',
            zIndex: 100000,
            background: 'rgba(255, 255, 255, 0.15)',
            border: '1px solid rgba(255, 255, 255, 0.25)',
            color: 'white',
            width: '48px',
            height: '48px',
            borderRadius: '50%',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            cursor: 'pointer',
            transition: 'var(--transition)'
          }}
          onMouseOver={(e) => { e.currentTarget.style.background = 'rgba(255, 255, 255, 0.3)'; }}
          onMouseOut={(e) => { e.currentTarget.style.background = 'rgba(255, 255, 255, 0.15)'; }}
        >
          <ChevronLeft size={28} />
        </button>
      )}

      {/* Main Image Container */}
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          maxWidth: '92vw',
          maxHeight: '84vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          userSelect: 'none'
        }}
      >
        <img
          src={currentPhoto}
          alt={`Review attachment ${currentIndex + 1}`}
          style={{
            maxWidth: '100%',
            maxHeight: '84vh',
            objectFit: 'contain',
            borderRadius: '12px',
            boxShadow: '0 20px 50px rgba(0, 0, 0, 0.5)'
          }}
        />
      </div>

      {/* Next Button */}
      {total > 1 && (
        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation();
            handleNext();
          }}
          title="Next (Right Arrow)"
          aria-label="Next image"
          style={{
            position: 'absolute',
            right: '20px',
            zIndex: 100000,
            background: 'rgba(255, 255, 255, 0.15)',
            border: '1px solid rgba(255, 255, 255, 0.25)',
            color: 'white',
            width: '48px',
            height: '48px',
            borderRadius: '50%',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            cursor: 'pointer',
            transition: 'var(--transition)'
          }}
          onMouseOver={(e) => { e.currentTarget.style.background = 'rgba(255, 255, 255, 0.3)'; }}
          onMouseOut={(e) => { e.currentTarget.style.background = 'rgba(255, 255, 255, 0.15)'; }}
        >
          <ChevronRight size={28} />
        </button>
      )}
    </div>
  );
};

/**
 * Compact Shopee-style Guest Review Item.
 * Only takes as much vertical space as its own content.
 * Thumbnails are small square previews (76x76) that open the in-page viewer.
 */
export const CompactReviewCard = ({
  review,
  onPhotoClick,
  isUnread = false,
  onCardClick,
  replyActions = null,
  replyInput = null,
  showDate = true,
  cardStyle = {}
}) => {
  const r = review;

  // Extract photos (supports single photoUrl or photoUrls array)
  const photos = Array.isArray(r.photoUrls)
    ? r.photoUrls.filter(Boolean)
    : (r.photoUrl ? [r.photoUrl] : []);

  const visibleThumbnails = photos.slice(0, 4);
  const remainingCount = photos.length - visibleThumbnails.length;

  const dateStr = r.timestamp || r.createdAt
    ? new Date(r.timestamp || r.createdAt).toLocaleDateString(undefined, {
        month: 'short',
        day: 'numeric',
        year: 'numeric'
      })
    : null;

  return (
    <div
      className="card compact-review-card"
      onClick={onCardClick}
      style={{
        padding: '16px 18px',
        margin: 0,
        marginBottom: '14px',
        display: 'flex',
        flexDirection: 'column',
        gap: '10px',
        background: 'var(--surface)',
        borderRadius: '16px',
        border: isUnread ? '1.5px solid #F59E0B' : '1px solid var(--border)',
        boxShadow: isUnread ? '0 4px 14px rgba(245, 158, 11, 0.12)' : 'var(--shadow)',
        boxSizing: 'border-box',
        breakInside: 'avoid',
        pageBreakInside: 'avoid',
        position: 'relative',
        ...cardStyle
      }}
    >
      {isUnread && (
        <div
          style={{
            position: 'absolute',
            top: '12px',
            right: '12px',
            background: '#F59E0B',
            color: 'white',
            fontSize: '10px',
            fontWeight: 800,
            padding: '2px 7px',
            borderRadius: '8px',
            letterSpacing: '0.3px',
            textTransform: 'uppercase'
          }}
        >
          New
        </div>
      )}

      {/* Header Row: Avatar + Name + Stars + Date */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: '12px',
          paddingRight: isUnread ? '45px' : '0'
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px', minWidth: 0, flex: 1 }}>
          <div
            style={{
              width: '32px',
              height: '32px',
              borderRadius: '50%',
              background: 'rgba(29, 211, 176, 0.12)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: 'var(--secondary)',
              flexShrink: 0
            }}
          >
            <Users size={16} />
          </div>
          <div style={{ minWidth: 0, flex: 1 }}>
            <h4
              style={{
                margin: 0,
                fontSize: '14px',
                fontWeight: 800,
                color: 'var(--text-main)',
                whiteSpace: 'nowrap',
                overflow: 'hidden',
                textOverflow: 'ellipsis'
              }}
            >
              {r.touristName || r.userName || 'Guest'}
            </h4>
            {showDate && dateStr && (
              <span style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 500 }}>
                {dateStr}
              </span>
            )}
          </div>
        </div>

        {/* Stars */}
        <div style={{ display: 'flex', gap: '2px', flexShrink: 0, alignItems: 'center' }}>
          {[...Array(5)].map((_, idx) => (
            <Star
              key={idx}
              size={13}
              fill={idx < (r.rating || 0) ? '#F59E0B' : 'none'}
              color={idx < (r.rating || 0) ? '#F59E0B' : '#CBD5E1'}
            />
          ))}
        </div>
      </div>

      {/* Review Text */}
      {r.comment && (
        <p
          style={{
            margin: 0,
            fontSize: '13.5px',
            color: 'var(--text-main)',
            lineHeight: 1.5,
            wordBreak: 'break-word',
            fontStyle: 'normal'
          }}
        >
          {r.comment}
        </p>
      )}

      {/* Shopee-style Thumbnails Row */}
      {photos.length > 0 && (
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            flexWrap: 'wrap',
            marginTop: '2px'
          }}
        >
          {visibleThumbnails.map((url, idx) => {
            const isLast = idx === visibleThumbnails.length - 1 && remainingCount > 0;
            return (
              <div
                key={idx}
                onClick={(e) => {
                  e.stopPropagation();
                  if (onPhotoClick) onPhotoClick(photos, idx);
                }}
                style={{
                  width: '76px',
                  height: '76px',
                  borderRadius: '10px',
                  overflow: 'hidden',
                  position: 'relative',
                  cursor: 'pointer',
                  border: '1px solid var(--border)',
                  background: 'var(--light-bg)',
                  flexShrink: 0,
                  transition: 'transform 0.15s ease, box-shadow 0.15s ease'
                }}
                onMouseOver={(e) => {
                  e.currentTarget.style.transform = 'scale(1.04)';
                  e.currentTarget.style.boxShadow = '0 4px 12px rgba(0,0,0,0.15)';
                }}
                onMouseOut={(e) => {
                  e.currentTarget.style.transform = 'scale(1)';
                  e.currentTarget.style.boxShadow = 'none';
                }}
                title="Click to view photo"
              >
                <img
                  src={url}
                  alt={`Review thumbnail ${idx + 1}`}
                  style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }}
                />
                {isLast && (
                  <div
                    style={{
                      position: 'absolute',
                      inset: 0,
                      background: 'rgba(0,0,0,0.5)',
                      color: 'white',
                      fontWeight: 800,
                      fontSize: '14px',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center'
                    }}
                  >
                    +{remainingCount}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* Response from Host (Compact) */}
      {r.ownerReply && (
        <div
          style={{
            marginTop: '4px',
            padding: '10px 12px',
            background: 'rgba(29, 211, 176, 0.08)',
            borderRadius: '12px',
            borderLeft: '3px solid var(--primary)',
            textAlign: 'left'
          }}
        >
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              marginBottom: '3px'
            }}
          >
            <span
              style={{
                fontSize: '11px',
                fontWeight: 800,
                color: 'var(--primary)',
                display: 'flex',
                alignItems: 'center',
                gap: '4px'
              }}
            >
              💬 Response from Host
            </span>
            {replyActions}
          </div>
          <p
            style={{
              margin: 0,
              fontSize: '12.5px',
              color: 'var(--text-main)',
              lineHeight: 1.4,
              wordBreak: 'break-word'
            }}
          >
            {r.ownerReply}
          </p>
          {r.ownerReplyTimestamp && (
            <div style={{ marginTop: '4px', fontSize: '10px', color: 'var(--text-muted)' }}>
              {new Date(r.ownerReplyTimestamp).toLocaleDateString(undefined, {
                month: 'short',
                day: 'numeric',
                year: 'numeric'
              })}
            </div>
          )}
        </div>
      )}

      {/* Inline Reply Input (For Owner Dashboard) */}
      {replyInput}
    </div>
  );
};
