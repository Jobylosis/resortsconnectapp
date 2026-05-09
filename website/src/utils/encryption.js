import CryptoJS from 'crypto-js';

export const deriveKeys = (chatId) => {
  // Key: SHA256 of chatId
  const key = CryptoJS.SHA256(chatId);

  // IV: MD5 of reversed chatId
  const reversedChatId = chatId.split('').reverse().join('');
  const iv = CryptoJS.MD5(reversedChatId);

  return { key, iv };
};

export const encryptText = (text, chatId) => {
  const { key, iv } = deriveKeys(chatId);
  const encrypted = CryptoJS.AES.encrypt(text, key, {
    iv: iv,
    mode: CryptoJS.mode.CBC,
    padding: CryptoJS.pad.Pkcs7
  });
  return encrypted.toString();
};

export const decryptText = (encryptedBase64, chatId) => {
  if (!encryptedBase64) return "";
  try {
    const { key, iv } = deriveKeys(chatId);
    const decrypted = CryptoJS.AES.decrypt(encryptedBase64, key, {
      iv: iv,
      mode: CryptoJS.mode.CBC,
      padding: CryptoJS.pad.Pkcs7
    });
    return decrypted.toString(CryptoJS.enc.Utf8);
  } catch (e) {
    console.error("Decryption failed", e);
    return "[Encrypted Message]";
  }
};
