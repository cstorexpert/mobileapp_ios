import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:countx/config/config.dart';
import 'package:countx/services/api_services.dart';
import 'package:countx/services/dio_services.dart';

import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';

class User {
  final String id;
  final String username;
  final String email;
  final String role;
  final String contact;
  final String address;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    required this.contact,
    required this.address,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      contact: json['contact']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
    );
  }
}

// Define CanvasShape class first
class CanvasShape {
  String type;
  Offset position;
  Size size;
  Color color;
  String name;
  List<String> assigned;
  String id;
  bool isDragging;
  bool isLocked;

  CanvasShape({
    required this.type,
    required this.position,
    required this.size,
    required this.color,
    required this.name,
    List<String>? assigned,
    String? id,
    this.isDragging = false,
    this.isLocked = false,
  }) : assigned = assigned ?? [],
   id = id ?? DateTime.now().millisecondsSinceEpoch.toString();
  
  CanvasShape clone() {
    return CanvasShape(
      type: type,
      position: Offset(position.dx, position.dy),
      size: Size(size.width, size.height),
      color: Color(color.value),
      name: name,
      assigned: List<String>.from(assigned),
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      isDragging: false,
      isLocked: isLocked,
    );
  }
}

// Define CanvasPainter class
class CanvasPainter extends CustomPainter {
  final List<CanvasShape> shapes;
  final CanvasShape? selectedShape;
  final CanvasShape? hoveredShape;
  final double zoom;
  final Size canvasSize;
  final bool isLongPressMode;

  CanvasPainter(
    this.shapes, 
    this.selectedShape, 
    this.hoveredShape, 
    this.zoom, 
    this.canvasSize,
    this.isLongPressMode,
  );

