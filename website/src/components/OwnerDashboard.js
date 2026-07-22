import React, { useState, useEffect, useMemo } from 'react';
import { db } from '../firebase';
import { ref, onValue, update, remove, get, push, serverTimestamp } from 'firebase/database';
import { Plus, Trash2, Edit3, MessageSquare, Eye, User, QrCode, TrendingUp, Home as HomeIcon, X, AlertCircle, Calendar, CreditCard, PlusSquare, ChevronRight, ShoppingBag, Copy, Printer, Share2, CheckCircle2, Search } from 'lucide-react';
import Chat from './Chat';
import AddRoomModal from './AddRoomModal';
import EditPropertyModal from './EditPropertyModal';
import BookingModal from './BookingModal';
import QrScanner from './QrScanner';
import { format, parse, addDays, isBefore, isAfter } from 'date-fns';
import { encryptText } from '../utils/encryption';

const ChatRoomItem = ({ room, onClick }) => {
  const [photo, setPhoto] = useState(room.otherProfilePic || null);

  useEffect(() => {
    if (room.otherProfilePic) return;

    const fetchPhoto = async () => {
      try {
        const propSnap = await get(ref(db, `properties/${room.otherUid}`));
        if (propSnap.exists()) {
          const data = propSnap.val();
          const imgs = Array.isArray(data.imageUrls) ? data.imageUrls : (data.imageUrls ? Object.values(data.imageUrls) : []);
          if (imgs.length > 0) setPhoto(imgs[0]);
        } else {
          const userSnap = await get(ref(db, `users/${room.otherUid}`));
          if (userSnap.exists() && userSnap.val().profilePicUrl) {
            setPhoto(userSnap.val().profilePicUrl);
          }
        }
      } catch (e) {
        console.error("Chat photo fetch error", e);
      }
    };
    fetchPhoto();
  }, [room.otherUid, room.otherProfilePic]);

  return (
    <div
      className="card chat-room-card"
      style={{ cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '16px', padding: '16px', transition: 'var(--transition)' }}
      onClick={() => onClick(room)}
    >
      <div style={{
        width: '52px', height: '52px', borderRadius: '18px',
        background: 'var(--light-bg)', overflow: 'hidden',
        display: 'flex', justifyContent: 'center', alignItems: 'center', color: 'var(--text-muted)'
      }}>
        {photo ? (
          <img src={photo} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
        ) : (
          <User size={28} />
        )}
      </div>
      <div style={{ flex: 1 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <h4 style={{ margin: 0, fontWeight: 800 }}>{room.otherUserName}</h4>
          <span style={{ fontSize: '10px', color: 'var(--text-muted)' }}>{room.timestamp ? format(new Date(room.timestamp), 'p') : ''}</span>
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '4px' }}>
          <p style={{ margin: 0, fontSize: '13px', color: 'var(--text-muted)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
            View messages
          </p>
          {room.unreadCount > 0 && (
            <span style={{ background: 'var(--primary)', color: 'white', fontSize: '11px', fontWeight: 800, padding: '2px 8px', borderRadius: '12px' }}>
              {room.unreadCount}
            </span>
          )}
        </div>
      </div>
    </div>
  );
};

const OwnerDashboard = ({ profile, uid }) => {
  const [activeTab, setActiveTab] = useState('Rooms');
  const [rooms, setRooms] = useState([]);
  const [bookings, setBookings] = useState([]);
  const [chatRooms, setChatRooms] = useState([]);
  // loading state removed
  const [selectedChat, setSelectedChat] = useState(null);
  const [showAddRoom, setShowAddRoom] = useState(false);
  const [showEditProperty, setShowEditProperty] = useState(false);
  const [showScanner, setShowScanner] = useState(false);
  const [showBreakdownBooking, setShowBreakdownBooking] = useState(null);
  const [breakdownAddonPrices, setBreakdownAddonPrices] = useState({});
  const [showRevenue, setShowRevenue] = useState(false);
  const [roomToEdit, setRoomToEdit] = useState(null);
  const [roomToDisable, setRoomToDisable] = useState(null);
  const [disableStartDate, setDisableStartDate] = useState('');
  const [disableDays, setDisableDays] = useState(1);
  const [roomToDelete, setRoomToDelete] = useState(null);
  const [scannedBooking, setScannedBooking] = useState(null);
  const [scannedViaQr, setScannedViaQr] = useState(false);
  const [previewRoom, setPreviewRoom] = useState(null);
  const [scannedTouristPhoto, setScannedTouristPhoto] = useState(null);
  const [scannedTouristName, setScannedTouristName] = useState('');
  const [scannedTouristGcashName, setScannedTouristGcashName] = useState(null);
  const [scannedTouristGcashNumber, setScannedTouristGcashNumber] = useState(null);
  const [revenueFilter, setRevenueFilter] = useState('All');
  const [revenueYearFilter, setRevenueYearFilter] = useState('All');
  const [expandedMonth, setExpandedMonth] = useState(null);
  const [bookingLimit, setBookingLimit] = useState(10);
  const [roomLimit, setRoomLimit] = useState(8);
  const [bookingFilter, setBookingFilter] = useState('All');
  const [balanceSearchQuery, setBalanceSearchQuery] = useState('');
  const [selectedBalances, setSelectedBalances] = useState({});
  const [confirmAction, setConfirmAction] = useState({ isOpen: false, bookingId: null, newStatus: null, requireReason: false, reason: '', message: '' });
  const [confirmPaymentAction, setConfirmPaymentAction] = useState({ isOpen: false, type: '', payload: null, message: '' });

  const getBalance = (b) => {
    const total = parseFloat(b.totalPrice) || 0;
    const paid = parseFloat(b.amountPaid || (b.paymentOption?.includes('30%') ? total * 0.3 : total)) || 0;
    return total - paid;
  };

  const initiatePaymentAction = (type, payload) => {
    let message = '';
    if (type === 'single') {
      message = 'Are you sure you want to mark this booking as paid?';
    } else if (type === 'selected') {
      message = 'Are you sure you want to mark the selected bookings as paid?';
    } else if (type === 'all') {
      message = 'Are you sure you want to mark all unpaid bookings for this tourist as paid?';
    }
    setConfirmPaymentAction({ isOpen: true, type, payload, message });
  };

  const handleConfirmPayment = async () => {
    const { type, payload } = confirmPaymentAction;
    if (type === 'single') {
      await markAsPaid(payload.bookingId, payload.totalPrice);
    } else if (type === 'selected') {
      await markSelectedAsPaid(payload);
    } else if (type === 'all') {
      await markAllAsPaid(payload);
    }
    setConfirmPaymentAction({ isOpen: false, type: '', payload: null, message: '' });
  };

  const markAsPaid = async (bookingId, total) => {
    try {
      await update(ref(db, `bookings/${bookingId}`), {
        amountPaid: total,
        paymentStatus: 'paid'
      });
    } catch (e) {
      console.error('Error marking as paid:', e);
    }
  };

  const markAllAsPaid = async (touristGroup) => {
    try {
      const updates = {};
      touristGroup.bookings.forEach(b => {
        updates[`bookings/${b.id}/amountPaid`] = parseFloat(b.totalPrice) || 0;
        updates[`bookings/${b.id}/paymentStatus`] = 'paid';
      });
      await update(ref(db), updates);
      
      // Clear selected state for this group
      setSelectedBalances(prev => {
        const next = { ...prev };
        touristGroup.bookings.forEach(b => delete next[b.id]);
        return next;
      });
    } catch (e) {
      console.error('Error marking all as paid:', e);
    }
  };

  const markSelectedAsPaid = async (touristGroup) => {
    try {
      const updates = {};
      touristGroup.bookings.forEach(b => {
        if (selectedBalances[b.id]) {
          updates[`bookings/${b.id}/amountPaid`] = parseFloat(b.totalPrice) || 0;
          updates[`bookings/${b.id}/paymentStatus`] = 'paid';
        }
      });
      if (Object.keys(updates).length > 0) {
        await update(ref(db), updates);
        
        // Clear selected state
        setSelectedBalances(prev => {
          const next = { ...prev };
          touristGroup.bookings.forEach(b => {
            if (next[b.id]) delete next[b.id];
          });
          return next;
        });
      }
    } catch (e) {
      console.error('Error marking selected as paid:', e);
    }
  };

  const toggleBalanceSelection = (bookingId) => {
    setSelectedBalances(prev => ({ ...prev, [bookingId]: !prev[bookingId] }));
  };

  const balancesByTourist = useMemo(() => {
    const grouped = {};
    bookings.forEach(b => {
      const bal = getBalance(b);
      // Only consider active bookings that have a balance
      if (bal > 0 && ['Pending', 'Confirmed', 'Checked In'].includes(b.status || 'Pending')) {
        const tUid = b.touristUid || 'unknown';
        if (!grouped[tUid]) {
          grouped[tUid] = { touristName: b.touristName || 'Unknown', touristUid: tUid, bookings: [], totalBalance: 0 };
        }
        grouped[tUid].bookings.push(b);
        grouped[tUid].totalBalance += bal;
      }
    });
    
    const q = balanceSearchQuery.toLowerCase();
    return Object.values(grouped).filter(g => 
      g.touristName.toLowerCase().includes(q) || 
      g.bookings.some(b => 
        b.id.toLowerCase().includes(q) || 
        (b.bookingDate && b.bookingDate.toLowerCase().includes(q)) ||
        (b.checkInDate && b.checkInDate.toLowerCase().includes(q)) ||
        (b.date && b.date.toLowerCase().includes(q))
      )
    );
  }, [bookings, balanceSearchQuery]);

  const handleCopyReport = (month) => {
    if (!stats.monthlyRevenue[month]) return;
    let reportText = `${month} Sales Report\nTotal Revenue: ₱${stats.monthlyRevenue[month]}\n\nBookings:\n`;
    const details = stats.monthDetails[month] || [];
    details.forEach(b => {
      reportText += `- ${b.room}: ₱${b.amount} (${b.tourist})\n`;
    });

    navigator.clipboard.writeText(reportText).then(() => {
      alert("Report copied to clipboard!");
    }).catch(err => {
      console.error("Failed to copy report", err);
      alert("Failed to copy report.");
    });
  };

  useEffect(() => {
    if (showBreakdownBooking && !showBreakdownBooking.pricing && showBreakdownBooking.selectedAddons?.length > 0) {
      const propId = showBreakdownBooking.propertyId || showBreakdownBooking.ownerUid || uid;
      if (propId) {
        get(ref(db, `properties/${propId}/addonPrices`)).then(snap => {
          if (snap.exists()) {
            setBreakdownAddonPrices(snap.val());
          } else {
            setBreakdownAddonPrices({});
          }
        }).catch(() => setBreakdownAddonPrices({}));
      }
    } else {
      setBreakdownAddonPrices({});
    }
  }, [showBreakdownBooking, uid]);

  useEffect(() => {
    if (!scannedBooking || !scannedBooking.touristUid) return;

    const fetchTouristData = async () => {
      try {
        const userSnap = await get(ref(db, `users/${scannedBooking.touristUid}`));
        if (userSnap.exists()) {
          const val = userSnap.val();
          if (val.profilePicUrl) {
            setScannedTouristPhoto(val.profilePicUrl);
          } else {
            setScannedTouristPhoto(null);
          }
          const tName = val.firstName || val.name || val.fullName;
          const tLast = val.lastName ? ` ${val.lastName}` : '';
          if (tName) setScannedTouristName(`${tName}${tLast}`.trim());
          else setScannedTouristName(scannedBooking.touristName || 'Guest');
          setScannedTouristGcashName(val.gcashName && val.gcashName.trim() ? val.gcashName : 'N/A');
          setScannedTouristGcashNumber(val.gcashNumber && val.gcashNumber.trim() ? val.gcashNumber : 'N/A');
        }
      } catch (e) {
        console.error("Tourist data fetch error", e);
      }
    };
    fetchTouristData();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [scannedBooking?.touristUid]);

  useEffect(() => {
    if (!uid) return;

    // Rooms listener
    const roomsRef = ref(db, `properties/${uid}/roomInventory`);
    const unsubscribeRooms = onValue(roomsRef, (snapshot) => {
      const data = snapshot.val();
      const list = data ? Object.entries(data)
        .map(([id, val]) => ({ id, ...val }))
        .sort((a, b) => {
          const titleA = a.title || '';
          const titleB = b.title || '';
          const titleCompare = titleA.localeCompare(titleB);
          if (titleCompare !== 0) return titleCompare;
          return (b.timestamp || 0) - (a.timestamp || 0);
        }) : [];
      setRooms(list);
    });

    // Bookings listener
    const bookingsRef = ref(db, 'bookings');
    const unsubscribeBookings = onValue(bookingsRef, (snapshot) => {
      const data = snapshot.val();
      const list = data ? Object.entries(data)
        .map(([id, val]) => ({ id, ...val }))
        .filter(b => b.ownerUid === uid)
        .sort((a, b) => {
          const aTime = (typeof a.timestamp === 'number') ? a.timestamp : (a.timestamp && typeof a.timestamp === 'object' ? Date.now() : 0);
          const bTime = (typeof b.timestamp === 'number') ? b.timestamp : (b.timestamp && typeof b.timestamp === 'object' ? Date.now() : 0);
          return bTime - aTime;
        }) : [];
      setBookings(list);
    });

    // Chat Rooms listener
    const chatRoomsRef = ref(db, `chat_rooms/${uid}`);
    const unsubscribeChats = onValue(chatRoomsRef, (snapshot) => {
      const data = snapshot.val();
      const list = data ? Object.entries(data).map(([otherUid, val]) => ({
        otherUid,
        ...val
      })).sort((a, b) => {
        const aTime = a.timestamp;
        const bTime = b.timestamp;
        const aNum = (typeof aTime === 'number') ? aTime : (aTime && typeof aTime === 'object' ? Date.now() : 0);
        const bNum = (typeof bTime === 'number') ? bTime : (bTime && typeof bTime === 'object' ? Date.now() : 0);
        return bNum - aNum;
      }) : [];
      setChatRooms(list);
    });

    return () => {
      unsubscribeRooms();
      unsubscribeBookings();
      unsubscribeChats();
    };
  }, [uid]);

  const stats = useMemo(() => {
    let totalRevenue = 0;
    let totalPending = 0;
    const monthlyRevenue = {};
    const monthlyPending = {};
    const roomSales = {};
    const availableMonths = ['All'];
    const availableYears = ['All'];
    const monthDetails = {};
    const pendingDetails = {};

    bookings.forEach(b => {
      const status = (b.status || '').toLowerCase();

      try {
        const dateStr = b.bookingDate || b.checkInDate || b.date;
        if (dateStr) {
          let date;
          if (dateStr.includes('T')) {
            date = new Date(dateStr);
          } else {
            date = parse(dateStr, 'MMM dd, yyyy', new Date());
          }
          const monthKey = format(date, 'MMMM yyyy');
          const yearKey = format(date, 'yyyy');
          if (!availableMonths.includes(monthKey)) availableMonths.push(monthKey);
          if (!availableYears.includes(yearKey)) availableYears.push(yearKey);

          if (!['cancelled', 'declined', 'refund approved'].includes(status)) {
            const total = parseFloat(b.totalPrice || b.amount || 0);
            let paid = parseFloat(b.amountPaid) || 0;
            const payOption = (b.paymentOption || b.paymentMethod || '').toString().toLowerCase();

            if (paid === 0 && total > 0) {
              if (payOption.includes('30%') || payOption.includes('downpayment')) {
                paid = total * 0.3;
              } else if (payOption.includes('full') || payOption.includes('100%') || b.paymentStatus === 'paid') {
                paid = total;
              }
            }

            // Also fallback to total if completed just in case
            if (['completed', 'checked out'].includes(status) && paid === 0) {
              paid = total;
            }

            const pending = Math.max(0, total - paid);

            if (pending > 0) {
              if (!pendingDetails[monthKey]) pendingDetails[monthKey] = [];
              pendingDetails[monthKey].push({
                room: b.activityTitle || b.roomTitle || b.room || b.roomId || 'Unknown Room',
                date: dateStr,
                parsedDate: date.getTime(),
                nights: b.nights || 1,
                tourist: b.touristName || b.customerName || b.userName || b.name || b.fullName || 'Tourist',
                amount: pending,
                rawBooking: b
              });
            }

            if (paid > 0) {
              if (!monthDetails[monthKey]) monthDetails[monthKey] = [];

              monthDetails[monthKey].push({
                room: b.activityTitle || b.roomTitle || b.room || b.roomId || 'Unknown Room',
                date: dateStr,
                parsedDate: date.getTime(),
                nights: b.nights || 1,
                tourist: b.touristName || b.customerName || b.userName || b.name || b.fullName || 'Tourist',
                amount: paid,
                rawBooking: b
              });
            }

            // Filter logic
            const matchYear = revenueYearFilter === 'All' || yearKey === revenueYearFilter;
            const matchMonth = revenueFilter === 'All' || monthKey === revenueFilter;

            if (matchYear && matchMonth) {
              if (paid > 0) {
                totalRevenue += paid;
                monthlyRevenue[monthKey] = (monthlyRevenue[monthKey] || 0) + paid;
                const room = b.activityTitle || b.roomTitle || 'Unknown Room';
                roomSales[room] = (roomSales[room] || 0) + 1;
              }
              if (pending > 0) {
                totalPending += pending;
                monthlyPending[monthKey] = (monthlyPending[monthKey] || 0) + pending;
              }
            }
          }
        }
      } catch (e) { }
    });

    // Sort bookings inside each month by date (oldest to newest)
    Object.keys(monthDetails).forEach(key => {
      monthDetails[key].sort((a, b) => a.parsedDate - b.parsedDate);
    });
    Object.keys(pendingDetails).forEach(key => {
      pendingDetails[key].sort((a, b) => a.parsedDate - b.parsedDate);
    });

    const bestSeller = Object.keys(roomSales).length > 0
      ? Object.entries(roomSales).reduce((a, b) => a[1] > b[1] ? a : b)[0]
      : "No sales yet";

    return { totalRevenue, totalPending, monthlyRevenue, monthlyPending, bestSeller, roomCount: rooms.length, bookingCount: bookings.length, availableMonths, availableYears, monthDetails, pendingDetails };
  }, [bookings, rooms.length, revenueFilter, revenueYearFilter]);

  const checkConflict = (targetBooking, allBookings) => {
    try {
      const startA = parse(targetBooking.bookingDate, 'MMM dd, yyyy', new Date());
      const endA = addDays(startA, parseInt(targetBooking.nights) || 1);

      return allBookings.some(b => {
        if (b.id === targetBooking.id) return false;
        if (b.activityId !== targetBooking.activityId) return false;

        const status = (b.status || '').toLowerCase();
        if (status !== 'confirmed' && status !== 'checked in') return false;

        const startB = parse(b.bookingDate, 'MMM dd, yyyy', new Date());
        const endB = addDays(startB, parseInt(b.nights) || 1);

        return isBefore(startA, endB) && isAfter(endA, startB);
      });
    } catch (e) {
      console.error("Conflict check error:", e);
      return false;
    }
  };

  const updateUserBalance = async (touristUid) => {
    if (!touristUid) return;
    try {
      const snap = await get(ref(db, 'bookings'));
      if (snap.exists()) {
        let balance = 0;
        const allBookings = snap.val();
        Object.values(allBookings).forEach(b => {
          if (b.touristUid === touristUid) {
            const status = (b.status || '').toLowerCase();
            if (status !== 'cancelled' && status !== 'declined' && status !== 'refund approved') {
              const grandTotal = b.pricing?.grandTotal || b.totalPrice || 0;
              const paid = b.amountPaid || 0;
              balance += (grandTotal - paid);
            }
          }
        });
        balance = Math.max(0, balance);
        await update(ref(db, `users/${touristUid}`), { totalOutstandingBalance: balance });
      }
    } catch (e) {
      console.error("Failed to update user balance", e);
    }
  };

  const updateStatus = async (bookingId, newStatus, providedReason = null) => {
    try {
      let cancellationReason = providedReason;

      if (newStatus === 'Reschedule Approved') {
        const target = bookings.find(b => b.id === bookingId);
        if (target && target.requestedRescheduleDate) {
          await update(ref(db, `bookings/${bookingId}`), {
            status: 'Confirmed',
            bookingDate: target.requestedRescheduleDate,
            nights: target.requestedRescheduleNights || target.nights,
            requestedRescheduleDate: null,
            requestedRescheduleNights: null
          });
          newStatus = 'Confirmed';
        }
      } else if (newStatus === 'Reschedule Declined') {
        const updates = {
          status: 'Confirmed',
          requestedRescheduleDate: null,
          requestedRescheduleNights: null
        };
        if (providedReason) updates.cancellationReason = providedReason;
        await update(ref(db, `bookings/${bookingId}`), updates);
        newStatus = 'Reschedule Request Declined';
      } else {

        if (newStatus === 'Confirmed') {
          const target = bookings.find(b => b.id === bookingId);
          if (target && checkConflict(target, bookings)) {
            alert("Cannot confirm: This booking overlaps with an existing confirmed reservation for the same room.");
            return;
          }

          // Auto-reject overlapping pending bookings
          if (target) {
            const targetStart = new Date(target.bookingDate || target.checkInDate || target.date || target.createdAt);
            const targetNights = parseInt(target.nights || 1);
            const targetEnd = new Date(targetStart);
            targetEnd.setDate(targetEnd.getDate() + targetNights);

            for (const b of bookings) {
              if (b.id !== bookingId && b.status === 'Pending' && (b.activityId === target.activityId || b.roomId === target.roomId)) {
                const bStart = new Date(b.bookingDate || b.checkInDate || b.date || b.createdAt);
                const bNights = parseInt(b.nights || 1);
                const bEnd = new Date(bStart);
                bEnd.setDate(bEnd.getDate() + bNights);

                if (targetStart < bEnd && targetEnd > bStart) {
                  // overlap! reject it.
                  await update(ref(db, `bookings/${b.id}`), {
                    status: 'Declined',
                    cancellationReason: 'Room became unavailable for your selected dates.'
                  });

                  if (b.touristUid) {
                    await push(ref(db, `notifications/${b.touristUid}`), {
                      title: 'Booking Declined',
                      message: `Your booking for "${b.activityTitle || b.roomTitle || 'Room'}" was declined because the room became unavailable for your selected dates.`,
                      type: 'booking_rejected',
                      isRead: false,
                      timestamp: serverTimestamp(),
                    });
                  }
                }
              }
            }
          }
        }

        const bookingRef = ref(db, `bookings/${bookingId}`);
        const updates = { status: newStatus };
        if (cancellationReason) {
          updates.cancellationReason = cancellationReason;
        }

        const targetForUpdate = bookings.find(b => b.id === bookingId);
        if (targetForUpdate && (newStatus === 'Confirmed' || newStatus === 'Checked In' || newStatus === 'Completed')) {
          const grandTotal = targetForUpdate.pricing?.grandTotal || targetForUpdate.totalPrice || 0;
          const paid = targetForUpdate.amountPaid || 0;
          if (paid >= grandTotal) {
            updates.paymentStatus = 'fully_paid';
          } else if (paid > 0) {
            updates.paymentStatus = 'partially_paid';
          } else {
            updates.paymentStatus = 'unpaid';
          }
        }

        await update(bookingRef, updates);
        if (targetForUpdate && targetForUpdate.touristUid) {
          await updateUserBalance(targetForUpdate.touristUid);
        }
      }

      const target = bookings.find(b => b.id === bookingId);
      if (target && target.touristUid) {
        let notifType = 'booking_updated';
        if (newStatus === 'Confirmed') notifType = 'booking_accepted';
        else if (newStatus === 'Cancelled' || newStatus.includes('Declined')) notifType = 'booking_rejected';
        else if (newStatus === 'Completed') notifType = 'booking_completed';

        let message = `Your booking for "${target.activityTitle || target.roomTitle || 'Room'}" is now ${newStatus}.`;
        let sysMessage = `System: Your booking for "${target.activityTitle || target.roomTitle || 'Room'}" is now ${newStatus}.`;

        const roomName = target.activityTitle || target.roomTitle || 'Room';
        if (newStatus === 'Confirmed' || newStatus === 'Approved') {
          message = `Good day! We are pleased to inform you that your booking for "${roomName}" has been officially Approved. We look forward to hosting you!`;
          sysMessage = `System: Good day! We are pleased to inform you that your booking for "${roomName}" has been officially Approved. We look forward to hosting you!`;
        } else if (newStatus === 'Checked In') {
          message = `Welcome to the resort! Your check-in for "${roomName}" is now complete. We hope you have a wonderful stay with us.`;
          sysMessage = `System: Welcome to the resort! Your check-in for "${roomName}" is now complete. We hope you have a wonderful stay with us.`;
        } else if (newStatus === 'Checked Out' || newStatus === 'Completed') {
          message = `Thank you for staying with us in "${roomName}". Your check-out is complete. We hope to see you again soon!`;
          sysMessage = `System: Thank you for staying with us in "${roomName}". Your check-out is complete. We hope to see you again soon!`;
        }

        if (cancellationReason) {
          message += ` Reason: ${cancellationReason}`;
          sysMessage += ` Reason: ${cancellationReason}`;
        }

        await push(ref(db, `notifications/${target.touristUid}`), {
          title: 'Booking Updated',
          message: message,
          type: notifType,
          isRead: false,
          timestamp: serverTimestamp(),
        });

        // Add system chat notification
        const tUid = target.touristUid;
        if (uid && tUid) {
          const ids = [uid, tUid].sort();
          const chatId = ids.join('_');
          const encryptedMessage = encryptText(sysMessage, chatId);

          await push(ref(db, `chats/${chatId}/messages`), {
            senderUid: uid,
            text: encryptedMessage,
            timestamp: serverTimestamp(),
            seen: false
          });

          await update(ref(db, `chat_rooms/${uid}/${tUid}`), {
            lastMessage: encryptedMessage,
            timestamp: serverTimestamp()
          });

          const otherChatRoomRef = ref(db, `chat_rooms/${tUid}/${uid}`);
          const otherSnap = await get(otherChatRoomRef);
          const currentUnread = otherSnap.exists() && otherSnap.val().unreadCount ? otherSnap.val().unreadCount : 0;
          await update(otherChatRoomRef, {
            lastMessage: encryptedMessage,
            timestamp: serverTimestamp(),
            unreadCount: currentUnread + 1
          });
        }
      }
    } catch (err) {
      alert("Status update failed: " + err.message);
    }
  };

  const initiateUpdateStatus = (bookingId, newStatus) => {
    let msg = '';
    let reqReason = false;

    if (newStatus === 'Cancelled') {
      msg = 'Please provide a reason for declining/cancelling this booking:';
      reqReason = true;
    } else if (newStatus === 'Reschedule Declined') {
      msg = 'Please provide a reason for declining this reschedule request:';
      reqReason = true;
    } else if (newStatus === 'Refund Declined') {
      msg = 'Please provide a reason for declining this refund:';
      reqReason = true;
    } else if (newStatus === 'Reschedule Approved') {
      const target = bookings.find(b => b.id === bookingId);
      msg = `Approve reschedule to ${target?.requestedRescheduleDate} (${target?.requestedRescheduleNights || target?.nights} nights)?`;
    } else if (newStatus === 'Refund Approved') {
      msg = `Are you sure you want to approve this refund?`;
    } else if (newStatus === 'Completed') {
      msg = `Are you sure you want to complete the check-out for this guest?`;
    } else {
      msg = `Are you sure you want to mark this booking as ${newStatus}?`;
    }

    setConfirmAction({
      isOpen: true,
      bookingId,
      newStatus,
      requireReason: reqReason,
      reason: '',
      message: msg
    });
  };

  const handleConfirmActionSubmit = async () => {
    if (confirmAction.requireReason && !confirmAction.reason.trim()) {
      alert("Reason is required.");
      return;
    }
    const { bookingId, newStatus, reason } = confirmAction;
    setConfirmAction({ isOpen: false, bookingId: null, newStatus: null, requireReason: false, reason: '', message: '' });
    if (scannedBooking) {
      setScannedBooking(null);
    }
    await updateStatus(bookingId, newStatus, reason);
  };

  const deleteBooking = async (id) => {
    const target = bookings.find(b => b.id === id);
    await remove(ref(db, `bookings/${id}`));
    if (target && target.touristUid) {
      await updateUserBalance(target.touristUid);
    }
  };

  const handleDisableRoomClick = (room) => {
    if (room.isDisabled) {
      update(ref(db, `properties/${uid}/roomInventory/${room.id}`), {
        isDisabled: false,
        disabledStartDate: null,
        disabledDays: null
      });
      return;
    }

    const checkedInBookings = bookings.filter(b => 
      (b.roomId === room.id || b.activityId === room.id || (b.roomTitle && room.title && b.roomTitle === room.title)) &&
      b.status === 'Checked In'
    );

    if (checkedInBookings.length > 0) {
      alert("WARNING: There is currently a tourist checked into this room. You cannot disable it until they check out.");
      return;
    }

    setRoomToDisable(room);
    setDisableStartDate(format(new Date(), 'yyyy-MM-dd'));
    setDisableDays(1);
  };

  const confirmDisableRoom = async () => {
    if (!disableStartDate || disableDays < 1) {
      alert("Please provide a valid start date and number of days.");
      return;
    }

    const disableStart = new Date(disableStartDate);
    const disableEnd = addDays(disableStart, parseInt(disableDays));

    const activeBookingsForRoom = bookings.filter(b => 
      (b.roomId === roomToDisable.id || b.activityId === roomToDisable.id || (b.roomTitle && roomToDisable.title && b.roomTitle === roomToDisable.title)) &&
      ['Pending', 'Confirmed', 'Reschedule Requested'].includes(b.status || 'Pending')
    );

    let conflict = false;
    for (const b of activeBookingsForRoom) {
      if (b.bookingDate) {
        const bookingStart = parse(b.bookingDate, 'MMM dd, yyyy', new Date());
        const nights = parseInt(b.nights) || 1;
        const bookingEnd = addDays(bookingStart, nights);
        
        if (bookingStart < disableEnd && disableStart < bookingEnd) {
          conflict = true;
          break;
        }
      }
    }

    if (conflict) {
      alert("WARNING: The selected disable dates overlap with an existing booking. Please select different dates or cancel/reschedule the bookings first.");
      return;
    }

    await update(ref(db, `properties/${uid}/roomInventory/${roomToDisable.id}`), {
      isDisabled: true,
      disabledStartDate: disableStartDate,
      disabledDays: parseInt(disableDays)
    });
    setRoomToDisable(null);
  };

  const deleteRoom = async (id) => {
    try {
      await remove(ref(db, `properties/${uid}/roomInventory/${id}`));
      setRoomToDelete(null);
    } catch (err) {
      alert('Failed to delete: ' + err.message);
    }
  };

  if (selectedChat) {
    return (
      <Chat
        currentUid={uid}
        otherUserUid={selectedChat.otherUid}
        otherUserName={selectedChat.otherUserName}
        onBack={() => setSelectedChat(null)}
      />
    );
  }

  return (
    <div className="owner-dashboard">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '32px' }}>
        <div className="tab-container" style={{
          display: 'flex', gap: '8px', background: 'rgba(0,0,0,0.03)',
          padding: '6px', borderRadius: '40px'
        }}>
          {['Rooms', 'Bookings', 'Balances', 'Chat'].map(tab => {
            const isChat = tab === 'Chat';
            const isBookings = tab === 'Bookings';
            const totalUnread = isChat ? chatRooms.reduce((sum, room) => sum + (parseInt(room.unreadCount) || 0), 0) : 0;
            const pendingBookings = isBookings ? bookings.filter(b => b.status === 'Pending').length : 0;
            const badgeCount = isChat ? totalUnread : (isBookings ? pendingBookings : 0);

            return (
              <button
                key={tab}
                onClick={() => setActiveTab(tab)}
                style={{
                  padding: '10px 24px',
                  background: activeTab === tab ? 'var(--surface)' : 'transparent',
                  border: 'none',
                  borderRadius: '30px',
                  color: activeTab === tab ? 'var(--primary)' : 'var(--text-muted)',
                  fontWeight: 700,
                  fontSize: '14px',
                  cursor: 'pointer',
                  boxShadow: activeTab === tab ? '0 4px 12px rgba(0,0,0,0.08)' : 'none',
                  transition: 'var(--transition)',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '8px'
                }}
              >
                {tab}
                {badgeCount > 0 && (
                  <span style={{
                    background: isBookings ? '#EF4444' : 'var(--primary)',
                    color: 'white',
                    fontSize: '11px',
                    fontWeight: 800,
                    padding: '2px 8px',
                    borderRadius: '12px'
                  }}>
                    {badgeCount}
                  </span>
                )}
              </button>
            )
          })}
        </div>
        <div style={{ display: 'flex', gap: '12px' }}>
          <button
            className="btn btn-primary"
            style={{
              padding: '12px',
              borderRadius: '16px',
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              border: 'none',
              outline: 'none',
              boxShadow: 'none'
            }}
            onClick={() => { setShowScanner(true); }}
            title="Scan Booking QR"
          >
            <QrCode size={22} />
          </button>
        </div>
      </div>

      {activeTab === 'Rooms' && (
        <section className="view-transition">
          {/* Dashboard Stats */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '16px', marginBottom: '32px' }}>
            <div className="stat-card" onClick={() => document.getElementById('room-inventory')?.scrollIntoView({ behavior: 'smooth' })} style={{ cursor: 'pointer' }}>
              <div style={{ background: 'linear-gradient(135deg, rgba(29,211,176,0.15), rgba(29,211,176,0.05))', padding: '14px', borderRadius: '18px', display: 'inline-flex', marginBottom: '14px' }}>
                <HomeIcon color="var(--secondary)" size={26} />
              </div>
              <div style={{ fontSize: '32px', fontWeight: 900, letterSpacing: '-1px' }}>{stats.roomCount}</div>
              <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.5px', marginTop: '2px' }}>Rooms</div>
            </div>

            <div className="stat-card" onClick={() => setActiveTab('Bookings')} style={{ cursor: 'pointer' }}>
              <div style={{ background: 'linear-gradient(135deg, rgba(251,54,64,0.15), rgba(251,54,64,0.05))', padding: '14px', borderRadius: '18px', display: 'inline-flex', marginBottom: '14px' }}>
                <Calendar color="var(--primary)" size={26} />
              </div>
              <div style={{ fontSize: '32px', fontWeight: 900, letterSpacing: '-1px' }}>{stats.bookingCount}</div>
              <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.5px', marginTop: '2px' }}>Bookings</div>
            </div>

            <div className="stat-card" onClick={() => setShowRevenue(true)} style={{ cursor: 'pointer' }}>
              <div style={{ background: 'linear-gradient(135deg, rgba(16,185,129,0.15), rgba(16,185,129,0.05))', padding: '14px', borderRadius: '18px', display: 'inline-flex', marginBottom: '14px' }}>
                <TrendingUp color="#10B981" size={26} />
              </div>
              <div style={{ fontSize: '26px', fontWeight: 900, letterSpacing: '-1px', color: '#059669' }}>₱{stats.totalRevenue.toLocaleString()}</div>
              <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.5px', marginTop: '2px' }}>Earnings · tap to view</div>
            </div>
          </div>

          <div id="room-inventory" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
              <h3 style={{ margin: 0, fontSize: '22px', fontWeight: 800 }}>Room Inventory</h3>
              <button
                className="btn"
                style={{ background: 'var(--light-bg)', color: 'var(--text-muted)', padding: '8px', borderRadius: '10px', border: '1px solid var(--border)' }}
                onClick={() => setShowEditProperty(true)}
              >
                <Edit3 size={16} />
              </button>
            </div>
            <button
              className="btn btn-secondary"
              onClick={() => { setRoomToEdit(null); setShowAddRoom(true); }}
              style={{ borderRadius: '14px', padding: '10px 20px', cursor: 'pointer' }}
            >
              <Plus size={18} /> Add New Room
            </button>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: '24px' }}>
            {rooms.length > 0 ? (
              <>
                {rooms.slice(0, roomLimit).map(room => {
                  const isConfirmingDelete = roomToDelete === room.id;
                  const imgSrc = (Array.isArray(room.imageUrls) ? room.imageUrls[0] : Object.values(room.imageUrls || {})[0]) || 'https://via.placeholder.com/400x200?text=No+Photo';
                  return (
                    <div key={room.id} className="room-card">
                      {/* Image */}
                      <div style={{ position: 'relative', height: '190px', overflow: 'hidden', cursor: 'pointer' }} onClick={() => setPreviewRoom(room)} title="Click to preview how tourists see this room">
                        <img src={imgSrc} alt={room.title} className="room-card-img" />
                        <div style={{
                          position: 'absolute', inset: 0,
                          background: 'linear-gradient(to top, rgba(0,0,0,0.55) 0%, transparent 55%)'
                        }} />
                        <div style={{
                          position: 'absolute', top: '12px', right: '12px',
                          background: 'rgba(255,255,255,0.95)', backdropFilter: 'blur(8px)',
                          padding: '5px 12px', borderRadius: '10px',
                          fontWeight: 900, color: 'var(--primary)', fontSize: '14px',
                          boxShadow: '0 4px 12px rgba(0,0,0,0.1)'
                        }}>
                          ₱{parseFloat(room.price).toLocaleString()}
                        </div>
                        <div style={{
                          position: 'absolute', top: '12px', left: '12px',
                          background: 'rgba(0,0,0,0.45)', backdropFilter: 'blur(6px)',
                          padding: '4px 10px', borderRadius: '8px',
                          fontWeight: 700, color: 'white', fontSize: '11px', textTransform: 'uppercase', letterSpacing: '0.5px'
                        }}>
                          {room.category}
                        </div>
                        <div style={{ position: 'absolute', bottom: '12px', left: '14px', right: '14px' }}>
                          <h4 style={{ margin: 0, color: 'white', fontSize: '17px', fontWeight: 900, textShadow: '0 1px 4px rgba(0,0,0,0.4)' }}>
                            {room.title}{room.nickname ? ` · ${room.nickname}` : ''}
                          </h4>
                          <p style={{ margin: '2px 0 0 0', color: 'rgba(255,255,255,0.8)', fontSize: '12px', fontWeight: 600 }}>{room.location}</p>
                        </div>
                      </div>

                      {/* Body */}
                      <div style={{ padding: '16px 18px' }}>
                        {room.inclusions && room.inclusions.length > 0 && (
                          <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px', marginBottom: '14px' }}>
                            {(Array.isArray(room.inclusions) ? room.inclusions : Object.values(room.inclusions)).slice(0, 3).map((inc, i) => (
                              <span key={i} style={{ background: 'var(--secondary-soft)', color: 'var(--secondary)', fontSize: '11px', fontWeight: 700, padding: '3px 9px', borderRadius: '8px' }}>{inc}</span>
                            ))}
                            {(Array.isArray(room.inclusions) ? room.inclusions : Object.values(room.inclusions)).length > 3 && (
                              <span style={{ background: '#F1F5F9', color: 'var(--text-muted)', fontSize: '11px', fontWeight: 700, padding: '3px 9px', borderRadius: '8px' }}>+{(Array.isArray(room.inclusions) ? room.inclusions : Object.values(room.inclusions)).length - 3} more</span>
                            )}
                          </div>
                        )}
                        <div style={{ display: 'flex', gap: '10px' }}>
                          <button
                            className="btn"
                            style={{ flex: 1, padding: '9px', background: 'var(--light-bg)', color: 'var(--text-main)', borderRadius: '12px', fontSize: '13px', border: '1px solid var(--border)' }}
                            onClick={() => { setRoomToEdit(room); setShowAddRoom(true); }}
                          >
                            <Edit3 size={15} /> Edit
                          </button>
                          <button
                            className="btn"
                            style={{ flex: 1, padding: '9px', background: isConfirmingDelete ? '#FEE2E2' : 'rgba(239, 68, 68, 0.1)', color: 'var(--primary)', borderRadius: '12px', fontSize: '13px', border: isConfirmingDelete ? '1.5px solid #FECACA' : 'none' }}
                            onClick={() => setRoomToDelete(isConfirmingDelete ? null : room.id)}
                          >
                            <Trash2 size={15} /> {isConfirmingDelete ? 'Cancel' : 'Delete'}
                          </button>
                        </div>

                        <div style={{ marginTop: '14px', borderTop: '1px solid var(--border)', paddingTop: '14px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                          <span style={{ fontSize: '13px', fontWeight: 700, color: room.isDisabled ? 'var(--text-muted)' : 'var(--text-main)' }}>
                            {room.isDisabled ? 'Room Disabled' : 'Available to Book'}
                          </span>
                          <button
                            className="btn"
                            style={{
                              padding: '6px 12px',
                              fontSize: '12px',
                              borderRadius: '8px',
                              background: room.isDisabled ? 'var(--light-bg)' : 'var(--primary-soft)',
                              color: room.isDisabled ? 'var(--text-muted)' : 'var(--primary)',
                              border: room.isDisabled ? '1px solid var(--border)' : '1px solid rgba(251, 54, 64, 0.2)',
                            }}
                            onClick={() => handleDisableRoomClick(room)}
                          >
                            {room.isDisabled ? 'Enable Room' : 'Disable Room'}
                          </button>
                        </div>
                      </div>

                      {/* Inline Delete Confirmation */}
                      {isConfirmingDelete && (
                        <div className="delete-confirm-panel" style={{
                          background: 'linear-gradient(135deg, rgba(239, 68, 68, 0.1), #FFF5F5)',
                          borderTop: '1.5px solid #FEE2E2',
                          padding: '16px 18px',
                        }}>
                          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '12px' }}>
                            <div style={{ background: '#FEE2E2', borderRadius: '50%', width: '32px', height: '32px', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                              <Trash2 size={15} color="#DC2626" />
                            </div>
                            <div>
                              <p style={{ margin: 0, fontWeight: 800, fontSize: '13px', color: '#DC2626' }}>Delete "{room.title}"?</p>
                              <p style={{ margin: 0, fontSize: '11px', color: 'var(--text-muted)', fontWeight: 600 }}>This action cannot be undone.</p>
                            </div>
                          </div>
                          <button
                            className="btn btn-danger"
                            style={{ width: '100%', padding: '10px', borderRadius: '12px', fontSize: '13px' }}
                            onClick={() => deleteRoom(room.id)}
                          >
                            Yes, Delete Permanently
                          </button>
                        </div>
                      )}
                    </div>
                  );
                })}
                {rooms.length > roomLimit && (
                  <div style={{ gridColumn: '1/-1', textAlign: 'center', marginTop: '8px' }}>
                    <button className="btn btn-secondary" onClick={() => setRoomLimit(prev => prev + 8)}>Load More Rooms</button>
                  </div>
                )}
              </>
            ) : (
              <div style={{ gridColumn: '1/-1', textAlign: 'center', padding: '80px 0', opacity: 0.45 }}>
                <HomeIcon size={52} style={{ marginBottom: '16px' }} />
                <p style={{ fontWeight: 700, fontSize: '16px' }}>No rooms in your inventory yet.</p>
                <p style={{ fontWeight: 500, fontSize: '13px', color: 'var(--text-muted)' }}>Click "Add New Room" to get started.</p>
              </div>
            )}
          </div>
        </section>
      )}

      {activeTab === 'Bookings' && (
        <section className="view-transition">
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '24px', flexWrap: 'wrap', gap: '16px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
              <Calendar size={20} color="var(--primary)" />
              <h3 style={{ margin: 0, fontSize: '22px', fontWeight: 800 }}>Reservations</h3>
            </div>

            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <span style={{ fontSize: '13px', fontWeight: 600, color: 'var(--text-muted)' }}>Filter:</span>
              <select
                className="input"
                style={{ width: 'auto', minWidth: '160px', padding: '8px 12px', fontSize: '13px', borderRadius: '12px' }}
                value={bookingFilter}
                onChange={e => { setBookingFilter(e.target.value); setBookingLimit(10); }}
              >
                <option value="All">All Reservations ({bookings.length})</option>
                <option value="Pending">Pending ({bookings.filter(b => b.status === 'Pending').length})</option>
                <option value="Confirmed">Confirmed ({bookings.filter(b => b.status === 'Confirmed').length})</option>
                <option value="Checked In">Checked In ({bookings.filter(b => b.status === 'Checked In').length})</option>
                <option value="Completed">Completed ({bookings.filter(b => b.status === 'Completed').length})</option>
                <option value="Reschedule Requested">Reschedule Requests ({bookings.filter(b => b.status === 'Reschedule Requested').length})</option>
                <option value="Refund Requested">Refund Requests ({bookings.filter(b => b.status === 'Refund Requested').length})</option>
                <option value="Refund Approved">Refund Approved ({bookings.filter(b => b.status === 'Refund Approved').length})</option>
                <option value="Refund Declined">Refund Declined ({bookings.filter(b => b.status === 'Refund Declined').length})</option>
                <option value="Cancelled">Declined / Cancelled ({bookings.filter(b => ['Cancelled', 'Declined'].includes(b.status)).length})</option>
              </select>
            </div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', maxWidth: '800px' }}>
            {(() => {
              const filteredBookings = bookings.filter(b => {
                if (bookingFilter === 'All') return true;
                if (bookingFilter === 'Cancelled') return ['Cancelled', 'Declined'].includes(b.status);
                return b.status === bookingFilter;
              }).sort((a, b) => {
                if (bookingFilter === 'All') {
                  const attentionStatuses = ['Pending', 'Reschedule Requested', 'Refund Requested'];
                  const aNeedsAttention = attentionStatuses.includes(a.status);
                  const bNeedsAttention = attentionStatuses.includes(b.status);
                  if (aNeedsAttention && !bNeedsAttention) return -1;
                  if (!aNeedsAttention && bNeedsAttention) return 1;
                }
                return 0;
              });

              if (filteredBookings.length === 0) {
                return <p style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '60px 0' }}>No {bookingFilter === 'All' ? '' : bookingFilter.toLowerCase()} bookings found.</p>;
              }

              return (
                <>
                  {filteredBookings.slice(0, bookingLimit).map(booking => (
                    <BookingCard
                      key={booking.id}
                      booking={booking}
                      onDelete={() => deleteBooking(booking.id)}
                      onUpdateStatus={initiateUpdateStatus}
                      hasConflict={booking.status === 'Pending' && checkConflict(booking, bookings)}
                      onClick={() => { setScannedViaQr(false); setScannedBooking(booking); }}
                    />
                  ))}
                  {filteredBookings.length > bookingLimit && (
                    <button className="btn btn-secondary" style={{ width: '100%', padding: '14px', borderRadius: '16px' }} onClick={() => setBookingLimit(prev => prev + 10)}>
                      Load More Reservations
                    </button>
                  )}
                </>
              );
            })()}
          </div>
        </section>
      )}

      {activeTab === 'Balances' && (
        <section className="view-transition">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
              <CreditCard size={20} color="var(--primary)" />
              <h3 style={{ margin: 0, fontSize: '22px', fontWeight: 800 }}>Unpaid Balances</h3>
            </div>
            <div style={{ position: 'relative', width: '300px' }}>
              <Search size={18} color="var(--text-muted)" style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)' }} />
              <input
                type="text"
                placeholder="Search name, booking ID, or date (e.g. Jul 19)..."
                className="input"
                style={{ width: '100%', paddingLeft: '40px', borderRadius: '12px' }}
                value={balanceSearchQuery}
                onChange={(e) => setBalanceSearchQuery(e.target.value)}
              />
            </div>
          </div>

          <div style={{ display: 'grid', gap: '20px' }}>
            {balancesByTourist.length > 0 ? balancesByTourist.map(group => (
              <div key={group.touristUid} className="card" style={{ padding: '24px', borderRadius: '24px', border: '1px solid rgba(0,0,0,0.05)' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '20px', paddingBottom: '16px', borderBottom: '1px dashed var(--border)' }}>
                  <div>
                    <h4 style={{ margin: '0 0 4px 0', fontSize: '18px', fontWeight: 800 }}>{group.touristName}</h4>
                    <p style={{ margin: 0, fontSize: '13px', color: 'var(--text-muted)', fontWeight: 600 }}>Total Unpaid Balance: <span style={{ color: 'var(--primary)', fontWeight: 800 }}>₱{group.totalBalance.toLocaleString()}</span></p>
                  </div>
                  {group.bookings.length > 1 && (
                    <div style={{ display: 'flex', gap: '8px' }}>
                      {group.bookings.some(b => selectedBalances[b.id]) && (
                        <button 
                          className="btn" 
                          style={{ background: '#3B82F6', color: 'white', padding: '8px 16px', fontSize: '12px' }}
                          onClick={() => initiatePaymentAction('selected', group)}
                        >
                          Mark Selected Paid
                        </button>
                      )}
                      <button 
                        className="btn" 
                        style={{ background: '#10B981', color: 'white', padding: '8px 16px', fontSize: '12px' }}
                        onClick={() => initiatePaymentAction('all', group)}
                      >
                        Mark All Paid
                      </button>
                    </div>
                  )}
                </div>
                
                <div style={{ display: 'grid', gap: '12px' }}>
                  {group.bookings.map(b => {
                    const bal = getBalance(b);
                    return (
                      <div key={b.id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', background: 'var(--light-bg)', padding: '16px', borderRadius: '16px', border: '1px solid var(--border)' }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                          <input 
                            type="checkbox" 
                            checked={!!selectedBalances[b.id]} 
                            onChange={() => toggleBalanceSelection(b.id)}
                            style={{ width: '18px', height: '18px', cursor: 'pointer' }}
                          />
                          <div>
                            <p style={{ margin: '0 0 4px 0', fontWeight: 700, fontSize: '14px' }}>{b.activityTitle || b.roomTitle}</p>
                            <p style={{ margin: 0, fontSize: '12px', color: 'var(--text-muted)' }}>Booking Ref: {b.id.slice(-6).toUpperCase()} • {b.bookingDate}</p>
                            <p style={{ margin: '4px 0 0 0', fontSize: '13px', fontWeight: 800, color: 'var(--primary)' }}>Balance: ₱{bal.toLocaleString()}</p>
                          </div>
                        </div>
                        <button 
                          className="btn" 
                          style={{ background: 'rgba(16, 185, 129, 0.1)', color: '#059669', padding: '8px 16px', fontSize: '12px', border: '1px solid rgba(16, 185, 129, 0.2)' }}
                          onClick={() => initiatePaymentAction('single', { bookingId: b.id, totalPrice: b.totalPrice })}
                        >
                          Mark as Paid
                        </button>
                      </div>
                    );
                  })}
                </div>
              </div>
            )) : (
              <div style={{ textAlign: 'center', padding: '60px 20px', background: 'var(--surface)', borderRadius: '24px', border: '1px dashed var(--border)' }}>
                <CheckCircle2 size={40} color="#10B981" style={{ marginBottom: '16px' }} />
                <h4 style={{ margin: '0 0 8px 0', fontSize: '18px', fontWeight: 800 }}>All Settled!</h4>
                <p style={{ margin: 0, color: 'var(--text-muted)', fontSize: '14px' }}>No active bookings with unpaid balances.</p>
              </div>
            )}
          </div>
        </section>
      )}

      {activeTab === 'Chat' && (
        <section className="view-transition">
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '24px' }}>
            <MessageSquare size={20} color="var(--secondary)" />
            <h3 style={{ margin: 0, fontSize: '22px', fontWeight: 800 }}>Inquiries</h3>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(350px, 1fr))', gap: '16px' }}>
            {chatRooms.length > 0 ? chatRooms.map(room => (
              <ChatRoomItem key={room.otherUid} room={room} onClick={setSelectedChat} />
            )) : (
              <div style={{ gridColumn: '1/-1', textAlign: 'center', padding: '80px 0', opacity: 0.5 }}>
                <MessageSquare size={48} style={{ marginBottom: '16px' }} />
                <p style={{ fontWeight: 600 }}>No active conversations.</p>
              </div>
            )}
          </div>
        </section>
      )}

      {showRevenue && (
        <div className="modal-overlay" onClick={() => { setShowRevenue(false); setExpandedMonth(null); }} style={{ zIndex: 2000 }}>
          <style>{`
            @media print {
              body * { visibility: hidden; }
              .print-area, .print-area * { visibility: visible; }
              .print-area { position: absolute; left: 0; top: 0; width: 100%; height: auto; }
              .no-print { display: none !important; }
              .modal-content { max-height: none !important; overflow: visible !important; border: none !important; padding: 0 !important; margin: 0 !important; }
            }
          `}</style>
          <div className="card modal-content print-area" onClick={e => e.stopPropagation()} style={{ maxWidth: expandedMonth ? '600px' : '550px', borderRadius: '32px', padding: '32px', transition: 'all 0.3s ease', maxHeight: '90vh', overflowY: 'auto' }}>
            {expandedMonth ? (
              <>
                <div className="no-print" style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '24px' }}>
                  <button onClick={() => setExpandedMonth(null)} className="icon-btn"><ChevronRight size={20} style={{ transform: 'rotate(180deg)' }} /></button>
                  <h3 style={{ margin: 0, fontWeight: 800, flex: 1 }}>{expandedMonth} Report</h3>
                  <button onClick={() => handleCopyReport(expandedMonth)} className="btn btn-primary" style={{ padding: '8px 16px', borderRadius: '12px', fontSize: '13px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                    <Share2 size={16} /> Copy
                  </button>
                  <button onClick={() => window.print()} className="btn btn-secondary" style={{ padding: '8px 16px', borderRadius: '12px', fontSize: '13px', display: 'flex', alignItems: 'center', gap: '6px', border: '1px solid var(--border)' }}>
                    <Printer size={16} /> Print
                  </button>
                  <button onClick={() => { setShowRevenue(false); setExpandedMonth(null); }} className="close-btn"><X size={20} /></button>
                </div>

                <h3 className="print-only" style={{ display: 'none', margin: '0 0 20px 0', fontSize: '24px', fontWeight: 800 }}>{expandedMonth} Report</h3>
                <style>{`@media print { .print-only { display: block !important; } }`}</style>

                <div style={{ background: 'var(--surface)', padding: '24px', borderRadius: '24px', marginBottom: '24px', border: '1px solid var(--border)', textAlign: 'center', display: 'flex', justifyContent: 'space-around' }}>
                  <div>
                    <p style={{ color: 'var(--text-muted)', fontSize: '12px', fontWeight: 700, textTransform: 'uppercase', marginBottom: '8px' }}>Revenue</p>
                    <h2 style={{ color: '#059669', margin: '0 0 8px 0', fontSize: '24px', fontWeight: 900 }}>₱{stats.monthlyRevenue[expandedMonth]?.toLocaleString() || 0}</h2>
                    <span style={{ fontSize: '11px', background: 'var(--light-bg)', padding: '4px 8px', borderRadius: '8px', fontWeight: 700 }}>{stats.monthDetails[expandedMonth]?.length || 0} Paid</span>
                  </div>
                  <div>
                    <p style={{ color: 'var(--text-muted)', fontSize: '12px', fontWeight: 700, textTransform: 'uppercase', marginBottom: '8px' }}>Pending</p>
                    <h2 style={{ color: '#F59E0B', margin: '0 0 8px 0', fontSize: '24px', fontWeight: 900 }}>₱{stats.monthlyPending[expandedMonth]?.toLocaleString() || 0}</h2>
                    <span style={{ fontSize: '11px', background: 'var(--light-bg)', padding: '4px 8px', borderRadius: '8px', fontWeight: 700 }}>{stats.pendingDetails[expandedMonth]?.length || 0} Pending</span>
                  </div>
                  <div>
                    <p style={{ color: 'var(--text-muted)', fontSize: '12px', fontWeight: 700, textTransform: 'uppercase', marginBottom: '8px' }}>Expected Total</p>
                    <h2 style={{ color: 'var(--primary)', margin: '0 0 8px 0', fontSize: '24px', fontWeight: 900 }}>₱{((stats.monthlyRevenue[expandedMonth] || 0) + (stats.monthlyPending[expandedMonth] || 0)).toLocaleString()}</h2>
                  </div>
                </div>

                <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', maxHeight: '50vh', overflowY: 'auto', paddingRight: '4px' }}>
                  {(stats.monthDetails[expandedMonth] || []).map((b, i) => (
                    <div key={`paid-${i}`} style={{ padding: '20px', borderRadius: '20px', background: 'var(--light-bg)', border: '1px solid var(--border)' }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '16px' }}>
                        <h4 style={{ margin: 0, fontSize: '16px', fontWeight: 900 }}>{b.room}</h4>
                        <div style={{ textAlign: 'right' }}>
                          <span style={{ fontSize: '16px', fontWeight: 800, color: '#059669' }}>₱{b.amount.toLocaleString()}</span>
                          <div style={{ fontSize: '11px', color: '#059669', fontWeight: 700 }}>PAID</div>
                        </div>
                      </div>

                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '8px', color: 'var(--text-color)' }}>
                        <User size={16} color="var(--text-muted)" />
                        <span style={{ fontWeight: 600, fontSize: '14px' }}>{b.tourist}</span>
                      </div>

                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '12px', color: 'var(--text-color)' }}>
                        <Calendar size={16} color="var(--text-muted)" />
                        <span style={{ fontSize: '14px' }}>{b.date} ({b.nights} nights)</span>
                      </div>
                    </div>
                  ))}

                  {(stats.pendingDetails[expandedMonth] || []).map((b, i) => (
                    <div key={`pending-${i}`} style={{ padding: '20px', borderRadius: '20px', background: 'var(--surface)', border: '1px dashed #FCD34D' }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '16px' }}>
                        <h4 style={{ margin: 0, fontSize: '16px', fontWeight: 900 }}>{b.room}</h4>
                        <div style={{ textAlign: 'right' }}>
                          <span style={{ fontSize: '16px', fontWeight: 800, color: '#F59E0B' }}>₱{b.amount.toLocaleString()}</span>
                          <div style={{ fontSize: '11px', color: '#F59E0B', fontWeight: 700 }}>PENDING BALANCE</div>
                        </div>
                      </div>

                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '8px', color: 'var(--text-color)' }}>
                        <User size={16} color="var(--text-muted)" />
                        <span style={{ fontWeight: 600, fontSize: '14px' }}>{b.tourist}</span>
                      </div>

                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '12px', color: 'var(--text-color)' }}>
                        <Calendar size={16} color="var(--text-muted)" />
                        <span style={{ fontSize: '14px' }}>{b.date} ({b.nights} nights)</span>
                      </div>
                    </div>
                  ))}
                </div>
              </>
            ) : (
              <>
                <div className="no-print" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
                  <h3 style={{ margin: 0, fontWeight: 800 }}>Sales Report</h3>
                  <div style={{ display: 'flex', gap: '8px' }}>
                    <button onClick={() => window.print()} className="btn btn-secondary" style={{ padding: '8px 16px', borderRadius: '12px', fontSize: '13px' }}>Print Report</button>
                    <button onClick={() => setShowRevenue(false)} className="close-btn"><X size={20} /></button>
                  </div>
                </div>
                <h3 className="print-only" style={{ display: 'none', margin: '0 0 20px 0', fontSize: '24px', fontWeight: 800 }}>Sales Report</h3>

                <div style={{ background: 'var(--light-bg)', padding: '24px', borderRadius: '24px', marginBottom: '32px' }}>
                  <div className="no-print" style={{ marginBottom: '20px', display: 'flex', gap: '12px' }}>
                    <div style={{ flex: 1 }}>
                      <label className="input-label" style={{ display: 'block', marginBottom: '8px', fontSize: '11px', fontWeight: 800, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Filter by Year</label>
                      <select
                        className="input"
                        value={revenueYearFilter}
                        onChange={(e) => setRevenueYearFilter(e.target.value)}
                        style={{ width: '100%', background: 'var(--surface)', color: 'var(--text-main)' }}
                      >
                        {stats.availableYears.map(y => <option key={y} value={y}>{y}</option>)}
                      </select>
                    </div>
                    <div style={{ flex: 1 }}>
                      <label className="input-label" style={{ display: 'block', marginBottom: '8px', fontSize: '11px', fontWeight: 800, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Filter by Month</label>
                      <select
                        className="input"
                        value={revenueFilter}
                        onChange={(e) => setRevenueFilter(e.target.value)}
                        style={{ width: '100%', background: 'var(--surface)', color: 'var(--text-main)' }}
                      >
                        {stats.availableMonths.map(m => <option key={m} value={m}>{m}</option>)}
                      </select>
                    </div>
                  </div>
                  <div style={{ textAlign: 'center' }}>
                    <p style={{ color: 'var(--text-muted)', fontSize: '13px', fontWeight: 700, textTransform: 'uppercase', marginBottom: '8px' }}>Most Booked Room</p>
                    <h2 style={{ color: 'var(--secondary)', margin: '0 0 16px 0', fontSize: '24px', fontWeight: 800 }}>{stats.bestSeller}</h2>
                    <div style={{ borderTop: '1px dashed var(--border-dashed)', paddingTop: '16px', display: 'flex', justifyContent: 'space-around', alignItems: 'center' }}>
                      <div>
                        <p style={{ color: 'var(--text-muted)', fontSize: '11px', fontWeight: 700, textTransform: 'uppercase', marginBottom: '4px' }}>Current Revenue</p>
                        <h2 style={{ color: '#059669', margin: 0, fontSize: '20px', fontWeight: 900 }}>₱{stats.totalRevenue.toLocaleString()}</h2>
                      </div>
                      <div style={{ fontSize: '20px', color: 'var(--text-muted)' }}>+</div>
                      <div>
                        <p style={{ color: 'var(--text-muted)', fontSize: '11px', fontWeight: 700, textTransform: 'uppercase', marginBottom: '4px' }}>Pending Balances</p>
                        <h2 style={{ color: '#F59E0B', margin: 0, fontSize: '20px', fontWeight: 900 }}>₱{stats.totalPending.toLocaleString()}</h2>
                      </div>
                      <div style={{ fontSize: '20px', color: 'var(--text-muted)' }}>=</div>
                      <div>
                        <p style={{ color: 'var(--text-muted)', fontSize: '11px', fontWeight: 700, textTransform: 'uppercase', marginBottom: '4px' }}>Expected Total</p>
                        <h2 style={{ color: 'var(--primary)', margin: 0, fontSize: '20px', fontWeight: 900 }}>₱{(stats.totalRevenue + stats.totalPending).toLocaleString()}</h2>
                      </div>
                    </div>
                  </div>
                </div>

                <h4 style={{ fontSize: '16px', fontWeight: 800, marginBottom: '16px' }}>Monthly Breakdown</h4>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', maxHeight: '40vh', overflowY: 'auto', paddingRight: '4px' }}>
                  {Object.entries(stats.monthlyRevenue).length > 0 ? Object.entries(stats.monthlyRevenue).map(([month, rev]) => (
                    <div
                      key={month}
                      onClick={() => setExpandedMonth(month)}
                      style={{ display: 'flex', justifyContent: 'space-between', padding: '16px', borderRadius: '16px', background: 'var(--light-bg)', border: '1px solid var(--border)', cursor: 'pointer', alignItems: 'center', transition: 'all 0.2s' }}
                      className="month-row-hover"
                    >
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                        <span style={{ fontWeight: 600 }}>{month}</span>
                        <span style={{ fontSize: '10px', background: 'rgba(0,0,0,0.05)', padding: '2px 6px', borderRadius: '10px' }}>
                          {stats.monthDetails[month]?.length || 0} bookings
                        </span>
                      </div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                        <div style={{ textAlign: 'right' }}>
                          <div style={{ fontWeight: 800, color: '#059669' }}>₱{rev.toLocaleString()}</div>
                          {stats.monthlyPending[month] > 0 && (
                            <div style={{ fontSize: '11px', color: '#F59E0B', fontWeight: 700 }}>+ ₱{stats.monthlyPending[month].toLocaleString()} Pending</div>
                          )}
                        </div>
                        <ChevronRight size={16} color="var(--text-muted)" />
                      </div>
                    </div>
                  )) : <p style={{ textAlign: 'center', color: 'var(--text-muted)', fontSize: '14px' }}>No revenue data yet.</p>}
                </div>
              </>
            )}
          </div>
        </div>
      )}

      {showAddRoom && (
        <AddRoomModal
          uid={uid}
          rooms={rooms}
          roomToEdit={roomToEdit}
          onClose={() => { setShowAddRoom(false); setRoomToEdit(null); }}
        />
      )}

      {showEditProperty && <EditPropertyModal uid={uid} onClose={() => setShowEditProperty(false)} />}

      {showScanner && (
        <QrScanner
          onResult={async (booking) => {
            setShowScanner(false);
            setScannedViaQr(true);
            setScannedBooking(booking);
          }}
          onClose={() => setShowScanner(false)}
        />
      )}

      {scannedBooking && (
        <div className="modal-overlay" onClick={() => setScannedBooking(null)} style={{ zIndex: 4000 }}>
          <div className="card modal-content view-transition" onClick={e => e.stopPropagation()} style={{ maxWidth: '550px', borderRadius: '32px', padding: '32px', background: 'var(--surface)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
              <h3 style={{ margin: 0, fontWeight: 800, fontSize: '24px' }}>Verification Result</h3>
              <button onClick={() => setScannedBooking(null)} className="close-btn"><X size={20} /></button>
            </div>

            <div style={{ background: 'var(--light-bg)', padding: '24px', borderRadius: '24px', border: '1px solid var(--border)' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '16px', marginBottom: '24px', paddingBottom: '20px', borderBottom: '1px solid #E5E7EB' }}>
                <div style={{ width: '60px', height: '60px', borderRadius: '18px', background: 'var(--surface)', display: 'flex', justifyContent: 'center', alignItems: 'center', boxShadow: '0 4px 12px rgba(0,0,0,0.05)', overflow: 'hidden' }}>
                  {scannedTouristPhoto ? (
                    <img src={scannedTouristPhoto} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                  ) : (
                    <User size={32} color="var(--secondary)" />
                  )}
                </div>
                <div>
                  <h4 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>{scannedTouristName || scannedBooking.touristName || 'Guest'}</h4>
                  <p style={{ margin: '2px 0 0 0', fontSize: '13px', color: 'var(--text-muted)', fontWeight: 600 }}>Guest Verification</p>
                </div>
              </div>

              <div style={{ display: 'grid', gap: '16px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                  <HomeIcon size={18} color="var(--primary)" />
                  <div>
                    <p style={{ margin: 0, fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Booked Room</p>
                    <p style={{ margin: 0, fontSize: '15px', fontWeight: 800 }}>{scannedBooking.activityTitle || scannedBooking.roomTitle}</p>
                  </div>
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                  <Calendar size={18} color="var(--secondary)" />
                  <div>
                    <p style={{ margin: 0, fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Check-in / Check-out</p>
                    <p style={{ margin: 0, fontSize: '15px', fontWeight: 800 }}>
                      {scannedBooking.bookingDate} - {format(addDays(parse(scannedBooking.bookingDate, 'MMM dd, yyyy', new Date()), parseInt(scannedBooking.nights) || 1), 'MMM dd, yyyy')}
                      <span style={{ color: 'var(--text-muted)', fontWeight: 600, fontSize: '13px', marginLeft: '8px' }}>({scannedBooking.nights} Night/s)</span>
                    </p>
                  </div>
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                  <TrendingUp size={18} color="#10B981" />
                  <div style={{ flex: 1 }}>
                    <p style={{ margin: 0, fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Payment Breakdown</p>
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: '4px' }}>
                      <span style={{ fontSize: '13px', fontWeight: 600 }}>Total:</span>
                      <span style={{ fontSize: '13px', fontWeight: 700 }}>₱{scannedBooking.totalPrice?.toLocaleString()}</span>
                    </div>
                    <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                      <span style={{ fontSize: '13px', fontWeight: 600, color: '#059669' }}>Paid:</span>
                      <span style={{ fontSize: '13px', fontWeight: 800, color: '#059669' }}>₱{(scannedBooking.amountPaid || (scannedBooking.paymentOption?.includes('30%') ? scannedBooking.totalPrice * 0.3 : scannedBooking.totalPrice))?.toLocaleString()}</span>
                    </div>
                    <div style={{ display: 'flex', justifyContent: 'space-between', borderTop: '1px dashed #E5E7EB', marginTop: '4px', paddingTop: '4px' }}>
                      <span style={{ fontSize: '13px', fontWeight: 700 }}>Balance:</span>
                      <span style={{ fontSize: '15px', fontWeight: 900, color: 'var(--primary)' }}>
                        ₱{(scannedBooking.totalPrice - (scannedBooking.amountPaid || (scannedBooking.paymentOption?.includes('30%') ? scannedBooking.totalPrice * 0.3 : scannedBooking.totalPrice)))?.toLocaleString()}
                      </span>
                    </div>
                  </div>
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                  <CreditCard size={18} color="#1D4ED8" />
                  <div>
                    <p style={{ margin: 0, fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Payment Details</p>
                    <p style={{ margin: 0, fontSize: '14px', fontWeight: 700 }}>{scannedBooking.paymentOption || 'Full Payment'} via {scannedBooking.paymentMethod || 'GCash'}</p>
                  </div>
                </div>

                {scannedBooking.status === 'Refund Requested' && (
                  <div style={{ display: 'flex', alignItems: 'flex-start', gap: '12px', background: 'rgba(239, 68, 68, 0.05)', padding: '12px', borderRadius: '12px' }}>
                    <AlertCircle size={18} color="#EF4444" style={{ marginTop: '2px' }} />
                    <div>
                      <p style={{ margin: 0, fontSize: '11px', fontWeight: 700, color: '#EF4444', textTransform: 'uppercase' }}>Refund Request Details</p>
                      <p style={{ margin: '4px 0 0 0', fontSize: '13px', fontWeight: 600 }}>Reason: {scannedBooking.refundReason}</p>
                      <p style={{ margin: '2px 0 0 0', fontSize: '13px', fontWeight: 800 }}>Send To: {scannedTouristGcashName || scannedBooking.gcashName || 'N/A'} ({scannedTouristGcashNumber || scannedBooking.gcashNumber || 'N/A'})</p>
                    </div>
                  </div>
                )}
                {scannedBooking.status === 'Reschedule Requested' && (
                  <div style={{ display: 'flex', alignItems: 'flex-start', gap: '12px', background: 'rgba(79, 70, 229, 0.05)', padding: '12px', borderRadius: '12px', marginTop: '12px' }}>
                    <AlertCircle size={18} color="#4F46E5" style={{ marginTop: '2px' }} />
                    <div>
                      <p style={{ margin: 0, fontSize: '11px', fontWeight: 700, color: '#4F46E5', textTransform: 'uppercase' }}>Reschedule Reason</p>
                      <p style={{ margin: '4px 0 0 0', fontSize: '13px', fontWeight: 600 }}>{scannedBooking.rescheduleReason || 'None provided'}</p>
                    </div>
                  </div>
                )}

                {scannedBooking.selectedAddons && scannedBooking.selectedAddons.length > 0 && (
                  <div style={{ display: 'flex', alignItems: 'flex-start', gap: '12px' }}>
                    <PlusSquare size={18} color="var(--primary)" style={{ marginTop: '2px' }} />
                    <div>
                      <p style={{ margin: 0, fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Add-ons</p>
                      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px', marginTop: '4px' }}>
                        {scannedBooking.selectedAddons.map((a, i) => (
                          <span key={i} style={{ background: 'var(--surface)', padding: '4px 10px', borderRadius: '8px', fontSize: '12px', fontWeight: 700, border: '1px solid var(--border)' }}>{a}</span>
                        ))}
                      </div>
                    </div>
                  </div>
                )}

                <div style={{ marginTop: '16px', display: 'flex', justifyContent: 'center' }}>
                  <button className="btn" style={{ background: 'rgba(79, 70, 229, 0.1)', color: '#4F46E5', fontSize: '13px', fontWeight: 800, border: '1px solid rgba(79, 70, 229, 0.2)', width: '100%', display: 'flex', gap: '8px', alignItems: 'center', justifyContent: 'center' }} onClick={() => setShowBreakdownBooking(scannedBooking)}>
                    <ShoppingBag size={16} /> View Price Breakdown
                  </button>
                </div>
              </div>
            </div>

            <div style={{ display: 'flex', gap: '12px', marginTop: '32px' }}>
              <button className="btn" style={{ flex: 1, background: 'var(--surface)', color: 'var(--text-main)', border: '1px solid var(--border)', fontSize: '13px' }} onClick={() => setScannedBooking(null)}>Close</button>
              {scannedBooking.gcashReceipt && scannedBooking.gcashReceipt !== 'MANUAL_GCASH_PAYMENT' && (
                <a href={scannedBooking.gcashReceipt} target="_blank" rel="noopener noreferrer" className="btn" style={{ background: 'rgba(29, 78, 216, 0.1)', color: '#3B82F6', padding: '10px 16px', fontSize: '13px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                  <Eye size={16} /> View Receipt
                </a>
              )}
            </div>

            {(scannedBooking.ocrStatus || scannedBooking.extractedRefNo) && (
              <div style={{ marginTop: '12px', padding: '12px', background: scannedBooking.ocrStatus === 'Verified' ? 'rgba(16, 185, 129, 0.1)' : 'rgba(245, 158, 11, 0.1)', border: `1px solid ${scannedBooking.ocrStatus === 'Verified' ? 'rgba(16, 185, 129, 0.2)' : 'rgba(245, 158, 11, 0.2)'}`, borderRadius: '12px', display: 'flex', alignItems: 'flex-start', gap: '8px' }}>
                {scannedBooking.ocrStatus === 'Verified' ? <CheckCircle2 size={16} color="#059669" style={{marginTop: '2px'}}/> : <AlertCircle size={16} color="#B45309" style={{marginTop: '2px'}}/>}
                <div>
                  <span style={{ fontSize: '13px', fontWeight: 800, color: scannedBooking.ocrStatus === 'Verified' ? '#059669' : '#B45309', display: 'block' }}>
                    AI Verification: {scannedBooking.ocrStatus === 'Verified' ? 'Passed' : (scannedBooking.ocrStatus === 'Multiple Receipts (Manual Review)' ? 'Multiple Receipts' : 'Flagged for Review')}
                  </span>
                  {scannedBooking.extractedRefNo && (
                    <span style={{ fontSize: '12px', color: scannedBooking.ocrStatus === 'Verified' ? '#059669' : '#B45309', display: 'block', marginTop: '2px' }}>
                      Ref No: {scannedBooking.extractedRefNo}
                    </span>
                  )}
                  {scannedBooking.ocrIssues && (
                    <span style={{ fontSize: '11px', color: '#B45309', display: 'block', marginTop: '4px', fontWeight: 600 }}>
                      Reason: {scannedBooking.ocrIssues}
                    </span>
                  )}
                </div>
              </div>
            )}

            {['Pending', 'Reschedule Requested', 'Refund Requested', 'Confirmed', 'Checked In'].includes(scannedBooking.status || 'Pending') && (
              <div style={{ display: 'flex', gap: '10px', marginTop: '12px' }}>
                {(scannedBooking.status || 'Pending').toLowerCase() === 'pending' && (
                  <>
                    <button className="btn" style={{ background: 'rgba(251, 54, 64, 0.15)', color: 'var(--primary)', flex: 1, fontSize: '13px' }} onClick={() => { initiateUpdateStatus(scannedBooking.id, 'Cancelled'); }}>Decline</button>
                    <button className="btn btn-primary" style={{ flex: 1.5, fontSize: '13px' }} onClick={() => { initiateUpdateStatus(scannedBooking.id, 'Confirmed'); }}>Confirm</button>
                  </>
                )}
                {scannedBooking.status === 'Reschedule Requested' && (
                  <>
                    <button className="btn" style={{ background: 'rgba(251, 54, 64, 0.15)', color: 'var(--primary)', flex: 1, fontSize: '13px' }} onClick={() => { initiateUpdateStatus(scannedBooking.id, 'Reschedule Declined'); }}>Decline Reschedule</button>
                    <button className="btn btn-primary" style={{ flex: 1.5, fontSize: '13px', background: '#059669' }} onClick={() => { initiateUpdateStatus(scannedBooking.id, 'Reschedule Approved'); }}>Approve</button>
                  </>
                )}
                {scannedBooking.status === 'Refund Requested' && (
                  <>
                    <button className="btn" style={{ background: 'rgba(251, 54, 64, 0.15)', color: 'var(--primary)', flex: 1, fontSize: '13px' }} onClick={() => { initiateUpdateStatus(scannedBooking.id, 'Refund Declined'); }}>Decline Refund</button>
                    <button className="btn btn-primary" style={{ flex: 1.5, fontSize: '13px', background: '#059669' }} onClick={() => { initiateUpdateStatus(scannedBooking.id, 'Refund Approved'); }}>Approve</button>
                  </>
                )}
                {(scannedBooking.status || '').toLowerCase() === 'confirmed' && (
                  <>
                    {scannedViaQr ? (
                      (() => {
                        const today = new Date();
                        today.setHours(0, 0, 0, 0);
                        let canCheckIn = true;
                        try {
                          if (scannedBooking.bookingDate) {
                            const bDate = parse(scannedBooking.bookingDate, 'MMM dd, yyyy', new Date());
                            bDate.setHours(0, 0, 0, 0);
                            canCheckIn = today >= bDate;
                          }
                        } catch(e) {}
                        return (
                          <button 
                            className="btn" 
                            style={{ background: canCheckIn ? '#4F46E5' : '#9CA3AF', color: 'white', width: '100%', fontSize: '13px', cursor: canCheckIn ? 'pointer' : 'not-allowed' }} 
                            disabled={!canCheckIn}
                            onClick={() => { initiateUpdateStatus(scannedBooking.id, 'Checked In'); }}
                          >
                            {canCheckIn ? 'Check In Customer' : `Check-in on ${scannedBooking.bookingDate}`}
                          </button>
                        );
                      })()
                    ) : (
                      <div style={{ textAlign: 'center', width: '100%', color: 'var(--primary)', fontSize: '12px', fontWeight: 700, padding: '10px', background: 'rgba(251, 54, 64, 0.1)', borderRadius: '12px' }}>
                        <AlertCircle size={14} style={{ marginBottom: '-2px', marginRight: '4px' }} />
                        Please use the QR Scanner to Check-In the guest.
                      </div>
                    )}
                  </>
                )}
                {(scannedBooking.status || '').toLowerCase() === 'checked in' && (
                  <button className="btn" style={{ background: 'var(--secondary)', color: '#002D24', width: '100%', fontSize: '13px' }} onClick={() => { initiateUpdateStatus(scannedBooking.id, 'Completed'); }}>VERIFY CHECK-OUT</button>
                )}
              </div>
            )}
          </div>
        </div>
      )}

      {showBreakdownBooking && (
        <div className="modal-overlay" onClick={() => setShowBreakdownBooking(null)} style={{ zIndex: 6000 }}>
          <div className="card modal-content" style={{ maxWidth: '450px', background: 'var(--surface)', borderRadius: '24px' }} onClick={e => e.stopPropagation()}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
              <h3 style={{ margin: 0, fontWeight: 800, fontSize: '20px' }}>Price Breakdown</h3>
              <button onClick={() => setShowBreakdownBooking(null)} className="close-btn"><X size={18} /></button>
            </div>

            {(() => {
              const isOldBooking = !showBreakdownBooking.pricing && showBreakdownBooking.selectedAddons?.length > 0;
              let calculatedAddonsTotal = showBreakdownBooking.pricing?.addonsTotal || 0;

              if (isOldBooking) {
                showBreakdownBooking.selectedAddons.forEach(addonStr => {
                  try {
                    const match = addonStr.match(/(.+?)\s*\(x(\d+)\)/);
                    if (match && Object.keys(breakdownAddonPrices).length > 0) {
                      const name = match[1].trim();
                      const qty = parseInt(match[2]);
                      const pricePerUnit = breakdownAddonPrices[name] || 0;
                      calculatedAddonsTotal += pricePerUnit * qty;
                    }
                  } catch (e) { }
                });
              }

              const grandTotal = showBreakdownBooking.pricing?.grandTotal || showBreakdownBooking.totalPrice || 0;
              let basePrice = showBreakdownBooking.pricing?.basePrice || (grandTotal - calculatedAddonsTotal);
              if (basePrice < 0) basePrice = 0;

              return (
                <div style={{ background: 'var(--light-bg)', padding: '20px', borderRadius: '16px', display: 'flex', flexDirection: 'column', gap: '12px', border: '1px solid var(--border)' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', fontWeight: 700 }}>
                    <span style={{ color: 'var(--text-main)' }}>Room Base ({showBreakdownBooking.nights} Night/s)</span>
                    <span style={{ color: 'var(--text-main)' }}>₱{basePrice.toLocaleString()}</span>
                  </div>

                  {(calculatedAddonsTotal > 0 || showBreakdownBooking.selectedAddons?.length > 0) && (
                    <>
                      <div style={{ height: '1px', background: 'var(--border)', margin: '8px 0' }} />
                      <div style={{ fontWeight: 800, fontSize: '12px', color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.5px' }}>ADD-ONS</div>

                      {/* New bookings use addonsList, old bookings use selectedAddons array */}
                      {showBreakdownBooking.pricing?.addonsList?.length > 0 ? (
                        showBreakdownBooking.pricing.addonsList.map((addon, idx) => (
                          <div key={idx} style={{ display: 'flex', justifyContent: 'space-between', fontSize: '14px', color: 'var(--text-muted)' }}>
                            <span>{addon.name}: ₱{(addon.total / addon.quantity).toLocaleString()} (x{addon.quantity})</span>
                            <span style={{ fontWeight: 600 }}>₱{addon.total.toLocaleString()}</span>
                          </div>
                        ))
                      ) : (
                        showBreakdownBooking.selectedAddons?.map((addonStr, idx) => {
                          let displayPrice = "Included in subtotal";
                          let displayName = addonStr;
                          try {
                            const match = addonStr.match(/(.+?)\s*\(x(\d+)\)/);
                            if (match && Object.keys(breakdownAddonPrices).length > 0) {
                              const name = match[1].trim();
                              const qty = parseInt(match[2]);
                              const pricePerUnit = breakdownAddonPrices[name] || 0;
                              if (pricePerUnit > 0) {
                                displayName = `${name}: ₱${pricePerUnit.toLocaleString()} (x${qty})`;
                                displayPrice = `₱${(pricePerUnit * qty).toLocaleString()}`;
                              }
                            }
                          } catch (e) { }
                          return (
                            <div key={idx} style={{ display: 'flex', justifyContent: 'space-between', fontSize: '14px', color: 'var(--text-muted)' }}>
                              <span>{displayName}</span>
                              <span style={{ fontWeight: 600 }}>{displayPrice}</span>
                            </div>
                          );
                        })
                      )}

                      <div style={{ display: 'flex', justifyContent: 'space-between', fontWeight: 700, marginTop: '8px' }}>
                        <span style={{ color: 'var(--text-main)' }}>Add-ons Subtotal</span>
                        <span style={{ color: 'var(--text-main)' }}>₱{calculatedAddonsTotal.toLocaleString()}</span>
                      </div>
                    </>
                  )}

                  <div style={{ height: '2px', background: 'var(--border)', margin: '12px 0' }} />
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <span style={{ fontWeight: 800, fontSize: '16px' }}>Grand Total</span>
                    <span style={{ fontWeight: 900, fontSize: '24px', color: 'var(--primary)' }}>₱{grandTotal.toLocaleString()}</span>
                  </div>

                  {(showBreakdownBooking.amountPaid && showBreakdownBooking.amountPaid < grandTotal) && (
                    <>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '12px' }}>
                        <span style={{ fontWeight: 600, fontSize: '14px', color: 'var(--text-muted)' }}>Amount Paid (Downpayment)</span>
                        <span style={{ fontWeight: 700, fontSize: '14px', color: 'var(--text-main)' }}>₱{showBreakdownBooking.amountPaid.toLocaleString()}</span>
                      </div>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '8px' }}>
                        <span style={{ fontWeight: 800, fontSize: '15px', color: 'var(--text-main)' }}>Outstanding Balance</span>
                        <span style={{ fontWeight: 900, fontSize: '18px', color: '#ff9800' }}>₱{(grandTotal - showBreakdownBooking.amountPaid).toLocaleString()}</span>
                      </div>
                      <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontStyle: 'italic', marginTop: '4px', textAlign: 'right' }}>
                        *To be paid upon check-in
                      </div>
                    </>
                  )}
                </div>
              );
            })()}
            <button className="btn btn-primary" style={{ width: '100%', marginTop: '24px', padding: '14px', fontSize: '15px' }} onClick={() => setShowBreakdownBooking(null)}>Close</button>
          </div>
        </div>
      )}

      {previewRoom && (
        <BookingModal
          room={previewRoom}
          property={{ id: uid, ...profile }}
          user={profile}
          onClose={() => setPreviewRoom(null)}
          isPreview={true}
        />
      )}

      {confirmAction.isOpen && (
        <div className="modal-overlay" onClick={() => setConfirmAction({ ...confirmAction, isOpen: false })} style={{ zIndex: 5000 }}>
          <div className="card modal-content view-transition" onClick={e => e.stopPropagation()} style={{ maxWidth: '400px', borderRadius: '24px', padding: '24px', textAlign: 'center' }}>
            <div style={{ background: 'rgba(29, 211, 176, 0.15)', width: '64px', height: '64px', borderRadius: '50%', display: 'flex', justifyContent: 'center', alignItems: 'center', margin: '0 auto 20px auto' }}>
              <AlertCircle size={32} color="var(--secondary)" />
            </div>
            <h3 style={{ margin: '0 0 12px 0', fontWeight: 800, fontSize: '20px' }}>Confirm Action</h3>
            <p style={{ margin: '0 0 24px 0', fontSize: '14px', color: 'var(--text-muted)' }}>{confirmAction.message}</p>

            {confirmAction.requireReason && (
              <textarea
                className="input"
                placeholder="Enter reason here..."
                value={confirmAction.reason}
                onChange={e => setConfirmAction({ ...confirmAction, reason: e.target.value })}
                style={{ width: '100%', minHeight: '80px', marginBottom: '24px', borderRadius: '12px', resize: 'none' }}
              />
            )}

            <div style={{ display: 'flex', gap: '12px' }}>
              <button
                className="btn"
                style={{ flex: 1, background: 'var(--light-bg)', color: 'var(--text-main)', border: '1px solid var(--border)' }}
                onClick={() => setConfirmAction({ ...confirmAction, isOpen: false })}
              >
                Cancel
              </button>
              <button
                className="btn btn-primary"
                style={{ flex: 1 }}
                onClick={handleConfirmActionSubmit}
              >
                Confirm
              </button>
            </div>
          </div>
        </div>
      )}

      {roomToDisable && (
        <div className="modal-overlay" onClick={() => setRoomToDisable(null)} style={{ zIndex: 5000 }}>
          <div className="card modal-content view-transition" onClick={e => e.stopPropagation()} style={{ maxWidth: '400px', borderRadius: '24px', padding: '32px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
              <h3 style={{ margin: 0, fontWeight: 800, fontSize: '20px' }}>Disable Room</h3>
              <button onClick={() => setRoomToDisable(null)} className="close-btn"><X size={18} /></button>
            </div>
            
            <p style={{ fontSize: '14px', color: 'var(--text-muted)', marginBottom: '20px' }}>
              You are about to disable <strong>{roomToDisable.title}</strong> (e.g., for renovations or repairs). Tourists will not be able to book this room.
            </p>

            <div style={{ marginBottom: '16px' }}>
              <label className="input-label" style={{ display: 'block', fontSize: '11px', fontWeight: 800, color: 'var(--text-muted)', marginBottom: '8px', textTransform: 'uppercase' }}>Disable Start Date</label>
              <input 
                type="date" 
                className="input" 
                style={{ width: '100%' }}
                value={disableStartDate}
                onChange={e => setDisableStartDate(e.target.value)}
                min={format(new Date(), 'yyyy-MM-dd')}
              />
            </div>

            <div style={{ marginBottom: '24px' }}>
              <label className="input-label" style={{ display: 'block', fontSize: '11px', fontWeight: 800, color: 'var(--text-muted)', marginBottom: '8px', textTransform: 'uppercase' }}>Duration (Days)</label>
              <input 
                type="number" 
                className="input" 
                style={{ width: '100%' }}
                value={disableDays}
                onChange={e => setDisableDays(e.target.value)}
                min="1"
                max="365"
              />
            </div>

            <button 
              className="btn btn-primary" 
              style={{ width: '100%', padding: '14px', borderRadius: '12px', fontSize: '14px' }}
              onClick={confirmDisableRoom}
            >
              Confirm Disabling
            </button>
          </div>
        </div>
      )}

      {/* Payment Confirmation Modal */}
      {confirmPaymentAction.isOpen && (
        <div className="modal-overlay" onClick={() => setConfirmPaymentAction({ isOpen: false, type: '', payload: null, message: '' })} style={{ zIndex: 6000 }}>
          <div className="card modal-content view-transition" onClick={e => e.stopPropagation()} style={{ maxWidth: '420px', borderRadius: '32px', padding: '32px', textAlign: 'center' }}>
            <div style={{ width: '64px', height: '64px', borderRadius: '50%', background: 'rgba(16, 185, 129, 0.1)', color: '#10B981', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 16px' }}>
              <CheckCircle2 size={32} />
            </div>
            <h3 style={{ margin: '0 0 12px 0', fontSize: '22px', fontWeight: 800 }}>Confirm Payment</h3>
            <p style={{ marginBottom: '28px', color: 'var(--text-muted)', fontSize: '15px', lineHeight: 1.5 }}>
              {confirmPaymentAction.message}
            </p>
            <div style={{ display: 'flex', gap: '12px' }}>
              <button 
                className="btn btn-secondary" 
                onClick={() => setConfirmPaymentAction({ isOpen: false, type: '', payload: null, message: '' })}
                style={{ flex: 1, padding: '14px', borderRadius: '16px' }}
              >
                Cancel
              </button>
              <button 
                className="btn" 
                onClick={handleConfirmPayment}
                style={{ flex: 1, padding: '14px', borderRadius: '16px', background: 'linear-gradient(135deg, #10B981, #059669)', color: 'white' }}
              >
                Confirm Paid
              </button>
            </div>
          </div>
        </div>
      )}

      <style>{`
        .view-transition { animation: fadeIn 0.35s ease-out; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
        .close-btn { background: var(--light-bg); border: none; width: 36px; height: 36px; border-radius: 50%; display: flex; align-items: center; justify-content: center; cursor: pointer; color: var(--text-main); transition: var(--transition); border: 1px solid var(--border); }
        .close-btn:hover { background: var(--surface); transform: rotate(90deg); }
        .icon-btn { background: var(--light-bg); border: 1px solid var(--border); width: 36px; height: 36px; border-radius: 12px; display: flex; align-items: center; justify-content: center; cursor: pointer; color: var(--text-main); transition: var(--transition); }
        .icon-btn:hover { background: var(--surface); transform: translateX(-4px); }
        .booking-card-hover:hover { transform: translateY(-4px); box-shadow: 0 12px 30px rgba(0,0,0,0.06); border-color: rgba(29, 211, 176, 0.4) !important; }
      `}</style>
    </div>
  );
};

const BookingCard = ({ booking, onDelete, onUpdateStatus, hasConflict, onClick }) => {
  const [photo, setPhoto] = useState(null);
  const [realName, setRealName] = useState(null);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [gcashName, setGcashName] = useState(null);
  const [gcashNumber, setGcashNumber] = useState(null);

  useEffect(() => {
    const fetchTouristData = async () => {
      if (!booking.touristUid) return;
      try {
        const userSnap = await get(ref(db, `users/${booking.touristUid}`));
        if (userSnap.exists()) {
          const val = userSnap.val();
          if (val.profilePicUrl) {
            setPhoto(val.profilePicUrl);
          }
          const tName = val.firstName || val.name || val.fullName;
          const tLast = val.lastName ? ` ${val.lastName}` : '';
          if (tName) setRealName(`${tName}${tLast}`.trim());
          setGcashName(val.gcashName && val.gcashName.trim() ? val.gcashName : 'N/A');
          setGcashNumber(val.gcashNumber && val.gcashNumber.trim() ? val.gcashNumber : 'N/A');
        }
      } catch (e) {
        console.error("Tourist data fetch error", e);
      }
    };
    fetchTouristData();
  }, [booking.touristUid]);

  return (
    <div className="card booking-card-hover" onClick={onClick} style={{
      position: 'relative',
      marginBottom: '0',
      border: hasConflict ? '2px solid var(--primary)' : '1px solid rgba(0,0,0,0.05)',
      padding: '20px',
      cursor: onClick ? 'pointer' : 'default',
      transition: 'var(--transition)'
    }}>

      <div style={{ display: 'flex', gap: '20px' }}>
        <div style={{ flex: 1 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '12px' }}>
            <div style={{
              width: '44px', height: '44px', borderRadius: '14px',
              background: '#F3F4F6', overflow: 'hidden',
              display: 'flex', justifyContent: 'center', alignItems: 'center', color: 'var(--secondary)'
            }}>
              {photo ? (
                <img src={photo} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
              ) : (
                <User size={22} />
              )}
            </div>
            <div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
                <h4 style={{ margin: 0, fontSize: '16px', fontWeight: 800 }}>{realName || booking.touristName || 'Guest'}</h4>
                {['Pending', 'Reschedule Requested', 'Refund Requested'].includes(booking.status) && (
                  <span style={{ background: '#EF4444', color: 'white', fontSize: '10px', fontWeight: 800, padding: '2px 8px', borderRadius: '12px' }}>
                    Action Needed
                  </span>
                )}
              </div>
              <span className={`status-badge status-${(booking.status || 'pending').toLowerCase().replace(' ', '-')}`}>
                {booking.status || 'Pending'}
              </span>
            </div>
          </div>

          <div style={{ background: 'var(--light-bg)', padding: '16px', borderRadius: '16px', marginBottom: '20px', border: '1px solid var(--border)' }}>
            <p style={{ margin: '0 0 4px 0', fontWeight: 800, fontSize: '15px' }}>{booking.activityTitle || booking.roomTitle}</p>
            <div style={{ fontSize: '13px', color: 'var(--text-muted)', display: 'flex', gap: '12px', flexWrap: 'wrap' }}>
              <span style={{ fontWeight: 700 }}>
                {booking.bookingDate} - {format(addDays(parse(booking.bookingDate, 'MMM dd, yyyy', new Date()), parseInt(booking.nights) || 1), 'MMM dd, yyyy')}
              </span>
              <span>•</span>
              <span>{booking.nights} Night/s</span>
              <span>•</span>
              <span style={{ fontWeight: 800, color: 'var(--secondary)' }}>₱{booking.totalPrice}</span>
            </div>
            {booking.paymentOption && (
              <div style={{ marginTop: '8px', fontSize: '12px', fontWeight: 700, color: 'var(--primary)', display: 'flex', alignItems: 'center', gap: '4px' }}>
                <CreditCard size={14} /> {booking.paymentOption}
              </div>
            )}

            {(booking.ocrStatus || booking.extractedRefNo) && (
              <div style={{ marginTop: '8px', padding: '10px', background: booking.ocrStatus === 'Verified' ? 'rgba(16, 185, 129, 0.1)' : 'rgba(245, 158, 11, 0.1)', border: `1px solid ${booking.ocrStatus === 'Verified' ? 'rgba(16, 185, 129, 0.2)' : 'rgba(245, 158, 11, 0.2)'}`, borderRadius: '10px', display: 'flex', alignItems: 'flex-start', gap: '8px' }}>
                {booking.ocrStatus === 'Verified' ? <CheckCircle2 size={14} color="#059669" style={{marginTop: '2px'}}/> : <AlertCircle size={14} color="#B45309" style={{marginTop: '2px'}}/>}
                <div>
                  <span style={{ fontSize: '12px', fontWeight: 800, color: booking.ocrStatus === 'Verified' ? '#059669' : '#B45309', display: 'block' }}>
                    AI Verification: {booking.ocrStatus === 'Verified' ? 'Passed' : (booking.ocrStatus === 'Multiple Receipts (Manual Review)' ? 'Multiple Receipts' : 'Flagged for Review')}
                  </span>
                  {booking.extractedRefNo && (
                    <span style={{ fontSize: '11px', color: booking.ocrStatus === 'Verified' ? '#059669' : '#B45309', display: 'block', marginTop: '2px', fontWeight: 600 }}>
                      Ref No: {booking.extractedRefNo}
                    </span>
                  )}
                  {booking.ocrIssues && (
                    <span style={{ fontSize: '11px', color: '#B45309', display: 'block', marginTop: '4px', fontWeight: 600 }}>
                      Reason: {booking.ocrIssues}
                    </span>
                  )}
                </div>
              </div>
            )}
            {booking.status === 'Reschedule Requested' && (
              <div style={{ marginTop: '8px', fontSize: '12px', fontWeight: 700, color: '#818CF8', background: 'rgba(79, 70, 229, 0.1)', padding: '8px', borderRadius: '8px' }}>
                <div style={{ marginBottom: '4px' }}>Reschedule to: {booking.requestedRescheduleDate} ({booking.requestedRescheduleNights || booking.nights} Night/s)</div>
                <div>Reason: {booking.rescheduleReason || 'None provided'}</div>
              </div>
            )}
            {booking.status === 'Refund Requested' && (
              <div style={{ marginTop: '8px', fontSize: '12px', fontWeight: 700, color: '#EF4444', background: 'rgba(239, 68, 68, 0.1)', padding: '8px', borderRadius: '8px' }}>
                <div style={{ marginBottom: '4px' }}>Refund Reason: {booking.refundReason}</div>
                <div>Send Refund To: {gcashName || booking.gcashName || 'N/A'} ({gcashNumber || booking.gcashNumber || 'N/A'})</div>
              </div>
            )}

            {booking.cancellationReason && (
              <div style={{ marginTop: '8px', fontSize: '12px', fontWeight: 700, color: '#DC2626', background: '#FEE2E2', padding: '8px', borderRadius: '8px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                <AlertCircle size={14} /> Owner Note/Reason: {booking.cancellationReason}
              </div>
            )}

            <div style={{ marginTop: '16px', display: 'flex', justifyContent: 'center' }}>
              <span style={{ background: 'rgba(79, 70, 229, 0.1)', color: '#818CF8', padding: '8px 16px', borderRadius: '12px', fontSize: '12px', fontWeight: '800', display: 'flex', alignItems: 'center', gap: '6px', border: '1px solid rgba(79, 70, 229, 0.2)', transition: 'var(--transition)' }}>
                <Eye size={14} /> Tap to view full details & actions
              </span>
            </div>
          </div>

          {hasConflict && (
            <div style={{ color: 'var(--primary)', fontSize: '12px', display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '16px', background: 'rgba(251, 54, 64, 0.15)', padding: '10px', borderRadius: '10px', fontWeight: 600 }}>
              <AlertCircle size={16} /> Overlaps with an existing reservation.
            </div>
          )}

        </div>
      </div>
    </div>
  );
};

export default OwnerDashboard;
