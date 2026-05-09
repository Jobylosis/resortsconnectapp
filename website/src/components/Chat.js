import React, { useState, useEffect, useRef } from 'react';
import { db } from '../firebase';
import { ref, onValue, push, set, update, serverTimestamp, get, increment } from 'firebase/database';
import { Send, ArrowLeft, User, MoreVertical, ShieldCheck } from 'lucide-react';
import { encryptText, decryptText } from '../utils/encryption';
import { format } from 'date-fns';

const Chat = ({ currentUid, otherUserUid, otherUserName, onBack }) => {
  const [messages, setMessages] = useState([]);
  const [newMessage, setNewMessage] = useState('');
  const [chatId, setChatId] = useState('');
  const [myPhoto, setMyPhoto] = useState(null);
  const [otherPhoto, setOtherPhoto] = useState(null);
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

    // Reset unread count for this room when opening
    try {
      update(ref(db, `chat_rooms/${currentUid}/${otherUserUid}`), { unreadCount: 0 });
    } catch (e) { console.warn("Unread reset failed", e); }

    const unsubscribe = onValue(chatRef, (snapshot) => {
      const data = snapshot.val();
      if (data) {
        const list = Object.entries(data).map(([msgId, val]) => ({
          id: msgId,
          ...val,
          decryptedText: decryptText(val.text, id)
        }));
        setMessages(list);
      } else {
        setMessages([]);
      }
    });

    return () => unsubscribe();
  }, [currentUid, otherUserUid]);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const sendMessage = async (e) => {
    e.preventDefault();
    if (!newMessage.trim()) return;

    try {
      const encrypted = encryptText(newMessage.trim(), chatId);
      const messagesRef = ref(db, `chats/${chatId}/messages`);

      await push(messagesRef, {
        senderUid: currentUid,
        text: encrypted,
        timestamp: serverTimestamp()
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
      background: 'white',
      borderRadius: '32px',
      overflow: 'hidden',
      boxShadow: 'var(--shadow)',
      border: '1px solid rgba(0,0,0,0.03)'
    }}>
      {/* Chat Header */}
      <div style={{
        padding: '16px 24px',
        borderBottom: '1px solid #F3F4F6',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        background: 'white'
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
              background: '#F3F4F6',
              overflow: 'hidden',
              display: 'flex', justifyContent: 'center', alignItems: 'center',
              color: '#1D4ED8', border: '2px solid white', boxShadow: '0 4px 12px rgba(0,0,0,0.05)'
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
        background: '#F9FAFB'
      }}>
        {messages.length === 0 && (
           <div style={{ textAlign: 'center', margin: 'auto', opacity: 0.5 }}>
              <div style={{ background: 'white', padding: '20px', borderRadius: '24px', display: 'inline-block', boxShadow: '0 4px 20px rgba(0,0,0,0.02)' }}>
                 <p style={{ margin: 0, fontSize: '13px', fontWeight: 600 }}>No messages yet. Say hello!</p>
              </div>
           </div>
        )}

        {messages.map((msg, index) => {
          const isMe = msg.senderUid === currentUid;
          const showTime = index === messages.length - 1 || messages[index+1]?.senderUid !== msg.senderUid;

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
                background: '#F3F4F6', overflow: 'hidden',
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
                  background: isMe ? 'linear-gradient(135deg, var(--primary), #FF5F6D)' : 'white',
                  color: isMe ? 'white' : 'var(--text-main)',
                  fontSize: '15px',
                  fontWeight: 500,
                  boxShadow: isMe ? '0 4px 15px rgba(251, 54, 64, 0.2)' : '0 2px 8px rgba(0,0,0,0.03)',
                  lineHeight: '1.5'
                }}>
                  {msg.decryptedText}
                </div>
                {showTime && msg.timestamp && (
                  <span style={{ fontSize: '10px', color: 'var(--text-muted)', marginTop: '4px', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                    {format(new Date(msg.timestamp), 'p')}
                  </span>
                )}
              </div>
            </div>
          );
        })}
        <div ref={messagesEndRef} />
      </div>

      {/* Input Area */}
      <div style={{ padding: '20px 24px', background: 'white', borderTop: '1px solid #F3F4F6' }}>
        <form onSubmit={sendMessage} style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
          <div style={{ flex: 1, position: 'relative' }}>
            <input
              type="text"
              placeholder="Type your message..."
              className="chat-input"
              value={newMessage}
              onChange={(e) => setNewMessage(e.target.value)}
            />
          </div>
          <button
            type="submit"
            disabled={!newMessage.trim()}
            style={{
              width: '52px', height: '52px', borderRadius: '18px', border: 'none',
              background: newMessage.trim() ? 'var(--secondary)' : '#F3F4F6',
              color: newMessage.trim() ? '#002D24' : '#9CA3AF',
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
        .back-btn-chat { background: #F3F4F6; border: none; width: 36px; height: 36px; borderRadius: 12px; display: flex; align-items: center; justify-content: center; cursor: pointer; color: var(--text-main); transition: var(--transition); }
        .back-btn-chat:hover { background: #E5E7EB; transform: translateX(-3px); }
        .icon-btn-more { background: transparent; border: none; width: 36px; height: 36px; borderRadius: 12px; display: flex; align-items: center; justify-content: center; cursor: pointer; }
        .icon-btn-more:hover { background: #F9FAFB; }
        .chat-input { width: 100%; padding: 14px 20px; borderRadius: '18px'; border: 2px solid #F3F4F6; background: #F9FAFB; font-family: inherit; font-size: 15px; font-weight: 500; outline: none; transition: var(--transition); }
        .chat-input:focus { border-color: var(--secondary); background: white; box-shadow: 0 0 0 4px rgba(29, 211, 176, 0.05); }
        .view-transition { animation: fadeIn 0.4s ease-out; }
      `}</style>
    </div>
  );
};

export default Chat;