  @override
  void paint(Canvas canvas, Size size) {
    // Draw canvas background with gradient
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.grey.shade50, Colors.grey.shade100],
      ).createShader(Rect.fromLTWH(0, 0, canvasSize.width * zoom, canvasSize.height * zoom));
    canvas.drawRect(Rect.fromLTWH(0, 0, canvasSize.width * zoom, canvasSize.height * zoom), bgPaint);
    
    // Draw grid
    final gridPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    
    for (double i = 0; i <= canvasSize.width * zoom; i += 50 * zoom) {
      canvas.drawLine(Offset(i, 0), Offset(i, canvasSize.height * zoom), gridPaint);
    }
    for (double i = 0; i <= canvasSize.height * zoom; i += 50 * zoom) {
      canvas.drawLine(Offset(0, i), Offset(canvasSize.width * zoom, i), gridPaint);
    }
    
    canvas.scale(zoom);
    
    // Draw shapes with shadows
    for (var shape in shapes) {
      final isSelected = shape == selectedShape;
      final isHovered = shape == hoveredShape;
      
      // Draw shadow
      if (shape.isDragging || isSelected) {
        final shadowPaint = Paint()
          ..color = Colors.black.withOpacity(0.2)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, shape.isDragging ? 8 : 4);
        
        _drawShapeWithPaint(
          canvas, 
          shape, 
          shadowPaint, 
          Offset(shape.isDragging ? 4 : 2, shape.isDragging ? 4 : 2)
        );
      }
      
      // Main shape paint
      final paint = Paint()
        ..color = shape.color.withOpacity(isHovered ? 0.9 : 1.0)
        ..style = PaintingStyle.fill;

      final borderPaint = Paint()
        ..color = shape.color.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isHovered ? 3 : 2;

      _drawShapeWithPaint(canvas, shape, paint, Offset.zero);
      _drawShapeWithPaint(canvas, shape, borderPaint, Offset.zero);

      // Draw text content
      _drawShapeText(canvas, shape);

      // Draw selection/hover indicator
      if (isSelected) {
        _drawSelectionIndicator(canvas, shape);
      } else if (isHovered) {
        _drawHoverIndicator(canvas, shape);
      }
    }
  }

  void _drawShapeWithPaint(Canvas canvas, CanvasShape shape, Paint paint, Offset offset) {
    switch (shape.type) {
      case 'Square':
      case 'Rectangle':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              shape.position.dx + offset.dx, 
              shape.position.dy + offset.dy, 
              shape.size.width, 
              shape.size.height
            ),
            Radius.circular(8),
          ),
          paint,
        );
        break;
      case 'Circle':
        canvas.drawCircle(
          Offset(
            shape.position.dx + shape.size.width / 2 + offset.dx,
            shape.position.dy + shape.size.height / 2 + offset.dy
          ),
          shape.size.width / 2,
          paint,
        );
        break;
    }
  }

  void _drawShapeText(Canvas canvas, CanvasShape shape) {
    // Draw shape name
    final textPainter = TextPainter(
      text: TextSpan(
        text: shape.name,
        style: TextStyle(
          color: _getContrastColor(shape.color),
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              offset: Offset(1, 1),
              blurRadius: 2,
              color: Colors.black.withOpacity(0.3),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    
    double textX = shape.position.dx + (shape.size.width - textPainter.width) / 2;
    double textY = shape.position.dy + (shape.size.height - textPainter.height) / 2 - 10;
    textPainter.paint(canvas, Offset(textX, textY));

    if (shape.assigned.isNotEmpty) {
      String assignedText;
      if (shape.assigned.length == 1) {
        assignedText = '👤 ${shape.assigned[0]}';
      } else {
        assignedText = '👤 ${shape.assigned[0]} +${shape.assigned.length - 1} more';
      }
      
      final assignedPainter = TextPainter(
        text: TextSpan(
          text: assignedText,
          style: TextStyle(
            color: _getContrastColor(shape.color),
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      assignedPainter.layout();
      double assignedX = shape.position.dx + (shape.size.width - assignedPainter.width) / 2;
      double assignedY = shape.position.dy + (shape.size.height - assignedPainter.height) / 2 + 10;
      assignedPainter.paint(canvas, Offset(assignedX, assignedY));
    }
  }

  void _drawSelectionIndicator(Canvas canvas, CanvasShape shape) {
    final selectionPaint = Paint()
      ..color = shape.isLocked ? Colors.red : const Color.fromARGB(255, 3, 25, 55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    
    if (shape.type == 'Circle') {
      canvas.drawCircle(
        Offset(shape.position.dx + shape.size.width / 2, shape.position.dy + shape.size.height / 2),
        shape.size.width / 2 + 5,
        selectionPaint,
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(shape.position.dx - 5, shape.position.dy - 5, 
                      shape.size.width + 10, shape.size.height + 10),
          Radius.circular(8),
        ),
        selectionPaint,
      );
    }
    
    // Draw resize handles only if not locked and in resize mode
    if (!shape.isLocked) {
      final handlePaint = Paint()
        ..color = const Color.fromARGB(255, 3, 25, 55)
        ..style = PaintingStyle.fill;
      
      final handleBorder = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      
      // Make handles larger for easier interaction
      double handleSize = 10;
      
      List<Offset> handles = [
        Offset(shape.position.dx, shape.position.dy),
        Offset(shape.position.dx + shape.size.width, shape.position.dy),
        Offset(shape.position.dx, shape.position.dy + shape.size.height),
        Offset(shape.position.dx + shape.size.width, shape.position.dy + shape.size.height),
      ];
      
      for (var handle in handles) {
        canvas.drawCircle(handle, handleSize, handlePaint);
        canvas.drawCircle(handle, handleSize, handleBorder);
      }
      
      // Draw corner indicators in long press mode
      if (isLongPressMode) {
        final cornerPaint = Paint()
          ..color = Colors.orange.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        
        // Draw dashed border
        _drawDashedBorder(canvas, shape, cornerPaint);
      }
    }
    
    // Draw lock indicator
    if (shape.isLocked) {
      final lockPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(
        Offset(shape.position.dx + shape.size.width - 15, shape.position.dy + 15),
        8,
        Paint()..color = Colors.white..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(shape.position.dx + shape.size.width - 15, shape.position.dy + 15),
        8,
        Paint()..color = Colors.red..style = PaintingStyle.stroke..strokeWidth = 2,
      );
      
      // Draw lock icon (simplified)
      final lockRect = Rect.fromCenter(
        center: Offset(shape.position.dx + shape.size.width - 15, shape.position.dy + 15),
        width: 8,
        height: 8,
      );
      canvas.drawRect(lockRect, Paint()..color = Colors.red..style = PaintingStyle.stroke..strokeWidth = 1);
    }
  }

  void _drawDashedBorder(Canvas canvas, CanvasShape shape, Paint paint) {
    final path = Path();
    if (shape.type == 'Circle') {
      path.addOval(Rect.fromCircle(
        center: Offset(shape.position.dx + shape.size.width / 2, shape.position.dy + shape.size.height / 2),
        radius: shape.size.width / 2 + 8,
      ));
    } else {
      path.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(shape.position.dx - 8, shape.position.dy - 8, 
                    shape.size.width + 16, shape.size.height + 16),
        Radius.circular(12),
      ));
    }
    canvas.drawPath(path, paint);
  }

  void _drawHoverIndicator(Canvas canvas, CanvasShape shape) {
    final hoverPaint = Paint()
      ..color = const Color.fromARGB(255, 3, 25, 55).withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    if (shape.type == 'Circle') {
      canvas.drawCircle(
        Offset(shape.position.dx + shape.size.width / 2, shape.position.dy + shape.size.height / 2),
        shape.size.width / 2 + 3,
        hoverPaint,
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(shape.position.dx - 3, shape.position.dy - 3, 
                       shape.size.width + 6, shape.size.height + 6),
          Radius.circular(8),
        ),
        hoverPaint,
      );
    }
  }

  Color _getContrastColor(Color color) {
    double luminance = (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255;
    return luminance > 0.5 ? Colors.black87 : Colors.white;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Modern color picker widget
class ModernColorPicker extends StatelessWidget {
  final Color pickerColor;
  final ValueChanged<Color> onColorChanged;

  const ModernColorPicker({Key? key, required this.pickerColor, required this.onColorChanged}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = [
      Colors.red, Colors.pink, Colors.purple, Colors.deepPurple,
      Colors.indigo, const Color.fromARGB(255, 3, 25, 55), Colors.lightBlue, Colors.cyan,
      Colors.teal, Colors.green, Colors.lightGreen, Colors.lime,
      Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange,
      Colors.brown, Colors.grey, Colors.blueGrey, Colors.black,
    ];

    return Container(
      width: 320,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Choose Color',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: colors.map((color) {
              bool isSelected = pickerColor.value == color.value;
              return GestureDetector(
                onTap: () => onColorChanged(color),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 200),
                  width: isSelected ? 50 : 45,
                  height: isSelected ? 50 : 45,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(isSelected ? 16 : 12),
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: [
                      if (isSelected)
                        BoxShadow(
                          color: color.withOpacity(0.5),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                    ],
                  ),
                  child: isSelected 
                    ? Icon(Icons.check, color: Colors.white, size: 24)
                    : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// Main Company Screen
class CompanyScreen extends StatefulWidget {
  const CompanyScreen({Key? key}) : super(key: key);

  @override
  State<CompanyScreen> createState() => _CompanyScreenState();
}

class _CompanyScreenState extends State<CompanyScreen> with SingleTickerProviderStateMixin {
  final List<Map<String, dynamic>> _companies = []; // Changed to dynamic to store full data
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
      duration: Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
    _fetchCompanies();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchCompanies() async {
    try {
      setState(() => isLoading = true);
      const url = '${AppConfig.baseUrl}company';

      final data = await _apiService.getRequest(url);

      if (data != null) {
        //print('Fetched COMPANIES ::::>$data');
        
        List<dynamic> companiesData = [];
        
        if (data is List) {
          companiesData = data;
        } else if (data is Map && data['data'] != null) {
          companiesData = data['data'];
        }

        setState(() {
          _companies.clear();
          // Store full company data including layout
          _companies.addAll(companiesData.map((company) => 
            Map<String, dynamic>.from(company)
          ).toList());
          isLoading = false;
        });
        
        _animationController.forward();
        //print('Successfully loaded ${_companies.length} companies');
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      //print('Error fetching companies: $e');
      _showErrorSnackBar('Failed to load companies: ${e.toString()}');
      setState(() => isLoading = false);
    }
  }

  

  void _openCreateCompany() async {
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => CreateCompanyScreen(
          isEditMode: false,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: animation.drive(
              Tween(begin: Offset(1.0, 0.0), end: Offset.zero).chain(
                CurveTween(curve: Curves.easeInOut),
              ),
            ),
            child: child,
          );
        },
      ),
    );

    if (result != null) {
      await _fetchCompanies();
    }
  }

  void _openEditCompany(Map<String, dynamic> company) async {
    //print('_openEditCompany :::>$company');
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => CreateCompanyScreen(
          isEditMode: true,
          companyData: company,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: animation.drive(
              Tween(begin: Offset(1.0, 0.0), end: Offset.zero).chain(
                CurveTween(curve: Curves.easeInOut),
              ),
            ),
            child: child,
          );
        },
      ),
    );

    if (result != null) {
      await _fetchCompanies();
    }
  }

  void _deleteCompany(Map<String, dynamic> company) async {
    try {
      //print('deleteCompany :::>$company');
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete Company'),
          content: Text('Are you sure you want to delete this company? This action cannot be undone.'),
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
      
      setState(() => isDeleting = true);
       //print('TO BE DELETED COMPANY ID 2 :::> ${company["id"]}');
      final url = '${AppConfig.baseUrl}company/${company["id"]}';
      
      await _apiService.deleteRequest(url);
      
      // setState(() {
      //   _companies.removeWhere((c) => c['id'] == companyId || c['_id'] == companyId);
      //   isDeleting = false;
      // });
      
      _showSuccessSnackBar('Company deleted successfully!');
      await _fetchCompanies();
    } catch (e) {
      //print('Error deleting company: $e');
      _showErrorSnackBar('Failed to delete company: ${e.toString()}');
      setState(() => isDeleting = false);
    }
  }

  

  void _showCompanyDetails(Map<String, dynamic> company) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.business, size: 30, color: const Color.fromARGB(255, 3, 25, 55)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      company['name'] ?? "Company Details",
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit, color: const Color.fromARGB(255, 3, 25, 55)),
                    onPressed: () {
                      Navigator.pop(context);
                      _openEditCompany(company);
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                       Navigator.pop(context);
                      _deleteCompany(company);
                    },
                  ),
                ],
              ),
              SizedBox(height: 24),
              _buildDetailRow(Icons.person, "Contact", company['contact']?.toString() ?? 'N/A'),
              _buildDetailRow(Icons.email, "Email", company['email']?.toString() ?? 'N/A'),
              _buildDetailRow(Icons.phone, "Phone", company['phone']?.toString() ?? 'N/A'),
              _buildDetailRow(Icons.location_on, "Address", company['address']?.toString() ?? 'N/A'),
              if (company['role'] != null)
                _buildDetailRow(Icons.work, "Role", company['role'].toString()),
              if (company['layout'] != null && (company['layout'] as List).isNotEmpty)
                _buildDetailRow(Icons.dashboard, "Sections", '${(company['layout'] as List).length} sections'),
              SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Close", style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 16)),
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
            Icon(Icons.error_outline, color: Colors.white),
            SizedBox(width: 16),
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
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 16),
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
        title: Text('Companies'),
        backgroundColor: const Color.fromARGB(255, 3, 25, 55),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (isLoading)
            Center(
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
      body: isLoading && _companies.isEmpty
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchCompanies,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: _companies.isEmpty
                    ? ListView(
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.7,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.business, size: 80, color: Colors.grey.shade400),
                                  SizedBox(height: 20),
                                  Text(
                                    "No companies created yet",
                                    style: TextStyle(fontSize: 20, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    "Tap the + button to add your first company",
                                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: EdgeInsets.all(16),
                        itemCount: _companies.length,
                        itemBuilder: (context, index) {
                          final company = _companies[index];
                          return AnimatedContainer(
                            duration: Duration(milliseconds: 300),
                            margin: EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
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
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _showCompanyDetails(company),
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 50,
                                        height: 50,
                                        decoration: BoxDecoration(
                                          color: const Color.fromARGB(255, 3, 25, 55),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(Icons.business, color: Colors.white),
                                      ),
                                      SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              company['name']?.toString() ?? 'Unnamed Company',
                                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              company['contact']?.toString() ?? 'No contact',
                                              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isCreating ? null : _openCreateCompany,
        icon: Icon(Icons.add),
        label: Text('Add Company'),
        backgroundColor: const Color.fromARGB(255, 3, 25, 55),
        foregroundColor: Colors.white,
        elevation: 4,
      ),
    );
  }
}


// Create Company Screen
class CreateCompanyScreen extends StatefulWidget {
  final bool isEditMode;
  final Map<String, dynamic>? companyData;

  const CreateCompanyScreen({
    Key? key,
    this.isEditMode = false,
    this.companyData,
  }) : super(key: key);

  @override
  _CreateCompanyScreenState createState() => _CreateCompanyScreenState();
}

class _CreateCompanyScreenState extends State<CreateCompanyScreen> with TickerProviderStateMixin {
  int currentStage = 1;
  
  late final ApiService _apiService;
  
  // Stage 1 - Company Details
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  
  // Stage 2 - Design
  final TextEditingController _sectionNameController = TextEditingController();
  String selectedShape = 'Square';
  Color selectedColor = Colors.orange;
  List<CanvasShape> shapes = [];
  List<List<CanvasShape>> undoStack = [];
  List<List<CanvasShape>> redoStack = [];
  double canvasZoom = 1.0;
  CanvasShape? selectedShape_canvas;
  CanvasShape? hoveredShape;
  CanvasShape? copiedShape;
  Size canvasSize = Size(800, 600);
  Offset? dragOffset;
  final List<Map<String, String>> _companies = [];

  // Add these new state variables
  bool isResizing = false;
  String resizeHandle = ''; // 'topLeft', 'topRight', 'bottomLeft', 'bottomRight'
  
  // Animation controllers
  late AnimationController _stageAnimationController;
  late Animation<double> _stageAnimation;
  late AnimationController _animationController;
  
  // Available employees for assign to dropdown
  // final List<String> availableEmployees = [
  //   'John Doe',
  //   'Jane Smith',
  //   'Mike Johnson',
  //   'Sarah Williams',
  //   'Tom Brown',
  // ];

  List<User> availableUsers = [];
  List<String> get availableEmployees => availableUsers.map((u) => u.username).toList();


  // Add these new state variables
  bool isLongPressMode = false;
  CanvasShape? longPressShape;
  Timer? longPressTimer;
  final DioService _dioService = DioService();
  
  // Update existing variables
  Map<String, bool> lockedShapes = {}; // Track locked shapes by ID
  
  // Loading states
  bool isLoading = false;
  bool isSaving = false;
  
  @override
  void initState() {
    super.initState();
    _apiService = ApiService(_dioService);
    _sectionNameController.text = 'Rack 1';
    
    _stageAnimationController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );
    _stageAnimation = CurvedAnimation(
      parent: _stageAnimationController,
      curve: Curves.easeInOut,
    );
    _stageAnimationController.forward();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _fetchUsers();  // Wait for users to load first
    
    // Now load company data if in edit mode
    if (widget.isEditMode && widget.companyData != null) {
      _loadCompanyData();
    }
  }

  Future<void> _fetchUsers() async {
  try {
    const url = '${AppConfig.baseUrl}users';
    final data = await _apiService.getRequest(url);

    if (data != null) {
      //print('Fetched USERS ::::>$data');
      
      List<dynamic> usersData = [];
      if (data is List) {
        usersData = data;
      } else if (data is Map && data['data'] != null) {
        usersData = data['data'];
      }

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
        availableUsers = fetchedUsers;
      });
      
      //print('Successfully loaded ${availableUsers.length} users');
    }
  } catch (e) {
    //print('Error fetching users: $e');
    _showErrorSnackBar('Failed to load users: ${e.toString()}');
  } 
}

  void _loadCompanyData() {
    final data = widget.companyData!;
    
    // Pre-fill company details
    _idController.text = data['id']?.toString() ?? '';
    _nameController.text = data['name']?.toString() ?? '';
    _contactController.text = data['contact']?.toString() ?? '';
    _addressController.text = data['address']?.toString() ?? '';
    _emailController.text = data['email']?.toString() ?? '';
    _phoneController.text = data['phone']?.toString() ?? '';
    
    // Load canvas size if available
    if (data['canvasSize'] != null) {
      final canvasSizeData = data['canvasSize'] as Map;
      canvasSize = Size(
        (canvasSizeData['width'] ?? 800).toDouble(),
        (canvasSizeData['height'] ?? 600).toDouble(),
      );
    }
    
    // Load shapes from layout
    if (data['layout'] != null && data['layout'] is List) {
      shapes.clear();
      final layoutList = data['layout'] as List;
      
      for (var shapeData in layoutList) {
        if (shapeData is Map) {

          List<String> assignedUsernames = [];
          if (shapeData['assigned'] != null) {
            //print('assigned');
            if (shapeData['assigned'] is List) {
              //print('assigned List');
              List<String> assignedIds = (shapeData['assigned'] as List)
                  .map((id) => id.toString())
                  .toList();
              // Convert IDs to usernames
              assignedUsernames = availableUsers
                  .where((user) => assignedIds.contains(user.id))
                  .map((user) => user.username)
                  .toList();


            }
          }
          // Convert hex color to Flutter Color
          Color shapeColor = const Color.fromARGB(255, 3, 25, 55);
          if (shapeData['color'] != null) {
            String hexColor = shapeData['color'].toString().replaceAll('#', '');
            if (hexColor.length == 6) {
              hexColor = 'FF$hexColor';
            }
            try {
              shapeColor = Color(int.parse(hexColor, radix: 16));
            } catch (e) {
              //print('Error parsing color: $e');
              shapeColor = const Color.fromARGB(255, 3, 25, 55);
            }
          }
          
          // Determine shape type
          String shapeType = 'Rectangle';
          if (shapeData['shape'] != null) {
            String shape = shapeData['shape'].toString().toLowerCase();
            if (shape == 'circle') {
              shapeType = 'Circle';
            } else if (shape == 'square') {
              shapeType = 'Square';
            } else {
              shapeType = 'Rectangle';
            }
          }
          
          shapes.add(CanvasShape(
            id: shapeData['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
            type: shapeType,
            position: Offset(
              (shapeData['x'] ?? 50).toDouble(),
              (shapeData['y'] ?? 50).toDouble(),
            ),
            size: Size(
              (shapeData['width'] ?? 100).toDouble(),
              (shapeData['height'] ?? 100).toDouble(),
            ),
            color: shapeColor,
            name: shapeData['name']?.toString() ?? 'Section',
            assigned: assignedUsernames,
            isLocked: shapeData['isLocked'] ?? false,
          ));
        }
      }
    }
  }

  @override
  void dispose() {
    longPressTimer?.cancel();
    _stageAnimationController.dispose();
    _nameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _sectionNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(widget.isEditMode ? 'Edit Company' : 'Create Company', 
          style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Container(
            color: Colors.grey.shade200,
            height: 1,
          ),
        ),
      ),
      body: Column(
        children: [
          _buildStageIndicator(),
          Expanded(
            child: AnimatedSwitcher(
              duration: Duration(milliseconds: 300),
              child: _buildCurrentStage(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageIndicator() {
    return Container(
      padding: EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        children: [
          _buildStageCircle(1, 'Company Info'),
          Expanded(child: _buildStageConnector(currentStage > 1)),
          _buildStageCircle(2, 'Design Layout'),
          Expanded(child: _buildStageConnector(currentStage > 2)),
          _buildStageCircle(3, 'Preview & Save'),
        ],
      ),
    );
  }

  Widget _buildStageCircle(int stage, String title) {
    bool isActive = currentStage == stage;
    bool isCompleted = currentStage > stage;
    
    return Column(
      children: [
        AnimatedContainer(
          duration: Duration(milliseconds: 300),
          width: isActive ? 44 : 40,
          height: isActive ? 44 : 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted || isActive ? const Color.fromARGB(255, 3, 25, 55) : Colors.grey.shade300,
            boxShadow: isActive ? [
              BoxShadow(
                color: const Color.fromARGB(255, 3, 25, 55).withOpacity(0.3),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ] : [],
          ),
          child: Center(
            child: isCompleted 
              ? Icon(Icons.check, color: Colors.white, size: 20)
              : Text(
                  stage.toString(),
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
          ),
        ),
        SizedBox(height: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? const Color.fromARGB(255, 3, 25, 55) : Colors.grey.shade600,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildStageConnector(bool isCompleted) {
    return Container(
      height: 2,
      margin: EdgeInsets.only(bottom: 30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isCompleted 
            ? [const Color.fromARGB(255, 3, 25, 55), const Color.fromARGB(255, 3, 25, 55)]
            : [Colors.grey.shade300, Colors.grey.shade300],
        ),
      ),
    );
  }

  Widget _buildCurrentStage() {
    switch (currentStage) {
      case 1:
        return _buildCompanyDetailsStage();
      case 2:
        return _buildDesignStage();
      case 3:
        return _buildPreviewStage();
      default:
        return Container();
    }
  }

  Widget _buildCompanyDetailsStage() {
    return Container(
      padding: EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Company Details', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Enter your company information', style: TextStyle(color: Colors.grey.shade600)),
            SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildModernTextField(_nameController, 'Company Name', Icons.business),
                    SizedBox(height: 16),
                    _buildModernTextField(_contactController, 'Contact Person', Icons.person),
                    SizedBox(height: 16),
                    _buildModernTextField(_addressController, 'Address', Icons.location_on, maxLines: 3),
                    SizedBox(height: 16),
                    _buildModernTextField(_emailController, 'Email', Icons.email, keyboardType: TextInputType.emailAddress),
                    SizedBox(height: 16),
                    _buildModernTextField(_phoneController, 'Phone', Icons.phone, keyboardType: TextInputType.phone),
                  ],
                ),
              ),
            ),
            SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                      foregroundColor: Colors.black87,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _validateAndNextStage,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Continue'),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward, size: 18),
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
          ],
        ),
      ),
    );
  }

  Widget _buildModernTextField(TextEditingController controller, String label, IconData icon, {int maxLines = 1, TextInputType? keyboardType}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: const Color.fromARGB(255, 3, 25, 55)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.red.shade300, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: const Color.fromARGB(255, 3, 25, 55), width: 2),
          ),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'This field is required';
          }
          if (label == 'Email' && !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}').hasMatch(value)) {
            return 'Please enter a valid email';
          }
          return null;
        },
      ),
    );
  }

