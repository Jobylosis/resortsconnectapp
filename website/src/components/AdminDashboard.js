import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, onValue, update, get } from 'firebase/database';
import { Shield, UserX, UserCheck, Search, Users, AlertTriangle, CheckCircle, X, ArrowLeft, ShieldCheck, CheckCheck, Send, User, Mail, Phone, Calendar } from 'lucide-react';
import { decryptText } from '../utils/encryption';
import { format, isToday, isThisYear } from 'date-fns';
import AdminCMS from './AdminCMS';

const AdminDashboard = ({ profile, uid }) => {
  const [users, setUsers] = useState([]);
  const [reports, setReports] = useState([]);
  const [loading, setLoading] = useState(true);
  const [selectedReport, setSelectedReport] = useState(null);
  const [chatOpen, setChatOpen] = useState(false);
  const [chatMessages, setChatMessages] = useState([]);
  const [chatLoading, setChatLoading] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [activeTab, setActiveTab] = useState('users');
  const [selectedUser, setSelectedUser] = useState(null);

  // Ban modal state
  const [banModal, setBanModal] = useState(null); // { user, action: 'ban'|'unban' }
  const [banReason, setBanReason] = useState('');
  const [banError, setBanError] = useState('');
  const [banLoading, setBanLoading] = useState(false);

  // Resolve modal state
  const [resolveModal, setResolveModal] = useState(null); // report object
  const [resolveLoading, setResolveLoading] = useState(false);
  const [resolveAction, setResolveAction] = useState('dismiss');
  const [resolveMessage, setResolveMessage] = useState('');
  const [reporterPhoto, setReporterPhoto] = useState(null);
  const [reportedPhoto, setReportedPhoto] = useState(null);

  // Verification modal state
  const [verificationModal, setVerificationModal] = useState(null);
  const [verificationLoading, setVerificationLoading] = useState(false);

  useEffect(() => {
    if (!selectedReport || !chatOpen) return;
    setChatLoading(true);

    const fetchPhotos = async () => {
      try {
        const reporterPropSnap = await get(ref(db, `properties/${selectedReport.reporterUid}`));
        if (reporterPropSnap.exists()) {
          const propData = reporterPropSnap.val();
          const imgs = Array.isArray(propData.imageUrls) ? propData.imageUrls : (propData.imageUrls ? Object.values(propData.imageUrls) : []);
          if (imgs.length > 0) setReporterPhoto(imgs[0]);
        } else {
          const userSnap = await get(ref(db, `users/${selectedReport.reporterUid}`));
          if (userSnap.exists() && userSnap.val().profilePicUrl) {
            setReporterPhoto(userSnap.val().profilePicUrl);
          } else {
            setReporterPhoto(null);
          }
        }
      } catch (e) { console.warn("Failed fetching reporter photo", e); }

      try {
        const reportedPropSnap = await get(ref(db, `properties/${selectedReport.reportedUid}`));
        if (reportedPropSnap.exists()) {
          const propData = reportedPropSnap.val();
          const imgs = Array.isArray(propData.imageUrls) ? propData.imageUrls : (propData.imageUrls ? Object.values(propData.imageUrls) : []);
          if (imgs.length > 0) setReportedPhoto(imgs[0]);
        } else {
          const userSnap = await get(ref(db, `users/${selectedReport.reportedUid}`));
          if (userSnap.exists() && userSnap.val().profilePicUrl) {
            setReportedPhoto(userSnap.val().profilePicUrl);
          } else {
            setReportedPhoto(null);
          }
        }
      } catch (e) { console.warn("Failed fetching reported photo", e); }
    };
    fetchPhotos();

    const sortedIds = [selectedReport.reportedUid, selectedReport.reporterUid].sort();
    const chatId = sortedIds.join('_');
    const chatRef = ref(db, `chats/${chatId}/messages`);
    get(chatRef)
      .then(snap => {
        const data = snap.val();
        if (data) {
          const msgs = Object.entries(data)
            .map(([msgId, val]) => {
              let decrypted = '';
              try {
                decrypted = decryptText(val.text, chatId);
              } catch (e) {
                console.error('Failed to decrypt message:', e);
                decrypted = '[Could not decrypt message]';
              }
              return { id: msgId, ...val, decryptedText: decrypted || val.text };
            })
            .sort((a, b) => (a.timestamp || 0) - (b.timestamp || 0));
          setChatMessages(msgs);
        } else {
          setChatMessages([]);
        }
        setChatLoading(false);
      })
      .catch(err => {
        console.error('Failed to load chat:', err);
        setChatLoading(false);
      });
  }, [chatOpen, selectedReport]);

  useEffect(() => {
    const usersRef = ref(db, 'users');
    const unsubscribe = onValue(usersRef, (snapshot) => {
      const data = snapshot.val();
      if (data) {
        const list = Object.entries(data)
          .map(([id, val]) => ({ id, ...val }))
          .filter(u => u.id !== uid)
          .sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));
        setUsers(list);
      }
      setLoading(false);
    });

    const reportsRef = ref(db, 'reports');
    const unsubReports = onValue(reportsRef, (snap) => {
      const data = snap.val();
      if (data) {
        setReports(Object.entries(data).map(([id, val]) => ({ id, ...val })).sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0)));
      } else {
        setReports([]);
      }
    });

    return () => { unsubscribe(); unsubReports(); };
  }, [uid]);

  const openBanModal = (user) => {
    setBanModal(user);
    setBanReason('');
    setBanError('');
  };

  const confirmBan = async () => {
    if (!banModal) return;
    const isBanning = !banModal.isBanned;
    if (isBanning && !banReason.trim()) {
      setBanError('Please provide a reason for restricting this user.');
      return;
    }
    setBanLoading(true);
    try {
      await update(ref(db, `users/${banModal.id}`), {
        isBanned: isBanning,
        ...(isBanning ? { banReason: banReason.trim(), bannedAt: Date.now() } : { banReason: null, bannedAt: null })
      });
      setBanModal(null);
      setBanReason('');
      setBanError('');
    } catch (e) {
      setBanError(`Failed: ${e.message}`);
    }
    setBanLoading(false);
  };

  const openResolveModal = (report) => {
    setResolveAction('dismiss');
    setResolveMessage('');
    setResolveModal(report);
  };

  const confirmResolve = async () => {
    if (!resolveModal) return;
    setResolveLoading(true);
    try {
      const updates = {};
      
      if (resolveAction === 'ban_reported') {
        updates[`users/${resolveModal.reportedUid}/isBanned`] = true;
        updates[`users/${resolveModal.reportedUid}/banReason`] = resolveMessage || 'Banned due to report violation';
        updates[`users/${resolveModal.reportedUid}/bannedAt`] = Date.now();
      } else if (resolveAction === 'warn_reported') {
        const userSnap = await get(ref(db, `users/${resolveModal.reportedUid}/warningCount`));
        const currentWarnings = userSnap.exists() ? userSnap.val() : 0;
        const newWarnings = currentWarnings + 1;
        
        updates[`users/${resolveModal.reportedUid}/warningCount`] = newWarnings;
        
        if (newWarnings >= 3) {
          updates[`users/${resolveModal.reportedUid}/isBanned`] = true;
          updates[`users/${resolveModal.reportedUid}/banReason`] = 'Accumulated 3 Warnings';
          updates[`users/${resolveModal.reportedUid}/bannedAt`] = Date.now();
        }

        const notifKey = `notifications/${resolveModal.reportedUid}/${Date.now()}`;
        updates[notifKey] = {
          title: newWarnings >= 3 ? 'Account Banned' : 'Official Warning',
          message: newWarnings >= 3 ? 'Your account has been banned due to accumulating 3 warnings.' : (resolveMessage || 'You have received a warning regarding your recent conduct.'),
          type: 'warning',
          read: false,
          timestamp: Date.now()
        };
      } else if (resolveAction === 'warn_reporter') {
        const userSnap = await get(ref(db, `users/${resolveModal.reporterUid}/warningCount`));
        const currentWarnings = userSnap.exists() ? userSnap.val() : 0;
        const newWarnings = currentWarnings + 1;

        updates[`users/${resolveModal.reporterUid}/warningCount`] = newWarnings;

        if (newWarnings >= 3) {
          updates[`users/${resolveModal.reporterUid}/isBanned`] = true;
          updates[`users/${resolveModal.reporterUid}/banReason`] = 'Accumulated 3 Warnings';
          updates[`users/${resolveModal.reporterUid}/bannedAt`] = Date.now();
        }

        const notifKey = `notifications/${resolveModal.reporterUid}/${Date.now()}`;
        updates[notifKey] = {
          title: newWarnings >= 3 ? 'Account Banned' : 'Official Warning: False Report',
          message: newWarnings >= 3 ? 'Your account has been banned due to accumulating 3 warnings.' : (resolveMessage || 'You have received a warning for submitting a false or inappropriate report.'),
          type: 'warning',
          read: false,
          timestamp: Date.now()
        };
      }

      updates[`reports/${resolveModal.id}/status`] = 'resolved';
      updates[`reports/${resolveModal.id}/resolvedAt`] = Date.now();
      updates[`reports/${resolveModal.id}/resolveAction`] = resolveAction;

      await update(ref(db), updates);
      setResolveModal(null);
    } catch (e) {
      console.error(e);
      alert('Failed to resolve report: ' + e.message);
    }
    setResolveLoading(false);
  };

  const confirmVerification = async (approved) => {
    if (!verificationModal) return;
    setVerificationLoading(true);
    try {
      if (approved) {
        await update(ref(db, `users/${verificationModal.id}`), { identityStatus: 'verified', idVerified: true });
      } else {
        const reason = window.prompt("Enter reason for rejection (e.g. Blurry photo, Not matching):", "Blurry Image");
        if (reason === null) {
          setVerificationLoading(false);
          return; // Cancelled
        }
        await update(ref(db, `users/${verificationModal.id}`), { 
          identityStatus: 'rejected', 
          rejectionReason: reason || "ID verification failed",
          idImageUrl: null,
          selfieUrl: null,
          idVerified: false
        });
        
        // Push notification
        const notifKey = `notifications/${verificationModal.id}/${Date.now()}`;
        await update(ref(db, `notifications/${verificationModal.id}`), {
          [Date.now()]: {
            title: 'ID Verification Rejected',
            message: `Your ID verification was rejected. Reason: ${reason || "ID verification failed"}. Please log in and resubmit your documents.`,
            type: 'verification_rejected',
            isRead: false,
            timestamp: Date.now()
          }
        });
      }
      setVerificationModal(null);
    } catch (e) {
      console.error(e);
    }
    setVerificationLoading(false);
  };

  const getReporterName = (uid) => {
    const user = users.find(u => u.id === uid);
    if (user) {
      const name = `${user.firstName || ''} ${user.lastName || ''}`.trim();
      return name ? name : uid;
    }
    return uid;
  };

  const filteredUsers = users.filter(u => {
    const matchesSearch = `${u.firstName} ${u.lastName}`.toLowerCase().includes(searchQuery.toLowerCase()) ||
                          u.email?.toLowerCase().includes(searchQuery.toLowerCase());
    let matchesStatus = true;
    if (statusFilter === 'active') matchesStatus = !u.isBanned;
    if (statusFilter === 'suspended') matchesStatus = u.isBanned;
    if (statusFilter === 'owner') matchesStatus = u.role === 'Owner';
    if (statusFilter === 'tourist') matchesStatus = (u.role === 'Tourist' || !u.role);
    return matchesSearch && matchesStatus;
  });

  const stats = {
    total: users.length,
    active: users.filter(u => !u.isBanned && u.identityStatus !== 'rejected').length,
    banned: users.filter(u => u.isBanned).length,
    owners: users.filter(u => u.role === 'Owner').length,
    pendingVerifications: users.filter(u => u.role !== 'Admin' && u.identityStatus === 'pending').length
  };

  const pendingReports = reports.filter(r => r.status === 'pending').length;

  if (loading) return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '60vh' }}>
      <div className="loader"></div>
    </div>
  );

  return (
    <div className="view-transition">
      <div className="card" style={{
        background: 'linear-gradient(135deg, var(--primary), #FF5F6D)',
        color: 'white', marginBottom: '40px', padding: '40px',
        border: 'none', position: 'relative', overflow: 'hidden'
      }}>
        <div style={{ position: 'relative', zIndex: 1 }}>
          <h2 style={{ display: 'flex', alignItems: 'center', gap: '16px', margin: 0, fontSize: '32px', fontWeight: 800 }}>
            <Shield size={36} /> System Control
          </h2>
          <p style={{ opacity: 0.9, margin: '12px 0 0 0', fontSize: '16px', fontWeight: 500 }}>
            Oversee ecosystem health, manage memberships, and maintain security.
          </p>
        </div>
        <Shield size={180} style={{ position: 'absolute', right: '-40px', bottom: '-40px', opacity: 0.1, transform: 'rotate(-15deg)' }} />
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '20px', marginBottom: '48px' }}>
        <StatItem icon={<Users color="var(--secondary)" size={26} />} label="Total Users" value={stats.total} bgGradient="linear-gradient(135deg, rgba(29,211,176,0.15), rgba(29,211,176,0.05))" onClick={() => setActiveTab('users')} />
        <StatItem icon={<AlertTriangle color="#EF4444" size={26} />} label="Pending Reports" value={pendingReports} bgGradient="linear-gradient(135deg, rgba(239,68,68,0.15), rgba(239,68,68,0.05))" onClick={() => setActiveTab('reports')} />
        <StatItem icon={<ShieldCheck color="#F59E0B" size={26} />} label="Pending Verifications" value={stats.pendingVerifications} bgGradient="linear-gradient(135deg, rgba(245,158,11,0.15), rgba(245,158,11,0.05))" onClick={() => setActiveTab('verifications')} />
        <StatItem icon={<Shield color="#3B82F6" size={26} />} label="Resort Partners" value={stats.owners} bgGradient="linear-gradient(135deg, rgba(59,130,246,0.15), rgba(59,130,246,0.05))" />
      </div>

      <div style={{ display: 'flex', gap: '16px', marginBottom: '24px', borderBottom: '2px solid var(--border)', paddingBottom: '16px', overflowX: 'auto' }}>
        <button onClick={() => setActiveTab('users')} style={{ background: 'none', border: 'none', fontSize: '18px', fontWeight: 800, color: activeTab === 'users' ? 'var(--primary)' : 'var(--text-muted)', cursor: 'pointer', transition: 'var(--transition)' }}>All Users</button>
        <button onClick={() => setActiveTab('reports')} style={{ background: 'none', border: 'none', fontSize: '18px', fontWeight: 800, color: activeTab === 'reports' ? 'var(--primary)' : 'var(--text-muted)', cursor: 'pointer', transition: 'var(--transition)', display: 'flex', alignItems: 'center', gap: '8px' }}>
          Reports {pendingReports > 0 && <span style={{ background: '#EF4444', color: 'white', fontSize: '12px', padding: '2px 8px', borderRadius: '12px' }}>{pendingReports}</span>}
        </button>
        <button onClick={() => setActiveTab('verifications')} style={{ background: 'none', border: 'none', fontSize: '18px', fontWeight: 800, color: activeTab === 'verifications' ? 'var(--primary)' : 'var(--text-muted)', cursor: 'pointer', transition: 'var(--transition)', display: 'flex', alignItems: 'center', gap: '8px' }}>
          Verifications {stats.pendingVerifications > 0 && <span style={{ background: '#F59E0B', color: 'white', fontSize: '12px', padding: '2px 8px', borderRadius: '12px' }}>{stats.pendingVerifications}</span>}
        </button>
        <button onClick={() => setActiveTab('cms')} style={{ background: 'none', border: 'none', fontSize: '18px', fontWeight: 800, color: activeTab === 'cms' ? 'var(--primary)' : 'var(--text-muted)', cursor: 'pointer', transition: 'var(--transition)' }}>Content CMS</button>
      </div>

      {activeTab === 'users' && (
        <>
          <div style={{ marginBottom: '32px', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', flexWrap: 'wrap', gap: '20px' }}>
            <p style={{ color: 'var(--text-muted)', margin: 0, fontSize: '14px' }}>Review and manage user access permissions.</p>
            <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap' }}>
              <div style={{ position: 'relative', minWidth: '300px', flex: 1 }}>
                <Search style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} size={18} />
                <input type="text" placeholder="Search by name or email..." className="input"
                  style={{ paddingLeft: '48px', height: '48px', borderRadius: '14px', width: '100%' }}
                  value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} />
              </div>
              <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} className="input"
                style={{ height: '48px', borderRadius: '14px', minWidth: '160px', padding: '0 16px', background: 'var(--surface)', cursor: 'pointer' }}>
                <option value="all">All Accounts</option>
                <option value="active">Active Only</option>
                <option value="suspended">Suspended</option>
                <option value="owner">Owners</option>
                <option value="tourist">Tourists</option>
              </select>
            </div>
          </div>

          <div className="card" style={{ padding: 0, overflow: 'hidden', border: '1px solid var(--border)', boxShadow: 'var(--shadow)' }}>
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                <thead>
                  <tr style={{ background: 'var(--light-bg)', borderBottom: '1px solid var(--border)', textAlign: 'left' }}>
                    <th style={{ padding: '20px 24px', fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', color: 'var(--text-muted)', letterSpacing: '1px' }}>Account</th>
                    <th style={{ padding: '20px 24px', fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', color: 'var(--text-muted)', letterSpacing: '1px' }}>Type</th>
                    <th style={{ padding: '20px 24px', fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', color: 'var(--text-muted)', letterSpacing: '1px' }}>Status / Reason</th>
                    <th style={{ padding: '20px 24px', fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', color: 'var(--text-muted)', letterSpacing: '1px', textAlign: 'right' }}>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredUsers.length === 0 && (
                    <tr><td colSpan="4" style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>No users found.</td></tr>
                  )}
                  {filteredUsers.map(user => (
                    <tr key={user.id} style={{ borderBottom: '1px solid var(--border)' }} className="table-row">
                      <td style={{ padding: '20px 24px' }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
                          <div style={{
                            width: '44px', height: '44px', borderRadius: '14px',
                            background: user.isBanned ? '#FEF2F2' : '#EFF6FF',
                            display: 'flex', justifyContent: 'center', alignItems: 'center',
                            color: user.isBanned ? '#EF4444' : '#1D4ED8', fontSize: '18px', fontWeight: 700
                          }}>
                            {user.firstName?.charAt(0) || 'U'}
                          </div>
                          <div>
                            <div style={{ fontWeight: 800, fontSize: '15px' }}>{user.firstName} {user.lastName}</div>
                            <div style={{ fontSize: '13px', color: 'var(--text-muted)', fontWeight: 500 }}>{user.email}</div>
                          </div>
                        </div>
                      </td>
                      <td style={{ padding: '20px 24px' }}>
                        <span style={{
                          fontSize: '11px', padding: '6px 12px', borderRadius: '8px',
                          background: user.role === 'Owner' ? 'rgba(16, 185, 129, 0.1)' : 'var(--light-bg)',
                          color: user.role === 'Owner' ? 'var(--secondary)' : 'var(--text-muted)',
                          fontWeight: 800, textTransform: 'uppercase'
                        }}>
                          {user.role || 'Tourist'}
                        </span>
                      </td>
                      <td style={{ padding: '20px 24px' }}>
                        {user.isBanned ? (
                          <div>
                            <div style={{ color: '#EF4444', display: 'flex', alignItems: 'center', gap: '6px', fontSize: '13px', fontWeight: 700 }}>
                              <UserX size={16} /> Restricted
                            </div>
                            {user.banReason && (
                              <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '4px', maxWidth: '200px', lineHeight: 1.4 }}>
                                Reason: {user.banReason}
                              </div>
                            )}
                          </div>
                        ) : (
                          <div style={{ color: '#10B981', display: 'flex', alignItems: 'center', gap: '6px', fontSize: '13px', fontWeight: 700 }}>
                            <UserCheck size={16} /> Active
                          </div>
                        )}
                      </td>
                      <td style={{ padding: '20px 24px', textAlign: 'right' }}>
                        <div style={{ display: 'flex', gap: '8px', justifyContent: 'flex-end' }}>
                          <button
                            onClick={() => setSelectedUser(user)}
                            className="btn btn-secondary"
                            style={{ padding: '8px 16px', fontSize: '12px', borderRadius: '10px' }}
                          >
                            View Details
                          </button>
                          <button
                            onClick={() => openBanModal(user)}
                            className="btn"
                            style={{
                              display: 'inline-flex', padding: '8px 16px', fontSize: '12px',
                              background: user.isBanned ? '#ECFDF5' : '#FEF2F2',
                              color: user.isBanned ? '#047857' : '#B91C1C',
                              borderRadius: '10px'
                            }}
                          >
                            {user.isBanned ? 'Unban Account' : 'Restrict Access'}
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}

      {activeTab === 'reports' && (
        <div className="card" style={{ padding: 0, overflow: 'hidden', border: '1px solid var(--border)', boxShadow: 'var(--shadow)' }}>
          <div style={{ overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse' }}>
              <thead>
                <tr style={{ background: 'var(--light-bg)', borderBottom: '1px solid var(--border)', textAlign: 'left' }}>
                  <th style={{ padding: '20px 24px', fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', color: 'var(--text-muted)', letterSpacing: '1px' }}>Reported User</th>
                  <th style={{ padding: '20px 24px', fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', color: 'var(--text-muted)', letterSpacing: '1px' }}>Reason</th>
                  <th style={{ padding: '20px 24px', fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', color: 'var(--text-muted)', letterSpacing: '1px' }}>Status</th>
                  <th style={{ padding: '20px 24px', fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', color: 'var(--text-muted)', letterSpacing: '1px', textAlign: 'right' }}>Actions</th>
                </tr>
              </thead>
              <tbody>
                {reports.length === 0 && (
                  <tr><td colSpan="4" style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>No reports found.</td></tr>
                )}
                {reports.map(report => (
                  <tr key={report.id} style={{ borderBottom: '1px solid var(--border)' }} className="table-row">
                    <td style={{ padding: '20px 24px' }}>
                      <div style={{ fontWeight: 800, fontSize: '15px' }}>{report.reportedName || 'Unknown User'}</div>
                      <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>UID: {(report.reportedUid || '').substring(0, 12)}...</div>
                      <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '2px' }}>
                        Reported by: {report.reporterUid ? getReporterName(report.reporterUid) : 'Anonymous'}
                      </div>
                    </td>
                    <td style={{ padding: '20px 24px', maxWidth: '300px' }}>
                      <p style={{ margin: 0, fontSize: '14px', lineHeight: 1.5, color: 'var(--text-main)', fontStyle: 'italic' }}>"{report.reason}"</p>
                      {report.timestamp && (
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '6px' }}>
                          {new Date(report.timestamp).toLocaleString()}
                        </div>
                      )}
                    </td>
                    <td style={{ padding: '20px 24px', cursor: 'pointer' }} onClick={() => setSelectedReport(report)}>
                      {report.status === 'resolved' ? (
                        <span style={{ fontSize: '11px', padding: '4px 10px', borderRadius: '6px', background: 'rgba(16, 185, 129, 0.1)', color: 'var(--secondary)', fontWeight: 800, textTransform: 'uppercase', display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                          <CheckCircle size={12} /> Resolved
                        </span>
                      ) : (
                        <span style={{ fontSize: '11px', padding: '4px 10px', borderRadius: '6px', background: '#FEF2F2', color: '#EF4444', fontWeight: 800, textTransform: 'uppercase', display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                          <AlertTriangle size={12} /> Pending
                        </span>
                      )}
                    </td>
                    <td style={{ padding: '20px 24px', textAlign: 'right' }}>
                      <button
                        onClick={() => setSelectedReport(report)}
                        className="btn btn-secondary"
                        style={{ padding: '8px 16px', fontSize: '12px', borderRadius: '10px' }}
                      >
                        View Details
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {activeTab === 'verifications' && (
        <div className="card" style={{ padding: 0, overflow: 'hidden', border: '1px solid var(--border)', boxShadow: 'var(--shadow)' }}>
          <div style={{ overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse' }}>
              <thead>
                <tr style={{ background: 'var(--light-bg)', borderBottom: '1px solid var(--border)', textAlign: 'left' }}>
                  <th style={{ padding: '20px 24px', fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', color: 'var(--text-muted)' }}>User Details</th>
                  <th style={{ padding: '20px 24px', fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', color: 'var(--text-muted)' }}>ID Type</th>
                  <th style={{ padding: '20px 24px', fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', color: 'var(--text-muted)', textAlign: 'right' }}>Actions</th>
                </tr>
              </thead>
              <tbody>
                {users.filter(u => u.role !== 'Admin' && u.identityStatus === 'pending').length === 0 && (
                  <tr><td colSpan="3" style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>No pending verifications.</td></tr>
                )}
                {users.filter(u => u.role !== 'Admin' && u.identityStatus === 'pending').map(user => (
                  <tr key={user.id} style={{ borderBottom: '1px solid var(--border)' }} className="table-row">
                    <td style={{ padding: '20px 24px' }}>
                      <div style={{ fontWeight: 800, fontSize: '15px' }}>{user.firstName} {user.lastName}</div>
                      <div style={{ fontSize: '13px', color: 'var(--text-muted)' }}>{user.email}</div>
                    </td>
                    <td style={{ padding: '20px 24px', fontWeight: 600, fontSize: '13px', color: 'var(--text-main)' }}>
                      AI Pre-verified
                    </td>
                    <td style={{ padding: '20px 24px', textAlign: 'right' }}>
                      <button onClick={() => setVerificationModal(user)} className="btn btn-primary" style={{ padding: '8px 16px', fontSize: '12px', borderRadius: '10px' }}>
                        Review ID
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {activeTab === 'cms' && <AdminCMS />}

      {selectedUser && (
        <div className="modal-overlay" style={{ zIndex: 2500 }}>
          <div className="modal-content" style={{
            background: 'var(--surface)', borderRadius: '24px', maxWidth: '480px',
            width: '90%', padding: '32px 28px', position: 'relative',
            boxShadow: '0 24px 64px rgba(0,0,0,0.18)', maxHeight: '90vh', overflowY: 'auto'
          }}>
            <button onClick={() => setSelectedUser(null)} style={{
              position: 'absolute', top: '16px', right: '16px', background: 'var(--light-bg)',
              border: 'none', borderRadius: '50%', width: '32px', height: '32px',
              display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer'
            }}>
              <X size={16} />
            </button>

            <div style={{ display: 'flex', alignItems: 'center', gap: '16px', marginBottom: '24px' }}>
              <div style={{
                width: '60px', height: '60px', borderRadius: '16px', background: '#EFF6FF',
                display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
                color: '#1D4ED8', fontSize: '24px', fontWeight: 700, overflow: 'hidden'
              }}>
                {selectedUser.profilePicUrl ? (
                  <img src={selectedUser.profilePicUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                ) : (
                  selectedUser.firstName?.charAt(0) || 'U'
                )}
              </div>
              <div>
                <h3 style={{ margin: 0, fontSize: '22px', fontWeight: 800 }}>{selectedUser.firstName} {selectedUser.lastName}</h3>
                <div style={{ fontSize: '13px', color: 'var(--text-muted)', fontWeight: 500, marginTop: '2px' }}>
                  {selectedUser.email}
                </div>
                <span style={{
                  display: 'inline-block', fontSize: '11px', padding: '4px 8px', borderRadius: '6px',
                  background: selectedUser.role === 'Owner' ? 'rgba(16, 185, 129, 0.1)' : 'var(--light-bg)',
                  color: selectedUser.role === 'Owner' ? 'var(--secondary)' : 'var(--text-muted)',
                  fontWeight: 800, textTransform: 'uppercase', marginTop: '6px'
                }}>
                  {selectedUser.role || 'Tourist'}
                </span>
              </div>
            </div>

            <div style={{ background: 'var(--light-bg)', borderRadius: '16px', padding: '20px', marginBottom: '20px' }}>
              <h4 style={{ margin: '0 0 12px 0', fontSize: '14px', fontWeight: 700, color: 'var(--text-main)' }}>Verification Documents</h4>
              
              <div style={{ display: 'flex', gap: '16px' }}>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginBottom: '8px', fontWeight: 600 }}>Valid ID</div>
                  {selectedUser.idImageUrl ? (
                    <a href={selectedUser.idImageUrl} target="_blank" rel="noreferrer">
                      <img src={selectedUser.idImageUrl} alt="Valid ID" style={{ width: '100%', height: '120px', objectFit: 'cover', borderRadius: '12px', border: '1px solid var(--border)' }} />
                    </a>
                  ) : (
                    <div style={{ width: '100%', height: '120px', background: 'var(--surface)', borderRadius: '12px', border: '1px dashed var(--border)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-muted)', fontSize: '12px' }}>Not Uploaded</div>
                  )}
                </div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginBottom: '8px', fontWeight: 600 }}>Selfie</div>
                  {selectedUser.selfieUrl ? (
                    <a href={selectedUser.selfieUrl} target="_blank" rel="noreferrer">
                      <img src={selectedUser.selfieUrl} alt="Selfie" style={{ width: '100%', height: '120px', objectFit: 'cover', borderRadius: '12px', border: '1px solid var(--border)' }} />
                    </a>
                  ) : (
                    <div style={{ width: '100%', height: '120px', background: 'var(--surface)', borderRadius: '12px', border: '1px dashed var(--border)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-muted)', fontSize: '12px' }}>Not Uploaded</div>
                  )}
                </div>
              </div>

              <div style={{ marginTop: '16px', paddingTop: '16px', borderTop: '1px solid var(--border)' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <span style={{ fontSize: '13px', color: 'var(--text-muted)', fontWeight: 600 }}>Identity Status</span>
                  <span style={{ fontSize: '13px', fontWeight: 700, textTransform: 'capitalize', color: selectedUser.identityStatus === 'verified' ? '#10B981' : (selectedUser.identityStatus === 'rejected' ? '#EF4444' : 'var(--text-main)') }}>
                    {selectedUser.identityStatus || 'Not Submitted'}
                  </span>
                </div>
              </div>
            </div>

            <div style={{ display: 'grid', gap: '10px' }}>
              {[
                ['Phone Number', selectedUser.phone || 'N/A', <Phone size={16} />],
                ['Joined Date', selectedUser.createdAt ? new Date(selectedUser.createdAt).toLocaleDateString() : 'Unknown', <Calendar size={16} />],
                ['Warnings', `${selectedUser.warningCount || 0} / 3`, <AlertTriangle size={16} />]
              ].map(([label, val, icon]) => (
                <div key={label} style={{
                  display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                  padding: '12px 16px', border: '1px solid var(--border)', borderRadius: '12px'
                }}>
                  <span style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '13px', color: 'var(--text-muted)', fontWeight: 600 }}>
                    {icon} {label}
                  </span>
                  <span style={{ fontSize: '13px', fontWeight: 600, color: 'var(--text-main)' }}>{val}</span>
                </div>
              ))}
            </div>

            <div style={{ marginTop: '24px' }}>
              <button
                className="btn btn-secondary"
                style={{ width: '100%', padding: '12px' }}
                onClick={() => setSelectedUser(null)}
              >
                Close Details
              </button>
            </div>
          </div>
        </div>
      )}

      {selectedReport && !chatOpen && (
        <div className="modal-overlay" style={{ zIndex: 2500 }}>
          <div className="modal-content" style={{
            background: 'var(--surface)', borderRadius: '24px', maxWidth: '480px',
            width: '90%', padding: '32px 28px', position: 'relative',
            boxShadow: '0 24px 64px rgba(0,0,0,0.18)'
          }}>
            <button onClick={() => { setSelectedReport(null); setChatMessages([]); }} style={{
              position: 'absolute', top: '16px', right: '16px', background: 'var(--light-bg)',
              border: 'none', borderRadius: '50%', width: '32px', height: '32px',
              display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer'
            }}>
              <X size={16} />
            </button>

            <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '20px' }}>
              <div style={{
                width: '48px', height: '48px', borderRadius: '50%', background: '#FEF2F2',
                display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0
              }}>
                <AlertTriangle size={24} color="#EF4444" />
              </div>
              <div>
                <h3 style={{ margin: 0, fontSize: '20px', fontWeight: 800 }}>Report Details</h3>
                <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '2px' }}>
                  {selectedReport.timestamp ? new Date(selectedReport.timestamp).toLocaleString() : 'Unknown date'}
                </div>
              </div>
            </div>

            {[
              ['Reported User', selectedReport.reportedName || selectedReport.reportedUid],
              ['Reporter', getReporterName(selectedReport.reporterUid)],
              ['Status', selectedReport.status],
            ].map(([label, val]) => (
              <div key={label} style={{
                display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                padding: '10px 0', borderBottom: '1px solid var(--border)'
              }}>
                <span style={{ fontSize: '13px', color: 'var(--text-muted)', fontWeight: 700 }}>{label}</span>
                <span style={{ fontSize: '13px', fontWeight: 600, textTransform: label === 'Status' ? 'capitalize' : 'none' }}>{val}</span>
              </div>
            ))}

            <div style={{
              background: 'var(--light-bg)', borderRadius: '12px', padding: '14px 16px',
              marginTop: '16px', marginBottom: '20px'
            }}>
              <div style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase', letterSpacing: '1px', color: 'var(--text-muted)', marginBottom: '6px' }}>Reason</div>
              <p style={{ margin: 0, fontSize: '14px', lineHeight: 1.6, fontStyle: 'italic', color: 'var(--text-main)' }}>"{selectedReport.reason}"</p>
            </div>

            <div style={{ display: 'flex', gap: '10px', flexDirection: 'column' }}>
              <button
                className="btn btn-primary"
                style={{ width: '100%', padding: '12px' }}
                onClick={() => setChatOpen(true)}
              >
                View Chat History
              </button>
              {selectedReport.status === 'pending' && (
                <button
                  className="btn"
                  style={{ width: '100%', padding: '12px', background: 'linear-gradient(135deg, #10B981, #059669)', color: 'white' }}
                  onClick={() => { openResolveModal(selectedReport); setSelectedReport(null); }}
                >
                  Mark as Resolved
                </button>
              )}
              <button
                className="btn btn-secondary"
                style={{ width: '100%', padding: '12px' }}
                onClick={() => { setSelectedReport(null); setChatMessages([]); }}
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}

      {selectedReport && chatOpen && (
        <div className="modal-overlay" style={{ zIndex: 2600, background: 'rgba(0,0,0,0.65)', backdropFilter: 'blur(4px)' }}>
          <div className="modal-content" style={{
            background: 'var(--surface)', borderRadius: '28px', maxWidth: '600px',
            width: '95%', height: '85vh', display: 'flex', flexDirection: 'column',
            padding: '0', position: 'relative', overflow: 'hidden',
            boxShadow: '0 32px 80px rgba(0,0,0,0.3)'
          }}>
            {/* Real Chat-like Header */}
            <div style={{
              padding: '16px 24px',
              borderBottom: '1px solid var(--border)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              background: 'var(--surface)',
              flexShrink: 0
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
                <button onClick={() => setChatOpen(false)} style={{
                  background: 'var(--light-bg)', border: '1px solid var(--border)', width: '36px', height: '36px',
                  borderRadius: '12px', display: 'flex', alignItems: 'center', justifyContent: 'center',
                  cursor: 'pointer', color: 'var(--text-main)'
                }}>
                  <ArrowLeft size={20} />
                </button>

                <div style={{ position: 'relative' }}>
                  <div style={{
                    width: '48px', height: '48px', borderRadius: '16px',
                    background: 'var(--light-bg)',
                    overflow: 'hidden',
                    display: 'flex', justifyContent: 'center', alignItems: 'center',
                    color: 'var(--text-muted)', border: '2px solid var(--border)', boxShadow: '0 4px 12px rgba(0,0,0,0.05)'
                  }}>
                    {reportedPhoto ? (
                      <img src={reportedPhoto} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                    ) : (
                      <User size={24} />
                    )}
                  </div>
                  <div style={{
                    position: 'absolute', bottom: '-2px', right: '-2px',
                    width: '14px', height: '14px', background: '#10B981',
                    borderRadius: '50%', border: '2px solid white'
                  }}></div>
                </div>

                <div>
                  <h4 style={{ margin: 0, fontSize: '16px', fontWeight: 800, color: 'var(--text-main)', display: 'flex', alignItems: 'center', gap: '6px' }}>
                    {selectedReport.reportedName || 'Reported User'}
                    <ShieldCheck size={14} color="var(--secondary)" />
                  </h4>
                  <span style={{ fontSize: '12px', color: 'var(--secondary)', fontWeight: 700 }}>Online</span>
                </div>
              </div>

              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end' }}>
                  <span style={{ fontSize: '10px', textTransform: 'uppercase', fontWeight: 800, color: 'var(--primary)', background: 'var(--primary-soft)', padding: '2px 8px', borderRadius: '6px' }}>Admin Chat Monitor</span>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '2px' }}>Reporter: {selectedReport.reporterName || 'Tourist'}</span>
                </div>
              </div>
            </div>

            {/* Real Chat-like Messages Area */}
            <div style={{
              flex: 1,
              overflowY: 'auto',
              padding: '24px',
              display: 'flex',
              flexDirection: 'column',
              gap: '16px',
              background: 'var(--light-bg)'
            }}>
              {chatLoading ? (
                <div style={{ textAlign: 'center', margin: 'auto', color: 'var(--text-muted)' }}>Loading chat transcript...</div>
              ) : chatMessages.length === 0 ? (
                <div style={{ textAlign: 'center', margin: 'auto', opacity: 0.5 }}>
                  <div style={{ background: 'var(--surface)', padding: '20px', borderRadius: '24px', display: 'inline-block', boxShadow: '0 4px 20px rgba(0,0,0,0.02)', border: '1px solid var(--border)' }}>
                    <p style={{ margin: 0, fontSize: '13px', fontWeight: 600 }}>No chat messages found between these parties.</p>
                  </div>
                </div>
              ) : (
                chatMessages.map((msg) => {
                  const isReporter = msg.senderUid === selectedReport.reporterUid;
                  const showTime = true;

                  const formatMessageTime = (ts) => {
                    if (!ts) return '';
                    const d = new Date(ts);
                    if (isToday(d)) return format(d, 'p');
                    if (isThisYear(d)) return format(d, 'MMM d, p');
                    return format(d, 'MMM d, yyyy, p');
                  };

                  return (
                    <div key={msg.id} style={{
                      alignSelf: isReporter ? 'flex-start' : 'flex-end',
                      maxWidth: '85%',
                      display: 'flex',
                      gap: '12px',
                      flexDirection: isReporter ? 'row' : 'row-reverse',
                      alignItems: 'flex-end'
                    }}>
                      {/* Avatar next to message */}
                      <div style={{
                        width: '32px', height: '32px', borderRadius: '10px',
                        background: 'var(--light-bg)', overflow: 'hidden',
                        flexShrink: 0, display: 'flex', justifyContent: 'center', alignItems: 'center',
                        boxShadow: '0 2px 5px rgba(0,0,0,0.05)', marginBottom: showTime ? '18px' : '0'
                      }}>
                        {isReporter ? (
                          reporterPhoto ? <img src={reporterPhoto} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : <User size={16} color="#9CA3AF" />
                        ) : (
                          reportedPhoto ? <img src={reportedPhoto} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : <User size={16} color="#9CA3AF" />
                        )}
                      </div>

                      <div style={{
                        display: 'flex',
                        flexDirection: 'column',
                        alignItems: isReporter ? 'flex-start' : 'flex-end'
                      }}>
                        <div style={{
                          padding: '12px 18px',
                          borderRadius: isReporter ? '20px 20px 20px 4px' : '20px 20px 4px 20px',
                          background: isReporter ? 'var(--surface)' : 'linear-gradient(135deg, var(--primary), #FF5F6D)',
                          color: isReporter ? 'var(--text-main)' : 'white',
                          fontSize: '15px',
                          fontWeight: 500,
                          boxShadow: isReporter ? '0 2px 8px rgba(0,0,0,0.03)' : '0 4px 15px rgba(251, 54, 64, 0.2)',
                          lineHeight: '1.5',
                          border: isReporter ? '1px solid var(--border)' : 'none',
                          wordBreak: 'break-word'
                        }}>
                          {msg.decryptedText || msg.text || ''}
                        </div>
                        {showTime && msg.timestamp && (
                          <div style={{ display: 'flex', alignItems: 'center', gap: '4px', marginTop: '4px' }}>
                            <span style={{ fontSize: '10px', color: 'var(--text-muted)', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                              {formatMessageTime(msg.timestamp)}
                            </span>
                            {!isReporter && (
                              <CheckCheck size={14} color="#3B82F6" />
                            )}
                          </div>
                        )}
                      </div>
                    </div>
                  );
                })
              )}
            </div>

            {/* Real Chat-like Input Area (Disabled / Monitor Mode) */}
            <div style={{ padding: '20px 24px', background: 'var(--surface)', borderTop: '1px solid var(--border)' }}>
              <div style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
                <div style={{ flex: 1, position: 'relative' }}>
                  <input
                    type="text"
                    disabled
                    placeholder="Read-only monitor mode... cannot send messages."
                    style={{
                      width: '100%', padding: '14px 20px', borderRadius: '18px', border: '2px solid var(--border)',
                      background: 'var(--light-bg)', color: 'var(--text-muted)', fontFamily: 'inherit', fontSize: '15px',
                      fontWeight: 500, cursor: 'not-allowed'
                    }}
                  />
                </div>
                <button
                  disabled
                  style={{
                    width: '52px', height: '52px', borderRadius: '18px', border: '1px solid var(--border)',
                    background: 'var(--light-bg)', color: 'var(--text-muted)', display: 'flex', justifyContent: 'center',
                    alignItems: 'center', cursor: 'not-allowed'
                  }}
                >
                  <Send size={22} />
                </button>
              </div>
            </div>

            {/* Modal Actions Footer */}
            <div style={{ padding: '16px 24px', borderTop: '1px solid var(--border)', background: 'var(--surface)', flexShrink: 0 }}>
              <button
                className="btn btn-secondary"
                style={{ width: '100%', padding: '12px', borderRadius: '14px', fontWeight: 700 }}
                onClick={() => setChatOpen(false)}
              >
                ← Back to Report Details
              </button>
            </div>
          </div>
        </div>
      )}

      {banModal && (
        <div className="modal-overlay" style={{ zIndex: 2000 }}>
          <div className="modal-content" style={{ background: 'var(--surface)', borderRadius: '24px', maxWidth: '420px', width: '90%', padding: '32px 28px', textAlign: 'center' }}>
            <div style={{
              width: '64px', height: '64px', borderRadius: '50%', margin: '0 auto 16px',
              display: 'flex', justifyContent: 'center', alignItems: 'center',
              background: banModal.isBanned ? 'rgba(16, 185, 129, 0.1)' : '#FEF2F2'
            }}>
              {banModal.isBanned ? <UserCheck size={32} color="#10B981" /> : <UserX size={32} color="#EF4444" />}
            </div>
            <h3 style={{ margin: '0 0 8px 0', fontSize: '20px', fontWeight: 800 }}>
              {banModal.isBanned ? 'Unban Account?' : 'Restrict Access?'}
            </h3>
            <p style={{ color: 'var(--text-muted)', fontSize: '14px', marginBottom: '20px' }}>
              {banModal.isBanned
                ? `Are you sure you want to restore access for ${banModal.firstName || 'this user'}? They will be able to use the platform again.`
                : `Are you sure you want to restrict ${banModal.firstName || 'this user'}? They will not be able to log in or use the platform.`
              }
            </p>
            {!banModal.isBanned && (
              <div style={{ textAlign: 'left', marginBottom: '20px' }}>
                <label style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase', letterSpacing: '1px', color: 'var(--text-muted)', display: 'block', marginBottom: '8px' }}>
                  Reason for Restriction *
                </label>
                <textarea
                  className="input"
                  rows={3}
                  placeholder="e.g., Violation of terms of service, inappropriate conduct..."
                  value={banReason}
                  onChange={(e) => { setBanReason(e.target.value); if (banError) setBanError(''); }}
                  style={{ width: '100%', resize: 'none' }}
                />
              </div>
            )}
            {banError && (
              <div style={{ background: '#FEF2F2', color: '#B91C1C', padding: '10px 14px', borderRadius: '12px', fontSize: '13px', fontWeight: 700, marginBottom: '16px', border: '1px solid #FEE2E2' }}>
                {banError}
              </div>
            )}
            <div style={{ display: 'flex', gap: '12px' }}>
              <button className="btn btn-secondary" style={{ flex: 1 }} onClick={() => { setBanModal(null); setBanReason(''); setBanError(''); }}>
                Cancel
              </button>
              <button
                className="btn"
                disabled={banLoading}
                style={{
                  flex: 1,
                  background: banModal.isBanned ? 'linear-gradient(135deg, #10B981, #059669)' : 'linear-gradient(135deg, #EF4444, #DC2626)',
                  color: 'white', opacity: banLoading ? 0.7 : 1
                }}
                onClick={confirmBan}
              >
                {banLoading ? 'Processing...' : (banModal.isBanned ? 'Unban Account' : 'Restrict Access')}
              </button>
            </div>
            <button onClick={() => { setBanModal(null); setBanReason(''); setBanError(''); }} style={{ position: 'absolute', top: '16px', right: '16px', background: 'var(--light-bg)', border: 'none', borderRadius: '50%', width: '32px', height: '32px', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <X size={16} color="var(--text-muted)" />
            </button>
          </div>
        </div>
      )}

      {/* Resolve Report Modal */}
      {resolveModal && (
        <div className="modal-overlay" style={{ zIndex: 2000 }}>
          <div className="modal-content" style={{ background: 'var(--surface)', borderRadius: '24px', maxWidth: '400px', width: '90%', padding: '32px 28px', textAlign: 'center' }}>
            <div style={{ width: '64px', height: '64px', borderRadius: '50%', margin: '0 auto 16px', display: 'flex', justifyContent: 'center', alignItems: 'center', background: 'rgba(16, 185, 129, 0.1)' }}>
              <CheckCircle size={32} color="#10B981" />
            </div>
            <h3 style={{ margin: '0 0 8px 0', fontSize: '20px', fontWeight: 800 }}>Resolve Report Action</h3>
            <p style={{ color: 'var(--text-muted)', fontSize: '14px', marginBottom: '16px' }}>
              Select an action to take before resolving this report.
            </p>
            <div style={{ background: 'var(--light-bg)', borderRadius: '12px', padding: '12px 16px', marginBottom: '16px', textAlign: 'left' }}>
              <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 700, marginBottom: '4px' }}>Report against: <span style={{ color: 'var(--text-main)' }}>{resolveModal.reportedName || resolveModal.reportedUid}</span></div>
              <div style={{ fontSize: '13px', color: 'var(--text-main)', fontStyle: 'italic' }}>"{resolveModal.reason}"</div>
            </div>

            <div style={{ textAlign: 'left', marginBottom: '24px' }}>
              <select className="input" value={resolveAction} onChange={(e) => setResolveAction(e.target.value)} style={{ width: '100%', marginBottom: '12px' }}>
                <option value="dismiss">Dismiss / No Action</option>
                <option value="warn_reported">Warn Reported User</option>
                <option value="ban_reported">Ban Reported User</option>
                <option value="warn_reporter">Warn Reporter (False Report)</option>
              </select>

              {resolveAction !== 'dismiss' && (
                <textarea 
                  className="input" 
                  placeholder={resolveAction === 'ban_reported' ? "Reason for banning..." : "Message for warning..."}
                  rows={3} 
                  style={{ width: '100%', resize: 'none' }}
                  value={resolveMessage}
                  onChange={(e) => setResolveMessage(e.target.value)}
                />
              )}
            </div>

            <div style={{ display: 'flex', gap: '12px' }}>
              <button className="btn btn-secondary" style={{ flex: 1 }} onClick={() => setResolveModal(null)}>Cancel</button>
              <button className="btn" disabled={resolveLoading} style={{ flex: 1, background: 'linear-gradient(135deg, #10B981, #059669)', color: 'white', opacity: resolveLoading ? 0.7 : 1 }} onClick={confirmResolve}>
                {resolveLoading ? 'Processing...' : 'Confirm Action'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Verification Modal */}
      {verificationModal && (
        <div className="modal-overlay" style={{ zIndex: 3000 }}>
          <div className="modal-content" style={{
            background: 'var(--surface)', borderRadius: '24px', maxWidth: '600px',
            width: '95%', padding: '0', position: 'relative',
            maxHeight: '90vh', overflowY: 'auto', overflowX: 'hidden', boxShadow: '0 20px 60px rgba(0,0,0,0.3)'
          }}>
            <div style={{ position: 'sticky', top: 0, background: 'var(--surface)', zIndex: 10, padding: '24px 28px', borderBottom: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                <div style={{ width: '44px', height: '44px', borderRadius: '12px', background: 'var(--primary)', color: 'white', display: 'flex', justifyContent: 'center', alignItems: 'center', boxShadow: '0 4px 12px rgba(0,0,0,0.15)' }}>
                  <ShieldCheck size={22} />
                </div>
                <div>
                  <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800, color: 'var(--text-main)' }}>Registration Review</h3>
                  <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 500, marginTop: '2px' }}>Identity Verification Request</div>
                </div>
              </div>
              <button onClick={() => setVerificationModal(null)} style={{ background: 'var(--light-bg)', border: 'none', borderRadius: '50%', width: '36px', height: '36px', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', transition: 'var(--transition)' }}>
                <X size={18} color="var(--text-muted)" />
              </button>
            </div>
            
            <div style={{ padding: '28px' }}>
              <div style={{ marginBottom: '28px' }}>
                <h4 style={{ margin: '0 0 16px 0', fontSize: '13px', textTransform: 'uppercase', letterSpacing: '1px', color: 'var(--text-muted)', fontWeight: 800 }}>Applicant Details</h4>
                <div style={{ background: 'var(--light-bg)', border: '1px solid var(--border)', borderRadius: '16px', padding: '20px' }}>
                  <div style={{ display: 'flex', alignItems: 'flex-start', gap: '16px', marginBottom: '20px', paddingBottom: '20px', borderBottom: '1px dashed var(--border)' }}>
                    <div style={{ width: '56px', height: '56px', borderRadius: '50%', background: 'linear-gradient(135deg, var(--primary), var(--secondary))', display: 'flex', justifyContent: 'center', alignItems: 'center', color: 'white', fontSize: '20px', fontWeight: 800, textTransform: 'uppercase', boxShadow: '0 4px 12px rgba(0,0,0,0.1)' }}>
                      {verificationModal.firstName?.[0]}{verificationModal.lastName?.[0]}
                    </div>
                    <div style={{ flex: 1 }}>
                      <div style={{ fontSize: '18px', fontWeight: 800, color: 'var(--text-main)', marginBottom: '6px' }}>
                        {verificationModal.firstName} {verificationModal.middleName ? verificationModal.middleName + ' ' : ''}{verificationModal.lastName}
                      </div>
                      <div style={{ display: 'flex', gap: '16px', flexWrap: 'wrap' }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '13px', color: 'var(--text-muted)', fontWeight: 500 }}>
                          <Mail size={14} /> {verificationModal.email}
                        </div>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '13px', color: 'var(--text-muted)', fontWeight: 500 }}>
                          <Phone size={14} /> {verificationModal.phoneNumber || 'Not provided'}
                        </div>
                      </div>
                    </div>
                  </div>
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
                    <div>
                      <div style={{ fontSize: '11px', color: 'var(--text-muted)', textTransform: 'uppercase', fontWeight: 800, marginBottom: '6px' }}>Account Role</div>
                      <div style={{ fontSize: '13px', fontWeight: 700, color: 'var(--text-main)' }}>
                        <span style={{ padding: '6px 12px', background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: '8px', fontSize: '12px' }}>{verificationModal.role || 'Tourist'}</span>
                      </div>
                    </div>
                    <div>
                      <div style={{ fontSize: '11px', color: 'var(--text-muted)', textTransform: 'uppercase', fontWeight: 800, marginBottom: '6px' }}>Joined Date</div>
                      <div style={{ fontSize: '14px', fontWeight: 600, color: 'var(--text-main)', display: 'flex', alignItems: 'center', gap: '6px', marginTop: '4px' }}>
                        <Calendar size={15} color="var(--primary)" /> {verificationModal.createdAt ? new Date(verificationModal.createdAt).toLocaleDateString() : 'Unknown'}
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <div style={{ marginBottom: '36px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
                  <h4 style={{ margin: 0, fontSize: '13px', textTransform: 'uppercase', letterSpacing: '1px', color: 'var(--text-muted)', fontWeight: 800 }}>Identity Documents</h4>
                  <div style={{ padding: '6px 14px', background: 'rgba(59, 130, 246, 0.1)', color: '#3B82F6', borderRadius: '20px', fontSize: '12px', fontWeight: 800 }}>
                    AI PRE-VERIFIED
                  </div>
                </div>
                
                <div style={{ display: 'flex', gap: '16px', overflowX: 'auto', paddingBottom: '16px' }}>
                  <div style={{ flex: 1, minWidth: '250px', background: 'var(--card-bg)', border: '2px solid var(--border)', borderRadius: '20px', overflow: 'hidden', minHeight: '260px', display: 'flex', justifyContent: 'center', alignItems: 'center', position: 'relative', boxShadow: 'inset 0 4px 20px rgba(0,0,0,0.02)' }}>
                    {verificationModal.idImageUrl ? (
                      <img src={verificationModal.idImageUrl} alt="Valid ID" style={{ width: '100%', height: '100%', maxHeight: '400px', objectFit: 'contain', background: '#0a0a0a' }} />
                    ) : (
                      <div style={{ color: 'var(--text-muted)', textAlign: 'center', padding: '40px' }}>
                        <div style={{ width: '64px', height: '64px', borderRadius: '50%', background: 'var(--light-bg)', display: 'flex', justifyContent: 'center', alignItems: 'center', margin: '0 auto 16px' }}>
                          <ShieldCheck size={32} style={{ opacity: 0.5 }} />
                        </div>
                        <p style={{ fontWeight: 600 }}>No ID image</p>
                      </div>
                    )}
                  </div>

                  <div style={{ flex: 1, minWidth: '250px', background: 'var(--card-bg)', border: '2px solid var(--border)', borderRadius: '20px', overflow: 'hidden', minHeight: '260px', display: 'flex', justifyContent: 'center', alignItems: 'center', position: 'relative', boxShadow: 'inset 0 4px 20px rgba(0,0,0,0.02)' }}>
                    {verificationModal.selfieUrl ? (
                      <img src={verificationModal.selfieUrl} alt="Selfie" style={{ width: '100%', height: '100%', maxHeight: '400px', objectFit: 'contain', background: '#0a0a0a' }} />
                    ) : (
                      <div style={{ color: 'var(--text-muted)', textAlign: 'center', padding: '40px' }}>
                        <div style={{ width: '64px', height: '64px', borderRadius: '50%', background: 'var(--light-bg)', display: 'flex', justifyContent: 'center', alignItems: 'center', margin: '0 auto 16px' }}>
                          <User size={32} style={{ opacity: 0.5 }} />
                        </div>
                        <p style={{ fontWeight: 600 }}>No selfie image</p>
                      </div>
                    )}
                  </div>
                </div>
              </div>

              <div style={{ display: 'flex', gap: '16px' }}>
                <button 
                  className="btn btn-secondary" 
                  disabled={verificationLoading}
                  style={{ flex: 1, padding: '16px', color: '#EF4444', borderColor: '#FEE2E2', background: '#FEF2F2', fontSize: '15px', fontWeight: 800, borderRadius: '16px' }} 
                  onClick={() => confirmVerification(false)}
                >
                  <span style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px' }}>
                    <X size={18} /> Reject Verification
                  </span>
                </button>
                <button 
                  className="btn btn-primary" 
                  disabled={verificationLoading}
                  style={{ flex: 1, padding: '16px', fontSize: '15px', fontWeight: 800, borderRadius: '16px', background: 'linear-gradient(135deg, #10B981, #059669)', border: 'none', color: 'white', boxShadow: '0 8px 20px rgba(16, 185, 129, 0.25)' }} 
                  onClick={() => confirmVerification(true)}
                >
                  {verificationLoading ? 'Processing...' : (
                    <span style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px' }}>
                      <CheckCircle size={18} /> Approve User
                    </span>
                  )}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      <style>{`
        .table-row:hover { background: var(--card-hover-bg); }
        .view-transition { animation: fadeIn 0.4s ease-out; }
        .stat-card { transition: transform 0.2s, box-shadow 0.2s; }
        .stat-card[style*="cursor: pointer"]:hover { transform: translateY(-4px); box-shadow: 0 12px 24px rgba(0,0,0,0.1); }
      `}</style>
    </div>
  );
};

const StatItem = ({ icon, label, value, bgGradient, onClick }) => (
  <div className="card stat-card" onClick={onClick} style={{ margin: 0, padding: '24px', display: 'flex', flexDirection: 'column', alignItems: 'flex-start', border: '1px solid var(--border)', boxShadow: 'var(--shadow)', background: 'var(--surface)', cursor: onClick ? 'pointer' : 'default' }}>
    <div style={{ background: bgGradient, padding: '14px', borderRadius: '18px', display: 'inline-flex', marginBottom: '14px' }}>{icon}</div>
    <div style={{ fontSize: '32px', fontWeight: 900, letterSpacing: '-1px' }}>{value}</div>
    <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.5px', marginTop: '2px' }}>{label}</div>
  </div>
);

export default AdminDashboard;
