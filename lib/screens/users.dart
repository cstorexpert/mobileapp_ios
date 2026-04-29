import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:countx/config/config.dart';
import 'package:countx/services/api_services.dart';
import 'package:countx/services/dio_services.dart';

// User Model
class User {
  final String? id;
  final String username;
  final String contact;
  final String email;
  final String address;
  final String role;
  final String password;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  User({
    this.id,
    required this.username,
    required this.contact,
    required this.email,
    required this.address,
    required this.role,
    required this.password,
    this.createdAt,
    this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString(),
      username: json['username'] ?? '',
      contact: json['contact'] ?? '',
      email: json['email'] ?? '',
      address: json['address'] ?? '',
      role: json['role'] ?? '',
      password: json['password'] ?? '',
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'username': username,
      'contact': contact,
      'email': email,
      'address': address,
      'role': role,
      'password': password,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  User copyWith({
    String? id,
    String? username,
    String? contact,
    String? email,
    String? address,
    String? role,
    String? password,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      contact: contact ?? this.contact,
      email: email ?? this.email,
      address: address ?? this.address,
      role: role ?? this.role,
      password: password ?? this.password,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// CSV Import Result for tracking success/errors
class CsvImportResult {
  final User? user;
  final int rowNumber;
  final bool success;
  final String? error;

  CsvImportResult({
    this.user,
    required this.rowNumber,
    required this.success,
    this.error,
  });
}

// API Service (with dummy responses for demonstration)
class UserApiService {
  static const String baseUrl = 'https://your-api-domain.com/api';
  late final ApiService _apiService;
  
  // Dummy data for demonstration
  static List<User> _dummyUsers = [
    User(
      id: '1',
      username: 'John Doe',
      contact: '+1234567890',
      email: 'john.doe@example.com',
      address: '123 Main Street, New York, NY 10001',
      role: 'Admin',
      password: 'password123',
      createdAt: DateTime.now().subtract(Duration(days: 30)),
      updatedAt: DateTime.now().subtract(Duration(days: 5)),
    ),
    User(
      id: '2',
      username: 'Jane Smith',
      contact: '+1987654321',
      email: 'jane.smith@example.com',
      address: '456 Oak Avenue, Los Angeles, CA 90001',
      role: 'Manager',
      password: 'password456',
      createdAt: DateTime.now().subtract(Duration(days: 25)),
      updatedAt: DateTime.now().subtract(Duration(days: 2)),
    ),
    User(
      id: '3',
      username: 'Mike Johnson',
      contact: '+1122334455',
      email: 'mike.johnson@example.com',
      address: '789 Pine Road, Chicago, IL 60601',
      role: 'Employee',
      password: 'password789',
      createdAt: DateTime.now().subtract(Duration(days: 20)),
      updatedAt: DateTime.now().subtract(Duration(days: 1)),
    ),
  ];

  // Simulate network delay
  static Future<void> _simulateNetworkDelay() async {
    await Future.delayed(Duration(milliseconds: 800 + (DateTime.now().millisecond % 500)));
  }

  // GET - Fetch all users
  static Future<List<User>> getUsers() async {
    await _simulateNetworkDelay();
    return List.from(_dummyUsers);
  }

  // POST - Create user
  // static Future<User> createUser(User user) async {
  //   await _simulateNetworkDelay();
    
  //   final newUser = user.copyWith(
  //     id: DateTime.now().millisecondsSinceEpoch.toString(),
  //     createdAt: DateTime.now(),
  //     updatedAt: DateTime.now(),
  //   );
  //   _dummyUsers.add(newUser);
  //   return newUser;
  // }

  // POST - Bulk create users
  static Future<List<CsvImportResult>> bulkCreateUsers(List<User> users) async {
    await _simulateNetworkDelay();
    
    List<CsvImportResult> results = [];
    
    for (int i = 0; i < users.length; i++) {
      try {
        // Check for duplicate email
        bool emailExists = _dummyUsers.any((u) => u.email == users[i].email);
        if (emailExists) {
          results.add(CsvImportResult(
            rowNumber: i + 2, // +2 because row 1 is headers
            success: false,
            error: 'Email already exists',
          ));
          continue;
        }
        
        final newUser = users[i].copyWith(
          id: DateTime.now().millisecondsSinceEpoch.toString() + '_$i',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        _dummyUsers.add(newUser);
        
        results.add(CsvImportResult(
          user: newUser,
          rowNumber: i + 2,
          success: true,
        ));
      } catch (e) {
        results.add(CsvImportResult(
          rowNumber: i + 2,
          success: false,
          error: e.toString(),
        ));
      }
    }
    
    return results;
  }

  // PUT - Update user
  static Future<User> updateUser(String id, User user) async {
    await _simulateNetworkDelay();
    
    final index = _dummyUsers.indexWhere((u) => u.id == id);
    if (index != -1) {
      final updatedUser = user.copyWith(
        id: id,
        updatedAt: DateTime.now(),
      );
      _dummyUsers[index] = updatedUser;
      return updatedUser;
    } else {
      throw Exception('User not found');
    }
  }

  // DELETE - Delete user
  static Future<void> deleteUser(String id) async {
    print('Reached Delete User section');
    await _simulateNetworkDelay();
    _dummyUsers.removeWhere((user) => user.id == id);
  }

  // GET - Get user by ID
  static Future<User> getUserById(String id) async {
    await _simulateNetworkDelay();
    
    final user = _dummyUsers.firstWhere(
      (user) => user.id == id,
      orElse: () => throw Exception('User not found'),
    );
    return user;
  }
}

// Main User Management Screen
class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({Key? key}) : super(key: key);

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen>
    with SingleTickerProviderStateMixin {
  late final ApiService _apiService;
  List<User> users = [];
  bool isLoading = false;
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final DioService _dioService = DioService();

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(_dioService);
    _animationController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _fetchUsers();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    try {
        setState(() => isLoading = true);
      const url = '${AppConfig.baseUrl}users';

      final data = await _apiService.getRequest(url);

      if (data != null) {
        print('Fetched ORDERS ::::>$data');
        
        List<dynamic> usersData = [];
        
        if (data != null) {
          usersData = data;
        } 

        // Convert to User objects
        final fetchedUsers = usersData
            .map((userData) {
              if (userData is Map<String, dynamic>) {
                return User.fromJson(userData);
              } else {
                throw Exception('Invalid user data format');
              }
            })
            .toList();

        setState(() {
          users = fetchedUsers;
          isLoading = false;
        });
        
        _animationController.forward();
        print('Successfully loaded ${users.length} users');
      } else {
        throw Exception('Failed to fetch orders');
      }
    } catch (e) {
      print('Error fetching orders: $e');
      _showErrorSnackBar('Failed to load users: ${e.toString()}');
    } 
  }
  
  Future<void> _loadUsers() async {
    setState(() => isLoading = true);
    try {
      final loadedUsers = await UserApiService.getUsers();
      setState(() {
        users = loadedUsers;
        isLoading = false;
      });
      _animationController.forward();
    } catch (e) {
      setState(() => isLoading = false);
      _showErrorSnackBar('Failed to load users: ${e.toString()}');
    }
  }

  Future<void> _refreshUsers() async {
    await _loadUsers();
  }

  void _showUserDialog({User? user}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => UserDialog(
        user: user,
        onSave: (savedUser) async {
          try {
            setState(() => isLoading = true);
            if (user == null) {
              // Create new user - pass the savedUser (User object)
              print('Creating new user: $savedUser');
              await _createUser(savedUser);
              _showSuccessSnackBar('User created successfully');
            } else {
              // Update existing user
               await _updateUser(user.id!, savedUser);
               _showSuccessSnackBar('User updated successfully');
            }
            await _fetchUsers(); // Use _fetchUsers instead of _loadUsers
          } catch (e) {
            setState(() => isLoading = false);
            _showErrorSnackBar('Failed to save user: ${e.toString()}');
          }
        },
      ),
    );
  }

  void _showBulkUploadDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BulkUploadDialog(
        onUploadComplete: () async {
          await _loadUsers();
        },
      ),
    );
  }

  // Delete User Method
  Future<void> _deleteUser(String userId) async {
    try {
      print('userID $userId');
      final url = '${AppConfig.baseUrl}users/$userId';
      final response = await _apiService.deleteRequest(url);
      
      print('Test  $response');
      
      // Remove from local list immediately for better UX
      setState(() {
        users.removeWhere((user) => user.id == userId);
      });
      
      _showSuccessSnackBar('User deleted successfully');
    } catch (e) {
      throw Exception('Failed to delete user: $e');
    }
  }
  // Future<void> _deleteUser(User user) async {
  //   final confirmed = await showDialog<bool>(
  //     context: context,
  //     builder: (context) => AlertDialog(
  //       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  //       title: Row(
  //         children: [
  //           Icon(Icons.delete_forever, color: Colors.red),
  //           SizedBox(width: 12),
  //           Text('Delete User'),
  //         ],
  //       ),
  //       content: Text('Are you sure you want to delete ${user.username}? This action cannot be undone.'),
  //       actions: [
  //         TextButton(
  //           onPressed: () => Navigator.pop(context, false),
  //           child: Text('Cancel'),
  //         ),
  //         ElevatedButton(
  //           onPressed: () => Navigator.pop(context, true),
  //           style: ElevatedButton.styleFrom(
  //             backgroundColor: Colors.red,
  //             foregroundColor: Colors.white,
  //           ),
  //           child: Text('Delete'),
  //         ),
  //       ],
  //     ),
  //   );

  //   if (confirmed == true) {
  //     try {
  //       setState(() => isLoading = true);
  //       await UserApiService.deleteUser(user.id!);
  //       _showSuccessSnackBar('User deleted successfully');
  //       await _loadUsers();
  //     } catch (e) {
  //       setState(() => isLoading = false);
  //       _showErrorSnackBar('Failed to delete user: ${e.toString()}');
  //     }
  //   }
  // }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error, color: Colors.white),
            SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: Duration(seconds: 4),
      ),
    );
  }

  List<User> get filteredUsers {
    if (searchQuery.isEmpty) return users;
    return users.where((user) =>
        user.username.toLowerCase().contains(searchQuery.toLowerCase()) ||
        user.email.toLowerCase().contains(searchQuery.toLowerCase()) ||
        user.role.toLowerCase().contains(searchQuery.toLowerCase())).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text('User Management'),
        backgroundColor: const Color.fromARGB(255, 3, 25, 55),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _showBulkUploadDialog,
            icon: Icon(Icons.upload_file),
            tooltip: 'Bulk Upload',
          ),
          IconButton(
            onPressed: _refreshUsers,
            icon: Icon(Icons.refresh),
            tooltip: 'Refresh Users',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.white,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search users by username, email, or role...',
                  prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => searchQuery = '');
                          },
                          icon: Icon(Icons.clear, color: Colors.grey.shade600),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: (value) {
                  setState(() => searchQuery = value);
                },
              ),
            ),
          ),
          
          // Users Count
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                Icon(Icons.people, size: 20, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  '${filteredUsers.length} ${filteredUsers.length == 1 ? 'user' : 'users'} found',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // User List
          Expanded(
            child: isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading users...', style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                  )
                : filteredUsers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 80, color: Colors.grey.shade400),
                            SizedBox(height: 20),
                            Text(
                              searchQuery.isEmpty ? 'No users found' : 'No users match your search',
                              style: TextStyle(fontSize: 20, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                            ),
                            SizedBox(height: 8),
                            Text(
                              searchQuery.isEmpty 
                                  ? 'Tap the + button to add your first user'
                                  : 'Try adjusting your search criteria',
                              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      )
                    : FadeTransition(
                        opacity: _fadeAnimation,
                        child: RefreshIndicator(
                          onRefresh: _refreshUsers,
                          child: ListView.builder(
                            padding: EdgeInsets.all(16),
                            itemCount: filteredUsers.length,
                            itemBuilder: (context, index) {
                              final user = filteredUsers[index];
                              return _buildUserCard(user);
                            },
                          ),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUserDialog(),
        icon: Icon(Icons.person_add),
        label: Text('Add User'),
        backgroundColor: const Color.fromARGB(255, 3, 25, 55),
        foregroundColor: Colors.white,
        elevation: 4,
      ),
    );
  }

  Widget _buildUserCard(User user) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showUserDialog(user: user),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: _getRoleColor(user.role).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        _getRoleIcon(user.role),
                        color: _getRoleColor(user.role),
                        size: 28,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.username,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: 4),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getRoleColor(user.role),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              user.role,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) async {
                        switch (value) {
                          case 'edit':
                            _showUserDialog(user: user);
                            break;
                          case 'delete':
                            await _deleteUser(user.id!);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 18, color: Colors.white),
                              SizedBox(width: 12),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, size: 18, color: Colors.red),
                              SizedBox(width: 12),
                              Text('Delete'),
                            ],
                          ),
                        ),
                      ],
                      icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                _buildUserDetailRow(Icons.email, user.email),
                _buildUserDetailRow(Icons.phone, user.contact),
                _buildUserDetailRow(Icons.location_on, user.address),
                if (user.updatedAt != null) ...[
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 14, color: Colors.grey.shade500),
                      SizedBox(width: 8),
                      Text(
                        'Updated ${_formatDate(user.updatedAt!)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserDetailRow(IconData icon, String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 3, 25, 55),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                color: const Color.fromARGB(255, 3, 25, 55),
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Colors.red;
      case 'manager':
        return Colors.orange;
      case 'employee':
        return Colors.green;
      case 'intern':
        return const Color.fromARGB(255, 3, 25, 55);
      default:
        return Colors.grey;
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Icons.admin_panel_settings;
      case 'manager':
        return Icons.manage_accounts;
      case 'employee':
        return Icons.person;
      case 'intern':
        return Icons.school;
      default:
        return Icons.person_outline;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }

  bool _checkSuccess(dynamic data) {
    if (data == null || data is! Map<String, dynamic>) {
      return false;
    }
    
    final successValue = data['success'];
    
    if (successValue == null) {
      // If no success field, assume success if we have data
      return data.containsKey('payload') || data.containsKey('data') || data.containsKey('users');
    }
    
    if (successValue is bool) {
      return successValue;
    } else if (successValue is String) {
      return successValue.toLowerCase() == 'true' || 
            successValue.toLowerCase() == 'success' || 
            successValue == '1';
    } else if (successValue is int) {
      return successValue == 1;
    }
    
    return false;
  }

  Future<void> _createUser(User user) async {
    print('savedUse :::> ${user.toJson()}');
    try {
      const url = '${AppConfig.baseUrl}users';
      final response = await _apiService.postRequest(url, user.toJson());
      await _fetchUsers();
      
      // if (!_checkSuccess(response)) {
      //   throw Exception('Failed to create user: ${response?['message'] ?? 'Unknown error'}');
      // }else{
      //   _fetchUsers();
      // }
    } catch (e) {
      throw Exception('Failed to create user: $e');
    }
  }

  // Update User Method
  Future<void> _updateUser(String userId, User updatedUser) async {
    try {
      final url = '${AppConfig.baseUrl}users/$userId';
      final response = await _apiService.putRequest(url, updatedUser.toJson());
      
      // if (!_checkSuccess(response)) {
      //   throw Exception('Failed to update user: ${response?['message'] ?? 'Unknown error'}');
      // }
      
      // Update the local list immediately for better UX
      setState(() {
        final index = users.indexWhere((user) => user.id == userId);
        if (index != -1) {
          users[index] = updatedUser.copyWith(
            id: userId,
            updatedAt: DateTime.now(),
          );
        }
      });
      
      _showSuccessSnackBar('User updated successfully');
    } catch (e) {
      throw Exception('Failed to update user: $e');
    }
  }

  


}

