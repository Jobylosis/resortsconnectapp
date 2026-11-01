import fs from 'fs';

async function testFetch() {
  const boundary = '----WebKitFormBoundary7MA4YWxkTrZu0gW';
  const body = [];
  
  // Create a minimal fake png (1x1 transparent png)
  const fakePng = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==', 'base64');

  const formData = new FormData();
  const blob = new Blob([fakePng], { type: 'image/png' });
  formData.append('image', blob, 'test.png');
  formData.append('expectedAmount', '1.00');
  formData.append('expectedRecipient', 'JOHN JASON L.');
  formData.append('expectedPhone', '09108971097');

  console.log("Sending fetch to ngrok...");
  try {
    const res = await fetch('https://walk-versus-peculiar.ngrok-free.dev/extract_reference', {
      method: 'POST',
      headers: { 'ngrok-skip-browser-warning': '69420' },
      body: formData,
    });
    console.log("Response status:", res.status);
    const json = await res.json();
    console.log("Response json:", json);
  } catch (e) {
    console.error("Fetch failed:", e);
  }
}

testFetch().then(() => process.exit(0));

