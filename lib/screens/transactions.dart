import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:countx/config/config.dart';
import 'package:countx/services/api_services.dart';
import 'package:countx/services/dio_services.dart';


import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' hide Border;
import 'dart:convert';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';


// Main Transaction Screen
class TransactionScreen extends StatefulWidget {
  const TransactionScreen({Key? key}) : super(key: key);

  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> with SingleTickerProviderStateMixin {

  String? userModule;

  final List<Map<String, dynamic>> _transactions = [];
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late final ApiService _apiService;
  final DioService _dioService = DioService();
  
  bool isLoading = false;
  bool isCreating = false;
  bool isDeleting = false;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(_dioService);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
    _loadUserModule();
    _fetchTransactions();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadUserModule() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userModule = prefs.getString('module');
    });
  }

  Future<void> _fetchTransactions() async {
    try {
      setState(() => isLoading = true);
      const url = '${AppConfig.baseUrl}transactions';

      final data = await _apiService.getRequest(url);

      if (data != null) {
        List<dynamic> transactionsData = [];
        
        if (data is List) {
          transactionsData = data;
        } else if (data is Map && data['data'] != null) {
          transactionsData = data['data'];
        }

        setState(() {
          _transactions.clear();
          _transactions.addAll(transactionsData.map((transaction) => 
            Map<String, dynamic>.from(transaction)
          ).toList());
          isLoading = false;
        });
        
        _animationController.forward();
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to load transactions: ${e.toString()}');
      setState(() => isLoading = false);
    }
  }

  void _openCreateTransaction() async {
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const CreateTransactionScreen(
          isEditMode: false,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: animation.drive(
              Tween(begin: const Offset(1.0, 0.0), end: Offset.zero).chain(
                CurveTween(curve: Curves.easeInOut),
              ),
            ),
            child: child,
          );
        },
      ),
    );

    if (result != null) {
      await _fetchTransactions();
    }
  }

  void _openEditTransaction(Map<String, dynamic> transaction) async {
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => CreateTransactionScreen(
          isEditMode: true,
          transactionData: transaction,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: animation.drive(
              Tween(begin: const Offset(1.0, 0.0), end: Offset.zero).chain(
                CurveTween(curve: Curves.easeInOut),
              ),
            ),
            child: child,
          );
        },
      ),
    );

    if (result != null) {
      await _fetchTransactions();
    }
  }

  // void _openProcessTransaction(Map<String, dynamic> transaction) async {
  //   // Navigate directly to StockManagementScreen
  //   await Navigator.push(
  //     context,
  //     MaterialPageRoute(
  //       builder: (context) => StockManagementScreen(
  //       transactionId: transaction['id']?.toString() ?? '',
  //       companyName: transaction['companyName']?.toString() ?? '',
  //       contactPerson: transaction['contactPerson']?.toString() ?? '',
  //     ),
  //     ),
  //   );
  // }

  void _openProcessTransaction(Map<String, dynamic> transaction) async {
    try {
      setState(() => isLoading = true);
      final companyId = transaction['companyId'];
      final url = '${AppConfig.baseUrl}company/$companyId';
      
      final companyData = await _apiService.getRequest(url);
      setState(() => isLoading = false);
      
      if (companyData != null && companyData['layout'] != null) {
        final List<dynamic> sections = companyData['layout'] is List 
          ? companyData['layout'] 
          : [];
        
        if (sections.isEmpty) {
          _showErrorSnackBar('No sections available for this company');
          return;
        }
        
        // Pass transaction data to bottom sheet
        final selectedSection = await _showSectionSelectionBottomSheet(
          sections,
          transaction, // Pass the transaction data
        );
        
        if (selectedSection != null) {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StockManagementScreen(
                transactionId: transaction['id']?.toString() ?? '',
                companyName: transaction['companyName']?.toString() ?? '',
                contactPerson: transaction['contactPerson']?.toString() ?? '',
                sectionId: selectedSection['id']?.toString() ?? '',
                sectionName: selectedSection['name']?.toString() ?? '',
              ),
            ),
          );
          if (result != null && result is Map && result['sectionCompleted'] == true) {
            // Update local transaction data
            setState(() {
              final sectionName = selectedSection['name']?.toString() ?? '';
              if (transaction['sections'] == null) {
                transaction['sections'] = {};
              }
              transaction['sections'][sectionName] = {
                'status': 'completed',
                'completedAt': DateTime.now().toIso8601String(),
              };
              
              // Check if all sections are completed
              final sections = transaction['sections'] as Map;
              final allCompleted = sections.values.every((s) => 
                s is Map && s['status'] == 'completed'
              );
              
              if (allCompleted) {
                transaction['status'] = 'completed';
              }
            });
            
            // Optional: Fetch fresh data from server
            // await _fetchTransactions();
          }
        }
      } else {
        _showErrorSnackBar('No sections found for this company');
      }
    } catch (e) {
      setState(() => isLoading = false);
      _showErrorSnackBar('Failed to load sections: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>?> _showSectionSelectionBottomSheet(
    List<dynamic> sections,
    Map<String, dynamic> transactionData,
  ) async {
    final sectionsStatus = transactionData['sections'] ?? {};
    
    return await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.category, size: 30, color: const Color.fromARGB(255, 3, 25, 55)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Select Section',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Choose a section to manage stock',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: sections.length,
                  itemBuilder: (context, index) {
                    final section = sections[index];
                    final sectionName = section['name']?.toString() ?? 'Section ${index + 1}';
                    final sectionStatus = sectionsStatus[sectionName];
                    final isCompleted = sectionStatus?['status'] == 'completed';
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isCompleted ? Colors.green.shade300 : Colors.grey.shade300,
                          width: isCompleted ? 2 : 1,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: isCompleted 
                            ? null // Disable tap for completed sections
                            : () => Navigator.pop(context, section),
                          child: Opacity(
                            opacity: isCompleted ? 0.6 : 1.0,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: isCompleted 
                                        ? Colors.green.shade50 
                                        : const Color.fromARGB(255, 3, 25, 55),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      isCompleted ? Icons.check_circle : Icons.category,
                                      color: isCompleted 
                                        ? Colors.green.shade700 
                                        : Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                sectionName,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            if (isCompleted)
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.shade100,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  'Completed',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.green.shade700,
                                                  ),
                                                ),
                                              )
                                            else
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange.shade100,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  'Pending A',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.orange.shade700,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        if (section['description'] != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            section['description'].toString(),
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                        if (isCompleted && sectionStatus?['completedAt'] != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Completed: ${DateFormat('MMM dd, HH:mm').format(DateTime.parse(sectionStatus['completedAt']))}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.green.shade600,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    isCompleted ? Icons.lock : Icons.arrow_forward_ios,
                                    size: 16,
                                    color: isCompleted ? Colors.green : Colors.grey,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _deleteTransaction(Map<String, dynamic> transaction) async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Transaction'),
          content: const Text('Are you sure you want to delete this transaction? This action cannot be undone.'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      
      if (confirmed != true) return;
      
      setState(() => isDeleting = true);
      final url = '${AppConfig.baseUrl}transactions/${transaction["id"]}';
      
      await _apiService.deleteRequest(url);
      
      _showSuccessSnackBar('Transaction deleted successfully!');
      await _fetchTransactions();
      setState(() => isDeleting = false);
    } catch (e) {
      _showErrorSnackBar('Failed to delete transaction: ${e.toString()}');
      setState(() => isDeleting = false);
    }
  }

  // void _showTransactionDetails(Map<String, dynamic> transaction) {
  //   showModalBottomSheet(
  //     context: context,
  //     isScrollControlled: true,
  //     backgroundColor: Colors.transparent,
  //     builder: (context) {
  //       return Container(
  //         decoration: const BoxDecoration(
  //           color: Colors.white,
  //           borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  //         ),
  //         padding: const EdgeInsets.all(24),
  //         child: Column(
  //           mainAxisSize: MainAxisSize.min,
  //           crossAxisAlignment: CrossAxisAlignment.start,
  //           children: [
  //             Row(
  //               children: [
  //                 const Icon(Icons.business, size: 30, color: const Color.fromARGB(255, 3, 25, 55)),
  //                 const SizedBox(width: 12),
  //                 Expanded(
  //                   child: Text(
  //                     transaction['companyName'] ?? "Transaction Details",
  //                     style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
  //                   ),
  //                 ),
  //                 IconButton(
  //                   icon: const Icon(Icons.edit, color: const Color.fromARGB(255, 3, 25, 55)),
  //                   onPressed: () {
  //                     Navigator.pop(context);
  //                     _openEditTransaction(transaction);
  //                   },
  //                 ),
  //                 IconButton(
  //                   icon: const Icon(Icons.play_arrow, color: Colors.green),
  //                   onPressed: () {
  //                     Navigator.pop(context);
  //                     _openProcessTransaction(transaction);
  //                   },
  //                 ),
  //                 IconButton(
  //                   icon: const Icon(Icons.delete, color: Colors.red),
  //                   onPressed: () {
  //                     Navigator.pop(context);
  //                     _deleteTransaction(transaction);
  //                   },
  //                 ),
  //               ],
  //             ),
  //             const SizedBox(height: 24),
  //             _buildDetailRow(Icons.person, "Contact Person", transaction['contactPerson']?.toString() ?? 'N/A'),
  //             _buildDetailRow(Icons.business, "Company", transaction['companyName']?.toString() ?? 'N/A'),
  //             const SizedBox(height: 24),
  //             Center(
  //               child: ElevatedButton.icon(
  //                 onPressed: () {
  //                   Navigator.pop(context);
  //                   _openProcessTransaction(transaction);
  //                 },
  //                 icon: const Icon(Icons.play_arrow),
  //                 label: const Text('Process Transaction'),
  //                 style: ElevatedButton.styleFrom(
  //                   backgroundColor: Colors.green,
  //                   foregroundColor: Colors.white,
  //                   padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
  //                 ),
  //               ),
  //             ),
  //             const SizedBox(height: 12),
  //             Center(
  //               child: TextButton(
  //                 onPressed: () => Navigator.pop(context),
  //                 child: const Text("Close", style: TextStyle(fontSize: 16)),
  //               ),
  //             ),
  //           ],
  //         ),
  //       );
  //     },
  //   );
  // }

  void _showTransactionDetails(Map<String, dynamic> transaction) {
    final sections = transaction['sections'] ?? {};
    final totalSections = sections.length;
    final completedSections = sections.values.where((s) => s['status'] == 'completed').length;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.business, size: 30, color: const Color.fromARGB(255, 3, 25, 55)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          transaction['companyName'] ?? "Transaction Details",
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        // Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getStatusColor(transaction['status']),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            (transaction['status'] ?? 'pending').toString().toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (userModule == 'admin') ...[
                    IconButton(
                      icon: const Icon(Icons.edit, color: const Color.fromARGB(255, 3, 25, 55)),
                      onPressed: () {
                        Navigator.pop(context);
                        _openEditTransaction(transaction);
                      },
                      tooltip: 'Edit',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteTransaction(transaction);
                      },
                      tooltip: 'Delete',
                    ),
                    // Always show reports button
                    IconButton(
                      icon: const Icon(Icons.assessment, color: const Color.fromARGB(255, 3, 25, 55)),
                      onPressed: () {
                        Navigator.pop(context);
                        _openTransactionReport(transaction);
                      },
                      tooltip: 'Reports',
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              _buildDetailRow(Icons.person, "Contact Person", transaction['contactPerson']?.toString() ?? 'N/A'),
              _buildDetailRow(Icons.business, "Company", transaction['companyName']?.toString() ?? 'N/A'),
              
              // Section progress
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.category, size: 20, color: Colors.grey.shade600),
                  const SizedBox(width: 12),
                  Text(
                    'Section Progress',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Progress bar
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$completedSections of $totalSections sections completed',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${totalSections > 0 ? ((completedSections / totalSections) * 100).toStringAsFixed(0) : 0}%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: const Color.fromARGB(255, 3, 25, 55),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: totalSections > 0 ? completedSections / totalSections : 0,
                        backgroundColor: Colors.grey.shade300,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          completedSections == totalSections ? Colors.green : const Color.fromARGB(255, 3, 25, 55),
                        ),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Section list
              if (sections.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  constraints: BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: sections.keys.length,
                    itemBuilder: (context, index) {
                      final sectionName = sections.keys.toList()[index];
                      final sectionStatus = sections[sectionName];
                      final isCompleted = sectionStatus['status'] == 'completed';
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isCompleted ? Colors.green.shade50 : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isCompleted ? Colors.green.shade200 : Colors.orange.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isCompleted ? Icons.check_circle : Icons.pending,
                              color: isCompleted ? Colors.green.shade700 : Colors.orange.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    sectionName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                  if (isCompleted && sectionStatus['completedAt'] != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Completed: ${DateFormat('MMM dd, HH:mm').format(DateTime.parse(sectionStatus['completedAt']))}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green.shade600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isCompleted ? Colors.green.shade100 : Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isCompleted ? 'Completed' : 'Pending',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isCompleted ? Colors.green.shade700 : Colors.orange.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _openProcessTransaction(transaction);
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Process Transaction'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close", style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Helper method to get status color
  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'in-progress':
        return const Color.fromARGB(255, 3, 25, 55);
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  void _openTransactionReport(Map<String, dynamic> transaction) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TransactionReportScreen(
          transactionId: transaction['id']?.toString() ?? '',
          companyId: transaction['companyId']?.toString() ?? '',
          companyName: transaction['companyName']?.toString() ?? '',
        ),
      ),
    );
    
    // If transaction was closed in report screen, refresh
    if (result != null && result == true) {
      await _fetchTransactions();
    }
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 16),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromRGBO(250, 250, 250, 1),
      appBar: AppBar(
        title: const Text('Transactions'),
        backgroundColor: const Color.fromARGB(255, 3, 25, 55),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: isLoading && _transactions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchTransactions,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: _transactions.isEmpty
                    ? ListView(
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.7,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.business, size: 80, color: Colors.grey.shade400),
                                  const SizedBox(height: 20),
                                  Text(
                                    "No transactions created yet",
                                    style: TextStyle(fontSize: 20, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Tap the + button to add your first transaction",
                                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _transactions.length,
                        itemBuilder: (context, index) {
                          final transaction = _transactions[index];
                          final sections = transaction['sections'] ?? {};
                          final totalSections = sections.length;
                          final completedSections = sections.values.where((s) => s['status'] == 'completed').length;
                          final status = transaction['status'] ?? 'pending';
                          
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: status == 'completed' ? Colors.green.shade200 : Colors.grey.shade200,
                                width: status == 'completed' ? 2 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _showTransactionDetails(transaction),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 50,
                                            height: 50,
                                            decoration: BoxDecoration(
                                              color: _getStatusColor(status).withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              status == 'completed' ? Icons.verified : Icons.business,
                                              color: _getStatusColor(status),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        transaction['companyName']?.toString() ?? 'Unnamed Transaction',
                                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: _getStatusColor(status),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Text(
                                                        status.toUpperCase(),
                                                        style: const TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  transaction['contactPerson']?.toString() ?? 'No contact',
                                                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                                                ),
                                                if (totalSections > 0) ...[
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    children: [
                                                      Icon(Icons.category, size: 14, color: Colors.grey.shade600),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        '$completedSections/$totalSections sections',
                                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: ClipRRect(
                                                          borderRadius: BorderRadius.circular(4),
                                                          child: LinearProgressIndicator(
                                                            value: completedSections / totalSections,
                                                            backgroundColor: Colors.grey.shade300,
                                                            valueColor: AlwaysStoppedAnimation<Color>(
                                                              completedSections == totalSections ? Colors.green : const Color.fromARGB(255, 3, 25, 55),
                                                            ),
                                                            minHeight: 4,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: Icon(
                                              Icons.play_arrow,
                                              color: status == 'completed' ? Colors.grey : Colors.green,
                                            ),
                                            onPressed: status == 'completed' 
                                              ? null 
                                              : () => _openProcessTransaction(transaction),
                                            tooltip: status == 'completed' ? 'Completed' : 'Process',
                                          ),
                                          const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      )
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isCreating ? null : _openCreateTransaction,
        icon: const Icon(Icons.add),
        label: const Text('Add Transaction'),
        backgroundColor: const Color.fromARGB(255, 3, 25, 55),
        foregroundColor: Colors.white,
        elevation: 4,
      ),
    );
  }
}


// Create Transaction Screen
class CreateTransactionScreen extends StatefulWidget {
  final bool isEditMode;
  final Map<String, dynamic>? transactionData;

  const CreateTransactionScreen({
    Key? key,
    this.isEditMode = false,
    this.transactionData,
  }) : super(key: key);

  @override
  _CreateTransactionScreenState createState() => _CreateTransactionScreenState();
}

class _CreateTransactionScreenState extends State<CreateTransactionScreen> {
  late final ApiService _apiService;
  final DioService _dioService = DioService();
  
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _contactPersonController = TextEditingController();
  
  List<Map<String, dynamic>> _companies = [];
  Map<String, dynamic>? _selectedCompany;
  
  bool isLoading = false;
  bool isSaving = false;
  
  @override
  void initState() {
    super.initState();
    _apiService = ApiService(_dioService);
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _fetchCompanies();  // Wait for users to load first
    
    // Now load company data if in edit mode
    if (widget.isEditMode && widget.transactionData != null) {
      _loadTransactionData();
    }
  }

  Future<void> _fetchCompanies() async {
    try {
      setState(() => isLoading = true);
      const url = '${AppConfig.baseUrl}company';

      final data = await _apiService.getRequest(url);

      if (data != null) {
        List<dynamic> companiesData = [];
        
        if (data is List) {
          companiesData = data;
        } else if (data is Map && data['data'] != null) {
          companiesData = data['data'];
        }

        setState(() {
          _companies.clear();
          _companies.addAll(companiesData.map((company) => 
            Map<String, dynamic>.from(company)
          ).toList());
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to load companies: ${e.toString()}');
      setState(() => isLoading = false);
    }
  }

  void _loadTransactionData() {
    final data = widget.transactionData!;
    //print('_loadTransactionData ::::> $data');
    //print('_loadTransactionData _companies ::::> $_companies');
    _contactPersonController.text = data['contactPerson']?.toString() ?? '';
    
    // Find and set the selected company
    if (data['companyId'] != null) {
      final companyId = data['companyId'].toString();
      final company = _companies.firstWhere(
        (c) => c['id'].toString() == companyId,
        orElse: () => {},
      );
      if (company.isNotEmpty) {
        setState(() {
          _selectedCompany = company;
        });
      }
    }
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedCompany == null) {
      _showErrorSnackBar('Please select a company');
      return;
    }

    try {
      setState(() => isSaving = true);

      // Create sections object from layout
      Map<String, dynamic> sectionsStatus = {};
      final layout = _selectedCompany!['layout'] ?? [];
      
      for (var section in layout) {
        String sectionName = section['name']?.toString() ?? '';
        if (sectionName.isNotEmpty) {
          sectionsStatus[sectionName] = {
            'status': 'pending',
            'completedAt': null,
            'completedBy': null,
          };
        }
      }

      final transactionData = {
        'companyId': _selectedCompany!['id'],
        'companyName': _selectedCompany!['name'],
        'layout': _selectedCompany!['layout'],
        'contactPerson': _contactPersonController.text.trim(),
        'status': 'pending', // NEW: Overall transaction status
        'sections': sectionsStatus, // NEW: Section-wise status
      };

      String url;
      dynamic result;

      if (widget.isEditMode && widget.transactionData != null) {
        // Update existing transaction
        url = '${AppConfig.baseUrl}transactions/${widget.transactionData!['id']}';
        result = await _apiService.putRequest(url, transactionData);
      } else {
        // Create new transaction
        url = '${AppConfig.baseUrl}transactions';
        result = await _apiService.postRequest(url, transactionData);
      }

      setState(() => isSaving = false);

      if (result != null) {
        _showSuccessSnackBar(
          widget.isEditMode 
            ? 'Transaction updated successfully!' 
            : 'Transaction created successfully!'
        );

        // Go back to transaction list
        Navigator.pop(context, true);
      } else {
        throw Exception('Failed to save transaction');
      }
    } catch (e) {
      _showErrorSnackBar('Failed to save transaction: ${e.toString()}');
      setState(() => isSaving = false);
    }
  }

  void _navigateToStockManagement(dynamic transactionResult) async {
    // Extract transaction ID from result
    String transactionId = '';
    if (transactionResult is Map) {
      transactionId = transactionResult['id']?.toString() ?? 
                      transactionResult['_id']?.toString() ?? '';
    }

    if (transactionId.isEmpty && widget.transactionData != null) {
      transactionId = widget.transactionData!['id']?.toString() ?? '';
    }

    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => StockManagementScreen(
          transactionId: transactionId,
          companyName: _selectedCompany!['name']?.toString() ?? '',
          contactPerson: _contactPersonController.text.trim(), sectionId: '', sectionName: '',
        ),
      ),
    );
  }
 
  @override
  void dispose() {
    _contactPersonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          widget.isEditMode ? 'Edit Transaction' : 'Create Transaction', 
          style: const TextStyle(fontWeight: FontWeight.bold)
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: Colors.grey.shade200,
            height: 1,
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    
                    // Company Dropdown
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: DropdownButtonFormField<Map<String, dynamic>>(
                        value: _selectedCompany,
                        decoration: InputDecoration(
                          labelText: 'Select Company *',
                          prefixIcon: const Icon(Icons.business, color: const Color.fromARGB(255, 3, 25, 55)),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                        items: _companies.map((company) {
                          return DropdownMenuItem<Map<String, dynamic>>(
                            value: company,
                            child: Text(
                              company['name']?.toString() ?? 'Unknown Company',
                              style: const TextStyle(fontSize: 16),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedCompany = value;
                          });
                        },
                        validator: (value) {
                          if (value == null) {
                            return 'Please select a company';
                          }
                          return null;
                        },
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Contact Person Name
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextFormField(
                        controller: _contactPersonController,
                        decoration: InputDecoration(
                          labelText: 'Contact Person Name *',
                          prefixIcon: const Icon(Icons.person, color: const Color.fromARGB(255, 3, 25, 55)),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter contact person name';
                          }
                          return null;
                        },
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // Continue/Save Button
                    ElevatedButton(
                      onPressed: isSaving ? null : _saveTransaction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(255, 3, 25, 55),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              widget.isEditMode ? 'Save Changes' : 'Continue',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Info text
                    if (!widget.isEditMode)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 3, 25, 55),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color.fromARGB(255, 3, 25, 55)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: const Color.fromARGB(255, 3, 25, 55), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'After filling these details, you will proceed to stock management',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: const Color.fromARGB(255, 3, 25, 55),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 16),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}


class StockManagementScreen extends StatefulWidget {
  final String transactionId;
  final String companyName;
  final String contactPerson;
  final String sectionId;
  final String sectionName;
  
  const StockManagementScreen({
    Key? key,
    required this.transactionId,
    required this.companyName,
    required this.contactPerson,
    required this.sectionId,
    required this.sectionName,
  }) : super(key: key);

  @override
  State<StockManagementScreen> createState() => _StockManagementScreenState();
}

class _StockManagementScreenState extends State<StockManagementScreen> 
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  String selectedPage = 'dashboard';

  void setPage(String page) {
    setState(() {
      selectedPage = page;
    });
    Navigator.pop(context); // Close drawer
  }

  Widget getPageContent() {
    switch (selectedPage) {
      case 'dashboard':
        return const Center(child: Text('Dashboard Page'));
      // case 'upload_stock':
      //   return const Center(child: Text('Upload Stock Page'));
      // case 'upload_consumption':
      //   return const Center(child: Text('Upload Consumption Page'));
      // case 'report_stock':
      //   return const Center(child: Text('Aggregate Stock Report Page'));
      // case 'customer_node_status':
      //   return const CustomerNodeStatusScreen();
      // case 'aggregate_stock_report':
      //   return AggregateStockScreen();
      // case 'trend_report':
      //   return  TrendReportScreen();
      default:
        return const Center(child: Text('Page not found'));
    }
  }

  // Data structures
  Map<String, StockItem> previousStock = {};
  Map<String, StockItem> currentStock = {};
  List<String> departments = [];
  
  // NEW: Transaction data and buffer
  late TransactionData _transactionData;
  List<ScannedItem> _unsavedBuffer = [];
  static const int BUFFER_SIZE = 25;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  
  // Controllers
  final TextEditingController scanCodeController = TextEditingController();
  final TextEditingController codeController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController departmentController = TextEditingController();
  final TextEditingController rateController = TextEditingController();
  final TextEditingController quantityController = TextEditingController();
  
  // Services
  late final ApiService _apiService;
  final DioService _dioService = DioService();
  
  // State variables
  int currentStep = 0;
  bool isScanning = false;
  String? uploadedFileName;
  DateTime? lastUpdated;
  bool isUploading = false;
  double uploadProgress = 0.0;
  MobileScannerController scannerController = MobileScannerController();

  final FocusNode scanCodeFocusNode = FocusNode();
  final FocusNode codeFocusNode = FocusNode();
  final FocusNode nameFocusNode = FocusNode();
  final FocusNode departmentFocusNode = FocusNode();
  final FocusNode rateFocusNode = FocusNode();
  final FocusNode quantityFocusNode = FocusNode();
  
  @override
  void initState() {
    super.initState();
    _apiService = ApiService(_dioService);
    WidgetsBinding.instance.addObserver(this);
    _initializeTransactionData();
    loadSavedStock();
    scanCodeController.addListener(_onScanCodeChanged);
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    scanCodeController.dispose();
    codeController.dispose();
    nameController.dispose();
    departmentController.dispose();
    rateController.dispose();
    quantityController.dispose();
    scannerController.dispose();
    scanCodeFocusNode.dispose();
    codeFocusNode.dispose();
    nameFocusNode.dispose();
    departmentFocusNode.dispose();
    rateFocusNode.dispose();
    quantityFocusNode.dispose();
    scanCodeController.removeListener(_onScanCodeChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive) {
      // App going to background - save to SharedPreferences
      _saveToLocalStorage();
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 16),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _updateTransactionStatus(String status) async {
    try {
      final url = '${AppConfig.baseUrl}transactions/${widget.transactionId}';
      await _apiService.putRequest(url, {'status': status});
    } catch (e) {
      //print('Failed to update transaction status: $e');
    }
  }

  // NEW: Initialize transaction data
  Future<void> _initializeTransactionData() async {
    try {
      // Try to load from SharedPreferences first
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getString('transaction_data_${widget.transactionId}_${widget.sectionId}');
      
      if (savedData != null) {
        // Load existing data
        final decoded = json.decode(savedData);
        setState(() {
          _transactionData = TransactionData.fromJson(decoded);
          _lastSyncTime = _transactionData.lastSynced;
        });
      } else {
        // Fetch company data to get layout
        await _fetchCompanyLayout();
      }
    } catch (e) {
      //print('Error initializing transaction data: $e');
      _showErrorSnackBar('Failed to initialize: ${e.toString()}');
    }
  }

  // NEW: Fetch company layout
  Future<void> _fetchCompanyLayout() async {
    try {
      setState(() => isUploading = true);
      
      // Get company data from transaction
      final transactionUrl = '${AppConfig.baseUrl}transactions/${widget.transactionId}';
      final transactionData = await _apiService.getRequest(transactionUrl);
      
      if (transactionData != null) {
        final companyId = transactionData['companyId'];
        
        // Fetch company to get layout
        final companyUrl = '${AppConfig.baseUrl}company/$companyId';
        final companyData = await _apiService.getRequest(companyUrl);
        
        if (companyData != null && companyData['layout'] != null) {
          setState(() {
            _transactionData = TransactionData(
              companyId: companyId,
              transactionId: widget.transactionId,
              sectionId: widget.sectionId,
              sectionName: widget.sectionName,
              contactPerson: widget.contactPerson,
              layout: companyData['layout'] is List ? companyData['layout'] : [],
              scannedData: {widget.sectionName: []},
              sectionTotals: {},
            );
            isUploading = false;
          });
          
          // Save initial structure
          await _saveToLocalStorage();
        }
      }
    } catch (e) {
      //print('Error fetching company layout: $e');
      setState(() => isUploading = false);
    }
  }

  // NEW: Save to local storage
  Future<void> _saveToLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = json.encode(_transactionData.toJson());
      await prefs.setString(
        'transaction_data_${widget.transactionId}_${widget.sectionId}',
        encoded
      );
      setState(() {
        lastUpdated = DateTime.now();
      });
    } catch (e) {
      //print('Error saving to local storage: $e');
    }
  }

  // NEW: Add item to buffer and manage sync
  Future<void> _addToBufferAndSync(ScannedItem item) async {
    // Check if this is the first item being added (transaction starts)
    final isFirstItem = _transactionData.scannedData[widget.sectionName]?.isEmpty ?? true;
    
    // Check if item already exists in section's scanned data
    final sectionItems = _transactionData.scannedData[widget.sectionName] ?? [];
    
    final existingIndex = sectionItems.indexWhere(
      (existingItem) => existingItem.code == item.code || existingItem.scanCode == item.scanCode
    );
    
    if (existingIndex != -1) {
      // Update existing item
      sectionItems[existingIndex] = item;
      
      // Remove from unsaved buffer if it was there
      _unsavedBuffer.removeWhere(
        (bufferItem) => bufferItem.code == item.code || bufferItem.scanCode == item.scanCode
      );
    } else {
      // Add new item to section
      sectionItems.add(item);
    }
    
    // Add/update in unsaved buffer
    final bufferIndex = _unsavedBuffer.indexWhere(
      (bufferItem) => bufferItem.code == item.code || bufferItem.scanCode == item.scanCode
    );
    
    if (bufferIndex != -1) {
      _unsavedBuffer[bufferIndex] = item;
    } else {
      _unsavedBuffer.add(item);
    }
    
    // Update transaction data
    _transactionData.scannedData[widget.sectionName] = sectionItems;
    
    // If this is the first item, update transaction status to in-progress
    if (isFirstItem && sectionItems.length == 1) {
      await _updateTransactionStatus('in-progress');
    }
    
    // Save to local storage
    await _saveToLocalStorage();
    
    setState(() {});
    
    // Check if buffer reached limit
    if (_unsavedBuffer.length >= BUFFER_SIZE) {
      await _syncToServer();
    }
  }

  // NEW: Sync to server
  Future<void> _syncToServer() async {
    if (_unsavedBuffer.isEmpty || _isSyncing) return;
    
    setState(() => _isSyncing = true);
    
    try {
      final url = '${AppConfig.baseUrl}transactions/${widget.transactionId}/scanned-data';
      
      final payload = {
        'sectionId': widget.sectionId,
        'sectionName': widget.sectionName,
        'newItems': _unsavedBuffer.map((item) => item.toJson()).toList(),
      };
      
      final result = await _apiService.postRequest(url, payload);
      
      if (result != null) {
        // Success - clear buffer
        setState(() {
          _unsavedBuffer.clear();
          _lastSyncTime = DateTime.now();
          _transactionData = TransactionData(
            companyId: _transactionData.companyId,
            transactionId: _transactionData.transactionId,
            sectionId: _transactionData.sectionId,
            sectionName: _transactionData.sectionName,
            contactPerson: _transactionData.contactPerson,
            layout: _transactionData.layout,
            scannedData: _transactionData.scannedData,
            sectionTotals: _transactionData.sectionTotals,
            status: _transactionData.status,
            lastSynced: DateTime.now(),
          );
          _isSyncing = false;
        });
        
        await _saveToLocalStorage();
        
        _showSuccessSnackBar('${_unsavedBuffer.length} items synced successfully!');
      } else {
        throw Exception('Sync failed - no response');
      }
    } catch (e) {
      //print('Sync error: $e');
      setState(() => _isSyncing = false);
      
      _showErrorSnackBar('Sync failed: ${e.toString()}. Data saved locally.');
      
      // Show retry option
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_unsavedBuffer.length} items pending sync. Tap to retry.'),
          backgroundColor: Colors.orange,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _syncToServer(),
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  // UPDATED: Add or update stock with buffer management
  void addOrUpdateStock() {
    // Validation
    if (scanCodeController.text.isEmpty) {
      _showErrorSnackBar('Scan code is required');
      return;
    }
    
    if (codeController.text.isEmpty ||
        nameController.text.isEmpty ||
        departmentController.text.isEmpty ||
        rateController.text.isEmpty ||
        quantityController.text.isEmpty) {
      _showErrorSnackBar('Please fill all fields');
      return;
    }
    
    // NEW: Validate against previous stock
    final inputScanCode = scanCodeController.text.trim();
    if (!previousStock.containsKey(inputScanCode)) {
      _showErrorSnackBar('Item not found in previous stock. Please verify scan code.');
      return;
    }
    
    try {
      // Create stock item for local tracking
      final stockItem = StockItem(
        scanCode: scanCodeController.text,
        code: codeController.text,
        name: nameController.text,
        department: departmentController.text,
        rate: double.parse(rateController.text),
        quantity: int.parse(quantityController.text),
      );
      
      // Create scanned item for API
      final scannedItem = ScannedItem(
        code: codeController.text,
        department: departmentController.text,
        name: nameController.text,
        qty: quantityController.text,
        rate: double.parse(rateController.text),
        source: isScanning ? 'scanner' : 'manual',
        scanCode: scanCodeController.text,
      );
      
      setState(() {
        currentStock[stockItem.scanCode!] = stockItem;
        if (!departments.contains(stockItem.department)) {
          departments.add(stockItem.department);
        }
      });
      
      // Add to buffer and sync
      _addToBufferAndSync(scannedItem);
      
      clearForm();
      
      Future.delayed(Duration(milliseconds: 100), () {
        if (mounted) {
          scanCodeFocusNode.requestFocus();
        }
      });
      
      _showSuccessSnackBar('Item added! (${_unsavedBuffer.length}/$BUFFER_SIZE pending sync)');
      
    } catch (e) {
      _showErrorSnackBar('Error: ${e.toString()}');
    }
  }

  // void _onScanCodeChanged() {
  //   final inputCode = scanCodeController.text.trim();
  //   if (inputCode.isNotEmpty) {
  //     // Check if it matches any scan code
  //     if (previousStock.containsKey(inputCode)) {
  //       _fillFormFromStock(inputCode);
  //     }
  //   }
  // }

  void _onScanCodeChanged() {
    // Only check for recognition, don't auto-fill
    // Auto-fill will happen on field submission instead
    setState(() {}); // Just trigger rebuild to show/hide check icon
  }
  
  Future<void> loadSavedStock() async {
    final prefs = await SharedPreferences.getInstance();
    final savedData = prefs.getString('current_stock_${widget.transactionId}_${widget.sectionId}');
    if (savedData != null) {
      final decoded = json.decode(savedData) as Map<String, dynamic>;
      setState(() {
        currentStock = decoded.map((key, value) => 
          MapEntry(key, StockItem.fromJson(value)));
        lastUpdated = DateTime.now();
      });
    }
  }
  
  Future<void> saveStock() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = currentStock.map((key, value) => 
      MapEntry(key, value.toJson()));
    await prefs.setString(
      'current_stock_${widget.transactionId}_${widget.sectionId}',
      json.encode(encoded)
    );
    setState(() {
      lastUpdated = DateTime.now();
    });
  }

  Future<void> uploadExcel() async {
    setState(() {
      isUploading = true;
      uploadProgress = 0.0;
    });

    try {
      // Update progress
      setState(() {
        uploadProgress = 0.1;
      });

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: false,
        withData: true, // Important for mobile - ensures bytes are loaded
      );
      
      setState(() {
        uploadProgress = 0.3;
      });
      
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        
        // Check if file has bytes (important for mobile)
        if (file.bytes == null) {
          throw Exception('File could not be read. Please try selecting the file again.');
        }

        setState(() {
          uploadProgress = 0.5;
        });

        var excel = Excel.decodeBytes(file.bytes!);
        
        setState(() {
          uploadProgress = 0.7;
        });
        
        // Clear previous stock before loading new data
        previousStock.clear();
        departments.clear();
        
        int itemsProcessed = 0;
        int totalItems = 0;
        
        // Count total items first for accurate progress
        for (var table in excel.tables.keys) {
          var sheet = excel.tables[table];
          if (sheet != null) {
            totalItems += sheet.maxRows - 1; // Subtract header row
          }
        }
        
        for (var table in excel.tables.keys) {
          var sheet = excel.tables[table];
          if (sheet != null && sheet.maxRows > 1) {
            // Skip header row (index 0), start from index 1
            for (int i = 1; i < sheet.maxRows; i++) {
              var row = sheet.row(i);
              
              // Check if row has enough columns and data
              if (row.length >= 6) {
                // Excel structure: Scan Code, Item Description, Item Code, Department, Rate, Qty
                final scanCodeCell = row[0];
                final itemDescriptionCell = row[1];
                final itemCodeCell = row[2];
                final departmentCell = row[3];
                final priceGroupCell = row[4];
                final quantityCell = row[5];
                
                // Extract values with null safety and proper type handling
                String scanCode = '';
                String itemDescription = '';
                String itemCode = '';
                String department = '';
                
                // Safe string extraction with type checking
                if (scanCodeCell?.value != null) {
                  final value = scanCodeCell!.value;
                  if (value is TextCellValue) {
                    scanCode = value.value.toString().trim();
                  } else if (value is IntCellValue || value is DoubleCellValue) {
                    scanCode = value.toString().trim();
                  } else {
                    scanCode = value.toString().trim();
                  }
                }
                
                if (itemDescriptionCell?.value != null) {
                  final value = itemDescriptionCell!.value;
                  if (value is TextCellValue) {
                    itemDescription = value.value.toString().trim();
                  } else if (value is IntCellValue || value is DoubleCellValue) {
                    itemDescription = value.toString().trim();
                  } else {
                    itemDescription = value.toString().trim();
                  }
                }
                
                if (itemCodeCell?.value != null) {
                  final value = itemCodeCell!.value;
                  if (value is TextCellValue) {
                    itemCode = value.value.toString().trim();
                  } else if (value is IntCellValue || value is DoubleCellValue) {
                    itemCode = value.toString().trim();
                  } else {
                    itemCode = value.toString().trim();
                  }
                }
                
                if (departmentCell?.value != null) {
                  final value = departmentCell!.value;
                  if (value is TextCellValue) {
                    department = value.value.toString().trim();
                  } else if (value is IntCellValue || value is DoubleCellValue) {
                    department = value.toString().trim();
                  } else {
                    department = value.toString().trim();
                  }
                }
                
                // Handle numeric values more carefully
                double priceGroup = 0.0;
                int quantity = 0;
                
                // Handle Rate conversion
                if (priceGroupCell?.value != null) {
                  final priceValue = priceGroupCell!.value;
                  if (priceValue is IntCellValue) {
                    priceGroup = priceValue.value.toDouble();
                  } else if (priceValue is DoubleCellValue) {
                    priceGroup = priceValue.value;
                  } else if (priceValue is TextCellValue) {
                    priceGroup = double.tryParse(priceValue.value.toString()) ?? 0.0;
                  } else {
                    // Fallback for any other type
                    priceGroup = double.tryParse(priceValue.toString()) ?? 0.0;
                  }
                }
                
                // Handle quantity conversion
                if (quantityCell?.value != null) {
                  final qtyValue = quantityCell!.value;
                  if (qtyValue is IntCellValue) {
                    quantity = qtyValue.value;
                  } else if (qtyValue is DoubleCellValue) {
                    quantity = qtyValue.value.toInt();
                  } else if (qtyValue is TextCellValue) {
                    quantity = int.tryParse(qtyValue.value.toString()) ?? 0;
                  } else {
                    // Fallback for any other type
                    quantity = int.tryParse(qtyValue.toString()) ?? 0;
                  }
                }
                
                // Only process items that belong to the allocated section and have valid data
                if (scanCode.isNotEmpty && itemCode.isNotEmpty) {
                  
                  // Store with scanCode as key
                  previousStock[scanCode] = StockItem(
                    scanCode: scanCode,
                    code: itemCode,
                    name: itemDescription,
                    department: department,
                    rate: priceGroup,
                    quantity: quantity,
                  );
                  
                  if (!departments.contains(department)) {
                    departments.add(department);
                  }
                }
              }
              
              itemsProcessed++;
              // Update progress during processing
              if (itemsProcessed % 10 == 0) {
                setState(() {
                  uploadProgress = 0.7 + (0.2 * (itemsProcessed / totalItems));
                });
                // Allow UI to update
                await Future.delayed(Duration(milliseconds: 1));
              }
            }
          }
        }
        
        setState(() {
          uploadProgress = 1.0;
          uploadedFileName = file.name;
          currentStep = 1;
        });
        
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Excel file uploaded successfully! ${previousStock.length} items loaded.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
        
      } else {
        throw Exception('No file selected or file is empty.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading file: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isUploading = false;
          uploadProgress = 0.0;
        });
      }
    }
  }
  
void handleBarcodeScan(String barcode) {
  //print('Scanned barcode: $barcode'); // Debug print
  
  // Stop scanning immediately after successful scan
  setState(() {
    scanCodeController.text = barcode;
    isScanning = false;
  });
  
  if (previousStock.containsKey(barcode)) {
    _fillFormFromStock(barcode);
  } else {
    setState(() {
      codeController.clear();
      nameController.clear();
      departmentController.clear();
      rateController.clear();
      quantityController.clear();
    });
    
    // Focus on code field for new items
    Future.delayed(Duration(milliseconds: 100), () {
      codeFocusNode.requestFocus();
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('New item detected. Please enter details.'),
        backgroundColor: Colors.orange,
      ),
    );
  }
}
  
  // void addOrUpdateStock() {
  //   if (scanCodeController.text.isNotEmpty && 
  //       codeController.text.isNotEmpty &&
  //       nameController.text.isNotEmpty &&
  //       departmentController.text.isNotEmpty &&
  //       rateController.text.isNotEmpty &&
  //       quantityController.text.isNotEmpty) {
      
  //     final item = StockItem(
  //       scanCode: scanCodeController.text,
  //       code: codeController.text,
  //       name: nameController.text,
  //       department: departmentController.text,
  //       rate: double.parse(rateController.text),
  //       quantity: int.parse(quantityController.text),
  //     );
      
  //     setState(() {
  //       // Use scan code as key for current stock
  //       currentStock[item.scanCode!] = item;
  //       if (!departments.contains(item.department)) {
  //         departments.add(item.department);
  //       }
  //     });
      
  //     saveStock();
  //     clearForm();
      
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text('Stock item added/updated!'),
  //         backgroundColor: Colors.green,
  //       ),
  //     );
  //   } else {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text('Please fill all fields'),
  //         backgroundColor: Colors.red,
  //       ),
  //     );
  //   }
  // }


  // void addOrUpdateStock() {
  //   if (scanCodeController.text.isNotEmpty && 
  //       codeController.text.isNotEmpty &&
  //       nameController.text.isNotEmpty &&
  //       departmentController.text.isNotEmpty &&
  //       rateController.text.isNotEmpty &&
  //       quantityController.text.isNotEmpty) {
      
  //     final item = StockItem(
  //       scanCode: scanCodeController.text,
  //       code: codeController.text,
  //       name: nameController.text,
  //       department: departmentController.text,
  //       rate: double.parse(rateController.text),
  //       quantity: int.parse(quantityController.text),
  //     );
      
  //     setState(() {
  //       currentStock[item.scanCode!] = item;
  //       if (!departments.contains(item.department)) {
  //         departments.add(item.department);
  //       }
  //     });
      
  //     saveStock();
  //     clearForm();
      
  //     // ✅ Focus on scan code field after adding/updating
  //     Future.delayed(Duration(milliseconds: 100), () {
  //       if (mounted) {
  //         scanCodeFocusNode.requestFocus();
  //       }
  //     });
      
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text('Stock item added/updated!'),
  //         backgroundColor: Colors.green,
  //       ),
  //     );
  //   } else {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text('Please fill all fields'),
  //         backgroundColor: Colors.red,
  //       ),
  //     );
  //   }
  // }
  
  void clearForm() {
    scanCodeController.clear();
    codeController.clear();
    nameController.clear();
    departmentController.clear();
    rateController.clear();
    quantityController.clear();
    
    // Reset scanner state
    if (isScanning) {
      setState(() {
        isScanning = false;
      });
      // Small delay to ensure scanner stops, then restart if needed
      Future.delayed(Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            isScanning = true;
          });
        }
      });
    }
  }

  void restartScanner() {
    if (isScanning) {
      setState(() {
        isScanning = false;
      });
      
      Future.delayed(Duration(milliseconds: 200), () {
        if (mounted) {
          setState(() {
            isScanning = true;
          });
        }
      });
    }
  }

  void _fillFormFromStock(String scanCode) {
    if (previousStock.containsKey(scanCode)) {
      final foundItem = previousStock[scanCode]!;
      
      setState(() {
        scanCodeController.text = foundItem.scanCode ?? scanCode;
        codeController.text = foundItem.code;
        nameController.text = foundItem.name;
        departmentController.text = foundItem.department;
        rateController.text = foundItem.rate.toString();
        quantityController.clear(); // Clear quantity for new entry
      });
      
      // Focus on quantity field after autofill
      Future.delayed(Duration(milliseconds: 100), () {
        quantityFocusNode.requestFocus();
      });
      
      // Show success feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Item loaded: ${foundItem.name} (Code: ${foundItem.code})'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
  
  Widget _buildStockEntryForm() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          // Scanner option
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Barcode Scanner',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      // IconButton(
                      //   onPressed: () => setState(() => isScanning = !isScanning),
                      //   icon: Icon(
                      //     isScanning ? FontAwesomeIcons.stop : FontAwesomeIcons.barcode,
                      //     color: Colors.deepPurple,
                      //   ),
                      // ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            isScanning = !isScanning;
                          });
                          // If we're starting to scan, ensure the scanner is fresh
                          if (isScanning) {
                            // Restart the scanner controller
                            scannerController.dispose();
                            scannerController = MobileScannerController();
                          }
                        },
                        icon: Icon(
                          isScanning ? FontAwesomeIcons.stop : FontAwesomeIcons.barcode,
                          color: const Color.fromARGB(255, 3, 25, 55),
                        ),
                      ),
                    ],
                  ),
                  if (isScanning) ...[
                    SizedBox(height: 16),
                    Container(
                      height: 250, // Increased height
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color.fromARGB(255, 3, 25, 55)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          children: [
                            MobileScanner(
                              controller: scannerController,
                              onDetect: (capture) {
                                final List<Barcode> barcodes = capture.barcodes;
                                for (final barcode in barcodes) {
                                  if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
                                    //print('Scanned barcode: ${barcode.rawValue}'); // Debug print
                                    handleBarcodeScan(barcode.rawValue!);
                                    break;
                                  }
                                }
                              },
                            ),
                            // Overlay with scanning guidelines
                            Center(
                              child: Container(
                                width: 200,
                                height: 100,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.red, width: 2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            // Controls overlay
                            Positioned(
                              bottom: 10,
                              left: 10,
                              right: 10,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: IconButton(
                                      icon: Icon(Icons.flash_on, color: Colors.white),
                                      onPressed: () => scannerController.toggleTorch(),
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: IconButton(
                                      icon: Icon(Icons.flip_camera_ios, color: Colors.white),
                                      onPressed: () => scannerController.switchCamera(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Position the barcode within the red frame',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          SizedBox(height: 16),
          
          // Manual entry form
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stock Entry Form',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  
                  // Scan Code field
                  // TextFormField(
                  //   controller: scanCodeController,
                  //   focusNode: scanCodeFocusNode,
                  //   decoration: InputDecoration(
                  //     labelText: 'Scan Code',
                  //     prefixIcon: FaFaIcon(FontAwesomeIcons.barcode, size: 16),
                  //     border: OutlineInputBorder(),
                  //     suffixIcon: _isCodeRecognized(scanCodeController.text) 
                  //       ? Icon(Icons.check_circle, color: Colors.green)
                  //       : null,
                  //     helperText: 'Enter or scan the barcode',
                  //   ),
                  //   onFieldSubmitted: (value) {
                  //     if (value.isNotEmpty) {
                  //       if (_isCodeRecognized(value)) {
                  //         quantityFocusNode.requestFocus();
                  //       } else {
                  //         codeFocusNode.requestFocus();
                  //       }
                  //     }
                  //   },
                  // ),
                  TextFormField(
                    controller: scanCodeController,
                    focusNode: scanCodeFocusNode,
                    decoration: InputDecoration(
                      labelText: 'Scan Code',
                      prefixIcon: FaIcon(FontAwesomeIcons.barcode, size: 16),
                      border: OutlineInputBorder(),
                      suffixIcon: _isCodeRecognized(scanCodeController.text) 
                        ? Icon(Icons.check_circle, color: Colors.green)
                        : null,
                      helperText: 'Enter or scan the barcode',
                    ),
                    onFieldSubmitted: (value) {
                      if (value.isNotEmpty) {
                        if (_isCodeRecognized(value)) {
                          _fillFormFromStock(value);  // ✅ Fill form when user submits (presses Enter)
                          quantityFocusNode.requestFocus();
                        } else {
                          codeFocusNode.requestFocus();
                        }
                      }
                    },
                  ),
                  SizedBox(height: 12),
                  
                  // Item Code field
                  TextFormField(
                    controller: codeController,
                    focusNode: codeFocusNode,
                    decoration: InputDecoration(
                      labelText: 'Item Code',
                      prefixIcon: FaIcon(FontAwesomeIcons.hashtag, size: 16),
                      border: OutlineInputBorder(),
                    ),
                    onFieldSubmitted: (value) => nameFocusNode.requestFocus(),
                  ),
                  SizedBox(height: 12),
                  
                  // Name field
                  TextFormField(
                    controller: nameController,
                    focusNode: nameFocusNode,
                    decoration: InputDecoration(
                      labelText: 'Item Description',
                      prefixIcon: FaIcon(FontAwesomeIcons.tag, size: 16),
                      border: OutlineInputBorder(),
                    ),
                    onFieldSubmitted: (value) => departmentFocusNode.requestFocus(),
                  ),
                  SizedBox(height: 12),
                  
                  // Department field
                  TextFormField(
                    controller: departmentController,
                    focusNode: departmentFocusNode,
                    decoration: InputDecoration(
                      labelText: 'Department',
                      prefixIcon: FaIcon(FontAwesomeIcons.building, size: 16),
                      border: OutlineInputBorder(),
                    ),
                    onFieldSubmitted: (value) => rateFocusNode.requestFocus(),
                  ),
                  SizedBox(height: 12),
                  
                  // Rate field
                  TextFormField(
                    controller: rateController,
                    focusNode: rateFocusNode,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Rate',
                      prefixIcon: FaIcon(FontAwesomeIcons.dollarSign, size: 16),
                      border: OutlineInputBorder(),
                    ),
                    onFieldSubmitted: (value) => quantityFocusNode.requestFocus(),
                  ),
                  SizedBox(height: 12),
                  
                  // Quantity field
                  TextFormField(
                    controller: quantityController,
                    focusNode: quantityFocusNode,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Current Quantity *',
                      prefixIcon: FaIcon(FontAwesomeIcons.boxesStacked, size: 16),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: quantityFocusNode.hasFocus ? Colors.orange : Colors.grey,
                          width: quantityFocusNode.hasFocus ? 2 : 1,
                        ),
                      ),
                      helperText: 'Enter current stock quantity',
                      fillColor: quantityFocusNode.hasFocus ? Colors.white : null,
                      filled: quantityFocusNode.hasFocus,
                    ),
                    onFieldSubmitted: (value) {
                      if (value.isNotEmpty) {
                        addOrUpdateStock();
                      }
                    },
                  ),
                  SizedBox(height: 16),
                  
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: addOrUpdateStock,
                          icon: FaIcon(FontAwesomeIcons.plus, size: 16),
                          label: Text('Add/Update'),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.green,
                            padding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      // ElevatedButton.icon(
                      //   onPressed: () {
                      //     clearForm();
                      //     scanCodeFocusNode.requestFocus();
                      //   },
                      //   icon: FaIcon(FontAwesomeIcons.eraser, size: 16),
                      //   label: Text('Clear'),
                      //   style: ElevatedButton.styleFrom(
                      //     backgroundColor: Colors.orange,
                      //     padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      //   ),
                      // ),
                      ElevatedButton.icon(
                        onPressed: () {
                          clearForm();
                          restartScanner(); // Add this line
                          scanCodeFocusNode.requestFocus();
                        },
                        icon: FaIcon(FontAwesomeIcons.eraser, size: 16),
                        label: Text('Clear'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.orange,
                          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                  
                  // Quick tips
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color.fromARGB(255, 3, 25, 55)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick Tips:',
                          style: TextStyle(fontWeight: FontWeight.bold, color: const Color.fromARGB(255, 3, 25, 55)),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '• Scan barcode or type scan code manually\n'
                          '• Details auto-fill for existing items\n'
                          '• Press Enter to move between fields\n'
                          '• Focus automatically moves to quantity for known items            ',
                          style: TextStyle(fontSize: 12, color: const Color.fromARGB(255, 3, 25, 55)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Current stock list
          if (currentStock.isNotEmpty) ...[
            SizedBox(height: 16),
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Stock (${currentStock.length} items)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 12),
                    Container(
                      height: 200,
                      child: ListView.builder(
                        itemCount: currentStock.length,
                        itemBuilder: (context, index) {
                          final entry = currentStock.entries.toList()[index];
                          final item = entry.value;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color.fromARGB(255, 3, 25, 55),
                              child: Text(item.code.isNotEmpty ? item.code[0] : 'X'),
                            ),
                            title: Text(item.name),
                            subtitle: Text('Code: ${item.code} | Scan: ${item.scanCode}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('Qty: ${item.quantity}', style: TextStyle(fontWeight: FontWeight.bold)),
                                    Text('@ \$${item.rate}', style: TextStyle(fontSize: 12)),
                                  ],
                                ),
                                IconButton(
                                  icon: FaIcon(FontAwesomeIcons.trash, size: 16, color: Colors.red),
                                  onPressed: () {
                                    setState(() {
                                      currentStock.remove(entry.key);
                                    });
                                    saveStock();
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Map<String, DepartmentSummary> getDepartmentSummary() {
    Map<String, DepartmentSummary> summary = {};
    
    // Previous stock summary
    previousStock.forEach((key, item) {
      if (!summary.containsKey(item.department)) {
        summary[item.department] = DepartmentSummary();
      }
      summary[item.department]!.previousTotal += item.rate * item.quantity;
    });
    
    // Current stock summary
    currentStock.forEach((key, item) {
      if (!summary.containsKey(item.department)) {
        summary[item.department] = DepartmentSummary();
      }
      summary[item.department]!.currentTotal += item.rate * item.quantity;
      
      if (!previousStock.containsKey(key)) {
        summary[item.department]!.addedTotal += item.rate * item.quantity;
      } else if (previousStock[key]!.quantity != item.quantity) {
        final diff = (item.quantity - previousStock[key]!.quantity) * item.rate;
        if (diff > 0) {
          summary[item.department]!.addedTotal += diff;
        } else {
          summary[item.department]!.removedTotal += diff.abs();
        }
      }
    });
    
    // Removed items
    previousStock.forEach((key, item) {
      if (!currentStock.containsKey(key)) {
        if (!summary.containsKey(item.department)) {
          summary[item.department] = DepartmentSummary();
        }
        summary[item.department]!.removedTotal += item.rate * item.quantity;
      }
    });
    
    return summary;
  }

  bool _isCodeRecognized(String inputCode) {
    return previousStock.containsKey(inputCode);
  }
  
  Future<void> generatePDFReport() async {
    final pdf = pw.Document();
    final summary = getDepartmentSummary();
    
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Stock Report - ${widget.companyName}',
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                style: pw.TextStyle(fontSize: 12),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                'Department Summary',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: pw.EdgeInsets.all(5),
                        child: pw.Text('Department', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: pw.EdgeInsets.all(5),
                        child: pw.Text('Previous', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: pw.EdgeInsets.all(5),
                        child: pw.Text('Added', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: pw.EdgeInsets.all(5),
                        child: pw.Text('Removed', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: pw.EdgeInsets.all(5),
                        child: pw.Text('Current', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                    ],
                  ),
                  ...summary.entries.map((entry) => pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: pw.EdgeInsets.all(5),
                        child: pw.Text(entry.key),
                      ),
                      pw.Padding(
                        padding: pw.EdgeInsets.all(5),
                        child: pw.Text('${entry.value.previousTotal.toStringAsFixed(2)}'),
                      ),
                      pw.Padding(
                        padding: pw.EdgeInsets.all(5),
                        child: pw.Text('${entry.value.addedTotal.toStringAsFixed(2)}'),
                      ),
                      pw.Padding(
                        padding: pw.EdgeInsets.all(5),
                        child: pw.Text('${entry.value.removedTotal.toStringAsFixed(2)}'),
                      ),
                      pw.Padding(
                        padding: pw.EdgeInsets.all(5),
                        child: pw.Text('${entry.value.currentTotal.toStringAsFixed(2)}'),
                      ),
                    ],
                  )),
                ],
              ),
            ],
          );
        },
      ),
    );
    
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  Future<void> generateExcelReport() async {
    try {
      setState(() => isUploading = true);
      
      // Create Excel workbook
      var excel = Excel.createExcel();
      
      // Remove default sheet
      excel.delete('Sheet1');
      
      // Generate all reports
      await _createInvReportDetailed(excel);
      await _createInvReportSummary(excel);
      await _createConsolidationReport(excel);
      await _createTotalStockList(excel);
      await _createInvReportVisual(excel);
      
      // Save Excel file
      var fileBytes = excel.save();
      
      if (fileBytes != null) {
        // Format: COMPANYNAME_SECTIONNAME_DATE.xlsx
        final fileName = '${widget.companyName.replaceAll(' ', '_')}_${widget.sectionName.replaceAll(' ', '_')}_${DateFormat('MMddyyyy').format(DateTime.now())}.xlsx';
        
        // For mobile - save and share
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(fileBytes);
        
        setState(() => isUploading = false);
        
        // Share the file
        await Share.shareXFiles([XFile(file.path)], text: 'Stock Report - ${widget.companyName}');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Excel report generated successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() => isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating report: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  // Sheet 1: INV REPORT (Detailed)
  Future<void> _createInvReportDetailed(Excel excel) async {
    var sheet = excel['INV REPORT'];
    
    // Headers
    var headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.grey200,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('DEPARTMENT');
    sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue('SCAN CODE');
    sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('COUNT');
    sheet.cell(CellIndex.indexByString('D1')).value = TextCellValue('ITEM DISCRIPTION');
    sheet.cell(CellIndex.indexByString('E1')).value = TextCellValue('Unit Retail');
    sheet.cell(CellIndex.indexByString('F1')).value = TextCellValue('AMOUNT');
    
    for (var col in ['A1', 'B1', 'C1', 'D1', 'E1', 'F1']) {
      sheet.cell(CellIndex.indexByString(col)).cellStyle = headerStyle;
    }
    
    // Set column widths
    sheet.setColumnWidth(0, 15);// Department
    sheet.setColumnWidth(1, 20); // Scan Code
    sheet.setColumnWidth(2, 10); // Count
    sheet.setColumnWidth(3, 40); // Description
    sheet.setColumnWidth(4, 12); // Rate
    sheet.setColumnWidth(5, 15); // Amount
    
    // Sort current stock by department
    var sortedStock = currentStock.values.toList()
      ..sort((a, b) {
        int deptCompare = a.department.compareTo(b.department);
        if (deptCompare != 0) return deptCompare;
        return a.name.compareTo(b.name);
      });
    
    int row = 2;
    for (var item in sortedStock) {
      sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(item.department);
      sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(item.scanCode ?? '');
      sheet.cell(CellIndex.indexByString('C$row')).value = IntCellValue(item.quantity);
      sheet.cell(CellIndex.indexByString('D$row')).value = TextCellValue(item.name);
      sheet.cell(CellIndex.indexByString('E$row')).value = DoubleCellValue(item.rate);
      sheet.cell(CellIndex.indexByString('F$row')).value = DoubleCellValue(item.rate * item.quantity);
      row++;
    }
  }

  // Sheet 2: INV REPORT (Summary)
  Future<void> _createInvReportSummary(Excel excel) async {
    var sheet = excel['INV REPORT SUMMARY'];
    
    // Title
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('D1'));
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue(widget.companyName.toUpperCase());
    sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
      bold: true,
      fontSize: 16,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    // Date
    sheet.merge(CellIndex.indexByString('A2'), CellIndex.indexByString('D2'));
    sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue(DateFormat('MM-dd-yyyy').format(DateTime.now()));
    sheet.cell(CellIndex.indexByString('A2')).cellStyle = CellStyle(
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    // Headers
    var headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.grey200,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue('DEPARTMENT');
    sheet.cell(CellIndex.indexByString('B3')).value = TextCellValue('CURRENT DOLLARS');
    sheet.cell(CellIndex.indexByString('C3')).value = TextCellValue('PREVIOUS DOLLARS');
    sheet.cell(CellIndex.indexByString('D3')).value = TextCellValue('DIFFERENCE');
    
    for (var col in ['A3', 'B3', 'C3', 'D3']) {
      sheet.cell(CellIndex.indexByString(col)).cellStyle = headerStyle;
    }
    
    // Set column widths
    sheet.setColumnWidth(0, 20);
    sheet.setColumnWidth(1, 18);
    sheet.setColumnWidth(2, 18);
    sheet.setColumnWidth(3, 18);
    
    // Calculate department summaries
    var summary = getDepartmentSummary();
    
    int row = 4;
    double totalCurrent = 0;
    double totalPrevious = 0;
    
    var sortedSummary = summary.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    
    for (var entry in sortedSummary) {
      sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(entry.key);
      sheet.cell(CellIndex.indexByString('B$row')).value = DoubleCellValue(entry.value.currentTotal);
      sheet.cell(CellIndex.indexByString('C$row')).value = DoubleCellValue(entry.value.previousTotal);
      
      double difference = entry.value.currentTotal - entry.value.previousTotal;
      sheet.cell(CellIndex.indexByString('D$row')).value = DoubleCellValue(difference);
      
      totalCurrent += entry.value.currentTotal;
      totalPrevious += entry.value.previousTotal;
      row++;
    }
    
    // Total row
    var totalStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.grey200,
    );
    
    sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue('TOTAL');
    sheet.cell(CellIndex.indexByString('B$row')).value = DoubleCellValue(totalCurrent);
    sheet.cell(CellIndex.indexByString('C$row')).value = DoubleCellValue(totalPrevious);
    sheet.cell(CellIndex.indexByString('D$row')).value = DoubleCellValue(totalCurrent - totalPrevious);
    
    for (var col in ['A$row', 'B$row', 'C$row', 'D$row']) {
      sheet.cell(CellIndex.indexByString(col)).cellStyle = totalStyle;
    }
    
    // Add prepared by footer
    row += 2;
    sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue('PREPARED BY ${widget.contactPerson}');
    sheet.cell(CellIndex.indexByString('A$row')).cellStyle = CellStyle(italic: true);
  }

  // Sheet 3: CONSOLIDATION REPORT
  Future<void> _createConsolidationReport(Excel excel) async {
    var sheet = excel['CONSOLIDATION'];
    
    // Title
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('G1'));
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('CONSOLIDATION REPORT');
    sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
      bold: true,
      fontSize: 14,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    // Headers
    var headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.grey200,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue('SECTION');
    sheet.cell(CellIndex.indexByString('B2')).value = TextCellValue('CODE');
    sheet.cell(CellIndex.indexByString('C2')).value = TextCellValue('DEPARTMENT');
    sheet.cell(CellIndex.indexByString('D2')).value = TextCellValue('ITEM NAME');
    sheet.cell(CellIndex.indexByString('E2')).value = TextCellValue('RATE');
    sheet.cell(CellIndex.indexByString('F2')).value = TextCellValue('QTY');
    sheet.cell(CellIndex.indexByString('G2')).value = TextCellValue('AMOUNT');
    
    for (var col in ['A2', 'B2', 'C2', 'D2', 'E2', 'F2', 'G2']) {
      sheet.cell(CellIndex.indexByString(col)).cellStyle = headerStyle;
    }
    
    // Set column widths
    sheet.setColumnWidth(0, 15); // Section
    sheet.setColumnWidth(1, 18); // Code
    sheet.setColumnWidth(2, 18); // Department
    sheet.setColumnWidth(3, 40); // Item Name
    sheet.setColumnWidth(4, 12); // Rate
    sheet.setColumnWidth(5, 10); // Qty
    sheet.setColumnWidth(6, 15); // Amount
    
    // Data rows
    var sortedStock = currentStock.values.toList()
      ..sort((a, b) {
        int deptCompare = a.department.compareTo(b.department);
        if (deptCompare != 0) return deptCompare;
        return a.name.compareTo(b.name);
      });
    
    int row = 3;
    for (var item in sortedStock) {
      sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(widget.sectionName);
      sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(item.code);
      sheet.cell(CellIndex.indexByString('C$row')).value = TextCellValue(item.department);
      sheet.cell(CellIndex.indexByString('D$row')).value = TextCellValue(item.name);
      sheet.cell(CellIndex.indexByString('E$row')).value = DoubleCellValue(item.rate);
      sheet.cell(CellIndex.indexByString('F$row')).value = DoubleCellValue(item.quantity.toDouble());
      sheet.cell(CellIndex.indexByString('G$row')).value = DoubleCellValue(item.rate * item.quantity);
      row++;
    }
  }

  // Sheet 4: TOTAL STOCK LIST
  Future<void> _createTotalStockList(Excel excel) async {
    var sheet = excel['TOTAL STOCK'];
    
    // Title
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('C1'));
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('TOTAL STOCK LIST');
    sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
      bold: true,
      fontSize: 14,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    // Headers
    var headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.grey200,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue('DEPARTMENT');
    sheet.cell(CellIndex.indexByString('B3')).value = TextCellValue('CODE');
    sheet.cell(CellIndex.indexByString('C3')).value = TextCellValue('TOTAL QTY');
    
    for (var col in ['A3', 'B3', 'C3']) {
      sheet.cell(CellIndex.indexByString(col)).cellStyle = headerStyle;
    }
    
    // Set column widths
    sheet.setColumnWidth(0, 20);
    sheet.setColumnWidth(1, 20);
    sheet.setColumnWidth(2, 15);
    
    // Data rows
    var sortedStock = currentStock.values.toList()
      ..sort((a, b) {
        int deptCompare = a.department.compareTo(b.department);
        if (deptCompare != 0) return deptCompare;
        return a.code.compareTo(b.code);
      });
    
    int row = 4;
    for (var item in sortedStock) {
      sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(item.department);
      sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(item.code);
      sheet.cell(CellIndex.indexByString('C$row')).value = DoubleCellValue(item.quantity.toDouble());
      row++;
    }
  }

  // Sheet 5: INV REPORT VISUAL (Layout-based summary)
  Future<void> _createInvReportVisual(Excel excel) async {
    var sheet = excel['INV REPORT VISUAL'];
    
    // Title
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('E1'));
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('INVENTORY VISUAL SUMMARY');
    sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
      bold: true,
      fontSize: 14,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    // Headers
    var headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.grey200,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue('Section');
    sheet.cell(CellIndex.indexByString('B3')).value = TextCellValue('Department');
    sheet.cell(CellIndex.indexByString('C3')).value = TextCellValue('Item Count');
    sheet.cell(CellIndex.indexByString('D3')).value = TextCellValue('Total Quantity');
    sheet.cell(CellIndex.indexByString('E3')).value = TextCellValue('Total Value');
    
    for (var col in ['A3', 'B3', 'C3', 'D3', 'E3']) {
      sheet.cell(CellIndex.indexByString(col)).cellStyle = headerStyle;
    }
    
    // Set column widths
    sheet.setColumnWidth(0, 20);
    sheet.setColumnWidth(1, 20);
    sheet.setColumnWidth(2, 15);
    sheet.setColumnWidth(3, 15);
    sheet.setColumnWidth(4, 18);
    
    // Calculate summary by department
    var summary = getDepartmentSummary();
    
    int row = 4;
    double grandTotal = 0;
    int totalItems = 0;
    int totalQty = 0;
    
    var sortedSummary = summary.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    
    for (var entry in sortedSummary) {
      // Count items in this department
      int itemCount = currentStock.values.where((item) => item.department == entry.key).length;
      int deptQty = currentStock.values
          .where((item) => item.department == entry.key)
          .fold(0, (sum, item) => sum + item.quantity);
      
      sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(widget.sectionName);
      sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(entry.key);
      sheet.cell(CellIndex.indexByString('C$row')).value = IntCellValue(itemCount);
      sheet.cell(CellIndex.indexByString('D$row')).value = IntCellValue(deptQty);
      sheet.cell(CellIndex.indexByString('E$row')).value = DoubleCellValue(entry.value.currentTotal);
      
      grandTotal += entry.value.currentTotal;
      totalItems += itemCount;
      totalQty += deptQty;
      row++;
    }
    
    // Total row
    var totalStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.grey200,
    );
    
  sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue('TOTAL');
  sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue('');
  sheet.cell(CellIndex.indexByString('C$row')).value = IntCellValue(totalItems);
  sheet.cell(CellIndex.indexByString('D$row')).value = IntCellValue(totalQty);
  sheet.cell(CellIndex.indexByString('E$row')).value = DoubleCellValue(grandTotal);
  
  for (var col in ['A$row', 'B$row', 'C$row', 'D$row', 'E$row']) {
    sheet.cell(CellIndex.indexByString(col)).cellStyle = totalStyle;
  }
}
  
  Future<void> _finishSection() async {
    try {
      // First, sync any pending items
      if (_unsavedBuffer.isNotEmpty) {
        await _syncToServer();
      }

      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 12),
              Text('Finish Section?'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Are you sure you want to mark "${widget.sectionName}" as completed?'),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This section will be locked and you won\'t be able to scan more items.',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Finish Section'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      setState(() => isUploading = true);

      // Call API to mark section as completed
      final url = '${AppConfig.baseUrl}transactions/${widget.transactionId}/sections/${widget.sectionId}/complete';
      
      final payload = {
        'status': 'completed',
        'completedAt': DateTime.now().toIso8601String(),
        'completedBy': widget.contactPerson, // Or user ID if available
      };

      final result = await _apiService.putRequest(url, payload);

      setState(() => isUploading = false);

      if (result != null) {
        // Show success dialog
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 32),
                SizedBox(width: 12),
                Text('Section Completed!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '"${widget.sectionName}" has been marked as completed.',
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.inventory_2, color: Colors.green.shade700, size: 48),
                      SizedBox(height: 8),
                      Text(
                        '${currentStock.length} items scanned',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  //Navigator.pop(context, true); // Go back to transaction screen
                  Navigator.pop(context, {'sectionCompleted': true, 'sectionId': widget.sectionId}); 
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 3, 25, 55),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text('Back to Transaction'),
              ),
            ],
          ),
        );
      } else {
        throw Exception('Failed to mark section as completed');
      }
    } catch (e) {
      setState(() => isUploading = false);
      _showErrorSnackBar('Failed to finish section: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   title: Text('Stock Management - ${widget.companyName}'),
      //   backgroundColor: const Color.fromARGB(255, 3, 25, 55),
      //   foregroundColor: Colors.white,
      //   elevation: 0,
      //   actions: [
      //     if (lastUpdated != null)
      //       Padding(
      //         padding: EdgeInsets.symmetric(horizontal: 16),
      //         child: Center(
      //           child: Text(
      //             'Last Updated: ${DateFormat('HH:mm').format(lastUpdated!)}',
      //             style: TextStyle(fontSize: 12),
      //           ),
      //         ),
      //       ),
      //   ],
      // ),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.companyName}'),
            Text(
              widget.sectionName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: const Color.fromARGB(255, 3, 25, 55),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Buffer counter
          if (_unsavedBuffer.isNotEmpty)
            Container(
              margin: EdgeInsets.only(right: 8),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _unsavedBuffer.length >= BUFFER_SIZE ? Colors.red : Colors.orange,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_upload, size: 16),
                  SizedBox(width: 4),
                  Text(
                    '${_unsavedBuffer.length}/$BUFFER_SIZE',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          // Sync button
          if (_unsavedBuffer.isNotEmpty)
            IconButton(
              icon: _isSyncing 
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Icon(Icons.sync),
              onPressed: _isSyncing ? null : _syncToServer,
              tooltip: 'Sync now',
            ),
          // Last sync time
          if (_lastSyncTime != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  'Synced: ${DateFormat('HH:mm').format(_lastSyncTime!)}',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ),
        ],
      ),
      //drawer: AppDrawer(onItemTap: setPage),
      body: Column(
        children: [
          // Step indicator
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStepIndicator(0, 'Upload', FontAwesomeIcons.upload),
                Container(width: 200, height: 1, color: Colors.grey), // thin connector line
                _buildStepIndicator(1, 'Stock Entry', FontAwesomeIcons.boxOpen),
              ],
            ),
          ),

          
          // Content
          Expanded(
            child: IndexedStack(
              index: currentStep,
              children: [
                _buildUploadStep(),
                _buildStockEntryForm(),
                // _buildComparisonStep(),
                // _buildSummaryStep(),
              ],
            ),
          ),
          
          // Navigation buttons
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade300,
                  blurRadius: 5,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (currentStep > 0)
                  ElevatedButton.icon(
                    onPressed: () => setState(() => currentStep--),
                    icon: FaIcon(FontAwesomeIcons.arrowLeft, size: 16),
                    label: Text('Back'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.grey,
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  )
                else
                  SizedBox(),
                Row(
                  children: [
                    // Show sync button if there are unsaved items
                    if (_unsavedBuffer.isNotEmpty && currentStep == 1) ...[
                      ElevatedButton.icon(
                        onPressed: _isSyncing ? null : _syncToServer,
                        icon: Icon(_isSyncing ? FontAwesomeIcons.spinner : FontAwesomeIcons.cloudArrowUp, size: 16),
                        label: Text(_isSyncing ? 'Syncing...' : 'Sync (${_unsavedBuffer.length})'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.orange,
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                      SizedBox(width: 8),
                    ],
                    
                    // CHANGE: Show Finish button in Stock Entry step (step 1)
                    if (currentStep == 1)
                      ElevatedButton.icon(
                        onPressed: isUploading ? null : _finishSection,
                        icon: Icon(isUploading ? FontAwesomeIcons.spinner : FontAwesomeIcons.checkCircle, size: 16),
                        label: Text(isUploading ? 'Finishing...' : 'Finish Section'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.green,
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      )
                    else
                      // Next button only for upload step (step 0)
                      ElevatedButton.icon(
                        onPressed: () {
                          if (currentStep == 0 && previousStock.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Please upload previous stock first')),
                            );
                          } else {
                            setState(() => currentStep++);
                          }
                        },
                        icon: FaIcon(FontAwesomeIcons.arrowRight, size: 16),
                        label: Text('Next'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: const Color.fromARGB(255, 3, 25, 55),
                          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStepIndicator(int step, String label, IconData icon) {
    final isActive = currentStep >= step;
    return GestureDetector(
      onTap: () {
        if (step <= currentStep) {
          setState(() => currentStep = step);
        }
      },
      child: Column(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: isActive ? const Color.fromARGB(255, 3, 25, 55) : Colors.grey.shade300,
            child: Icon(
              icon,
              color: Colors.white,
              size: 16,
            ),
          ),
          SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? const Color.fromARGB(255, 3, 25, 55) : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildUploadStep() {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 200,
              height: 200,
              child: SvgPicture.string(
                '''<svg viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
                  <circle cx="100" cy="100" r="80" fill="#E8E8E8"/>
                  <rect x="70" y="60" width="60" height="80" fill="#031937" rx="5"/>
                  <polyline points="85,100 100,85 115,100" stroke="white" stroke-width="3" fill="none"/>
                  <line x1="100" y1="85" x2="100" y2="120" stroke="white" stroke-width="3"/>
                </svg>''',
              ),
            ),
            SizedBox(height: 32),
            Text(
              'Upload Previous Stock',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              'Upload an Excel file with columns:\nScan Code, Item Description, Item Code, Department, Rate, Qty',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            SizedBox(height: 32),
            
            // Progress indicator
            if (isUploading) ...[
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color.fromARGB(255, 3, 25, 55)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(const Color.fromARGB(255, 3, 25, 55)),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Uploading... ${(uploadProgress * 100).toInt()}%',
                          style: TextStyle(
                            color: const Color.fromARGB(255, 3, 25, 55),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: uploadProgress,
                      backgroundColor: const Color.fromARGB(255, 3, 25, 55),
                      valueColor: AlwaysStoppedAnimation<Color>(const Color.fromARGB(255, 3, 25, 55)),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
            ],
            
            if (uploadedFileName != null && !isUploading) ...[
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FaIcon(FontAwesomeIcons.fileExcel, color: Colors.green),
                    SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        uploadedFileName!,
                        style: TextStyle(color: Colors.green.shade700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
            ],
            
            ElevatedButton.icon(
              onPressed: isUploading ? null : uploadExcel,
              icon: Icon(
                isUploading ? FontAwesomeIcons.spinner : FontAwesomeIcons.upload,
              ),
              label: Text(isUploading ? 'Uploading...' : 'Choose Excel File'),
              style: ElevatedButton.styleFrom(
                foregroundColor:Colors.white,
                backgroundColor: isUploading ? Colors.grey : const Color.fromARGB(255, 3, 25, 55),
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: TextStyle(fontSize: 16),
              ),
            ),
            
            if (previousStock.isNotEmpty && !isUploading) ...[
              SizedBox(height: 24),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Text(
                  '${previousStock.length} items loaded successfully.',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            
            // Help text for mobile users
            SizedBox(height: 24),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 3, 25, 55),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color.fromARGB(255, 3, 25, 55)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mobile Upload Tips:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• Ensure the Excel file is saved locally on your device\n'
                    '• Check that the file format is .xlsx or .xls\n'
                    '• Make sure your internet connection is stable',
                    style: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildComparisonStep() {
    final added = <String, StockItem>{};
    final updated = <String, StockItem>{};
    // final removed = <String, StockItem>{};
    
    currentStock.forEach((key, item) {
      if (!previousStock.containsKey(key)) {
        added[key] = item;
      } else if (previousStock[key]!.quantity != item.quantity) {
        updated[key] = item;
      }
    });
    
    // previousStock.forEach((key, item) {
    //   if (!currentStock.containsKey(key)) {
    //     removed[key] = item;
    //   }
    // });
    
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary cards
          Row(
            children: [
              Expanded(
                child: Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        FaIcon(FontAwesomeIcons.plus, color: Colors.green, size: 24),
                        SizedBox(height: 8),
                        Text(
                          '${added.length}',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                        Text('Added', style: TextStyle(color: Colors.green.shade700)),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Card(
                  color: const Color.fromARGB(255, 3, 25, 55),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        FaIcon(FontAwesomeIcons.arrowsRotate, color: const Color.fromARGB(255, 3, 25, 55), size: 24),
                        SizedBox(height: 8),
                        Text(
                          '${updated.length}',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: const Color.fromARGB(255, 3, 25, 55)),
                        ),
                        Text('Updated', style: TextStyle(color: const Color.fromARGB(255, 3, 25, 55))),
                      ],
                    ),
                  ),
                ),
              ),
              // SizedBox(width: 8),
              // Expanded(
              //   child: Card(
              //     color: Colors.red.shade50,
              //     child: Padding(
              //       padding: EdgeInsets.all(16),
              //       child: Column(
              //         children: [
              //           FaIcon(FontAwesomeIcons.minus, color: Colors.red, size: 24),
              //           SizedBox(height: 8),
              //           Text(
              //             '${removed.length}',
              //             style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red),
              //           ),
              //           Text('Removed', style: TextStyle(color: Colors.red.shade700)),
              //         ],
              //       ),
              //     ),
              //   ),
              // ),
            ],
          ),
          
          SizedBox(height: 16),
          
          // Detailed comparison lists
          if (added.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        FaIcon(FontAwesomeIcons.plus, color: Colors.green, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'New Items Added',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    ...added.values.map((item) => ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.green.shade100,
                        child: FaIcon(FontAwesomeIcons.plus, size: 12, color: Colors.green),
                      ),
                      title: Text(item.name),
                      subtitle: Text('Code: ${item.code} | Scan: ${item.scanCode}'),
                      trailing: Text(
                        'Qty: ${item.quantity}',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    )),
                  ],
                ),
              ),
            ),
            SizedBox(height: 12),
          ],
          
          if (updated.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        FaIcon(FontAwesomeIcons.arrowsRotate, color: const Color.fromARGB(255, 3, 25, 55), size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Updated Items',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: const Color.fromARGB(255, 3, 25, 55)),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    ...updated.entries.map((entry) {
                      final oldQty = previousStock[entry.key]!.quantity;
                      final newQty = entry.value.quantity;
                      final diff = newQty - oldQty;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color.fromARGB(255, 3, 25, 55),
                          child: FaIcon(FontAwesomeIcons.arrowsRotate, size: 12, color: const Color.fromARGB(255, 3, 25, 55)),
                        ),
                        title: Text(entry.value.name),
                        subtitle: Text('Code: ${entry.value.code} | Scan: ${entry.value.scanCode}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '$oldQty → $newQty',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${diff > 0 ? '+' : ''}$diff',
                              style: TextStyle(
                                color: diff > 0 ? Colors.green : Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            SizedBox(height: 12),
          ],
          
          // if (removed.isNotEmpty) ...[
          //   Card(
          //     child: Padding(
          //       padding: EdgeInsets.all(16),
          //       child: Column(
          //         crossAxisAlignment: CrossAxisAlignment.start,
          //         children: [
          //           Row(
          //             children: [
          //               FaIcon(FontAwesomeIcons.minus, color: Colors.red, size: 16),
          //               SizedBox(width: 8),
          //               Text(
          //                 'Removed Items',
          //                 style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
          //               ),
          //             ],
          //           ),
          //           SizedBox(height: 12),
          //           ...removed.values.map((item) => ListTile(
          //             leading: CircleAvatar(
          //               backgroundColor: Colors.red.shade100,
          //               child: FaIcon(FontAwesomeIcons.minus, size: 12, color: Colors.red),
          //             ),
          //             title: Text(item.name),
          //             subtitle: Text('Code: ${item.code} | Scan: ${item.scanCode}'),
          //             trailing: Text(
          //               'Qty: ${item.quantity}',
          //               style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
          //             ),
          //           )),
          //         ],
          //       ),
          //     ),
          //   ),
          // ],
        ],
      ),
    );
  }
  
  Widget _buildSummaryStep() {
    final summary = getDepartmentSummary();
    final maxValue = summary.values.fold(0.0, (max, item) {
      final itemMax = [item.previousTotal, item.currentTotal].reduce(math.max);
      return itemMax > max ? itemMax : max;
    });
    
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Department-wise Summary',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          //SizedBox(height: 16),
          
          // Pie Chart
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Stock Distribution',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  Container(
                    height: 300,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        sections: summary.entries.map((entry) {
                          final index = summary.keys.toList().indexOf(entry.key);
                          final total = summary.values.fold(0.0, (sum, item) => sum + item.currentTotal);
                          final percentage = (entry.value.currentTotal / total) * 100;
                          
                          return PieChartSectionData(
                            color: _getColorForIndex(index),
                            value: entry.value.currentTotal,
                            title: '${percentage.toStringAsFixed(1)}%',
                            radius: 100,
                            titleStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: summary.entries.map((entry) {
                      final index = summary.keys.toList().indexOf(entry.key);
                      return _buildLegendItem(entry.key, _getColorForIndex(index));
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          
          SizedBox(height: 16),
          
          // Data Table
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Detailed Summary Table',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: MaterialStateProperty.all(const Color.fromARGB(255, 3, 25, 55)),
                      columns: [
                        DataColumn(label: Text('Department', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Previous', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Added', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Removed', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Current', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Change %', style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                      rows: summary.entries.map((entry) {
                        final changePercent = entry.value.previousTotal > 0 
                          ? ((entry.value.currentTotal - entry.value.previousTotal) / entry.value.previousTotal) * 100
                          : 0.0;
                        
                        return DataRow(
                          cells: [
                            DataCell(Text(entry.key)),
                            DataCell(Text('${entry.value.previousTotal.toStringAsFixed(2)}')),
                            DataCell(Text(
                              '${entry.value.addedTotal.toStringAsFixed(2)}',
                              style: TextStyle(color: Colors.green),
                            )),
                            DataCell(Text(
                              '${entry.value.removedTotal.toStringAsFixed(2)}',
                              style: TextStyle(color: Colors.red),
                            )),
                            DataCell(Text(
                              '${entry.value.currentTotal.toStringAsFixed(2)}',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            )),
                            DataCell(Text(
                              '${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(1)}%',
                              style: TextStyle(
                                color: changePercent >= 0 ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            )),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12)),
      ],
    );
  }
  
  Color _getColorForIndex(int index) {
    final colors = [
      Colors.deepPurple,
      const Color.fromARGB(255, 3, 25, 55),
      Colors.green,
      Colors.orange,
      Colors.red,
      Colors.teal,
      Colors.pink,
      Colors.amber,
    ];
    return colors[index % colors.length];
  }
}

class StockItem {
  final String? scanCode;
  final String code;
  final String name;
  final String department;
  final double rate;
  final int quantity;
  
  StockItem({
    this.scanCode,
    required this.code,
    required this.name,
    required this.department,
    required this.rate,
    required this.quantity,
  });
  
  Map<String, dynamic> toJson() => {
    'scanCode': scanCode,
    'code': code,
    'name': name,
    'department': department,
    'rate': rate,
    'quantity': quantity,
  };
  
  factory StockItem.fromJson(Map<String, dynamic> json) => StockItem(
    scanCode: json['scanCode'],
    code: json['code'],
    name: json['name'],
    department: json['department'],
    rate: json['rate'],
    quantity: json['quantity'],
  );
}

class DepartmentSummary {
  double previousTotal = 0;
  double currentTotal = 0;
  double addedTotal = 0;
  double removedTotal = 0;
}


class TransactionData {
  final String companyId;
  final String transactionId;
  final String sectionId;
  final String sectionName;
  final String contactPerson;
  final List<dynamic> layout;
  final Map<String, List<ScannedItem>> scannedData;
  final Map<String, dynamic> sectionTotals;
  final String status;
  final DateTime lastSynced;
  
  TransactionData({
    required this.companyId,
    required this.transactionId,
    required this.sectionId,
    required this.sectionName,
    required this.contactPerson,
    required this.layout,
    required this.scannedData,
    required this.sectionTotals,
    this.status = 'scanning',
    DateTime? lastSynced,
  }) : lastSynced = lastSynced ?? DateTime.now();
  
  Map<String, dynamic> toJson() => {
    'companyId': companyId,
    'transactionId': transactionId,
    'sectionId': sectionId,
    'sectionName': sectionName,
    'contactPerson': contactPerson,
    'layout': layout,
    'scannedData': scannedData.map((key, value) => 
      MapEntry(key, value.map((item) => item.toJson()).toList())),
    'sectionTotals': sectionTotals,
    'status': status,
    'lastSynced': lastSynced.toIso8601String(),
  };
  
  factory TransactionData.fromJson(Map<String, dynamic> json) {
    Map<String, List<ScannedItem>> scannedDataMap = {};
    if (json['scannedData'] != null) {
      (json['scannedData'] as Map<String, dynamic>).forEach((key, value) {
        scannedDataMap[key] = (value as List)
            .map((item) => ScannedItem.fromJson(item))
            .toList();
      });
    }
    
    return TransactionData(
      companyId: json['companyId'] ?? '',
      transactionId: json['transactionId'] ?? '',
      sectionId: json['sectionId'] ?? '',
      sectionName: json['sectionName'] ?? '',
      contactPerson: json['contactPerson'] ?? '',
      layout: json['layout'] ?? [],
      scannedData: scannedDataMap,
      sectionTotals: json['sectionTotals'] ?? {},
      status: json['status'] ?? 'scanning',
      lastSynced: json['lastSynced'] != null 
          ? DateTime.parse(json['lastSynced']) 
          : DateTime.now(),
    );
  }
}

class ScannedItem {
  final String code;
  final String department;
  final String name;
  final String qty;
  final double rate;
  final String source; // 'manual' or 'scanner'
  final String? scanCode;
  
  ScannedItem({
    required this.code,
    required this.department,
    required this.name,
    required this.qty,
    required this.rate,
    this.source = 'manual',
    this.scanCode,
  });
  
  Map<String, dynamic> toJson() => {
    'code': code,
    'department': department,
    'name': name,
    'qty': qty,
    'rate': rate,
    '__source': source,
    if (scanCode != null) 'scanCode': scanCode,
  };
  
  factory ScannedItem.fromJson(Map<String, dynamic> json) => ScannedItem(
    code: json['code'] ?? '',
    department: json['department'] ?? '',
    name: json['name'] ?? '',
    qty: json['qty']?.toString() ?? '0',
    rate: (json['rate'] is num) ? (json['rate'] as num).toDouble() : 0.0,
    source: json['__source'] ?? 'manual',
    scanCode: json['scanCode'],
  );
}

class TransactionReportScreen extends StatefulWidget {
  final String transactionId;
  final String companyId;
  final String companyName;

  const TransactionReportScreen({
    Key? key,
    required this.transactionId,
    required this.companyId,
    required this.companyName,
  }) : super(key: key);

  @override
  State<TransactionReportScreen> createState() => _TransactionReportScreenState();
}

//  class _TransactionReportScreenState extends State<TransactionReportScreen> {

//   late final ApiService _apiService;
//   final DioService _dioService = DioService();
  
//   bool isLoading = false;
//   bool isGenerating = false;
//   Map<String, dynamic>? currentTransactionData;
//   Map<String, dynamic>? previousTransactionData;
  
//   @override
//   void initState() {
//     super.initState();
//     _apiService = ApiService(_dioService);
//     _fetchTransactionData();
//   }

//   Future<void> _fetchTransactionData() async {
//     try {
//       setState(() => isLoading = true);
      
//       // Fetch current transaction
//       final currentUrl = '${AppConfig.baseUrl}transactions/${widget.transactionId}';
//       final currentData = await _apiService.getRequest(currentUrl);
      
//       // Fetch previous transaction
//       final previousUrl = '${AppConfig.baseUrl}transactions?companyId=${widget.companyId}&sort=createdAt:desc&limit=2';
//       final previousList = await _apiService.getRequest(previousUrl);
      
//       Map<String, dynamic>? previousData;
//       if (previousList != null) {
//         List<dynamic> transactions = previousList is List ? previousList : (previousList['data'] ?? []);
//         // Find the transaction that's not the current one
//         for (var trans in transactions) {
//           if (trans['id']?.toString() != widget.transactionId) {
//             previousData = trans;
//             break;
//           }
//         }
//       }
      
//       setState(() {
//         currentTransactionData = currentData;
//         previousTransactionData = previousData;
//         isLoading = false;
//       });
//     } catch (e) {
//       setState(() => isLoading = false);
//       _showErrorSnackBar('Failed to load transaction data: ${e.toString()}');
//     }
//   }

//   Future<void> _generateExcelReport() async {
//     if (currentTransactionData == null) {
//       _showErrorSnackBar('No transaction data available');
//       return;
//     }

//     try {
//       setState(() => isGenerating = true);
      
//       // Create Excel workbook
//       var excel = Excel.createExcel();
//       excel.delete('Sheet1');
      
//       // Generate all sheets
//       await _createMissingItemReport(excel);
//       await _createInventoryReport(excel);
//       await _createInvReportVisual(excel);
//       await _createConsolidationReport(excel);
//       await _createTotalStockReport(excel);
      
//       // Save and share
//       var fileBytes = excel.save();
      
//       if (fileBytes != null) {
//         final fileName = '${widget.companyName.replaceAll(' ', '_')}_${DateFormat('MMddyyyy').format(DateTime.now())}.xlsx';
//         final directory = await getApplicationDocumentsDirectory();
//         final file = File('${directory.path}/$fileName');
//         await file.writeAsBytes(fileBytes);
        
//         setState(() => isGenerating = false);
        
//         await Share.shareXFiles([XFile(file.path)], text: 'Transaction Report - ${widget.companyName}');
        
//         _showSuccessSnackBar('Report generated successfully!');
//       }
//     } catch (e) {
//       setState(() => isGenerating = false);
//       _showErrorSnackBar('Error generating report: ${e.toString()}');
//     }
//   }

//   // Sheet 1: MISSING ITEM REPORT
//   Future<void> _createMissingItemReport(Excel excel) async {
//     var sheet = excel['MISSING ITEM REPORT'];
    
//     var headerStyle = CellStyle(
//       bold: true,
//       backgroundColorHex: ExcelColor.grey200,
//       horizontalAlign: HorizontalAlign.Center,
//       verticalAlign: VerticalAlign.Center,
//     );
    
//     // Headers
//     sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('DEPARTMENT');
//     sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue('SCAN CODE');
//     sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('COUNT');
//     sheet.cell(CellIndex.indexByString('D1')).value = TextCellValue('ITEM DESCRIPTION');
//     sheet.cell(CellIndex.indexByString('E1')).value = TextCellValue('Unit Retail');
//     sheet.cell(CellIndex.indexByString('F1')).value = TextCellValue('AMOUNT');
    
//     for (var col in ['A1', 'B1', 'C1', 'D1', 'E1', 'F1']) {
//       sheet.cell(CellIndex.indexByString(col)).cellStyle = headerStyle;
//     }
    
//     // Set column widths
//     sheet.setColumnWidth(0, 15);
//     sheet.setColumnWidth(1, 20);
//     sheet.setColumnWidth(2, 10);
//     sheet.setColumnWidth(3, 40);
//     sheet.setColumnWidth(4, 12);
//     sheet.setColumnWidth(5, 15);
    
//     // Collect all manually added items
//     List<Map<String, dynamic>> manualItems = [];
//     final scannedData = currentTransactionData!['scannedData'] ?? {};
    
//     scannedData.forEach((sectionName, items) {
//       if (items is List) {
//         for (var item in items) {
//           if (item['__source'] == 'manual') {
//             manualItems.add({
//               'department': item['department'] ?? '',
//               'scanCode': item['scanCode'] ?? item['code'] ?? '',
//               'name': item['name'] ?? '',
//               'rate': (item['rate'] is num) ? (item['rate'] as num).toDouble() : 0.0,
//               'qty': int.tryParse(item['qty']?.toString() ?? '0') ?? 0,
//             });
//           }
//         }
//       }
//     });
    
//     // Sort by department, then by scan code
//     manualItems.sort((a, b) {
//       int deptCompare = a['department'].toString().compareTo(b['department'].toString());
//       if (deptCompare != 0) return deptCompare;
//       return a['scanCode'].toString().compareTo(b['scanCode'].toString());
//     });
    
//     // Fill data
//     int row = 2;
//     for (var item in manualItems) {
//       sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(item['department']);
//       sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(item['scanCode']);
//       sheet.cell(CellIndex.indexByString('C$row')).value = IntCellValue(item['qty']);
//       sheet.cell(CellIndex.indexByString('D$row')).value = TextCellValue(item['name']);
//       sheet.cell(CellIndex.indexByString('E$row')).value = DoubleCellValue(item['rate']);
//       sheet.cell(CellIndex.indexByString('F$row')).value = DoubleCellValue(item['rate'] * item['qty']);
//       row++;
//     }
//   }

//   // Sheet 2: INVENTORY REPORT
//   Future<void> _createInventoryReport(Excel excel) async {
//     var sheet = excel['INV REPORT'];
    
//     // Title
//     sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('D1'));
//     sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue(widget.companyName.toUpperCase());
//     sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
//       bold: true,
//       fontSize: 16,
//       horizontalAlign: HorizontalAlign.Center,
//       verticalAlign: VerticalAlign.Center,
//     );
    
//     // Date
//     sheet.merge(CellIndex.indexByString('A2'), CellIndex.indexByString('D2'));
//     sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue(DateFormat('MM-dd-yyyy').format(DateTime.now()));
//     sheet.cell(CellIndex.indexByString('A2')).cellStyle = CellStyle(
//       horizontalAlign: HorizontalAlign.Center,
//       verticalAlign: VerticalAlign.Center,
//     );
    
//     // Headers
//     var headerStyle = CellStyle(
//       bold: true,
//       backgroundColorHex: ExcelColor.grey200,
//       horizontalAlign: HorizontalAlign.Center,
//       verticalAlign: VerticalAlign.Center,
//     );
    
//     sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue('DEPARTMENT');
//     sheet.cell(CellIndex.indexByString('B3')).value = TextCellValue('CURRENT DOLLARS');
//     sheet.cell(CellIndex.indexByString('C3')).value = TextCellValue('PREVIOUS DOLLARS');
//     sheet.cell(CellIndex.indexByString('D3')).value = TextCellValue('DIFFERENCE');
    
//     for (var col in ['A3', 'B3', 'C3', 'D3']) {
//       sheet.cell(CellIndex.indexByString(col)).cellStyle = headerStyle;
//     }
    
//     // Set column widths
//     sheet.setColumnWidth(0, 20);
//     sheet.setColumnWidth(1, 18);
//     sheet.setColumnWidth(2, 18);
//     sheet.setColumnWidth(3, 18);
    
//     // Calculate current department totals
//     Map<String, double> currentTotals = {};
//     final scannedData = currentTransactionData!['scannedData'] ?? {};
    
//     scannedData.forEach((sectionName, items) {
//       if (items is List) {
//         for (var item in items) {
//           String dept = item['department'] ?? '';
//           double rate = (item['rate'] is num) ? (item['rate'] as num).toDouble() : 0.0;
//           int qty = int.tryParse(item['qty']?.toString() ?? '0') ?? 0;
//           currentTotals[dept] = (currentTotals[dept] ?? 0) + (rate * qty);
//         }
//       }
//     });
    
//     // Get previous department totals
//     Map<String, double> previousTotals = {};
//     if (previousTransactionData != null && previousTransactionData!['departmentTotal'] != null) {
//       final prevDeptTotal = previousTransactionData!['departmentTotal'];
//       prevDeptTotal.forEach((key, value) {
//         previousTotals[key] = (value is num) ? (value as num).toDouble() : 0.0;
//       });
//     }
    
//     // Fill data
//     int row = 4;
//     double totalCurrent = 0;
//     double totalPrevious = 0;
    
//     var sortedDepts = currentTotals.keys.toList()..sort();
    
//     for (var dept in sortedDepts) {
//       double currentAmount = currentTotals[dept] ?? 0;
//       double previousAmount = previousTotals[dept] ?? 0;
//       double difference = currentAmount - previousAmount;
      
//       sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(dept);
//       sheet.cell(CellIndex.indexByString('B$row')).value = DoubleCellValue(currentAmount);
      
//       if (previousTransactionData == null) {
//         sheet.cell(CellIndex.indexByString('C$row')).value = TextCellValue('-');
//         sheet.cell(CellIndex.indexByString('D$row')).value = TextCellValue('-');
//       } else {
//         sheet.cell(CellIndex.indexByString('C$row')).value = DoubleCellValue(previousAmount);
//         sheet.cell(CellIndex.indexByString('D$row')).value = DoubleCellValue(difference);
//         totalPrevious += previousAmount;
//       }
      
//       totalCurrent += currentAmount;
//       row++;
//     }
    
//     // Total row
//     var totalStyle = CellStyle(
//       bold: true,
//       backgroundColorHex: ExcelColor.grey200,
//     );
    
//     sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue('TOTAL');
//     sheet.cell(CellIndex.indexByString('B$row')).value = DoubleCellValue(totalCurrent);
    
//     if (previousTransactionData == null) {
//       sheet.cell(CellIndex.indexByString('C$row')).value = TextCellValue('-');
//       sheet.cell(CellIndex.indexByString('D$row')).value = TextCellValue('-');
//     } else {
//       sheet.cell(CellIndex.indexByString('C$row')).value = DoubleCellValue(totalPrevious);
//       sheet.cell(CellIndex.indexByString('D$row')).value = DoubleCellValue(totalCurrent - totalPrevious);
//     }
    
//     for (var col in ['A$row', 'B$row', 'C$row', 'D$row']) {
//       sheet.cell(CellIndex.indexByString(col)).cellStyle = totalStyle;
//     }
    
//     // Prepared by
//     row += 2;
//     sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue('PREPARED BY ${currentTransactionData!['contactPerson'] ?? 'admin'}');
//     sheet.cell(CellIndex.indexByString('A$row')).cellStyle = CellStyle(italic: true);
//   }

//   // Sheet 3: INV REPORT VISUAL
//   Future<void> _createInvReportVisual(Excel excel) async {
//     var sheet = excel['INV REPORT VISUAL'];
    
//     // Title
//     sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('E1'));
//     sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('INVENTORY VISUAL SUMMARY');
//     sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
//       bold: true,
//       fontSize: 14,
//       horizontalAlign: HorizontalAlign.Center,
//       verticalAlign: VerticalAlign.Center,
//     );
    
//     // Headers
//     var headerStyle = CellStyle(
//       bold: true,
//       backgroundColorHex: ExcelColor.grey200,
//       horizontalAlign: HorizontalAlign.Center,
//       verticalAlign: VerticalAlign.Center,
//     );
    
//     sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue('Section');
//     sheet.cell(CellIndex.indexByString('B3')).value = TextCellValue('Position');
//     sheet.cell(CellIndex.indexByString('C3')).value = TextCellValue('Item Count');
//     sheet.cell(CellIndex.indexByString('D3')).value = TextCellValue('Total Quantity');
//     sheet.cell(CellIndex.indexByString('E3')).value = TextCellValue('Total Value');
    
//     for (var col in ['A3', 'B3', 'C3', 'D3', 'E3']) {
//       sheet.cell(CellIndex.indexByString(col)).cellStyle = headerStyle;
//     }
    
//     // Set column widths
//     sheet.setColumnWidth(0, 20);
//     sheet.setColumnWidth(1, 15);
//     sheet.setColumnWidth(2, 15);
//     sheet.setColumnWidth(3, 15);
//     sheet.setColumnWidth(4, 18);
    
//     // Get layout and scanned data
//     final layout = currentTransactionData!['layout'] ?? [];
//     final scannedData = currentTransactionData!['scannedData'] ?? {};
    
//     int row = 4;
//     double grandTotal = 0;
//     int totalItems = 0;
//     int totalQty = 0;
    
//     for (var section in layout) {
//       String sectionName = section['name'] ?? '';
//       String position = 'X:${section['x']}, Y:${section['y']}';
      
//       // Calculate section totals
//       int itemCount = 0;
//       int sectionQty = 0;
//       double sectionValue = 0;
      
//       if (scannedData[sectionName] != null) {
//         List items = scannedData[sectionName];
//         itemCount = items.length;
        
//         for (var item in items) {
//           int qty = int.tryParse(item['qty']?.toString() ?? '0') ?? 0;
//           double rate = (item['rate'] is num) ? (item['rate'] as num).toDouble() : 0.0;
//           sectionQty += qty;
//           sectionValue += rate * qty;
//         }
//       }
      
//       sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(sectionName);
//       sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(position);
//       sheet.cell(CellIndex.indexByString('C$row')).value = IntCellValue(itemCount);
//       sheet.cell(CellIndex.indexByString('D$row')).value = IntCellValue(sectionQty);
//       sheet.cell(CellIndex.indexByString('E$row')).value = DoubleCellValue(sectionValue);
      
//       grandTotal += sectionValue;
//       totalItems += itemCount;
//       totalQty += sectionQty;
//       row++;
//     }
    
//     // Total row
//     var totalStyle = CellStyle(
//       bold: true,
//       backgroundColorHex: ExcelColor.grey200,
//     );
    
//     sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue('TOTAL');
//     sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue('');
//     sheet.cell(CellIndex.indexByString('C$row')).value = IntCellValue(totalItems);
//     sheet.cell(CellIndex.indexByString('D$row')).value = IntCellValue(totalQty);
//     sheet.cell(CellIndex.indexByString('E$row')).value = DoubleCellValue(grandTotal);
    
//     for (var col in ['A$row', 'B$row', 'C$row', 'D$row', 'E$row']) {
//       sheet.cell(CellIndex.indexByString(col)).cellStyle = totalStyle;
//     }
//   }

//   // Sheet 4: CONSOLIDATION REPORT
//   Future<void> _createConsolidationReport(Excel excel) async {
//     var sheet = excel['CONSOLIDATION'];
    
//     // Title
//     sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('G1'));
//     sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('CONSOLIDATION REPORT');
//     sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
//       bold: true,
//       fontSize: 14,
//       horizontalAlign: HorizontalAlign.Center,
//       verticalAlign: VerticalAlign.Center,
//     );
    
//     // Headers
//     var headerStyle = CellStyle(
//       bold: true,
//       backgroundColorHex: ExcelColor.grey200,
//       horizontalAlign: HorizontalAlign.Center,
//       verticalAlign: VerticalAlign.Center,
//     );
    
//     sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue('SECTION');
//     sheet.cell(CellIndex.indexByString('B2')).value = TextCellValue('CODE');
//     sheet.cell(CellIndex.indexByString('C2')).value = TextCellValue('DEPARTMENT');
//     sheet.cell(CellIndex.indexByString('D2')).value = TextCellValue('ITEM NAME');
//     sheet.cell(CellIndex.indexByString('E2')).value = TextCellValue('RATE');
//     sheet.cell(CellIndex.indexByString('F2')).value = TextCellValue('QTY');
//     sheet.cell(CellIndex.indexByString('G2')).value = TextCellValue('AMOUNT');
    
//     for (var col in ['A2', 'B2', 'C2', 'D2', 'E2', 'F2', 'G2']) {
//       sheet.cell(CellIndex.indexByString(col)).cellStyle = headerStyle;
//     }
    
//     // Set column widths
//     sheet.setColumnWidth(0, 15);
//     sheet.setColumnWidth(1, 18);
//     sheet.setColumnWidth(2, 18);
//     sheet.setColumnWidth(3, 40);
//     sheet.setColumnWidth(4, 12);
//     sheet.setColumnWidth(5, 10);
//     sheet.setColumnWidth(6, 15);
    
//     // Consolidate items by scan code
//     Map<String, Map<String, dynamic>> consolidatedItems = {};
//     final scannedData = currentTransactionData!['scannedData'] ?? {};
    
//     scannedData.forEach((sectionName, items) {
//       if (items is List) {
//         for (var item in items) {
//           String scanCode = item['scanCode']?.toString() ?? item['code']?.toString() ?? '';
          
//           if (scanCode.isNotEmpty) {
//             if (consolidatedItems.containsKey(scanCode)) {
//               // Merge quantities
//               int existingQty = consolidatedItems[scanCode]!['qty'];
//               int newQty = int.tryParse(item['qty']?.toString() ?? '0') ?? 0;
//               consolidatedItems[scanCode]!['qty'] = existingQty + newQty;
//               consolidatedItems[scanCode]!['sections'].add(sectionName);
//             } else {
//               // New item
//               consolidatedItems[scanCode] = {
//                 'scanCode': scanCode,
//                 'code': item['code'] ?? '',
//                 'department': item['department'] ?? '',
//                 'name': item['name'] ?? '',
//                 'rate': (item['rate'] is num) ? (item['rate'] as num).toDouble() : 0.0,
//                 'qty': int.tryParse(item['qty']?.toString() ?? '0') ?? 0,
//                 'sections': [sectionName],
//               };
//             }
//           }
//         }
//       }
//     });
    
//     // Sort by department, then by name
//     var sortedItems = consolidatedItems.values.toList()
//       ..sort((a, b) {
//         int deptCompare = a['department'].toString().compareTo(b['department'].toString());
//         if (deptCompare != 0) return deptCompare;
//         return a['name'].toString().compareTo(b['name'].toString());
//       });
    
//     // Fill data
//     int row = 3;
//     for (var item in sortedItems) {
//       String sections = (item['sections'] as List).join(', ');
//       sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(sections);
//       sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(item['code']);
//       sheet.cell(CellIndex.indexByString('C$row')).value = TextCellValue(item['department']);
//       sheet.cell(CellIndex.indexByString('D$row')).value = TextCellValue(item['name']);
//       sheet.cell(CellIndex.indexByString('E$row')).value = DoubleCellValue(item['rate']);
//       sheet.cell(CellIndex.indexByString('F$row')).value = IntCellValue(item['qty']);
//       sheet.cell(CellIndex.indexByString('G$row')).value = DoubleCellValue(item['rate'] * item['qty']);
//       row++;
//     }
//   }

//   // Sheet 5: TOTAL STOCK REPORT
//   Future<void> _createTotalStockReport(Excel excel) async {
//     var sheet = excel['TOTAL STOCK'];
    
//     // Title
//     sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('C1'));
//     sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('TOTAL STOCK LIST');
//     sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
//       bold: true,
//       fontSize: 14,
//       horizontalAlign: HorizontalAlign.Center,
//       verticalAlign: VerticalAlign.Center,
//     );
    
//     // Headers
//     var headerStyle = CellStyle(
//       bold: true,
//       backgroundColorHex: ExcelColor.grey200,
//       horizontalAlign: HorizontalAlign.Center,
//       verticalAlign: VerticalAlign.Center,
//     );
    
//     sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue('DEPARTMENT');
//     sheet.cell(CellIndex.indexByString('B3')).value = TextCellValue('CODE');
//     sheet.cell(CellIndex.indexByString('C3')).value = TextCellValue('TOTAL QTY');
    
//     for (var col in ['A3', 'B3', 'C3']) {
//       sheet.cell(CellIndex.indexByString(col)).cellStyle = headerStyle;
//     }
    
//     // Set column widths
//     sheet.setColumnWidth(0, 20);
//     sheet.setColumnWidth(1, 20);
//     sheet.setColumnWidth(2, 15);
    
//     // Group by department and code
//     Map<String, Map<String, int>> departmentCodeMap = {};
//     final scannedData = currentTransactionData!['scannedData'] ?? {};
    
//     scannedData.forEach((sectionName, items) {
//       if (items is List) {
//         for (var item in items) {
//           String dept = item['department'] ?? '';
//           String code = item['code'] ?? '';
//           int qty = int.tryParse(item['qty']?.toString() ?? '0') ?? 0;
          
//           if (!departmentCodeMap.containsKey(dept)) {
//             departmentCodeMap[dept] = {};
//           }
          
//           departmentCodeMap[dept]![code] = (departmentCodeMap[dept]![code] ?? 0) + qty;
//         }
//       }
//     });
    
//     // Sort and fill data
//     int row = 4;
//     var sortedDepts = departmentCodeMap.keys.toList()..sort();
    
//     for (var dept in sortedDepts) {
//       var codes = departmentCodeMap[dept]!;
//       var sortedCodes = codes.keys.toList()..sort();
      
//       for (var code in sortedCodes) {
//         sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(dept);
//         sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(code);
//         sheet.cell(CellIndex.indexByString('C$row')).value = IntCellValue(codes[code]!);
//         row++;
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.grey.shade50,
//       appBar: AppBar(
//         title: const Text('Transaction Reports', style: TextStyle(fontWeight: FontWeight.bold)),
//         backgroundColor: const Color.fromARGB(255, 3, 25, 55),
//         foregroundColor: Colors.white,
//         elevation: 0,
//       ),
//       body: isLoading
//           ? const Center(child: CircularProgressIndicator())
//           : SingleChildScrollView(
//               padding: const EdgeInsets.all(24),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.stretch,
//                 children: [
//                   // Company info card
//                   Card(
//                     elevation: 2,
//                     child: Padding(
//                       padding: const EdgeInsets.all(20),
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Row(
//                             children: [
//                               Icon(Icons.business, size: 40, color: const Color.fromARGB(255, 3, 25, 55)),
//                               const SizedBox(width: 16),
//                               Expanded(
//                                 child: Column(
//                                   crossAxisAlignment: CrossAxisAlignment.start,
//                                   children: [
//                                     Text(
//                                       widget.companyName,
//                                       style: const TextStyle(
//                                         fontSize: 22,
//                                         fontWeight: FontWeight.bold,
//                                       ),
//                                     ),
//                                     const SizedBox(height: 4),
//                                     Text(
//                                       'Transaction ID: ${widget.transactionId}',
//                                       style: TextStyle(
//                                         fontSize: 14,
//                                         color: Colors.grey.shade600,
//                                       ),
//                                     ),
//                                   ],
//                                 ),
//                               ),
//                             ],
//                           ),
//                           if (currentTransactionData != null) ...[
//                             const SizedBox(height: 16),
//                             const Divider(),
//                             const SizedBox(height: 12),
//                             _buildInfoRow('Contact Person', currentTransactionData!['contactPerson']?.toString() ?? 'N/A'),
//                             _buildInfoRow('Created At', currentTransactionData!['createdAt'] != null 
//                                 ? DateFormat('MMM dd, yyyy HH:mm').format(DateTime.parse(currentTransactionData!['createdAt']))
//                                 : 'N/A'),
//                             _buildInfoRow('Status', currentTransactionData!['status']?.toString().toUpperCase() ?? 'N/A'),
//                           ],
//                         ],
//                       ),
//                     ),
//                   ),
                  
//                   const SizedBox(height: 24),
                  
//                   // Reports info card
//                   Card(
//                     elevation: 2,
//                     child: Padding(
//                       padding: const EdgeInsets.all(20),
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           const Text(
//                             'Available Reports',
//                             style: TextStyle(
//                               fontSize: 18,
//                               fontWeight: FontWeight.bold,
//                             ),
//                           ),
//                           const SizedBox(height: 16),
//                           _buildReportItem(
//                             icon: FontAwesomeIcons.userPen,
//                             title: 'Missing Item Report',
//                             description: 'List of manually added items across all sections',
//                             color: Colors.orange,
//                           ),
//                           const Divider(height: 24),
//                           _buildReportItem(
//                             icon: FontAwesomeIcons.chartColumn,
//                             title: 'Inventory Report',
//                             description: 'Department-wise current vs previous comparison',
//                             color: const Color.fromARGB(255, 3, 25, 55),
//                           ),
//                           const Divider(height: 24),
//                           _buildReportItem(
//                             icon: FontAwesomeIcons.chartPie,
//                             title: 'Inventory Visual Summary',
//                             description: 'Section-wise totals based on layout',
//                             color: const Color.fromARGB(255, 3, 25, 55),
//                           ),
//                           const Divider(height: 24),
//                           _buildReportItem(
//                             icon: FontAwesomeIcons.layerGroup,
//                             title: 'Consolidation Report',
//                             description: 'Merged items across all sections',
//                             color: Colors.teal,
//                           ),
//                           const Divider(height: 24),
//                           _buildReportItem(
//                             icon: FontAwesomeIcons.boxesStacked,
//                             title: 'Total Stock Report',
//                             description: 'Department and code-wise quantities',
//                             color: Colors.green,
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
                  
//                   const SizedBox(height: 24),
                  
//                   // Statistics card
//                   if (currentTransactionData != null) ...[
//                     Card(
//                       elevation: 2,
//                       color: const Color.fromARGB(255, 3, 25, 55).shade50,
//                       child: Padding(
//                         padding: const EdgeInsets.all(20),
//                         child: Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             Row(
//                               children: [
//                                 Icon(Icons.analytics, color: const Color.fromARGB(255, 3, 25, 55)),
//                                 const SizedBox(width: 8),
//                                 const Text(
//                                   'Quick Statistics',
//                                   style: TextStyle(
//                                     fontSize: 16,
//                                     fontWeight: FontWeight.bold,
//                                   ),
//                                 ),
//                               ],
//                             ),
//                             const SizedBox(height: 16),
//                             _buildStatRow('Total Sections', _getTotalSections().toString()),
//                             _buildStatRow('Total Items', _getTotalItems().toString()),
//                             _buildStatRow('Manual Entries', _getManualEntries().toString()),
//                             _buildStatRow('Scanned Entries', _getScannedEntries().toString()),
//                             if (previousTransactionData != null)
//                               _buildStatRow('Previous Transaction', 'Available')
//                             else
//                               _buildStatRow('Previous Transaction', 'None (First transaction)', isWarning: true),
//                           ],
//                         ),
//                       ),
//                     ),
//                     const SizedBox(height: 24),
//                   ],
                  
//                   // Generate button
//                   ElevatedButton.icon(
//                     onPressed: isGenerating ? null : _generateExcelReport,
//                     icon: Icon(
//                       isGenerating ? FontAwesomeIcons.spinner : FontAwesomeIcons.fileExcel,
//                       size: 20,
//                     ),
//                     label: Text(
//                       isGenerating ? 'Generating Report...' : 'Generate Excel Report',
//                       style: const TextStyle(
//                         fontSize: 16,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: Colors.green,
//                       foregroundColor: Colors.white,
//                       padding: const EdgeInsets.symmetric(vertical: 16),
//                       shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                       elevation: 2,
//                     ),
//                   ),
                  
//                   const SizedBox(height: 16),
                  
//                   // Info box
//                   Container(
//                     padding: const EdgeInsets.all(12),
//                     decoration: BoxDecoration(
//                       color: const Color.fromARGB(255, 3, 25, 55).shade50,
//                       borderRadius: BorderRadius.circular(8),
//                       border: Border.all(color: const Color.fromARGB(255, 3, 25, 55).shade200),
//                     ),
//                     child: Row(
//                       children: [
//                         Icon(Icons.info_outline, color: const Color.fromARGB(255, 3, 25, 55).shade700, size: 20),
//                         const SizedBox(width: 8),
//                         Expanded(
//                           child: Text(
//                             'The Excel file will contain all 5 reports in separate sheets',
//                             style: TextStyle(
//                               fontSize: 12,
//                               color: const Color.fromARGB(255, 3, 25, 55).shade700,
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//     );
//   }

//   Widget _buildInfoRow(String label, String value) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 6),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           SizedBox(
//             width: 120,
//             child: Text(
//               label,
//               style: TextStyle(
//                 fontSize: 14,
//                 color: Colors.grey.shade700,
//                 fontWeight: FontWeight.w500,
//               ),
//             ),
//           ),
//           Expanded(
//             child: Text(
//               value,
//               style: const TextStyle(
//                 fontSize: 14,
//                 fontWeight: FontWeight.w600,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildReportItem({
//     required IconData icon,
//     required String title,
//     required String description,
//     required Color color,
//   }) {
//     return Row(
//       children: [
//         Container(
//           width: 40,
//           height: 40,
//           decoration: BoxDecoration(
//             color: color.withOpacity(0.1),
//             borderRadius: BorderRadius.circular(8),
//           ),
//           child: Icon(icon, color: color, size: 20),
//         ),
//         const SizedBox(width: 12),
//         Expanded(
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 title,
//                 style: const TextStyle(
//                   fontSize: 14,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               const SizedBox(height: 2),
//               Text(
//                 description,
//                 style: TextStyle(
//                   fontSize: 12,
//                   color: Colors.grey.shade600,
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildStatRow(String label, String value, {bool isWarning = false}) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 4),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           Text(
//             label,
//             style: TextStyle(
//               fontSize: 14,
//               color: Colors.grey.shade700,
//             ),
//           ),
//           Text(
//             value,
//             style: TextStyle(
//               fontSize: 14,
//               fontWeight: FontWeight.bold,
//               color: isWarning ? Colors.orange : const Color.fromARGB(255, 3, 25, 55),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   int _getTotalSections() {
//     if (currentTransactionData == null) return 0;
//     final scannedData = currentTransactionData!['scannedData'] ?? {};
//     return scannedData.keys.length;
//   }

//   int _getTotalItems() {
//     if (currentTransactionData == null) return 0;
//     int count = 0;
//     final scannedData = currentTransactionData!['scannedData'] ?? {};
//     scannedData.forEach((key, items) {
//       if (items is List) count += items.length;
//     });
//     return count;
//   }

//   int _getManualEntries() {
//     if (currentTransactionData == null) return 0;
//     int count = 0;
//     final scannedData = currentTransactionData!['scannedData'] ?? {};
//     scannedData.forEach((key, items) {
//       if (items is List) {
//         count += items.where((item) => item['__source'] == 'manual').length;
//       }
//     });
//     return count;
//   }

//   int _getScannedEntries() {
//     if (currentTransactionData == null) return 0;
//     int count = 0;
//     final scannedData = currentTransactionData!['scannedData'] ?? {};
//     scannedData.forEach((key, items) {
//       if (items is List) {
//         count += items.where((item) => item['__source'] == 'scanner').length;
//       }
//     });
//     return count;
//   }

//   void _showErrorSnackBar(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Row(
//           children: [
//             const Icon(Icons.error_outline, color: Colors.white),
//             const SizedBox(width: 16),
//             Expanded(child: Text(message)),
//           ],
//         ),
//         backgroundColor: Colors.red,
//         behavior: SnackBarBehavior.floating,
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
//       ),
//     );
//   }

//   void _showSuccessSnackBar(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Row(
//           children: [
//             const Icon(Icons.check_circle, color: Colors.white),
//             const SizedBox(width: 16),
//             Text(message),
//           ],
//         ),
//         backgroundColor: Colors.green,
//         behavior: SnackBarBehavior.floating,
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
//       ),
//     );
//   }
// }

class _TransactionReportScreenState extends State<TransactionReportScreen> with SingleTickerProviderStateMixin {
  late final ApiService _apiService;
  final DioService _dioService = DioService();
  
  late TabController _tabController;
  
  bool isLoading = false;
  bool isGenerating = false;
  Map<String, dynamic>? currentTransactionData;
  Map<String, dynamic>? previousTransactionData;
  
  // Computed data for tabs
  List<Map<String, dynamic>> departmentData = [];
  List<Map<String, dynamic>> sectionData = [];
  List<Map<String, dynamic>> missingItemsData = [];
  
  @override
  void initState() {
    super.initState();
    _apiService = ApiService(_dioService);
    _tabController = TabController(length: 3, vsync: this);
    _fetchTransactionData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchTransactionData() async {
    try {
      setState(() => isLoading = true);
      
      // Fetch current transaction
      final currentUrl = '${AppConfig.baseUrl}transactions/${widget.transactionId}';
      final currentData = await _apiService.getRequest(currentUrl);

      //print('🔍 Transaction Data: ${json.encode(currentData)}');
      //print('🔍 Sections type: ${currentData?['sections'].runtimeType}');
      //print('🔍 Sections data: ${currentData?['sections']}');
      
      // Fetch previous transaction
      final previousUrl = '${AppConfig.baseUrl}transactions?companyId=${widget.companyId}&sort=createdAt:desc&limit=2';
      final previousList = await _apiService.getRequest(previousUrl);
      
      Map<String, dynamic>? previousData;
      if (previousList != null) {
        List<dynamic> transactions = previousList is List ? previousList : (previousList['data'] ?? []);
        for (var trans in transactions) {
          if (trans['id']?.toString() != widget.transactionId) {
            previousData = trans;
            break;
          }
        }
      }
      
      setState(() {
        currentTransactionData = currentData;
        previousTransactionData = previousData;
        isLoading = false;
      });
      
      // Calculate tab data
      _calculateTabData();
      
    } catch (e) {
      setState(() => isLoading = false);
      _showErrorSnackBar('Failed to load transaction data: ${e.toString()}');
    }
  }

  void _calculateTabData() {
    if (currentTransactionData == null) return;
    
    //print('📊 Starting _calculateTabData...');
    
    // 1. Calculate Department Data
    Map<String, double> currentTotals = {};
    final scannedData = currentTransactionData!['scannedData'];
    
    //print('🔍 ScannedData type: ${scannedData.runtimeType}');
    //print('🔍 ScannedData: $scannedData');
    
    // Safely handle scannedData - it can be null or empty
    if (scannedData != null && scannedData is Map) {
      scannedData.forEach((sectionName, items) {
        //print('  📦 Processing section: $sectionName');
        
        if (items == null) {
          //print('    ⚠️ Items is null for section $sectionName');
          return; // Skip this section
        }
        
        if (items is! List) {
          //print('    ⚠️ Items is not a List for section $sectionName: ${items.runtimeType}');
          return; // Skip this section
        }
        
        //print('    ✅ Found ${items.length} items in $sectionName');
        
        for (var item in items) {
          if (item == null || item is! Map) {
            //print('      ⚠️ Skipping invalid item: ${item.runtimeType}');
            continue;
          }
          
          String dept = item['department']?.toString() ?? '';
          double rate = 0.0;
          int qty = 0;
          
          // Safely parse rate
          try {
            if (item['rate'] != null) {
              if (item['rate'] is num) {
                rate = (item['rate'] as num).toDouble();
              } else if (item['rate'] is String) {
                rate = double.tryParse(item['rate']) ?? 0.0;
              }
            }
          } catch (e) {
            //print('      ⚠️ Error parsing rate: $e');
          }
          
          // Safely parse qty
          try {
            if (item['qty'] != null) {
              if (item['qty'] is int) {
                qty = item['qty'];
              } else if (item['qty'] is String) {
                qty = int.tryParse(item['qty']) ?? 0;
              } else if (item['qty'] is num) {
                qty = (item['qty'] as num).toInt();
              }
            }
          } catch (e) {
            //print('      ⚠️ Error parsing qty: $e');
          }
          
          if (dept.isNotEmpty) {
            currentTotals[dept] = (currentTotals[dept] ?? 0) + (rate * qty);
            //print('      ✅ Added ${rate * qty} to dept $dept');
          }
        }
      });
    } else {
      //print('⚠️ ScannedData is null or not a Map');
    }
    
    // Get previous totals
    Map<String, double> previousTotals = {};
    if (previousTransactionData != null) {
      final prevDeptTotal = previousTransactionData!['departmentTotal'];
      if (prevDeptTotal != null && prevDeptTotal is Map) {
        prevDeptTotal.forEach((key, value) {
          try {
            if (value is num) {
              previousTotals[key.toString()] = value.toDouble();
            } else if (value is String) {
              previousTotals[key.toString()] = double.tryParse(value) ?? 0.0;
            }
          } catch (e) {
            //print('⚠️ Error parsing previous total for $key: $e');
          }
        });
      }
    }
    
    // Build department data list
    departmentData = currentTotals.keys.map((dept) {
      return {
        'department': dept,
        'totalAmount': currentTotals[dept] ?? 0.0,
        'prevTotal': previousTotals[dept] ?? 0.0,
      };
    }).toList();
    
    departmentData.sort((a, b) => 
      (a['department'] as String).compareTo(b['department'] as String));
    
    //print('✅ Department data calculated: ${departmentData.length} departments');
    
    // 2. Calculate Section Data
    Map<String, double> sectionTotals = {};
    
    if (scannedData != null && scannedData is Map) {
      scannedData.forEach((sectionName, items) {
        double total = 0;
        
        if (items != null && items is List) {
          for (var item in items) {
            if (item == null || item is! Map) continue;
            
            double rate = 0.0;
            int qty = 0;
            
            try {
              if (item['rate'] != null) {
                if (item['rate'] is num) {
                  rate = (item['rate'] as num).toDouble();
                } else if (item['rate'] is String) {
                  rate = double.tryParse(item['rate']) ?? 0.0;
                }
              }
              
              if (item['qty'] != null) {
                if (item['qty'] is int) {
                  qty = item['qty'];
                } else if (item['qty'] is String) {
                  qty = int.tryParse(item['qty']) ?? 0;
                } else if (item['qty'] is num) {
                  qty = (item['qty'] as num).toInt();
                }
              }
              
              total += rate * qty;
            } catch (e) {
              //print('⚠️ Error calculating section total: $e');
            }
          }
        }
        
        sectionTotals[sectionName.toString()] = total;
      });
    }
    
    // IMPORTANT: Also include sections with no data (0 totals)
    final sections = currentTransactionData!['sections'];
    if (sections != null && sections is Map) {
      sections.keys.forEach((sectionName) {
        final sectionNameStr = sectionName.toString();
        if (!sectionTotals.containsKey(sectionNameStr)) {
          sectionTotals[sectionNameStr] = 0.0;
          //print('  ℹ️ Added empty section: $sectionNameStr');
        }
      });
    }
    
    sectionData = sectionTotals.entries.map((entry) {
      return {
        'section': entry.key,
        'totalAmount': entry.value,
      };
    }).toList();
    
    sectionData.sort((a, b) => 
      (a['section'] as String).compareTo(b['section'] as String));
    
    //print('✅ Section data calculated: ${sectionData.length} sections');
    
    // 3. Calculate Missing Items Data
    missingItemsData = [];
    
    if (scannedData != null && scannedData is Map) {
      scannedData.forEach((sectionName, items) {
        if (items == null || items is! List) return;
        
        for (var item in items) {
          if (item == null || item is! Map) continue;
          
          try {
            if (item['__source'] == 'manual') {
              double rate = 0.0;
              int qty = 0;
              
              if (item['rate'] != null) {
                if (item['rate'] is num) {
                  rate = (item['rate'] as num).toDouble();
                } else if (item['rate'] is String) {
                  rate = double.tryParse(item['rate']) ?? 0.0;
                }
              }
              
              if (item['qty'] != null) {
                if (item['qty'] is int) {
                  qty = item['qty'];
                } else if (item['qty'] is String) {
                  qty = int.tryParse(item['qty']) ?? 0;
                } else if (item['qty'] is num) {
                  qty = (item['qty'] as num).toInt();
                }
              }
              
              missingItemsData.add({
                'section': sectionName.toString(),
                'scanCode': item['scanCode']?.toString() ?? item['code']?.toString() ?? '',
                'name': item['name']?.toString() ?? '',
                'department': item['department']?.toString() ?? '',
                'rate': rate,
                'qty': qty,
              });
            }
          } catch (e) {
            //print('⚠️ Error processing missing item: $e');
          }
        }
      });
    }
    
    missingItemsData.sort((a, b) {
      int sectionCompare = (a['section'] as String).compareTo(b['section'] as String);
      if (sectionCompare != 0) return sectionCompare;
      return (a['name'] as String).compareTo(b['name'] as String);
    });
    
    //print('✅ Missing items calculated: ${missingItemsData.length} items');
    //print('📊 _calculateTabData completed successfully!');
    
    setState(() {});
  }

  // void _calculateTabData() {
  //   if (currentTransactionData == null) return;
    
  //   // 1. Calculate Department Data
  //   Map<String, double> currentTotals = {};
  //   final scannedData = currentTransactionData!['scannedData'] ?? {};
    
  //   scannedData.forEach((sectionName, items) {
  //     if (items is List) {
  //       for (var item in items) {
  //         String dept = item['department'] ?? '';
  //         double rate = (item['rate'] is num) ? (item['rate'] as num).toDouble() : 0.0;
  //         int qty = int.tryParse(item['qty']?.toString() ?? '0') ?? 0;
  //         currentTotals[dept] = (currentTotals[dept] ?? 0) + (rate * qty);
  //       }
  //     }
  //   });
    
  //   Map<String, double> previousTotals = {};
  //   if (previousTransactionData != null && previousTransactionData!['departmentTotal'] != null) {
  //     final prevDeptTotal = previousTransactionData!['departmentTotal'];
  //     prevDeptTotal.forEach((key, value) {
  //       previousTotals[key] = (value is num) ? (value as num).toDouble() : 0.0;
  //     });
  //   }
    
  //   departmentData = currentTotals.keys.map((dept) {
  //     return {
  //       'department': dept,
  //       'totalAmount': currentTotals[dept] ?? 0,
  //       'prevTotal': previousTotals[dept] ?? 0,
  //     };
  //   }).toList()..sort((a, b) => a['department'].toString().compareTo(b['department'].toString()));
    
  //   // 2. Calculate Section Data
  //   Map<String, double> sectionTotals = {};
  //   scannedData.forEach((sectionName, items) {
  //     if (items is List) {
  //       double total = 0;
  //       for (var item in items) {
  //         double rate = (item['rate'] is num) ? (item['rate'] as num).toDouble() : 0.0;
  //         int qty = int.tryParse(item['qty']?.toString() ?? '0') ?? 0;
  //         total += rate * qty;
  //       }
  //       sectionTotals[sectionName] = total;
  //     }
  //   });
    
  //   sectionData = sectionTotals.entries.map((entry) {
  //     return {
  //       'section': entry.key,
  //       'totalAmount': entry.value,
  //     };
  //   }).toList()..sort((a, b) => a['section'].toString().compareTo(b['section'].toString()));
    
  //   // 3. Calculate Missing Items Data
  //   missingItemsData = [];
  //   scannedData.forEach((sectionName, items) {
  //     if (items is List) {
  //       for (var item in items) {
  //         if (item['__source'] == 'manual') {
  //           missingItemsData.add({
  //             'section': sectionName,
  //             'scanCode': item['scanCode'] ?? item['code'] ?? '',
  //             'name': item['name'] ?? '',
  //             'department': item['department'] ?? '',
  //             'rate': (item['rate'] is num) ? (item['rate'] as num).toDouble() : 0.0,
  //             'qty': int.tryParse(item['qty']?.toString() ?? '0') ?? 0,
  //           });
  //         }
  //       }
  //     }
  //   });
    
  //   missingItemsData.sort((a, b) {
  //     int sectionCompare = a['section'].toString().compareTo(b['section'].toString());
  //     if (sectionCompare != 0) return sectionCompare;
  //     return a['name'].toString().compareTo(b['name'].toString());
  //   });
    
  //   setState(() {});
  // }

  Future<void> _generateExcelReport() async {
    if (currentTransactionData == null) {
      _showErrorSnackBar('No transaction data available');
      return;
    }

    try {
      setState(() => isGenerating = true);
      
      var excel = Excel.createExcel();
      excel.delete('Sheet1');
      
      await _createMissingItemReport(excel);
      await _createInventoryReport(excel);
      await _createInvReportVisual(excel);
      await _createConsolidationReport(excel);
      await _createTotalStockReport(excel);
      
      var fileBytes = excel.save();
      
      if (fileBytes != null) {
        final fileName = '${widget.companyName.replaceAll(' ', '_')}_${DateFormat('MMddyyyy').format(DateTime.now())}.xlsx';
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(fileBytes);
        
        setState(() => isGenerating = false);
        
        await Share.shareXFiles([XFile(file.path)], text: 'Transaction Report - ${widget.companyName}');
        
        _showSuccessSnackBar('Report generated successfully!');
      }
    } catch (e) {
      setState(() => isGenerating = false);
      _showErrorSnackBar('Error generating report: ${e.toString()}');
    }
  }

  // Excel generation methods remain the same
  Future<void> _createMissingItemReport(Excel excel) async {
    var sheet = excel['MISSING ITEM REPORT'];
    
    var headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.grey200,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('DEPARTMENT');
    sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue('SCAN CODE');
    sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('COUNT');
    sheet.cell(CellIndex.indexByString('D1')).value = TextCellValue('ITEM DESCRIPTION');
    sheet.cell(CellIndex.indexByString('E1')).value = TextCellValue('Unit Retail');
    sheet.cell(CellIndex.indexByString('F1')).value = TextCellValue('AMOUNT');
    
    for (var col in ['A1', 'B1', 'C1', 'D1', 'E1', 'F1']) {
      sheet.cell(CellIndex.indexByString(col)).cellStyle = headerStyle;
    }
    
    sheet.setColumnWidth(0, 15);
    sheet.setColumnWidth(1, 20);
    sheet.setColumnWidth(2, 10);
    sheet.setColumnWidth(3, 40);
    sheet.setColumnWidth(4, 12);
    sheet.setColumnWidth(5, 15);
    
    List<Map<String, dynamic>> manualItems = [];
    final scannedData = currentTransactionData!['scannedData'] ?? {};
    
    scannedData.forEach((sectionName, items) {
      if (items is List) {
        for (var item in items) {
          if (item['__source'] == 'manual') {
            manualItems.add({
              'department': item['department'] ?? '',
              'scanCode': item['scanCode'] ?? item['code'] ?? '',
              'name': item['name'] ?? '',
              'rate': (item['rate'] is num) ? (item['rate'] as num).toDouble() : 0.0,
              'qty': int.tryParse(item['qty']?.toString() ?? '0') ?? 0,
            });
          }
        }
      }
    });
    
    manualItems.sort((a, b) {
      int deptCompare = a['department'].toString().compareTo(b['department'].toString());
      if (deptCompare != 0) return deptCompare;
      return a['scanCode'].toString().compareTo(b['scanCode'].toString());
    });
    
    int row = 2;
    for (var item in manualItems) {
      sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(item['department']);
      sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(item['scanCode']);
      sheet.cell(CellIndex.indexByString('C$row')).value = IntCellValue(item['qty']);
      sheet.cell(CellIndex.indexByString('D$row')).value = TextCellValue(item['name']);
      sheet.cell(CellIndex.indexByString('E$row')).value = DoubleCellValue(item['rate']);
      sheet.cell(CellIndex.indexByString('F$row')).value = DoubleCellValue(item['rate'] * item['qty']);
      row++;
    }
  }

  Future<void> _createInventoryReport(Excel excel) async {
    var sheet = excel['INV REPORT'];
    
    // Title
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('D1'));
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue(widget.companyName.toUpperCase());
    sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
      bold: true,
      fontSize: 16,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    // Date - use current date since createdAt might be Firestore Timestamp
    sheet.merge(CellIndex.indexByString('A2'), CellIndex.indexByString('D2'));
    sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue(DateFormat('MM-dd-yyyy').format(DateTime.now()));
    sheet.cell(CellIndex.indexByString('A2')).cellStyle = CellStyle(
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    var headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.grey200,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue('DEPARTMENT');
    sheet.cell(CellIndex.indexByString('B3')).value = TextCellValue('CURRENT DOLLARS');
    sheet.cell(CellIndex.indexByString('C3')).value = TextCellValue('PREVIOUS DOLLARS');
    sheet.cell(CellIndex.indexByString('D3')).value = TextCellValue('DIFFERENCE');
    
    for (var col in ['A3', 'B3', 'C3', 'D3']) {
      sheet.cell(CellIndex.indexByString(col)).cellStyle = headerStyle;
    }
    
    sheet.setColumnWidth(0, 20);
    sheet.setColumnWidth(1, 18);
    sheet.setColumnWidth(2, 18);
    sheet.setColumnWidth(3, 18);
    
    Map<String, double> currentTotals = {};
    final scannedData = currentTransactionData!['scannedData'] ?? {};
    
    scannedData.forEach((sectionName, items) {
      if (items is List) {
        for (var item in items) {
          String dept = item['department'] ?? '';
          double rate = (item['rate'] is num) ? (item['rate'] as num).toDouble() : 0.0;
          int qty = int.tryParse(item['qty']?.toString() ?? '0') ?? 0;
          currentTotals[dept] = (currentTotals[dept] ?? 0) + (rate * qty);
        }
      }
    });
    
    Map<String, double> previousTotals = {};
    if (previousTransactionData != null && previousTransactionData!['departmentTotal'] != null) {
      final prevDeptTotal = previousTransactionData!['departmentTotal'];
      prevDeptTotal.forEach((key, value) {
        previousTotals[key] = (value is num) ? (value as num).toDouble() : 0.0;
      });
    }
    
    int row = 4;
    double totalCurrent = 0;
    double totalPrevious = 0;
    
    var sortedDepts = currentTotals.keys.toList()..sort();
    
    for (var dept in sortedDepts) {
      double currentAmount = currentTotals[dept] ?? 0;
      double previousAmount = previousTotals[dept] ?? 0;
      double difference = currentAmount - previousAmount;
      
      sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(dept);
      sheet.cell(CellIndex.indexByString('B$row')).value = DoubleCellValue(currentAmount);
      
      if (previousTransactionData == null) {
        sheet.cell(CellIndex.indexByString('C$row')).value = TextCellValue('-');
        sheet.cell(CellIndex.indexByString('D$row')).value = TextCellValue('-');
      } else {
        sheet.cell(CellIndex.indexByString('C$row')).value = DoubleCellValue(previousAmount);
        sheet.cell(CellIndex.indexByString('D$row')).value = DoubleCellValue(difference);
        totalPrevious += previousAmount;
      }
      
      totalCurrent += currentAmount;
      row++;
    }
    
    var totalStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.grey200,
    );
    
    sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue('TOTAL');
    sheet.cell(CellIndex.indexByString('B$row')).value = DoubleCellValue(totalCurrent);
    
    if (previousTransactionData == null) {
      sheet.cell(CellIndex.indexByString('C$row')).value = TextCellValue('-');
      sheet.cell(CellIndex.indexByString('D$row')).value = TextCellValue('-');
    } else {
      sheet.cell(CellIndex.indexByString('C$row')).value = DoubleCellValue(totalPrevious);
      sheet.cell(CellIndex.indexByString('D$row')).value = DoubleCellValue(totalCurrent - totalPrevious);
    }
    
    for (var col in ['A$row', 'B$row', 'C$row', 'D$row']) {
      sheet.cell(CellIndex.indexByString(col)).cellStyle = totalStyle;
    }
    
    row += 2;
    sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue('PREPARED BY ${currentTransactionData!['contactPerson'] ?? 'admin'}');
    sheet.cell(CellIndex.indexByString('A$row')).cellStyle = CellStyle(italic: true);
  }

  Future<void> _createInvReportVisual(Excel excel) async {
    var sheet = excel['INV REPORT VISUAL'];
    
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('E1'));
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('INVENTORY VISUAL SUMMARY');
    sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
      bold: true,
      fontSize: 14,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    var headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.grey200,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue('Section');
    sheet.cell(CellIndex.indexByString('B3')).value = TextCellValue('Position');
    sheet.cell(CellIndex.indexByString('C3')).value = TextCellValue('Item Count');
    sheet.cell(CellIndex.indexByString('D3')).value = TextCellValue('Total Quantity');
    sheet.cell(CellIndex.indexByString('E3')).value = TextCellValue('Total Value');
    
    for (var col in ['A3', 'B3', 'C3', 'D3', 'E3']) {
      sheet.cell(CellIndex.indexByString(col)).cellStyle = headerStyle;
    }
    
    sheet.setColumnWidth(0, 20);
    sheet.setColumnWidth(1, 15);
    sheet.setColumnWidth(2, 15);
    sheet.setColumnWidth(3, 15);
    sheet.setColumnWidth(4, 18);
    
    final layout = currentTransactionData!['layout'] ?? [];
    final scannedData = currentTransactionData!['scannedData'] ?? {};
    
    int row = 4;
    double grandTotal = 0;
    int totalItems = 0;
    int totalQty = 0;
    
    for (var section in layout) {
      String sectionName = section['name'] ?? '';
      String position = 'X:${section['x']}, Y:${section['y']}';
      
      int itemCount = 0;
      int sectionQty = 0;
      double sectionValue = 0;
      
      if (scannedData[sectionName] != null) {
        List items = scannedData[sectionName];
        itemCount = items.length;
        
        for (var item in items) {
          int qty = int.tryParse(item['qty']?.toString() ?? '0') ?? 0;
          double rate = (item['rate'] is num) ? (item['rate'] as num).toDouble() : 0.0;
          sectionQty += qty;
          sectionValue += rate * qty;
        }
      }
      
      sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(sectionName);
      sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(position);
      sheet.cell(CellIndex.indexByString('C$row')).value = IntCellValue(itemCount);
      sheet.cell(CellIndex.indexByString('D$row')).value = IntCellValue(sectionQty);
      sheet.cell(CellIndex.indexByString('E$row')).value = DoubleCellValue(sectionValue);
      
      grandTotal += sectionValue;
      totalItems += itemCount;
      totalQty += sectionQty;
      row++;
    }
    
    var totalStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.grey200,
    );
    
    sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue('TOTAL');
    sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue('');
    sheet.cell(CellIndex.indexByString('C$row')).value = IntCellValue(totalItems);
    sheet.cell(CellIndex.indexByString('D$row')).value = IntCellValue(totalQty);
    sheet.cell(CellIndex.indexByString('E$row')).value = DoubleCellValue(grandTotal);
    
    for (var col in ['A$row', 'B$row', 'C$row', 'D$row', 'E$row']) {
      sheet.cell(CellIndex.indexByString(col)).cellStyle = totalStyle;
    }
  }

  Future<void> _createConsolidationReport(Excel excel) async {
    var sheet = excel['CONSOLIDATION'];
    
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('G1'));
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('CONSOLIDATION REPORT');
    sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
      bold: true,
      fontSize: 14,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    var headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.grey200,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue('SECTION');
    sheet.cell(CellIndex.indexByString('B2')).value = TextCellValue('CODE');
    sheet.cell(CellIndex.indexByString('C2')).value = TextCellValue('DEPARTMENT');
    sheet.cell(CellIndex.indexByString('D2')).value = TextCellValue('ITEM NAME');
    sheet.cell(CellIndex.indexByString('E2')).value = TextCellValue('RATE');
    sheet.cell(CellIndex.indexByString('F2')).value = TextCellValue('QTY');
    sheet.cell(CellIndex.indexByString('G2')).value = TextCellValue('AMOUNT');
    
    for (var col in ['A2', 'B2', 'C2', 'D2', 'E2', 'F2', 'G2']) {
      sheet.cell(CellIndex.indexByString(col)).cellStyle = headerStyle;
    }
    
    sheet.setColumnWidth(0, 15);
    sheet.setColumnWidth(1, 18);
    sheet.setColumnWidth(2, 18);
    sheet.setColumnWidth(3, 40);
    sheet.setColumnWidth(4, 12);
    sheet.setColumnWidth(5, 10);
    sheet.setColumnWidth(6, 15);
    
    Map<String, Map<String, dynamic>> consolidatedItems = {};
    final scannedData = currentTransactionData!['scannedData'] ?? {};
    
    scannedData.forEach((sectionName, items) {
      if (items is List) {
        for (var item in items) {
          String scanCode = item['scanCode']?.toString() ?? item['code']?.toString() ?? '';
          
          if (scanCode.isNotEmpty) {
            if (consolidatedItems.containsKey(scanCode)) {
              int existingQty = consolidatedItems[scanCode]!['qty'];
              int newQty = int.tryParse(item['qty']?.toString() ?? '0') ?? 0;
              consolidatedItems[scanCode]!['qty'] = existingQty + newQty;
              consolidatedItems[scanCode]!['sections'].add(sectionName);
            } else {
              consolidatedItems[scanCode] = {
                'scanCode': scanCode,
                'code': item['code'] ?? '',
                'department': item['department'] ?? '',
                'name': item['name'] ?? '',
                'rate': (item['rate'] is num) ? (item['rate'] as num).toDouble() : 0.0,
                'qty': int.tryParse(item['qty']?.toString() ?? '0') ?? 0,
                'sections': [sectionName],
              };
            }
          }
        }
      }
    });
    
    var sortedItems = consolidatedItems.values.toList()
      ..sort((a, b) {
        int deptCompare = a['department'].toString().compareTo(b['department'].toString());
        if (deptCompare != 0) return deptCompare;
        return a['name'].toString().compareTo(b['name'].toString());
      });
    
    int row = 3;
    for (var item in sortedItems) {
      String sections = (item['sections'] as List).join(', ');
      sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(sections);
      sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(item['code']);
      sheet.cell(CellIndex.indexByString('C$row')).value = TextCellValue(item['department']);
      sheet.cell(CellIndex.indexByString('D$row')).value = TextCellValue(item['name']);
      sheet.cell(CellIndex.indexByString('E$row')).value = DoubleCellValue(item['rate']);
      sheet.cell(CellIndex.indexByString('F$row')).value = IntCellValue(item['qty']);
      sheet.cell(CellIndex.indexByString('G$row')).value = DoubleCellValue(item['rate'] * item['qty']);
      row++;
    }
  }

  Future<void> _createTotalStockReport(Excel excel) async {
    var sheet = excel['TOTAL STOCK'];
    
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('C1'));
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('TOTAL STOCK LIST');
    sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
      bold: true,
      fontSize: 14,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    var headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.grey200,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    
    sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue('DEPARTMENT');
    sheet.cell(CellIndex.indexByString('B3')).value = TextCellValue('CODE');
    sheet.cell(CellIndex.indexByString('C3')).value = TextCellValue('TOTAL QTY');
    
    for (var col in ['A3', 'B3', 'C3']) {
      sheet.cell(CellIndex.indexByString(col)).cellStyle = headerStyle;
    }
    
    sheet.setColumnWidth(0, 20);
    sheet.setColumnWidth(1, 20);
    sheet.setColumnWidth(2, 15);
    
    Map<String, Map<String, int>> departmentCodeMap = {};
    final scannedData = currentTransactionData!['scannedData'] ?? {};
    
    scannedData.forEach((sectionName, items) {
      if (items is List) {
        for (var item in items) {
          String dept = item['department'] ?? '';
          String code = item['code'] ?? '';
          int qty = int.tryParse(item['qty']?.toString() ?? '0') ?? 0;
          
          if (!departmentCodeMap.containsKey(dept)) {
            departmentCodeMap[dept] = {};
          }
          
          departmentCodeMap[dept]![code] = (departmentCodeMap[dept]![code] ?? 0) + qty;
        }
      }
    });
    
    int row = 4;
    var sortedDepts = departmentCodeMap.keys.toList()..sort();
    
    for (var dept in sortedDepts) {
      var codes = departmentCodeMap[dept]!;
      var sortedCodes = codes.keys.toList()..sort();
      
      for (var code in sortedCodes) {
        sheet.cell(CellIndex.indexByString('A$row')).value = TextCellValue(dept);
        sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(code);
        sheet.cell(CellIndex.indexByString('C$row')).value = IntCellValue(codes[code]!);
        row++;
      }
    }
  }

  // Add this method to check if all sections are completed
  bool _areAllSectionsCompleted() {
    if (currentTransactionData == null) return false;
    
    final sections = currentTransactionData!['sections'];
    
    // Safely check if sections exists and is a Map
    if (sections == null || sections is! Map) {
      //print('⚠️ Sections is null or not a Map: ${sections.runtimeType}');
      return false;
    }
    
    if (sections.isEmpty) return false;
    
    for (var sectionStatus in sections.values) {
      if (sectionStatus is Map) {
        if (sectionStatus['status'] != 'completed') {
          return false;
        }
      } else {
        //print('⚠️ Section status is not a Map: ${sectionStatus.runtimeType}');
        return false;
      }
    }
    
    return true;
  }

  // Add this method to calculate department totals
  // Map<String, double> _calculateDepartmentTotals() {
  //   Map<String, double> departmentTotals = {};
    
  //   final scannedData = currentTransactionData!['scannedData'] ?? {};
    
  //   scannedData.forEach((sectionName, items) {
  //     if (items is List) {
  //       for (var item in items) {
  //         String dept = item['department'] ?? '';
  //         double rate = (item['rate'] is num) ? (item['rate'] as num).toDouble() : 0.0;
  //         int qty = int.tryParse(item['qty']?.toString() ?? '0') ?? 0;
  //         double amount = rate * qty;
          
  //         departmentTotals[dept] = (departmentTotals[dept] ?? 0) + amount;
  //       }
  //     }
  //   });
    
  //   return departmentTotals;
  // }
  Map<String, double> _calculateDepartmentTotals() {
    Map<String, double> departmentTotals = {};
    
    final scannedData = currentTransactionData!['scannedData'];
    
    if (scannedData == null || scannedData is! Map) {
      //print('⚠️ ScannedData is null or not a Map');
      return departmentTotals;
    }
    
    scannedData.forEach((sectionName, items) {
      if (items is List) {
        for (var item in items) {
          if (item is Map) {
            String dept = item['department']?.toString() ?? '';
            double rate = 0.0;
            int qty = 0;
            
            // Safely parse rate
            if (item['rate'] != null) {
              if (item['rate'] is num) {
                rate = (item['rate'] as num).toDouble();
              } else if (item['rate'] is String) {
                rate = double.tryParse(item['rate']) ?? 0.0;
              }
            }
            
            // Safely parse qty
            if (item['qty'] != null) {
              if (item['qty'] is int) {
                qty = item['qty'];
              } else if (item['qty'] is String) {
                qty = int.tryParse(item['qty']) ?? 0;
              } else if (item['qty'] is double) {
                qty = (item['qty'] as double).toInt();
              }
            }
            
            double amount = rate * qty;
            
            if (dept.isNotEmpty) {
              departmentTotals[dept] = (departmentTotals[dept] ?? 0) + amount;
            }
          }
        }
      }
    });
    
    return departmentTotals;
  }

  // Add this method to close the transaction
  Future<void> _closeTransaction() async {
    try {
      // Show confirmation
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.lock, color: Colors.red, size: 28),
              SizedBox(width: 12),
              Text('Close Transaction?'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Are you sure you want to close this transaction?'),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.red.shade700, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This will finalize all data and lock the transaction permanently.',
                        style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Close Transaction'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      setState(() => isGenerating = true);

      // Calculate department totals
      final departmentTotals = _calculateDepartmentTotals();

      // Call API to close transaction
      final url = '${AppConfig.baseUrl}transactions/${widget.transactionId}/complete';
      
      final payload = {
        'status': 'completed',
        'departmentTotal': departmentTotals,
        'completedAt': DateTime.now().toIso8601String(),
      };

      final result = await _apiService.putRequest(url, payload);

      setState(() => isGenerating = false);

      if (result != null) {
        // Update local state immediately
        setState(() {
          if (currentTransactionData != null) {
            currentTransactionData!['status'] = 'completed';
            currentTransactionData!['departmentTotal'] = departmentTotals;
            currentTransactionData!['completedAt'] = DateTime.now().toIso8601String();
          }
          isGenerating = false;
        });
        
        _showSuccessSnackBar('Transaction closed successfully!');
        
        // Recalculate tab data with updated state
        _calculateTabData();
        
      } else {
        throw Exception('Failed to close transaction');
      }
    } catch (e) {
      setState(() => isGenerating = false);
      _showErrorSnackBar('Failed to close transaction: ${e.toString()}');
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Transaction Reports', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color.fromARGB(255, 3, 25, 55),
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: Colors.white.withOpacity(0.2),
            height: 1,
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : currentTransactionData == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                      const SizedBox(height: 16),
                      const Text('Failed to load transaction data'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchTransactionData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCompanyInfoCard(),
                      const SizedBox(height: 24),
                      _buildReportsSection(),
                      const SizedBox(height: 24),
                      if (currentTransactionData != null) ...[
                        _buildStatisticsCard(),
                        const SizedBox(height: 24),
                      ],
                      _buildGenerateButton(),
                      const SizedBox(height: 16),
                      _buildInfoBox(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildCompanyInfoCard() {
    // Safely extract values with null checks and type casting
    String transactionId = '';
    String contactPerson = 'N/A';
    String createdAt = 'N/A';
    String status = 'N/A';
    
    try {
      if (currentTransactionData != null) {
        // Transaction ID
        if (currentTransactionData!['id'] != null) {
          transactionId = currentTransactionData!['id'].toString();
        }
        
        // Contact Person
        if (currentTransactionData!['contactPerson'] != null) {
          contactPerson = currentTransactionData!['contactPerson'].toString();
        }
        
        // Created At
        if (currentTransactionData!['createdAt'] != null) {
          final createdAtData = currentTransactionData!['createdAt'];
          
          // Handle Firestore Timestamp format
          if (createdAtData is Map && createdAtData['_seconds'] != null) {
            final seconds = createdAtData['_seconds'];
            final milliseconds = (seconds is int ? seconds : int.tryParse(seconds.toString()) ?? 0) * 1000;
            final dateTime = DateTime.fromMillisecondsSinceEpoch(milliseconds);
            createdAt = DateFormat('MMM dd, yyyy HH:mm').format(dateTime);
          } 
          // Handle ISO string format
          else if (createdAtData is String) {
            try {
              final dateTime = DateTime.parse(createdAtData);
              createdAt = DateFormat('MMM dd, yyyy HH:mm').format(dateTime);
            } catch (e) {
              createdAt = createdAtData;
            }
          }
        }
        
        // Status
        if (currentTransactionData!['status'] != null) {
          status = currentTransactionData!['status'].toString().toUpperCase();
        }
      }
    } catch (e) {
      //print('⚠️ Error in _buildCompanyInfoCard: $e');
    }
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 3, 25, 55),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.business, size: 28, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.companyName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Transaction ID: $transactionId',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.grey.shade200),
            const SizedBox(height: 12),
            _buildInfoRow('Contact Person', contactPerson),
            _buildInfoRow('Created At', createdAt),
            _buildInfoRow('Status', status),
          ],
        ),
      ),
    );
  }

  // Widget _buildTabsCard() {
  //   return Card(
  //     elevation: 2,
  //     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  //     child: Column(
  //       children: [
  //         // Tab bar
  //         Container(
  //           decoration: BoxDecoration(
  //             color: Colors.grey.shade50,
  //             borderRadius: const BorderRadius.only(
  //               topLeft: Radius.circular(16),
  //               topRight: Radius.circular(16),
  //             ),
  //           ),
  //           child: TabBar(
  //             controller: _tabController,
  //             labelColor: const Color.fromARGB(255, 3, 25, 55),
  //             unselectedLabelColor: Colors.grey.shade600,
  //             indicatorColor: const Color.fromARGB(255, 3, 25, 55),
  //             indicatorWeight: 3,
  //             labelStyle: const TextStyle(
  //               fontSize: 15,
  //               fontWeight: FontWeight.bold,
  //             ),
  //             unselectedLabelStyle: const TextStyle(
  //               fontSize: 15,
  //               fontWeight: FontWeight.normal,
  //             ),
  //             tabs: [
  //               Tab(
  //                 child: Row(
  //                   mainAxisAlignment: MainAxisAlignment.center,
  //                   children: [
  //                     FaIcon(FontAwesomeIcons.layerGroup, size: 16),
  //                     const SizedBox(width: 8),
  //                     Text('DEPARTMENT'),
  //                     const SizedBox(width: 4),
  //                     Container(
  //                       padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  //                       decoration: BoxDecoration(
  //                         color: const Color.fromARGB(255, 3, 25, 55).shade100,
  //                         borderRadius: BorderRadius.circular(10),
  //                       ),
  //                       child: Text(
  //                         '${departmentData.length}',
  //                         style: TextStyle(fontSize: 11, color: const Color.fromARGB(255, 3, 25, 55).shade700),
  //                       ),
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //               Tab(
  //                 child: Row(
  //                   mainAxisAlignment: MainAxisAlignment.center,
  //                   children: [
  //                     FaIcon(FontAwesomeIcons.mapLocationDot, size: 16),
  //                     const SizedBox(width: 8),
  //                     Text('SECTION'),
  //                     const SizedBox(width: 4),
  //                     Container(
  //                       padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  //                       decoration: BoxDecoration(
  //                         color: Colors.teal.shade100,
  //                         borderRadius: BorderRadius.circular(10),
  //                       ),
  //                       child: Text(
  //                         '${sectionData.length}',
  //                         style: TextStyle(fontSize: 11, color: Colors.teal.shade700),
  //                       ),
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //               Tab(
  //                 child: Row(
  //                   mainAxisAlignment: MainAxisAlignment.center,
  //                   children: [
  //                     FaIcon(FontAwesomeIcons.triangleExclamation, size: 16),
  //                     const SizedBox(width: 8),
  //                     Text('MISSING'),
  //                     const SizedBox(width: 4),
  //                     Container(
  //                       padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  //                       decoration: BoxDecoration(
  //                         color: Colors.orange.shade100,
  //                         borderRadius: BorderRadius.circular(10),
  //                       ),
  //                       child: Text(
  //                         '${missingItemsData.length}',
  //                         style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
  //                       ),
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //             ],
  //           ),
  //         ),
  //         // Tab views
  //         SizedBox(
  //           height: 400,
  //           child: TabBarView(
  //             controller: _tabController,
  //             children: [
  //               _buildDepartmentTab(),
  //               _buildSectionTab(),
  //               _buildMissingTab(),
  //             ],
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Color _getShade(Color color, int shade) {
  if (color is MaterialColor) {
    return color[shade] ?? color;
  }
  
  // Fallback mapping for common colors
  if (color == const Color.fromARGB(255, 3, 25, 55)) {
    return shade == 400 ? const Color.fromARGB(255, 3, 25, 55) : const Color.fromARGB(255, 3, 25, 55);
  } else if (color == Colors.teal) {
    return shade == 400 ? Colors.teal.shade400 : Colors.teal.shade700;
  } else if (color == Colors.orange) {
    return shade == 400 ? Colors.orange.shade400 : Colors.orange.shade700;
  } else if (color == Colors.green) {
    return shade == 400 ? Colors.green.shade400 : Colors.green.shade700;
  } else if (color == Colors.purple) {
    return shade == 400 ? Colors.purple.shade400 : Colors.purple.shade700;
  }
  
  return color; // Fallback
}


Widget _buildReportsSection() {
  return Column(
    children: [
      _buildDepartmentAccordion(),
      const SizedBox(height: 16),
      _buildSectionAccordion(),
      const SizedBox(height: 16),
      _buildMissingAccordion(),
    ],
  );
}


// Department Accordion
Widget _buildDepartmentAccordion() {
  double totalCurrent = departmentData.fold(0, (sum, item) => sum + (item['totalAmount'] as double));
  double totalPrevious = departmentData.fold(0, (sum, item) => sum + (item['prevTotal'] as double));

  return Card(
    elevation: 3,
    shadowColor: const Color.fromARGB(255, 3, 25, 55).withOpacity(0.3),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        childrenPadding: const EdgeInsets.only(bottom: 16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color.fromARGB(255, 3, 25, 55), const Color.fromARGB(255, 3, 25, 55)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color.fromARGB(255, 3, 25, 55).withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const FaIcon(FontAwesomeIcons.layerGroup, color: Colors.white, size: 20),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'DEPARTMENT SUMMARY',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${departmentData.length} departments • \$${totalCurrent.toStringAsFixed(2)} total',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        children: [
          if (departmentData.isEmpty)
            _buildEmptyState(
              icon: FontAwesomeIcons.boxOpen,
              message: 'No department data available',
              color: const Color.fromARGB(255, 3, 25, 55),
            )
          else ...[
            // Summary cards row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _buildSummaryMiniCard(
                      'Current Total',
                      '\$${totalCurrent.toStringAsFixed(2)}',
                      Icons.attach_money,
                      const Color.fromARGB(255, 3, 25, 55),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryMiniCard(
                      'Previous Total',
                      previousTransactionData == null 
                        ? 'N/A' 
                        : '\$${totalPrevious.toStringAsFixed(2)}',
                      Icons.history,
                      Colors.purple,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Department cards
            ...departmentData.map((item) => _buildDepartmentCard(item)).toList(),
            // Grand total card
            _buildGrandTotalCard(totalCurrent, totalPrevious, const Color.fromARGB(255, 3, 25, 55)),
          ],
        ],
      ),
    ),
  );
}

// Section Accordion
Widget _buildSectionAccordion() {
  double total = sectionData.fold(0, (sum, item) => sum + (item['totalAmount'] as double));

  return Card(
    elevation: 3,
    shadowColor: Colors.teal.withOpacity(0.3),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        childrenPadding: const EdgeInsets.only(bottom: 16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal.shade400, Colors.teal.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.teal.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const FaIcon(FontAwesomeIcons.mapLocationDot, color: Colors.white, size: 20),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SECTION BREAKDOWN',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${sectionData.length} sections • \$${total.toStringAsFixed(2)} total',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        children: [
          if (sectionData.isEmpty)
            _buildEmptyState(
              icon: FontAwesomeIcons.mapLocationDot,
              message: 'No section data available',
              color: Colors.teal,
            )
          else ...[
            // Grand total hero card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.teal.shade400, Colors.teal.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.teal.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.analytics, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'GRAND TOTAL',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '\$${total.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Section cards
            ...sectionData.map((item) => _buildSectionCard(item)).toList(),
          ],
        ],
      ),
    ),
  );
}

// Missing Items Accordion
Widget _buildMissingAccordion() {
  return Card(
    elevation: 3,
    shadowColor: Colors.orange.withOpacity(0.3),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        childrenPadding: const EdgeInsets.only(bottom: 16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orange.shade400, Colors.orange.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const FaIcon(FontAwesomeIcons.triangleExclamation, color: Colors.white, size: 20),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'MISSING ITEMS',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${missingItemsData.length} manually added items',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        children: [
          if (missingItemsData.isEmpty)
            _buildEmptyState(
              icon: FontAwesomeIcons.circleCheck,
              message: 'All items scanned successfully!',
              subtitle: 'No manually added items',
              color: Colors.green,
              isSuccess: true,
            )
          else ...[
            // Alert banner
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200, width: 1.5),
                ),
                child: Row(
                  children: [
                    FaIcon(FontAwesomeIcons.triangleExclamation, 
                      color: Colors.orange.shade700, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${missingItemsData.length} Items Not Found in Database',
                            style: TextStyle(
                              color: Colors.orange.shade900,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'These items were manually entered during scanning',
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Missing item cards
            ...missingItemsData.map((item) => _buildMissingItemCard(item)).toList(),
          ],
        ],
      ),
    ),
  );
}

// Helper Widgets

Widget _buildEmptyState({
  required IconData icon,
  required String message,
  String? subtitle,
  required Color color,
  bool isSuccess = false,
}) {
  return Padding(
    padding: const EdgeInsets.all(32),
    child: Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: _getShade(color, 400)),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    ),
  );
}

Widget _buildSummaryMiniCard(String label, String value, IconData icon, Color color) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.2), width: 1.5),
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(0.1),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _getShade(color, 700),
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

Widget _buildDepartmentCard(Map<String, dynamic> item) {
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color.fromARGB(255, 3, 25, 55), width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.08),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top row: Icon + Department name
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 3, 25, 55),
                borderRadius: BorderRadius.circular(10),
              ),
              child: FaIcon(FontAwesomeIcons.building, 
                color: const Color.fromARGB(255, 3, 25, 55), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item['department'],
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Bottom section: Amounts in a column layout
        Row(
          children: [
            // Current amount
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${item['totalAmount'].toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color.fromARGB(255, 3, 25, 55),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            
            // Previous amount (if exists)
            if (previousTransactionData != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Previous',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\$${item['prevTotal'].toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // Difference badge
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: (item['totalAmount'] - item['prevTotal']) >= 0 
                    ? Colors.green.shade50 
                    : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Icon(
                      (item['totalAmount'] - item['prevTotal']) >= 0 
                        ? Icons.arrow_upward 
                        : Icons.arrow_downward,
                      size: 14,
                      color: (item['totalAmount'] - item['prevTotal']) >= 0 
                        ? Colors.green.shade700 
                        : Colors.red.shade700,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '\$${(item['totalAmount'] - item['prevTotal']).abs().toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: (item['totalAmount'] - item['prevTotal']) >= 0 
                          ? Colors.green.shade700 
                          : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

Widget _buildSectionCard(Map<String, dynamic> item) {
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.08),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: FaIcon(FontAwesomeIcons.mapMarkerAlt, color: Colors.teal.shade600, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['section'],
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Section Total',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
        Text(
          '\$${item['totalAmount'].toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.teal.shade700,
          ),
        ),
      ],
    ),
  );
}

Widget _buildMissingItemCard(Map<String, dynamic> item) {
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.orange.shade100, width: 1.5),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.08),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                item['section'],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade700,
                ),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 3, 25, 55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                item['department'],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color.fromARGB(255, 3, 25, 55),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          item['name'],
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FaIcon(FontAwesomeIcons.barcode, size: 12, color: Colors.grey.shade500),
            const SizedBox(width: 6),
            Text(
              item['scanCode'],
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(color: Colors.grey.shade200, height: 1),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildItemDetail('Rate', '\$${item['rate'].toStringAsFixed(2)}', Colors.green),
            _buildItemDetail('Qty', '${item['qty']}', const Color.fromARGB(255, 3, 25, 55)),
            _buildItemDetail('Total', '\$${(item['rate'] * item['qty']).toStringAsFixed(2)}', Colors.purple),
          ],
        ),
      ],
    ),
  );
}

