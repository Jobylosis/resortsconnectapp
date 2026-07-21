import re
import sys
from datetime import datetime

def patch_homepage_js():
    file_path = "website/src/components/Homepage.js"
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    # 1. Update Hero Carousel to use heroImageUrls
    # Current: {(cmsData?.heroImageUrl ? [{ src: cmsData.heroImageUrl, title: cmsData.heroTitle || 'Featured' }, ...HERO_IMAGES] : HERO_IMAGES).map((item, i) => (
    
    old_hero = "{(cmsData?.heroImageUrl ? [{ src: cmsData.heroImageUrl, title: cmsData.heroTitle || 'Featured' }, ...HERO_IMAGES] : HERO_IMAGES).map((item, i) => ("
    new_hero = "{((cmsData?.heroImageUrls && cmsData.heroImageUrls.length > 0) ? cmsData.heroImageUrls.map(url => ({ src: url, title: cmsData.heroTitle || 'Featured' })) : (cmsData?.heroImageUrl ? [{ src: cmsData.heroImageUrl, title: cmsData.heroTitle || 'Featured' }] : HERO_IMAGES)).map((item, i) => ("
    content = content.replace(old_hero, new_hero)

    # Replace dots indicator
    # Current: {(cmsData?.heroImageUrl ? [cmsData.heroImageUrl, ...HERO_IMAGES] : HERO_IMAGES).map((_, i) => (
    old_dots = "{(cmsData?.heroImageUrl ? [cmsData.heroImageUrl, ...HERO_IMAGES] : HERO_IMAGES).map((_, i) => ("
    new_dots = "{((cmsData?.heroImageUrls && cmsData.heroImageUrls.length > 0) ? cmsData.heroImageUrls : (cmsData?.heroImageUrl ? [cmsData.heroImageUrl] : HERO_IMAGES)).map((_, i) => ("
    content = content.replace(old_dots, new_dots)

    # 2. Update Promotions filter to check endDate
    # Current: Object.values(cmsData.promotions).filter(p => p.active)
    
    old_promo_filter = "Object.values(cmsData.promotions).filter(p => p.active)"
    new_promo_filter = "Object.values(cmsData.promotions).filter(p => p.active && (!p.endDate || new Date(p.endDate) >= new Date().setHours(0,0,0,0)))"
    content = content.replace(old_promo_filter, new_promo_filter)

    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("Homepage.js patched")

patch_homepage_js()
