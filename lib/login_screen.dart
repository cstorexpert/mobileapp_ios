import 'dart:async';

import 'package:flutter/material.dart';
import 'package:countx/screens/admin/admin.dart';
// import 'package:flutter_svg/svg.dart';
import '../../services/dio_services.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Login',
      home: LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final DioService _dioService = DioService();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String? _loginMessage;
  bool _isLoggedIn = false;
  bool _isLoading = false;
  bool _staySignedIn = false;
  String? _selectedModule; // Track selected module (worker/admin)
  String? _moduleSelectionError; // Track module selection error

  // Add focus nodes to track when user interacts with text fields
  final FocusNode _usernameFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    
    // Add listeners to focus nodes to check module selection
    _usernameFocusNode.addListener(() {
      if (_usernameFocusNode.hasFocus && _selectedModule == null) {
        _showModuleSelectionError();
      }
    });
    
    _passwordFocusNode.addListener(() {
      if (_passwordFocusNode.hasFocus && _selectedModule == null) {
        _showModuleSelectionError();
      }
    });
  }

  @override
  void dispose() {
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _showModuleSelectionError() {
    setState(() {
      _moduleSelectionError = "Please select Admin or Worker login first";
    });
    
    // Clear the error after 3 seconds
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _moduleSelectionError = null;
        });
      }
    });
  }

  void _selectModule(String module) {
    setState(() {
      _selectedModule = module;
      _moduleSelectionError = null; // Clear any existing error
    });
  }

  void _login() async {
    // Check if module is selected before login
    if (_selectedModule == null) {
      setState(() {
        _loginMessage = "Please select Admin or Worker login first";
        _isLoggedIn = false;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _loginMessage = "Logging in...";
      _isLoading = true;
    });

    final username = _usernameController.text;
    final password = _passwordController.text;
    
    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _loginMessage = "Username and password cannot be empty";
        _isLoggedIn = false;
        _isLoading = false;
      });
      return;
    }

    try {
      // Add timeout wrapper
      print('printing module: ${_selectedModule}');
      print('username: ${username}');
      print('password: ${password}');
      
      final response = await _dioService.login(username, password)
      .timeout(const Duration(seconds: 45));

      if (!mounted) return;

      if (response != null) {
        if (_staySignedIn) {
          await _dioService.tempCredentials(username, password,_selectedModule!, _staySignedIn);
        }

        setState(() {
          _loginMessage = "Login successful.";
          _isLoggedIn = true;
          _isLoading = false;
        });

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const StreamsPage()),
        );
      } else {
        setState(() {
          _loginMessage = "Login failed. Please check your credentials.";
          _isLoggedIn = false;
          _isLoading = false;
        });
      }
    } on TimeoutException {
      setState(() {
        _loginMessage = "Login timeout. Please check your connection and try again.";
        _isLoggedIn = false;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _loginMessage = "An error occurred. Please try again.";
        _isLoggedIn = false;
        _isLoading = false;
      });
    }
  }

  Widget _buildModuleSelectionButtons() {
    return Column(
      children: [
        // const Text(
        //   'Select Login Type',
        //   style: TextStyle(
        //     fontSize: 16,
        //     fontWeight: FontWeight.w600,
        //     color: Color(0xFF3C4B64),
        //   ),
        // ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _selectModule('worker'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: _selectedModule == 'worker' 
                        ? const Color(0xFF6366F1) 
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _selectedModule == 'worker' 
                          ? const Color(0xFF6366F1) 
                          : Colors.grey.shade300,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.school,
                        color: _selectedModule == 'worker' 
                            ? Colors.white 
                            : const Color(0xFF6366F1),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Worker',
                        style: TextStyle(
                          color: _selectedModule == 'worker' 
                              ? Colors.white 
                              : const Color(0xFF6366F1),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => _selectModule('admin'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: _selectedModule == 'admin' 
                        ? const Color(0xFF10B981) 
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _selectedModule == 'admin' 
                          ? const Color(0xFF10B981) 
                          : Colors.grey.shade300,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_outline,
                        color: _selectedModule == 'admin' 
                            ? Colors.white 
                            : const Color(0xFF10B981),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Admin',
                        style: TextStyle(
                          color: _selectedModule == 'admin' 
                              ? Colors.white 
                              : const Color(0xFF10B981),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // Show error if module not selected
        if (_moduleSelectionError != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red.shade600,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _moduleSelectionError!,
                    style: TextStyle(
                      color: Colors.red.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image
          // Image.asset(
          //   'assets/splash_bg.png',
          //   fit: BoxFit.cover,
          //   width: screenWidth * 0.5,
          //   height: 300,
          // ),
          Container(
            width: screenWidth * 0.5,
            height: 300,
            color: const Color.fromARGB(255, 3, 25, 55), // Approx. navy blue
          ),
          Center(
            child: Container(
              width: 320,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 15,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 20),
                  // SvgPicture.asset(
                  //   'assets/Logo.svg',
                  //   width: 100,
                  //   height: 200,
                  // ),
                  Image.asset(
                    'assets/Logo.png',
                    width: 300,
                    height: screenWidth * 0.15,
                  ),
                  //const SizedBox(height: 10),
                  // const Text(
                  //   'Scan your stocks and generate reports',
                  //   style: TextStyle(fontSize: 10),
                  //   textAlign: TextAlign.left,
                  // ),
                   const SizedBox(height: 20),
                  
                  // Module Selection Buttons
                  _buildModuleSelectionButtons(),
                  
                  TextField(
                    controller: _usernameController,
                    focusNode: _usernameFocusNode,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      prefixIcon: Container(
                        margin: const EdgeInsets.only(top: 4, bottom: 4, right: 8, left: 5),
                        color: const Color.fromARGB(255, 3, 25, 55),
                        child: const Icon(size: 18, Icons.person, color:Colors.white),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      prefixIcon: Container(
                        margin: const EdgeInsets.only(top: 4, bottom: 4, right: 8, left: 5),
                        color: const Color.fromARGB(255, 3, 25, 55),
                        child: const Icon(size: 18, Icons.lock, color:Colors.white),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Padding(
                  //   padding: const EdgeInsets.only(left: 6.0),
                  //   child: Row(
                  //     children: [
                  //       GestureDetector(
                  //         onTap: () {
                  //           setState(() {
                  //             _staySignedIn = !_staySignedIn;
                  //           });
                  //         },
                  //         child: Container(
                  //           height: 15,
                  //           width: 15,
                  //           decoration: BoxDecoration(
                  //             color: _staySignedIn ? const Color(0xFFFFC000) : Colors.transparent,
                  //             borderRadius: BorderRadius.circular(10),
                  //             border: Border.all(
                  //               color: _staySignedIn ? const Color(0xFFFFC000) : Colors.grey,
                  //               width: 2,
                  //             ),
                  //           ),
                  //           child: _staySignedIn
                  //               ? const Icon(
                  //                   Icons.check,
                  //                   size: 11,
                  //                   color: Colors.white,
                  //                 )
                  //               : null,
                  //         ),
                  //       ),
                  //       const SizedBox(width: 8),
                  //       const Text(
                  //         'Stay Signed In',
                  //         style: TextStyle(
                  //           fontSize: 10,
                  //           color: Color(0xFF3C4B64),
                  //         ),
                  //       ),
                  //       SizedBox(width: screenWidth * 0.2),
                  //       const Text(
                  //         'Forgot Password',
                  //         style: TextStyle(
                  //           fontSize: 10,
                  //           color: Color(0xFF3C4B64),
                  //         ),
                  //       ),
                  //     ],
                  //   ),
                  // ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 100.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      backgroundColor: _isLoading ? Colors.grey : const Color.fromARGB(255, 3, 25, 55),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Sign In',
                            style: TextStyle(fontSize: 14, color: Colors.white),
                          ),
                  ),
                  const SizedBox(height: 20),
                  if (_loginMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _loginMessage == "Login successful."
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _loginMessage == "Login successful."
                              ? Colors.green.shade200
                              : Colors.red.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _loginMessage == "Login successful."
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            color: _loginMessage == "Login successful."
                                ? Colors.green.shade600
                                : Colors.red.shade600,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _loginMessage!,
                              style: TextStyle(
                                color: _loginMessage == "Login successful."
                                    ? Colors.green.shade600
                                    : Colors.red.shade600,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}