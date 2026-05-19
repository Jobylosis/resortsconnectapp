const fs = require('fs');

const filesToFix = [
  'src/components/RescheduleModal.js',
  'src/components/ReviewModal.js',
  'src/components/OwnerDashboard.js',
  'src/components/AiChatBot.js',
  'src/components/AdminDashboard.js',
  'src/components/TouristDashboard.js'
];

filesToFix.forEach(file => {
  if (fs.existsSync(file)) {
    let content = fs.readFileSync(file, 'utf8');
    
    // Replace light mode specific backgrounds
    content = content.replace(/background: '#F9FAFB'/g, "background: 'var(--light-bg)'");
    content = content.replace(/background: '#F3F4F6'/g, "background: 'var(--light-bg)'");
    content = content.replace(/background: #F9FAFB/g, "background: var(--light-bg)");
    content = content.replace(/background: #F3F4F6/g, "background: var(--light-bg)");
    
    // Replace borders
    content = content.replace(/border: '1px solid #F3F4F6'/g, "border: '1px solid var(--border)'");
    content = content.replace(/border: 1px solid #F3F4F6/g, "border: 1px solid var(--border)");
    content = content.replace(/borderBottom: '1px solid #F3F4F6'/g, "borderBottom: '1px solid var(--border)'");
    content = content.replace(/borderTop: '1px solid #F3F4F6'/g, "borderTop: '1px solid var(--border)'");
    
    // Replace other specific ones from grep
    content = content.replace(/background: user\.role === 'Owner' \? '#ECFDF5' : '#F3F4F6'/g, "background: user.role === 'Owner' ? 'rgba(16, 185, 129, 0.1)' : 'var(--light-bg)'");
    
    fs.writeFileSync(file, content);
    console.log('Fixed:', file);
  }
});
