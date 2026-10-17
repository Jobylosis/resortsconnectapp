import React, { useState, useEffect, useRef } from 'react';
import { MapContainer, TileLayer, Marker, Popup, Polyline, useMap, useMapEvents } from 'react-leaflet';
import L from 'leaflet';
import { X, Navigation, MapPin, Compass, Clock, Route, RefreshCw, Layers } from 'lucide-react';

// Custom Map Markers
// Real-time Directional Navigation Arrow Marker for User Location
const createUserArrowIcon = (heading = null) => {
  const hasHeading = heading !== null && !isNaN(heading);
  const rot = hasHeading ? Math.round(heading) : 0;
  
  return L.divIcon({
    className: 'custom-user-nav-marker',
    html: `
      <div style="position: relative; width: 44px; height: 44px; display: flex; align-items: center; justify-content: center;">
        <!-- Pulsing radar accuracy ring -->
        <div style="
          position: absolute;
          width: 44px;
          height: 44px;
          border-radius: 50%;
          background: rgba(59, 130, 246, 0.18);
          border: 1px solid rgba(59, 130, 246, 0.4);
          animation: navPulse 2s ease-out infinite;
        "></div>

        <!-- Heading beam / cardinal direction cone (Google Maps style) -->
        ${hasHeading ? `
        <div style="
          position: absolute;
          top: -12px;
          width: 0;
          height: 0;
          border-left: 18px solid transparent;
          border-right: 18px solid transparent;
          border-bottom: 26px solid rgba(59, 130, 246, 0.28);
          transform-origin: 50% 34px;
          transform: rotate(${rot}deg);
          pointer-events: none;
        "></div>
        ` : ''}

        <!-- Rotating Navigation Arrow / Pointer -->
        <div style="
          width: 32px;
          height: 32px;
          border-radius: 50%;
          background: #2563EB;
          border: 3px solid #FFFFFF;
          box-shadow: 0 4px 14px rgba(37, 99, 235, 0.5), 0 2px 6px rgba(0,0,0,0.3);
          display: flex;
          align-items: center;
          justify-content: center;
          position: relative;
          z-index: 2;
        ">
          <!-- Direction Arrow Icon that points to cardinal heading -->
          <svg
            viewBox="0 0 24 24"
            width="20"
            height="20"
            style="
              transform: rotate(${rot}deg);
              transition: transform 0.25s cubic-bezier(0.4, 0, 0.2, 1);
              filter: drop-shadow(0 1px 2px rgba(0,0,0,0.3));
            "
          >
            <!-- Navigation 3D Chevron Arrow (points strictly North at 0deg) -->
            <path d="M12 2L4 21L12 17L20 21L12 2Z" fill="#FFFFFF" />
          </svg>
        </div>
      </div>
    `,
    iconSize: [44, 44],
    iconAnchor: [22, 22],
    popupAnchor: [0, -22],
  });
};

const createIcon = (color, label, isUser = false) => {
  return L.divIcon({
    className: 'custom-map-marker',
    html: `
      <div style="
        background: ${color};
        color: white;
        width: ${isUser ? '34px' : '30px'};
        height: ${isUser ? '34px' : '30px'};
        border-radius: 50% 50% 50% 0;
        transform: rotate(-45deg);
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: 0 4px 12px rgba(0,0,0,0.4);
        border: 2px solid white;
      ">
        <div style="transform: rotate(45deg); font-size: ${isUser ? '14px' : '12px'}; font-weight: 800;">
          ${label}
        </div>
      </div>
    `,
    iconSize: [32, 32],
    iconAnchor: [16, 32],
    popupAnchor: [0, -28],
  });
};

const resortIcon = (num, isSelected) => createIcon(isSelected ? '#EF4444' : '#1DD3B0', num);

// Component to handle map clicks for user pin repositioning
const MapClickHandler = ({ onMapClick }) => {
  useMapEvents({
    click(e) {
      onMapClick(e.latlng);
    },
  });
  return null;
};

