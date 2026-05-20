import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, onValue, update } from 'firebase/database';
import { Shield, User, UserX, UserCheck, Search, Users, Activity, ExternalLink } from 'lucide-react';

const AdminDashboard = ({ profile, uid }) => {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');

  useEffect(() => {
    const usersRef = ref(db, 'users');
    const unsubscribe = onValue(usersRef, (snapshot) => {
      const data = snapshot.val();
      if (data) {
        const list = Object.entries(data)
          .map(([id, val]) => ({ id, ...val }))
          .filter(u => u.id !== uid); // Don't show current admin in list
        setUsers(list);
      }
      setLoading(false);
    });

    return () => unsubscribe();
  }, [uid]);

  const toggleBan = async (user) => {
    const newStatus = !user.isBanned;
    if (window.confirm(`${newStatus ? 'Ban' : 'Unban'} ${user.firstName} ${user.lastName}?`)) {
      await update(ref(db, `users/${user.id}`), {
        isBanned: newStatus
      });
    }
  };

  const filteredUsers = users.filter(u =>
    `${u.firstName} ${u.lastName}`.toLowerCase().includes(searchQuery.toLowerCase()) ||
    u.email?.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const stats = {
    total: users.length,
    active: users.filter(u => !u.isBanned).length,
    banned: users.filter(u => u.isBanned).length,
    owners: users.filter(u => u.role === 'Owner').length
  };

  if (loading) return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '60vh' }}>
      <div className="loader"></div>
    </div>
  );

  return (
    <div className="view-transition">
      <div className="card" style={{
        background: 'linear-gradient(135deg, var(--primary), #FF5F6D)',
        color: 'white',
        marginBottom: '40px',
        padding: '40px',
        border: 'none',
        position: 'relative',
        overflow: 'hidden'
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
         <StatItem icon={<Users color="var(--secondary)" />} label="Total Users" value={stats.total} />
         <StatItem icon={<UserCheck color="#10B981" />} label="Active Accounts" value={stats.active} />
         <StatItem icon={<UserX color="#EF4444" />} label="Suspended" value={stats.banned} />
         <StatItem icon={<Shield color="#3B82F6" />} label="Resort Partners" value={stats.owners} />
      </div>

      <div style={{ marginBottom: '32px', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', flexWrap: 'wrap', gap: '20px' }}>
        <div>
           <h3 style={{ margin: 0, fontSize: '24px', fontWeight: 800 }}>Member Directory</h3>
           <p style={{ color: 'var(--text-muted)', margin: '4px 0 0 0', fontSize: '14px' }}>Review and manage user access permissions.</p>
        </div>
        <div style={{ position: 'relative', minWidth: '300px' }}>
          <Search style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} size={18} />
          <input
            type="text"
            placeholder="Search by name or email..."
            className="input"
            style={{ paddingLeft: '48px', height: '48px', borderRadius: '14px' }}
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
        </div>
      </div>

      <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
        <div style={{ overflowX: 'auto' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ background: 'var(--light-bg)', borderBottom: '1px solid var(--border)', textAlign: 'left' }}>
                <th style={{ padding: '20px 24px', fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', color: 'var(--text-muted)', letterSpacing: '1px' }}>Account</th>
                <th style={{ padding: '20px 24px', fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', color: 'var(--text-muted)', letterSpacing: '1px' }}>Type</th>
                <th style={{ padding: '20px 24px', fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', color: 'var(--text-muted)', letterSpacing: '1px' }}>Status</th>
                <th style={{ padding: '20px 24px', fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', color: 'var(--text-muted)', letterSpacing: '1px', textAlign: 'right' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {filteredUsers.map(user => (
                <tr key={user.id} style={{ borderBottom: '1px solid var(--border)' }} className="table-row">
                  <td style={{ padding: '20px 24px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
                      <div style={{
                        width: '44px', height: '44px', borderRadius: '14px',
                        background: user.isBanned ? '#FEF2F2' : '#EFF6FF',
                        display: 'flex', justifyContent: 'center', alignItems: 'center',
                        color: user.isBanned ? '#EF4444' : '#1D4ED8',
                        fontSize: '18px', fontWeight: 700
                      }}>
                        {user.firstName?.charAt(0)}
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
                      <div style={{ color: '#EF4444', display: 'flex', alignItems: 'center', gap: '6px', fontSize: '13px', fontWeight: 700 }}>
                        <UserX size={16} /> Restricted
                      </div>
                    ) : (
                      <div style={{ color: '#10B981', display: 'flex', alignItems: 'center', gap: '6px', fontSize: '13px', fontWeight: 700 }}>
                        <UserCheck size={16} /> Active
                      </div>
                    )}
                  </td>
                  <td style={{ padding: '20px 24px', textAlign: 'right' }}>
                    <button
                      onClick={() => toggleBan(user)}
                      className="btn"
                      style={{
                        display: 'inline-flex', padding: '8px 16px', fontSize: '12px',
                        background: user.isBanned ? '#ECFDF5' : '#FEF2F2',
                        color: user.isBanned ? '#047857' : '#B91C1C',
                        borderRadius: '10px', marginLeft: 'auto'
                      }}
                    >
                      {user.isBanned ? 'Unban Account' : 'Restrict Access'}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      <style>{`
        .table-row:hover { background: var(--card-hover-bg); }
        .view-transition { animation: fadeIn 0.4s ease-out; }
      `}</style>
    </div>
  );
};

const StatItem = ({ icon, label, value }) => (
  <div className="card" style={{ margin: 0, padding: '24px', display: 'flex', alignItems: 'center', gap: '20px' }}>
     <div style={{ background: 'var(--light-bg)', padding: '12px', borderRadius: '16px' }}>{icon}</div>
     <div>
        <p style={{ margin: 0, fontSize: '12px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.5px' }}>{label}</p>
        <h4 style={{ margin: '4px 0 0 0', fontSize: '24px', fontWeight: 800 }}>{value}</h4>
     </div>
  </div>
);

export default AdminDashboard;
