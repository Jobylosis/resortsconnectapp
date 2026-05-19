const fs = require('fs');

// Fix AiChatBot.js
let aiFile = fs.readFileSync('src/components/AiChatBot.js', 'utf8');
aiFile = aiFile.replace("background: '#F9FAFB' }}", "background: 'var(--light-bg)' }}");
aiFile = aiFile.replace("background: 'white', border: '1px solid #F3F4F6',", "background: 'var(--surface)', border: '1px solid var(--border)',");
aiFile = aiFile.replace(/e\.currentTarget\.style\.borderColor = '#F3F4F6'/g, "e.currentTarget.style.borderColor = 'var(--border)'");
aiFile = aiFile.replace("background: m.isBot ? 'white' : 'var(--secondary)'", "background: m.isBot ? 'var(--surface)' : 'var(--secondary)'");
aiFile = aiFile.replace("border: m.isBot ? '1px solid #F3F4F6' : 'none'", "border: m.isBot ? '1px solid var(--border)' : 'none'");
fs.writeFileSync('src/components/AiChatBot.js', aiFile);
console.log('AiChatBot.js fixed');

// Fix BookingModal.js
let bookingFile = fs.readFileSync('src/components/BookingModal.js', 'utf8');
bookingFile = bookingFile.replace(
  "background: '#F9FAFB', borderRadius: '20px', border: '1px solid #F3F4F6'",
  "background: 'var(--light-bg)', borderRadius: '20px', border: '1px solid var(--border)'"
);
fs.writeFileSync('src/components/BookingModal.js', bookingFile);
console.log('BookingModal.js fixed');

// Fix PropertyDetails.js
let propFile = fs.readFileSync('src/components/PropertyDetails.js', 'utf8');
propFile = propFile.replace(/background: 'white', borderRadius: '40px 40px 0 0'/g, "background: 'var(--surface)', borderRadius: '40px 40px 0 0'");
propFile = propFile.replace(/display: 'flex', alignItems: 'center', gap: '8px', background: 'white',/g, "display: 'flex', alignItems: 'center', gap: '8px', background: 'var(--surface)',");
propFile = propFile.replace(/background: 'white', border: 'none', borderRadius: '50%',/g, "background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: '50%',");
propFile = propFile.replace(/background: '#F9FAFB', borderRadius: '24px', border: '1px solid #F3F4F6'/g, "background: 'var(--light-bg)', borderRadius: '24px', border: '1px solid var(--border)'");
propFile = propFile.replace(/padding: '10px', background: 'white', borderRadius: '12px',/g, "padding: '10px', background: 'var(--surface)', borderRadius: '12px', border: '1px solid var(--border)',");
propFile = propFile.replace(/background: 'white', borderRadius: '16px', border: '1px solid #F3F4F6'/g, "background: 'var(--surface)', borderRadius: '16px', border: '1px solid var(--border)'");
propFile = propFile.replace("background: 'white', borderRadius: '24px', border: '2px dashed #E5E7EB'", "background: 'var(--surface)', borderRadius: '24px', border: '2px dashed var(--border-dashed)'");
propFile = propFile.replace("background: 'white', borderRadius: '32px', border: '1px solid #F3F4F6',", "background: 'var(--surface)', borderRadius: '32px', border: '1px solid var(--border)',");
fs.writeFileSync('src/components/PropertyDetails.js', propFile);
console.log('PropertyDetails.js fixed');

// Fix TouristDashboard.js remaining
let tdFile = fs.readFileSync('src/components/TouristDashboard.js', 'utf8');
tdFile = tdFile.replace(/background: '#F3F4F6' \}\} onClick=\{.*?setRefundBooking/g, 
  "background: 'var(--light-bg)', color: 'var(--text-main)', border: '1px solid var(--border)' }} onClick={() => setRefundBooking");
fs.writeFileSync('src/components/TouristDashboard.js', tdFile);
console.log('TouristDashboard.js fixed');

console.log('All files fixed!');
