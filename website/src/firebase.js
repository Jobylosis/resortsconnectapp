import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import { getDatabase } from "firebase/database";
import { getAnalytics, isSupported, logEvent } from "firebase/analytics";

const firebaseConfig = {
  apiKey: "AIzaSyD8favTsJbL6Kcr5-oaoovV3OUya4bnRU4",
  authDomain: "resortconnect-f7dd6.firebaseapp.com",
  projectId: "resortconnect-f7dd6",
  storageBucket: "resortconnect-f7dd6.firebasestorage.app",
  messagingSenderId: "49794661773",
  appId: "1:49794661773:web:8d67cdad5d6b45a2c6d1c4",
  databaseURL: "https://resortconnect-f7dd6-default-rtdb.firebaseio.com",
  measurementId: "G-7PJXLQH6RL"
};

const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getDatabase(app);

// Initialize Firebase Analytics if supported by the browser environment
export let analytics = null;
if (typeof window !== "undefined") {
  isSupported().then((supported) => {
    if (supported) {
      analytics = getAnalytics(app);
      // Log initial session start
      logEvent(analytics, 'session_start');
      logEvent(analytics, 'page_view', {
        page_location: window.location.href,
        page_path: window.location.pathname,
        page_title: document.title
      });
    }
  }).catch(() => {});
}

export const logAnalyticsEvent = (eventName, eventParams = {}) => {
  if (analytics) {
    try {
      logEvent(analytics, eventName, eventParams);
    } catch (_) {}
  }
};

