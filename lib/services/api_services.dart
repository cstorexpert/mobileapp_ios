


import 'package:dio/dio.dart';
import 'package:countx/config/config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/dio_services.dart';

class ApiService {
  final Dio _dio = Dio();
  final DioService _dioService;

  ApiService(this._dioService) {
    _dio.options.connectTimeout = const Duration(seconds: 100); // 10 seconds
    _dio.options.receiveTimeout = const Duration(seconds: 100); // 10 seconds
  }

  Future<dynamic> getRequest(String url) async {
    try {
       final prefs = await SharedPreferences.getInstance();
       final token = prefs.getString('token');
       final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token', // Ensure this is included
          },
        ),
      );
       //print('GET response: ${response.data}');
      return response.data;
    } catch (e) {
      // print('GET request error: $e');
      // return null;

      print('GET request error: $e');

      final token = await _dioService.getValidAccessToken();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', token!);

      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token', // Ensure this is included
          },
        ),
      );

      // Print the response for debugging
      print('GET response: ${response.data}');
      return response.data;
    }
  }

  Future<dynamic> postRequest(String url, Map<String, dynamic> data) async {
  try {
    // Ensure a valid token is retrieved
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null) {
      throw Exception('Failed to retrieve a valid token');
    }

    // Print the token for debugging
    // print('POST request token: $token');
    // print('POST request URL: $url');
    // print('POST request Data: $data');

    final response = await _dio.post(
      url,
      data: data,
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ),
    );

    // Print the response for debugging
    print('POST response: ${response.data}');
    return response.data;
  } catch (e) {
    print('POST request error: $e');

    final token = await _dioService.getValidAccessToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token!);

    final response = await _dio.post(
      url,
      data: data,
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ),
    );

    // Print the response for debugging
    print('POST response: ${response.data}');
    return response.data;
  }
}

  // PUT request method
  Future<Map<String, dynamic>?> putRequest(String url, Map<String, dynamic> data) async {
    try {
      // Ensure a valid token is retrieved
      //final token = await _dioService.getValidAccessToken();

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        throw Exception('Failed to retrieve a valid token');
      }

      if (token == null) {
        throw Exception('Failed to retrieve a valid token');
      }

      final response = await _dio.put(
        url,
        data: data,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );
      return response.data;
    } on DioException catch (e) {
      print('PUT request failed: ${e.message}');
      if (e.response != null) {
        print('Response data: ${e.response!.data}');
        print('Response status: ${e.response!.statusCode}');
      }
      throw Exception('PUT request failed: ${e.message}');
    } catch (e) {
      // print('Unexpected error during PUT request: $e');
      // throw Exception('Unexpected error during PUT request: $e');

      final token = await _dioService.getValidAccessToken();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', token!);

      if (token == null) {
        throw Exception('Failed to retrieve a valid token');
      }

      final response = await _dio.put(
        url,
        data: data,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );
      return response.data;
    }
  }

  // DELETE request method
  Future<Map<String, dynamic>?> deleteRequest(String url) async {
    try {
      //final token = await _dioService.getValidAccessToken();

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        throw Exception('Failed to retrieve a valid token');
      }


      final response = await _dio.delete(
        url,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token', // Ensure this is included
          },
        ),
      );
      return response.data;
    } on DioException catch (e) {
      print('DELETE request failed: ${e.message}');
      if (e.response != null) {
        print('Response data: ${e.response!.data}');
        print('Response status: ${e.response!.statusCode}');
      }
      throw Exception('DELETE request failed: ${e.message}');
    } catch (e) {
      // print('Unexpected error during DELETE request: $e');
      // throw Exception('Unexpected error during DELETE request: $e');
      print('DELETE request error: $e');

      final token = await _dioService.getValidAccessToken();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', token!);


      final response = await _dio.delete(
        url,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token', // Ensure this is included
          },
        ),
      );
      return response.data;
    }
  }

  Future<bool?> login(String username, String password) async {
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
          return true;
          //await _storeCredentials(username, password, response);
          //await saveUserObject(response.data);
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
}






