import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:convert';
import 'dart:math' as math;

import 'package:countx/drawer.dart';

class StockManagementScreen extends StatefulWidget {
  final String allocatedSection;
  
  const StockManagementScreen({
    Key? key,
    required this.allocatedSection,
  }) : super(key: key);

  @override
  State<StockManagementScreen> createState() => _StockManagementScreenState();
}

class _StockManagementScreenState extends State<StockManagementScreen> {
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
  
  // Controllers
  final TextEditingController scanCodeController = TextEditingController();
  final TextEditingController codeController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController departmentController = TextEditingController();
  final TextEditingController rateController = TextEditingController();
  final TextEditingController quantityController = TextEditingController();
  
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
    loadSavedStock();
    scanCodeController.addListener(_onScanCodeChanged);
  }
  
  @override
  void dispose() {
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

  void _onScanCodeChanged() {
    final inputCode = scanCodeController.text.trim();
    if (inputCode.isNotEmpty) {
      // Check if it matches any scan code
      if (previousStock.containsKey(inputCode)) {
        _fillFormFromStock(inputCode);
      }
    }
  }
  
  Future<void> loadSavedStock() async {
    final prefs = await SharedPreferences.getInstance();
    final savedData = prefs.getString('current_stock_${widget.allocatedSection}');
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
      'current_stock_${widget.allocatedSection}', 
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
                // Excel structure: Scan Code, Item Description, Item Code, Department, Price Group, Qty
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
                
                // Handle price group conversion
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
                if (scanCode.isNotEmpty && 
                    itemCode.isNotEmpty && 
                    department.toLowerCase() == widget.allocatedSection.toLowerCase()) {
                  
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
              content: Text('Excel file uploaded successfully! ${previousStock.length} items loaded for ${widget.allocatedSection}.'),
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
  print('Scanned barcode: $barcode'); // Debug print
  
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
      departmentController.text = widget.allocatedSection;
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
  
  void addOrUpdateStock() {
    if (scanCodeController.text.isNotEmpty && 
        codeController.text.isNotEmpty &&
        nameController.text.isNotEmpty &&
        departmentController.text.isNotEmpty &&
        rateController.text.isNotEmpty &&
        quantityController.text.isNotEmpty) {
      
      final item = StockItem(
        scanCode: scanCodeController.text,
        code: codeController.text,
        name: nameController.text,
        department: departmentController.text,
        rate: double.parse(rateController.text),
        quantity: int.parse(quantityController.text),
      );
      
      setState(() {
        // Use scan code as key for current stock
        currentStock[item.scanCode!] = item;
        if (!departments.contains(item.department)) {
          departments.add(item.department);
        }
      });
      
      saveStock();
      clearForm();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stock item added/updated!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please fill all fields'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  void clearForm() {
    scanCodeController.clear();
    codeController.clear();
    nameController.clear();
    departmentController.text = widget.allocatedSection;
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
                                    print('Scanned barcode: ${barcode.rawValue}'); // Debug print
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
                      labelText: 'Price Group / Rate',
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
                          color: quantityFocusNode.hasFocus ? const Color.fromARGB(255, 3, 25, 55) : Colors.grey,
                          width: quantityFocusNode.hasFocus ? 2 : 1,
                        ),
                      ),
                      helperText: 'Enter current stock quantity',
                      fillColor: quantityFocusNode.hasFocus ? const Color.fromARGB(255, 3, 25, 55) : null,
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
                      color: const Color.fromARGB(255, 3, 25, 55),
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
                          '• Focus automatically moves to quantity for known items',
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
                'Stock Report - ${widget.allocatedSection}',
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
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Stock Management - ${widget.allocatedSection}'),
        backgroundColor: const Color.fromARGB(255, 3, 25, 55),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (lastUpdated != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(
                  'Last Updated: ${DateFormat('HH:mm').format(lastUpdated!)}',
                  style: TextStyle(fontSize: 12),
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
            color: const Color.fromARGB(255, 3, 25, 55),
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                _buildStepIndicator(0, 'Upload', FontAwesomeIcons.upload),
                Expanded(child: Divider(thickness: 2)),
                _buildStepIndicator(1, 'Stock Entry', FontAwesomeIcons.boxOpen),
                Expanded(child: Divider(thickness: 2)),
                _buildStepIndicator(2, 'Comparison', FontAwesomeIcons.chartBar),
                Expanded(child: Divider(thickness: 2)),
                _buildStepIndicator(3, 'Summary', FontAwesomeIcons.chartPie),
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
                _buildComparisonStep(),
                _buildSummaryStep(),
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
                      backgroundColor: Colors.grey,
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  )
                else
                  SizedBox(),
                Row(
                  children: [
                    if (currentStep == 3)
                      ElevatedButton.icon(
                        onPressed: generatePDFReport,
                        icon: FaIcon(FontAwesomeIcons.filePdf, size: 16),
                        label: Text('Generate PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    SizedBox(width: 12),
                    if (currentStep < 3)
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
                          backgroundColor: const Color.fromARGB(255, 3, 25, 55),
                          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: () async {
                          await saveStock();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Stock saved successfully!')),
                          );
                        },
                        icon: FaIcon(FontAwesomeIcons.save, size: 16),
                        label: Text('Save'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
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
                  <rect x="70" y="60" width="60" height="80" fill="#1E90FF" rx="5"/>
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
              'Upload an Excel file with columns:\nScan Code, Item Description, Item Code, Department, Price Group, Qty',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            SizedBox(height: 32),
            
            // Progress indicator
            if (isUploading) ...[
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 3, 25, 55),
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
                  '${previousStock.length} items loaded from ${widget.allocatedSection}',
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
                      color: const Color.fromARGB(255, 3, 25, 55),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• Ensure the Excel file is saved locally on your device\n'
                    '• Try using Google Drive or Dropbox if direct upload fails\n'
                    '• Check that the file format is .xlsx or .xls\n'
                    '• Make sure your internet connection is stable',
                    style: TextStyle(fontSize: 12, color: const Color.fromARGB(255, 3, 25, 55)),
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
    final removed = <String, StockItem>{};
    
    currentStock.forEach((key, item) {
      if (!previousStock.containsKey(key)) {
        added[key] = item;
      } else if (previousStock[key]!.quantity != item.quantity) {
        updated[key] = item;
      }
    });
    
    previousStock.forEach((key, item) {
      if (!currentStock.containsKey(key)) {
        removed[key] = item;
      }
    });
    
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
              SizedBox(width: 8),
              Expanded(
                child: Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        FaIcon(FontAwesomeIcons.minus, color: Colors.red, size: 24),
                        SizedBox(height: 8),
                        Text(
                          '${removed.length}',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red),
                        ),
                        Text('Removed', style: TextStyle(color: Colors.red.shade700)),
                      ],
                    ),
                  ),
                ),
              ),
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
          
          if (removed.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        FaIcon(FontAwesomeIcons.minus, color: Colors.red, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Removed Items',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    ...removed.values.map((item) => ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.red.shade100,
                        child: FaIcon(FontAwesomeIcons.minus, size: 12, color: Colors.red),
                      ),
                      title: Text(item.name),
                      subtitle: Text('Code: ${item.code} | Scan: ${item.scanCode}'),
                      trailing: Text(
                        'Qty: ${item.quantity}',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                    )),
                  ],
                ),
              ),
            ),
          ],
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