Widget _buildItemDetail(String label, String value, Color color) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: Colors.grey.shade600,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: _getShade(color, 700),
        ),
      ),
    ],
  );
}

Widget _buildGrandTotalCard(double current, double previous, Color color) {
  return Container(
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.grey.shade100, Colors.grey.shade200],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _getShade(color, 200), width: 2),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.functions, color: _getShade(color, 700), size: 24),
            const SizedBox(width: 12),
            Text(
              'GRAND TOTAL',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '\$${current.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _getShade(color, 700),
              ),
            ),
            if (previousTransactionData != null) ...[
              const SizedBox(height: 2),
              Text(
                'Prev: \$${previous.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}
  // Widget _buildStatisticsCard() {
  //   final sections = currentTransactionData?['sections'] ?? {};
  //   final totalSections = sections.length;
  //   final completedSections = sections.values.where((s) => s['status'] == 'completed').length;
    
  //   return Card(
  //     elevation: 2,
  //     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  //     color: const Color.fromARGB(255, 3, 25, 55).shade50,
  //     child: Padding(
  //       padding: const EdgeInsets.all(20),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Row(
  //             children: [
  //               Container(
  //                 padding: const EdgeInsets.all(8),
  //                 decoration: BoxDecoration(
  //                   color: const Color.fromARGB(255, 3, 25, 55).shade100,
  //                   borderRadius: BorderRadius.circular(10),
  //                 ),
  //                 child: Icon(Icons.analytics, color: const Color.fromARGB(255, 3, 25, 55).shade700, size: 20),
  //               ),
  //               const SizedBox(width: 12),
  //               const Text(
  //                 'Quick Statistics',
  //                 style: TextStyle(
  //                   fontSize: 16,
  //                   fontWeight: FontWeight.bold,
  //                 ),
  //               ),
  //             ],
  //           ),
  //           const SizedBox(height: 16),
            
  //           // Section completion progress
  //           Container(
  //             padding: const EdgeInsets.all(12),
  //             decoration: BoxDecoration(
  //               color: Colors.white,
  //               borderRadius: BorderRadius.circular(8),
  //               border: Border.all(color: const Color.fromARGB(255, 3, 25, 55).shade200),
  //             ),
  //             child: Column(
  //               crossAxisAlignment: CrossAxisAlignment.start,
  //               children: [
  //                 Row(
  //                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //                   children: [
  //                     Text(
  //                       'Section Progress',
  //                       style: TextStyle(
  //                         fontSize: 14,
  //                         fontWeight: FontWeight.bold,
  //                         color: Colors.grey.shade800,
  //                       ),
  //                     ),
  //                     Text(
  //                       '$completedSections / $totalSections',
  //                       style: TextStyle(
  //                         fontSize: 14,
  //                         fontWeight: FontWeight.bold,
  //                         color: const Color.fromARGB(255, 3, 25, 55).shade700,
  //                       ),
  //                     ),
  //                   ],
  //                 ),
  //                 const SizedBox(height: 8),
  //                 ClipRRect(
  //                   borderRadius: BorderRadius.circular(4),
  //                   child: LinearProgressIndicator(
  //                     value: totalSections > 0 ? completedSections / totalSections : 0,
  //                     backgroundColor: Colors.grey.shade300,
  //                     valueColor: AlwaysStoppedAnimation<Color>(
  //                       completedSections == totalSections ? Colors.green : const Color.fromARGB(255, 3, 25, 55),
  //                     ),
  //                     minHeight: 6,
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           ),
            
  //           const SizedBox(height: 12),
  //           _buildStatRow('Total Sections', _getTotalSections().toString(), Icons.map),
  //           _buildStatRow('Completed Sections', completedSections.toString(), Icons.check_circle, color: Colors.green),
  //           _buildStatRow('Pending Sections', (totalSections - completedSections).toString(), Icons.pending, color: Colors.orange),
  //           _buildStatRow('Total Items', _getTotalItems().toString(), Icons.inventory_2),
  //           _buildStatRow('Manual Entries', _getManualEntries().toString(), Icons.edit, color: Colors.orange),
  //           _buildStatRow('Scanned Entries', _getScannedEntries().toString(), Icons.qr_code_scanner, color: Colors.green),
  //           if (previousTransactionData != null)
  //             _buildStatRow('Previous Transaction', 'Available', Icons.history, color: const Color.fromARGB(255, 3, 25, 55))
  //           else
  //             _buildStatRow('Previous Transaction', 'None (First transaction)', Icons.info_outline, color: Colors.orange, isWarning: true),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  Widget _buildStatisticsCard() {
    final sections = currentTransactionData?['sections'];
    int totalSections = 0;
    int completedSections = 0;
    
    // Safely handle sections
    if (sections != null && sections is Map) {
      totalSections = sections.length;
      completedSections = sections.values.where((s) {
        if (s is Map) {
          return s['status'] == 'completed';
        }
        return false;
      }).length;
    }
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color.fromARGB(255, 3, 25, 55),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 3, 25, 55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.analytics, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Quick Statistics',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Section completion progress
            if (totalSections > 0) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color.fromARGB(255, 3, 25, 55)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Section Progress',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        Text(
                          '$completedSections / $totalSections',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: const Color.fromARGB(255, 3, 25, 55),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: totalSections > 0 ? completedSections / totalSections : 0,
                        backgroundColor: Colors.grey.shade300,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          completedSections == totalSections ? Colors.green : const Color.fromARGB(255, 3, 25, 55),
                        ),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            
            _buildStatRow('Total Sections', totalSections.toString(), Icons.map),
            _buildStatRow('Completed Sections', completedSections.toString(), Icons.check_circle, color: Colors.green),
            _buildStatRow('Pending Sections', (totalSections - completedSections).toString(), Icons.pending, color: Colors.orange),
            _buildStatRow('Total Items', _getTotalItems().toString(), Icons.inventory_2),
            _buildStatRow('Manual Entries', _getManualEntries().toString(), Icons.edit, color: Colors.orange),
            _buildStatRow('Scanned Entries', _getScannedEntries().toString(), Icons.qr_code_scanner, color: Colors.green),
            if (previousTransactionData != null)
              _buildStatRow('Previous Transaction', 'Available', Icons.history, color: const Color.fromARGB(255, 3, 25, 55))
            else
              _buildStatRow('Previous Transaction', 'None (First transaction)', Icons.info_outline, color: Colors.orange, isWarning: true),
          ],
        ),
      ),
    );
  }

  Widget _buildGenerateButton() {
    final allSectionsCompleted = _areAllSectionsCompleted();
    final isTransactionCompleted = currentTransactionData?['status'] == 'completed';

    return Column(
      children: [
        // Show Close Transaction button if all sections completed but transaction not closed
        if (allSectionsCompleted && !isTransactionCompleted) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200, width: 2),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'All Sections Completed!',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'You can now close this transaction',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: isGenerating ? null : _closeTransaction,
            icon: Icon(
              isGenerating ? FontAwesomeIcons.spinner : FontAwesomeIcons.lock,
              size: 20,
            ),
            label: Text(
              isGenerating ? 'Closing Transaction...' : 'Close Transaction',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3,
            ),
          ),
          const SizedBox(height: 16),
        ],
        
        // Excel Report Button
        ElevatedButton.icon(
          onPressed: isGenerating ? null : _generateExcelReport,
          icon: Icon(
            isGenerating ? FontAwesomeIcons.spinner : FontAwesomeIcons.fileExcel,
            size: 20,
          ),
          label: Text(
            isGenerating ? 'Generating Report...' : 'Generate Excel Report',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 3,
          ),
        ),
        
        // Show completion badge if transaction is completed
        if (isTransactionCompleted) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color.fromARGB(255, 3, 25, 55), width: 2),
            ),
            child: Row(
              children: [
                Icon(Icons.verified, color: Colors.green, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Transaction Completed',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: const Color.fromARGB(255, 3, 25, 55),
                        ),
                      ),
                      // Safely handle completedAt
                      Builder(
                        builder: (context) {
                          String completedAtStr = '';
                          try {
                            if (currentTransactionData?['completedAt'] != null) {
                              final completedAtData = currentTransactionData!['completedAt'];
                              
                              if (completedAtData is String) {
                                final dateTime = DateTime.parse(completedAtData);
                                completedAtStr = DateFormat('MMM dd, yyyy HH:mm').format(dateTime);
                              } else if (completedAtData is Map && completedAtData['_seconds'] != null) {
                                final seconds = completedAtData['_seconds'];
                                final milliseconds = (seconds is int ? seconds : int.tryParse(seconds.toString()) ?? 0) * 1000;
                                final dateTime = DateTime.fromMillisecondsSinceEpoch(milliseconds);
                                completedAtStr = DateFormat('MMM dd, yyyy HH:mm').format(dateTime);
                              }
                            }
                          } catch (e) {
                            //print('⚠️ Error parsing completedAt: $e');
                          }
                          
                          if (completedAtStr.isNotEmpty) {
                            return Column(
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  'Closed on $completedAtStr',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: const Color.fromARGB(255, 3, 25, 55),
                                  ),
                                ),
                              ],
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueAccent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color.fromARGB(255, 3, 25, 55)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'The Excel file will contain all 5 reports in separate sheets',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon, {Color? color, bool isWarning = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: color ?? Colors.white,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isWarning ? Colors.orange : (color ?? Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  int _getTotalSections() {
    if (currentTransactionData == null) return 0;
    
    final sections = currentTransactionData!['sections'];
    if (sections == null || sections is! Map) return 0;
    
    return sections.keys.length;
  }

  int _getTotalItems() {
    if (currentTransactionData == null) return 0;
    int count = 0;
    
    final scannedData = currentTransactionData!['scannedData'];
    if (scannedData == null || scannedData is! Map) return 0;
    
    scannedData.forEach((key, items) {
      if (items != null && items is List) {
        count += items.length;
      }
    });
    
    return count;
  }

  int _getManualEntries() {
    if (currentTransactionData == null) return 0;
    int count = 0;
    
    final scannedData = currentTransactionData!['scannedData'];
    if (scannedData == null || scannedData is! Map) return 0;
    
    scannedData.forEach((key, items) {
      if (items != null && items is List) {
        count += items.where((item) {
          if (item == null || item is! Map) return false;
          return item['__source'] == 'manual';
        }).length;
      }
    });
    
    return count;
  }

  int _getScannedEntries() {
    if (currentTransactionData == null) return 0;
    int count = 0;
    
    final scannedData = currentTransactionData!['scannedData'];
    if (scannedData == null || scannedData is! Map) return 0;
    
    scannedData.forEach((key, items) {
      if (items != null && items is List) {
        count += items.where((item) {
          if (item == null || item is! Map) return false;
          return item['__source'] == 'scanner';
        }).length;
      }
    });
    
    return count;
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 16),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}