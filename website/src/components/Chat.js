import React, { useState, useEffect, useRef } from 'react';
import { db } from '../firebase';
import { ref, onValue, push, set, update, serverTimestamp, get, increment, query, orderByChild } from 'firebase/database';
import { Send, ArrowLeft, User, MoreVertical, ShieldCheck, CheckCheck } from 'lucide-react';
import { encryptText, decryptText } from '../utils/encryption';
import { format } from 'date-fns';

const Chat = ({ currentUid, otherUserUid, otherUserName, onBack }) => {
  const [messages, setMessages] = useState([]);
  const [newMessage, setNewMessage] = useState('');
  const [chatId, setChatId] = useState('');
  const [myPhoto, setMyPhoto] = useState(null);
  const [otherPhoto, setOtherPhoto] = useState(null);
  const [messageLimit, setMessageLimit] = useState(20);
  const messagesEndRef = useRef(null);

  useEffect(() => {
    // Fetch photos
    const fetchPhotos = async () => {
      try {
        // Get my photo
        const myUserSnap = await get(ref(db, `users/${currentUid}`));
        if (myUserSnap.exists()) {
          const userData = myUserSnap.val();
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
        } else {
          const otherUserSnap = await get(ref(db, `users/${otherUserUid}`));
          if (otherUserSnap.exists() && otherUserSnap.val().profilePicUrl) {
            setOtherPhoto(otherUserSnap.val().profilePicUrl);
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

    return () => unsubscribe();
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
        <button className="icon-btn-more"><MoreVertical size={20} color="var(--text-muted)" /></button>
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
          const showTime = index === messages.length - 1 || messages[index+1]?.senderUid !== msg.senderUid;

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
                      {format(new Date(msg.timestamp), 'p')}
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

      {/* Input Area */}
      <div style={{ padding: '20px 24px', background: 'var(--surface)', borderTop: '1px solid var(--border)' }}>
        <form onSubmit={sendMessage} style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
          <div style={{ flex: 1, position: 'relative' }}>
            <input
              type="text"
              placeholder="Type your message..."
              className="chat-input"
              value={newMessage}
              onChange={(e) => setNewMessage(handleEmojiFilter(e.target.value))}
            />
          </div>
          <button
            type="submit"
            disabled={!newMessage.trim()}
            style={{
              width: '52px', height: '52px', borderRadius: '18px', border: '1px solid var(--border)',
              background: newMessage.trim() ? 'var(--secondary)' : 'var(--light-bg)',
              color: newMessage.trim() ? '#002D24' : 'var(--text-muted)',
              display: 'flex', justifyContent: 'center', alignItems: 'center',
              cursor: newMessage.trim() ? 'pointer' : 'default',
              transition: 'var(--transition)',
              boxShadow: newMessage.trim() ? '0 8px 15px rgba(29, 211, 176, 0.3)' : 'none'
            }}
          >
            <Send size={22} style={{ transform: newMessage.trim() ? 'translateX(2px) translateY(-1px)' : 'none' }} />
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
      `}</style>
    </div>
  );
};

export default Chat;
