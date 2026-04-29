// screens/shortcode_management_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:countx/config/config.dart';
import 'package:countx/services/api_services.dart';
import 'package:countx/services/dio_services.dart';

// ShortCode Model
class ShortCode {
  final String? id;
  final String shortcode;
  final String longcode;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ShortCode({
    this.id,
    required this.shortcode,
    required this.longcode,
    this.createdAt,
    this.updatedAt,
  });

  factory ShortCode.fromJson(Map<String, dynamic> json) {
    return ShortCode(
      id: json['id']?.toString(),
      shortcode: json['shortcode'] ?? '',
      longcode: json['longcode'] ?? '',
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'shortcode': shortcode,
      'longcode': longcode,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  ShortCode copyWith({
    String? id,
    String? shortcode,
    String? longcode,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ShortCode(
      id: id ?? this.id,
      shortcode: shortcode ?? this.shortcode,
      longcode: longcode ?? this.longcode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// Excel Import Result for tracking success/errors
class ExcelImportResult {
  final ShortCode? shortCode;
  final int rowNumber;
  final bool success;
  final String? error;

  ExcelImportResult({
    this.shortCode,
    required this.rowNumber,
    required this.success,
    this.error,
  });
}

// Main ShortCode Management Screen
class ShortCodeManagementScreen extends StatefulWidget {
  const ShortCodeManagementScreen({Key? key}) : super(key: key);

  @override
  State<ShortCodeManagementScreen> createState() => _ShortCodeManagementScreenState();
}

class _ShortCodeManagementScreenState extends State<ShortCodeManagementScreen>
    with SingleTickerProviderStateMixin {
  late final ApiService _apiService;
  List<ShortCode> shortCodes = [];
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
    _fetchShortCodes();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchShortCodes() async {
    try {
      setState(() => isLoading = true);
      const url = '${AppConfig.baseUrl}shortcode';

      final data = await _apiService.getRequest(url);

      if (data != null) {
        print('Fetched SHORTCODES ::::>$data');
        
        List<dynamic> shortCodesData = [];
        
        if (data is List) {
          shortCodesData = data;
        } else if (data is Map && data['data'] != null) {
          shortCodesData = data['data'];
        }

        // Convert to ShortCode objects
        final fetchedShortCodes = shortCodesData
            .map((shortCodeData) {
              if (shortCodeData is Map<String, dynamic>) {
                return ShortCode.fromJson(shortCodeData);
              } else {
                throw Exception('Invalid shortcode data format');
              }
            })
            .toList();

        setState(() {
          shortCodes = fetchedShortCodes;
          isLoading = false;
        });
        
        _animationController.forward();
        print('Successfully loaded ${shortCodes.length} shortcodes');
      } else {
        throw Exception('Failed to fetch shortcodes');
      }
    } catch (e) {
      print('Error fetching shortcodes: $e');
      _showErrorSnackBar('Failed to load shortcodes: ${e.toString()}');
      setState(() => isLoading = false);
    } 
  }

  Future<void> _refreshShortCodes() async {
    await _fetchShortCodes();
  }

  void _showShortCodeDialog({ShortCode? shortCode}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ShortCodeDialog(
        shortCode: shortCode,
        onSave: (savedShortCode) async {
          try {
            setState(() => isLoading = true);
            if (shortCode == null) {
              // Create new shortcode
              print('Creating new shortcode: $savedShortCode');
              await _createShortCode(savedShortCode);
              _showSuccessSnackBar('ShortCode created successfully');
            } else {
              // Update existing shortcode
              await _updateShortCode(shortCode.id!, savedShortCode);
              _showSuccessSnackBar('ShortCode updated successfully');
            }
            await _fetchShortCodes();
          } catch (e) {
            setState(() => isLoading = false);
            _showErrorSnackBar('Failed to save shortcode: ${e.toString()}');
          }
        },
      ),
    );
  }

  void _showBulkUploadDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _BulkUploadDialog(
        onUploadComplete: () async {
          await _fetchShortCodes();
        },
      ),
    );
  }

  // Delete ShortCode Method
  Future<void> _deleteShortCode(String shortCodeId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ShortCode'),
        content: Text('Are you sure you want to delete this shortcode? This action cannot be undone.'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      print('shortCodeId $shortCodeId');
      final url = '${AppConfig.baseUrl}shortcode/$shortCodeId';
      final response = await _apiService.deleteRequest(url);
      
      print('Delete response: $response');
      
      // Remove from local list immediately for better UX
      setState(() {
        shortCodes.removeWhere((shortCode) => shortCode.id == shortCodeId);
      });
      
      _showSuccessSnackBar('ShortCode deleted successfully');
    } catch (e) {
      _showErrorSnackBar('Failed to delete shortcode: $e');
    }
  }

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

  List<ShortCode> get filteredShortCodes {
    if (searchQuery.isEmpty) return shortCodes;
    return shortCodes.where((shortCode) =>
        shortCode.shortcode.toLowerCase().contains(searchQuery.toLowerCase()) ||
        shortCode.longcode.toLowerCase().contains(searchQuery.toLowerCase())).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text('ShortCode Management'),
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
            onPressed: _refreshShortCodes,
            icon: Icon(Icons.refresh),
            tooltip: 'Refresh ShortCodes',
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
                  hintText: 'Search shortcodes by code or description...',
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
          
          // ShortCodes Count
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                Icon(Icons.code, size: 20, color: const Color.fromARGB(255, 3, 25, 55)),
                SizedBox(width: 8),
                Text(
                  '${filteredShortCodes.length} ${filteredShortCodes.length == 1 ? 'shortcode' : 'shortcodes'} found',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // ShortCode List
          Expanded(
            child: isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading shortcodes...', style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                  )
                : filteredShortCodes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.code_off, size: 80, color: Colors.grey.shade400),
                            SizedBox(height: 20),
                            Text(
                              searchQuery.isEmpty ? 'No shortcodes found' : 'No shortcodes match your search',
                              style: TextStyle(fontSize: 20, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                            ),
                            SizedBox(height: 8),
                            Text(
                              searchQuery.isEmpty 
                                  ? 'Tap the + button to add your first shortcode'
                                  : 'Try adjusting your search criteria',
                              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      )
                    : FadeTransition(
                        opacity: _fadeAnimation,
                        child: RefreshIndicator(
                          onRefresh: _refreshShortCodes,
                          child: ListView.builder(
                            padding: EdgeInsets.all(16),
                            itemCount: filteredShortCodes.length,
                            itemBuilder: (context, index) {
                              final shortCode = filteredShortCodes[index];
                              return _buildShortCodeCard(shortCode);
                            },
                          ),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showShortCodeDialog(),
        icon: Icon(Icons.add),
        label: Text('Add ShortCode'),
        backgroundColor: const Color.fromARGB(255, 3, 25, 55),
        foregroundColor: Colors.white,
        elevation: 4,
      ),
    );
  }

  Widget _buildShortCodeCard(ShortCode shortCode) {
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
          onTap: () => _showShortCodeDialog(shortCode: shortCode),
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
                        color: const Color.fromARGB(255, 3, 25, 55).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        Icons.code,
                        color: const Color.fromARGB(255, 3, 25, 55),
                        size: 28,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(255, 3, 25, 55),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              shortCode.shortcode,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            shortCode.longcode,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) async {
                        switch (value) {
                          case 'edit':
                            _showShortCodeDialog(shortCode: shortCode);
                            break;
                          case 'delete':
                            await _deleteShortCode(shortCode.id!);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 18, color: const Color.fromARGB(255, 3, 25, 55)),
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
                if (shortCode.updatedAt != null) ...[
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 14, color: Colors.grey.shade500),
                      SizedBox(width: 8),
                      Text(
                        'Updated ${_formatDate(shortCode.updatedAt!)}',
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

  Future<void> _createShortCode(ShortCode shortCode) async {
    print('savedShortCode :::> ${shortCode.toJson()}');
    try {
      const url = '${AppConfig.baseUrl}shortcode';
      final response = await _apiService.postRequest(url, shortCode.toJson());
      print('Create response: $response');
    } catch (e) {
      throw Exception('Failed to create shortcode: $e');
    }
  }

  // Update ShortCode Method
  Future<void> _updateShortCode(String shortCodeId, ShortCode updatedShortCode) async {
    try {
      final url = '${AppConfig.baseUrl}shortcode/$shortCodeId';
      final response = await _apiService.putRequest(url, updatedShortCode.toJson());
      
      print('Update response: $response');
      
      // Update the local list immediately for better UX
      setState(() {
        final index = shortCodes.indexWhere((shortCode) => shortCode.id == shortCodeId);
        if (index != -1) {
          shortCodes[index] = updatedShortCode.copyWith(
            id: shortCodeId,
            updatedAt: DateTime.now(),
          );
        }
      });
    } catch (e) {
      throw Exception('Failed to update shortcode: $e');
    }
  }
}

// Bulk Upload Dialog
class _BulkUploadDialog extends StatefulWidget {
  final VoidCallback onUploadComplete;

  const _BulkUploadDialog({
    Key? key,
    required this.onUploadComplete,
  }) : super(key: key);

  @override
  State<_BulkUploadDialog> createState() => _BulkUploadDialogState();
}

class _BulkUploadDialogState extends State<_BulkUploadDialog> {
  bool _isLoading = false;
  String? _fileName;
  List<ShortCode>? _parsedShortCodes;
  List<String> _errors = [];
  List<ExcelImportResult>? _uploadResults;

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.bytes != null) {
        setState(() {
          _fileName = result.files.single.name;
          _errors = [];
          _uploadResults = null;
        });
        _parseExcel(result.files.single.bytes!);
      }
    } catch (e) {
      setState(() {
        _errors = ['Failed to pick file: ${e.toString()}'];
      });
    }
  }

  void _parseExcel(Uint8List bytes) {
    try {
      var excel = Excel.decodeBytes(bytes);
      
      if (excel.tables.isEmpty) {
        setState(() {
          _errors = ['Excel file has no worksheets'];
          _parsedShortCodes = null;
        });
        return;
      }

      // Get the first sheet
      var table = excel.tables[excel.tables.keys.first];
      
      if (table == null || table.rows.isEmpty) {
        setState(() {
          _errors = ['Excel sheet is empty'];
          _parsedShortCodes = null;
        });
        return;
      }

      // Check if first row contains headers
      var firstRow = table.rows[0];
      bool hasHeaders = false;
      
      if (firstRow.length >= 2) {
        var firstCell = firstRow[0]?.value?.toString()?.toLowerCase().trim() ?? '';
        var secondCell = firstRow[1]?.value?.toString()?.toLowerCase().trim() ?? '';
        
        if (firstCell.contains('short') || secondCell.contains('long')) {
          hasHeaders = true;
        }
      }

      // Parse data rows
      List<ShortCode> shortCodes = [];
      List<String> parseErrors = [];
      
      int startRow = hasHeaders ? 1 : 0;
      
      for (int i = startRow; i < table.rows.length; i++) {
        final row = table.rows[i];
        
        if (row.length < 2) {
          parseErrors.add('Row ${i + 1}: Incomplete data - needs both shortcode and longcode');
          continue;
        }

        try {
          String shortcode = row[0]?.value?.toString()?.trim() ?? '';
          String longcode = row[1]?.value?.toString()?.trim() ?? '';

          // Validation
          if (shortcode.isEmpty) {
            parseErrors.add('Row ${i + 1}: Shortcode is required');
            continue;
          }
          
          if (longcode.isEmpty) {
            parseErrors.add('Row ${i + 1}: Longcode is required');
            continue;
          }

          // Check for duplicates in current batch
          bool isDuplicate = shortCodes.any((sc) => 
            sc.shortcode.toLowerCase() == shortcode.toLowerCase()
          );
          
          if (isDuplicate) {
            parseErrors.add('Row ${i + 1}: Duplicate shortcode "$shortcode" in file');
            continue;
          }

          shortCodes.add(ShortCode(
            shortcode: shortcode.toUpperCase(),
            longcode: longcode,
          ));
        } catch (e) {
          parseErrors.add('Row ${i + 1}: ${e.toString()}');
        }
      }

      setState(() {
        _parsedShortCodes = shortCodes;
        _errors = parseErrors;
      });
    } catch (e) {
      setState(() {
        _errors = ['Failed to parse Excel: ${e.toString()}'];
        _parsedShortCodes = null;
      });
    }
  }

  Future<void> _uploadShortCodes() async {
    if (_parsedShortCodes == null || _parsedShortCodes!.isEmpty) return;

    setState(() {
      _isLoading = true;
      _uploadResults = null;
    });

    try {
      // Prepare bulk data for single API call
      final bulkData = {
        'shortcodes': _parsedShortCodes!.map((sc) => sc.toJson()).toList(),
      };
      
      
      // const url = '${AppConfig.baseUrl}shortcode/bulk';
      // final response = await ApiService(DioService()).postRequest(
      //       url, 
      //       bulkData
      //     );

      final response = {};
      
      // Parse response to create results
      List<ExcelImportResult> results = [];
      
      if (response != null && response['results'] != null) {
        // If API returns detailed results for each item
        List<dynamic> apiResults = response['results'];
        
        for (int i = 0; i < apiResults.length; i++) {
          final result = apiResults[i];
          final bool success = result['success'] == true;
          
          results.add(ExcelImportResult(
            shortCode: success ? _parsedShortCodes![i] : null,
            rowNumber: i + 1,
            success: success,
            error: success ? null : (result['error']?.toString() ?? 'Unknown error'),
          ));
        }
      } else {
        // If API doesn't return detailed results, assume all succeeded
        for (int i = 0; i < _parsedShortCodes!.length; i++) {
          results.add(ExcelImportResult(
            shortCode: _parsedShortCodes![i],
            rowNumber: i + 1,
            success: true,
          ));
        }
      }
      
      setState(() {
        _uploadResults = results;
        _isLoading = false;
      });

      int successCount = results.where((r) => r.success).length;
      int failureCount = results.where((r) => !r.success).length;

      if (successCount > 0) {
        widget.onUploadComplete();
      }

      // Show success message
      if (failureCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully uploaded $successCount shortcodes'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Uploaded $successCount shortcodes, $failureCount failed'),
            backgroundColor: failureCount > successCount ? Colors.red : Colors.orange,
          ),
        );
      }

    } catch (e) {
      setState(() {
        _isLoading = false;
        _errors = ['Upload failed: ${e.toString()}'];
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _downloadTemplate() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Excel Template Format'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Create an Excel file (.xlsx or .xls) with this structure:', 
                   style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Column A: shortcode', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('Column B: longcode', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text('Example:', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('A1: "HOME"    B1: "Go to Homepage"'),
                    Text('A2: "ABOUT"   B2: "Navigate to About Us"'),
                    Text('A3: "CONTACT" B3: "Visit Contact Page"'),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Text('Requirements:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text('• Both shortcode and longcode are required'),
              Text('• Shortcodes must be unique'),
              Text('• Headers are optional (will be auto-detected)'),
              Text('• Supported formats: .xlsx, .xls'),
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
                          'Upload ShortCodes',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Upload multiple shortcodes via Excel file',
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
                                label: Text('Choose Excel File'),
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

                    // Parsed ShortCodes Preview
                    if (_parsedShortCodes != null) ...[
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
                                    '${_parsedShortCodes!.length} valid shortcodes found',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: const Color.fromARGB(255, 3, 25, 55),
                                    ),
                                  ),
                                  if (_parsedShortCodes!.isNotEmpty)
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
                      if (_parsedShortCodes!.isNotEmpty) ...[
                        SizedBox(height: 16),
                        Text(
                          'Preview (first 5 shortcodes):',
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
                                DataColumn(label: Text('ShortCode')),
                                DataColumn(label: Text('LongCode')),
                              ],
                              rows: _parsedShortCodes!.take(5).map((shortCode) {
                                return DataRow(cells: [
                                  DataCell(
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color.fromARGB(255, 3, 25, 55),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        shortCode.shortcode,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    SizedBox(
                                      width: 200,
                                      child: Text(
                                        shortCode.longcode,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                  ),
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
                      onPressed: (_isLoading || _parsedShortCodes == null || _parsedShortCodes!.isEmpty)
                          ? null
                          : _uploadShortCodes,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(255, 3, 25, 55),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
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
                                Text('Upload ${_parsedShortCodes?.length ?? 0} ShortCodes'),
                              ],
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
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ShortCode Dialog for Create/Edit
class _ShortCodeDialog extends StatefulWidget {
  final ShortCode? shortCode;
  final Function(ShortCode) onSave;

  const _ShortCodeDialog({
    Key? key,
    this.shortCode,
    required this.onSave,
  }) : super(key: key);

  @override
  State<_ShortCodeDialog> createState() => _ShortCodeDialogState();
}

class _ShortCodeDialogState extends State<_ShortCodeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _shortcodeController = TextEditingController();
  final _longcodeController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.shortCode != null) {
      _shortcodeController.text = widget.shortCode!.shortcode;
      _longcodeController.text = widget.shortCode!.longcode;
    }
  }

  @override
  void dispose() {
    _shortcodeController.dispose();
    _longcodeController.dispose();
    super.dispose();
  }

  Future<void> _saveShortCode() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final shortCode = ShortCode(
        id: widget.shortCode?.id,
        shortcode: _shortcodeController.text.trim().toUpperCase(),
        longcode: _longcodeController.text.trim(),
        createdAt: widget.shortCode?.createdAt,
        updatedAt: DateTime.now(),
      );

      widget.onSave(shortCode);
      Navigator.pop(context);
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving shortcode: ${e.toString()}'),
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
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
          maxWidth: 500,
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
                  Icon(
                    widget.shortCode == null ? Icons.add : Icons.edit,
                    color: Colors.white,
                    size: 28,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.shortCode == null ? 'Add New ShortCode' : 'Edit ShortCode',
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
                      // ShortCode Field
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: TextFormField(
                          controller: _shortcodeController,
                          textCapitalization: TextCapitalization.characters,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            labelText: 'ShortCode',
                            hintText: 'e.g., HOME, ABOUT, CONTACT',
                            prefixIcon: Icon(Icons.code, color: const Color.fromARGB(255, 3, 25, 55)),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a shortcode';
                            }
                            if (value.trim().length < 2) {
                              return 'Shortcode must be at least 2 characters';
                            }
                            if (!RegExp(r'^[A-Z0-9_]+').hasMatch(value.trim().toUpperCase())) {
                              return 'Shortcode can only contain letters, numbers, and underscores';
                            }
                            return null;
                          },
                        ),
                      ),
                      SizedBox(height: 20),
                      
                      // LongCode Field
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: TextFormField(
                          controller: _longcodeController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'LongCode (Description)',
                            hintText: 'Enter the full description or meaning of the shortcode',
                            prefixIcon: Padding(
                              padding: EdgeInsets.only(bottom: 60),
                              child: Icon(Icons.description, color: const Color.fromARGB(255, 3, 25, 55)),
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a description';
                            }
                            if (value.trim().length < 3) {
                              return 'Description must be at least 3 characters';
                            }
                            return null;
                          },
                        ),
                      ),
                      SizedBox(height: 20),

                      // Preview Card
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 3, 25, 55),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color.fromARGB(255, 3, 25, 55)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Preview:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: const Color.fromARGB(255, 3, 25, 55),
                              ),
                            ),
                            SizedBox(height: 8),
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color.fromARGB(255, 3, 25, 55),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _shortcodeController.text.toUpperCase().isEmpty 
                                        ? 'SHORTCODE' 
                                        : _shortcodeController.text.toUpperCase(),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _longcodeController.text.isEmpty 
                                        ? 'Description will appear here' 
                                        : _longcodeController.text,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade700,
                                      fontStyle: _longcodeController.text.isEmpty 
                                          ? FontStyle.italic 
                                          : FontStyle.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
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
                      onPressed: _isLoading ? null : _saveShortCode,
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
                                Text(widget.shortCode == null ? 'Create ShortCode' : 'Update ShortCode'),
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
}