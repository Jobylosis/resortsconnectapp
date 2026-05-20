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

    return "I'm still learning! You can click one of the 'Common Questions' buttons above or chat with a resort owner directly for specific help.";
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

           {faqs.length > 0 && (
             <div style={{ marginTop: '10px' }}>
                <p style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 800, textTransform: 'uppercase', marginBottom: '8px', letterSpacing: '0.5px' }}>Common Questions</p>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                   {faqs.map((f, idx) => (
                     <button
                       key={idx}
                       onClick={() => handleSend(null, f.q)}
                       style={{
                         textAlign: 'left', background: 'var(--surface)', border: '1px solid var(--border)',
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
           )}

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

        <div style={{ padding: '16px', borderTop: '1px solid #F3F4F6' }}>
           <form onSubmit={handleSend} style={{ display: 'flex', gap: '8px' }}>
              <input
                className="input" placeholder="Type a question..."
                style={{ height: '44px', borderRadius: '14px', fontSize: '14px' }}
                value={input} onChange={e => setInput(handleEmojiFilter(e.target.value))}
              />
              <button type="submit" className="btn btn-primary" style={{ width: '44px', height: '44px', padding: 0, borderRadius: '14px' }}><Send size={18} /></button>
           </form>
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