// class _CreateCompanyScreenState extends State<CreateCompanyScreen> with TickerProviderStateMixin {
//   int currentStage = 1;
  
//   late final ApiService _apiService;
  
//   // Stage 1 - Company Details
//   final _formKey = GlobalKey<FormState>();
//   final TextEditingController _nameController = TextEditingController();
//   final TextEditingController _contactController = TextEditingController();
//   final TextEditingController _addressController = TextEditingController();
//   final TextEditingController _emailController = TextEditingController();
//   final TextEditingController _phoneController = TextEditingController();
  
//   // Stage 2 - Design
//   final TextEditingController _sectionNameController = TextEditingController();
//   String selectedShape = 'Square';
//   Color selectedColor = const Color.fromARGB(255, 3, 25, 55);
//   List<CanvasShape> shapes = [];
//   List<List<CanvasShape>> undoStack = [];
//   List<List<CanvasShape>> redoStack = [];
//   double canvasZoom = 1.0;
//   CanvasShape? selectedShape_canvas;
//   CanvasShape? hoveredShape;
//   CanvasShape? copiedShape;
//   Size canvasSize = Size(800, 600);
//   Offset? dragOffset;
//   final List<Map<String, String>> _companies = [];

//   // Add these new state variables
//   bool isResizing = false;
//   String resizeHandle = ''; // 'topLeft', 'topRight', 'bottomLeft', 'bottomRight'
  
//   // Animation controllers
//   late AnimationController _stageAnimationController;
//   late Animation<double> _stageAnimation;
//   late AnimationController _animationController;
  
//   // Available employees for assign to dropdown
//   final List<String> availableEmployees = [
//     'John Doe',
//     'Jane Smith',
//     'Mike Johnson',
//     'Sarah Williams',
//     'Tom Brown',
//   ];