// Bulk Upload Dialog
class BulkUploadDialog extends StatefulWidget {
  final VoidCallback onUploadComplete;

  const BulkUploadDialog({
    Key? key,
    required this.onUploadComplete,
  }) : super(key: key);

  @override
  State<BulkUploadDialog> createState() => _BulkUploadDialogState();
}

class _BulkUploadDialogState extends State<BulkUploadDialog> {
  bool _isLoading = false;
  String? _fileName;
  List<User>? _parsedUsers;
  List<String> _errors = [];
  List<CsvImportResult>? _uploadResults;
  
  final List<String> _validRoles = ['Admin', 'Manager', 'Employee', 'Intern'];

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.bytes != null) {
        setState(() {
          _fileName = result.files.single.name;
          _errors = [];
          _uploadResults = null;
        });
        _parseCSV(result.files.single.bytes!);
      }
    } catch (e) {
      setState(() {
        _errors = ['Failed to pick file: ${e.toString()}'];
      });
    }
  }

  void _parseCSV(List<int> bytes) {
    try {
      final String csvString = utf8.decode(bytes);
      final List<List<dynamic>> csvTable = CsvToListConverter().convert(csvString);
      
      if (csvTable.isEmpty) {
        setState(() {
          _errors = ['CSV file is empty'];
          _parsedUsers = null;
        });
        return;
      }

      // Check headers
      final headers = csvTable[0].map((e) => e.toString().toLowerCase().trim()).toList();
      final requiredHeaders = ['username', 'contact', 'email', 'address', 'role', 'password'];
      
      List<String> missingHeaders = [];
      for (String required in requiredHeaders) {
        if (!headers.contains(required)) {
          missingHeaders.add(required);
        }
      }
      
      if (missingHeaders.isNotEmpty) {
        setState(() {
          _errors = ['Missing required columns: ${missingHeaders.join(', ')}'];
          _parsedUsers = null;
        });
        return;
      }

      // Parse data rows
      List<User> users = [];
      List<String> parseErrors = [];
      
      for (int i = 1; i < csvTable.length; i++) {
        final row = csvTable[i];
        
        if (row.length < headers.length) {
          parseErrors.add('Row ${i + 1}: Incomplete data');
          continue;
        }

        try {
          String username = row[headers.indexOf('username')].toString().trim();
          String contact = row[headers.indexOf('contact')].toString().trim();
          String email = row[headers.indexOf('email')].toString().trim();
          String address = row[headers.indexOf('address')].toString().trim();
          String role = row[headers.indexOf('role')].toString().trim();
          String password = row[headers.indexOf('password')].toString().trim();

          // Validation
          if (username.isEmpty) {
            parseErrors.add('Row ${i + 1}: Name is required');
            continue;
          }
          
          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}').hasMatch(email)) {
            parseErrors.add('Row ${i + 1}: Invalid email format');
            continue;
          }
          
          // Normalize role
          String normalizedRole = _normalizeRole(role);
          if (!_validRoles.contains(normalizedRole)) {
            parseErrors.add('Row ${i + 1}: Invalid role "$role". Valid roles: ${_validRoles.join(', ')}');
            continue;
          }
          
          if (password.length < 6) {
            parseErrors.add('Row ${i + 1}: Password must be at least 6 characters');
            continue;
          }

          users.add(User(
            username: username,
            contact: contact,
            email: email,
            address: address,
            role: normalizedRole,
            password: password,
          ));
        } catch (e) {
          parseErrors.add('Row ${i + 1}: ${e.toString()}');
        }
      }

      setState(() {
        _parsedUsers = users;
        _errors = parseErrors;
      });
    } catch (e) {
      setState(() {
        _errors = ['Failed to parse CSV: ${e.toString()}'];
        _parsedUsers = null;
      });
    }
  }

  String _normalizeRole(String role) {
    String lower = role.toLowerCase().trim();
    for (String validRole in _validRoles) {
      if (validRole.toLowerCase() == lower) {
        return validRole;
      }
    }
    return role; // Return original if no match found
  }

  Future<void> _uploadUsers() async {
    if (_parsedUsers == null || _parsedUsers!.isEmpty) return;

    setState(() {
      _isLoading = true;
      _uploadResults = null;
    });

    try {
      final results = await UserApiService.bulkCreateUsers(_parsedUsers!);
      
      setState(() {
        _uploadResults = results;
        _isLoading = false;
      });

      int successCount = results.where((r) => r.success).length;
      int failureCount = results.where((r) => !r.success).length;

      if (successCount > 0) {
        widget.onUploadComplete();
      }

      // Show success message if all uploaded successfully
      if (failureCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully uploaded $successCount users'),
            backgroundColor: Colors.green,
          ),
        );
      }

    } catch (e) {
      setState(() {
        _isLoading = false;
        _errors = ['Upload failed: ${e.toString()}'];
      });
    }
  }

  void _downloadTemplate() {
    // Generate CSV template
    String csvContent = 'username,contact,email,address,role,password\n';
    csvContent += 'John Doe,+1234567890,john@example.com,123 Main St,Employee,password123\n';
    csvContent += 'Jane Smith,+9876543210,jane@example.com,456 Oak Ave,Manager,password456\n';
    
    // Note: In a real app, you would use a package like universal_html to download the file
    // For demonstration, we'll just show the template content
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('CSV Template'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Copy this template format:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SelectableText(
                  csvContent,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              SizedBox(height: 16),
              Text('Valid Roles:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text(_validRoles.join(', ')),
              SizedBox(height: 16),
              Text('Requirements:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text('• All fields are required'),
              Text('• Email must be valid format'),
              Text('• Password must be at least 6 characters'),
              Text('• Role must be one of the valid roles'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
          maxWidth: 800,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 3, 25, 55),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.upload_file, color: Colors.white, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bulk Upload Users',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Upload multiple users via CSV or Excel file',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // File Upload Section
                    Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _fileName != null ? Colors.green : Colors.grey.shade300,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: _fileName != null ? Colors.green.shade50 : Colors.grey.shade50,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.cloud_upload,
                            size: 48,
                            color: _fileName != null ? Colors.green : Colors.grey.shade400,
                          ),
                          SizedBox(height: 12),
                          Text(
                            _fileName ?? 'No file selected',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: _fileName != null ? Colors.green.shade700 : Colors.grey.shade600,
                            ),
                          ),
                          SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _isLoading ? null : _pickFile,
                                icon: Icon(Icons.folder_open),
                                label: Text('Choose File'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color.fromARGB(255, 3, 25, 55),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                              // SizedBox(width: 12),
                              // TextButton.icon(
                              //   onPressed: _downloadTemplate,
                              //   icon: Icon(Icons.info_outline),
                              //   label: Text('View Template'),
                              // ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Parsed Users Preview
                    if (_parsedUsers != null) ...[
                      SizedBox(height: 20),
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 3, 25, 55),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color.fromARGB(255, 3, 25, 55)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: const Color.fromARGB(255, 3, 25, 55)),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_parsedUsers!.length} valid users found',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: const Color.fromARGB(255, 3, 25, 55),
                                    ),
                                  ),
                                  if (_parsedUsers!.isNotEmpty)
                                    Text(
                                      'Ready to upload',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: const Color.fromARGB(255, 3, 25, 55),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Preview Table
                      if (_parsedUsers!.isNotEmpty) ...[
                        SizedBox(height: 16),
                        Text(
                          'Preview (first 5 users):',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: MaterialStateProperty.all(Colors.grey.shade100),
                              columns: [
                                DataColumn(label: Text('Name')),
                                DataColumn(label: Text('Email')),
                                DataColumn(label: Text('Role')),
                                DataColumn(label: Text('Contact')),
                              ],
                              rows: _parsedUsers!.take(5).map((user) {
                                return DataRow(cells: [
                                  DataCell(Text(user.username)),
                                  DataCell(Text(user.email)),
                                  DataCell(
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _getRoleColor(user.role),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        user.role,
                                        style: TextStyle(color: Colors.white, fontSize: 12),
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(user.contact)),
                                ]);
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ],

                    // Errors Section
                    if (_errors.isNotEmpty) ...[
                      SizedBox(height: 20),
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.error, color: Colors.red.shade700),
                                SizedBox(width: 12),
                                Text(
                                  'Validation Errors (${_errors.length})',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            Container(
                              constraints: BoxConstraints(maxHeight: 150),
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: _errors.map((error) {
                                    return Padding(
                                      padding: EdgeInsets.symmetric(vertical: 2),
                                      child: Text(
                                        '• $error',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.red.shade600,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Upload Results
                    if (_uploadResults != null) ...[
                      SizedBox(height: 20),
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Upload Results',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildResultStat(
                                    'Success',
                                    _uploadResults!.where((r) => r.success).length,
                                    Colors.green,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: _buildResultStat(
                                    'Failed',
                                    _uploadResults!.where((r) => !r.success).length,
                                    Colors.red,
                                  ),
                                ),
                              ],
                            ),
                            if (_uploadResults!.any((r) => !r.success)) ...[
                              SizedBox(height: 12),
                              Text(
                                'Failed Records:',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              SizedBox(height: 8),
                              Container(
                                constraints: BoxConstraints(maxHeight: 100),
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: _uploadResults!
                                        .where((r) => !r.success)
                                        .map((result) {
                                      return Padding(
                                        padding: EdgeInsets.symmetric(vertical: 2),
                                        child: Text(
                                          '• Row ${result.rowNumber}: ${result.error}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.red.shade600,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Action Buttons
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      child: Text('Close'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: (_isLoading || _parsedUsers == null || _parsedUsers!.isEmpty)
                          ? null
                          : _uploadUsers,
                      child: _isLoading
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('Uploading...'),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.upload, size: 18),
                                SizedBox(width: 8),
                                Text('Upload ${_parsedUsers?.length ?? 0} Users'),
                              ],
                            ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(255, 3, 25, 55),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultStat(String label, int count, Color color) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
             // color: color.shade700,
             color: color
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Colors.red;
      case 'manager':
        return Colors.orange;
      case 'employee':
        return Colors.green;
      case 'intern':
        return const Color.fromARGB(255, 3, 25, 55);
      default:
        return Colors.grey;
    }
  }
}

// User Dialog for Create/Edit
class UserDialog extends StatefulWidget {
  final User? user;
  final Function(User) onSave;

  const UserDialog({
    Key? key,
    this.user,
    required this.onSave,
  }) : super(key: key);

  @override
  State<UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<UserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _contactController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _passwordController = TextEditingController();
  
  String selectedRole = 'Employee';
  bool _obscurePassword = true;
  bool _isLoading = false;

  final List<String> roles = ['Admin', 'Manager', 'Employee', 'Intern'];

  @override
  void initState() {
    super.initState();
    if (widget.user != null) {
      _usernameController.text = widget.user!.username;
      _contactController.text = widget.user!.contact;
      _emailController.text = widget.user!.email;
      _addressController.text = widget.user!.address;
      _passwordController.text = widget.user!.password;
      selectedRole = widget.user!.role;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _saveUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = User(
        id: widget.user?.id,
        username: _usernameController.text.trim(),
        contact: _contactController.text.trim(),
        email: _emailController.text.trim(),
        address: _addressController.text.trim(),
        role: selectedRole,
        password: _passwordController.text,
        createdAt: widget.user?.createdAt,
        updatedAt: DateTime.now(),
      );

      widget.onSave(user);
      Navigator.pop(context);
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving user: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 3, 25, 55),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.user == null ? Icons.person_add : Icons.edit,
                    color: Colors.white,
                    size: 28,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.user == null ? 'Add New User' : 'Edit User',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Form
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildTextField(
                        controller: _usernameController,
                        label: 'Full Name',
                        icon: Icons.person,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a username';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      
                      _buildTextField(
                        controller: _contactController,
                        label: 'Contact Number',
                        icon: Icons.phone,
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a contact number';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      
                      _buildTextField(
                        controller: _emailController,
                        label: 'Email Address',
                        icon: Icons.email,
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter an email';
                          }
                          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}').hasMatch(value)) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      
                      _buildTextField(
                        controller: _addressController,
                        label: 'Address',
                        icon: Icons.location_on,
                        maxLines: 2,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter an address';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      
                      // Role Dropdown
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButtonFormField<String>(
                          value: selectedRole,
                          decoration: InputDecoration(
                            labelText: 'Role',
                            prefixIcon: Icon(Icons.badge, color: const Color.fromARGB(255, 3, 25, 55)),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          items: roles.map((role) {
                            return DropdownMenuItem(
                              value: role,
                              child: Row(
                                children: [
                                  Icon(
                                    _getRoleIcon(role),
                                    size: 18,
                                    color: _getRoleColor(role),
                                  ),
                                  SizedBox(width: 12),
                                  Text(role),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              selectedRole = value!;
                            });
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please select a role';
                            }
                            return null;
                          },
                        ),
                      ),
                      SizedBox(height: 16),
                      
                      // Password Field
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock, color: const Color.fromARGB(255, 3, 25, 55)),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                              icon: Icon(
                                _obscurePassword ? Icons.visibility : Icons.visibility_off,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a password';
                            }
                            if (value.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Action Buttons
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      child: Text('Cancel'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveUser,
                      child: _isLoading
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('Saving...'),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.save, size: 18),
                                SizedBox(width: 8),
                                Text(widget.user == null ? 'Create User' : 'Update User'),
                              ],
                            ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(255, 3, 25, 55),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: const Color.fromARGB(255, 3, 25, 55)),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        validator: validator,
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Colors.red;
      case 'manager':
        return Colors.orange;
      case 'employee':
        return Colors.green;
      case 'intern':
        return const Color.fromARGB(255, 3, 25, 55);
      default:
        return Colors.grey;
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Icons.admin_panel_settings;
      case 'manager':
        return Icons.manage_accounts;
      case 'employee':
        return Icons.person;
      case 'intern':
        return Icons.school;
      default:
        return Icons.person_outline;
    }
  }
}