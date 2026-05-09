import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import { getDatabase } from "firebase/database";

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
