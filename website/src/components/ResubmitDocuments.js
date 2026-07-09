import React, { useState } from 'react';
import { db } from '../firebase';
import { ref, update } from 'firebase/database';
import { ArrowRight, Camera } from 'lucide-react';

const ResubmitDocuments = ({ user, profile, onLogout }) => {
  const [idType, setIdType] = useState('Passport');
  const [otherIdType, setOtherIdType] = useState('');
  const [idFile, setIdFile] = useState(null);
  const [selfieFile, setSelfieFile] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  
  const cloudName = 'dth7r65f4';
  const uploadPreset = 'ResortsConnectImages';

  const handleUploadImage = async (file) => {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('upload_preset', uploadPreset);
    
    const response = await fetch(`https://api.cloudinary.com/v1_1/${cloudName}/image/upload`, {
      method: 'POST',
      body: formData
    });
    
    const data = await response.json();
    return data.secure_url;
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!idFile || !selfieFile) {
      setError('Both ID and Selfie images are required.');
      return;
    }
    
    const finalIdType = idType === 'Other' ? otherIdType : idType;
    if (!finalIdType) {
      setError('Please specify your ID type.');
      return;
    }

    setLoading(true);
    setError('');
    
    try {
      const idUrl = await handleUploadImage(idFile);
      const selfieUrl = await handleUploadImage(selfieFile);
      
      await update(ref(db, `users/${user.uid}`), {
        idType: finalIdType,
        idImageUrl: idUrl,
        selfieUrl: selfieUrl,
        identityStatus: 'pending',
        idVerified: false,
        rejectionReason: null
      });
      
    } catch (err) {
      setError('Upload failed. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '100vh', background: 'var(--light-bg)', padding: '20px' }}>
      <div className="card" style={{ maxWidth: '500px', width: '100%', padding: '32px' }}>
        <h2 style={{ margin: '0 0 16px', color: 'var(--primary)', textAlign: 'center' }}>Verification Rejected</h2>
        
        <div style={{ background: 'rgba(239, 68, 68, 0.1)', border: '1px solid rgba(239, 68, 68, 0.3)', padding: '16px', borderRadius: '12px', marginBottom: '24px' }}>
          <p style={{ margin: '0 0 8px', color: '#ef4444', fontWeight: 600 }}>Reason for rejection:</p>
          <p style={{ margin: 0, color: 'var(--text-main)' }}>{profile?.rejectionReason || 'Invalid documents provided.'}</p>
        </div>

        <p style={{ color: 'var(--text-muted)', marginBottom: '24px', textAlign: 'center' }}>Please upload clear and valid documents to resubmit your verification request.</p>

        {error && <div style={{ color: '#ef4444', marginBottom: '16px', textAlign: 'center', fontWeight: 600 }}>{error}</div>}

        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label className="input-label">Select ID Type</label>
            <select className="input" value={idType} onChange={e => setIdType(e.target.value)}>
              <option value="Passport">Passport</option>
              <option value="Driver's License">Driver's License</option>
              <option value="National ID">National ID</option>
              <option value="Postal ID">Postal ID</option>
              <option value="Voter's ID">Voter's ID</option>
              <option value="Other">Other</option>
            </select>
          </div>

          {idType === 'Other' && (
            <div className="form-group">
              <label className="input-label">Specify ID Type</label>
              <input className="input" type="text" value={otherIdType} onChange={e => setOtherIdType(e.target.value)} required />
            </div>
          )}

          <div className="form-group" style={{ marginTop: '24px' }}>
            <label className="input-label">Upload Valid ID</label>
            <label style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '140px', border: '2px dashed var(--border)', borderRadius: '12px', background: 'var(--surface)', cursor: 'pointer', overflow: 'hidden' }}>
              {idFile ? (
                <img src={URL.createObjectURL(idFile)} alt="ID Preview" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
              ) : (
                <>
                  <Camera size={32} color="var(--text-muted)" style={{ marginBottom: '8px' }} />
                  <span style={{ color: 'var(--text-muted)' }}>Click to upload ID</span>
                </>
              )}
              <input type="file" hidden accept="image/*" onChange={(e) => setIdFile(e.target.files[0])} />
            </label>
          </div>

          <div className="form-group">
            <label className="input-label">Upload Selfie with ID</label>
            <label style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '140px', border: '2px dashed var(--border)', borderRadius: '12px', background: 'var(--surface)', cursor: 'pointer', overflow: 'hidden' }}>
              {selfieFile ? (
                <img src={URL.createObjectURL(selfieFile)} alt="Selfie Preview" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
              ) : (
                <>
                  <Camera size={32} color="var(--text-muted)" style={{ marginBottom: '8px' }} />
                  <span style={{ color: 'var(--text-muted)' }}>Click to upload Selfie</span>
                </>
              )}
              <input type="file" hidden accept="image/*" onChange={(e) => setSelfieFile(e.target.files[0])} />
            </label>
          </div>

          <button type="submit" className="btn btn-primary" style={{ width: '100%', marginTop: '32px', height: '48px', display: 'flex', justifyContent: 'center', alignItems: 'center', gap: '8px' }} disabled={loading}>
            {loading ? <div className="loader small"></div> : <>RESUBMIT DOCUMENTS <ArrowRight size={18} /></>}
          </button>
        </form>

        <button onClick={onLogout} style={{ width: '100%', marginTop: '16px', background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', fontWeight: 600 }}>
          Log Out
        </button>
      </div>
    </div>
  );
};

export default ResubmitDocuments;
