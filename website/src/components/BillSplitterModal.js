import React, { useState } from 'react';
import { X, Users, Split, Copy, Check, Plus, Trash2, QrCode } from 'lucide-react';
import { QRCodeSVG } from 'qrcode.react';

const BillSplitterModal = ({ onClose, initialAmount = 0, resortGCash = null, addons = [] }) => {
  const [totalBill, setTotalBill] = useState(initialAmount || '');
  const [people, setPeople] = useState(2);
  const [mode, setMode] = useState('equal'); // 'equal' | 'itemized' | 'percentage'
  const [items, setItems] = useState([{ name: '', amount: '', assignedTo: 'Friend 1' }]);
  const [percentShares, setPercentShares] = useState([{ name: 'Friend 1', percent: '60' }, { name: 'Friend 2', percent: '40' }]);
  const [copied, setCopied] = useState(false);
  const [showQR, setShowQR] = useState(false);
  const [paymentInfo, setPaymentInfo] = useState('');

  const parsedTotal = parseFloat(String(totalBill).replace(/,/g, '')) || 0;
  const perPerson = people > 0 ? parsedTotal / people : 0;

  const itemizedTotal = items.reduce((sum, i) => sum + (parseFloat(i.amount) || 0), 0);
  const itemizedPerPerson = people > 0 ? itemizedTotal / people : 0;

  const displayTotal = mode === 'itemized' ? itemizedTotal : parsedTotal;

  const addItem = () => setItems([...items, { name: '', amount: '', assignedTo: `Friend ${items.length + 1}` }]);
  const removeItem = (i) => setItems(items.filter((_, idx) => idx !== i));
  const updateItem = (i, key, val) => setItems(items.map((item, idx) => idx === i ? { ...item, [key]: val } : item));

  const addPercentShare = () => setPercentShares([...percentShares, { name: `Friend ${percentShares.length + 1}`, percent: '' }]);
  const removePercentShare = (i) => setPercentShares(percentShares.filter((_, idx) => idx !== i));
  const updatePercentShare = (i, key, val) => setPercentShares(percentShares.map((item, idx) => idx === i ? { ...item, [key]: val } : item));

  const getSummaryText = () => {
    let txt = `💰 Bill Split Summary\nTotal: ₱${displayTotal.toLocaleString()}\n\n`;
    if (mode === 'equal') {
      txt += `Split by: ${people} people\nEach pays: ₱${perPerson.toFixed(2)}`;
    } else if (mode === 'itemized') {
      txt += `Itemized Breakdown:\n`;
      const personTotals = {};
      items.forEach(i => {
        if (i.name || i.amount) {
          const who = i.assignedTo || 'Unassigned';
          const amt = parseFloat(i.amount) || 0;
          txt += `- ${i.name || 'Item'} (${who}): ₱${amt.toFixed(2)}\n`;
          personTotals[who] = (personTotals[who] || 0) + amt;
        }
      });
      txt += `\nEach Person Pays:\n`;
      Object.entries(personTotals).forEach(([who, amt]) => {
        txt += `${who}: ₱${amt.toFixed(2)}\n`;
      });
    } else if (mode === 'percentage') {
      txt += `Percentage Breakdown:\n`;
      percentShares.forEach(p => {
        const amt = displayTotal * ((parseFloat(p.percent) || 0) / 100);
        txt += `- ${p.name}: ₱${amt.toFixed(2)} (${p.percent}%)\n`;
      });
    }
    if (paymentInfo.trim()) {
      txt += `\nSend Payment To:\n${paymentInfo.trim()}`;
    }
    return txt;
  };

  const getIndividualQRs = () => {
    const qrs = [];
    const paymentSuffix = paymentInfo.trim() ? `\n\nSend Payment To:\n${paymentInfo.trim()}` : '';

    if (mode === 'itemized') {
      const personTotals = {};
      const personItems = {};
      items.forEach(i => {
        if (i.name || i.amount) {
          const who = i.assignedTo || 'Unassigned';
          const amt = parseFloat(i.amount) || 0;
          personTotals[who] = (personTotals[who] || 0) + amt;
          if (!personItems[who]) personItems[who] = [];
          personItems[who].push({ name: i.name || 'Item', amt });
        }
      });
      Object.entries(personTotals).forEach(([who, total]) => {
        let text = `💰 Personal Bill\nName: ${who}\nTotal Owed: ₱${total.toFixed(2)}\n\nItems:\n`;
        personItems[who].forEach(i => {
          text += `- ${i.name}: ₱${i.amt.toFixed(2)}\n`;
        });
        text += paymentSuffix;
        qrs.push({ name: who, amount: total, text });
      });
    } else if (mode === 'percentage') {
      percentShares.forEach(p => {
        const amt = displayTotal * ((parseFloat(p.percent) || 0) / 100);
        const text = `💰 Personal Bill\nName: ${p.name}\nTotal Owed: ₱${amt.toFixed(2)}\nShare: ${p.percent}%${paymentSuffix}`;
        qrs.push({ name: p.name, amount: amt, text });
      });
    }
    return qrs;
  };

  const handleCopy = () => {
    navigator.clipboard.writeText(getSummaryText());
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const totalPercent = percentShares.reduce((s, i) => s + (parseFloat(i.percent) || 0), 0);

  return (
    <div className="modal-overlay" style={{ zIndex: 5000 }}>
      <div className="card modal-content" onClick={e => e.stopPropagation()} style={{ maxWidth: '420px', borderRadius: '32px', padding: '32px', maxHeight: '90vh', overflowY: 'auto' }}>
        {/* Header */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <div style={{ background: 'rgba(124,58,237,0.1)', padding: '10px', borderRadius: '14px' }}>
              <Split size={22} color="#7C3AED" />
            </div>
            <div>
              <h3 style={{ margin: 0, fontWeight: 800, fontSize: '20px' }}>Bill Splitter</h3>
              <p style={{ margin: 0, fontSize: '12px', color: 'var(--text-muted)', fontWeight: 600 }}>Split the bill with your group</p>
            </div>
          </div>
          <button onClick={onClose} className="close-btn"><X size={20} /></button>
        </div>

        {/* Mode Toggle */}
        <div style={{ display: 'flex', gap: '8px', background: 'var(--light-bg)', padding: '5px', borderRadius: '14px', marginBottom: '24px' }}>
          {['equal', 'itemized', 'percentage'].map(m => (
            <button key={m} onClick={() => { setMode(m); setShowQR(false); }} style={{
              flex: 1, padding: '9px', borderRadius: '10px', border: 'none',
              background: mode === m ? 'var(--surface)' : 'transparent',
              fontWeight: 700, fontSize: '12px', cursor: 'pointer',
              color: mode === m ? '#7C3AED' : 'var(--text-muted)',
              boxShadow: mode === m ? 'var(--shadow)' : 'none', transition: 'var(--transition)'
            }}>
              {m === 'equal' ? 'Equal' : m === 'itemized' ? 'Itemized' : 'Percentage'}
            </button>
          ))}
        </div>

        {/* Payment Info */}
        <div style={{ marginBottom: '24px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '10px' }}>
            <label className="input-label" style={{ margin: 0, display: 'block' }}>Payment Info (Optional)</label>
            {resortGCash && (
              <button 
                type="button"
                onClick={() => { setPaymentInfo(resortGCash); setShowQR(false); }}
                style={{ background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: '6px', color: '#7C3AED', fontSize: '11px', fontWeight: 700, cursor: 'pointer', padding: '4px 8px' }}
              >
                Use Resort GCash
              </button>
            )}
          </div>
          <input 
            className="input" 
            placeholder="e.g. GCash 09123456789" 
            value={paymentInfo} 
            onChange={e => { setPaymentInfo(e.target.value); setShowQR(false); }}
            style={{ width: '100%', padding: '12px 16px', fontSize: '14px', boxSizing: 'border-box' }}
          />
        </div>

        {/* People Stepper (Only for Equal/Itemized) */}
        {mode !== 'percentage' && (
          <div style={{ marginBottom: '24px' }}>
            <label className="input-label" style={{ display: 'block', marginBottom: '10px' }}>Number of People</label>
            <div style={{ display: 'flex', alignItems: 'center', gap: '16px', background: 'var(--light-bg)', padding: '12px 20px', borderRadius: '16px' }}>
              <button onClick={() => setPeople(Math.max(2, people - 1))} style={{ width: '38px', height: '38px', borderRadius: '12px', border: '1px solid var(--border)', background: 'var(--surface)', fontWeight: 800, fontSize: '18px', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', transition: 'var(--transition)' }}>−</button>
              <div style={{ flex: 1, textAlign: 'center' }}>
                <div style={{ fontSize: '28px', fontWeight: 900, color: '#7C3AED' }}>{people}</div>
                <div style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 700 }}>PEOPLE</div>
              </div>
              <button onClick={() => setPeople(Math.min(20, people + 1))} style={{ width: '38px', height: '38px', borderRadius: '12px', border: '1px solid var(--border)', background: 'var(--surface)', fontWeight: 800, fontSize: '18px', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', transition: 'var(--transition)' }}>+</button>
            </div>
          </div>
        )}

        {/* Equal Mode */}
        {mode === 'equal' && (
          <div style={{ marginBottom: '24px' }}>
            <label className="input-label" style={{ display: 'block', marginBottom: '10px' }}>Total Bill Amount</label>
            <div style={{ position: 'relative' }}>
              <span style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', fontWeight: 800, color: 'var(--secondary)', fontSize: '18px' }}>₱</span>
              <input
                type="number" className="input" placeholder="0.00"
                style={{ paddingLeft: '36px', fontSize: '20px', fontWeight: 800, height: '56px' }}
                value={totalBill}
                onChange={e => setTotalBill(e.target.value.replace(/[^0-9.]/g, ''))}
              />
            </div>
          </div>
        )}

        {/* Itemized Mode */}
        {mode === 'itemized' && (
          <div style={{ marginBottom: '24px' }}>
            <label className="input-label" style={{ display: 'block', marginBottom: '10px' }}>Items</label>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', maxHeight: '200px', overflowY: 'auto' }}>
              {items.map((item, i) => (
                <div key={i} style={{ display: 'flex', gap: '8px', alignItems: 'center', flexWrap: 'wrap' }}>
                  {addons && addons.length > 0 ? (
                    <select className="input" style={{ flex: 1.5, padding: '10px 14px', fontSize: '13px', minWidth: '100px' }}
                      value={item.name}
                      onChange={e => {
                        const selectedAddon = addons.find(a => a.name === e.target.value);
                        updateItem(i, 'name', e.target.value);
                        if (selectedAddon) updateItem(i, 'amount', selectedAddon.price.toString());
                      }}>
                      <option value="">Select Item / Add-on</option>
                      {Array.from(new Map(addons.map(a => [a.name, a])).values()).map(a => <option key={a.name} value={a.name}>{a.name}</option>)}
                      <option value="Custom Item">Custom Item</option>
                    </select>
                  ) : (
                    <input className="input" placeholder="Item name" style={{ flex: 1.5, padding: '10px 14px', fontSize: '13px', minWidth: '100px' }}
                      value={item.name} onChange={e => updateItem(i, 'name', e.target.value)} />
                  )}
                  <input className="input" placeholder="Who pays?" style={{ flex: 1.5, padding: '10px 14px', fontSize: '13px', minWidth: '100px' }}
                    value={item.assignedTo} onChange={e => updateItem(i, 'assignedTo', e.target.value)} />
                  <div style={{ position: 'relative', flex: 1, minWidth: '80px' }}>
                    <span style={{ position: 'absolute', left: '10px', top: '50%', transform: 'translateY(-50%)', fontWeight: 700, color: 'var(--secondary)', fontSize: '14px' }}>₱</span>
                    <input className="input" type="text" placeholder="0.00" style={{ paddingLeft: '24px', padding: '10px 10px 10px 24px', fontSize: '13px', width: '100%' }}
                      value={item.amount} onChange={e => updateItem(i, 'amount', e.target.value.replace(/[^0-9.]/g, ''))} />
                  </div>
                  {items.length > 1 && <button onClick={() => removeItem(i)} style={{ background: 'rgba(239, 68, 68, 0.1)', border: 'none', borderRadius: '10px', width: '36px', height: '36px', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--primary)', flexShrink: 0 }}><Trash2 size={14} /></button>}
                </div>
              ))}
            </div>
            <button onClick={addItem} style={{ marginTop: '10px', background: 'var(--light-bg)', border: '1px dashed var(--border)', borderRadius: '12px', padding: '9px 16px', fontWeight: 700, fontSize: '13px', cursor: 'pointer', color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: '8px', width: '100%', justifyContent: 'center' }}>
              <Plus size={15} /> Add Item
            </button>
          </div>
        )}

        {/* Percentage Mode */}
        {mode === 'percentage' && (
          <div style={{ marginBottom: '24px' }}>
            <label className="input-label" style={{ display: 'block', marginBottom: '10px' }}>Total Bill Amount</label>
            <div style={{ position: 'relative', marginBottom: '16px' }}>
              <span style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', fontWeight: 800, color: 'var(--secondary)', fontSize: '18px' }}>₱</span>
              <input
                type="number" className="input" placeholder="0.00"
                style={{ paddingLeft: '36px', fontSize: '20px', fontWeight: 800, height: '56px' }}
                value={totalBill}
                onChange={e => setTotalBill(e.target.value.replace(/[^0-9.]/g, ''))}
              />
            </div>
            
            <label className="input-label" style={{ display: 'block', marginBottom: '10px' }}>Percentage Split</label>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', maxHeight: '200px', overflowY: 'auto' }}>
              {percentShares.map((item, i) => {
                const calculatedAmt = displayTotal * ((parseFloat(item.percent) || 0) / 100);
                return (
                  <div key={i} style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                    <input className="input" placeholder="Name" style={{ flex: 1.5, padding: '10px 14px', fontSize: '13px' }}
                      value={item.name} onChange={e => updatePercentShare(i, 'name', e.target.value)} />
                    <div style={{ position: 'relative', flex: 1 }}>
                      <span style={{ position: 'absolute', right: '10px', top: '50%', transform: 'translateY(-50%)', fontWeight: 700, color: 'var(--text-muted)', fontSize: '13px' }}>%</span>
                      <input className="input" type="number" placeholder="0" style={{ paddingRight: '24px', padding: '10px', fontSize: '13px' }}
                        value={item.percent} onChange={e => updatePercentShare(i, 'percent', e.target.value)} />
                    </div>
                    <div style={{ flex: 1, fontSize: '13px', fontWeight: 700, color: 'var(--primary)', textAlign: 'right' }}>
                      ₱{calculatedAmt.toFixed(2)}
                    </div>
                    {percentShares.length > 1 && <button onClick={() => removePercentShare(i)} style={{ background: 'rgba(239, 68, 68, 0.1)', border: 'none', borderRadius: '10px', width: '36px', height: '36px', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--primary)', flexShrink: 0 }}><Trash2 size={14} /></button>}
                  </div>
                );
              })}
            </div>
            <button onClick={addPercentShare} style={{ marginTop: '10px', background: 'var(--light-bg)', border: '1px dashed var(--border)', borderRadius: '12px', padding: '9px 16px', fontWeight: 700, fontSize: '13px', cursor: 'pointer', color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: '8px', width: '100%', justifyContent: 'center' }}>
              <Plus size={15} /> Add Person
            </button>
            
            {totalPercent !== 100 && (
              <div style={{ color: '#ef4444', fontSize: '12px', marginTop: '12px', textAlign: 'center', fontWeight: 600 }}>
                Warning: Total percentage must equal 100% (Currently {totalPercent}%)
              </div>
            )}
          </div>
        )}

        {/* Result (Text) */}
        {!showQR && displayTotal > 0 && mode === 'equal' && (
          <div style={{ background: 'linear-gradient(135deg, rgba(124,58,237,0.08), rgba(124,58,237,0.04))', border: '1.5px solid rgba(124,58,237,0.15)', borderRadius: '20px', padding: '24px', marginBottom: '20px', textAlign: 'center' }}>
            <div style={{ fontSize: '13px', fontWeight: 700, color: '#7C3AED', textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: '8px' }}>Each Person Pays</div>
            <div style={{ fontSize: '44px', fontWeight: 900, color: '#7C3AED', letterSpacing: '-2px' }}>₱{perPerson.toFixed(2)}</div>
            <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '8px', fontWeight: 600 }}>
              Total ₱{displayTotal.toLocaleString()} ÷ {people} people
            </div>
          </div>
        )}

        {!showQR && displayTotal > 0 && mode !== 'equal' && (
          <div style={{ background: 'var(--light-bg)', borderRadius: '20px', padding: '24px', marginBottom: '20px' }}>
            <div style={{ fontSize: '14px', fontWeight: 800, color: 'var(--text-main)', marginBottom: '12px' }}>Calculated Split</div>
            <div style={{ whiteSpace: 'pre-wrap', fontFamily: 'monospace', fontSize: '13px', color: 'var(--text-muted)' }}>
              {getSummaryText()}
            </div>
          </div>
        )}

        {/* Result (QR) */}
        {showQR && displayTotal > 0 && (
          <div style={{ textAlign: 'center', marginBottom: '24px', padding: '24px', background: 'var(--surface)', borderRadius: '20px', border: '1.5px solid var(--border)', animation: 'fadeIn 0.3s ease-out' }}>
             <div style={{ fontSize: '13px', fontWeight: 800, marginBottom: '16px', color: 'var(--text-main)' }}>Scan to view Full Split Summary</div>
             <div style={{ background: 'var(--surface)', padding: '16px', borderRadius: '16px', display: 'inline-block', boxShadow: '0 10px 25px -5px rgba(0,0,0,0.1)' }}>
               <QRCodeSVG value={getSummaryText()} size={180} level="M" />
             </div>
          </div>
        )}

        {/* Actions */}
        <div style={{ display: 'flex', gap: '10px' }}>
          <button onClick={onClose} className="btn" style={{ flex: 1, background: 'var(--light-bg)', color: 'var(--text-main)', border: '1px solid var(--border)' }}>Close</button>
          
          <button 
            onClick={() => setShowQR(!showQR)} 
            disabled={displayTotal <= 0}
            className="btn" 
            style={{ 
              flex: 1.2, 
              background: showQR ? 'rgba(239, 68, 68, 0.1)' : 'var(--surface)', 
              color: showQR ? '#ef4444' : 'var(--text-main)', 
              border: `1px solid ${showQR ? '#FEE2E2' : 'var(--border)'}`, 
              transition: 'var(--transition)',
              opacity: displayTotal <= 0 ? 0.5 : 1,
              cursor: displayTotal <= 0 ? 'not-allowed' : 'pointer'
            }}>
            {showQR ? 'Hide QR' : <><QrCode size={16} /> Show QR</>}
          </button>

          <button 
            onClick={handleCopy} 
            disabled={displayTotal <= 0}
            className="btn" 
            style={{ 
              flex: 1.5, 
              background: copied ? 'rgba(16, 185, 129, 0.1)' : '#F5F3FF', 
              color: copied ? '#059669' : '#7C3AED', 
              border: `1px solid ${copied ? '#D1FAE5' : 'rgba(124,58,237,0.2)'}`, 
              transition: 'var(--transition)',
              opacity: displayTotal <= 0 ? 0.5 : 1,
              cursor: displayTotal <= 0 ? 'not-allowed' : 'pointer'
            }}>
            {copied ? <><Check size={16} /> Copied!</> : <><Copy size={16} /> Copy Text</>}
          </button>
        </div>
      </div>
    </div>
  );
};

export default BillSplitterModal;
