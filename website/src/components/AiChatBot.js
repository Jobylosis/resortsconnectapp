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
  const messagesEndRef = useRef(null);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, isTyping]);

  const handleSend = async (e) => {
    e.preventDefault();
    if (!input.trim()) return;

    const userMsg = input.trim();
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
    const q = query.toLowerCase();

    // Check FAQs
    try {
      const snap = await get(ref(db, 'master_data/faqs'));
      if (snap.exists()) {
        const faqs = Object.values(snap.val());
        for (const faq of faqs) {
          if (q.includes(faq.q.toLowerCase().split(' ').pop()) ||
              faq.q.toLowerCase().split(' ').some(word => q.includes(word) && word.length > 4)) {
            return `Based on our FAQs: ${faq.a}`;
          }
        }
      }
    } catch (e) { console.warn("FAQ fetch failed", e); }

    if (q.includes('hi') || q.includes('hello')) return 'Hello! Ready to find your perfect getaway?';
    if (q.includes('book')) return 'Booking is easy! Just browse our "Partners" tab, pick a property, and follow the simple booking steps.';
    if (q.includes('cancel')) return 'You can manage your bookings under the "My Bookings" tab. Cancellation requests are reviewed by property owners.';
    if (q.includes('price') || q.includes('cost')) return 'Room rates are displayed for each listing. Total costs including add-ons are shown during the booking process.';

    return "I'm still learning! You can check our FAQ tab for detailed information or chat with a resort owner directly.";
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

        <div style={{ flex: 1, overflowY: 'auto', padding: '20px', display: 'flex', flexDirection: 'column', gap: '12px', background: '#F9FAFB' }}>
           {messages.map((m, i) => (
             <div key={i} style={{ alignSelf: m.isBot ? 'flex-start' : 'flex-end', maxWidth: '85%' }}>
                <div style={{
                  padding: '12px 16px',
                  borderRadius: m.isBot ? '16px 16px 16px 4px' : '16px 16px 4px 16px',
                  background: m.isBot ? 'white' : 'var(--secondary)',
                  color: m.isBot ? 'var(--text-main)' : '#002D24',
                  fontSize: '14px', fontWeight: 500, boxShadow: '0 2px 8px rgba(0,0,0,0.02)', border: m.isBot ? '1px solid #F3F4F6' : 'none'
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
                value={input} onChange={e => setInput(e.target.value)}
              />
              <button type="submit" className="btn btn-primary" style={{ width: '44px', height: '44px', padding: 0, borderRadius: '14px' }}><Send size={18} /></button>
           </form>
        </div>
      </div>
      <style>{`
        .chatbot-overlay { position: fixed; bottom: 100px; right: 30px; }
        .view-transition { animation: slideIn 0.3s ease-out; }
        @keyframes slideIn { from { opacity: 0; transform: translateY(20px) scale(0.95); } to { opacity: 1; transform: translateY(0) scale(1); } }
      `}</style>
    </div>
  );
};

export default AiChatBot;