//   // Add these new state variables
//   bool isLongPressMode = false;
//   CanvasShape? longPressShape;
//   Timer? longPressTimer;
//   final DioService _dioService = DioService();
  

//   // Update existing variables
//   Map<String, bool> lockedShapes = {}; // Track locked shapes by ID
  
//   @override
//   void initState() {
//     super.initState();
//     _apiService = ApiService(_dioService);
//     _sectionNameController.text = 'Rack 1';
    
//     _stageAnimationController = AnimationController(
//       duration: Duration(milliseconds: 300),
//       vsync: this,
//     );
//     _stageAnimation = CurvedAnimation(
//       parent: _stageAnimationController,
//       curve: Curves.easeInOut,
//     );
//     _stageAnimationController.forward();
//   }

//   @override
//   void dispose() {
//     longPressTimer?.cancel();
//     _stageAnimationController.dispose();
//     _nameController.dispose();
//     _contactController.dispose();
//     _addressController.dispose();
//     _emailController.dispose();
//     _phoneController.dispose();
//     _sectionNameController.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.grey.shade50,
//       appBar: AppBar(
//         title: Text('Create Company', style: TextStyle(fontWeight: FontWeight.bold)),
//         backgroundColor: Colors.white,
//         foregroundColor: Colors.black87,
//         elevation: 0,
//         leading: IconButton(
//           icon: Icon(Icons.close),
//           onPressed: () => Navigator.pop(context),
//         ),
//         bottom: PreferredSize(
//           preferredSize: Size.fromHeight(1),
//           child: Container(
//             color: Colors.grey.shade200,
//             height: 1,
//           ),
//         ),
//       ),
//       body: Column(
//         children: [
//           _buildStageIndicator(),
//           Expanded(
//             child: AnimatedSwitcher(
//               duration: Duration(milliseconds: 300),
//               child: _buildCurrentStage(),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildStageIndicator() {
//     return Container(
//       padding: EdgeInsets.all(20),
//       color: Colors.white,
//       child: Row(
//         children: [
//           _buildStageCircle(1, 'Company Info'),
//           Expanded(child: _buildStageConnector(currentStage > 1)),
//           _buildStageCircle(2, 'Design Layout'),
//           Expanded(child: _buildStageConnector(currentStage > 2)),
//           _buildStageCircle(3, 'Preview & Save'),
//         ],
//       ),
//     );
//   }

//   Widget _buildStageCircle(int stage, String title) {
//     bool isActive = currentStage == stage;
//     bool isCompleted = currentStage > stage;
    
//     return Column(
//       children: [
//         AnimatedContainer(
//           duration: Duration(milliseconds: 300),
//           width: isActive ? 44 : 40,
//           height: isActive ? 44 : 40,
//           decoration: BoxDecoration(
//             shape: BoxShape.circle,
//             color: isCompleted || isActive ? const Color.fromARGB(255, 3, 25, 55) : Colors.grey.shade300,
//             boxShadow: isActive ? [
//               BoxShadow(
//                 color: const Color.fromARGB(255, 3, 25, 55).withOpacity(0.3),
//                 blurRadius: 8,
//                 offset: Offset(0, 2),
//               ),
//             ] : [],
//           ),
//           child: Center(
//             child: isCompleted 
//               ? Icon(Icons.check, color: Colors.white, size: 20)
//               : Text(
//                   stage.toString(),
//                   style: TextStyle(
//                     color: isActive ? Colors.white : Colors.grey.shade600,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//           ),
//         ),
//         SizedBox(height: 8),
//         Text(
//           title,
//           style: TextStyle(
//             fontSize: 12,
//             color: isActive ? const Color.fromARGB(255, 3, 25, 55) : Colors.grey.shade600,
//             fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildStageConnector(bool isCompleted) {
//     return Container(
//       height: 2,
//       margin: EdgeInsets.only(bottom: 30),
//       decoration: BoxDecoration(
//         gradient: LinearGradient(
//           colors: isCompleted 
//             ? [const Color.fromARGB(255, 3, 25, 55), const Color.fromARGB(255, 3, 25, 55).shade300]
//             : [Colors.grey.shade300, Colors.grey.shade300],
//         ),
//       ),
//     );
//   }

//   Widget _buildCurrentStage() {
//     switch (currentStage) {
//       case 1:
//         return _buildCompanyDetailsStage();
//       case 2:
//         return _buildDesignStage();
//       case 3:
//         return _buildPreviewStage();
//       default:
//         return Container();
//     }
//   }

