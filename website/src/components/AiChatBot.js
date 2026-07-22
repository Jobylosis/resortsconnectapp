import React, { useState, useEffect, useRef } from 'react';
import { db } from '../firebase';
import { ref, get } from 'firebase/database';
import { Send, X, Bot, User, Sparkles } from 'lucide-react';

const AiChatBot = ({ onClose }) => {
  const [messages, setMessages] = useState([
    { text: 'Hello! I am your Resort Connect AI assistant. How can I help you today?', isBot: true }
  ]);
  const [input, setInput] = useState('');
  const [isTyping, setIsTyping] = useState(false);
  const [faqs, setFaqs] = useState([
    { q: 'How do I book a room?', a: 'Browse resorts in the "Partners" tab, select a room, and click "Book Now".' },
    { q: 'Can I cancel my booking?', a: 'Yes, in the "My Bookings" tab, you can request a cancellation.' },
    { q: 'How does rescheduling work?', a: 'Go to "My Bookings", click "Reschedule", and pick a new date and duration.' },
    { q: 'Is my payment secure?', a: 'Yes, we use GCash for verified payments and manual receipt verification.' }
  ]);
  const messagesEndRef = useRef(null);

  useEffect(() => {
    const faqRef = ref(db, 'master_data/faqs');
    get(faqRef).then((snap) => {
      if (snap.exists()) {
        const val = snap.val();
        const list = Array.isArray(val) ? val.filter(e => e) : Object.values(val);
        if (list.length > 0) setFaqs(list);
      }
    }).catch(err => {
      console.warn("AI Bot FAQ fetch permission issue or error:", err);
    });
  }, []);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, isTyping]);

  const handleEmojiFilter = (value) => {
    const emojiRegex = /[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]/gu;
    return value.replace(emojiRegex, '');
  };

  const handleSend = async (e, forcedMsg = null) => {
    if (e) e.preventDefault();
    const userMsg = forcedMsg || input.trim();
    if (!userMsg) return;

    setMessages(prev => [...prev, { text: userMsg, isBot: false }]);
    setInput('');
    setIsTyping(true);

    // Simulate AI delay
    setTimeout(async () => {
      const response = await getAiResponse(userMsg);
      setMessages(prev => [...prev, { text: response, isBot: true }]);
      setIsTyping(false);
    }, 1000);
  };

  const findCheapestRoom = async () => {
    try {
      const snap = await get(ref(db, 'properties'));
      if (!snap.exists()) return "Sorry, I couldn't find any properties at the moment.";

      const properties = snap.val();
      let lowestPrice = Infinity;
      let bestRoomName = "";
      let bestResortName = "";

      Object.values(properties).forEach((propData) => {
        if (propData && propData.roomInventory) {
          const resortName = propData.name || 'A resort';
          const rooms = propData.roomInventory;
          
          const roomsArray = Array.isArray(rooms) ? rooms.filter(Boolean) : Object.values(rooms);
          roomsArray.forEach((roomData) => {
            if (roomData && roomData.price) {
              const price = parseFloat(roomData.price);
              if (!isNaN(price) && price < lowestPrice) {
                lowestPrice = price;
                bestRoomName = roomData.title || 'Room';
                bestResortName = resortName;
              }
            }
          });
        }
      });

      if (lowestPrice === Infinity) return "I couldn't find any room prices right now. Please check the Partners tab for available rooms.";
      return `Based on our current listings, the most affordable option is the '${bestRoomName}' at ${bestResortName} for just ₱${lowestPrice} per night! Go to the Partners tab to book it.`;
    } catch (e) {
      return "There was an error fetching the room prices. Please check the Partners tab.";
    }
  };

  const findMostExpensiveRoom = async () => {
    try {
      const snap = await get(ref(db, 'properties'));
      if (!snap.exists()) return "Sorry, I couldn't find any properties at the moment.";

      const properties = snap.val();
      let highestPrice = 0;
      let bestRoomName = "";
      let bestResortName = "";

      Object.values(properties).forEach((propData) => {
        if (propData && propData.roomInventory) {
          const resortName = propData.name || 'A resort';
          const rooms = propData.roomInventory;
          
          const roomsArray = Array.isArray(rooms) ? rooms.filter(Boolean) : Object.values(rooms);
          roomsArray.forEach((roomData) => {
            if (roomData && roomData.price) {
              const price = parseFloat(roomData.price);
              if (!isNaN(price) && price > highestPrice) {
                highestPrice = price;
                bestRoomName = roomData.title || 'Room';
                bestResortName = resortName;
              }
            }
          });
        }
      });

      if (highestPrice === 0) return "I couldn't find any room prices right now.";
      return `If you're looking for premium luxury, our most expensive offering is the '${bestRoomName}' at ${bestResortName} for ₱${highestPrice} per night. Check it out in the Partners tab!`;
    } catch (e) {
      return "There was an error fetching the room prices. Please check the Partners tab.";
    }
  };

  const findLargestRoom = async () => {
    try {
      const snap = await get(ref(db, 'properties'));
      if (!snap.exists()) return "Sorry, I couldn't find any properties at the moment.";

      const properties = snap.val();
      let largestCapacity = 0;
      let bestRoomName = "";
      let bestResortName = "";

      Object.values(properties).forEach((propData) => {
        if (propData && propData.roomInventory) {
          const resortName = propData.name || 'A resort';
          const rooms = propData.roomInventory;
          
          const roomsArray = Array.isArray(rooms) ? rooms.filter(Boolean) : Object.values(rooms);
          roomsArray.forEach((roomData) => {
            if (roomData) {
              const cap = parseInt(roomData.maxPax) || parseInt(roomData.capacity) || 0;
              if (cap > largestCapacity) {
                largestCapacity = cap;
                bestRoomName = roomData.title || 'Room';
                bestResortName = resortName;
              }
            }
          });
        }
      });

      if (largestCapacity === 0) return "I couldn't find any room capacities right now.";
      return `If you're traveling with a big group or family, I recommend the '${bestRoomName}' at ${bestResortName}. It can accommodate up to ${largestCapacity} people! Check it out in the Partners tab.`;
    } catch (e) {
      return "There was an error fetching the room sizes. Please check the Partners tab.";
    }
  };

  const getAiResponse = async (query) => {
    const q = query.toLowerCase().trim();

    // 1. Try to find an exact match in the current faqs state
    const exactMatch = faqs.find(f => f.q.toLowerCase().trim() === q);
    if (exactMatch) return exactMatch.a;

    // 2. Check Database for latest FAQ data if not matched yet
    try {
      const snap = await get(ref(db, 'master_data/faqs'));
      if (snap.exists()) {
        const dbFaqs = Object.values(snap.val());
        const dbMatch = dbFaqs.find(f => f.q.toLowerCase().trim() === q);
        if (dbMatch) return dbMatch.a;

        // 3. Keyword matching (fuzzy)
        for (const faq of dbFaqs) {
          const faqQ = faq.q.toLowerCase();
          if (q.includes(faqQ) || faqQ.includes(q)) return faq.a;

          // Check significant words
          const keywords = faqQ.split(' ').filter(w => w.length > 4);
          if (keywords.some(k => q.includes(k))) return faq.a;
        }
      }
    } catch (e) { console.warn("AI Bot fuzzy match failed", e); }

    // 4. Default responses for common greetings
    if (q.includes('hi') || q.includes('hello')) return 'Hello! Ready to find your perfect getaway?';
    if (q.includes('book')) return 'Booking is easy! Just browse our "Partners" tab, pick a property, and follow the simple booking steps.';
    if (q.includes('cancel')) return 'You can manage your bookings under the "My Bookings" tab. Cancellation requests are reviewed by property owners.';
    if (q.includes('mura') || q.includes('cheapest') || q.includes('lowest') || q.includes('affordable')) {
      return await findCheapestRoom();
    }
    if (q.includes('mahal') || q.includes('expensive') || q.includes('premium') || q.includes('luxury')) {
      return await findMostExpensiveRoom();
    }
    if (q.includes('pool') || q.includes('swimming')) {
      return "Many of our resorts have swimming pools! You can go to the 'Partners' tab and check the 'Amenities' section of each resort to find the perfect pool for your stay.";
    }
    if (q.includes('pet') || q.includes('dog') || q.includes('cat')) {
      return "Looking to bring your furry friends? Some of our resorts are pet-friendly! Please check the specific resort's policies in the Partners tab before booking.";
    }
    if (q.includes('thanks') || q.includes('thank you') || q.includes('salamat')) {
      return "You're very welcome! Let me know if you need anything else.";
    }
    if (q.includes('group') || q.includes('family') || q.includes('barkada') || q.includes('marami')) {
      return await findLargestRoom();
    }
    if (q.includes('payment') || q.includes('gcash') || q.includes('bayad')) {
      return "For payments, we currently support GCash! You have the option to pay the Full Amount or a 30% Downpayment when booking a room. The remaining balance can be paid at the resort.";
    }
    if (q.includes('location') || q.includes('saan') || q.includes('where')) {
      return "ResortsConnect features amazing properties! You can go to the 'Partners' tab and use the Map view to see exact locations and even get directions.";
    }
    if (q.includes('refund') || q.includes('bawi')) {
      return "Refunds are processed depending on the resort's cancellation policy. Generally, you need to request cancellation through the 'My Bookings' tab and wait for the owner's approval.";
    }

    return "I'm still learning! You can click one of the 'Common Questions' buttons above or try asking about the cheapest, most expensive, or largest rooms for groups!";
  };

  return (
    <div className="chatbot-overlay" style={{ zIndex: 5000 }}>
      <div className="card chatbot-content view-transition" style={{ maxWidth: '400px', height: '500px', display: 'flex', flexDirection: 'column', padding: 0 }}>
        <div style={{ padding: '16px 20px', background: 'var(--primary)', color: 'white', display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderRadius: '32px 32px 0 0' }}>
           <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
              <Bot size={24} />
              <div>
                 <h4 style={{ margin: 0, fontSize: '15px', fontWeight: 800 }}>AI Assistant</h4>
                 <span style={{ fontSize: '10px', opacity: 0.8, fontWeight: 600 }}>Always active</span>
              </div>
           </div>
           <button onClick={onClose} style={{ background: 'rgba(255,255,255,0.2)', border: 'none', borderRadius: '50%', width: '28px', height: '28px', cursor: 'pointer', color: 'white' }}><X size={16} /></button>
        </div>

        <div style={{ flex: 1, overflowY: 'auto', padding: '20px', display: 'flex', flexDirection: 'column', gap: '12px', background: 'var(--light-bg)' }}>
           <div style={{ alignSelf: 'flex-start', maxWidth: '85%' }}>
              <div style={{
                padding: '12px 16px',
                borderRadius: '16px 16px 16px 4px',
                background: 'var(--surface)',
                color: 'var(--text-main)',
                fontSize: '14px', fontWeight: 500, boxShadow: '0 2px 8px rgba(0,0,0,0.02)', border: '1px solid var(--border)'
              }}>
                Hello! I am your Resort Connect AI assistant. How can I help you today?
              </div>
           </div>



           {messages.filter(m => m.text !== 'Hello! I am your Resort Connect AI assistant. How can I help you today?').map((m, i) => (
             <div key={i} style={{ alignSelf: m.isBot ? 'flex-start' : 'flex-end', maxWidth: '85%' }}>
                <div style={{
                  padding: '12px 16px',
                  borderRadius: m.isBot ? '16px 16px 16px 4px' : '16px 16px 4px 16px',
                  background: m.isBot ? 'var(--surface)' : 'var(--secondary)',
                  color: m.isBot ? 'var(--text-main)' : '#002D24',
                  fontSize: '14px', fontWeight: 500, boxShadow: '0 2px 8px rgba(0,0,0,0.02)', border: m.isBot ? '1px solid var(--border)' : 'none'
                }}>
                  {m.text}
                </div>
             </div>
           ))}

           {isTyping && (
             <div style={{ alignSelf: 'flex-start', fontSize: '11px', color: 'var(--text-muted)', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '4px' }}>
                <Sparkles size={12} /> AI is typing...
             </div>
           )}
           <div ref={messagesEndRef} />
        </div>

        <div style={{ padding: '16px', borderTop: '1px solid var(--border)', background: 'var(--surface)', borderRadius: '0 0 32px 32px' }}>
            <p style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 800, textTransform: 'uppercase', marginBottom: '8px', letterSpacing: '0.5px' }}>Tap a question to ask</p>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', maxHeight: '160px', overflowY: 'auto' }}>
               {faqs.map((f, idx) => (
                 <button
                   key={idx}
                   onClick={() => handleSend(null, f.q)}
                   style={{
                     textAlign: 'left', background: 'var(--light-bg)', border: '1px solid var(--border)',
                     padding: '10px 14px', borderRadius: '12px', fontSize: '12px',
                     fontWeight: 600, color: 'var(--primary)', cursor: 'pointer',
                     transition: 'var(--transition)'
                   }}
                   onMouseOver={e => e.currentTarget.style.borderColor = 'var(--secondary)'}
                   onMouseOut={e => e.currentTarget.style.borderColor = 'var(--border)'}
                 >
                   {f.q}
                 </button>
               ))}
            </div>
        </div>
      </div>
      <style>{`
        .chatbot-overlay {
          position: fixed;
          bottom: 100px;
          right: 30px;
          width: calc(100% - 60px);
          max-width: 400px;
          z-index: 5000;
        }
        .view-transition { animation: slideIn 0.3s ease-out; }
        @keyframes slideIn { from { opacity: 0; transform: translateY(20px) scale(0.95); } to { opacity: 1; transform: translateY(0) scale(1); } }
      `}</style>
    </div>
  );
};

export default AiChatBot;
