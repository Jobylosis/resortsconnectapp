import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App';

class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error) {
    return { hasError: true, error };
  }

  componentDidCatch(error, errorInfo) {
    console.error("Uncaught application error:", error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div style={{
          minHeight: '100vh',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '24px',
          background: 'var(--bg-main, #0f172a)',
          color: 'var(--text-main, #f8fafc)',
          fontFamily: 'Outfit, sans-serif',
          textAlign: 'center'
        }}>
          <div style={{
            background: 'var(--surface, #1e293b)',
            padding: '36px 40px',
            borderRadius: '24px',
            maxWidth: '520px',
            boxShadow: '0 20px 50px rgba(0,0,0,0.3)',
            border: '1px solid rgba(255,255,255,0.08)'
          }}>
            <div style={{ fontSize: '48px', marginBottom: '16px' }}>⚠️</div>
            <h2 style={{ margin: '0 0 12px 0', fontSize: '22px', fontWeight: 800 }}>Something went wrong</h2>
            <p style={{ margin: '0 0 24px 0', fontSize: '14px', opacity: 0.8, lineHeight: 1.5 }}>
              An unexpected error occurred. Please refresh the page to reload the application.
            </p>
            <button
              onClick={() => window.location.reload()}
              style={{
                background: 'linear-gradient(135deg, #1DD1B0, #0E9F85)',
                color: 'white',
                border: 'none',
                padding: '12px 28px',
                borderRadius: '14px',
                fontWeight: 700,
                fontSize: '15px',
                cursor: 'pointer'
              }}
            >
              Refresh Page
            </button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(
  <React.StrictMode>
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  </React.StrictMode>
);
