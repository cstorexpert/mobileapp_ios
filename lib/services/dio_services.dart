import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:countx/config/config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DioService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30), // Connection timeout
    receiveTimeout: const Duration(seconds: 30), // Response timeout
    sendTimeout: const Duration(seconds: 30),    // Send timeout
  ));

  DioService() {
    // _dio.options.baseUrl = KeycloakConfig.baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 10000);
    _dio.options.receiveTimeout = const Duration(seconds: 10000);
  }

  Future<Response?> login(String username, String password) async {
    try {
      final clientData = {
        "email":"stockapp-uat@gmail.com",
        "password":"stockapp123",
        "returnSecureToken": true
    };
      final tokenGen = await _dio.post(
        '${AppConfig.baseUrl}login',
        data: clientData,
        options: Options(
          // Add per-request timeout if needed
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      final token = tokenGen.data['idToken'];
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', token!);


      //print('printing tokenGen response: ${token}');

      final formData = {
        'username': username,
        'password': password,
      };
      String url = 'users/credentials';
      //print('printing module: ${module}');
      // if(module == 'student'){
      //   url = 'UserProfileAPI/AdminLogIn';
      // }else{
      //   url = '';
      // }
      
      print('printing url: ${AppConfig.baseUrl}${url}');
      
      final response = await _dio.post(
        AppConfig.baseUrl + url,
        data: formData,
        options: Options(
          // Add per-request timeout if needed
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );
      
      print('printing response: ${response}');
      
      if (response.data['id'] != null) {
        if (response.data['id'] != null) {
          print('Login Successful:');
          await _storeCredentials(username, password, response);
          //await saveUserObject(response.data);
          return response;
        } else {
          print('Login failed: ${response.data?['ErrorMessage'] ?? 'Unknown error'}');
          return null;
        }
      } else {
        print('Login failed: ${response.statusCode}');
        return null;
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        print('Login timeout: ${e.message}');
      } else {
        print('Login DioException: ${e.message}');
      }
      return null;
    } catch (e) {
      print('Login error: $e');
      return null;
    }
  }

  Future<void> tempCredentials(String username, String password, String module, bool signInPref) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', username);
    await prefs.setString('password', password);
    await prefs.setString('module', module);
    final currentTimestamp = DateTime.now().millisecondsSinceEpoch; // Current time in milliseconds
    await prefs.setInt('savedTimestamp', currentTimestamp); // Save the timestamp
    print('Timestamp saved: $currentTimestamp');
    String preference = 'false';
    if(signInPref == true){
      preference = 'true'; 
    }
    await prefs.setString('signedPreference', preference); // Corrected key name
  }


  Future<void> _storeCredentials(String username, String password, Response response) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', username);
    await prefs.setString('password', password);

    print('This is my _storeCredentials username ::> $username');
    print('This is my _storeCredentials password ::> $password');
    
    // Check if SchoolId exists in the response data
    if (response.data != null && response.data['role'] != null) {
      await prefs.setString('role', response.data['role']);
      print('GET Role: ${response.data['role']}');
      await prefs.setString('module', response.data['role']);
    }
    
    // You might also want to store the Id
    if (response.data != null && response.data['uid'] != null) {
      await prefs.setString('uid', response.data['uid']);
      print('GET uid: ${response.data['uid']}');
    }
  }


  Future<void> saveUserObject(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    String userJson = jsonEncode(user);
    await prefs.setString('user', userJson);
  }


  Future<String?> getValidAccessToken() async {
    final clientData = {
        "email":"stockapp-uat@gmail.com",
        "password":"stockapp123",
        "returnSecureToken": true
    };
      final tokenGen = await _dio.post(
        '${AppConfig.baseUrl}login',
        data: clientData,
        options: Options(
          // Add per-request timeout if needed
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      final token = tokenGen.data['idToken'];

      return token;
  }
  
}