//   Widget _buildCompanyDetailsStage() {
//     return Container(
//       padding: EdgeInsets.all(20),
//       child: Form(
//         key: _formKey,
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Text('Company Details', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
//             SizedBox(height: 8),
//             Text('Enter your company information', style: TextStyle(color: Colors.grey.shade600)),
//             SizedBox(height: 24),
//             Expanded(
//               child: SingleChildScrollView(
//                 child: Column(
//                   children: [
//                     _buildModernTextField(_nameController, 'Company Name', Icons.business),
//                     SizedBox(height: 16),
//                     _buildModernTextField(_contactController, 'Contact Person', Icons.person),
//                     SizedBox(height: 16),
//                     _buildModernTextField(_addressController, 'Address', Icons.location_on, maxLines: 3),
//                     SizedBox(height: 16),
//                     _buildModernTextField(_emailController, 'Email', Icons.email, keyboardType: TextInputType.emailAddress),
//                     SizedBox(height: 16),
//                     _buildModernTextField(_phoneController, 'Phone', Icons.phone, keyboardType: TextInputType.phone),
//                   ],
//                 ),
//               ),
//             ),
//             SizedBox(height: 20),
//             Row(
//               children: [
//                 Expanded(
//                   child: ElevatedButton(
//                     onPressed: () => Navigator.pop(context),
//                     child: Text('Cancel'),
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: Colors.grey.shade200,
//                       foregroundColor: Colors.black87,
//                       padding: EdgeInsets.symmetric(vertical: 16),
//                       shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                       elevation: 0,
//                     ),
//                   ),
//                 ),
//                 SizedBox(width: 16),
//                 Expanded(
//                   flex: 2,
//                   child: ElevatedButton(
//                     onPressed: _validateAndNextStage,
//                     child: Row(
//                       mainAxisAlignment: MainAxisAlignment.center,
//                       children: [
//                         Text('Continue'),
//                         SizedBox(width: 8),
//                         Icon(Icons.arrow_forward, size: 18),
//                       ],
//                     ),
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: const Color.fromARGB(255, 3, 25, 55),
//                       foregroundColor: Colors.white,
//                       padding: EdgeInsets.symmetric(vertical: 16),
//                       shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                       elevation: 2,
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildModernTextField(TextEditingController controller, String label, IconData icon, {int maxLines = 1, TextInputType? keyboardType}) {
//     return Container(
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(12),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             blurRadius: 10,
//             offset: Offset(0, 2),
//           ),
//         ],
//       ),
//       child: TextFormField(
//         controller: controller,
//         maxLines: maxLines,
//         keyboardType: keyboardType,
//         decoration: InputDecoration(
//           labelText: label,
//           prefixIcon: Icon(icon, color: const Color.fromARGB(255, 3, 25, 55)),
//           border: OutlineInputBorder(
//             borderRadius: BorderRadius.circular(12),
//             borderSide: BorderSide.none,
//           ),
//           filled: true,
//           fillColor: Colors.white,
//           errorBorder: OutlineInputBorder(
//             borderRadius: BorderRadius.circular(12),
//             borderSide: BorderSide(color: Colors.red.shade300, width: 1),
//           ),
//           focusedBorder: OutlineInputBorder(
//             borderRadius: BorderRadius.circular(12),
//             borderSide: BorderSide(color: const Color.fromARGB(255, 3, 25, 55), width: 2),
//           ),
//         ),
//         validator: (value) {
//           if (value == null || value.isEmpty) {
//             return 'This field is required';
//           }
//           if (label == 'Email' && !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}').hasMatch(value)) {
//             return 'Please enter a valid email';
//           }
//           return null;
//         },
//       ),
//     );
//   }

  Widget _buildDesignStage() {
    return Column(
      children: [
        // Modern Control Panel
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Shape Creation Row
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 3, 25, 55),
                  border: Border(
                    bottom: BorderSide(color: const Color.fromARGB(255, 3, 25, 55), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    // Shape Selector
                    Expanded(
                      flex: 3,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color.fromARGB(255, 3, 25, 55)),
                        ),
                        child: DropdownButtonFormField<String>(
                          value: selectedShape,
                          decoration: InputDecoration(
                            labelText: 'Shape',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: ['Square', 'Rectangle', 'Circle'].map((shape) {
                            return DropdownMenuItem(
                              value: shape, 
                              child: Row(
                                children: [
                                  Icon(
                                    shape == 'Circle' ? Icons.circle : Icons.square,
                                    size: 16,
                                    color: const Color.fromARGB(255, 3, 25, 55)
                                  ),
                                  SizedBox(width: 8),
                                  Text(shape),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              selectedShape = value!;
                            });
                          },
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    // Section Name
                    Expanded(
                      flex: 3,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color.fromARGB(255, 3, 25, 55)),
                        ),
                        child: TextFormField(
                          controller: _sectionNameController,
                          decoration: InputDecoration(
                            labelText: 'Section Name',
                            prefixIcon: Icon(Icons.label, color: const Color.fromARGB(255, 3, 25, 55)),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onChanged: (value) {
                            if (selectedShape_canvas != null) {
                              setState(() {
                                selectedShape_canvas!.name = value;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    // Add Button
                    _buildAddButton()
                  ],
                ),
              ),
              // Selected Shape Editor
              AnimatedContainer(
                duration: Duration(milliseconds: 300),
                height: selectedShape_canvas != null ? null : 0,
                child: selectedShape_canvas != null
                  ? Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [const Color.fromARGB(255, 3, 25, 55), const Color.fromARGB(255, 3, 25, 55).withOpacity(0.5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: selectedShape_canvas!.isLocked ? null : () => _showUserAssignmentDialog(),
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color.fromARGB(255, 3, 25, 55)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.person_add, color: const Color.fromARGB(255, 3, 25, 55), size: 20),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        selectedShape_canvas!.assigned.isEmpty
                                            ? 'Assign Users'
                                            : selectedShape_canvas!.assigned.length == 1
                                                ? selectedShape_canvas!.assigned[0]
                                                : '${selectedShape_canvas!.assigned[0]} +${selectedShape_canvas!.assigned.length - 1} more',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: selectedShape_canvas!.assigned.isEmpty 
                                              ? Colors.grey.shade600 
                                              : Colors.black87,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 16),
                          IconButton(
                            onPressed: _toggleShapeLock,
                            icon: Icon(selectedShape_canvas!.isLocked ? Icons.lock : Icons.lock_open),
                            color: selectedShape_canvas!.isLocked ? Colors.red : Colors.green,
                            tooltip: selectedShape_canvas!.isLocked ? 'Unlock Shape' : 'Lock Shape',
                            style: IconButton.styleFrom(
                              backgroundColor: selectedShape_canvas!.isLocked ? Colors.red.shade50 : Colors.green.shade50,
                            ),
                          ),
                          SizedBox(width: 8),
                          IconButton(
                            onPressed: selectedShape_canvas!.isLocked ? null : _deleteSelectedShape,
                            icon: Icon(Icons.delete),
                            color: selectedShape_canvas!.isLocked ? Colors.grey : Colors.red,
                            tooltip: 'Delete Shape',
                            style: IconButton.styleFrom(
                              backgroundColor: selectedShape_canvas!.isLocked ? Colors.grey.shade100 : Colors.red.shade50,
                            ),
                          ),
                        ],
                      ),
                    )
                  : SizedBox.shrink(),
              ),
              // Control Buttons
              Container(
                padding: EdgeInsets.all(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildModernControlButton(Icons.palette, 'palette', _showColorPicker),
                      _buildModernControlButton(Icons.undo, 'Undo', _undo, enabled: undoStack.isNotEmpty),
                      _buildModernControlButton(Icons.redo, 'Redo', _redo, enabled: redoStack.isNotEmpty),
                      // _buildModernControlButton(Icons.zoom_in, 'Zoom In', _zoomIn),
                      // _buildModernControlButton(Icons.zoom_out, 'Zoom Out', _zoomOut),
                      _buildModernControlButton(Icons.copy, 'Copy', _copyShape, enabled: selectedShape_canvas != null),
                      _buildModernControlButton(Icons.paste, 'Paste', _pasteShape, enabled: copiedShape != null),
                      if (isLongPressMode)
                        _buildModernControlButton(Icons.exit_to_app, 'Exit Resize', _exitResizeMode),
                      _buildModernControlButton(Icons.refresh, 'Reset', _reset),
                    ],
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.all(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Canvas Size Controls
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.aspect_ratio, size: 18, color: Colors.grey.shade700),
                            SizedBox(width: 8),
                            Text(
                              'Canvas: ${canvasSize.width.toInt()} x ${canvasSize.height.toInt()}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            SizedBox(width: 12),
                            _buildSizeButton(Icons.add, () => _resizeCanvas(100, 0), 'W+'),
                            _buildSizeButton(Icons.remove, () => _resizeCanvas(-100, 0), 'W-'),
                            SizedBox(width: 8),
                            _buildSizeButton(Icons.add, () => _resizeCanvas(0, 100), 'H+'),
                            _buildSizeButton(Icons.remove, () => _resizeCanvas(0, -100), 'H-'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Canvas Area
        // Expanded(
        //   child: Container(
        //     margin: EdgeInsets.all(16),
        //     decoration: BoxDecoration(
        //       color: Colors.white,
        //       borderRadius: BorderRadius.circular(16),
        //       boxShadow: [
        //         BoxShadow(
        //           color: Colors.black.withOpacity(0.1),
        //           blurRadius: 20,
        //           offset: Offset(0, 10),
        //         ),
        //       ],
        //     ),
        //     child: ClipRRect(
        //       borderRadius: BorderRadius.circular(16),
        //       child: SingleChildScrollView(
        //         scrollDirection: Axis.horizontal,
        //         child: SingleChildScrollView(
        //           scrollDirection: Axis.vertical,
        //           child: LayoutBuilder(
        //             builder: (context, constraints) {
        //               // Calculate actual canvas size with zoom
        //               double canvasDisplayWidth = canvasSize.width * canvasZoom;
        //               double canvasDisplayHeight = canvasSize.height * canvasZoom;
                      
        //               return SingleChildScrollView(
        //                 scrollDirection: Axis.horizontal,
        //                 child: SingleChildScrollView(
        //                   scrollDirection: Axis.vertical,
        //                   child: Container(
        //                     width: canvasDisplayWidth,
        //                     height: canvasDisplayHeight,
        //                     child: MouseRegion(
        //                       onHover: (event) => _onCanvasHover(event.localPosition),
        //                       onExit: (_) => setState(() => hoveredShape = null),
        //                       child: GestureDetector(
        //                         onTapDown: (details) => _onCanvasTap(details.localPosition),
        //                         onPanStart: (details) => _onDragStart(details.localPosition),
        //                         onPanUpdate: (details) => _onDragUpdate(details.localPosition),
        //                         onPanEnd: (_) => _onDragEnd(),
        //                         onDoubleTap: _deleteSelectedShape,
        //                         child: CustomPaint(
        //                           size: Size(canvasDisplayWidth, canvasDisplayHeight),
        //                           painter: CanvasPainter(shapes, selectedShape_canvas, hoveredShape, canvasZoom, canvasSize, isLongPressMode),
        //                         ),
        //                       ),
        //                     ),
        //                   ),
        //                 ),
        //               );
        //             },
        //           ),
        //         )
        //       )
        //     ),
        //   ),
        // ),

        // Canvas Area
        Expanded(
          child: Container(
            margin: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: MouseRegion(
                        onHover: (event) => _onCanvasHover(event.localPosition),
                        onExit: (_) => setState(() => hoveredShape = null),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (details) => _onCanvasTap(details.localPosition),
                          onPanStart: (details) => _onDragStart(details.localPosition),
                          onPanUpdate: (details) => _onDragUpdate(details.localPosition),
                          onPanEnd: (_) => _onDragEnd(),
                          onDoubleTap: _deleteSelectedShape,
                          child: Container(
                            width: canvasSize.width,
                            height: canvasSize.height,
                            child: CustomPaint(
                              size: canvasSize,
                              painter: CanvasPainter(shapes, selectedShape_canvas, hoveredShape, 1.0, canvasSize, isLongPressMode),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        // Bottom Navigation
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => setState(() => currentStage = 1),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_back, size: 18),
                      SizedBox(width: 8),
                      Text('Back'),
                    ],
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                    foregroundColor: Colors.black87,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => setState(() => currentStage = 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Preview'),
                      SizedBox(width: 8),
                      Icon(Icons.visibility, size: 18),
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
    );
  }

  Widget _buildPreviewStage() {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(20),
          color: Colors.white,
          child: Row(
            children: [
              Icon(Icons.preview, size: 30, color: const Color.fromARGB(255, 3, 25, 55)),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Preview & Save', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Text('Review your design before saving', style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 3.0,
                child: Container(
                  width: canvasSize.width,
                  height: canvasSize.height,
                  color: Colors.white,
                  child: CustomPaint(
                    size: canvasSize,
                    painter: CanvasPainter(shapes, null, null, 1.0, canvasSize, false),
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => setState(() => currentStage = 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_back, size: 18),
                      SizedBox(width: 8),
                      Text('Back'),
                    ],
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                    foregroundColor: Colors.black87,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _exportToPng,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.image, size: 18),
                      SizedBox(width: 8),
                      Text('Export'),
                    ],
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveCompany,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.save, size: 18),
                      SizedBox(width: 8),
                      Text('Save'),
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
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: _addShape,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withOpacity(0.3),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(Icons.add, color: Colors.white, size: 24),
      ),
    );
  }

  Widget _buildModernControlButton(IconData icon, String tooltip, VoidCallback onPressed, {bool enabled = true}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: enabled ? const Color.fromARGB(255, 3, 25, 55) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: EdgeInsets.all(12),
            child: Icon(
              icon,
              color: icon == Icons.palette
              ? selectedColor
              : (enabled ? Colors.white : Colors.grey.shade400),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSizeButton(IconData icon, VoidCallback onPressed, String label) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Icon(icon, size: 16, color: Colors.grey.shade700),
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ],
          ),
        ),
      ),
    );
  }

  void _exitResizeMode() {
    setState(() {
      isLongPressMode = false;
      longPressShape = null;
      isResizing = false;
      resizeHandle = '';
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Resize mode deactivated'),
        duration: Duration(seconds: 1),
        backgroundColor: const Color.fromARGB(255, 3, 25, 55),
      ),
    );
  }

  void _toggleShapeLock() {
    if (selectedShape_canvas != null) {
      setState(() {
        selectedShape_canvas!.isLocked = !selectedShape_canvas!.isLocked;
        lockedShapes[selectedShape_canvas!.id] = selectedShape_canvas!.isLocked;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(selectedShape_canvas!.isLocked ? 'Shape locked' : 'Shape unlocked'),
          duration: Duration(seconds: 1),
          backgroundColor: selectedShape_canvas!.isLocked ? Colors.red : Colors.green,
        ),
      );
    }
  }

  void _validateAndNextStage() {
    if (_formKey.currentState!.validate()) {
      setState(() {
        currentStage = 2;
        _stageAnimationController.forward(from: 0);
      });
    }
  }

  void _addShape() {
    _saveState();
    redoStack.clear();
    
    Size shapeSize = selectedShape == 'Rectangle' ? Size(150, 100) : Size(100, 100);
    
    // Ensure shape fits within canvas
    if (shapeSize.width > canvasSize.width) shapeSize = Size(canvasSize.width - 20, shapeSize.height);
    if (shapeSize.height > canvasSize.height) shapeSize = Size(shapeSize.width, canvasSize.height - 20);
    
    Offset newPosition = _findNonOverlappingPosition(shapeSize);
    
    setState(() {
      shapes.add(CanvasShape(
        type: selectedShape,
        position: newPosition,
        size: shapeSize,
        color: selectedColor,
        name: _sectionNameController.text,
        assigned: [],
      ));
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Shape added to canvas'),
        duration: Duration(seconds: 1),
        backgroundColor: Colors.green,
      ),
    );
  }

  Offset _findNonOverlappingPosition(Size shapeSize) {
    double x = 50;
    double y = 50;
    bool foundPosition = false;
    
    while (!foundPosition && y < canvasSize.height - shapeSize.height) {
      foundPosition = true;
      for (var shape in shapes) {
        if (_isOverlapping(
          Rect.fromLTWH(x, y, shapeSize.width, shapeSize.height),
          Rect.fromLTWH(shape.position.dx, shape.position.dy, shape.size.width, shape.size.height),
        )) {
          foundPosition = false;
          x += 120;
          if (x > canvasSize.width - shapeSize.width) {
            x = 50;
            y += 120;
          }
          break;
        }
      }
    }
    
    return Offset(x, y);
  }

  bool _isOverlapping(Rect rect1, Rect rect2) {
    return !(rect1.right < rect2.left || 
             rect1.left > rect2.right || 
             rect1.bottom < rect2.top || 
             rect1.top > rect2.bottom);
  }

  void _onCanvasHover(Offset position) {
    setState(() {
      hoveredShape = null;
      for (var shape in shapes.reversed) {
        if (_isPointInShape(position, shape)) {
          hoveredShape = shape;
          break;
        }
      }
    });
  }

  void _onCanvasTap(Offset position) {
    bool shapeFound = false;
    setState(() {
      selectedShape_canvas = null;
      for (var shape in shapes.reversed) {
        if (_isPointInShape(position, shape)) {
          selectedShape_canvas = shape;
          selectedColor = shape.color;
          _sectionNameController.text = shape.name;
          selectedShape = shape.type;
          shapeFound = true;
          break;
        }
      }
      
      // If no shape was clicked, exit long press mode
      if (!shapeFound) {
        isLongPressMode = false;
        longPressShape = null;
      }
    });
  }

  void _onDragStart(Offset position) {
    // FIRST priority: resize handles on the currently selected shape,
    // even when the touch point is slightly outside the shape boundary.
    if (selectedShape_canvas != null && !selectedShape_canvas!.isLocked) {
      String? handle = _getResizeHandle(position, selectedShape_canvas!);
      if (handle != null) {
        setState(() {
          isResizing = true;
          resizeHandle = handle;
          isLongPressMode = true;
          longPressShape = selectedShape_canvas;
        });
        return;
      }
    }

    // SECOND: check which shape (if any) was touched
    CanvasShape? targetShape;
    for (var shape in shapes.reversed) {
      if (_isPointInShape(position, shape)) {
        targetShape = shape;
        break;
      }
    }

    if (targetShape != null) {
      // Don't drag locked shapes
      if (targetShape.isLocked) {
        setState(() {
          selectedShape_canvas = targetShape;
          selectedColor = targetShape!.color;
          _sectionNameController.text = targetShape.name;
          selectedShape = targetShape.type;
        });
        return;
      }

      // Normal drag
      setState(() {
        selectedShape_canvas = targetShape;
        selectedColor = targetShape!.color;
        _sectionNameController.text = targetShape.name;
        selectedShape = targetShape.type;
        targetShape.isDragging = true;
        isResizing = false;
        dragOffset = position - targetShape.position;
      });
    } else {
      // Touched empty canvas — deselect
      setState(() {
        selectedShape_canvas = null;
        isLongPressMode = false;
        longPressShape = null;
        isResizing = false;
      });
    }
  }

  void _onLongPress(Offset position) {
    // Find shape at position
    for (var shape in shapes.reversed) {
      if (_isPointInShape(position, shape) && !shape.isLocked) {
        setState(() {
          isLongPressMode = true;
          longPressShape = shape;
          selectedShape_canvas = shape;
          // Stop any dragging when entering resize mode
          shape.isDragging = false;
        });
        
        // Provide haptic feedback
        HapticFeedback.mediumImpact();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Resize mode activated - drag corners to resize'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.orange,
          ),
        );
        break;
      }
    }
  }

  String? _getResizeHandle(Offset position, CanvasShape shape) {
    const double handleSize = 40.0; // Increased for easier clicking
    
    List<Map<String, dynamic>> handles = [
      {'name': 'topLeft', 'pos': Offset(shape.position.dx, shape.position.dy)},
      {'name': 'topRight', 'pos': Offset(shape.position.dx + shape.size.width, shape.position.dy)},
      {'name': 'bottomLeft', 'pos': Offset(shape.position.dx, shape.position.dy + shape.size.height)},
      {'name': 'bottomRight', 'pos': Offset(shape.position.dx + shape.size.width, shape.position.dy + shape.size.height)},
    ];
    
    for (var handle in handles) {
      Offset handlePos = handle['pos'];
      double distance = (position - handlePos).distance;
      if (distance <= handleSize) {
        return handle['name'];
      }
    }
    
    return null;
  }

  void _onDragUpdate(Offset position) {
    //Offset adjustedPosition = position / canvasZoom;
    
    if (selectedShape_canvas != null) {
      if (isResizing) {
        _handleResize(position);
      } else if (selectedShape_canvas!.isDragging && dragOffset != null) {
        Offset newPosition = position - dragOffset!;
        
        // Ensure shapes stay within canvas bounds
        newPosition = Offset(
          newPosition.dx.clamp(0, canvasSize.width - selectedShape_canvas!.size.width),
          newPosition.dy.clamp(0, canvasSize.height - selectedShape_canvas!.size.height),
        );
        
        // Check for overlapping with other shapes
        bool wouldOverlap = false;
        for (var shape in shapes) {
          if (shape != selectedShape_canvas) {
            if (_isOverlapping(
              Rect.fromLTWH(newPosition.dx, newPosition.dy, 
                            selectedShape_canvas!.size.width, selectedShape_canvas!.size.height),
              Rect.fromLTWH(shape.position.dx, shape.position.dy, 
                            shape.size.width, shape.size.height),
            )) {
              wouldOverlap = true;
              break;
            }
          }
        }
        
        if (!wouldOverlap) {
          setState(() {
            selectedShape_canvas!.position = newPosition;
          });
        }
      }
    }
  }

  void _handleResize(Offset position) {
    if (selectedShape_canvas == null) return;
    
    double minSize = 30.0;
    double newWidth = selectedShape_canvas!.size.width;
    double newHeight = selectedShape_canvas!.size.height;
    Offset newPosition = selectedShape_canvas!.position;
    
    switch (resizeHandle) {
      case 'topLeft':
        newWidth = math.max(minSize, (selectedShape_canvas!.position.dx + selectedShape_canvas!.size.width) - position.dx);
        newHeight = math.max(minSize, (selectedShape_canvas!.position.dy + selectedShape_canvas!.size.height) - position.dy);
        newPosition = Offset(
          math.min(position.dx, selectedShape_canvas!.position.dx + selectedShape_canvas!.size.width - minSize),
          math.min(position.dy, selectedShape_canvas!.position.dy + selectedShape_canvas!.size.height - minSize)
        );
        break;
        
      case 'topRight':
        newWidth = math.max(minSize, position.dx - selectedShape_canvas!.position.dx);
        newHeight = math.max(minSize, (selectedShape_canvas!.position.dy + selectedShape_canvas!.size.height) - position.dy);
        newPosition = Offset(
          selectedShape_canvas!.position.dx,
          math.min(position.dy, selectedShape_canvas!.position.dy + selectedShape_canvas!.size.height - minSize)
        );
        break;
        
      case 'bottomLeft':
        newWidth = math.max(minSize, (selectedShape_canvas!.position.dx + selectedShape_canvas!.size.width) - position.dx);
        newHeight = math.max(minSize, position.dy - selectedShape_canvas!.position.dy);
        newPosition = Offset(
          math.min(position.dx, selectedShape_canvas!.position.dx + selectedShape_canvas!.size.width - minSize),
          selectedShape_canvas!.position.dy
        );
        break;
        
      case 'bottomRight':
        newWidth = math.max(minSize, position.dx - selectedShape_canvas!.position.dx);
        newHeight = math.max(minSize, position.dy - selectedShape_canvas!.position.dy);
        break;
    }
    
    // Ensure shapes don't exceed canvas bounds
    if (newPosition.dx < 0) {
      newWidth += newPosition.dx;
      newPosition = Offset(0, newPosition.dy);
    }
    if (newPosition.dy < 0) {
      newHeight += newPosition.dy;
      newPosition = Offset(newPosition.dx, 0);
    }
    if (newPosition.dx + newWidth > canvasSize.width) {
      newWidth = canvasSize.width - newPosition.dx;
    }
    if (newPosition.dy + newHeight > canvasSize.height) {
      newHeight = canvasSize.height - newPosition.dy;
    }
    
    // For circles, maintain aspect ratio
    if (selectedShape_canvas!.type == 'Circle') {
      double size = math.min(newWidth, newHeight);
      newWidth = size;
      newHeight = size;
    }
    
    setState(() {
      selectedShape_canvas!.size = Size(newWidth, newHeight);
      selectedShape_canvas!.position = newPosition;
    });
  }

  void _onDragEnd() {
    if (selectedShape_canvas != null) {
      setState(() {
        selectedShape_canvas!.isDragging = false;
        if (!isResizing) {
          // Only exit long press mode if we weren't resizing
          isLongPressMode = false;
          longPressShape = null;
        }
        isResizing = false;
        resizeHandle = '';
        dragOffset = null;
      });
      _saveState();
    }
  }

  bool _isPointInShape(Offset point, CanvasShape shape) {
    if (shape.type == 'Circle') {
      double centerX = shape.position.dx + shape.size.width / 2;
      double centerY = shape.position.dy + shape.size.height / 2;
      double radius = shape.size.width / 2;
      double distance = math.sqrt(math.pow(point.dx - centerX, 2) + math.pow(point.dy - centerY, 2));
      return distance <= radius;
    } else {
      return point.dx >= shape.position.dx &&
             point.dx <= shape.position.dx + shape.size.width &&
             point.dy >= shape.position.dy &&
             point.dy <= shape.position.dy + shape.size.height;
    }
  }

  void _undo() {
    if (undoStack.isNotEmpty) {
      redoStack.add(List.from(shapes.map((s) => s.clone())));
      setState(() {
        shapes = undoStack.removeLast();
        selectedShape_canvas = null;
      });
    }
  }

  void _redo() {
    if (redoStack.isNotEmpty) {
      undoStack.add(List.from(shapes.map((s) => s.clone())));
      setState(() {
        shapes = redoStack.removeLast();
        selectedShape_canvas = null;
      });
    }
  }

  // void _zoomIn() {
  //   setState(() {
  //     canvasZoom = math.min(canvasZoom * 1.2, 3.0);
  //   });
  // }

  // void _zoomOut() {
  //   setState(() {
  //     canvasZoom = math.max(canvasZoom / 1.2, 0.5);
  //   });
  // }

  void _copyShape() {
    if (selectedShape_canvas != null) {
      copiedShape = selectedShape_canvas!.clone();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Shape copied'),
          duration: Duration(seconds: 1),
          backgroundColor: const Color.fromARGB(255, 3, 25, 55),
        ),
      );
    }
  }

  void _pasteShape() {
    if (copiedShape != null) {
      _saveState();
      redoStack.clear();
      
      Offset newPosition = _findNonOverlappingPosition(copiedShape!.size);
      
      setState(() {
        var newShape = copiedShape!.clone();
        newShape.position = newPosition;
        shapes.add(newShape);
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Shape pasted'),
          duration: Duration(seconds: 1),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _deleteSelectedShape() {
    if (selectedShape_canvas != null && !selectedShape_canvas!.isLocked) {
      _saveState();
      setState(() {
        shapes.remove(selectedShape_canvas);
        selectedShape_canvas = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Shape deleted'),
          duration: Duration(seconds: 1),
          backgroundColor: Colors.red,
        ),
      );
    } else if (selectedShape_canvas != null && selectedShape_canvas!.isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot delete locked shape'),
          duration: Duration(seconds: 1),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _resizeCanvas(double widthDelta, double heightDelta) {
    setState(() {
      double newWidth = math.max(400, canvasSize.width + widthDelta);
      double newHeight = math.max(400, canvasSize.height + heightDelta);
      
      // If reducing canvas size, ensure no shapes exceed new bounds
      if (widthDelta < 0 || heightDelta < 0) {
        for (var shape in shapes) {
          if (shape.position.dx + shape.size.width > newWidth) {
            newWidth = math.max(newWidth, shape.position.dx + shape.size.width + 10);
          }
          if (shape.position.dy + shape.size.height > newHeight) {
            newHeight = math.max(newHeight, shape.position.dy + shape.size.height + 10);
          }
        }
      }
      
      canvasSize = Size(newWidth, newHeight);
    });
  }

  void _reset() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reset Canvas'),
        content: Text('Are you sure you want to clear all shapes? This action cannot be undone.'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _saveState();
              setState(() {
                shapes.clear();
                canvasZoom = 1.0;
                selectedShape_canvas = null;
                copiedShape = null;
                isLongPressMode = false;
                longPressShape = null;
              });
            },
            child: Text('Reset'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _saveState() {
    undoStack.add(List.from(shapes.map((s) => s.clone())));
    if (undoStack.length > 20) {
      undoStack.removeAt(0);
    }
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ModernColorPicker(
            pickerColor: selectedColor,
            onColorChanged: (color) {
              setState(() {
                selectedColor = color;
                if (selectedShape_canvas != null) {
                  _saveState();
                  selectedShape_canvas!.color = color;
                }
              });
              Navigator.pop(context);
            },
          ),
        );
      },
    );
  }

  Future<ui.Image> _createCanvasImage() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // Create the painter and paint to the canvas
    final painter = CanvasPainter(
      shapes, 
      null,  // No selection
      null,  // No hover
      1.0,   // No zoom
      canvasSize, 
      false  // No long press mode
    );
    
    painter.paint(canvas, canvasSize);
    
    // Convert to image
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      canvasSize.width.toInt(),
      canvasSize.height.toInt(),
    );
    
    return image;
  }

  Future<void> _exportToPng() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Text('Exporting to PNG...'),
            ],
          ),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.blue,
        ),
      );

      // Create image directly from painter
      final ui.Image image = await _createCanvasImage();
      
      // Convert to PNG bytes
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData == null) {
        throw Exception('Failed to convert canvas to PNG bytes');
      }
      
      final Uint8List pngBytes = byteData.buffer.asUint8List();

      // Determine save directory based on platform
      Directory? directory;
      String locationName = '';
      
      try {
        if (Platform.isAndroid) {
          // Try Downloads folder first
          directory = Directory('/storage/emulated/0/Download');
          if (!await directory.exists()) {
            // Fallback to app directory
            directory = await getExternalStorageDirectory();
          }
          locationName = 'Downloads';
        } else if (Platform.isIOS) {
          directory = await getApplicationDocumentsDirectory();
          locationName = 'Documents';
        } else {
          // Desktop or other platforms
          directory = await getApplicationDocumentsDirectory();
          locationName = 'Documents';
        }
      } catch (e) {
        print('Platform detection error: $e, using fallback');
        directory = await getApplicationDocumentsDirectory();
        locationName = 'Documents';
      }
      
      if (directory == null) {
        throw Exception('Could not access storage directory');
      }

      // Create filename with timestamp
      final String timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final String companyName = _nameController.text.isNotEmpty 
          ? _nameController.text.replaceAll(' ', '_').replaceAll(RegExp(r'[^\w-]'), '')
          : 'company';
      final String fileName = '${companyName}_layout_$timestamp.png';
      final String filePath = '${directory.path}/$fileName';
      
      // Save file
      final File file = File(filePath);
      await file.writeAsBytes(pngBytes);

      // Verify file was created and get size
      if (!await file.exists()) {
        throw Exception('File was not created at: $filePath');
      }
      
      final int fileSize = await file.length();
      final String fileSizeStr = fileSize > 1024 * 1024 
          ? '${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB'
          : '${(fileSize / 1024).toStringAsFixed(2)} KB';

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 24),
                  SizedBox(width: 12),
                  Text(
                    '✅ Exported Successfully!',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.insert_drive_file, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            fileName,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.folder_open, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$locationName: ${directory.path}',
                            style: TextStyle(fontSize: 11),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Size: $fileSizeStr | ${canvasSize.width.toInt()}x${canvasSize.height.toInt()}px | ${shapes.length} shapes',
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 10),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );

      print('✅ ========================================');
      print('✅ CANVAS EXPORT SUCCESSFUL!');
      print('✅ ========================================');
      print('📁 File: $fileName');
      print('📂 Path: $filePath');
      print('📏 Size: $fileSizeStr');
      print('🎨 Shapes: ${shapes.length}');
      print('📐 Dimensions: ${canvasSize.width.toInt()} x ${canvasSize.height.toInt()} px');
      print('✅ ========================================');
    } catch (e, stackTrace) {
      print('❌ ========================================');
      print('❌ EXPORT FAILED!');
      print('❌ ========================================');
      print('❌ Error: $e');
      print('📍 Stack trace:');
      print(stackTrace);
      print('❌ ========================================');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white, size: 24),
                  SizedBox(width: 12),
                  Text(
                    'Export Failed',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  e.toString(),
                  style: TextStyle(fontSize: 12),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _exportToPng(),
          ),
        ),
      );
    }
  }

  void _showUserAssignmentDialog() {
    if (selectedShape_canvas == null) return;
    
    List<String> tempSelectedUsers = List.from(selectedShape_canvas!.assigned);
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.people, color: const Color.fromARGB(255, 3, 25, 55)),
                SizedBox(width: 12),
                Text('Assign Users'),
              ],
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Container(
              width: double.maxFinite,
              child: availableUsers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Loading users...'),
                        ],
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: availableUsers.length,
                      itemBuilder: (context, index) {
                        final user = availableUsers[index];
                        final isSelected = tempSelectedUsers.contains(user.username);
                        
                        return CheckboxListTile(
                          title: Text(user.username),
                          subtitle: Text(user.role),
                          secondary: CircleAvatar(
                            backgroundColor: isSelected ? const Color.fromARGB(255, 3, 25, 55) : Colors.grey.shade300,
                            child: Text(
                              user.username[0].toUpperCase(),
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.grey.shade700,
                              ),
                            ),
                          ),
                          value: isSelected,
                          onChanged: (bool? value) {
                            setDialogState(() {
                              if (value == true) {
                                tempSelectedUsers.add(user.username);
                              } else {
                                tempSelectedUsers.remove(user.username);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    selectedShape_canvas!.assigned = tempSelectedUsers;
                  });
                  Navigator.pop(context);
                  _saveState();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(tempSelectedUsers.isEmpty 
                          ? 'Users unassigned' 
                          : 'Assigned ${tempSelectedUsers.length} user(s)'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 3, 25, 55),
                  foregroundColor: Colors.white,
                ),
                child: Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }
  
  
  
  Future<void> _saveCompany() async {
    const url = '${AppConfig.baseUrl}company';
    
    String colorToHex(Color color) {
      return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
    }
    
    // Helper to convert usernames to user IDs
    List<String> getUserIds(List<String> usernames) {
      return usernames
          .map((username) {
            final user = availableUsers.firstWhere(
              (u) => u.username == username,
              orElse: () => User(id: '', username: username, email: '', role: '', contact: '', address: ''),
            );
            return user.id;
          })
          .where((id) => id.isNotEmpty)
          .toList();
    }
    
    List<Map<String, dynamic>> layout = shapes.map((shape) {
      return {
        'id': shape.id,
        'name': shape.name,
        'shape': shape.type.toLowerCase(),
        'x': shape.position.dx.round(),
        'y': shape.position.dy.round(),
        'width': shape.size.width.round(),
        'height': shape.size.height.round(),
        'color': colorToHex(shape.color),
        'fontSize': 12,
        'textColor': '#000000',
        'assigned': getUserIds(shape.assigned), // CHANGED: Convert usernames to IDs
        'isLocked': shape.isLocked,
      };
    }).toList();
    
    // Create the complete JSON structure
    final companyData = {
      'name': _nameController.text,
      'address': _addressController.text,
      'contact': _contactController.text,
      'phone': _phoneController.text,
      'email': _emailController.text,
      'role': 'Owner', // You can make this configurable if needed
      'layout': layout,
      'canvasSize': {
        'width': canvasSize.width.round(),
        'height': canvasSize.height.round(),
      },
      'createdBy': 1, // You should replace this with actual user ID
      'createdAt': {
        '_seconds': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        '_nanoseconds': (DateTime.now().millisecondsSinceEpoch % 1000) * 1000000,
      },
    };
    
    // //print the JSON for debugging (you can remove this in production)
    //print('Company Data JSON:');
    //print(companyData);

    if(_idController.text == ''){
      await _apiService.postRequest(url, companyData);
    }else{
      final newurl = url + '/${_idController.text}';
      await _apiService.putRequest(newurl, companyData);
    }

    
    
    Navigator.pop(context, companyData);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 16),
            Text('Company saved successfully!'),
          ],
        ),
        backgroundColor: const Color.fromARGB(255, 3, 25, 55),
      ),
    );
  }


  
  void _showErrorSnackBar(String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.white),
          SizedBox(width: 16),
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
          Icon(Icons.check_circle, color: Colors.white),
          SizedBox(width: 16),
          Text(message),
        ],
      ),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

