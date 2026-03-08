import { initializeApp } from "https://www.gstatic.com/firebasejs/11.4.0/firebase-app.js";
import { getAnalytics } from "https://www.gstatic.com/firebasejs/11.4.0/firebase-analytics.js";

const firebaseConfig = {
  apiKey: "AIzaSyBV5BwtK4deaLIJxn-ylClbv_E8URqQK0o",
  authDomain: "top-quality-2a1a4.firebaseapp.com",
  projectId: "top-quality-2a1a4",
  storageBucket: "top-quality-2a1a4.firebasestorage.app",
  messagingSenderId: "1001852847766",
  appId: "1:1001852847766:web:c76201b837e9b399d5a4b7",
  measurementId: "G-17XLZS3GHD",
};

const app = initializeApp(firebaseConfig);

if (typeof window !== "undefined") {
  window.firebaseApp = app;
}

if (typeof window !== "undefined" && "measurementId" in firebaseConfig) {
  getAnalytics(app);
}
