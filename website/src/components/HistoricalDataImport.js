import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, get, push } from 'firebase/database';
import {
  History, ArrowLeft, ShieldAlert, Check, AlertCircle, Hotel, Compass,
  Calendar, User, DollarSign, Tag, CheckCircle2, Camera, Trash2, UploadCloud, X
} from 'lucide-react';
import {
  formatAsDateInput,
  isValidDateMMDDYY,
  parseDateMMDDYY,
  validateField,
  validateEntireForm,
  cleanSpacedString,
  maskSensitive
} from '../utils/historicalImportHelper';

const HistoricalDataImport = ({ profile, uid, onBack }) => {
  const [propertyName, setPropertyName] = useState('My Property');
  const [propertyId, setPropertyId] = useState(uid);
  const [recordType, setRecordType] = useState('Room'); // 'Room' | 'Activity'
  const [maskData, setMaskData] = useState(false);

  // Form State
  const [form, setForm] = useState({
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

  const [errors, setErrors] = useState({});
  const [isLoading, setIsLoading] = useState(false);
  const [statusMessage, setStatusMessage] = useState(null);
  const [isSuccess, setIsSuccess] = useState(false);

  // Attached Photo state
  const [attachedPhotoFile, setAttachedPhotoFile] = useState(null);
  const [photoPreview, setPhotoPreview] = useState(null);
  const [uploadedPhotoUrl, setUploadedPhotoUrl] = useState(null);
  const [isUploadingPhoto, setIsUploadingPhoto] = useState(false);
  const [photoError, setPhotoError] = useState(null);

  const handlePhotoSelect = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setPhotoError(null);
    const validTypes = ['image/jpeg', 'image/png', 'image/webp'];
    const ext = file.name.split('.').pop().toLowerCase();
    if ((!validTypes.includes(file.type) && !['jpg', 'jpeg', 'png', 'webp'].includes(ext)) || file.size > 10 * 1024 * 1024) {
      setPhotoError('Photo must be JPG, PNG, or WEBP and under 10 MB.');
      return;
    }

    setAttachedPhotoFile(file);
    setPhotoPreview(URL.createObjectURL(file));
    setUploadedPhotoUrl(null);
    setIsUploadingPhoto(true);

    try {
      const fd = new FormData();
      fd.append('file', file);
      fd.append('upload_preset', 'resort_unsigned');

      const response = await fetch('https://api.cloudinary.com/v1_1/dnv6ezitm/image/upload', {
        method: 'POST',
        body: fd
      });

      const data = await response.json();
      if (response.ok && data.secure_url) {
        setUploadedPhotoUrl(data.secure_url);
      } else {
        setPhotoError(data.error?.message || 'Failed to upload photo to Cloudinary.');
      }
    } catch (err) {
      setPhotoError(`Photo upload error: ${err.message}`);
    } finally {
      setIsUploadingPhoto(false);
    }
  };

  const removePhoto = () => {
    setAttachedPhotoFile(null);
    if (photoPreview) {
      URL.revokeObjectURL(photoPreview);
    }
    setPhotoPreview(null);
    setUploadedPhotoUrl(null);
    setIsUploadingPhoto(false);
    setPhotoError(null);
  };

  // Fetch logged-in user's property name from properties/<uid>
  useEffect(() => {
    const fetchProp = async () => {
      try {
        if (!uid) return;
        const snap = await get(ref(db, `properties/${uid}`));
        if (snap.exists()) {
          const val = snap.val();
          setPropertyName(val.name || val.title || 'My Property');
          setPropertyId(uid);
        } else {
          // If admin without property node, check all properties
          const allSnap = await get(ref(db, 'properties'));
          if (allSnap.exists()) {
            const first = Object.entries(allSnap.val())[0];
            if (first) {
              setPropertyId(first[0]);
              setPropertyName(first[1].name || first[1].title || 'Partner Resort');
            }
          }
        }
      } catch (err) {
        console.error("Error loading property:", err);
      }
    };
    fetchProp();
  }, [uid]);

  // Handle Date formatting as user types and auto-calculate nights
  const handleDateChange = (field, e) => {
    const rawVal = e.target.value;
    const prevVal = form[field];
    const formatted = formatAsDateInput(rawVal, prevVal);

    setForm(prev => {
      const next = { ...prev, [field]: formatted };

      // Auto-compute nights if both dates are valid
      const arr = field === 'arrivalDate' ? formatted : prev.arrivalDate;
      const dep = field === 'departureDate' ? formatted : prev.departureDate;
      if (isValidDateMMDDYY(arr) && isValidDateMMDDYY(dep)) {
        const arrDate = parseDateMMDDYY(arr);
        const depDate = parseDateMMDDYY(dep);
        if (arrDate && depDate) {
          const diffDays = Math.round((depDate - arrDate) / (1000 * 60 * 60 * 24));
          if (diffDays >= 1) {
            next.nights = String(diffDays);
            // If ratePerNight is present, update totalStay too
            if (next.ratePerNight) {
              const r = parseFloat(next.ratePerNight);
              if (!isNaN(r) && r > 0) {
                next.totalStay = String((r * diffDays).toFixed(2)).replace(/\.00$/, '');
              }
            }
          }
        }
      }

      return next;
    });

    // Validate on change
    const err = validateField(field, formatted, { ...form, [field]: formatted });
    setErrors(prev => ({ ...prev, [field]: err }));
  };

  // Handle generic input change
  const handleChange = (field, val) => {
    setForm(prev => {
      const next = { ...prev, [field]: val };

      // Auto compute total stay when rate or nights changes if totalStay not manually fixed
      if (field === 'ratePerNight' || field === 'nights') {
        const r = parseFloat(field === 'ratePerNight' ? val : prev.ratePerNight);
        const n = parseInt(field === 'nights' ? val : prev.nights, 10);
        if (!isNaN(r) && !isNaN(n) && r >= 0 && n > 0) {
          next.totalStay = String((r * n).toFixed(2)).replace(/\.00$/, '');
        }
      }

      // Auto compute activity grand total
      if (field === 'pricePerPax' || field === 'pax') {
        const p = parseFloat(field === 'pricePerPax' ? val : prev.pricePerPax);
        const paxNum = parseInt(field === 'pax' ? val : prev.pax, 10);
        if (!isNaN(p) && !isNaN(paxNum) && p >= 0 && paxNum > 0) {
          next.totalStay = String((p * paxNum).toFixed(2)).replace(/\.00$/, '');
        }
      }

      return next;
    });

    const err = validateField(field, val, { ...form, [field]: val });
    setErrors(prev => ({ ...prev, [field]: err }));
  };

  // Submit record
  const handleSubmit = async (addAnother = false) => {
    setStatusMessage(null);
    const formErrors = validateEntireForm(form, recordType);
    setErrors(formErrors);

    if (Object.keys(formErrors).length > 0) {
      setStatusMessage('Please correct the highlighted fields before saving.');
      setIsSuccess(false);
      return;
    }

    setIsLoading(true);

    try {
      const arrDt = parseDateMMDDYY(form.arrivalDate);
      if (!arrDt) {
        setStatusMessage('Invalid Arrival Date. Format must be MM/DD/YY.');
        setIsSuccess(false);
        setIsLoading(false);
        return;
      }

      // Clean & sanitize text values
      const guestName = cleanSpacedString(form.guestName);
      let contactNum = cleanSpacedString(form.contactNumber);
      let emailStr = cleanSpacedString(form.email).toLowerCase();
      const address = cleanSpacedString(form.address);
      const nationality = cleanSpacedString(form.nationality) || 'Filipino';
      const checkedInBy = cleanSpacedString(form.checkedInBy);
      const note = cleanSpacedString(form.note);
      const plateNumber = cleanSpacedString(form.plateNumber).toUpperCase();

      if (maskData) {
        if (contactNum) contactNum = maskSensitive(contactNum);
        if (emailStr) emailStr = maskSensitive(emailStr);
      }

      const randSuffix = Math.random().toString(36).substring(2, 8);
      const syntheticTouristUid = `walkin_${Date.now()}_${randSuffix}`;
      const batchId = `web_manual_${Date.now()}`;

      // Payment revenue rules:
      // Cash, GCash, Bank Transfer count toward revenue.
      // Other DOES NOT count toward revenue.
      const isRevenueMethod = ['Cash', 'GCash', 'Bank Transfer'].includes(form.paymentMethod);
      const countsTowardRevenue = isRevenueMethod;
      const paymentStatus = isRevenueMethod ? 'paid' : 'unpaid';

      // Standard display format: "MMM dd, yyyy"
      const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      const arrivalFormatted = `${monthNames[arrDt.getMonth()]} ${String(arrDt.getDate()).padStart(2, '0')}, ${arrDt.getFullYear()}`;

      if (recordType === 'Room') {
        const nights = parseInt(form.nights, 10) || 1;
        let depDt = form.departureDate ? parseDateMMDDYY(form.departureDate) : null;
        if (!depDt) {
          depDt = new Date(arrDt.getTime() + nights * 86400000);
        }
        const departureFormatted = `${monthNames[depDt.getMonth()]} ${String(depDt.getDate()).padStart(2, '0')}, ${depDt.getFullYear()}`;

        const rate = parseFloat(form.ratePerNight) || 0;
        let total = parseFloat(form.totalStay) || 0;
        if (total <= 0 && rate > 0) {
          total = rate * nights;
        }

        const roomType = cleanSpacedString(form.roomType);

        const payload = {
          touristUid: syntheticTouristUid,
          touristName: guestName,
          touristProfilePic: null,
          ownerUid: propertyId,
          propertyName,
          roomId: 'historical',
          roomTitle: roomType,
          activityId: 'historical',
          activityTitle: roomType,
          isActivityBooking: false,
          pricing: {
            basePrice: total,
            addonsTotal: 0,
            taxes: 0,
            grandTotal: total
          },
          totalPrice: total,
          amountPaid: isRevenueMethod ? total : 0,
          nights,
          bookingDate: arrivalFormatted,
          departureDate: departureFormatted,
          checkInDate: arrivalFormatted,
          checkOutDate: departureFormatted,
          ...(uploadedPhotoUrl ? {
            gcashReceipt: uploadedPhotoUrl,
            historicalPhotoUrl: uploadedPhotoUrl
          } : {}),
          status: 'Completed',
          paymentStatus,
          paymentMethod: form.paymentMethod,
          paymentOption: form.paymentOption,
          bookingSource: form.bookingSource,
          adults: parseInt(form.adults, 10) || 1,
          children: parseInt(form.children, 10) || 0,
          plateNumber,
          nationality,
          address,
          contactNumber: contactNum,
          email: emailStr,
          note,
          checkedInBy,
          selectedAddons: [],
          agreedToTerms: true,
          timestamp: arrDt.getTime(),
          createdAt: Date.now(),
          // Flags
          isHistorical: true,
          countsTowardRevenue,
          importBatchId: batchId,
          importedBy: uid,
          importedAt: Date.now(),
          dataSource: 'registration_card'
        };

        await push(ref(db, 'bookings'), payload);
      } else {
        // Activity Booking
        const pax = parseInt(form.pax, 10) || 1;
        const price = parseFloat(form.pricePerPax) || 0;
        const actTitle = cleanSpacedString(form.activityTitle);
        const isBoat = actTitle.toLowerCase().includes('boatride');
        const soloFee = (isBoat && pax === 1) ? 750 : 0;
        const subtotal = price * pax;
        const total = subtotal + soloFee;

        const payload = {
          touristUid: syntheticTouristUid,
          touristName: guestName,
          touristProfilePic: null,
          ownerUid: propertyId,
          propertyName,
          roomId: 'historical',
          roomTitle: actTitle,
          activityId: 'historical',
          activityTitle: actTitle,
          isActivityBooking: true,
          selectedActivities: [
            {
              id: 'historical_act',
              title: actTitle,
              price,
              pax,
              soloFee,
              timeSlot: cleanSpacedString(form.timeSlot),
              arrivalTime: cleanSpacedString(form.timeSlot),
              total
            }
          ],
          pricing: {
            activitiesSubtotal: subtotal,
            soloSurcharges: soloFee,
            mealsTotal: 0,
            grandTotal: total
          },
          totalPrice: total,
          amountPaid: isRevenueMethod ? total : 0,
          nights: 1,
          bookingDate: arrivalFormatted,
          departureDate: arrivalFormatted,
          checkInDate: arrivalFormatted,
          checkOutDate: arrivalFormatted,
          ...(uploadedPhotoUrl ? {
            gcashReceipt: uploadedPhotoUrl,
            historicalPhotoUrl: uploadedPhotoUrl
          } : {}),
          timeSlot: cleanSpacedString(form.timeSlot),
          status: 'Completed',
          paymentStatus,
          paymentMethod: form.paymentMethod,
          paymentOption: 'Full Payment',
          bookingSource: form.bookingSource,
          contactNumber: contactNum,
          email: emailStr,
          note,
          selectedAddons: form.mealAddons ? form.mealAddons.split(';').map(m => m.trim()).filter(Boolean) : [],
          agreedToTerms: true,
          timestamp: arrDt.getTime(),
          createdAt: Date.now(),
          // Flags
          isHistorical: true,
          countsTowardRevenue,
          importBatchId: batchId,
          importedBy: uid,
          importedAt: Date.now(),
          dataSource: 'registration_card'
        };

        await push(ref(db, 'bookings'), payload);
      }

      setIsLoading(false);
      setIsSuccess(true);
      setStatusMessage(`Historical stay for ${guestName} successfully recorded!`);

      if (addAnother) {
        setForm(prev => ({
          ...prev,
          guestName: '',
          email: '',
          contactNumber: '',
          totalStay: '',
          plateNumber: '',
          note: ''
        }));
        removePhoto();
      } else {
        setTimeout(() => {
          if (onBack) onBack();
        }, 1200);
      }
    } catch (err) {
      console.error("Save error:", err);
      setIsLoading(false);
      setIsSuccess(false);
      setStatusMessage(`Failed to save: ${err.message}`);
    }
  };

  const hasErrors = Object.values(errors).some(Boolean);

  const inputStyle = (hasErr) => ({
    width: '100%',
    height: '48px',
    boxSizing: 'border-box',
    padding: '10px 14px',
    borderRadius: '12px',
    fontSize: '13px',
    border: `1px solid ${hasErr ? '#EF4444' : 'var(--border)'}`,
    background: 'var(--surface)',
    color: 'var(--text-main)',
    outline: 'none',
  });

  return (
    <div style={{ maxWidth: '900px', width: '100%', margin: '0 auto', padding: '24px 16px', boxSizing: 'border-box' }}>
      {/* Top Bar with Back Button */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '20px', flexWrap: 'wrap', gap: '10px' }}>
        <button
          onClick={onBack}
          className="btn"
          style={{
            display: 'flex', alignItems: 'center', gap: '8px',
            background: 'var(--light-bg)', color: 'var(--text-main)',
            border: '1px solid var(--border)', padding: '8px 16px', borderRadius: '12px',
            cursor: 'pointer'
          }}
        >
          <ArrowLeft size={16} /> Back to Dashboard
        </button>
        <div style={{ fontSize: '13px', fontWeight: 700, color: 'var(--text-muted)' }}>
          Property: <span style={{ color: 'var(--primary)' }}>{propertyName}</span>
        </div>
      </div>

      {/* Header Banner */}
      <div style={{
        background: 'linear-gradient(135deg, #0F766E 0%, #14B8A6 100%)',
        borderRadius: '24px', padding: '24px', color: 'white', marginBottom: '24px',
        boxShadow: '0 10px 25px -5px rgba(15, 118, 110, 0.25)'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '8px' }}>
          <History size={28} />
          <h2 style={{ margin: 0, fontSize: '20px', fontWeight: 800 }}>Registration Card Entry</h2>
        </div>
        <p style={{ margin: 0, fontSize: '13px', color: 'rgba(255,255,255,0.85)', lineHeight: 1.5 }}>
          Record historical walk-in cards for {propertyName}. Records are stored as Completed stays for defense day analytics and monthly revenue reports.
        </p>
      </div>

      {/* Privacy Notice Box */}
      <div style={{
        background: 'var(--surface)', border: '1px solid var(--border)',
        borderRadius: '16px', padding: '16px', marginBottom: '24px'
      }}>
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: '10px', marginBottom: '12px' }}>
          <ShieldAlert size={20} color="var(--primary)" style={{ flexShrink: 0, marginTop: '2px' }} />
          <div style={{ fontSize: '12px', color: 'var(--text-muted)', lineHeight: 1.5 }}>
            <strong style={{ color: 'var(--text-main)' }}>PH Data Privacy Act:</strong> Only import personal guest data you are authorized to transcribe. You may mask sensitive phone numbers and emails.
          </div>
        </div>
        <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', fontWeight: 700, cursor: 'pointer' }}>
          <input
            type="checkbox"
            checked={maskData}
            onChange={(e) => setMaskData(e.target.checked)}
            style={{ width: '16px', height: '16px', accentColor: 'var(--primary)' }}
          />
          Mask contact number and email (store last 4 digits only)
        </label>
      </div>

      {/* Record Type Toggle Buttons */}
      <div style={{ marginBottom: '24px' }}>
        <label style={{ display: 'block', fontSize: '11px', fontWeight: 800, textTransform: 'uppercase', letterSpacing: '1px', color: 'var(--text-muted)', marginBottom: '8px' }}>
          Record Type
        </label>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '12px' }}>
          <button
            type="button"
            onClick={() => setRecordType('Room')}
            style={{
              padding: '12px', borderRadius: '14px', border: 'none', cursor: 'pointer',
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px',
              fontWeight: 800, fontSize: '14px', transition: 'all 0.2s',
              background: recordType === 'Room' ? 'var(--primary)' : 'var(--light-bg)',
              color: recordType === 'Room' ? 'white' : 'var(--text-main)'
            }}
          >
            <Hotel size={18} /> Room Stay
          </button>
          <button
            type="button"
            onClick={() => setRecordType('Activity')}
            style={{
              padding: '12px', borderRadius: '14px', border: 'none', cursor: 'pointer',
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px',
              fontWeight: 800, fontSize: '14px', transition: 'all 0.2s',
              background: recordType === 'Activity' ? 'var(--primary)' : 'var(--light-bg)',
              color: recordType === 'Activity' ? 'white' : 'var(--text-main)'
            }}
          >
            <Compass size={18} /> Activity Booking
          </button>
        </div>
      </div>

      {/* Form Card */}
      <div style={{
        background: 'var(--surface)', border: '1px solid var(--border)',
        borderRadius: '24px', padding: '28px', marginBottom: '24px', boxSizing: 'border-box'
      }}>
        {/* Section 1: Guest Details */}
        <div style={{ fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', letterSpacing: '1px', color: 'var(--primary)', marginBottom: '16px' }}>
          Guest Information
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: '16px', marginBottom: '16px' }}>
          <div>
            <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Guest Name *</label>
            <input
              type="text"
              value={form.guestName}
              placeholder="e.g. Juan D. Cruz"
              onChange={(e) => handleChange('guestName', e.target.value)}
              style={inputStyle(errors.guestName)}
            />
            {errors.guestName && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.guestName}</div>}
          </div>

          <div>
            <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Contact Number</label>
            <input
              type="text"
              value={form.contactNumber}
              placeholder="09XXXXXXXXX or +639..."
              onChange={(e) => {
                const val = e.target.value.replace(/[^0-9+]/g, '');
                handleChange('contactNumber', val);
              }}
              style={inputStyle(errors.contactNumber)}
            />
            {errors.contactNumber && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.contactNumber}</div>}
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: '16px', marginBottom: '16px' }}>
          <div>
            <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>E-mail Address</label>
            <input
              type="email"
              value={form.email}
              placeholder="guest@example.com"
              onChange={(e) => handleChange('email', e.target.value)}
              style={inputStyle(errors.email)}
            />
            {errors.email && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.email}</div>}
          </div>

          <div>
            <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Address</label>
            <input
              type="text"
              value={form.address}
              placeholder="City / Province"
              onChange={(e) => handleChange('address', e.target.value)}
              style={inputStyle(errors.address)}
            />
            {errors.address && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.address}</div>}
          </div>
        </div>

        <div style={{ marginBottom: '28px' }}>
          <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Nationality</label>
          <input
            type="text"
            value={form.nationality}
            placeholder="Filipino"
            onChange={(e) => handleChange('nationality', e.target.value)}
            style={{ ...inputStyle(errors.nationality), maxWidth: '320px' }}
          />
          {errors.nationality && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.nationality}</div>}
        </div>

        {/* Section 2: Reservation / Activity Details */}
        <div style={{ fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', letterSpacing: '1px', color: 'var(--primary)', marginBottom: '16px' }}>
          {recordType === 'Room' ? 'Reservation Details' : 'Activity Details'}
        </div>

        {recordType === 'Room' ? (
          <>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: '16px', marginBottom: '16px' }}>
              <div>
                <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Arrival Date * (MM/DD/YY)</label>
                <input
                  type="text"
                  value={form.arrivalDate}
                  placeholder="10/02/26"
                  maxLength={8}
                  onChange={(e) => handleDateChange('arrivalDate', e)}
                  style={inputStyle(errors.arrivalDate)}
                />
                {errors.arrivalDate && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.arrivalDate}</div>}
              </div>

              <div>
                <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Departure Date (MM/DD/YY)</label>
                <input
                  type="text"
                  value={form.departureDate}
                  placeholder="10/03/26"
                  maxLength={8}
                  onChange={(e) => handleDateChange('departureDate', e)}
                  style={inputStyle(errors.departureDate)}
                />
                {errors.departureDate && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.departureDate}</div>}
              </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: '16px', marginBottom: '16px' }}>
              <div>
                <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>No. of Nights</label>
                <input
                  type="number"
                  min="1"
                  value={form.nights}
                  onChange={(e) => handleChange('nights', e.target.value)}
                  style={inputStyle(errors.nights)}
                />
                {errors.nights && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.nights}</div>}
              </div>

              <div>
                <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Room Type / No. *</label>
                <input
                  type="text"
                  value={form.roomType}
                  placeholder="e.g. Deluxe Room or Rm 101"
                  onChange={(e) => handleChange('roomType', e.target.value)}
                  style={inputStyle(errors.roomType)}
                />
                {errors.roomType && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.roomType}</div>}
              </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: '16px', marginBottom: '16px' }}>
              <div>
                <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Adults</label>
                <input
                  type="number"
                  min="0"
                  max="50"
                  value={form.adults}
                  onChange={(e) => handleChange('adults', e.target.value)}
                  style={inputStyle(errors.adults)}
                />
                {errors.adults && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.adults}</div>}
              </div>

              <div>
                <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Children</label>
                <input
                  type="number"
                  min="0"
                  max="50"
                  value={form.children}
                  onChange={(e) => handleChange('children', e.target.value)}
                  style={inputStyle(errors.children)}
                />
                {errors.children && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.children}</div>}
              </div>

              <div>
                <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Plate Number</label>
                <input
                  type="text"
                  value={form.plateNumber}
                  placeholder="ABC-1234"
                  onChange={(e) => handleChange('plateNumber', e.target.value)}
                  style={inputStyle(errors.plateNumber)}
                />
                {errors.plateNumber && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.plateNumber}</div>}
              </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: '16px', marginBottom: '28px' }}>
              <div>
                <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Rate per Night (₱)</label>
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  value={form.ratePerNight}
                  placeholder="3730"
                  onChange={(e) => handleChange('ratePerNight', e.target.value)}
                  style={inputStyle(errors.ratePerNight)}
                />
                {errors.ratePerNight && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.ratePerNight}</div>}
              </div>

              <div>
                <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Total Stay Cost (₱)</label>
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  value={form.totalStay}
                  placeholder="3730"
                  onChange={(e) => handleChange('totalStay', e.target.value)}
                  style={inputStyle(errors.totalStay)}
                />
                {errors.totalStay && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.totalStay}</div>}
              </div>
            </div>
          </>
        ) : (
          <>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: '16px', marginBottom: '16px' }}>
              <div>
                <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Activity Date * (MM/DD/YY)</label>
                <input
                  type="text"
                  value={form.arrivalDate}
                  placeholder="10/02/26"
                  maxLength={8}
                  onChange={(e) => handleDateChange('arrivalDate', e)}
                  style={inputStyle(errors.arrivalDate)}
                />
                {errors.arrivalDate && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.arrivalDate}</div>}
              </div>

              <div>
                <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Activity Title *</label>
                <input
                  type="text"
                  value={form.activityTitle}
                  placeholder="Kayak, Boatride to falls, etc."
                  onChange={(e) => handleChange('activityTitle', e.target.value)}
                  style={inputStyle(errors.activityTitle)}
                />
                {errors.activityTitle && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.activityTitle}</div>}
              </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: '16px', marginBottom: '16px' }}>
              <div>
                <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Pax</label>
                <input
                  type="number"
                  min="1"
                  value={form.pax}
                  onChange={(e) => handleChange('pax', e.target.value)}
                  style={inputStyle(errors.pax)}
                />
                {errors.pax && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.pax}</div>}
              </div>

              <div>
                <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Price per Pax (₱)</label>
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  value={form.pricePerPax}
                  placeholder="500"
                  onChange={(e) => handleChange('pricePerPax', e.target.value)}
                  style={inputStyle(errors.pricePerPax)}
                />
                {errors.pricePerPax && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.pricePerPax}</div>}
              </div>
            </div>

            <div style={{ marginBottom: '16px' }}>
              <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Time Slot</label>
              <input
                type="text"
                value={form.timeSlot}
                placeholder="09:00 AM - 10:00 AM"
                onChange={(e) => handleChange('timeSlot', e.target.value)}
                style={inputStyle(false)}
              />
            </div>

            <div style={{ marginBottom: '28px' }}>
              <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Meal Add-ons (semicolon separated)</label>
              <input
                type="text"
                value={form.mealAddons}
                placeholder="Lunch Set Menu (x2)"
                onChange={(e) => handleChange('mealAddons', e.target.value)}
                style={inputStyle(false)}
              />
            </div>
          </>
        )}

        {/* Section 3: Payment & Meta */}
        <div style={{ fontSize: '12px', fontWeight: 800, textTransform: 'uppercase', letterSpacing: '1px', color: 'var(--primary)', marginBottom: '16px' }}>
          Payment & Remarks
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: '16px', marginBottom: '16px' }}>
          <div>
            <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Booking Source</label>
            <select
              value={form.bookingSource}
              onChange={(e) => handleChange('bookingSource', e.target.value)}
              style={inputStyle(false)}
            >
              {['Walk-in', 'Agoda', 'Booking.com', 'Facebook/Messenger', 'Phone call', 'Website', 'Mobile app', 'Other'].map(s => (
                <option key={s} value={s}>{s}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Payment Method *</label>
            <select
              value={form.paymentMethod}
              onChange={(e) => handleChange('paymentMethod', e.target.value)}
              style={inputStyle(false)}
            >
              {['Cash', 'GCash', 'Bank Transfer', 'Other'].map(m => (
                <option key={m} value={m}>{m}</option>
              ))}
            </select>
            <div style={{ fontSize: '11px', color: form.paymentMethod === 'Other' ? '#F59E0B' : 'var(--text-muted)', marginTop: '4px' }}>
              {form.paymentMethod === 'Other'
                ? 'Notice: "Other" method will NOT be counted toward revenue totals.'
                : 'Will be counted toward monthly revenue reports.'}
            </div>
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: '16px', marginBottom: '24px' }}>
          <div>
            <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Card Notes / Remarks</label>
            <input
              type="text"
              value={form.note}
              placeholder="e.g. Paid, Agoda paid"
              onChange={(e) => handleChange('note', e.target.value)}
              style={inputStyle(errors.note)}
            />
            {errors.note && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.note}</div>}
          </div>

          {recordType === 'Room' && (
            <div>
              <label className="input-label" style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>Checked In By (Staff)</label>
              <input
                type="text"
                value={form.checkedInBy}
                placeholder="Staff name"
                onChange={(e) => handleChange('checkedInBy', e.target.value)}
                style={inputStyle(errors.checkedInBy)}
              />
              {errors.checkedInBy && <div style={{ color: '#EF4444', fontSize: '11px', marginTop: '4px' }}>{errors.checkedInBy}</div>}
            </div>
          )}
        </div>

        {/* Section: Attach Photo (Registration Card / Receipt) - Optional */}
        <div style={{
          background: 'var(--light-bg)', padding: '20px', borderRadius: '16px',
          border: '1px solid var(--border)', marginBottom: '24px', width: '100%', maxWidth: '100%', boxSizing: 'border-box'
        }}>
          <div style={{ display: 'flex', alignItems: 'flex-start', gap: '10px', marginBottom: '6px' }}>
            <Camera size={18} color="var(--primary)" style={{ flexShrink: 0, marginTop: '2px' }} />
            <span style={{
              fontSize: '14px', fontWeight: 800, flex: 1, minWidth: 0,
              whiteSpace: 'normal', overflowWrap: 'anywhere'
            }}>
              Attach Photo (Registration Card / Receipt) - Optional
            </span>
          </div>
          <p style={{ margin: '0 0 16px 0', fontSize: '12px', color: 'var(--text-muted)' }}>
            Accepts JPG, PNG, WEBP (Max 10 MB). Stored for audit and record verification.
          </p>

          {attachedPhotoFile ? (
            <div>
              <div style={{ position: 'relative', display: 'inline-block' }}>
                {photoPreview && (
                  <img
                    src={photoPreview}
                    alt="Preview"
                    style={{
                      height: '120px', width: 'auto', maxWidth: '100%', borderRadius: '12px',
                      objectFit: 'cover', border: '2px solid var(--border)', display: 'block'
                    }}
                  />
                )}
                <button
                  type="button"
                  title="Remove"
                  disabled={isUploadingPhoto}
                  onClick={removePhoto}
                  style={{
                    position: 'absolute', top: '6px', right: '6px',
                    width: '26px', height: '26px', borderRadius: '50%',
                    background: 'rgba(0,0,0,0.65)', color: 'white',
                    border: 'none', cursor: isUploadingPhoto ? 'not-allowed' : 'pointer',
                    display: 'flex', alignItems: 'center', justifyContent: 'center'
                  }}
                >
                  <X size={16} />
                </button>
              </div>

              <div style={{ marginTop: '10px' }}>
                {isUploadingPhoto ? (
                  <span style={{ fontSize: '12px', color: '#2563EB', fontWeight: 700, display: 'inline-flex', alignItems: 'center', gap: '8px' }}>
                    <div style={{ width: '14px', height: '14px', border: '2px solid #2563EB', borderTopColor: 'transparent', borderRadius: '50%', animation: 'spin 1s linear infinite' }} />
                    Uploading photo...
                  </span>
                ) : uploadedPhotoUrl ? (
                  <span style={{ fontSize: '12px', color: '#059669', fontWeight: 700, display: 'inline-flex', alignItems: 'center', gap: '6px' }}>
                    <CheckCircle2 size={14} /> Photo uploaded successfully
                  </span>
                ) : null}
              </div>
            </div>
          ) : (
            <div>
              <label
                style={{
                  display: 'inline-flex', alignItems: 'center', gap: '8px',
                  background: 'var(--surface)', color: 'var(--text-main)',
                  border: '1px solid var(--border)', padding: '10px 18px',
                  borderRadius: '12px', fontSize: '13px', fontWeight: 700,
                  cursor: isUploadingPhoto ? 'not-allowed' : 'pointer',
                  transition: 'var(--transition)'
                }}
              >
                <Camera size={16} /> Add Photo
                <input
                  type="file"
                  accept="image/jpeg,image/png,image/webp"
                  onChange={handlePhotoSelect}
                  disabled={isUploadingPhoto}
                  style={{ display: 'none' }}
                />
              </label>
            </div>
          )}

          {photoError && (
            <div style={{
              color: '#DC2626', fontSize: '12px', fontWeight: 700, marginTop: '10px'
            }}>
              {photoError}
            </div>
          )}
        </div>

        {/* Status Alert */}
        {statusMessage && (
          <div style={{
            display: 'flex', alignItems: 'center', gap: '10px',
            padding: '12px 16px', borderRadius: '12px', marginBottom: '20px',
            background: isSuccess ? 'rgba(16, 185, 129, 0.1)' : 'rgba(239, 68, 68, 0.1)',
            border: `1px solid ${isSuccess ? '#10B981' : '#EF4444'}`,
            color: isSuccess ? '#059669' : '#DC2626',
            fontSize: '13px', fontWeight: 700
          }}>
            {isSuccess ? <CheckCircle2 size={18} /> : <AlertCircle size={18} />}
            <div>{statusMessage}</div>
          </div>
        )}

        {/* Action Buttons */}
        <div style={{ display: 'flex', gap: '12px', justifyContent: 'flex-end', flexWrap: 'wrap' }}>
          <button
            type="button"
            className="btn"
            disabled={isLoading || isUploadingPhoto || hasErrors}
            onClick={() => handleSubmit(true)}
            style={{
              background: 'var(--light-bg)', color: 'var(--text-main)',
              border: '1px solid var(--border)', padding: '12px 20px',
              borderRadius: '14px', fontWeight: 700, fontSize: '14px',
              cursor: (isLoading || isUploadingPhoto || hasErrors) ? 'not-allowed' : 'pointer',
              minWidth: '160px'
            }}
          >
            Save & Add Another
          </button>
          <button
            type="button"
            className="btn"
            disabled={isLoading || isUploadingPhoto || hasErrors}
            onClick={() => handleSubmit(false)}
            style={{
              background: 'var(--primary)', color: 'white',
              border: 'none', padding: '12px 24px',
              borderRadius: '14px', fontWeight: 800, fontSize: '14px',
              cursor: (isLoading || isUploadingPhoto || hasErrors) ? 'not-allowed' : 'pointer',
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px',
              minWidth: '140px'
            }}
          >
            {isLoading ? 'Saving...' : 'Save Record'}
          </button>
        </div>
      </div>
    </div>
  );
};

export default HistoricalDataImport;
