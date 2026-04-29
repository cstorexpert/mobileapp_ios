import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:countx/login_screen.dart';
import 'package:countx/screens/users.dart';
//import 'package:countx/screens/company.dart';
import 'package:countx/services/api_services.dart';
import 'package:countx/services/dio_services.dart';
import 'package:shared_preferences/shared_preferences.dart';
//import 'package:countx/splash_screen.dart'; // import your SplashScreen
//import './login_screen.dart';

void main() {
  runApp(const StockVisionApp());
}

class StockVisionApp extends StatelessWidget {
  const StockVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CountX',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final DioService _dioService;
  late final ApiService _apiService;

  @override
  void initState() {
    super.initState();
    _dioService = DioService();
    _apiService = ApiService(_dioService);
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');
    final password = prefs.getString('password');
    final preference = prefs.getString('signedPreference');

    final testdata = await getUserObject();
    print('This is my testdata ::> $testdata');

    print('This is my username ::> $username');
    print('This is my password ::> $password');
    print('This is my signedPreference ::> $preference');

    final elapsed = await is24HoursElapsed();
    // print('This is my Elapsed time ::> $elapsed');
    if(elapsed == false){
      if(preference == 'true'){
        print('This is my preference ::> $preference');
        if (username != null && password != null) {
          // Optional: Validate credentials with the backend
           print('This is username and password ::> $preference');
          final isValid = await _apiService.login(username, password);
          if (isValid == true) {
            final currentTimestamp = DateTime.now().millisecondsSinceEpoch; // Current time in milliseconds
            await prefs.setInt('savedTimestamp', currentTimestamp); // Save the timestamp
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const UserManagementScreen()),
            );
            // Navigator.pushReplacement(
            //   context,
            //   MaterialPageRoute(builder: (context) => LoginPage()),
            // );
          } else {
            print('Reached At this part of code');
            // Clear invalid credentials and navigate to login
            await prefs.remove('username');
            await prefs.remove('password');
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => LoginPage()),
            );
            // Navigator.pushReplacement(
            //   context,
            //   MaterialPageRoute(builder: (context) => StockManagementScreen(allocatedSection: 'E-CIGARETTE',)),
            // );
          }
        } else {
          // Navigate to Login Page if no credentials found
          print('Reached At this Else');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => LoginPage()),
          );
          // Navigator.pushReplacement(
          //   context,
          //   MaterialPageRoute(builder: (context) => StockManagementScreen(allocatedSection: 'E-CIGARETTE',)),
          // );
        }
      }else{
        // Navigate to Login Page if no credentials found
          // Navigator.pushReplacement(
          //   context,
          //   MaterialPageRoute(builder: (context) => StockManagementScreen(allocatedSection: 'E-CIGARETTE',)),
          // );

          Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const LoginPage()),
            );
          
      }
    }else{
        
          await prefs.setString('username', '');
          await prefs.setString('password', '');
          await prefs.setString('signedPreference', 'false');
          //await prefs.setInt('savedTimestamp', 0); // Save the timestamp
        // Navigator.pushReplacement(
        //     context,
        //     MaterialPageRoute(builder: (context) => StockManagementScreen(allocatedSection: 'Electronics',)),
        //   );
    }
    
  }

  Future<Map<String, dynamic>?> getUserObject() async {
    final prefs = await SharedPreferences.getInstance();
    String? userJson = prefs.getString('user');
    // print('This is my testdata ::> $userJson');
    if (userJson != null) {
      return jsonDecode(userJson);
    }
    return null;
  }

  Future<bool> is24HoursElapsed() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTimestamp = prefs.getInt('savedTimestamp') ?? 0; // Get saved timestamp, default is 0
    if (savedTimestamp == 0) {
      print('No timestamp found.');
      return false; // No timestamp saved
    }

    final currentTimestamp = DateTime.now().millisecondsSinceEpoch;
    final differenceInMilliseconds = currentTimestamp - savedTimestamp;
    final differenceInHours = differenceInMilliseconds / (1000 * 60 * 60); // Convert to hours

    print('Difference in hours: $differenceInHours');
    return differenceInHours >= 24; // Check if 24 hours or more have passed
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: CircularProgressIndicator(), // Splash screen loading indicator
        //child:StockManagementScreen(allocatedSection: 'E-CIGARETTE',)
      ),
    );
  }
}