// Component to recenter/fit bounds smoothly and invalidate map size
const MapAutoFitter = ({ userLocation, destinationLocation }) => {
  const map = useMap();
  useEffect(() => {
    if (!map) return;
    const timer = setTimeout(() => {
      map.invalidateSize();
      if (userLocation && destinationLocation) {
        const bounds = L.latLngBounds([
          [userLocation.lat, userLocation.lng],
          [destinationLocation.lat, destinationLocation.lng],
        ]);
        map.fitBounds(bounds, { padding: [50, 50], maxZoom: 15 });
      } else if (destinationLocation) {
        map.setView([destinationLocation.lat, destinationLocation.lng], 14);
      }
    }, 150);
    return () => clearTimeout(timer);
  }, [map, userLocation, destinationLocation]);
  return null;
};

const InteractiveDirectionsModal = ({
  isOpen,
  onClose,
  initialProperty,
  allProperties = [],
}) => {
  // Mode selection: 'interactive' (Leaflet + OSRM) or 'gmap' (Google Maps Embed)
  const [mapMode, setMapMode] = useState('gmap');

  // Destination selection (defaults to initialProperty)
  const [selectedPropId, setSelectedPropId] = useState(initialProperty?.id || initialProperty?.uid || '');
  
  // Available resort destinations (filtering valid coords)
  const [destinations, setDestinations] = useState([]);
  
  // User starting point (defaults to user geolocation or Laguna/Manila if pending)
  const [userLocation, setUserLocation] = useState(null);
  const [locating, setLocating] = useState(false);
  const [isLiveTracking, setIsLiveTracking] = useState(false);
  const [locError, setLocError] = useState(null);
  const watchIdRef = useRef(null);

  // Route calculation states
  const [routePolyline, setRoutePolyline] = useState([]);
  const [distanceKm, setDistanceKm] = useState(null);
  const [durationMins, setDurationMins] = useState(null);
  const [loadingRoute, setLoadingRoute] = useState(false);
  const [routeError, setRouteError] = useState(null);

  // Sync available destinations
  useEffect(() => {
    const list = (allProperties && allProperties.length > 0) 
      ? allProperties 
      : (initialProperty ? [initialProperty] : []);

    const valid = list.filter(p => {
      const lat = parseFloat(p.latitude);
      const lng = parseFloat(p.longitude);
      return !isNaN(lat) && !isNaN(lng) && (lat !== 0 || lng !== 0);
    });

    setDestinations(valid);
    if (!selectedPropId && valid.length > 0) {
      setSelectedPropId(valid[0].id || valid[0].uid);
    }
  }, [allProperties, initialProperty, selectedPropId]);

  // Active destination object
  const activeDestination = destinations.find(d => (d.id === selectedPropId || d.uid === selectedPropId)) || destinations[0] || initialProperty;

  // Heading in degrees (0 = North, 90 = East, 180 = South, 270 = West)
  const [userHeading, setUserHeading] = useState(null);
  const lastPosRef = useRef(null);

  // Compass Sensor Listener (DeviceOrientation for Cardinal Direction while stationary or turning)
  useEffect(() => {
    if (!isOpen) return;

    const handleOrientation = (e) => {
      // iOS Safari provides webkitCompassHeading (0 to 360, where 0 is true North)
      if (typeof e.webkitCompassHeading === 'number' && !isNaN(e.webkitCompassHeading)) {
        setUserHeading(Math.round(e.webkitCompassHeading));
      } else if (e.alpha !== null && typeof e.alpha === 'number' && !isNaN(e.alpha)) {
        // Standard Android / Chrome DeviceOrientation (alpha: 0 to 360, counterclockwise or clockwise relative to compass)
        // Convert to clockwise degrees from North
        const heading = (360 - e.alpha) % 360;
        setUserHeading(Math.round(heading));
      }
    };

    // Request orientation permission on iOS 13+ devices if needed
    if (typeof DeviceOrientationEvent !== 'undefined' && typeof DeviceOrientationEvent.requestPermission === 'function') {
      DeviceOrientationEvent.requestPermission()
        .then(permissionState => {
          if (permissionState === 'granted') {
            window.addEventListener('deviceorientation', handleOrientation, true);
          }
        })
        .catch(() => {});
    } else if (typeof window !== 'undefined' && 'ondeviceorientation' in window) {
      window.addEventListener('deviceorientation', handleOrientation, true);
    }

    return () => {
      window.removeEventListener('deviceorientation', handleOrientation, true);
    };
  }, [isOpen]);

  // Helper: calculate bearing from coord A to coord B in degrees
  const calculateBearing = (lat1, lon1, lat2, lon2) => {
    const toRad = deg => (deg * Math.PI) / 180;
    const toDeg = rad => (rad * 180) / Math.PI;
    const dLon = toRad(lon2 - lon1);
    const y = Math.sin(dLon) * Math.cos(toRad(lat2));
    const x = Math.cos(toRad(lat1)) * Math.sin(toRad(lat2)) - Math.sin(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.cos(dLon);
    let brng = toDeg(Math.atan2(y, x));
    return (brng + 360) % 360;
  };

  // Single locate
  const handleLocateMe = () => {
    if (!navigator.geolocation) {
      setLocError('Geolocation is not supported by your browser.');
      return;
    }
    setLocating(true);
    setLocError(null);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const coords = pos.coords;
        setUserLocation({
          lat: coords.latitude,
          lng: coords.longitude,
          name: 'My Current Location'
        });
        if (typeof coords.heading === 'number' && !isNaN(coords.heading) && coords.heading !== 0) {
          setUserHeading(Math.round(coords.heading));
        }
        lastPosRef.current = { lat: coords.latitude, lng: coords.longitude };
        setLocating(false);
      },
      (err) => {
        console.warn('Geolocation error:', err);
        setLocError('Location permission denied. Tap anywhere on the map to set starting pin!');
        if (!userLocation) {
          setUserLocation({
            lat: 14.2790,
            lng: 121.4150,
            name: 'Santa Cruz Town Proper (Tap map to change)'
          });
        }
        setLocating(false);
      },
      { enableHighAccuracy: true, timeout: 8000 }
    );
  };

  // Continuous Live Tracking for Moving Vehicle
  const toggleLiveTracking = () => {
    if (isLiveTracking) {
      if (watchIdRef.current !== null) {
        navigator.geolocation.clearWatch(watchIdRef.current);
        watchIdRef.current = null;
      }
      setIsLiveTracking(false);
    } else {
      if (!navigator.geolocation) {
        setLocError('Geolocation not supported');
        return;
      }
      setIsLiveTracking(true);
      setLocError(null);
      watchIdRef.current = navigator.geolocation.watchPosition(
        (pos) => {
          const coords = pos.coords;
          const newLat = coords.latitude;
          const newLng = coords.longitude;

          // Update heading from GPS bearing or consecutive coordinate delta
          if (typeof coords.heading === 'number' && !isNaN(coords.heading) && coords.heading !== 0) {
            setUserHeading(Math.round(coords.heading));
          } else if (lastPosRef.current) {
            const dist = Math.hypot(newLat - lastPosRef.current.lat, newLng - lastPosRef.current.lng);
            if (dist > 0.0001) { // moved noticeably
              const calculated = calculateBearing(lastPosRef.current.lat, lastPosRef.current.lng, newLat, newLng);
              setUserHeading(Math.round(calculated));
            }
          }

          lastPosRef.current = { lat: newLat, lng: newLng };

          setUserLocation({
            lat: newLat,
            lng: newLng,
            name: '🚗 Moving Vehicle (Live GPS)'
          });
        },
        (err) => {
          console.warn('WatchPosition error:', err);
          setIsLiveTracking(false);
        },
        { enableHighAccuracy: true, maximumAge: 2000, timeout: 10000 }
      );
    }
  };

  // Clean up watchPosition
  useEffect(() => {
    return () => {
      if (watchIdRef.current !== null) {
        navigator.geolocation.clearWatch(watchIdRef.current);
      }
    };
  }, []);

  // Initial locate on open
  useEffect(() => {
    if (isOpen && !userLocation) {
      handleLocateMe();
    }
  }, [isOpen]); // eslint-disable-line react-hooks/exhaustive-deps

  // Fetch OSRM driving route when userLocation or activeDestination changes
  useEffect(() => {
    if (!userLocation || !activeDestination) return;

    const destLat = parseFloat(activeDestination.latitude);
    const destLng = parseFloat(activeDestination.longitude);
    if (isNaN(destLat) || isNaN(destLng)) return;

    setLoadingRoute(true);
    setRouteError(null);

    const osrmUrl = `https://router.project-osrm.org/route/v1/driving/${userLocation.lng},${userLocation.lat};${destLng},${destLat}?overview=full&geometries=geojson`;

    fetch(osrmUrl)
      .then(res => {
        if (!res.ok) throw new Error('Failed to retrieve driving directions');
        return res.json();
      })
      .then(data => {
        if (data.code === 'Ok' && data.routes && data.routes.length > 0) {
          const route = data.routes[0];
          const latLngs = route.geometry.coordinates.map(coord => [coord[1], coord[0]]);
          setRoutePolyline(latLngs);
          setDistanceKm((route.distance / 1000).toFixed(1));
          const mins = Math.round(route.duration / 60);
          setDurationMins(mins);
        } else {
          throw new Error('No driving route found');
        }
      })
      .catch(err => {
        console.warn('Route calculation error:', err);
        setRouteError('Could not calculate road route. Showing straight path.');
        setRoutePolyline([
          [userLocation.lat, userLocation.lng],
          [destLat, destLng]
        ]);
        const R = 6371;
        const dLat = (destLat - userLocation.lat) * Math.PI / 180;
        const dLng = (destLng - userLocation.lng) * Math.PI / 180;
        const a = Math.sin(dLat/2)*Math.sin(dLat/2) +
                  Math.cos(userLocation.lat * Math.PI / 180) * Math.cos(destLat * Math.PI / 180) *
                  Math.sin(dLng/2)*Math.sin(dLng/2);
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
        const d = (R * c).toFixed(1);
        setDistanceKm(d);
        setDurationMins(Math.round((d / 40) * 60));
      })
      .finally(() => {
        setLoadingRoute(false);
      });
  }, [userLocation, activeDestination]);

  if (!isOpen || !activeDestination) return null;

  const destLat = parseFloat(activeDestination.latitude);
  const destLng = parseFloat(activeDestination.longitude);

  const formatDuration = (mins) => {
    if (!mins) return 'Calculating...';
    if (mins < 60) return `${mins} mins`;
    const h = Math.floor(mins / 60);
    const m = mins % 60;
    return `${h} hr ${m > 0 ? `${m} mins` : ''}`;
  };

  return (
    <div
      onClick={onClose}
      style={{
        position: 'fixed',
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        background: 'rgba(0,0,0,0.75)',
        backdropFilter: 'blur(6px)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        zIndex: 5000,
        padding: '16px',
      }}
    >
      <style>{`
        @keyframes navPulse {
          0% { transform: scale(0.8); opacity: 0.8; }
          100% { transform: scale(1.6); opacity: 0; }
        }
      `}</style>
      <div
        onClick={e => e.stopPropagation()}
        style={{
          background: 'var(--surface)',
          borderRadius: '24px',
          maxWidth: '960px',
          width: '100%',
          maxHeight: '92vh',
          display: 'flex',
          flexDirection: 'column',
          boxShadow: '0 30px 80px rgba(0,0,0,0.5)',
          border: '1px solid var(--border)',
          overflow: 'hidden',
          animation: 'fadeInScale 0.25s ease-out',
        }}
      >
        {/* Header with Mode Toggle */}
        <div style={{
          padding: '14px 20px',
          borderBottom: '1px solid var(--border)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          background: 'var(--card-bg)',
          flexWrap: 'wrap',
          gap: '12px',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <div style={{
              width: '40px',
              height: '40px',
              borderRadius: '12px',
              background: 'linear-gradient(135deg, #1DD3B0, #00887A)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: 'white',
              boxShadow: '0 4px 12px rgba(29, 211, 176, 0.3)',
            }}>
              <Compass size={22} />
            </div>
            <div>
              <h3 style={{ margin: 0, fontSize: '17px', fontWeight: 800, color: 'var(--text-main)' }}>
                {activeDestination.name || 'Location & Directions'}
              </h3>
              <p style={{ margin: '2px 0 0', fontSize: '12px', color: 'var(--text-muted)' }}>
                {activeDestination.address || `${destLat.toFixed(4)}, ${destLng.toFixed(4)}`}
              </p>
            </div>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            {/* View Mode Toggle Switch */}
            <div style={{
              display: 'flex',
              background: 'var(--light-bg)',
              borderRadius: '12px',
              padding: '4px',
              border: '1px solid var(--border)',
            }}>
              <button
                onClick={() => setMapMode('gmap')}
                style={{
                  padding: '6px 12px',
                  borderRadius: '8px',
                  border: 'none',
                  background: mapMode === 'gmap' ? 'var(--primary)' : 'transparent',
                  color: mapMode === 'gmap' ? 'white' : 'var(--text-main)',
                  fontWeight: 700,
                  fontSize: '12px',
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '6px',
                  transition: 'all 0.2s',
                }}
              >
                <Layers size={14} /> Google Maps Embed
              </button>
              <button
                onClick={() => setMapMode('interactive')}
                style={{
                  padding: '6px 12px',
                  borderRadius: '8px',
                  border: 'none',
                  background: mapMode === 'interactive' ? 'var(--primary)' : 'transparent',
                  color: mapMode === 'interactive' ? 'white' : 'var(--text-main)',
                  fontWeight: 700,
                  fontSize: '12px',
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '6px',
                  transition: 'all 0.2s',
                }}
              >
                <Route size={14} /> Live GPS Navigator
              </button>
            </div>

            <button
              onClick={onClose}
              style={{
                background: 'var(--surface)',
                border: '1px solid var(--border)',
                color: 'var(--text-main)',
                borderRadius: '50%',
                width: '34px',
                height: '34px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                cursor: 'pointer',
                transition: 'var(--transition)',
              }}
            >
              <X size={18} />
            </button>
          </div>
        </div>

        {/* Destination Resort Switcher Tabs */}
        {destinations.length > 1 && (
          <div style={{
            padding: '10px 20px',
            background: 'var(--light-bg)',
            borderBottom: '1px solid var(--border)',
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            overflowX: 'auto',
          }}>
            <span style={{ fontSize: '11px', fontWeight: 800, color: 'var(--text-muted)', textTransform: 'uppercase', marginRight: '4px', whiteSpace: 'nowrap' }}>
              Switch Resort:
            </span>
            {destinations.map((dest, idx) => {
              const isSelected = (dest.id || dest.uid) === (activeDestination.id || activeDestination.uid);
              return (
                <button
                  key={dest.id || dest.uid || idx}
                  onClick={() => setSelectedPropId(dest.id || dest.uid)}
                  style={{
                    padding: '6px 14px',
                    borderRadius: '20px',
                    border: isSelected ? '2px solid var(--primary)' : '1px solid var(--border)',
                    background: isSelected ? 'var(--primary)' : 'var(--surface)',
                    color: isSelected ? 'white' : 'var(--text-main)',
                    fontSize: '12px',
                    fontWeight: 700,
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'center',
                    gap: '6px',
                    whiteSpace: 'nowrap',
                    transition: 'all 0.2s ease',
                  }}
                >
                  <span style={{
                    width: '18px',
                    height: '18px',
                    borderRadius: '50%',
                    background: isSelected ? 'white' : 'var(--border)',
                    color: isSelected ? 'var(--primary)' : 'var(--text-main)',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    fontSize: '10px',
                    fontWeight: 800,
                  }}>
                    {idx + 1}
                  </span>
                  {dest.name}
                </button>
              );
            })}
          </div>
        )}

        {/* Live Route Stats Banner (Visible in Live GPS mode, or for summary in Google mode) */}
        {mapMode === 'interactive' && (
          <div style={{
            padding: '10px 20px',
            background: 'var(--surface)',
            borderBottom: '1px solid var(--border)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            flexWrap: 'wrap',
            gap: '12px',
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '20px', flexWrap: 'wrap' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <Clock size={16} color="var(--primary)" />
                <div>
                  <div style={{ fontSize: '10px', color: 'var(--text-muted)', fontWeight: 700, textTransform: 'uppercase' }}>Est. Travel Time</div>
                  <div style={{ fontSize: '15px', fontWeight: 800, color: 'var(--text-main)' }}>
                    {loadingRoute ? 'Calculating...' : formatDuration(durationMins)}
                  </div>
                </div>
              </div>

              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <Route size={16} color="var(--secondary)" />
                <div>
                  <div style={{ fontSize: '10px', color: 'var(--text-muted)', fontWeight: 700, textTransform: 'uppercase' }}>Driving Distance</div>
                  <div style={{ fontSize: '15px', fontWeight: 800, color: 'var(--text-main)' }}>
                    {loadingRoute ? '...' : (distanceKm ? `${distanceKm} km` : '—')}
                  </div>
                </div>
              </div>

              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <MapPin size={16} color="#EF4444" />
                <div>
                  <div style={{ fontSize: '10px', color: 'var(--text-muted)', fontWeight: 700, textTransform: 'uppercase' }}>Destination</div>
                  <div style={{ fontSize: '13px', fontWeight: 700, color: 'var(--text-main)' }}>
                    {activeDestination.name}
                  </div>
                </div>
              </div>
            </div>

            <div style={{ display: 'flex', gap: '8px' }}>
              {/* Continuous Vehicle GPS Tracking Button */}
              <button
                onClick={toggleLiveTracking}
                style={{
                  padding: '6px 14px',
                  borderRadius: '10px',
                  background: isLiveTracking ? '#10B981' : 'rgba(16, 185, 129, 0.1)',
                  border: '1px solid #10B981',
                  color: isLiveTracking ? 'white' : '#10B981',
                  fontWeight: 700,
                  fontSize: '12px',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '6px',
                  cursor: 'pointer',
                }}
              >
                <Navigation size={13} className={isLiveTracking ? 'animate-pulse' : ''} />
                {isLiveTracking ? '● Vehicle Moving (Tracking)' : 'Start Vehicle Tracking'}
              </button>

              <button
                onClick={handleLocateMe}
                disabled={locating}
                style={{
                  padding: '6px 14px',
                  borderRadius: '10px',
                  background: 'rgba(59, 130, 246, 0.1)',
                  border: '1px solid #3B82F6',
                  color: '#3B82F6',
                  fontWeight: 700,
                  fontSize: '12px',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '6px',
                  cursor: locating ? 'not-allowed' : 'pointer',
                }}
              >
                {locating ? <RefreshCw size={13} className="animate-spin" /> : <MapPin size={13} />}
                {locating ? 'Locating...' : 'Pin Location'}
              </button>
            </div>
          </div>
        )}

        {/* MODE 1: GOOGLE MAPS EMBED */}
        {mapMode === 'gmap' && (
          <div style={{ position: 'relative', width: '100%', height: '490px', background: 'var(--light-bg)' }}>
            <iframe
              title="Google Maps Location View"
              width="100%"
              height="100%"
              style={{ border: 0 }}
              loading="lazy"
              allowFullScreen
              referrerPolicy="no-referrer-when-downgrade"
              src={`https://maps.google.com/maps?q=${destLat},${destLng}&z=15&output=embed`}
            />
          </div>
        )}

        {/* MODE 2: INTERACTIVE LEAFLET + OSRM LIVE ROUTE & GPS TRACKER */}
        {mapMode === 'interactive' && (
          <div style={{ height: '480px', width: '100%', position: 'relative', background: '#e5e7eb', overflow: 'hidden' }}>
            <MapContainer
              key={`${destLat}-${destLng}`}
              center={[destLat, destLng]}
              zoom={13}
              style={{ height: '480px', width: '100%', zIndex: 1 }}
            >
              <TileLayer
                url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
              />

              <MapClickHandler onMapClick={(latlng) => {
                setUserLocation({
                  lat: latlng.lat,
                  lng: latlng.lng,
                  name: 'Custom Starting Point (Pinned)'
                });
              }} />

              <MapAutoFitter
                userLocation={userLocation}
                destinationLocation={{ lat: destLat, lng: destLng }}
              />

              {userLocation && (
                <Marker
                  position={[userLocation.lat, userLocation.lng]}
                  icon={createUserArrowIcon(userHeading)}
                  draggable={true}
                  eventHandlers={{
                    dragend: (e) => {
                      const marker = e.target;
                      const pos = marker.getLatLng();
                      setUserLocation({
                        lat: pos.lat,
                        lng: pos.lng,
                        name: 'Custom Starting Point (Dragged)'
                      });
                    }
                  }}
                >
                  <Popup>
                    <div style={{ padding: '4px' }}>
                      <strong style={{ color: '#3B82F6' }}>📍 Your Position</strong>
                      <div style={{ fontSize: '12px', color: '#555', marginTop: '2px' }}>
                        {userLocation.name || 'Drag pin or click map to reposition'}
                      </div>
                    </div>
                  </Popup>
                </Marker>
              )}

              {destinations.map((dest, idx) => {
                const dLat = parseFloat(dest.latitude);
                const dLng = parseFloat(dest.longitude);
                if (isNaN(dLat) || isNaN(dLng)) return null;
                const isSelected = (dest.id || dest.uid) === (activeDestination.id || activeDestination.uid);

                return (
                  <Marker
                    key={dest.id || dest.uid || idx}
                    position={[dLat, dLng]}
                    icon={resortIcon(idx + 1, isSelected)}
                    eventHandlers={{
                      click: () => setSelectedPropId(dest.id || dest.uid)
                    }}
                  >
                    <Popup>
                      <div style={{ padding: '6px' }}>
                        <strong style={{ fontSize: '14px' }}>{dest.name}</strong>
                        <div style={{ fontSize: '12px', color: '#666', marginTop: '4px' }}>
                          {dest.address || 'Address not specified'}
                        </div>
                        <button
                          onClick={() => setSelectedPropId(dest.id || dest.uid)}
                          style={{
                            marginTop: '8px',
                            background: isSelected ? 'var(--primary)' : 'var(--secondary)',
                            color: isSelected ? 'white' : '#002D24',
                            border: 'none',
                            padding: '4px 10px',
                            borderRadius: '6px',
                            fontSize: '11px',
                            fontWeight: 800,
                            cursor: 'pointer',
                            display: 'block',
                            width: '100%',
                          }}
                        >
                          {isSelected ? '✓ Current Destination' : 'Select Destination'}
                        </button>
                      </div>
                    </Popup>
                  </Marker>
                );
              })}

              {routePolyline.length > 0 && (
                <Polyline
                  positions={routePolyline}
                  pathOptions={{
                    color: '#3B82F6',
                    weight: 5,
                    opacity: 0.85,
                    lineCap: 'round',
                    lineJoin: 'round',
                  }}
                />
              )}
            </MapContainer>
          </div>
        )}

        {/* Footer */}
        <div style={{
          padding: '12px 20px',
          borderTop: '1px solid var(--border)',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          background: 'var(--card-bg)',
          flexWrap: 'wrap',
          gap: '10px',
        }}>
          <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
            📍 GPS: <strong>{destLat.toFixed(5)}, {destLng.toFixed(5)}</strong>
            {mapMode === 'interactive' && isLiveTracking && (
              <span style={{ marginLeft: '12px', color: '#10B981', fontWeight: 700 }}>
                ● Real-time GPS active
              </span>
            )}
          </div>
          <button
            onClick={onClose}
            className="btn btn-primary"
            style={{ padding: '8px 24px', borderRadius: '10px', fontWeight: 700 }}
          >
            Done
          </button>
        </div>
      </div>
    </div>
  );
};

export default InteractiveDirectionsModal;
