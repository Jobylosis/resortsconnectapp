import React, { useState, useEffect, useRef } from 'react';
import { db } from '../firebase';
import { ref, onValue, get, update } from 'firebase/database';
import { decryptText } from '../utils/encryption';
import { X } from 'lucide-react';
import Chat from './Chat';

const playChime = () => {
  try {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (!AudioContextClass) return;
    const ctx = new AudioContextClass();
    if (ctx.state === 'suspended') {
      ctx.resume().catch(() => {});
    }
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(587.33, ctx.currentTime); // D5
    osc.frequency.setValueAtTime(880, ctx.currentTime + 0.08); // A5
    gain.gain.setValueAtTime(0.12, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.35);
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + 0.35);
  } catch (e) {
    // Non-blocking if audio blocked by browser policy
  }
};

const ChatHeadBubble = ({ currentUid }) => {
  const [activeHead, setActiveHead] = useState(() => {
    try {
      const saved = sessionStorage.getItem('rc_active_chat_head');
      return saved ? JSON.parse(saved) : null;
    } catch (e) {
      return null;
    }
  });
  const [showBubble, setShowBubble] = useState(true);
  const [isHovered, setIsHovered] = useState(false);
  const [photoError, setPhotoError] = useState(false);
  const [isFloatingOpen, setIsFloatingOpen] = useState(false);

  const activeHeadRef = useRef(activeHead);
  const isFloatingOpenRef = useRef(isFloatingOpen);
  const activeChatUidRef = useRef(null);
  const knownRoomsRef = useRef({});
  const dismissedUidsRef = useRef(new Set());
  const hasInitRef = useRef(false);
  const bubbleTimerRef = useRef(null);

  useEffect(() => {
    activeHeadRef.current = activeHead;
    if (activeHead) {
      try {
        sessionStorage.setItem('rc_active_chat_head', JSON.stringify(activeHead));
      } catch (e) {}
    } else {
      try {
        sessionStorage.removeItem('rc_active_chat_head');
      } catch (e) {}
    }
  }, [activeHead]);

  useEffect(() => {
    isFloatingOpenRef.current = isFloatingOpen;
  }, [isFloatingOpen]);

  // Track currently active chat window so we don't pop up over full-page chat
  useEffect(() => {
    const handleOpened = (e) => {
      activeChatUidRef.current = e.detail?.otherUserUid || null;
      if (!isFloatingOpen && activeHead && activeHead.otherUid === activeChatUidRef.current) {
        setActiveHead(null);
      }
    };
    const handleClosed = () => {
      activeChatUidRef.current = null;
    };

    window.addEventListener('rc-chat-opened', handleOpened);
    window.addEventListener('rc-chat-closed', handleClosed);
    return () => {
      window.removeEventListener('rc-chat-opened', handleOpened);
      window.removeEventListener('rc-chat-closed', handleClosed);
    };
  }, [activeHead, isFloatingOpen]);

  // Fetch photo fallback: properties first (for resort owners), then users (for tourists)
  const fetchSenderPhoto = async (otherUid) => {
    try {
      // 1. Check properties (resort owners like Yamyam Adilina)
      const propSnap = await get(ref(db, `properties/${otherUid}`));
      if (propSnap.exists()) {
        const p = propSnap.val();
        const imgs = Array.isArray(p.imageUrls) ? p.imageUrls : (p.imageUrls ? Object.values(p.imageUrls) : []);
        if (imgs.length > 0 && imgs[0]) return imgs[0];
      }
      // 2. Check users (for tourists or users with custom avatar)
      const userSnap = await get(ref(db, `users/${otherUid}`));
      if (userSnap.exists()) {
        const u = userSnap.val();
        const photo = u.profilePicUrl || u.photoURL || u.photoUrl || u.idPhotoUrl || u.idImageUrl;
        if (photo) return photo;
      }
    } catch (e) {
      console.warn("Could not fetch sender photo", e);
    }
    return null;
  };

  const getDecryptedPreview = (lastMessage, otherUid) => {
    if (!lastMessage) return "View messages";
    const chatId = [currentUid, otherUid].sort().join('_');
    let text = decryptText(lastMessage, chatId);
    if (!text || text === '[Encrypted Message]') {
      text = lastMessage;
    }
    if (typeof text === 'string') {
      if (text.startsWith('http') && (text.includes('cloudinary') || text.match(/\.(jpeg|jpg|gif|png|webp)/i))) {
        return "📷 Sent a photo";
      }
      if (text.startsWith('[Photo]')) {
        return "📷 " + text.replace('[Photo]', '').trim();
      }
    }
    return text || "View messages";
  };

  // 1. Listen to chat_rooms for active user
  useEffect(() => {
    if (!currentUid) return;

    const chatRoomsRef = ref(db, `chat_rooms/${currentUid}`);
    const unsubscribe = onValue(chatRoomsRef, async (snapshot) => {
      const data = snapshot.val();
      if (!data) {
        if (!activeHeadRef.current || dismissedUidsRef.current.has(activeHeadRef.current?.otherUid)) {
          setActiveHead(null);
        }
        return;
      }

      const entries = Object.entries(data);

      // Sort by timestamp descending (most recent first)
      entries.sort((a, b) => {
        const tA = typeof a[1].timestamp === 'number' ? a[1].timestamp : (a[1].timestamp && typeof a[1].timestamp === 'object' ? Date.now() : 0);
        const tB = typeof b[1].timestamp === 'number' ? b[1].timestamp : (b[1].timestamp && typeof b[1].timestamp === 'object' ? Date.now() : 0);
        return tB - tA;
      });

      let newlyArrivedRoom = null;

      // Check for incoming updates compared to known state
      for (const [otherUid, val] of entries) {
        const prev = knownRoomsRef.current[otherUid];
        const newTimestamp = typeof val.timestamp === 'number'
          ? val.timestamp
          : (val.timestamp && typeof val.timestamp === 'object' ? Date.now() : 0);
        const newUnread = parseInt(val.unreadCount, 10) || 0;
        const prevUnread = prev ? (parseInt(prev.unreadCount, 10) || 0) : 0;
        const prevTime = prev ? prev.timestamp : 0;
        const prevMsg = prev ? prev.lastMessage : null;

        if (hasInitRef.current) {
          const isNewIncoming =
            (newUnread > 0 && newUnread > prevUnread) ||
            (val.lastMessage && val.lastMessage !== prevMsg) ||
            (newTimestamp > prevTime && newTimestamp > 0 && newUnread > 0);

          if (isNewIncoming && activeChatUidRef.current !== otherUid) {
            newlyArrivedRoom = [otherUid, val];
            dismissedUidsRef.current.delete(otherUid);
          }
        }

        knownRoomsRef.current[otherUid] = {
          timestamp: newTimestamp,
          unreadCount: newUnread,
          lastMessage: val.lastMessage
        };
      }

      // If a brand new message just arrived in real-time:
      if (newlyArrivedRoom) {
        const [otherUid, val] = newlyArrivedRoom;
        if (activeChatUidRef.current !== otherUid) {
          const preview = getDecryptedPreview(val.lastMessage, otherUid);
          let photo = val.otherProfilePic || null;
          if (!photo) {
            photo = await fetchSenderPhoto(otherUid);
          }

          setPhotoError(false);
          setActiveHead({
            otherUid,
            otherUserName: val.otherUserName || 'User',
            otherProfilePic: photo,
            preview,
            unreadCount: parseInt(val.unreadCount, 10) || 1
          });
          if (!isFloatingOpenRef.current) {
            setShowBubble(true);
            playChime();

            if (bubbleTimerRef.current) clearTimeout(bubbleTimerRef.current);
            bubbleTimerRef.current = setTimeout(() => {
              setShowBubble(false);
            }, 5000);
          }
        }
      } else {
        // Find most recent unread room that has not been dismissed
        const activeUnreadRoom = entries.find(([otherUid, val]) => {
          const unread = parseInt(val.unreadCount, 10) || 0;
          return unread > 0 && !dismissedUidsRef.current.has(otherUid) && activeChatUidRef.current !== otherUid;
        });

        if (activeUnreadRoom) {
          const [otherUid, val] = activeUnreadRoom;
          // Only update if not already showing this exact room with same unread count
          if (!activeHeadRef.current || activeHeadRef.current.otherUid !== otherUid || activeHeadRef.current.unreadCount !== val.unreadCount) {
            const preview = getDecryptedPreview(val.lastMessage, otherUid);
            let photo = val.otherProfilePic || null;
            if (!photo) {
              photo = await fetchSenderPhoto(otherUid);
            }

            setPhotoError(false);
            setActiveHead({
              otherUid,
              otherUserName: val.otherUserName || 'User',
              otherProfilePic: photo,
              preview,
              unreadCount: parseInt(val.unreadCount, 10) || 1
            });
            if (!isFloatingOpenRef.current) {
              setShowBubble(true);

              if (!hasInitRef.current) {
                if (bubbleTimerRef.current) clearTimeout(bubbleTimerRef.current);
                bubbleTimerRef.current = setTimeout(() => {
                  setShowBubble(false);
                }, 5000);
              }
            }
          }
        } else {
          // No unread rooms left
          // Keep activeHead if user has an active chat session that was not explicitly dismissed!
          if (activeHeadRef.current && dismissedUidsRef.current.has(activeHeadRef.current.otherUid)) {
            setActiveHead(null);
          }
        }
      }

      hasInitRef.current = true;
    });

    return () => {
      unsubscribe();
      if (bubbleTimerRef.current) clearTimeout(bubbleTimerRef.current);
    };
  }, [currentUid]);

  // 2. Dual Safeguard: Also listen to notifications for 'new_message' so bubble is 100% guaranteed to appear
  useEffect(() => {
    if (!currentUid) return;

    const notifRef = ref(db, `notifications/${currentUid}`);
    const unsubscribeNotif = onValue(notifRef, async (snapshot) => {
      const data = snapshot.val();
      if (!data) return;

      const unreadNotifs = Object.entries(data)
        .map(([id, val]) => ({ id, ...val }))
        .filter(n => n.type === 'new_message' && !n.isRead && n.senderUid && n.senderUid !== currentUid && !dismissedUidsRef.current.has(n.senderUid))
        .sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0));

      if (unreadNotifs.length > 0) {
        const latest = unreadNotifs[0];
        if (activeChatUidRef.current !== latest.senderUid) {
          dismissedUidsRef.current.delete(latest.senderUid);
          let photo = await fetchSenderPhoto(latest.senderUid);
          setPhotoError(false);
          setActiveHead({
            otherUid: latest.senderUid,
            otherUserName: latest.title ? latest.title.replace('New Message from ', '').replace('New Photo from ', '') : 'User',
            otherProfilePic: photo,
            preview: latest.message || 'Sent a message',
            unreadCount: unreadNotifs.length
          });
          if (!isFloatingOpenRef.current) {
            setShowBubble(true);
            playChime();
            if (bubbleTimerRef.current) clearTimeout(bubbleTimerRef.current);
            bubbleTimerRef.current = setTimeout(() => {
              setShowBubble(false);
            }, 5000);
          }
        }
      }
    });

    return () => unsubscribeNotif();
  }, [currentUid]);

  if (!activeHead) return null;

  // Clicking the bubble or avatar opens the floating mini-tab directly
  const handleOpenFloatingChat = async () => {
    setIsFloatingOpen(true);
    setShowBubble(false);
    // Remove red notification badge immediately on view
    setActiveHead(prev => prev ? { ...prev, unreadCount: 0 } : null);

    // Mark notifications as read for this sender in Firebase
    if (activeHeadRef.current?.otherUid) {
      try {
        const otherUid = activeHeadRef.current.otherUid;
        const snap = await get(ref(db, `notifications/${currentUid}`));
        if (snap.exists()) {
          const updates = {};
          Object.entries(snap.val()).forEach(([notifId, n]) => {
            if (n.type === 'new_message' && n.senderUid === otherUid && !n.isRead) {
              updates[`notifications/${currentUid}/${notifId}/isRead`] = true;
            }
          });
          if (Object.keys(updates).length > 0) {
            await update(ref(db), updates);
          }
        }
      } catch (e) {
        console.warn("Could not mark message notifications as read:", e);
      }
    }
  };

  const handleMinimize = () => {
    setIsFloatingOpen(false);
    // When minimized, ensure unread count is 0 because the chat was already viewed!
    setActiveHead(prev => prev ? { ...prev, unreadCount: 0 } : null);
    setShowBubble(true); // Show sender's name for 5 seconds after minimize
    if (bubbleTimerRef.current) clearTimeout(bubbleTimerRef.current);
    bubbleTimerRef.current = setTimeout(() => {
      setShowBubble(false);
    }, 5000);
  };

  const handleClose = () => {
    setIsFloatingOpen(false);
    if (activeHeadRef.current) {
      dismissedUidsRef.current.add(activeHeadRef.current.otherUid);
    }
    setActiveHead(null);
    setShowBubble(false);
    try {
      sessionStorage.removeItem('rc_active_chat_head');
    } catch (e) {}
  };

  const handleDismissBubble = (e) => {
    e.stopPropagation();
    if (activeHeadRef.current) {
      dismissedUidsRef.current.add(activeHeadRef.current.otherUid);
    }
    setActiveHead(null);
    setShowBubble(false);
    try {
      sessionStorage.removeItem('rc_active_chat_head');
    } catch (e) {}
  };

  const initials = (activeHead.otherUserName || 'U')
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map(p => p[0].toUpperCase())
    .join('');

  return (
    <>
      {/* Floating Chat Tab - only rendered when user opens it so background messages aren't prematurely marked read */}
      {isFloatingOpen && (
        <Chat
          currentUid={currentUid}
          otherUserUid={activeHead.otherUid}
          otherUserName={activeHead.otherUserName}
          isFloating={true}
          onMinimize={handleMinimize}
          onClose={handleClose}
        />
      )}

      {/* Floating circular chat head bubble - shown when minimized or incoming */}
      {!isFloatingOpen && (
        <div
          className="fb-chat-head-container"
          onMouseEnter={() => setIsHovered(true)}
          onMouseLeave={() => setIsHovered(false)}
          title="Click to open chat"
        >
          {/* Speech bubble popup pointing to avatar */}
          {(showBubble || isHovered) && (
            <div
              className="fb-chat-head-bubble"
              onClick={handleOpenFloatingChat}
              style={{
                padding: activeHead.unreadCount > 0 ? '10px 16px' : '7px 14px',
                borderRadius: '12px'
              }}
            >
              <div
                className="fb-chat-head-name"
                style={{
                  fontSize: activeHead.unreadCount > 0 ? '14px' : '13px',
                  fontWeight: 700
                }}
              >
                {activeHead.otherUserName}
              </div>

              {/* Only show message preview on fresh unread incoming alert; when viewed/minimized, show only the sender's name! */}
              {showBubble && activeHead.unreadCount > 0 && activeHead.preview && (
                <div className="fb-chat-head-preview" style={{ marginTop: '2px' }}>
                  {activeHead.preview}
                </div>
              )}
            </div>
          )}

          {/* Floating circular avatar with close button */}
          <div
            className="fb-chat-head-avatar-wrapper"
            onClick={handleOpenFloatingChat}
          >
            {activeHead.otherProfilePic && !photoError ? (
              <img
                src={activeHead.otherProfilePic}
                alt={activeHead.otherUserName}
                className="fb-chat-head-avatar-img"
                onError={() => setPhotoError(true)}
              />
            ) : (
              <div className="fb-chat-head-fallback">
                {initials}
              </div>
            )}

            {/* Small Close Button on Avatar */}
            <button
              className="fb-chat-head-close-btn"
              onClick={handleDismissBubble}
              title="Close chat bubble"
              aria-label="Close chat bubble"
            >
              <X size={13} strokeWidth={2.8} />
            </button>

            {/* Unread badge: only shown if there are unread messages */}
            {activeHead.unreadCount > 0 && (
              <span className="fb-chat-head-badge">
                {activeHead.unreadCount > 9 ? '9+' : activeHead.unreadCount}
              </span>
            )}
          </div>
        </div>
      )}
    </>
  );
};

export default ChatHeadBubble;
