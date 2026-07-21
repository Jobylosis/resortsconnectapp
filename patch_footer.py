import re

def patch_footer():
    file_path = "lib/landing_page.dart"
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    old_footer = """  Widget _buildFooter() {
    final isDark = Provider.of<ThemeProvider>(context).themeMode == ThemeMode.dark;
    return Container(
      color: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/ResortConnectLogo.png', height: 40),
              const SizedBox(width: 12),
              Text('Resort Connect', style: TextStyle(color: isDark ? Colors.white : isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'The easiest way to discover, book, and manage your resort experiences. Built for tourists and resort owners.',
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 32),
          Divider(color: isDark ? const Color(0xFF1E293B) : Colors.grey[300]),
          const SizedBox(height: 24),
          Text(
            '© ${DateTime.now().year} Resort Connect. All rights reserved.',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        ],
      ),
    );
  }"""

    new_footer = """  Widget _buildFooter() {
    final isDark = Provider.of<ThemeProvider>(context).themeMode == ThemeMode.dark;
    
    final contact = _cmsData != null && _cmsData!['contact'] is Map ? _cmsData!['contact'] : null;
    final String? email = contact != null ? contact['email'] : null;
    final String? phone = contact != null ? contact['phone'] : null;
    final String? facebook = contact != null ? contact['facebook'] : null;

    return Container(
      color: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/ResortConnectLogo.png', height: 40),
              const SizedBox(width: 12),
              Text('Resort Connect', style: TextStyle(color: isDark ? Colors.white : isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'The easiest way to discover, book, and manage your resort experiences. Built for tourists and resort owners.',
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 32),
          if (email != null && email.isNotEmpty || phone != null && phone.isNotEmpty || facebook != null && facebook.isNotEmpty) ...[
            Text('Contact Us', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            if (email != null && email.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.email, size: 16, color: AppTheme.primaryAccent),
                    const SizedBox(width: 8),
                    Text(email, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 14)),
                  ],
                ),
              ),
            if (phone != null && phone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.phone, size: 16, color: AppTheme.primaryAccent),
                    const SizedBox(width: 8),
                    Text(phone, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 14)),
                  ],
                ),
              ),
            if (facebook != null && facebook.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.facebook, size: 16, color: AppTheme.primaryAccent),
                    const SizedBox(width: 8),
                    Text('Facebook', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 14)),
                  ],
                ),
              ),
            const SizedBox(height: 24),
          ],
          Divider(color: isDark ? const Color(0xFF1E293B) : Colors.grey[300]),
          const SizedBox(height: 24),
          Text(
            '© ${DateTime.now().year} Resort Connect. All rights reserved.',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        ],
      ),
    );
  }"""
    
    content = content.replace(old_footer, new_footer)

    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
    
patch_footer()
