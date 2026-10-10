import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, get, push, update, remove } from 'firebase/database';
import Papa from 'papaparse';
import * as XLSX from 'xlsx';
import {
  FileSpreadsheet, Upload, Download, AlertCircle, CheckCircle2,
  Trash2, RefreshCw, Plus, ArrowLeft, ShieldAlert, Check, X,
  Layers, Database, Calendar, User, DollarSign, Eye, EyeOff
} from 'lucide-react';
import {
  SAMPLE_ROOM_CSV,
  SAMPLE_ACTIVITY_CSV,
  validateAndComputeRoomRow,
  validateAndComputeActivityRow,
  formatBookingPayloadForFirebase
} from '../utils/historicalImportHelper';

const HistoricalDataImport = ({ profile, uid, onBack }) => {
  const isAdmin = (profile?.role || '').toUpperCase() === 'ADMIN';

  const [properties, setProperties] = useState([]);
  const [selectedPropertyId, setSelectedPropertyId] = useState('');
  const [recordType, setRecordType] = useState('rooms'); // 'rooms' | 'activities'
  const [activeSubTab, setActiveSubTab] = useState('bulk'); // 'bulk' | 'single' | 'batches'

  // Privacy setting: mask contact / email
  const [maskData, setMaskData] = useState(false);

  // Bulk Upload State
  const [parsedRows, setParsedRows] = useState([]);
  const [existingBookings, setExistingBookings] = useState([]);
  const [uploadFileName, setUploadFileName] = useState('');
  const [isImporting, setIsImporting] = useState(false);
  const [importProgress, setImportProgress] = useState(0);
  const [importResult, setImportResult] = useState(null); // { imported, skipped, failed, errorRows }

  // Single Record Form State
  const [singleForm, setSingleForm] = useState({
    guestName: '',
    address: '',
    nationality: 'Filipino',
    email: '',
    contactNumber: '',
    arrivalDate: '',
    departureDate: '',
    nights: '1',
    adults: '2',
    children: '0',
    plateNumber: '',
    roomType: '',
    ratePerNight: '',
    totalStay: '',
    bookingSource: 'Walk-in',
    paymentMethod: 'Cash',
    paymentOption: 'Full Payment',
    note: '',
    checkedInBy: '',
    // Activity specific
    activityTitle: '',
    pax: '1',
    pricePerPax: '',
    timeSlot: '09:00 AM - 10:00 AM',
    mealAddons: ''
  });
  const [singleError, setSingleError] = useState('');
  const [singleSuccess, setSingleSuccess] = useState('');

  // Batches State
  const [batches, setBatches] = useState([]);
  const [loadingBatches, setLoadingBatches] = useState(false);
  const [deletingBatchId, setDeletingBatchId] = useState(null);

  // Fetch Properties & Existing Bookings for Duplicate Check
  useEffect(() => {
    const fetchProps = async () => {
      try {
        const snap = await get(ref(db, 'properties'));
        if (snap.exists()) {
          const list = Object.entries(snap.val()).map(([id, val]) => ({ id, ...val }));
          if (isAdmin) {
            setProperties(list);
            if (list.length > 0 && !selectedPropertyId) {
              setSelectedPropertyId(list[0].id);
            }
          } else {
            // Owner can only import for their own property
            const myProps = list.filter(p => p.id === uid || p.ownerUid === uid);
            setProperties(myProps);
            if (myProps.length > 0) {
              setSelectedPropertyId(myProps[0].id);
            }
          }
        }
      } catch (err) {
        console.error("Error fetching properties:", err);
      }
    };

    fetchProps();
  }, [uid, isAdmin]);

  // Load existing bookings whenever selected property changes
  useEffect(() => {
    if (!selectedPropertyId) return;
    const fetchExisting = async () => {
      try {
        const snap = await get(ref(db, 'bookings'));
        if (snap.exists()) {
          const all = Object.entries(snap.val()).map(([id, val]) => ({ id, ...val }));
          const propBookings = all.filter(b => b.ownerUid === selectedPropertyId);
          setExistingBookings(propBookings);
        }
      } catch (err) {
        console.error("Error fetching bookings for duplicates:", err);
      }
    };
    fetchExisting();
    loadBatches();
  }, [selectedPropertyId]);

  const loadBatches = async () => {
    setLoadingBatches(true);
    try {
      const snap = await get(ref(db, 'bookings'));
      if (snap.exists()) {
        const all = Object.entries(snap.val()).map(([id, val]) => ({ id, ...val }));
        const historical = all.filter(b => b.isHistorical === true && (!selectedPropertyId || b.ownerUid === selectedPropertyId));
        
        // Group by batchId
        const batchMap = {};
        historical.forEach(b => {
          const bId = b.importBatchId || 'legacy_import';
          if (!batchMap[bId]) {
            batchMap[bId] = {
              batchId: bId,
              propertyName: b.propertyName || 'Property',
              ownerUid: b.ownerUid,
              importedBy: b.importedBy,
              importedAt: b.importedAt || b.createdAt,
              dataSource: b.dataSource || 'import',
              recordsCount: 0,
              records: []
            };
          }
          batchMap[bId].recordsCount++;
          batchMap[bId].records.push(b.id);
        });

        const list = Object.values(batchMap).sort((a, b) => (b.importedAt || 0) - (a.importedAt || 0));
        setBatches(list);
      } else {
        setBatches([]);
      }
    } catch (e) {
      console.error("Error loading batches:", e);
    }
    setLoadingBatches(false);
  };

  const currentProperty = properties.find(p => p.id === selectedPropertyId);

  // Template Download Handler
  const handleDownloadTemplate = () => {
    const csvContent = recordType === 'rooms' ? SAMPLE_ROOM_CSV : SAMPLE_ACTIVITY_CSV;
    const fileName = `historical_${recordType}_template.csv`;
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.setAttribute('download', fileName);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  // File Upload & Parse
  const handleFileUpload = (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploadFileName(file.name);
    setImportResult(null);

    const ext = file.name.split('.').pop().toLowerCase();

    if (ext === 'xlsx' || ext === 'xls') {
      const reader = new FileReader();
      reader.onload = (evt) => {
        try {
          const bstr = evt.target.result;
          const wb = XLSX.read(bstr, { type: 'binary' });
          const wsname = wb.SheetNames[0];
          const ws = wb.Sheets[wsname];
          const data = XLSX.utils.sheet_to_json(ws);
          processRawRows(data);
        } catch (err) {
          alert("Failed to parse Excel file: " + err.message);
        }
      };
      reader.readAsBinaryString(file);
    } else {
      // CSV
      Papa.parse(file, {
        header: true,
        skipEmptyLines: true,
        complete: (results) => {
          processRawRows(results.data);
        },
        error: (err) => {
          alert("Failed to parse CSV file: " + err.message);
        }
      });
    }
  };

  const processRawRows = (rows) => {
    const processed = rows.map((rawRow, idx) => {
      const computed = recordType === 'rooms'
        ? validateAndComputeRoomRow(rawRow, currentProperty, maskData)
        : validateAndComputeActivityRow(rawRow, currentProperty, maskData);

      // Duplicate Check
      let isDuplicate = false;
      if (computed.status !== 'invalid') {
        const guestNorm = (computed.parsed.guestName || '').toLowerCase().trim();
        const dateStr = recordType === 'rooms' ? computed.parsed.arrivalFormatted : computed.parsed.activityFormatted;
        const targetTitle = recordType === 'rooms' ? (computed.parsed.roomTitle || '').toLowerCase().trim() : (computed.parsed.activityTitle || '').toLowerCase().trim();

        isDuplicate = existingBookings.some(b => {
          const bName = (b.touristName || '').toLowerCase().trim();
          const bDate = b.bookingDate || b.date;
          const bTitle = (b.roomTitle || b.activityTitle || '').toLowerCase().trim();
          return bName === guestNorm && bDate === dateStr && bTitle === targetTitle;
        });
      }

      return {
        id: `row_${idx}`,
        raw: rawRow,
        isDuplicate,
        ...computed
      };
    });

    setParsedRows(processed);
  };

  // Re-run validation on cell change
  const handleCellEdit = (rowId, field, value) => {
    setParsedRows(prev => prev.map(item => {
      if (item.id !== rowId) return item;
      const updatedRaw = { ...item.raw, [field]: value };
      const computed = recordType === 'rooms'
        ? validateAndComputeRoomRow(updatedRaw, currentProperty, maskData)
        : validateAndComputeActivityRow(updatedRaw, currentProperty, maskData);
      return {
        ...item,
        raw: updatedRaw,
        ...computed
      };
    }));
  };

  // Execute Bulk Import
  const handleExecuteImport = async () => {
    if (!currentProperty) {
      alert("Please select a target property first.");
      return;
    }

    const importableRows = parsedRows.filter(r => r.status !== 'invalid');
    if (importableRows.length === 0) {
      alert("There are no valid or importable rows to import.");
      return;
    }

    const confirmed = window.confirm(
      `Confirm importing ${importableRows.length} historical record(s) for "${currentProperty.name || currentProperty.title}"?\n` +
      `These will be loaded with status 'Completed' into the database.`
    );
    if (!confirmed) return;

    setIsImporting(true);
    setImportProgress(0);

    const batchId = `batch_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    let importedCount = 0;
    let skippedCount = 0;
    let failedCount = 0;
    const errorRows = [];

    const bookingsRef = ref(db, 'bookings');

    for (let i = 0; i < importableRows.length; i++) {
      const item = importableRows[i];
      if (item.isDuplicate) {
        skippedCount++;
        continue;
      }

      try {
        const payload = formatBookingPayloadForFirebase({
          type: recordType === 'rooms' ? 'room' : 'activity',
          record: item,
          property: currentProperty,
          batchId,
          userUid: uid,
          dataSource: 'csv_import'
        });

        await push(bookingsRef, payload);
        importedCount++;
      } catch (err) {
        failedCount++;
        errorRows.push({ ...item.raw, importError: err.message });
      }

      setImportProgress(Math.round(((i + 1) / importableRows.length) * 100));
    }

    setIsImporting(false);
    setImportResult({
      batchId,
      imported: importedCount,
      skipped: skippedCount,
      failed: failedCount,
      errorRows
    });

    // Refresh existing and batches
    loadBatches();
  };

  // Download Error CSV
  const handleDownloadErrorCsv = () => {
    if (!importResult?.errorRows || importResult.errorRows.length === 0) return;
    const csv = Papa.unparse(importResult.errorRows);
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.setAttribute('download', `import_errors_${importResult.batchId}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  // Single Record Submit
  const handleSingleSubmit = async (e, addAnother = false) => {
    e.preventDefault();
    setSingleError('');
    setSingleSuccess('');

    if (!currentProperty) {
      setSingleError('Please select a target property.');
      return;
    }

    const computed = recordType === 'rooms'
      ? validateAndComputeRoomRow(singleForm, currentProperty, maskData)
      : validateAndComputeActivityRow(singleForm, currentProperty, maskData);

    if (computed.status === 'invalid') {
      setSingleError(computed.errors.join(', '));
      return;
    }

    try {
      const batchId = `manual_${Date.now()}`;
      const payload = formatBookingPayloadForFirebase({
        type: recordType === 'rooms' ? 'room' : 'activity',
        record: computed,
        property: currentProperty,
        batchId,
        userUid: uid,
        dataSource: 'manual_entry'
      });

      await push(ref(db, 'bookings'), payload);
      setSingleSuccess(`Successfully recorded historical stay for ${computed.parsed.guestName}!`);

      if (addAnother) {
        setSingleForm(prev => ({
          ...prev,
          guestName: '',
          email: '',
          contactNumber: '',
          totalStay: '',
          note: ''
        }));
      } else {
        loadBatches();
      }
    } catch (err) {
      setSingleError("Failed to save record: " + err.message);
    }
  };

  // Delete Batch (Soft check: only isHistorical == true)
  const handleDeleteBatch = async (batch) => {
    const confirmed = window.confirm(
      `Are you sure you want to delete batch "${batch.batchId}"?\n` +
      `This will remove ${batch.recordsCount} historical records. Real live bookings will never be touched.`
    );
    if (!confirmed) return;

    setDeletingBatchId(batch.batchId);
    try {
      const updates = {};
      batch.records.forEach(id => {
        updates[`bookings/${id}`] = null;
      });
      await update(ref(db), updates);
      alert(`Batch "${batch.batchId}" deleted successfully.`);
      loadBatches();
    } catch (err) {
      alert("Failed to delete batch: " + err.message);
    }
    setDeletingBatchId(null);
  };

  return (
    <div className="view-transition" style={{ maxWidth: '1200px', margin: '0 auto', paddingBottom: '60px' }}>
      {/* Top Header Card */}
      <div className="card" style={{
        background: 'linear-gradient(135deg, #0F766E, var(--secondary))',
        color: 'white', marginBottom: '32px', padding: '32px',
        border: 'none', position: 'relative', overflow: 'hidden', borderRadius: '24px'
      }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
              {onBack && (
                <button onClick={onBack} className="btn" style={{ background: 'rgba(255,255,255,0.15)', color: 'white', padding: '8px 12px', borderRadius: '12px', border: 'none', cursor: 'pointer' }}>
                  <ArrowLeft size={18} />
                </button>
              )}
              <h2 style={{ display: 'flex', alignItems: 'center', gap: '12px', margin: 0, fontSize: '28px', fontWeight: 800 }}>
                <Database size={30} /> Historical Data Import
              </h2>
            </div>
            <p style={{ opacity: 0.9, margin: '8px 0 0 0', fontSize: '14px', maxWidth: '750px' }}>
              Import past guest registration cards and records for capstone panel analytics, dashboard metrics, and revenue charts. Real bookings and live room availability are safely preserved.
            </p>
          </div>

          <div style={{ background: 'rgba(255,255,255,0.12)', padding: '12px 18px', borderRadius: '16px', display: 'flex', alignItems: 'center', gap: '10px' }}>
            <ShieldAlert size={20} color="#FDE047" />
            <span style={{ fontSize: '12px', fontWeight: 700 }}>Auto-flagged as Completed</span>
          </div>
        </div>
      </div>

      {/* Privacy Notice Banner */}
      <div style={{
        background: 'var(--surface)', border: '1px solid var(--border)',
        borderRadius: '16px', padding: '16px 20px', marginBottom: '24px',
        display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '12px'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <AlertCircle size={20} color="var(--primary)" />
          <span style={{ fontSize: '13px', color: 'var(--text-muted)' }}>
            <strong>PH Data Privacy Notice:</strong> Only import data you are authorized to use. Mask or omit contact details if not needed.
          </span>
        </div>
        <label style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer', fontSize: '13px', fontWeight: 700 }}>
          <input
            type="checkbox"
            checked={maskData}
            onChange={(e) => setMaskData(e.target.checked)}
            style={{ width: '16px', height: '16px', accentColor: 'var(--primary)' }}
          />
          Mask contact number/email (stores last 4 digits only)
        </label>
      </div>

      {/* Property & Type Selector Bar */}
      <div className="card" style={{ padding: '24px', marginBottom: '28px', borderRadius: '20px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))', gap: '20px', alignItems: 'center' }}>
          <div>
            <label style={{ display: 'block', fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', color: 'var(--text-muted)', marginBottom: '8px' }}>
              Target Partner Property
            </label>
            <select
              className="input"
              value={selectedPropertyId}
              onChange={(e) => setSelectedPropertyId(e.target.value)}
              style={{ width: '100%', height: '46px', borderRadius: '12px', fontWeight: 700 }}
            >
              {properties.length === 0 && <option value="">No properties available</option>}
              {properties.map(p => (
                <option key={p.id} value={p.id}>
                  {p.name || p.title || `Property (${p.id.substring(0, 6)})`} {p.type ? `[${p.type}]` : ''}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label style={{ display: 'block', fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', color: 'var(--text-muted)', marginBottom: '8px' }}>
              Record Type
            </label>
            <div style={{ display: 'flex', gap: '10px' }}>
              <button
                type="button"
                className="btn"
                onClick={() => { setRecordType('rooms'); setParsedRows([]); setImportResult(null); }}
                style={{
                  flex: 1, padding: '10px', borderRadius: '12px', fontSize: '13px', fontWeight: 800,
                  background: recordType === 'rooms' ? 'var(--primary)' : 'var(--light-bg)',
                  color: recordType === 'rooms' ? 'white' : 'var(--text-main)',
                  border: '1px solid var(--border)'
                }}
              >
                🛏️ Room Stays
              </button>
              <button
                type="button"
                className="btn"
                onClick={() => { setRecordType('activities'); setParsedRows([]); setImportResult(null); }}
                style={{
                  flex: 1, padding: '10px', borderRadius: '12px', fontSize: '13px', fontWeight: 800,
                  background: recordType === 'activities' ? 'var(--primary)' : 'var(--light-bg)',
                  color: recordType === 'activities' ? 'white' : 'var(--text-main)',
                  border: '1px solid var(--border)'
                }}
              >
                🚣 Activities
              </button>
            </div>
          </div>

          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '8px', paddingTop: '20px' }}>
            <button
              onClick={handleDownloadTemplate}
              className="btn"
              style={{
                background: 'rgba(29, 211, 176, 0.1)', color: 'var(--secondary)',
                border: '1px solid var(--secondary)', borderRadius: '12px', padding: '10px 16px',
                fontSize: '13px', fontWeight: 800, display: 'flex', alignItems: 'center', gap: '8px'
              }}
              title="Download pre-formatted CSV template"
            >
              <Download size={16} /> Download CSV Template
            </button>
          </div>
        </div>
      </div>

      {/* Sub Navigation Tabs */}
      <div style={{ display: 'flex', gap: '12px', marginBottom: '24px', borderBottom: '2px solid var(--border)', paddingBottom: '12px' }}>
        <button
          onClick={() => setActiveSubTab('bulk')}
          style={{
            background: 'none', border: 'none', fontSize: '16px', fontWeight: 800,
            color: activeSubTab === 'bulk' ? 'var(--primary)' : 'var(--text-muted)',
            cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '8px'
          }}
        >
          <FileSpreadsheet size={18} /> Bulk CSV / Excel Upload
        </button>
        <button
          onClick={() => setActiveSubTab('single')}
          style={{
            background: 'none', border: 'none', fontSize: '16px', fontWeight: 800,
            color: activeSubTab === 'single' ? 'var(--primary)' : 'var(--text-muted)',
            cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '8px'
          }}
        >
          <Plus size={18} /> Manual Registration Card
        </button>
        <button
          onClick={() => { setActiveSubTab('batches'); loadBatches(); }}
          style={{
            background: 'none', border: 'none', fontSize: '16px', fontWeight: 800,
            color: activeSubTab === 'batches' ? 'var(--primary)' : 'var(--text-muted)',
            cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '8px'
          }}
        >
          <Layers size={18} /> Imported Batches ({batches.length})
        </button>
      </div>

      {/* TAB 1: BULK CSV / EXCEL UPLOAD */}
      {activeSubTab === 'bulk' && (
        <div>
          {/* File Upload Box */}
          <div className="card" style={{
            border: '2px dashed var(--border)', textAlign: 'center',
            padding: '36px 20px', borderRadius: '20px', marginBottom: '24px',
            background: 'var(--surface)'
          }}>
            <Upload size={36} color="var(--primary)" style={{ margin: '0 auto 12px auto' }} />
            <h4 style={{ margin: '0 0 8px 0', fontSize: '18px', fontWeight: 800 }}>
              Upload Historical {recordType === 'rooms' ? 'Room Stays' : 'Activities'} File
            </h4>
            <p style={{ color: 'var(--text-muted)', fontSize: '13px', margin: '0 0 16px 0' }}>
              Supports .csv, .xlsx, or .xls format matching the template columns.
            </p>
            <input
              type="file"
              accept=".csv, .xlsx, .xls"
              onChange={handleFileUpload}
              id="historicalFileInput"
              style={{ display: 'none' }}
            />
            <label
              htmlFor="historicalFileInput"
              className="btn btn-primary"
              style={{ cursor: 'pointer', display: 'inline-flex', alignItems: 'center', gap: '8px', padding: '10px 24px', borderRadius: '12px' }}
            >
              Browse Computer
            </label>
            {uploadFileName && (
              <p style={{ marginTop: '12px', fontSize: '13px', fontWeight: 700, color: 'var(--secondary)' }}>
                Loaded file: {uploadFileName} ({parsedRows.length} rows detected)
              </p>
            )}
          </div>

          {/* Import Result Feedback */}
          {importResult && (
            <div className="card" style={{
              background: 'rgba(16, 185, 129, 0.08)', border: '1.5px solid #10B981',
              borderRadius: '20px', padding: '24px', marginBottom: '24px'
            }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '12px' }}>
                <div>
                  <h4 style={{ margin: '0 0 6px 0', color: '#065F46', fontSize: '18px', fontWeight: 800, display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <CheckCircle2 size={22} color="#10B981" /> Import Execution Completed
                  </h4>
                  <p style={{ margin: 0, fontSize: '14px', color: '#047857' }}>
                    Batch ID: <code>{importResult.batchId}</code> • <strong>{importResult.imported}</strong> imported, <strong>{importResult.skipped}</strong> duplicate(s) skipped, <strong>{importResult.failed}</strong> failed.
                  </p>
                </div>
                {importResult.failed > 0 && (
                  <button
                    onClick={handleDownloadErrorCsv}
                    className="btn"
                    style={{ background: '#EF4444', color: 'white', borderRadius: '12px', padding: '8px 16px', fontSize: '13px', fontWeight: 700, border: 'none' }}
                  >
                    Download Error CSV ({importResult.failed})
                  </button>
                )}
              </div>
            </div>
          )}

          {/* Progress Bar when Importing */}
          {isImporting && (
            <div style={{ marginBottom: '20px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '13px', fontWeight: 700, marginBottom: '6px' }}>
                <span>Importing historical entries to database...</span>
                <span>{importProgress}%</span>
              </div>
              <div style={{ width: '100%', height: '10px', background: 'var(--border)', borderRadius: '10px', overflow: 'hidden' }}>
                <div style={{ width: `${importProgress}%`, height: '100%', background: 'var(--primary)', transition: 'width 0.2s ease' }} />
              </div>
            </div>
          )}

          {/* Parsed Rows Preview Table */}
          {parsedRows.length > 0 && (
            <div className="card" style={{ padding: '20px', borderRadius: '20px', overflow: 'hidden' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px', flexWrap: 'wrap', gap: '12px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
                  <h4 style={{ margin: 0, fontSize: '17px', fontWeight: 800 }}>Row Validation & Preview</h4>
                  <div style={{ display: 'flex', gap: '8px', fontSize: '12px', fontWeight: 700 }}>
                    <span style={{ color: '#059669' }}>● {parsedRows.filter(r => r.status === 'valid').length} Valid</span>
                    <span style={{ color: '#D97706' }}>● {parsedRows.filter(r => r.status === 'incomplete').length} Incomplete (Importable)</span>
                    <span style={{ color: '#DC2626' }}>● {parsedRows.filter(r => r.status === 'invalid').length} Invalid</span>
                    <span style={{ color: '#6366F1' }}>● {parsedRows.filter(r => r.isDuplicate).length} Duplicates (Will skip)</span>
                  </div>
                </div>

                <button
                  onClick={handleExecuteImport}
                  disabled={isImporting || parsedRows.filter(r => r.status !== 'invalid').length === 0}
                  className="btn btn-primary"
                  style={{ borderRadius: '12px', padding: '10px 20px', fontWeight: 800, fontSize: '14px' }}
                >
                  🚀 Confirm & Import {parsedRows.filter(r => r.status !== 'invalid' && !r.isDuplicate).length} Record(s)
                </button>
              </div>

              <div style={{ overflowX: 'auto', maxHeight: '500px' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
                  <thead>
                    <tr style={{ background: 'var(--light-bg)', borderBottom: '1px solid var(--border)', textAlign: 'left' }}>
                      <th style={{ padding: '12px 14px' }}>Status</th>
                      <th style={{ padding: '12px 14px' }}>Guest Name</th>
                      <th style={{ padding: '12px 14px' }}>Date (Preview)</th>
                      {recordType === 'rooms' ? (
                        <>
                          <th style={{ padding: '12px 14px' }}>Room</th>
                          <th style={{ padding: '12px 14px' }}>Nights</th>
                          <th style={{ padding: '12px 14px' }}>Pax</th>
                          <th style={{ padding: '12px 14px' }}>Total Stay</th>
                        </>
                      ) : (
                        <>
                          <th style={{ padding: '12px 14px' }}>Activity</th>
                          <th style={{ padding: '12px 14px' }}>Pax</th>
                          <th style={{ padding: '12px 14px' }}>Grand Total</th>
                        </>
                      )}
                      <th style={{ padding: '12px 14px' }}>Source / Method</th>
                      <th style={{ padding: '12px 14px' }}>Notes / Reason</th>
                    </tr>
                  </thead>
                  <tbody>
                    {parsedRows.map((r, i) => {
                      const bg = r.status === 'invalid'
                        ? 'rgba(239, 68, 68, 0.08)'
                        : (r.isDuplicate ? 'rgba(99, 102, 241, 0.08)' : (r.status === 'incomplete' ? 'rgba(245, 158, 11, 0.08)' : 'transparent'));

                      return (
                        <tr key={r.id} style={{ borderBottom: '1px solid var(--border)', background: bg }}>
                          <td style={{ padding: '10px 14px', whiteSpace: 'nowrap' }}>
                            {r.status === 'valid' && !r.isDuplicate && (
                              <span style={{ color: '#059669', fontWeight: 800, display: 'flex', alignItems: 'center', gap: '4px' }}>
                                <Check size={14} /> Valid
                              </span>
                            )}
                            {r.isDuplicate && (
                              <span style={{ color: '#4F46E5', fontWeight: 800 }}>
                                Duplicate
                              </span>
                            )}
                            {r.status === 'incomplete' && !r.isDuplicate && (
                              <span style={{ color: '#D97706', fontWeight: 800 }}>
                                Incomplete
                              </span>
                            )}
                            {r.status === 'invalid' && (
                              <span style={{ color: '#DC2626', fontWeight: 800 }}>
                                Invalid
                              </span>
                            )}
                          </td>
                          <td style={{ padding: '10px 14px' }}>
                            <input
                              type="text"
                              value={r.raw.guestName || r.raw['Guest Name'] || ''}
                              onChange={(e) => handleCellEdit(r.id, 'guestName', e.target.value)}
                              className="input"
                              style={{ padding: '6px 8px', fontSize: '13px', width: '130px' }}
                            />
                          </td>
                          <td style={{ padding: '10px 14px', whiteSpace: 'nowrap' }}>
                            <div style={{ fontWeight: 700 }}>
                              {recordType === 'rooms' ? r.parsed.arrivalFormatted : r.parsed.activityFormatted}
                            </div>
                            <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                              Raw: {r.raw.arrivalDate || r.raw.activityDate || r.raw['Arrival Date'] || ''}
                            </span>
                          </td>
                          {recordType === 'rooms' ? (
                            <>
                              <td style={{ padding: '10px 14px' }}>
                                <input
                                  type="text"
                                  value={r.raw.roomType || r.raw.room || ''}
                                  onChange={(e) => handleCellEdit(r.id, 'roomType', e.target.value)}
                                  className="input"
                                  style={{ padding: '6px 8px', fontSize: '13px', width: '90px' }}
                                />
                              </td>
                              <td style={{ padding: '10px 14px', fontWeight: 700 }}>
                                {r.parsed.nights}
                              </td>
                              <td style={{ padding: '10px 14px', fontWeight: 700 }}>
                                {r.parsed.adults}A {r.parsed.children > 0 ? `${r.parsed.children}C` : ''}
                              </td>
                              <td style={{ padding: '10px 14px', fontWeight: 800, color: '#059669' }}>
                                ₱{r.parsed.totalStay}
                              </td>
                            </>
                          ) : (
                            <>
                              <td style={{ padding: '10px 14px' }}>
                                <input
                                  type="text"
                                  value={r.raw.activityTitle || r.raw.title || ''}
                                  onChange={(e) => handleCellEdit(r.id, 'activityTitle', e.target.value)}
                                  className="input"
                                  style={{ padding: '6px 8px', fontSize: '13px', width: '150px' }}
                                />
                              </td>
                              <td style={{ padding: '10px 14px', fontWeight: 700 }}>
                                {r.parsed.pax}
                              </td>
                              <td style={{ padding: '10px 14px', fontWeight: 800, color: '#059669' }}>
                                ₱{r.parsed.grandTotal}
                              </td>
                            </>
                          )}
                          <td style={{ padding: '10px 14px', fontSize: '12px' }}>
                            {r.parsed.bookingSource} / {r.parsed.paymentMethod}
                          </td>
                          <td style={{ padding: '10px 14px', fontSize: '12px', color: r.status === 'invalid' ? '#DC2626' : 'var(--text-muted)' }}>
                            {r.errors.length > 0 ? r.errors.join('; ') : (r.warnings.length > 0 ? r.warnings.join('; ') : (r.parsed.note || '-'))}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </div>
      )}

      {/* TAB 2: MANUAL REGISTRATION CARD ENTRY */}
      {activeSubTab === 'single' && (
        <div className="card" style={{ padding: '32px', borderRadius: '24px' }}>
          <h3 style={{ margin: '0 0 8px 0', fontSize: '20px', fontWeight: 800 }}>
            Manual {recordType === 'rooms' ? 'Room Stay' : 'Activity'} Registration Card
          </h3>
          <p style={{ color: 'var(--text-muted)', fontSize: '13px', marginBottom: '24px' }}>
            Transcribe direct paper walk-in cards into the system. Required fields: Guest Name, Date, and Room / Activity.
          </p>

          {singleError && (
            <div style={{ background: '#FEE2E2', border: '1px solid #FECACA', color: '#DC2626', padding: '12px 16px', borderRadius: '12px', marginBottom: '20px', fontSize: '13px', fontWeight: 700 }}>
              ⚠️ {singleError}
            </div>
          )}
          {singleSuccess && (
            <div style={{ background: '#D1FAE5', border: '1px solid #A7F3D0', color: '#065F46', padding: '12px 16px', borderRadius: '12px', marginBottom: '20px', fontSize: '13px', fontWeight: 700 }}>
              ✅ {singleSuccess}
            </div>
          )}

          <form onSubmit={(e) => handleSingleSubmit(e, false)}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: '16px', marginBottom: '20px' }}>
              <div>
                <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>Guest Name *</label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Juan D. Cruz"
                  className="input"
                  value={singleForm.guestName}
                  onChange={(e) => setSingleForm({ ...singleForm, guestName: e.target.value })}
                  style={{ width: '100%' }}
                />
              </div>

              <div>
                <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>Address</label>
                <input
                  type="text"
                  placeholder="e.g. Makati City"
                  className="input"
                  value={singleForm.address}
                  onChange={(e) => setSingleForm({ ...singleForm, address: e.target.value })}
                  style={{ width: '100%' }}
                />
              </div>

              <div>
                <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>Contact Number</label>
                <input
                  type="text"
                  placeholder="e.g. 09171234567"
                  className="input"
                  value={singleForm.contactNumber}
                  onChange={(e) => setSingleForm({ ...singleForm, contactNumber: e.target.value })}
                  style={{ width: '100%' }}
                />
              </div>

              <div>
                <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>Email</label>
                <input
                  type="email"
                  placeholder="e.g. guest@example.com"
                  className="input"
                  value={singleForm.email}
                  onChange={(e) => setSingleForm({ ...singleForm, email: e.target.value })}
                  style={{ width: '100%' }}
                />
              </div>
            </div>

            {recordType === 'rooms' ? (
              <>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '16px', marginBottom: '20px' }}>
                  <div>
                    <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>Arrival Date *</label>
                    <input
                      type="text"
                      required
                      placeholder="MM/DD/YY e.g. 10/02/26"
                      className="input"
                      value={singleForm.arrivalDate}
                      onChange={(e) => setSingleForm({ ...singleForm, arrivalDate: e.target.value })}
                      style={{ width: '100%' }}
                    />
                  </div>
                  <div>
                    <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>Departure Date</label>
                    <input
                      type="text"
                      placeholder="MM/DD/YY e.g. 10/03/26"
                      className="input"
                      value={singleForm.departureDate}
                      onChange={(e) => setSingleForm({ ...singleForm, departureDate: e.target.value })}
                      style={{ width: '100%' }}
                    />
                  </div>
                  <div>
                    <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>No. of Nights</label>
                    <input
                      type="number"
                      min="1"
                      placeholder="1"
                      className="input"
                      value={singleForm.nights}
                      onChange={(e) => setSingleForm({ ...singleForm, nights: e.target.value })}
                      style={{ width: '100%' }}
                    />
                  </div>
                  <div>
                    <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>Room Type / No. *</label>
                    <input
                      type="text"
                      required
                      placeholder="e.g. RY or Rm 001"
                      className="input"
                      value={singleForm.roomType}
                      onChange={(e) => setSingleForm({ ...singleForm, roomType: e.target.value })}
                      style={{ width: '100%' }}
                    />
                  </div>
                </div>

                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '16px', marginBottom: '20px' }}>
                  <div>
                    <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>Rate / Night (₱)</label>
                    <input
                      type="number"
                      placeholder="3730"
                      className="input"
                      value={singleForm.ratePerNight}
                      onChange={(e) => setSingleForm({ ...singleForm, ratePerNight: e.target.value })}
                      style={{ width: '100%' }}
                    />
                  </div>
                  <div>
                    <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>Total Stay Cost (₱)</label>
                    <input
                      type="number"
                      placeholder="Computed automatically if blank"
                      className="input"
                      value={singleForm.totalStay}
                      onChange={(e) => setSingleForm({ ...singleForm, totalStay: e.target.value })}
                      style={{ width: '100%' }}
                    />
                  </div>
                  <div>
                    <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>Adults</label>
                    <input
                      type="number"
                      min="1"
                      className="input"
                      value={singleForm.adults}
                      onChange={(e) => setSingleForm({ ...singleForm, adults: e.target.value })}
                      style={{ width: '100%' }}
                    />
                  </div>
                  <div>
                    <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>Plate Number</label>
                    <input
                      type="text"
                      placeholder="e.g. ABC-1234"
                      className="input"
                      value={singleForm.plateNumber}
                      onChange={(e) => setSingleForm({ ...singleForm, plateNumber: e.target.value })}
                      style={{ width: '100%' }}
                    />
                  </div>
                </div>
              </>
            ) : (
              // Activity Fields
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '16px', marginBottom: '20px' }}>
                <div>
                  <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>Activity Date *</label>
                  <input
                    type="text"
                    required
                    placeholder="MM/DD/YY e.g. 10/02/26"
                    className="input"
                    value={singleForm.arrivalDate}
                    onChange={(e) => setSingleForm({ ...singleForm, arrivalDate: e.target.value })}
                    style={{ width: '100%' }}
                  />
                </div>
                <div>
                  <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>Activity Title *</label>
                  <input
                    type="text"
                    required
                    placeholder="e.g. Boatride to falls with meal"
                    className="input"
                    value={singleForm.activityTitle}
                    onChange={(e) => setSingleForm({ ...singleForm, activityTitle: e.target.value })}
                    style={{ width: '100%' }}
                  />
                </div>
                <div>
                  <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>Pax</label>
                  <input
                    type="number"
                    min="1"
                    className="input"
                    value={singleForm.pax}
                    onChange={(e) => setSingleForm({ ...singleForm, pax: e.target.value })}
                    style={{ width: '100%' }}
                  />
                </div>
                <div>
                  <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>Price / Pax (₱)</label>
                  <input
                    type="number"
                    placeholder="2000"
                    className="input"
                    value={singleForm.pricePerPax}
                    onChange={(e) => setSingleForm({ ...singleForm, pricePerPax: e.target.value })}
                    style={{ width: '100%' }}
                  />
                </div>
              </div>
            )}

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '16px', marginBottom: '24px' }}>
              <div>
                <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>Booking Source</label>
                <select
                  className="input"
                  value={singleForm.bookingSource}
                  onChange={(e) => setSingleForm({ ...singleForm, bookingSource: e.target.value })}
                  style={{ width: '100%' }}
                >
                  <option value="Walk-in">Walk-in</option>
                  <option value="Agoda">Agoda</option>
                  <option value="Booking.com">Booking.com</option>
                  <option value="Facebook/Messenger">Facebook/Messenger</option>
                  <option value="Phone call">Phone call</option>
                  <option value="Website">Website</option>
                  <option value="Mobile app">Mobile app</option>
                  <option value="Other">Other</option>
                </select>
              </div>

              <div>
                <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>Payment Method</label>
                <select
                  className="input"
                  value={singleForm.paymentMethod}
                  onChange={(e) => setSingleForm({ ...singleForm, paymentMethod: e.target.value })}
                  style={{ width: '100%' }}
                >
                  <option value="Cash">Cash</option>
                  <option value="GCash">GCash</option>
                  <option value="Bank transfer">Bank transfer</option>
                  <option value="OTA prepaid">OTA prepaid</option>
                  <option value="Other">Other</option>
                </select>
              </div>

              <div>
                <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>Notes (Card remarks)</label>
                <input
                  type="text"
                  placeholder="e.g. Agoda paid, Paid"
                  className="input"
                  value={singleForm.note}
                  onChange={(e) => setSingleForm({ ...singleForm, note: e.target.value })}
                  style={{ width: '100%' }}
                />
              </div>

              <div>
                <label className="input-label" style={{ fontSize: '11px', fontWeight: 800, textTransform: 'uppercase' }}>Checked In By (Staff)</label>
                <input
                  type="text"
                  placeholder="e.g. Staff Maria"
                  className="input"
                  value={singleForm.checkedInBy}
                  onChange={(e) => setSingleForm({ ...singleForm, checkedInBy: e.target.value })}
                  style={{ width: '100%' }}
                />
              </div>
            </div>

            <div style={{ display: 'flex', gap: '12px', justifyContent: 'flex-end' }}>
              <button
                type="button"
                onClick={(e) => handleSingleSubmit(e, true)}
                className="btn"
                style={{ background: 'var(--light-bg)', color: 'var(--text-main)', border: '1px solid var(--border)', borderRadius: '12px', padding: '12px 20px', fontWeight: 700 }}
              >
                Save and Add Another
              </button>
              <button
                type="submit"
                className="btn btn-primary"
                style={{ borderRadius: '12px', padding: '12px 24px', fontWeight: 800 }}
              >
                Save Record
              </button>
            </div>
          </form>
        </div>
      )}

      {/* TAB 3: IMPORTED BATCHES LIST */}
      {activeSubTab === 'batches' && (
        <div className="card" style={{ padding: '24px', borderRadius: '24px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
            <div>
              <h3 style={{ margin: '0 0 4px 0', fontSize: '18px', fontWeight: 800 }}>Imported Historical Batches</h3>
              <p style={{ margin: 0, fontSize: '13px', color: 'var(--text-muted)' }}>
                Batches loaded into the database. You can rollback or delete any batch without touching live customer bookings.
              </p>
            </div>
            <button
              onClick={loadBatches}
              className="btn"
              style={{ background: 'var(--light-bg)', border: '1px solid var(--border)', borderRadius: '12px', padding: '8px 14px', fontSize: '13px', display: 'flex', alignItems: 'center', gap: '6px' }}
            >
              <RefreshCw size={14} /> Refresh
            </button>
          </div>

          {loadingBatches ? (
            <p style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>Loading batches...</p>
          ) : batches.length === 0 ? (
            <div style={{ textAlign: 'center', padding: '60px 20px', color: 'var(--text-muted)' }}>
              <Database size={40} style={{ opacity: 0.3, marginBottom: '12px' }} />
              <p style={{ margin: 0, fontSize: '15px', fontWeight: 700 }}>No historical import batches found.</p>
              <p style={{ margin: '6px 0 0 0', fontSize: '13px' }}>Upload a CSV or add manual records to view batches here.</p>
            </div>
          ) : (
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
                <thead>
                  <tr style={{ background: 'var(--light-bg)', borderBottom: '1px solid var(--border)', textAlign: 'left' }}>
                    <th style={{ padding: '14px 16px' }}>Batch ID</th>
                    <th style={{ padding: '14px 16px' }}>Target Property</th>
                    <th style={{ padding: '14px 16px' }}>Records</th>
                    <th style={{ padding: '14px 16px' }}>Source</th>
                    <th style={{ padding: '14px 16px' }}>Import Date</th>
                    <th style={{ padding: '14px 16px', textAlign: 'right' }}>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {batches.map(b => (
                    <tr key={b.batchId} style={{ borderBottom: '1px solid var(--border)' }}>
                      <td style={{ padding: '14px 16px', fontWeight: 700 }}>
                        <code>{b.batchId}</code>
                      </td>
                      <td style={{ padding: '14px 16px', fontWeight: 700 }}>
                        {b.propertyName}
                      </td>
                      <td style={{ padding: '14px 16px' }}>
                        <span style={{ background: 'rgba(29, 211, 176, 0.15)', color: 'var(--secondary)', fontWeight: 800, padding: '4px 10px', borderRadius: '12px', fontSize: '12px' }}>
                          {b.recordsCount} bookings
                        </span>
                      </td>
                      <td style={{ padding: '14px 16px', textTransform: 'capitalize' }}>
                        {b.dataSource}
                      </td>
                      <td style={{ padding: '14px 16px', color: 'var(--text-muted)' }}>
                        {b.importedAt ? new Date(b.importedAt).toLocaleDateString() : 'N/A'}
                      </td>
                      <td style={{ padding: '14px 16px', textAlign: 'right' }}>
                        <button
                          onClick={() => handleDeleteBatch(b)}
                          disabled={deletingBatchId === b.batchId}
                          className="btn"
                          style={{
                            background: '#FEE2E2', border: '1px solid #FECACA', color: '#DC2626',
                            borderRadius: '10px', padding: '6px 12px', fontSize: '12px', fontWeight: 800,
                            display: 'inline-flex', alignItems: 'center', gap: '4px'
                          }}
                        >
                          <Trash2 size={13} /> {deletingBatchId === b.batchId ? 'Deleting...' : 'Delete Batch'}
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </div>
  );
};

export default HistoricalDataImport;
