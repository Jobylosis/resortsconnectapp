import React, { useState, useEffect, useRef } from 'react';
import { db } from '../firebase';
import { ref, onValue, push, set, update, serverTimestamp, get, increment, query, orderByChild, remove } from 'firebase/database';
import { Send, ArrowLeft, User, MoreVertical, ShieldCheck, CheckCheck } from 'lucide-react';
import { encryptText, decryptText } from '../utils/encryption';
import { format, isToday, isThisYear } from 'date-fns';

const Chat = ({ currentUid, otherUserUid, otherUserName, onBack }) => {
  const [messages, setMessages] = useState([]);
  const [newMessage, setNewMessage] = useState('');
  const [chatId, setChatId] = useState('');
  const [myPhoto, setMyPhoto] = useState(null);
  const [otherPhoto, setOtherPhoto] = useState(null);
  const [messageLimit, setMessageLimit] = useState(20);
  const [showMenu, setShowMenu] = useState(false);
  const [showReportModal, setShowReportModal] = useState(false);
  const [reportReason, setReportReason] = useState('');
  const [reportError, setReportError] = useState('');
  const [showBlockConfirm, setShowBlockConfirm] = useState(false);
  const [myRole, setMyRole] = useState(null);
  const [otherRole, setOtherRole] = useState(null);
  const [showClearConfirm, setShowClearConfirm] = useState(false);
  const [isBlocked, setIsBlocked] = useState(false); // I blocked them
  const [isBlockedByOther, setIsBlockedByOther] = useState(false); // they blocked me
  const messagesEndRef = useRef(null);

  useEffect(() => {
    // Fetch photos
    const fetchPhotos = async () => {
      try {
        // Get my photo
        const myUserSnap = await get(ref(db, `users/${currentUid}`));
        if (myUserSnap.exists()) {
          const userData = myUserSnap.val();
          setMyRole(userData.role);
          if (userData.profilePicUrl) {
            setMyPhoto(userData.profilePicUrl);
          } else if (userData.role === 'Owner') {
            const propSnap = await get(ref(db, `properties/${currentUid}`));
            if (propSnap.exists()) {
              const propData = propSnap.val();
              const imgs = Array.isArray(propData.imageUrls) ? propData.imageUrls : (propData.imageUrls ? Object.values(propData.imageUrls) : []);
              if (imgs.length > 0) setMyPhoto(imgs[0]);
            }
          }
        }
      } catch (e) { console.warn("My profile read failed", e); }

      try {
        // Get other user's photo
        const otherPropSnap = await get(ref(db, `properties/${otherUserUid}`));
        if (otherPropSnap.exists()) {
          const propData = otherPropSnap.val();
          const imgs = Array.isArray(propData.imageUrls) ? propData.imageUrls : (propData.imageUrls ? Object.values(propData.imageUrls) : []);
          if (imgs.length > 0) setOtherPhoto(imgs[0]);
          setOtherRole('Owner');
        } else {
          const otherUserSnap = await get(ref(db, `users/${otherUserUid}`));
          if (otherUserSnap.exists()) {
            setOtherRole(otherUserSnap.val().role);
            if (otherUserSnap.val().profilePicUrl) {
              setOtherPhoto(otherUserSnap.val().profilePicUrl);
            }
          }
        }
      } catch (e) { console.warn("Other profile read failed", e); }
    };

    fetchPhotos();

    const ids = [currentUid, otherUserUid].sort();
    const id = ids.join('_');
    setChatId(id);

    const chatRef = ref(db, `chats/${id}/messages`);
    const chatQuery = query(chatRef, orderByChild('timestamp')); // Cannot limitToLast here efficiently while maintaining real-time on top.
    // We'll limit locally for better UX.

    // Reset unread count for this room when opening
    try {
      update(ref(db, `chat_rooms/${currentUid}/${otherUserUid}`), { unreadCount: 0 });
    } catch (e) { console.warn("Unread reset failed", e); }

    const unsubscribe = onValue(chatQuery, (snapshot) => {
      const data = snapshot.val();
      if (data) {
        const list = Object.entries(data).map(([msgId, val]) => ({
          id: msgId,
          ...val,
          decryptedText: decryptText(val.text, id)
        })).sort((a, b) => (a.timestamp || 0) - (b.timestamp || 0));
        setMessages(list);
      } else {
        setMessages([]);
      }
    });

    // Check if I blocked them
    const myBlockRef = ref(db, `blocks/${currentUid}/${otherUserUid}`);
    const unsubscribeMyBlock = onValue(myBlockRef, (snap) => {
      setIsBlocked(snap.exists());
    });

    // Check if they blocked me
    const theirBlockRef = ref(db, `blocks/${otherUserUid}/${currentUid}`);
    const unsubscribeTheirBlock = onValue(theirBlockRef, (snap) => {
      setIsBlockedByOther(snap.exists());
    });

    return () => {
      unsubscribe();
      unsubscribeMyBlock();
      unsubscribeTheirBlock();
    };
  }, [currentUid, otherUserUid, messageLimit]);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const handleEmojiFilter = (value) => {
    const emojiRegex = /[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]/gu;
    return value.replace(emojiRegex, '');
  };

  const sendMessage = async (e) => {
    e.preventDefault();
    if (!newMessage.trim()) return;

    try {
      const encrypted = encryptText(newMessage.trim(), chatId);
      const messagesRef = ref(db, `chats/${chatId}/messages`);

      await push(messagesRef, {
        senderUid: currentUid,
        text: encrypted,
        timestamp: serverTimestamp(),
        seen: false,
      });

      // Update SENDER'S room
      updateChatRoom(currentUid, otherUserUid, otherUserName, encrypted, otherPhoto, false);

      // Fetch my name for RECIPIENT'S room
      let myName = "User";
      try {
        const myProfileSnap = await get(ref(db, `users/${currentUid}`));
        if (myProfileSnap.exists()) {
          const val = myProfileSnap.val();
          myName = `${val.firstName || ''} ${val.lastName || ''}`.trim() || "User";
        } else {
          // Check if I'm an owner
          const myPropSnap = await get(ref(db, `properties/${currentUid}`));
          if (myPropSnap.exists()) {
            myName = myPropSnap.val().name || "Resort";
          }
        }
      } catch (e) {
        console.warn("Could not fetch sender profile for recipient metadata", e);
      }

      // Update RECIPIENT'S room
      updateChatRoom(otherUserUid, currentUid, myName, encrypted, myPhoto, true);

      setNewMessage('');
    } catch (error) {
      console.error("Message send failed", error);
      alert("Failed to send message. Please check your connection.");
    }
  };

  const updateChatRoom = async (userUid, otherUid, name, lastMsg, photoUrl, incrementUnread) => {
    try {
      const roomRef = ref(db, `chat_rooms/${userUid}/${otherUid}`);

      const data = {
        otherUserName: name,
        lastMessage: lastMsg,
        timestamp: serverTimestamp()
      };
      if (photoUrl) data.otherProfilePic = photoUrl;
      if (incrementUnread) {
        data.unreadCount = increment(1);
      }

      await update(roomRef, data);
    } catch (e) {
      console.warn(`Could not update chat room metadata for ${userUid}`, e);
    }
  };

  return (
    <div className="chat-interface view-transition" style={{
      display: 'flex',
      flexDirection: 'column',
      height: 'calc(100vh - 140px)',
      background: 'var(--surface)',
      borderRadius: '32px',
      overflow: 'hidden',
      boxShadow: 'var(--shadow)',
      border: '1px solid var(--border)'
    }}>
      {/* Chat Header */}
      <div style={{
        padding: '16px 24px',
        borderBottom: '1px solid var(--border)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        background: 'var(--surface)'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
          {onBack && (
            <button onClick={onBack} className="back-btn-chat">
              <ArrowLeft size={20} />
            </button>
          )}
          <div style={{ position: 'relative' }}>
            <div style={{
              width: '48px', height: '48px', borderRadius: '16px',
              background: 'var(--light-bg)',
              overflow: 'hidden',
              display: 'flex', justifyContent: 'center', alignItems: 'center',
              color: 'var(--text-muted)', border: '2px solid var(--border)', boxShadow: '0 4px 12px rgba(0,0,0,0.05)'
            }}>
              {otherPhoto ? (
                <img src={otherPhoto} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
              ) : (
                <User size={24} />
              )}
            </div>
            <div style={{
              position: 'absolute', bottom: '-2px', right: '-2px',
              width: '14px', height: '14px', background: '#10B981',
              borderRadius: '50%', border: '2px solid white'
            }}></div>
          </div>
          <div>
            <h4 style={{ margin: 0, fontSize: '16px', fontWeight: 800, color: 'var(--text-main)', display: 'flex', alignItems: 'center', gap: '6px' }}>
              {otherUserName}
              <ShieldCheck size={14} color="var(--secondary)" />
            </h4>
            <span style={{ fontSize: '12px', color: 'var(--secondary)', fontWeight: 700 }}>Online</span>
          </div>
        </div>
        <div style={{ position: 'relative' }}>
          <button className="icon-btn-more" onClick={() => setShowMenu(!showMenu)}>
            <MoreVertical size={20} color="var(--text-muted)" />
          </button>
          {showMenu && (
            <div style={{
              position: 'absolute',
              top: '100%',
              right: 0,
              marginTop: '8px',
              background: 'var(--surface)',
              border: '1px solid var(--border)',
              borderRadius: '16px',
              boxShadow: 'var(--shadow)',
              padding: '8px',
              zIndex: 100,
              minWidth: '160px',
              animation: 'fadeIn 0.2s ease-out'
            }}>
              {!(myRole === 'Tourist' && otherRole === 'Owner') && (
                <button className="chat-dropdown-item" onClick={() => { setShowReportModal(true); setShowMenu(false); }}>Report User</button>
              )}
              {myRole !== 'Tourist' && (
                isBlocked ? (
                  <button className="chat-dropdown-item" style={{ color: '#16A34A' }} onClick={async () => {
                    setShowMenu(false);
                    try {
                      await set(ref(db, `blocks/${currentUid}/${otherUserUid}`), null);
                      alert(`${otherUserName} has been unblocked.`);
                    } catch (e) { alert('Failed to unblock. Please try again.'); }
                  }}>Unblock User</button>
                ) : (
                  <button className="chat-dropdown-item" onClick={() => { setShowBlockConfirm(true); setShowMenu(false); }}>Block User</button>
                )
              )}
              <div style={{ height: '1px', background: 'var(--border)', margin: '4px 0' }}></div>
              <button className="chat-dropdown-item" style={{ color: 'var(--primary)' }} onClick={() => { setShowClearConfirm(true); setShowMenu(false); }}>
                Clear Chat
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Messages Area */}
      <div style={{
        flex: 1,
        overflowY: 'auto',
        padding: '24px',
        display: 'flex',
        flexDirection: 'column',
        gap: '16px',
        background: 'var(--light-bg)'
      }}>
        {messages.length > messageLimit && (
          <button
            className="btn btn-secondary"
            style={{ fontSize: '11px', padding: '8px', margin: '0 auto 20px', borderRadius: '12px' }}
            onClick={() => setMessageLimit(prev => prev + 20)}
          >
            Load Older Messages
          </button>
        )}

        {messages.length === 0 && (
           <div style={{ textAlign: 'center', margin: 'auto', opacity: 0.5 }}>
              <div style={{ background: 'var(--surface)', padding: '20px', borderRadius: '24px', display: 'inline-block', boxShadow: '0 4px 20px rgba(0,0,0,0.02)', border: '1px solid var(--border)' }}>
                 <p style={{ margin: 0, fontSize: '13px', fontWeight: 600 }}>No messages yet. Say hello!</p>
              </div>
           </div>
        )}

        {messages.slice(-messageLimit).map((msg, index) => {
          const isMe = msg.senderUid === currentUid;
          const showTime = true;

          const formatMessageTime = (ts) => {
            if (!ts) return '';
            const d = new Date(ts);
            if (isToday(d)) return format(d, 'p');
            if (isThisYear(d)) return format(d, 'MMM d, p');
            return format(d, 'MMM d, yyyy, p');
          };

          // Update seen status
          if (!isMe && msg.seen === false) {
             update(ref(db, `chats/${chatId}/messages/${msg.id}`), { seen: true });
          }

          return (
            <div key={msg.id} style={{
              alignSelf: isMe ? 'flex-end' : 'flex-start',
              maxWidth: '85%',
              display: 'flex',
              gap: '12px',
              flexDirection: isMe ? 'row-reverse' : 'row',
              alignItems: 'flex-end'
            }}>
              {/* Avatar next to message */}
              <div style={{
                width: '32px', height: '32px', borderRadius: '10px',
                background: 'var(--light-bg)', overflow: 'hidden',
                flexShrink: 0, display: 'flex', justifyContent: 'center', alignItems: 'center',
                boxShadow: '0 2px 5px rgba(0,0,0,0.05)', marginBottom: showTime ? '18px' : '0'
              }}>
                {(isMe ? myPhoto : otherPhoto) ? (
                  <img src={isMe ? myPhoto : otherPhoto} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                ) : (
                  <User size={16} color="#9CA3AF" />
                )}
              </div>

              <div style={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: isMe ? 'flex-end' : 'flex-start'
              }}>
                <div style={{
                  padding: '12px 18px',
                  borderRadius: isMe ? '20px 20px 4px 20px' : '20px 20px 20px 4px',
                  background: isMe ? 'linear-gradient(135deg, var(--primary), #FF5F6D)' : 'var(--surface)',
                  color: isMe ? 'white' : 'var(--text-main)',
                  fontSize: '15px',
                  fontWeight: 500,
                  boxShadow: isMe ? '0 4px 15px rgba(251, 54, 64, 0.2)' : '0 2px 8px rgba(0,0,0,0.03)',
                  lineHeight: '1.5',
                  border: isMe ? 'none' : '1px solid var(--border)'
                }}>
                  {msg.decryptedText}
                </div>
                {showTime && msg.timestamp && (
                  <div style={{ display: 'flex', alignItems: 'center', gap: '4px', marginTop: '4px' }}>
                    <span style={{ fontSize: '10px', color: 'var(--text-muted)', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                      {formatMessageTime(msg.timestamp)}
                    </span>
                    {isMe && (
                      <CheckCheck size={14} color={msg.seen ? '#3B82F6' : '#9CA3AF'} />
                    )}
                  </div>
                )}
              </div>
            </div>
          );
        })}
        <div ref={messagesEndRef} />
      </div>

      {/* Block Status Banners */}
      {isBlocked && (
        <div style={{ padding: '10px 24px', background: 'rgba(245,158,11,0.12)', borderTop: '1px solid rgba(245,158,11,0.25)', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '12px' }}>
          <span style={{ fontSize: '13px', fontWeight: 700, color: '#B45309' }}>🚫 You have blocked {otherUserName}. You cannot send messages.</span>
          <button className="btn" style={{ padding: '6px 14px', fontSize: '12px', background: 'white', color: '#B45309', border: '1px solid #F59E0B', borderRadius: '10px', fontWeight: 700 }}
            onClick={async () => {
              try {
                await set(ref(db, `blocks/${currentUid}/${otherUserUid}`), null);
              } catch (e) { alert('Failed to unblock. Please try again.'); }
            }}>Unblock</button>
        </div>
      )}
      {isBlockedByOther && !isBlocked && (
        <div style={{ padding: '10px 24px', background: 'rgba(239,68,68,0.1)', borderTop: '1px solid rgba(239,68,68,0.2)' }}>
          <span style={{ fontSize: '13px', fontWeight: 700, color: '#DC2626' }}>⛔ You cannot send messages to this user.</span>
        </div>
      )}

      {/* Input Area */}
      <div style={{ padding: '20px 24px', background: 'var(--surface)', borderTop: '1px solid var(--border)' }}>
        <form onSubmit={sendMessage} style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
          <div style={{ flex: 1, position: 'relative' }}>
            <input
              type="text"
              placeholder={isBlocked || isBlockedByOther ? 'Messaging is unavailable.' : 'Type your message...'}
              className="chat-input"
              value={newMessage}
              disabled={isBlocked || isBlockedByOther}
              onChange={(e) => setNewMessage(handleEmojiFilter(e.target.value))}
              style={isBlocked || isBlockedByOther ? { opacity: 0.5, cursor: 'not-allowed' } : {}}
            />
          </div>
          <button
            type="submit"
            disabled={!newMessage.trim() || isBlocked || isBlockedByOther}
            style={{
              width: '52px', height: '52px', borderRadius: '18px', border: '1px solid var(--border)',
              background: (newMessage.trim() && !isBlocked && !isBlockedByOther) ? 'var(--secondary)' : 'var(--light-bg)',
              color: (newMessage.trim() && !isBlocked && !isBlockedByOther) ? '#002D24' : 'var(--text-muted)',
              display: 'flex', justifyContent: 'center', alignItems: 'center',
              cursor: (newMessage.trim() && !isBlocked && !isBlockedByOther) ? 'pointer' : 'default',
              transition: 'var(--transition)',
              boxShadow: (newMessage.trim() && !isBlocked && !isBlockedByOther) ? '0 8px 15px rgba(29, 211, 176, 0.3)' : 'none'
            }}
          >
            <Send size={22} style={{ transform: (newMessage.trim() && !isBlocked && !isBlockedByOther) ? 'translateX(2px) translateY(-1px)' : 'none' }} />
          </button>
        </form>
      </div>

      <style>{`
        .back-btn-chat { background: var(--light-bg); border: 1px solid var(--border); width: 36px; height: 36px; border-radius: 12px; display: flex; align-items: center; justify-content: center; cursor: pointer; color: var(--text-main); transition: var(--transition); }
        .back-btn-chat:hover { background: var(--surface); transform: translateX(-3px); }
        .icon-btn-more { background: transparent; border: none; width: 36px; height: 36px; border-radius: 12px; display: flex; align-items: center; justify-content: center; cursor: pointer; }
        .icon-btn-more:hover { background: var(--light-bg); }
        .chat-input { width: 100%; padding: 14px 20px; border-radius: 18px; border: 2px solid var(--border); background: var(--light-bg); color: var(--text-main); font-family: inherit; font-size: 15px; font-weight: 500; outline: none; transition: var(--transition); }
        .chat-input:focus { border-color: var(--secondary); background: var(--surface); box-shadow: 0 0 0 4px rgba(29, 211, 176, 0.05); }
        .view-transition { animation: fadeIn 0.4s ease-out; }
        .chat-dropdown-item { width: 100%; text-align: left; padding: 10px 12px; background: transparent; border: none; font-size: 13px; font-weight: 600; color: var(--text-main); border-radius: 8px; cursor: pointer; transition: var(--transition); }
        .chat-dropdown-item:hover { background: var(--light-bg); }
      `}</style>

      {showReportModal && (
        <div className="modal-overlay" style={{ zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div className="modal-content" style={{ background: 'var(--surface)', borderRadius: '24px', maxWidth: '400px', width: '90%', textAlign: 'center', padding: '32px 24px' }}>
            <div style={{ background: 'var(--primary-soft)', width: '64px', height: '64px', borderRadius: '50%', display: 'flex', justifyContent: 'center', alignItems: 'center', margin: '0 auto 16px' }}>
              <ShieldCheck size={32} color="var(--primary)" />
            </div>
            <h3 style={{ margin: '0 0 8px 0', fontSize: '20px', fontWeight: 800 }}>Report User</h3>
            <p style={{ color: 'var(--text-muted)', fontSize: '14px', marginBottom: '20px' }}>Please describe the issue with this user. This report will be sent to the super admin for review. <strong style={{color: '#EF4444'}}>Warning: False reporting may result in a warning or ban for your account.</strong></p>
            {reportError && (
              <div style={{ background: 'var(--logout-bg)', color: 'var(--primary)', padding: '10px', borderRadius: '12px', fontSize: '13px', fontWeight: 700, marginBottom: '16px', border: '1px solid var(--primary-soft)' }}>
                {reportError}
              </div>
            )}
            <textarea
              className="input"
              rows={4}
              placeholder="Reason for reporting..."
              value={reportReason}
              onChange={(e) => {
                setReportReason(e.target.value);
                if (reportError) setReportError('');
              }}
              style={{ width: '100%', marginBottom: '24px', resize: 'none' }}
            />
            <div style={{ display: 'flex', gap: '12px' }}>
              <button className="btn btn-secondary" style={{ flex: 1 }} onClick={() => {
                setShowReportModal(false);
                setReportError('');
              }}>Cancel</button>
              <button className="btn btn-primary" style={{ flex: 1 }} onClick={async () => {
                if (!reportReason.trim()) {
                  setReportError('Must input a reason for reporting user.');
                  return;
                }
                try {
                  const reportKey = `report_${Date.now()}`;
                  await set(ref(db, `reports/${reportKey}`), {
                    reportedUid: otherUserUid || 'Unknown',
                    reportedName: otherUserName || 'Unknown',
                    reporterUid: currentUid || 'Unknown',
                    reason: reportReason.trim(),
                    status: 'pending',
                    timestamp: Date.now()
                  });
                  setShowReportModal(false);
                  setReportReason('');
                  setReportError('');
                  alert('Report successfully submitted to super admin.');
                } catch (e) {
                  console.error('Report error:', e);
                  setReportError(`Failed to submit report: ${e.message || 'Permission denied. Please check connection.'}`);
                }
              }}>Submit Report</button>
            </div>
          </div>
        </div>
      )}

      {showBlockConfirm && (
        <div className="modal-overlay" style={{ zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div className="modal-content" style={{ background: 'var(--surface)', borderRadius: '24px', maxWidth: '400px', width: '90%', textAlign: 'center', padding: '32px 24px' }}>
            <div style={{ background: 'rgba(245, 158, 11, 0.1)', width: '64px', height: '64px', borderRadius: '50%', display: 'flex', justifyContent: 'center', alignItems: 'center', margin: '0 auto 16px' }}>
              <ShieldCheck size={32} color="#F59E0B" />
            </div>
            <h3 style={{ margin: '0 0 8px 0', fontSize: '20px', fontWeight: 800 }}>Block User?</h3>
            <p style={{ color: 'var(--text-muted)', fontSize: '14px', marginBottom: '24px' }}>Are you sure you want to block the user? You will no longer receive messages from this user. This action can be undone later.</p>
            <div style={{ display: 'flex', gap: '12px' }}>
              <button className="btn btn-secondary" style={{ flex: 1 }} onClick={() => setShowBlockConfirm(false)}>Cancel</button>
              <button className="btn" style={{ flex: 1, background: '#F59E0B', color: 'white' }} onClick={async () => {
                try {
                  await set(ref(db, `blocks/${currentUid}/${otherUserUid}`), {
                    blockedAt: Date.now(),
                    blockedName: otherUserName
                  });
                  setShowBlockConfirm(false);
                  alert(`${otherUserName} has been blocked. You will no longer receive messages from this user.`);
                  if (onBack) onBack();
                } catch (e) {
                  console.error('Block error:', e);
                  alert('Failed to block user. Please try again.');
                }
              }}>Block User</button>
            </div>
          </div>
        </div>
      )}

      {showClearConfirm && (
        <div className="modal-overlay" style={{ zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div className="modal-content" style={{ background: 'var(--surface)', borderRadius: '24px', maxWidth: '400px', width: '90%', textAlign: 'center', padding: '32px 24px' }}>
            <div style={{ background: 'var(--primary-soft)', width: '64px', height: '64px', borderRadius: '50%', display: 'flex', justifyContent: 'center', alignItems: 'center', margin: '0 auto 16px' }}>
              <ShieldCheck size={32} color="var(--primary)" />
            </div>
            <h3 style={{ margin: '0 0 8px 0', fontSize: '20px', fontWeight: 800 }}>Clear Chat History?</h3>
            <p style={{ color: 'var(--text-muted)', fontSize: '14px', marginBottom: '24px' }}>Are you sure to clear the chat history? This will permanently delete all messages in this conversation for you. This action cannot be undone.</p>
            <div style={{ display: 'flex', gap: '12px' }}>
              <button className="btn btn-secondary" style={{ flex: 1 }} onClick={() => setShowClearConfirm(false)}>Cancel</button>
              <button className="btn btn-primary" style={{ flex: 1 }} onClick={async () => {
                try {
                  await remove(ref(db, `chats/${chatId}/messages`));
                  setShowClearConfirm(false);
                } catch (e) {
                  console.error(e);
                  alert('Failed to clear chat.');
                }
              }}>Clear Chat</button>
            </div>
          </div>
        </div>
      )}

    </div>
  );
};

export default Chat;
