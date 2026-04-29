import 'package:countx/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppDrawer extends StatelessWidget {
  final Function(String) onItemTap;

  const AppDrawer({super.key, required this.onItemTap});

  // Theme color constant
  static const Color primaryColor = Color.fromARGB(255, 3, 25, 55);
  static const Color accentColor = Colors.orange;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFFF8F9FA),
      child: Column(
        children: [
          // Premium Header Section
          _buildDrawerHeader(),
          
          // Main Content (scrollable)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFF8F9FA),
                    Colors.white,
                  ],
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  _buildMenuItem(
                    icon: Icons.people_outline,
                    label: 'Users',
                    pageKey: 'users',
                  ),
                  const SizedBox(height: 4),
                  
                  _buildMenuItem(
                    icon: Icons.business_outlined,
                    label: 'Company',
                    pageKey: 'company',
                  ),
                  const SizedBox(height: 4),
                  
                  _buildMenuItem(
                    icon: Icons.qr_code_rounded,
                    label: 'Shortcode',
                    pageKey: 'shortcode',
                  ),
                  const SizedBox(height: 4),
                  
                  _buildMenuItem(
                    icon: Icons.receipt_long_outlined,
                    label: 'Transactions',
                    pageKey: 'barcode',
                  ),
                  // const SizedBox(height: 4),
                  
                  // _buildMenuItem(
                  //   icon: Icons.receipt_long_outlined,
                  //   label: 'Inventory Scan',
                  //   pageKey: 'inventory',
                  // ),
                ],
              ),
            ),
          ),
          
          // Logout Button (fixed at bottom)
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
            ),
            child: _buildLogoutButton(context),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader() {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryColor,
            primaryColor.withOpacity(0.85),
            const Color.fromARGB(255, 5, 35, 75),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            right: -30,
            top: -80,
            child: Container(
              width: 120,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
              ),
            ),
          ),
          Positioned(
            left: -20,
            bottom: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
              ),
            ),
          ),
          
          // Content
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // App Logo
                Container(
                  width: 280,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/Logo.png', // Add your logo here
                      fit: BoxFit.fill,
                      errorBuilder: (context, error, stackTrace) {
                        // Fallback if image not found
                        return Center(
                          child: Text(
                            'CX',
                            style: TextStyle(
                              color: primaryColor,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                
                
                // App Name
                // const Text(
                //   'CountX',
                //   style: TextStyle(
                //     color: Colors.white,
                //     fontSize: 32,
                //     fontWeight: FontWeight.bold,
                //     letterSpacing: 1.5,
                //     height: 1.2,
                //   ),
                // ),
                
                
                // Subtitle
                // Container(
                //   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                //   decoration: BoxDecoration(
                //     color: Colors.white.withOpacity(0.15),
                //     borderRadius: BorderRadius.circular(20),
                //     border: Border.all(
                //       color: Colors.white.withOpacity(0.3),
                //       width: 1,
                //     ),
                //   ),
                //   child: const Text(
                //     'Admin Login',
                //     style: TextStyle(
                //       color: Colors.white,
                //       fontSize: 13,
                //       fontWeight: FontWeight.w600,
                //       letterSpacing: 0.8,
                //     ),
                //   ),
                // ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required String pageKey,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onItemTap(pageKey),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: primaryColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: primaryColor.withOpacity(0.3),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFF6B6B),
            Color(0xFFEE5A6F),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6B6B).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B6B).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.logout_rounded,
                          color: Color(0xFFFF6B6B),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text('Logout'),
                    ],
                  ),
                  content: const Text(
                    'Are you sure you want to logout from your account?',
                    style: TextStyle(fontSize: 15),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        // Clear SharedPreferences
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.clear();

                        // Close dialog before navigating
                        Navigator.of(context).pop();

                        // Navigate to login page
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const LoginPage()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B6B),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Logout',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.logout_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                SizedBox(width: 12),
                Text(
                  'Logout',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Optional: Keep these classes if you need expandable sections in the future
class DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String pageKey;
  final Function(String) onTap;

  const DrawerItem({
    super.key,
    required this.icon,
    required this.label,
    required this.pageKey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: const Color.fromARGB(255, 3, 25, 55)),
      title: Text(label, style: const TextStyle(color: Color.fromARGB(255, 3, 25, 55))),
      onTap: () => onTap(pageKey),
    );
  }
}

class SubDrawerItem extends StatelessWidget {
  final String title;
  final String pageKey;
  final Function(String) onTap;

  const SubDrawerItem({
    super.key,
    required this.title,
    required this.pageKey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 72.0),
      title: Text(title, style: const TextStyle(color: Colors.black87)),
      onTap: () => onTap(pageKey),
    );
  }
}