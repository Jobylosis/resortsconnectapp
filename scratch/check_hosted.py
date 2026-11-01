import urllib.request
import re

try:
    req = urllib.request.urlopen('https://resortconnect-f7dd6.web.app')
    html = req.read().decode('utf-8')
    scripts = re.findall(r'src="([^"]+main\.[a-f0-9]+\.js)"', html)
    print('Live main js script:', scripts)
    if scripts:
        js_url = 'https://resortconnect-f7dd6.web.app' + scripts[0]
        js_req = urllib.request.urlopen(js_url)
        js_text = js_req.read().decode('utf-8')
        print('isRecipientVerified in live hosted website:', 'isRecipientVerified' in js_text)
except Exception as e:
    print('Error:', e)

