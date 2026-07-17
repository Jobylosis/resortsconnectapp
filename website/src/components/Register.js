import React, { useState, useRef, useEffect } from 'react';
import { auth, db } from '../firebase';
import { createUserWithEmailAndPassword, updateProfile, sendEmailVerification, signInWithPopup, GoogleAuthProvider, FacebookAuthProvider } from 'firebase/auth';
import { ref, set, get } from 'firebase/database';
import { Mail, Lock, User, Phone, ArrowLeft, ArrowRight, ShieldCheck, Eye, EyeOff, Info } from 'lucide-react';
import logo from '../assets/ResortConnectLogo.png';
import * as faceapi from 'face-api.js';

const Register = ({ onBackToLogin, onGoHome, isCompletingSocial = false, socialUser = null }) => {
  const [formData, setFormData] = useState({
    firstName: socialUser?.displayName ? socialUser.displayName.split(' ')[0] : '',
    middleName: '',
    lastName: socialUser?.displayName?.split(' ').length > 1 ? socialUser.displayName.split(' ').slice(1).join(' ') : '',
    email: socialUser?.email || '',
    phoneNumber: socialUser?.phoneNumber || '',
    password: '',
    confirmPassword: '',
    idType: '',
    otherIdType: ''
  });
  const [idImageFile, setIdImageFile] = useState(null);
  const [idImageUrl, setIdImageUrl] = useState(null);
  const [isUploading, setIsUploading] = useState(false);
  const [selfieImageFile, setSelfieImageFile] = useState(null);
  const [selfieImageUrl, setSelfieImageUrl] = useState(null);
  const [isUploadingSelfie, setIsUploadingSelfie] = useState(false);
  const [isAutoVerified, setIsAutoVerified] = useState(false);
  const [step, setStep] = useState(1);
  const [errors, setErrors] = useState({});
  const [loading, setLoading] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  const [showWebcam, setShowWebcam] = useState(false);

  // Face Detection States
  const [isModelLoading, setIsModelLoading] = useState(false);
  const [faceDetectionStatus, setFaceDetectionStatus] = useState("Loading AI models...");
  const detectInterval = useRef(null);
  const blinkState = useRef("open");

  const videoRef = useRef(null);
  const canvasRef = useRef(null);

  useEffect(() => {
    return () => stopWebcam(); // Cleanup on unmount
  }, []);

  const loadModels = async () => {
    if (isModelLoading) return;
    setIsModelLoading(true);
    setFaceDetectionStatus("Loading AI models (0%)...");
    try {
      await faceapi.nets.tinyFaceDetector.loadFromUri('/models');
      setFaceDetectionStatus("Loading AI models (50%)...");
      await faceapi.nets.faceLandmark68Net.loadFromUri('/models');
      setFaceDetectionStatus("AI models loaded!");
    } catch (err) {
      console.error("Error loading face-api models:", err);
      setFaceDetectionStatus("Error loading face tracking models.");
    } finally {
      setIsModelLoading(false);
    }
  };

  const getEAR = (eye) => {
    const d1 = Math.hypot(eye[1].x - eye[5].x, eye[1].y - eye[5].y);
    const d2 = Math.hypot(eye[2].x - eye[4].x, eye[2].y - eye[4].y);
    const d3 = Math.hypot(eye[0].x - eye[3].x, eye[0].y - eye[3].y);
    return (d1 + d2) / (2.0 * d3);
  };

  const startFaceTracking = () => {
    if (detectInterval.current) clearInterval(detectInterval.current);
    blinkState.current = "open";

    detectInterval.current = setInterval(async () => {
      if (!videoRef.current) return;
      const detections = await faceapi.detectSingleFace(videoRef.current, new faceapi.TinyFaceDetectorOptions()).withFaceLandmarks();

      if (detections) {
        const landmarks = detections.landmarks;
        const leftEye = landmarks.getLeftEye();
        const rightEye = landmarks.getRightEye();

        const leftEAR = getEAR(leftEye);
        const rightEAR = getEAR(rightEye);
        const avgEAR = (leftEAR + rightEAR) / 2.0;

        if (avgEAR < 0.25) {
          if (blinkState.current === "open") {
            blinkState.current = "closed";
          }
        } else {
          if (blinkState.current === "closed") {
            blinkState.current = "open";
            setFaceDetectionStatus("Blink detected! Capturing...");
            clearInterval(detectInterval.current);
            setTimeout(() => {
              captureWebcam();
            }, 300); // Small delay to let eyes open fully
          }
        }

        if (blinkState.current === "open" && avgEAR >= 0.25) {
          setFaceDetectionStatus("Face detected! Please blink slowly.");
        }
      } else {
        setFaceDetectionStatus("No face detected. Please center your face.");
      }
    }, 100);
  };

  const startWebcam = async () => {
    setShowWebcam(true);
    await loadModels();
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: true });
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        videoRef.current.onloadedmetadata = () => {
          setFaceDetectionStatus("Initializing face tracking...");
          startFaceTracking();
        };
      }
    } catch (err) {
      console.error("Error accessing webcam:", err);
      alert("Could not access webcam. Please ensure you have granted permission.");
      setShowWebcam(false);
    }
  };

  const stopWebcam = () => {
    if (detectInterval.current) clearInterval(detectInterval.current);
    if (videoRef.current && videoRef.current.srcObject) {
      const stream = videoRef.current.srcObject;
      const tracks = stream.getTracks();
      tracks.forEach(track => track.stop());
    }
    setShowWebcam(false);
  };


  const captureWebcam = () => {
    if (videoRef.current && canvasRef.current) {
      const context = canvasRef.current.getContext('2d');
      canvasRef.current.width = videoRef.current.videoWidth;
      canvasRef.current.height = videoRef.current.videoHeight;
      context.drawImage(videoRef.current, 0, 0, canvasRef.current.width, canvasRef.current.height);

      canvasRef.current.toBlob((blob) => {
        const file = new File([blob], "selfie.jpg", { type: "image/jpeg" });
        setSelfieImageFile(file);
        setIsAutoVerified(true);
        uploadSelfieImage(file);
        stopWebcam();
      }, 'image/jpeg');
    }
  };

  const idTypes = [
    'Philippine National ID (PhilSys)',
    'Passport',
    "Driver's License",
    "Voter's ID",
    'SSS / GSIS ID',
    'PRC ID',
    'Senior Citizen ID',
    'Postal ID',
    'Other'
  ];

  const validate = () => {
    const { firstName, lastName, email, phoneNumber, password, confirmPassword } = formData;
    const newErrors = {};

    if (!firstName || !firstName.trim()) newErrors.firstName = 'First Name is required';
    if (!lastName || !lastName.trim()) newErrors.lastName = 'Last Name is required';
    if (!email || !email.trim()) newErrors.email = 'Email is required';
    if (!phoneNumber || !phoneNumber.trim()) newErrors.phoneNumber = 'Phone Number is required';
    if (!isCompletingSocial && (!password || !password.trim())) newErrors.password = 'Password is required';
    if (!isCompletingSocial && (!confirmPassword || !confirmPassword.trim())) newErrors.confirmPassword = 'Confirm Password is required';

    const nameRegex = /^[a-zA-Z\s]+$/;
    if (firstName) {
      const fname = firstName.trim();
      if (!nameRegex.test(fname)) newErrors.firstName = 'No special characters allowed.';
      if (fname.length < 2) newErrors.firstName = 'Minimum length is 2 characters.';
      if (fname.split(' ').length > 4) newErrors.firstName = 'Maximum of 4 words allowed.';
    }
    if (formData.middleName) {
      const mname = formData.middleName.trim();
      if (!nameRegex.test(mname)) newErrors.middleName = 'No special characters allowed.';
      if (mname.split(' ').length > 4) newErrors.middleName = 'Maximum of 4 words allowed.';
    }
    if (lastName) {
      const lname = lastName.trim();
      if (!nameRegex.test(lname)) newErrors.lastName = 'No special characters allowed.';
      if (lname.length < 2) newErrors.lastName = 'Minimum length is 2 characters.';
      if (lname.split(' ').length > 4) newErrors.lastName = 'Maximum of 4 words allowed.';
    }

    const emailRegex = /^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$/;
    if (email && !emailRegex.test(email)) newErrors.email = 'Enter a valid email address';

    if (phoneNumber && (phoneNumber.length !== 11 || !phoneNumber.startsWith('09'))) {
      newErrors.phoneNumber = 'Phone number must be 11 digits and start with 09';
    }

    if (!isCompletingSocial && password) {
      if (password.length < 8) {
        newErrors.password = 'Password must be at least 8 characters';
      } else if (!/[A-Z]/.test(password)) {
        newErrors.password = 'Add at least one uppercase letter';
      } else if (!/[a-z]/.test(password)) {
        newErrors.password = 'Add at least one lowercase letter';
      } else if (!/[0-9]/.test(password)) {
        newErrors.password = 'Add at least one number';
      } else if (!/[!@#$%^&*(),.?":{}|<>]/.test(password)) {
        newErrors.password = 'Add at least one special character';
      }
    }

    if (!isCompletingSocial && confirmPassword && password !== confirmPassword) {
      newErrors.confirmPassword = 'Passwords do not match';
    }

    if (step === 2) {
      if (!formData.idType) newErrors.idType = 'Please select an ID type';
      if (formData.idType === 'Other' && (!formData.otherIdType || !formData.otherIdType.trim())) {
        newErrors.otherIdType = 'Please specify your ID type';
      }
      if (!idImageUrl) newErrors.idImage = 'Please upload a valid ID photo';
      if (!selfieImageUrl) newErrors.selfieImage = 'Please upload a selfie photo';
    }

    return Object.keys(newErrors).length > 0 ? newErrors : null;
  };

  const generateCustomId = () => {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let id = '';
    for (let i = 0; i < 6; i++) {
      id += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return `RC-${id}`;
  };

  const handleEmojiFilter = (value) => {
    // Regex for various emoji ranges
    const emojiRegex = /[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]/gu;
    return value.replace(emojiRegex, '');
  };

  const uploadIdImage = async (file) => {
    if (!file) return;
    setIsUploading(true);
    setErrors({ ...errors, idImage: null });
    
    // Check OCR match first
    try {
      const ocrFd = new FormData();
      ocrFd.append('image', file);
      ocrFd.append('firstName', firstName);
      ocrFd.append('lastName', lastName);
      
      const ocrRes = await fetch('http://127.0.0.1:8000/verify_id', {
        method: 'POST',
        body: ocrFd
      });
      
      const ocrData = await ocrRes.json();
      if (ocrData.success && ocrData.match === false) {
        setErrors({ ...errors, idImage: 'Credentials mismatch: The name on the ID does not match your registered name.' });
        setIsUploading(false);
        return; // reject upload
      }
    } catch (e) {
      console.warn("OCR check failed, proceeding to upload anyway.", e);
    }
    
    const cloudName = 'dnv6ezitm';
    const uploadPreset = 'resort_unsigned';

    const url = `https://api.cloudinary.com/v1_1/${cloudName}/image/upload`;
    const fd = new FormData();
    fd.append('upload_preset', uploadPreset);
    fd.append('file', file);

    try {
      const response = await fetch(url, {
        method: 'POST',
        body: fd
      });
      const data = await response.json();
      if (response.ok) {
        setIdImageUrl(data.secure_url);
      } else {
        throw new Error(data.error?.message || 'Upload failed');
      }
    } catch (e) {
      setErrors({ ...errors, idImage: 'Failed to upload image. Please try again.' });
    } finally {
      setIsUploading(false);
    }
  };

  const uploadSelfieImage = async (file) => {
    if (!file) return;
    setIsUploadingSelfie(true);
    setErrors({ ...errors, selfieImage: null });
    const cloudName = 'dnv6ezitm';
    const uploadPreset = 'resort_unsigned';

    const url = `https://api.cloudinary.com/v1_1/${cloudName}/image/upload`;
    const fd = new FormData();
    fd.append('upload_preset', uploadPreset);
    fd.append('file', file);

    try {
      const response = await fetch(url, {
        method: 'POST',
        body: fd
      });
      const data = await response.json();
      if (response.ok) {
        setSelfieImageUrl(data.secure_url);
      } else {
        throw new Error(data.error?.message || 'Upload failed');
      }
    } catch (e) {
      setErrors({ ...errors, selfieImage: 'Failed to upload image. Please try again.' });
    } finally {
      setIsUploadingSelfie(false);
    }
  };

  const handleNextStep = () => {
    const validationErrors = validate();
    if (validationErrors && Object.keys(validationErrors).filter(k => k !== 'idType' && k !== 'otherIdType' && k !== 'idImage' && k !== 'selfieImage').length > 0) {
      setErrors(validationErrors);
      return;
    }
    setErrors({});
    setStep(2);
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    const validationErrors = validate();
    if (validationErrors) {
      setErrors(validationErrors);
      return;
    }

    setErrors({});
    setLoading(true);
    try {
      let user = socialUser;
      if (!isCompletingSocial) {
        const userCredential = await createUserWithEmailAndPassword(auth, formData.email, formData.password);
        user = userCredential.user;

        await sendEmailVerification(user);

        await updateProfile(user, {
          displayName: `${formData.firstName} ${formData.lastName}`
        });
      }

      const customId = generateCustomId();

      const userRef = ref(db, `users/${user.uid}`);
      let existingData = {};
      if (isCompletingSocial) {
        const snap = await get(userRef);
        if (snap.exists()) {
          existingData = snap.val();
        }
      }

      await set(userRef, {
        ...existingData,
        firstName: formData.firstName,
        middleName: formData.middleName,
        lastName: formData.lastName,
        email: formData.email,
        phoneNumber: formData.phoneNumber,
        role: existingData.role || 'Tourist',
        uid: user.uid,
        customId: existingData.customId || customId,
        isBanned: existingData.isBanned || false,
        createdAt: existingData.createdAt || Date.now(),
        idType: formData.idType === 'Other' ? formData.otherIdType.trim() : formData.idType,
        idImageUrl: idImageUrl,
        selfieUrl: selfieImageUrl,
        idVerified: isAutoVerified,
        identityStatus: isAutoVerified ? 'approved' : 'pending'
      });

      alert('Registration Successful! Please check your email to verify your account.');
      onBackToLogin();
    } catch (err) {
      setErrors({ global: err.message });
    } finally {
      setLoading(false);
    }
  };

  const handleSocialRegister = async (providerName) => {
    setErrors({});
    setLoading(true);
    let provider;
    if (providerName === 'google') {
      provider = new GoogleAuthProvider();
    } else if (providerName === 'facebook') {
      provider = new FacebookAuthProvider();
    }

    try {
      const result = await signInWithPopup(auth, provider);
      const user = result.user;

      const userRef = ref(db, `users/${user.uid}`);
      const snapshot = await get(userRef);

      if (!snapshot.exists()) {
        // App.js will detect missing profile and route to complete registration
      }
    } catch (err) {
      setErrors({ global: err.message || 'An error occurred during social registration.' });
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{
      display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '100vh', width: '100%',
      backgroundImage: 'linear-gradient(rgba(0,15,8,0.7), rgba(0,15,8,0.7)), url("https://images.unsplash.com/photo-1540541338287-41700207dee6?ixlib=rb-4.0.3&auto=format&fit=crop&w=1470&q=80")',
      backgroundSize: 'cover', backgroundPosition: 'center', backgroundAttachment: 'fixed', padding: '40px 20px',
    }}>
      <div className="card view-transition" style={{
        width: '100%', maxWidth: '520px', padding: '48px 40px',
        backgroundColor: 'var(--surface)',
        borderRadius: '32px', boxShadow: '0 30px 60px -12px rgba(0,0,0,0.5)',
        border: '1px solid var(--border)', position: 'relative', overflow: 'hidden'
      }}>
        {/* Accent Bar */}
        <div style={{
          position: 'absolute', top: 0, left: 0, right: 0, height: '6px',
          background: 'linear-gradient(to right, var(--secondary), var(--primary))'
        }}></div>

        <button
          onClick={onBackToLogin}
          style={{
            background: 'none', border: 'none', cursor: 'pointer', display: 'flex',
            alignItems: 'center', gap: '8px', color: 'var(--text-muted)',
            marginBottom: '32px', fontWeight: 700, fontSize: '14px'
          }}
        >
          <ArrowLeft size={18} /> Back to Login
        </button>

        <div style={{ textAlign: 'center', marginBottom: '40px' }}>
          <div onClick={onGoHome} style={{ cursor: 'pointer', display: 'inline-block' }}>
            <img src={logo} alt="Resort Connect Logo" style={{ width: '280px', height: 'auto', marginBottom: '16px' }} />
          </div>
          <h2 style={{ margin: 0, fontSize: '26px', fontWeight: 800, color: 'var(--text-main)' }}>
            {step === 1 ? 'Join Resort Connect' : 'Identity Verification'}
          </h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '14px', marginTop: '4px', fontWeight: 500 }}>
            {step === 1 ? 'Start your premium stay experience' : 'Step 2: Upload a valid government ID'}
          </p>
        </div>

        <form onSubmit={handleSubmit}>
          {step === 1 ? (
            <>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px', marginBottom: '20px' }}>
                <div className="form-group">
                  <label className="input-label">First Name</label>
                  <div style={{ position: 'relative' }}>
                    <User style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
                    <input
                      className="input" style={{ paddingLeft: '48px', borderColor: errors.firstName ? '#ef4444' : undefined }} placeholder="Jane"
                      value={formData.firstName} onChange={(e) => { setFormData({ ...formData, firstName: handleEmojiFilter(e.target.value) }); setErrors({ ...errors, firstName: null }); }}
                      maxLength="30"
                    />
                  </div>
                  {errors.firstName && <div style={{ color: '#ef4444', fontSize: '12px', marginTop: '6px', fontWeight: 600 }}>⬆ {errors.firstName}</div>}
                </div>
                <div className="form-group">
                  <label className="input-label">Middle Name</label>
                  <div style={{ position: 'relative' }}>
                    <User style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} size={18} />
                    <input
                      className="input" style={{ paddingLeft: '48px', borderColor: errors.middleName ? '#ef4444' : undefined }} placeholder="Optional"
                      value={formData.middleName} onChange={(e) => { setFormData({ ...formData, middleName: handleEmojiFilter(e.target.value) }); setErrors({ ...errors, middleName: null }); }}
                      maxLength="30"
                    />
                  </div>
                  {errors.middleName && <div style={{ color: '#ef4444', fontSize: '12px', marginTop: '6px', fontWeight: 600 }}>⬆ {errors.middleName}</div>}
                </div>
              </div>

              <div style={{ marginBottom: '20px' }}>
                <label className="input-label">Last Name</label>
                <div style={{ position: 'relative' }}>
                  <User style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
                  <input
                    className="input" style={{ paddingLeft: '48px', borderColor: errors.lastName ? '#ef4444' : undefined }} placeholder="Doe"
                    value={formData.lastName} onChange={(e) => { setFormData({ ...formData, lastName: handleEmojiFilter(e.target.value) }); setErrors({ ...errors, lastName: null }); }}
                    maxLength="30"
                  />
                </div>
                {errors.lastName && <div style={{ color: '#ef4444', fontSize: '12px', marginTop: '6px', fontWeight: 600 }}>⬆ {errors.lastName}</div>}
              </div>

              <div style={{ marginBottom: '20px' }}>
                <label className="input-label">Email Address</label>
                <div style={{ position: 'relative' }}>
                  <Mail style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
                  <input
                    type="email" className="input" style={{ paddingLeft: '48px', borderColor: errors.email ? '#ef4444' : undefined }} placeholder="jane@example.com"
                    value={formData.email} onChange={(e) => { setFormData({ ...formData, email: e.target.value }); setErrors({ ...errors, email: null }); }}
                  />
                </div>
                {errors.email && <div style={{ color: '#ef4444', fontSize: '12px', marginTop: '6px', fontWeight: 600 }}>⬆ {errors.email}</div>}
              </div>

              <div style={{ marginBottom: '20px' }}>
                <label className="input-label">Phone Number</label>
                <div style={{ position: 'relative' }}>
                  <Phone style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
                  <input
                    type="tel" className="input" style={{ paddingLeft: '48px', borderColor: errors.phoneNumber ? '#ef4444' : undefined }} placeholder="09XX XXX XXXX" maxLength="11"
                    value={formData.phoneNumber} onChange={(e) => { setFormData({ ...formData, phoneNumber: e.target.value.replace(/\D/g, '') }); setErrors({ ...errors, phoneNumber: null }); }}
                  />
                </div>
                {errors.phoneNumber && <div style={{ color: '#ef4444', fontSize: '12px', marginTop: '6px', fontWeight: 600 }}>⬆ {errors.phoneNumber}</div>}
              </div>

              {!isCompletingSocial && (
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px', marginBottom: '32px' }}>
                  <div className="form-group">
                    <label className="input-label">Password</label>
                    <div style={{ position: 'relative' }}>
                      <Lock style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
                      <input
                        type={showPassword ? 'text' : 'password'} className="input" style={{ paddingLeft: '48px', paddingRight: '48px', borderColor: errors.password ? '#ef4444' : undefined }} placeholder="••••••••"
                        value={formData.password} onChange={(e) => { setFormData({ ...formData, password: e.target.value }); setErrors({ ...errors, password: null }); }}
                      />
                      <button type="button" onClick={() => setShowPassword(p => !p)} tabIndex={-1}
                        style={{ position: 'absolute', right: '14px', top: '50%', transform: 'translateY(-50%)', background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)', display: 'flex', alignItems: 'center', padding: '4px' }}>
                        {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                      </button>
                    </div>
                    {errors.password && <div style={{ color: '#ef4444', fontSize: '12px', marginTop: '6px', fontWeight: 600 }}>⬆ {errors.password}</div>}
                  </div>
                  <div className="form-group">
                    <label className="input-label">Confirm</label>
                    <div style={{ position: 'relative' }}>
                      <Lock style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--secondary)' }} size={18} />
                      <input
                        type={showConfirmPassword ? 'text' : 'password'} className="input" style={{ paddingLeft: '48px', paddingRight: '48px', borderColor: errors.confirmPassword ? '#ef4444' : undefined }} placeholder="••••••••"
                        value={formData.confirmPassword} onChange={(e) => { setFormData({ ...formData, confirmPassword: e.target.value }); setErrors({ ...errors, confirmPassword: null }); }}
                      />
                      <button type="button" onClick={() => setShowConfirmPassword(p => !p)} tabIndex={-1}
                        style={{ position: 'absolute', right: '14px', top: '50%', transform: 'translateY(-50%)', background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)', display: 'flex', alignItems: 'center', padding: '4px' }}>
                        {showConfirmPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                      </button>
                    </div>
                    {errors.confirmPassword && <div style={{ color: '#ef4444', fontSize: '12px', marginTop: '6px', fontWeight: 600 }}>⬆ {errors.confirmPassword}</div>}
                  </div>
                </div>
              )}

              <button
                type="button"
                className="btn btn-primary"
                style={{ width: '100%', height: '56px', fontSize: '16px', marginBottom: '16px' }}
                onClick={handleNextStep}
              >
                CONTINUE <ArrowRight size={18} />
              </button>

              {!isCompletingSocial && (
                <>
                  <div style={{ display: 'flex', alignItems: 'center', margin: '24px 0' }}>
                    <div style={{ flex: 1, height: '1px', background: 'var(--border)' }}></div>
                    <span style={{ padding: '0 16px', color: 'var(--text-muted)', fontSize: '12px', fontWeight: 600 }}>OR REGISTER WITH</span>
                    <div style={{ flex: 1, height: '1px', background: 'var(--border)' }}></div>
                  </div>

                  <div style={{ display: 'flex', gap: '16px', marginBottom: '20px' }}>
                    <button
                      type="button"
                      onClick={() => handleSocialRegister('google')}
                      style={{
                        flex: 1, height: '48px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '10px',
                        background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: '12px',
                        color: 'var(--text-main)', fontSize: '14px', fontWeight: 600, cursor: 'pointer', transition: 'var(--transition)'
                      }}
                      onMouseOver={e => e.currentTarget.style.background = 'var(--light-bg)'}
                      onMouseOut={e => e.currentTarget.style.background = 'var(--surface)'}
                    >
                      <img src="https://www.svgrepo.com/show/475656/google-color.svg" alt="Google" style={{ width: '20px', height: '20px' }} />
                      Google
                    </button>
                    <button
                      type="button"
                      onClick={() => handleSocialRegister('facebook')}
                      style={{
                        flex: 1, height: '48px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '10px',
                        background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: '12px',
                        color: 'var(--text-main)', fontSize: '14px', fontWeight: 600, cursor: 'pointer', transition: 'var(--transition)'
                      }}
                      onMouseOver={e => e.currentTarget.style.background = 'var(--light-bg)'}
                      onMouseOut={e => e.currentTarget.style.background = 'var(--surface)'}
                    >
                      <img src="https://www.svgrepo.com/show/475647/facebook-color.svg" alt="Facebook" style={{ width: '20px', height: '20px' }} />
                      Facebook
                    </button>
                  </div>
                </>
              )}
            </>
          ) : (
            <>
              <div style={{ marginBottom: '20px' }}>
                <label className="input-label">ID Type</label>
                <select
                  className="input"
                  style={{ width: '100%', padding: '14px', borderColor: errors.idType ? '#ef4444' : undefined }}
                  value={formData.idType}
                  onChange={(e) => { setFormData({ ...formData, idType: e.target.value }); setErrors({ ...errors, idType: null }); }}
                >
                  <option value="">Select your ID type</option>
                  {idTypes.map(type => <option key={type} value={type}>{type}</option>)}
                </select>
                {errors.idType && <div style={{ color: '#ef4444', fontSize: '12px', marginTop: '6px', fontWeight: 600 }}>⬆ {errors.idType}</div>}

                {formData.idType === 'Other' && (
                  <div style={{ marginTop: '16px' }}>
                    <label className="input-label">Specify ID</label>
                    <input
                      type="text"
                      className="input"
                      placeholder="Enter ID type"
                      maxLength={30}
                      style={{ borderColor: errors.otherIdType ? '#ef4444' : undefined }}
                      value={formData.otherIdType}
                      onChange={(e) => { setFormData({ ...formData, otherIdType: e.target.value }); setErrors({ ...errors, otherIdType: null }); }}
                    />
                    {errors.otherIdType && <div style={{ color: '#ef4444', fontSize: '12px', marginTop: '6px', fontWeight: 600 }}>⬆ {errors.otherIdType}</div>}
                  </div>
                )}
              </div>

              <div style={{ marginBottom: '32px' }}>
                <label className="input-label">Upload ID Photo</label>
                <div style={{
                  border: `2px dashed ${idImageUrl ? '#10B981' : 'var(--border)'}`,
                  borderRadius: '16px',
                  padding: '32px 20px',
                  textAlign: 'center',
                  background: 'var(--light-bg)',
                  cursor: 'pointer',
                  position: 'relative'
                }}>
                  {idImageUrl ? (
                    <div>
                      <img src={idImageUrl} alt="ID Preview" style={{ maxWidth: '100%', maxHeight: '160px', objectFit: 'contain', borderRadius: '8px', marginBottom: '12px' }} />
                      <p style={{ color: '#10B981', fontWeight: 700, margin: 0 }}>ID Uploaded Successfully</p>
                      <button
                        type="button"
                        onClick={() => setIdImageUrl(null)}
                        style={{ background: 'none', border: 'none', color: '#EF4444', fontSize: '13px', fontWeight: 700, marginTop: '8px', cursor: 'pointer' }}
                      >
                        Remove & Replace
                      </button>
                    </div>
                  ) : (
                    <div>
                      {isUploading ? (
                        <div className="loader" style={{ margin: '0 auto' }}></div>
                      ) : (
                        <>
                          <User size={48} color="var(--text-muted)" style={{ margin: '0 auto 12px', opacity: 0.5 }} />
                          <p style={{ color: 'var(--text-main)', fontWeight: 600, margin: '0 0 8px 0' }}>Click to upload front of ID</p>
                          <p style={{ color: 'var(--text-muted)', fontSize: '12px', margin: 0 }}>JPEG, PNG up to 5MB</p>
                        </>
                      )}
                    </div>
                  )}
                  {!idImageUrl && !isUploading && (
                    <input
                      type="file"
                      accept="image/*"
                      style={{ position: 'absolute', top: 0, left: 0, width: '100%', height: '100%', opacity: 0, cursor: 'pointer' }}
                      onChange={(e) => {
                        const file = e.target.files[0];
                        if (file) {
                          setIdImageFile(file);
                          uploadIdImage(file);
                        }
                      }}
                    />
                  )}
                </div>
                {errors.idImage && <div style={{ color: '#ef4444', fontSize: '12px', marginTop: '6px', fontWeight: 600 }}>⬆ {errors.idImage}</div>}
              </div>

              <div style={{ marginBottom: '32px' }}>
                <label className="input-label">Scan Face / Selfie</label>
                <div style={{
                  border: `2px dashed ${selfieImageUrl ? '#10B981' : 'var(--border)'}`,
                  borderRadius: '16px',
                  padding: '32px 20px',
                  textAlign: 'center',
                  background: 'var(--light-bg)',
                  cursor: 'pointer',
                  position: 'relative'
                }}>
                  {selfieImageUrl ? (
                    <div>
                      <img src={selfieImageUrl} alt="Selfie Preview" style={{ maxWidth: '100%', maxHeight: '160px', objectFit: 'contain', borderRadius: '8px', marginBottom: '12px' }} />
                      <p style={{ color: '#10B981', fontWeight: 700, margin: 0 }}>Selfie Uploaded Successfully</p>
                      {isAutoVerified && <p style={{ color: '#3B82F6', fontWeight: 700, fontSize: '12px', marginTop: '4px' }}>AI LIVENESS VERIFIED</p>}
                      <button
                        type="button"
                        onClick={() => setSelfieImageUrl(null)}
                        style={{ background: 'none', border: 'none', color: '#EF4444', fontSize: '13px', fontWeight: 700, marginTop: '8px', cursor: 'pointer' }}
                      >
                        Remove & Replace
                      </button>
                    </div>
                  ) : showWebcam ? (
                    <div style={{ position: 'relative', zIndex: 10 }}>
                      <div style={{ position: 'relative', overflow: 'hidden', borderRadius: '50%', width: '200px', height: '200px', margin: '0 auto', background: '#000', border: '4px solid #10B981' }}>
                        <video ref={videoRef} autoPlay playsInline muted style={{ width: '100%', height: '100%', objectFit: 'cover', transform: 'scaleX(-1)' }} />
                        <div style={{ position: 'absolute', bottom: '20px', left: '0', right: '0', textAlign: 'center' }}>
                          <span style={{ background: 'rgba(0,0,0,0.6)', color: 'white', padding: '4px 12px', borderRadius: '20px', fontSize: '11px', fontWeight: 700 }}>
                            {faceDetectionStatus}
                          </span>
                        </div>
                      </div>
                      <canvas ref={canvasRef} style={{ display: 'none' }} />
                      <div style={{ display: 'flex', gap: '8px', marginTop: '16px', justifyContent: 'center' }}>
                        {isModelLoading && <div className="loader" style={{ width: '20px', height: '20px' }}></div>}
                        <button type="button" onClick={stopWebcam} style={{ padding: '8px 24px', background: '#EF4444', color: 'white', border: 'none', borderRadius: '8px', cursor: 'pointer', fontWeight: 600, fontSize: '13px' }}>Cancel Camera</button>
                      </div>
                    </div>
                  ) : (
                    <div style={{ position: 'relative' }}>
                      {isUploadingSelfie ? (
                        <div className="loader" style={{ margin: '0 auto' }}></div>
                      ) : (
                        <>
                          <User size={48} color="var(--text-muted)" style={{ margin: '0 auto 12px', opacity: 0.5 }} />
                          <p style={{ color: 'var(--text-main)', fontWeight: 600, margin: '0 0 8px 0' }}>Scan your face for auto-verification</p>
                          <div style={{ display: 'flex', gap: '12px', justifyContent: 'center', marginTop: '12px', position: 'relative', zIndex: 10 }}>
                            <button type="button" onClick={startWebcam} style={{ padding: '8px 16px', background: 'var(--primary)', color: 'white', border: 'none', borderRadius: '8px', cursor: 'pointer', fontWeight: 600, fontSize: '12px' }}>Open Camera for Verification</button>
                          </div>
                        </>
                      )}
                    </div>
                  )}
                </div>
                {errors.selfieImage && <div style={{ color: '#ef4444', fontSize: '12px', marginTop: '6px', fontWeight: 600 }}>⬆ {errors.selfieImage}</div>}
              </div>

              <div style={{ display: 'flex', gap: '12px', marginBottom: '20px' }}>
                <button
                  type="button"
                  className="btn btn-secondary"
                  style={{ flex: 1, height: '56px', fontSize: '16px' }}
                  onClick={() => setStep(1)}
                  disabled={loading || isUploading || isUploadingSelfie}
                >
                  BACK
                </button>
                <button
                  type="submit"
                  className="btn btn-primary"
                  style={{ flex: 1, height: '56px', fontSize: '16px' }}
                  disabled={loading || isUploading || isUploadingSelfie}
                >
                  {loading ? <div className="loader" style={{ width: '20px', height: '20px', borderTopColor: 'white' }}></div> : 'CREATE ACCOUNT'}
                </button>
              </div>
            </>
          )}

          {errors.global && (
            <div style={{
              backgroundColor: '#EF4444', color: 'white', padding: '16px',
              borderRadius: '12px', fontSize: '14px', marginBottom: '24px',
              textAlign: 'center', fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px'
            }}>
              <ShieldCheck size={20} /> {errors.global}
            </div>
          )}
          <p style={{ textAlign: 'center', marginTop: '32px', fontSize: '13px', color: 'var(--text-muted)', fontWeight: 500 }}>
            By registering, you agree to our <strong>Terms</strong> and <strong>Privacy Policy</strong>.
          </p>
        </form>
      </div>
      <style>{`
        .input-label { display: block; font-size: 12px; font-weight: 800; color: var(--text-main); margin-bottom: 8px; text-transform: uppercase; letter-spacing: 0.5px; }
        .view-transition { animation: fadeIn 0.4s ease-out; }
      `}</style>
    </div>
  );
};

export default Register;