int _getCurrentUserId() {
  // Replace this with actual user ID from your authentication system
  // For example: return AuthService.currentUser?.id ?? 1;
  return 1;
}

// Add these state variables at the top of your _CompanyScreenState class:
//bool isLoading = false;
bool isCreating = false;
bool isUpdating = false;
bool isDeleting = false;

  Future<void> _fetchCompanies() async {
    try {
      setState(() => isLoading = true);
      const url = '${AppConfig.baseUrl}companies';

      final data = await _apiService.getRequest(url);

      if (data != null) {
        //print('Fetched COMPANIES ::::>$data');
        
        List<dynamic> companiesData = [];
        
        if (data != null) {
          companiesData = data;
        }

        // Convert to Company objects
        final fetchedCompanies = companiesData
            .map((companyData) {
              if (companyData is Map<String, dynamic>) {
                return companyData; // Store as Map<String, dynamic> for now
              } else {
                throw Exception('Invalid company data format');
              }
            })
            .toList();

        setState(() {
          _companies.clear();
          _companies.addAll(fetchedCompanies.map((company) => 
            Map<String, String>.from({
              'id': company['id']?.toString() ?? '',
              'name': company['name']?.toString() ?? '',
              'contact': company['contact']?.toString() ?? '',
              'email': company['email']?.toString() ?? '',
              'phone': company['phone']?.toString() ?? '',
              'address': company['address']?.toString() ?? '',
              'role': company['role']?.toString() ?? '',
            })
          ).toList());
          isLoading = false;
        });
        
        _animationController.forward();
        //print('Successfully loaded ${_companies.length} companies');
      } else {
        throw Exception('Failed to fetch companies');
      }
    } catch (e) {
      //print('Error fetching companies: $e');
      _showErrorSnackBar('Failed to load companies: ${e.toString()}');
      setState(() => isLoading = false);
    }
  }

  // 2. Get single company by ID
  Future<Map<String, dynamic>?> _getCompany(String companyId) async {
    try {
      final url = '${AppConfig.baseUrl}companies/$companyId';
      
      final data = await _apiService.getRequest(url);
      
      if (data != null) {
        //print('Fetched COMPANY ::::>$data');
        return data as Map<String, dynamic>;
      } else {
        throw Exception('Failed to fetch company');
      }
    } catch (e) {
      //print('Error fetching company: $e');
      _showErrorSnackBar('Failed to load company: ${e.toString()}');
      return null;
    }
  }

  // 3. Create new company
  Future<void> _createCompany(Map<String, dynamic> companyData) async {
    try {
      setState(() => isCreating = true);
      const url = '${AppConfig.baseUrl}companies';
      
      // Prepare the data for API
      final apiData = {
        'name': companyData['name'],
        'address': companyData['address'],
        'contact': companyData['contact'],
        'phone': companyData['phone'],
        'email': companyData['email'],
        'role': companyData['role'] ?? 'Owner',
        'layout': companyData['layout'] ?? [],
        'canvasSize': companyData['canvasSize'] ?? {
          'width': 800,
          'height': 600
        },
        'createdBy': _getCurrentUserId(), // Replace with actual user ID
        'createdAt': DateTime.now().toIso8601String(),
      };
      
      final response = await _apiService.postRequest(url, apiData);
      
      if (response != null) {
        //print('Created COMPANY ::::>$response');
        
        // Add the new company to the list
        setState(() {
          _companies.add(Map<String, String>.from({
            'id': response['id']?.toString() ?? '',
            'name': response['name']?.toString() ?? '',
            'contact': response['contact']?.toString() ?? '',
            'email': response['email']?.toString() ?? '',
            'phone': response['phone']?.toString() ?? '',
            'address': response['address']?.toString() ?? '',
            'role': response['role']?.toString() ?? '',
          }));
          isCreating = false;
        });
        
        _showSuccessSnackBar('Company created successfully!');
        
        // Optionally refresh the list
        await _fetchCompanies();
      } else {
        throw Exception('Failed to create company');
      }
    } catch (e) {
      //print('Error creating company: $e');
      _showErrorSnackBar('Failed to create company: ${e.toString()}');
      setState(() => isCreating = false);
    }
  }

  // 4. Update existing company
  Future<void> _updateCompany(String companyId, Map<String, dynamic> updatedData) async {
    try {
      setState(() => isUpdating = true);
      final url = '${AppConfig.baseUrl}companies/$companyId';
      
      // Prepare the update data
      final apiData = {
        'name': updatedData['name'],
        'address': updatedData['address'],
        'contact': updatedData['contact'],
        'phone': updatedData['phone'],
        'email': updatedData['email'],
        'role': updatedData['role'],
        'layout': updatedData['layout'],
        'canvasSize': updatedData['canvasSize'],
        'updatedAt': DateTime.now().toIso8601String(),
      };
      
      final response = await _apiService.putRequest(url, apiData);
      
      if (response != null) {
        //print('Updated COMPANY ::::>$response');
        
        // Update the company in the local list
        setState(() {
          final index = _companies.indexWhere((c) => c['id'] == companyId);
          if (index != -1) {
            _companies[index] = Map<String, String>.from({
              'id': companyId,
              'name': response['name']?.toString() ?? '',
              'contact': response['contact']?.toString() ?? '',
              'email': response['email']?.toString() ?? '',
              'phone': response['phone']?.toString() ?? '',
              'address': response['address']?.toString() ?? '',
              'role': response['role']?.toString() ?? '',
            });
          }
          isUpdating = false;
        });
        
        _showSuccessSnackBar('Company updated successfully!');
      } else {
        throw Exception('Failed to update company');
      }
    } catch (e) {
      //print('Error updating company: $e');
      _showErrorSnackBar('Failed to update company: ${e.toString()}');
      setState(() => isUpdating = false);
    }
  }

  // 5. Delete company
  


}