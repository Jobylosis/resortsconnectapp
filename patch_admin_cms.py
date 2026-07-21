import re
import sys

def patch_admin_cms_js():
    file_path = "website/src/components/AdminCMS.js"
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    # 1. Add heroImageUrls state
    content = content.replace(
        "heroImageUrl: '',",
        "heroImageUrls: [],"
    )

    # 2. Update initial data fetch
    content = content.replace(
        "contact: { ...prev.contact, ...(data.contact || {}) },",
        "contact: { ...prev.contact, ...(data.contact || {}) },\n          heroImageUrls: data.heroImageUrls || (data.heroImageUrl ? [data.heroImageUrl] : []),"
    )

    # 3. Update handleUpload for heroImageUrls
    content = content.replace(
        """      if (fieldPath.startsWith('promo_')) {
        const promoId = fieldPath.split('_')[1];
        handlePromoChange(promoId, 'imageUrl', data.secure_url);
      } else {
        handleChange(fieldPath, data.secure_url);
      }""",
        """      if (fieldPath.startsWith('promo_')) {
        const promoId = fieldPath.split('_')[1];
        handlePromoChange(promoId, 'imageUrl', data.secure_url);
      } else if (fieldPath === 'heroImageUrls') {
        setCmsData(prev => ({ ...prev, heroImageUrls: [...(prev.heroImageUrls || []), data.secure_url] }));
      } else {
        handleChange(fieldPath, data.secure_url);
      }"""
    )
    
    # Add remove image function
    content = content.replace(
        "const handleChange = (field, value) => {",
        """const removeHeroImage = (indexToRemove) => {
    setCmsData(prev => ({
      ...prev,
      heroImageUrls: prev.heroImageUrls.filter((_, idx) => idx !== indexToRemove)
    }));
  };

  const handleChange = (field, value) => {"""
    )

    # 4. Add validation in handleSave
    validation_logic = """
    if (!cmsData.heroTitle?.trim() || !cmsData.heroSubtitle?.trim()) {
      showToast('Hero Title and Subtitle are required', true);
      return;
    }
    if (!cmsData.heroImageUrls || cmsData.heroImageUrls.length === 0) {
      showToast('At least one Hero Background Image is required', true);
      return;
    }
    if (!cmsData.aboutTitle?.trim() || !cmsData.aboutText?.trim()) {
      showToast('About Title and Text are required', true);
      return;
    }
    
    for (const [id, promo] of Object.entries(cmsData.promotions)) {
      if (!promo.title?.trim() || !promo.description?.trim()) {
        showToast('All promotions must have a title and description', true);
        return;
      }
      if (!promo.startDate || !promo.endDate) {
        showToast(`Please specify start and end dates for promotion "${promo.title || 'Untitled'}"`, true);
        return;
      }
      if (new Date(promo.startDate) > new Date(promo.endDate)) {
        showToast(`Start date cannot be after end date for promotion "${promo.title}"`, true);
        return;
      }
    }
"""
    content = content.replace(
        "// Contact Info Validation",
        validation_logic + "\n    // Contact Info Validation"
    )

    # 5. Update UI for Hero Background Image
    old_hero_ui = """            <div style={{
              width: '100%', height: '160px', borderRadius: '12px', background: 'var(--light-bg)',
              position: 'relative', overflow: 'hidden', border: '2px dashed var(--border)',
              display: 'flex', justifyContent: 'center', alignItems: 'center'
            }}>
              {cmsData.heroImageUrl ? (
                <>
                  <img src={cmsData.heroImageUrl} alt="Hero" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                  <button 
                    onClick={() => handleChange('heroImageUrl', '')} 
                    style={{ position: 'absolute', top: '10px', right: '10px', background: 'rgba(239, 68, 68, 0.9)', color: 'white', border: 'none', borderRadius: '8px', padding: '6px', cursor: 'pointer', zIndex: 10 }}
                    title="Remove Image"
                  >
                    <Trash2 size={16} />
                  </button>
                </>
              ) : (
                <span style={{ color: 'var(--text-muted)' }}>No Image Set</span>
              )}
              <label style={{
                position: 'absolute', bottom: '10px', right: '10px',
                background: 'var(--surface)', padding: '8px', borderRadius: '8px',
                cursor: 'pointer', boxShadow: 'var(--shadow)', display: 'flex'
              }}>
                {uploadingImage === 'heroImageUrl' ? <div className="loader small"></div> : <Camera size={18} />}
                <input type="file" hidden accept="image/*" onChange={(e) => handleUpload(e, 'heroImageUrl')} />
              </label>
            </div>"""

    new_hero_ui = """            <div style={{ display: 'flex', flexWrap: 'wrap', gap: '10px', marginBottom: '10px' }}>
              {(cmsData.heroImageUrls || []).map((url, idx) => (
                <div key={idx} style={{ position: 'relative', width: '120px', height: '80px', borderRadius: '8px', overflow: 'hidden', border: '1px solid var(--border)' }}>
                  <img src={url} alt="Hero" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                  <button 
                    onClick={() => removeHeroImage(idx)} 
                    style={{ position: 'absolute', top: '4px', right: '4px', background: 'rgba(239, 68, 68, 0.9)', color: 'white', border: 'none', borderRadius: '4px', padding: '4px', cursor: 'pointer', zIndex: 10 }}
                  >
                    <Trash2 size={14} />
                  </button>
                </div>
              ))}
              
              <label style={{
                width: '120px', height: '80px', borderRadius: '8px', background: 'var(--light-bg)',
                border: '2px dashed var(--border)', display: 'flex', justifyContent: 'center', alignItems: 'center',
                cursor: 'pointer', color: 'var(--text-muted)'
              }}>
                {uploadingImage === 'heroImageUrls' ? <div className="loader small"></div> : <div style={{textAlign: 'center'}}><Plus size={20} /><div style={{fontSize: '10px'}}>Add Image</div></div>}
                <input type="file" hidden accept="image/*" onChange={(e) => handleUpload(e, 'heroImageUrls')} />
              </label>
            </div>"""

    content = content.replace(old_hero_ui, new_hero_ui)

    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("AdminCMS.js patched")

patch_admin_cms_js()
