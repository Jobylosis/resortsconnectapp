import React, { useState, useEffect } from 'react';
import { MapContainer, TileLayer, Marker, Popup, Polyline, useMap, useMapEvents } from 'react-leaflet';
import L from 'leaflet';
import { X, Navigation, MapPin, Compass, Clock, Route, Check, AlertCircle, RefreshCw } from 'lucide-react';

// Custom Map Markers
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

const userIcon = createIcon('#3B82F6', '📍', true);
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
  // Destination selection (defaults to initialProperty)
  const [selectedPropId, setSelectedPropId] = useState(initialProperty?.id || initialProperty?.uid || '');
  
  // Available resort destinations (filtering valid coords)
  const [destinations, setDestinations] = useState([]);
  
  // User starting point (defaults to user geolocation or Laguna/Manila if pending)
  const [userLocation, setUserLocation] = useState(null);
  const [locating, setLocating] = useState(false);
  const [locError, setLocError] = useState(null);

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

  // Locate current position
  const handleLocateMe = () => {
    if (!navigator.geolocation) {
      setLocError('Geolocation is not supported by your browser.');
      return;
    }
    setLocating(true);
    setLocError(null);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setUserLocation({
          lat: pos.coords.latitude,
          lng: pos.coords.longitude,
          name: 'My Current Location'
        });
        setLocating(false);
      },
      (err) => {
        console.warn('Geolocation error:', err);
        setLocError('Location permission denied or unavailable. Tap anywhere on the map to place your pin!');
        // Default starting point nearby (Santa Cruz Laguna town center)
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

  // Attempt initial locate on mount
  useEffect(() => {
    if (isOpen && !userLocation) {
      handleLocateMe();
    }
  }, [isOpen]);

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
          // GeoJSON coords are [lng, lat], Leaflet polyline takes [lat, lng]
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
        // Approximate distance via Haversine
        const R = 6371;
        const dLat = (destLat - userLocation.lat) * Math.PI / 180;
        const dLng = (destLng - userLocation.lng) * Math.PI / 180;
        const a = Math.sin(dLat/2)*Math.sin(dLat/2) +
                  Math.cos(userLocation.lat * Math.PI / 180) * Math.cos(destLat * Math.PI / 180) *
                  Math.sin(dLng/2)*Math.sin(dLng/2);
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
        const d = (R * c).toFixed(1);
        setDistanceKm(d);
        setDurationMins(Math.round((d / 40) * 60)); // Assumes 40 km/h avg
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
        {/* Header */}
        <div style={{
          padding: '16px 24px',
          borderBottom: '1px solid var(--border)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          background: 'var(--card-bg)',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <div style={{
              width: '42px',
              height: '42px',
              borderRadius: '12px',
              background: 'linear-gradient(135deg, #1DD3B0, #00887A)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: 'white',
              boxShadow: '0 4px 12px rgba(29, 211, 176, 0.3)',
            }}>
              <Compass size={24} />
            </div>
            <div>
              <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800, color: 'var(--text-main)', display: 'flex', alignItems: 'center', gap: '8px' }}>
                Full Route & Navigation Experience
              </h3>
              <p style={{ margin: '2px 0 0', fontSize: '13px', color: 'var(--text-muted)' }}>
                Live GPS pin, driving routes & estimated travel time
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            style={{
              background: 'var(--surface)',
              border: '1px solid var(--border)',
              color: 'var(--text-main)',
              borderRadius: '50%',
              width: '36px',
              height: '36px',
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
            <span style={{ fontSize: '12px', fontWeight: 800, color: 'var(--text-muted)', textTransform: 'uppercase', marginRight: '4px', whiteSpace: 'nowrap' }}>
              Select Destination:
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
                    fontSize: '13px',
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
                    fontSize: '11px',
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

        {/* Live Route Summary Bar */}
        <div style={{
          padding: '12px 24px',
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
              <Clock size={18} color="var(--primary)" />
              <div>
                <div style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 700, textTransform: 'uppercase' }}>Est. Travel Time</div>
                <div style={{ fontSize: '16px', fontWeight: 800, color: 'var(--text-main)' }}>
                  {loadingRoute ? 'Calculating route...' : formatDuration(durationMins)}
                </div>
              </div>
            </div>

            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <Route size={18} color="var(--secondary)" />
              <div>
                <div style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 700, textTransform: 'uppercase' }}>Driving Distance</div>
                <div style={{ fontSize: '16px', fontWeight: 800, color: 'var(--text-main)' }}>
                  {loadingRoute ? '...' : (distanceKm ? `${distanceKm} km` : '—')}
                </div>
              </div>
            </div>

            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <MapPin size={18} color="#EF4444" />
              <div>
                <div style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 700, textTransform: 'uppercase' }}>Destination</div>
                <div style={{ fontSize: '14px', fontWeight: 700, color: 'var(--text-main)' }}>
                  {activeDestination.name}
                </div>
              </div>
            </div>
          </div>

          <button
            onClick={handleLocateMe}
            disabled={locating}
            style={{
              padding: '8px 16px',
              borderRadius: '12px',
              background: 'rgba(59, 130, 246, 0.1)',
              border: '1px solid #3B82F6',
              color: '#3B82F6',
              fontWeight: 700,
              fontSize: '13px',
              display: 'flex',
              alignItems: 'center',
              gap: '6px',
              cursor: locating ? 'not-allowed' : 'pointer',
            }}
          >
            {locating ? <RefreshCw size={14} className="animate-spin" /> : <Navigation size={14} />}
            {locating ? 'Locating...' : 'Pin My Location'}
          </button>
        </div>

        {/* Tip Banner */}
        <div style={{
          padding: '6px 24px',
          background: 'rgba(29, 211, 176, 0.08)',
          fontSize: '12px',
          color: 'var(--text-muted)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
        }}>
          <span>💡 <strong>Tip:</strong> Tap or click anywhere on the map to manually set or drag your starting point pin!</span>
          {routeError && <span style={{ color: '#EF4444', fontWeight: 600 }}>{routeError}</span>}
        </div>

        {/* Full Interactive Map Container */}
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

            {/* Click to move user pin */}
            <MapClickHandler onMapClick={(latlng) => {
              setUserLocation({
                lat: latlng.lat,
                lng: latlng.lng,
                name: 'Custom Starting Point (Pinned)'
              });
            }} />

            {/* Auto fit bounds when points change */}
            <MapAutoFitter
              userLocation={userLocation}
              destinationLocation={{ lat: destLat, lng: destLng }}
            />

            {/* User Starting Point Pin */}
            {userLocation && (
              <Marker
                position={[userLocation.lat, userLocation.lng]}
                icon={userIcon}
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
                    <strong style={{ color: '#3B82F6' }}>📍 Your Starting Point</strong>
                    <div style={{ fontSize: '12px', color: '#555', marginTop: '2px' }}>
                      {userLocation.name || 'Drag pin or click map to reposition'}
                    </div>
                  </div>
                </Popup>
              </Marker>
            )}

            {/* All Destination Resorts Pins */}
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

            {/* Route Driving Polyline */}
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

        {/* Footer */}
        <div style={{
          padding: '12px 24px',
          borderTop: '1px solid var(--border)',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          background: 'var(--card-bg)',
          flexWrap: 'wrap',
          gap: '10px',
        }}>
          <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
            Destination GPS: <strong>{destLat.toFixed(5)}, {destLng.toFixed(5)}</strong>
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
