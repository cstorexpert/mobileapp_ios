// // import 'package:flutter/material.dart';
// // import 'package:camera/camera.dart';
// // import 'dart:async';
// // import 'dart:math' as math;

// // // Main Screen
// // class InventoryScanScreen extends StatefulWidget {
// //   const InventoryScanScreen({Key? key}) : super(key: key);

// //   @override
// //   State<InventoryScanScreen> createState() => _InventoryScanScreenState();
// // }

// // class _InventoryScanScreenState extends State<InventoryScanScreen>
// //     with TickerProviderStateMixin {
// //   CameraController? _cameraController;
// //   bool _isCameraInitialized = false;
// //   bool _isScanning = true;
// //   bool _showDepthView = false;
// //   List<DetectedItem> _detectedItems = [];
// //   late AnimationController _scanAnimationController;
// //   late AnimationController _itemAnimationController;

// //   // Mock detected items
// //   final List<Map<String, dynamic>> _mockDetections = [
// //     {'name': 'Coca-Cola Can', 'count': 12, 'confidence': 0.95},
// //     {'name': 'Pepsi Can', 'count': 8, 'confidence': 0.92},
// //     {'name': 'Sprite Bottle', 'count': 15, 'confidence': 0.89},
// //     {'name': 'Water Bottle', 'count': 20, 'confidence': 0.93},
// //   ];

// //   @override
// //   void initState() {
// //     super.initState();
// //     _initializeCamera();
// //     _scanAnimationController = AnimationController(
// //       vsync: this,
// //       duration: const Duration(seconds: 2),
// //     )..repeat();
// //     _itemAnimationController = AnimationController(
// //       vsync: this,
// //       duration: const Duration(milliseconds: 500),
// //     );
// //     _startMockDetection();
// //   }

// //   Future<void> _initializeCamera() async {
// //     try {
// //       final cameras = await availableCameras();
// //       if (cameras.isEmpty) return;

// //       _cameraController = CameraController(
// //         cameras.first,
// //         ResolutionPreset.high,
// //         enableAudio: false,
// //       );

// //       await _cameraController!.initialize();
// //       if (mounted) {
// //         setState(() {
// //           _isCameraInitialized = true;
// //         });
// //       }
// //     } catch (e) {
// //       debugPrint('Camera initialization error: $e');
// //     }
// //   }

// //   void _startMockDetection() {
// //     Future.delayed(const Duration(milliseconds: 1500), () {
// //       if (mounted && _isScanning) {
// //         setState(() {
// //           _detectedItems = _mockDetections
// //               .asMap()
// //               .entries
// //               .map((entry) => DetectedItem(
// //                     name: entry.value['name'],
// //                     count: entry.value['count'],
// //                     confidence: entry.value['confidence'],
// //                     boundingBox: _generateMockBoundingBox(entry.key),
// //                   ))
// //               .toList();
// //         });
// //         _itemAnimationController.forward(from: 0);
// //       }
// //     });
// //   }

// //   Rect _generateMockBoundingBox(int index) {
// //     final random = math.Random(index);
// //     final left = 50.0 + random.nextDouble() * 200;
// //     final top = 100.0 + (index * 120.0);
// //     return Rect.fromLTWH(left, top, 150 + random.nextDouble() * 100, 80);
// //   }

// //   void _rescan() {
// //     setState(() {
// //       _detectedItems.clear();
// //       _isScanning = true;
// //     });
// //     _startMockDetection();
// //   }

// //   void _confirmCount() {
// //     showDialog(
// //       context: context,
// //       builder: (context) => AlertDialog(
// //         backgroundColor: const Color(0xFF1E1E1E),
// //         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
// //         title: const Text(
// //           'Confirm Count',
// //           style: TextStyle(color: Colors.white, fontFamily: 'Inter'),
// //         ),
// //         content: Text(
// //           'Total items detected: ${_detectedItems.fold<int>(0, (sum, item) => sum + item.count)}',
// //           style: const TextStyle(color: Colors.white70, fontFamily: 'Inter'),
// //         ),
// //         actions: [
// //           TextButton(
// //             onPressed: () => Navigator.pop(context),
// //             child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
// //           ),
// //           ElevatedButton(
// //             onPressed: () {
// //               Navigator.pop(context);
// //               // Proceed to verification
// //             },
// //             style: ElevatedButton.styleFrom(
// //               backgroundColor: const Color(0xFF00C853),
// //               shape: RoundedRectangleBorder(
// //                 borderRadius: BorderRadius.circular(8),
// //               ),
// //             ),
// //             child: const Text('Confirm',
// //                 style: TextStyle(fontFamily: 'Inter', color: Colors.white)),
// //           ),
// //         ],
// //       ),
// //     );
// //   }

// //   void _toggleDepthView() {
// //     setState(() {
// //       _showDepthView = !_showDepthView;
// //     });
// //   }

// //   @override
// //   void dispose() {
// //     _cameraController?.dispose();
// //     _scanAnimationController.dispose();
// //     _itemAnimationController.dispose();
// //     super.dispose();
// //   }

// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       backgroundColor: const Color(0xFF121212),
// //       body: Stack(
// //         children: [
// //           // Camera Preview
// //           if (_isCameraInitialized && _cameraController != null)
// //             SizedBox.expand(
// //               child: CameraPreview(_cameraController!),
// //             )
// //           else
// //             Container(
// //               color: const Color(0xFF121212),
// //               child: const Center(
// //                 child: CircularProgressIndicator(color: Color(0xFF00C853)),
// //               ),
// //             ),

// //           // Semi-transparent overlay
// //           Container(
// //             color: Colors.black.withOpacity(0.3),
// //           ),

// //           // Detection Overlay
// //           if (_detectedItems.isNotEmpty)
// //             DetectionOverlay(
// //               detectedItems: _detectedItems,
// //               animation: _itemAnimationController,
// //             ),

// //           // Depth View Overlay
// //           if (_showDepthView)
// //             DepthViewOverlay(
// //               detectedItems: _detectedItems,
// //             ),

// //           // Scanning Indicator
// //           if (_isScanning && _detectedItems.isEmpty)
// //             Center(
// //               child: AnimatedBuilder(
// //                 animation: _scanAnimationController,
// //                 builder: (context, child) {
// //                   return Column(
// //                     mainAxisSize: MainAxisSize.min,
// //                     children: [
// //                       SizedBox(
// //                         width: 60,
// //                         height: 60,
// //                         child: CircularProgressIndicator(
// //                           value: _scanAnimationController.value,
// //                           strokeWidth: 3,
// //                           valueColor: const AlwaysStoppedAnimation<Color>(
// //                             Color(0xFF00C853),
// //                           ),
// //                         ),
// //                       ),
// //                       const SizedBox(height: 16),
// //                       const Text(
// //                         'Scanning inventory...',
// //                         style: TextStyle(
// //                           color: Colors.white,
// //                           fontSize: 16,
// //                           fontFamily: 'Inter',
// //                           fontWeight: FontWeight.w500,
// //                         ),
// //                       ),
// //                     ],
// //                   );
// //                 },
// //               ),
// //             ),

// //           // Top Counter
// //           Positioned(
// //             top: 50,
// //             right: 20,
// //             child: TotalItemsCounter(
// //               totalItems: _detectedItems.fold<int>(
// //                 0,
// //                 (sum, item) => sum + item.count,
// //               ),
// //             ),
// //           ),

// //           // Bottom Controls
// //           Positioned(
// //             bottom: 40,
// //             left: 0,
// //             right: 0,
// //             child: BottomControls(
// //               onRescan: _rescan,
// //               onConfirm: _confirmCount,
// //               onToggleDepth: _toggleDepthView,
// //               depthViewActive: _showDepthView,
// //             ),
// //           ),

// //           // Safe Area for status bar
// //           Positioned(
// //             top: 0,
// //             left: 0,
// //             right: 0,
// //             child: Container(
// //               height: MediaQuery.of(context).padding.top,
// //               color: Colors.black.withOpacity(0.5),
// //             ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// // }

// // // Detected Item Model
// // class DetectedItem {
// //   final String name;
// //   final int count;
// //   final double confidence;
// //   final Rect boundingBox;

// //   DetectedItem({
// //     required this.name,
// //     required this.count,
// //     required this.confidence,
// //     required this.boundingBox,
// //   });
// // }

// // // Detection Overlay Widget
// // class DetectionOverlay extends StatelessWidget {
// //   final List<DetectedItem> detectedItems;
// //   final Animation<double> animation;

// //   const DetectionOverlay({
// //     Key? key,
// //     required this.detectedItems,
// //     required this.animation,
// //   }) : super(key: key);

// //   @override
// //   Widget build(BuildContext context) {
// //     return CustomPaint(
// //       painter: DetectionPainter(
// //         detectedItems: detectedItems,
// //         animation: animation,
// //       ),
// //       child: Stack(
// //         children: detectedItems.map((item) {
// //           return AnimatedBuilder(
// //             animation: animation,
// //             builder: (context, child) {
// //               return Positioned(
// //                 left: item.boundingBox.left,
// //                 top: item.boundingBox.top - 30,
// //                 child: FadeTransition(
// //                   opacity: animation,
// //                   child: ScaleTransition(
// //                     scale: Tween<double>(begin: 0.8, end: 1.0).animate(
// //                       CurvedAnimation(
// //                         parent: animation,
// //                         curve: Curves.easeOutBack,
// //                       ),
// //                     ),
// //                     child: ItemLabel(item: item),
// //                   ),
// //                 ),
// //               );
// //             },
// //           );
// //         }).toList(),
// //       ),
// //     );
// //   }
// // }

// // // Detection Painter
// // class DetectionPainter extends CustomPainter {
// //   final List<DetectedItem> detectedItems;
// //   final Animation<double> animation;

// //   DetectionPainter({
// //     required this.detectedItems,
// //     required this.animation,
// //   }) : super(repaint: animation);

// //   @override
// //   void paint(Canvas canvas, Size size) {
// //     final paint = Paint()
// //       ..color = const Color(0xFF00C853).withOpacity(0.8 * animation.value)
// //       ..style = PaintingStyle.stroke
// //       ..strokeWidth = 3;

// //     final cornerPaint = Paint()
// //       ..color = const Color(0xFF00C853)
// //       ..style = PaintingStyle.stroke
// //       ..strokeWidth = 4
// //       ..strokeCap = StrokeCap.round;

// //     for (var item in detectedItems) {
// //       final rect = item.boundingBox;

// //       // Draw corner brackets
// //       const cornerLength = 20.0;

// //       // Top-left corner
// //       canvas.drawLine(
// //         rect.topLeft,
// //         rect.topLeft + const Offset(cornerLength, 0),
// //         cornerPaint,
// //       );
// //       canvas.drawLine(
// //         rect.topLeft,
// //         rect.topLeft + const Offset(0, cornerLength),
// //         cornerPaint,
// //       );

// //       // Top-right corner
// //       canvas.drawLine(
// //         rect.topRight,
// //         rect.topRight + const Offset(-cornerLength, 0),
// //         cornerPaint,
// //       );
// //       canvas.drawLine(
// //         rect.topRight,
// //         rect.topRight + const Offset(0, cornerLength),
// //         cornerPaint,
// //       );

// //       // Bottom-left corner
// //       canvas.drawLine(
// //         rect.bottomLeft,
// //         rect.bottomLeft + const Offset(cornerLength, 0),
// //         cornerPaint,
// //       );
// //       canvas.drawLine(
// //         rect.bottomLeft,
// //         rect.bottomLeft + const Offset(0, -cornerLength),
// //         cornerPaint,
// //       );

// //       // Bottom-right corner
// //       canvas.drawLine(
// //         rect.bottomRight,
// //         rect.bottomRight + const Offset(-cornerLength, 0),
// //         cornerPaint,
// //       );
// //       canvas.drawLine(
// //         rect.bottomRight,
// //         rect.bottomRight + const Offset(0, -cornerLength),
// //         cornerPaint,
// //       );
// //     }
// //   }

// //   @override
// //   bool shouldRepaint(DetectionPainter oldDelegate) => true;
// // }

// // // Item Label Widget
// // class ItemLabel extends StatelessWidget {
// //   final DetectedItem item;

// //   const ItemLabel({Key? key, required this.item}) : super(key: key);

// //   @override
// //   Widget build(BuildContext context) {
// //     return Container(
// //       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
// //       decoration: BoxDecoration(
// //         color: const Color(0xFF00C853),
// //         borderRadius: BorderRadius.circular(8),
// //         boxShadow: [
// //           BoxShadow(
// //             color: const Color(0xFF00C853).withOpacity(0.3),
// //             blurRadius: 8,
// //             offset: const Offset(0, 2),
// //           ),
// //         ],
// //       ),
// //       child: Row(
// //         mainAxisSize: MainAxisSize.min,
// //         children: [
// //           Text(
// //             item.name,
// //             style: const TextStyle(
// //               color: Colors.white,
// //               fontSize: 14,
// //               fontWeight: FontWeight.w600,
// //               fontFamily: 'Inter',
// //             ),
// //           ),
// //           const SizedBox(width: 8),
// //           Container(
// //             padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
// //             decoration: BoxDecoration(
// //               color: Colors.white.withOpacity(0.2),
// //               borderRadius: BorderRadius.circular(4),
// //             ),
// //             child: Text(
// //               '×${item.count}',
// //               style: const TextStyle(
// //                 color: Colors.white,
// //                 fontSize: 12,
// //                 fontWeight: FontWeight.bold,
// //                 fontFamily: 'Inter',
// //               ),
// //             ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// // }

// // // Total Items Counter
// // class TotalItemsCounter extends StatelessWidget {
// //   final int totalItems;

// //   const TotalItemsCounter({Key? key, required this.totalItems})
// //       : super(key: key);

// //   @override
// //   Widget build(BuildContext context) {
// //     return Container(
// //       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
// //       decoration: BoxDecoration(
// //         color: const Color(0xFF1E1E1E).withOpacity(0.9),
// //         borderRadius: BorderRadius.circular(20),
// //         border: Border.all(color: const Color(0xFF00C853), width: 2),
// //         boxShadow: [
// //           BoxShadow(
// //             color: const Color(0xFF00C853).withOpacity(0.2),
// //             blurRadius: 12,
// //             offset: const Offset(0, 4),
// //           ),
// //         ],
// //       ),
// //       child: Row(
// //         mainAxisSize: MainAxisSize.min,
// //         children: [
// //           const Icon(
// //             Icons.inventory_2_rounded,
// //             color: Color(0xFF00C853),
// //             size: 20,
// //           ),
// //           const SizedBox(width: 8),
// //           Text(
// //             'Total: $totalItems',
// //             style: const TextStyle(
// //               color: Colors.white,
// //               fontSize: 16,
// //               fontWeight: FontWeight.bold,
// //               fontFamily: 'Inter',
// //             ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// // }

// // // Bottom Controls
// // class BottomControls extends StatelessWidget {
// //   final VoidCallback onRescan;
// //   final VoidCallback onConfirm;
// //   final VoidCallback onToggleDepth;
// //   final bool depthViewActive;

// //   const BottomControls({
// //     Key? key,
// //     required this.onRescan,
// //     required this.onConfirm,
// //     required this.onToggleDepth,
// //     required this.depthViewActive,
// //   }) : super(key: key);

// //   @override
// //   Widget build(BuildContext context) {
// //     return Padding(
// //       padding: const EdgeInsets.symmetric(horizontal: 20),
// //       child: Row(
// //         mainAxisAlignment: MainAxisAlignment.spaceEvenly,
// //         children: [
// //           _ControlButton(
// //             icon: Icons.refresh_rounded,
// //             label: 'Rescan',
// //             onPressed: onRescan,
// //             color: const Color(0xFF2196F3),
// //           ),
// //           _ControlButton(
// //             icon: Icons.check_circle_rounded,
// //             label: 'Confirm',
// //             onPressed: onConfirm,
// //             color: const Color(0xFF00C853),
// //           ),
// //           _ControlButton(
// //             icon: depthViewActive
// //                 ? Icons.layers_rounded
// //                 : Icons.layers_outlined,
// //             label: 'Depth',
// //             onPressed: onToggleDepth,
// //             color: depthViewActive
// //                 ? const Color(0xFFFF9800)
// //                 : const Color(0xFF757575),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// // }

// // // Control Button
// // class _ControlButton extends StatelessWidget {
// //   final IconData icon;
// //   final String label;
// //   final VoidCallback onPressed;
// //   final Color color;

// //   const _ControlButton({
// //     Key? key,
// //     required this.icon,
// //     required this.label,
// //     required this.onPressed,
// //     required this.color,
// //   }) : super(key: key);

// //   @override
// //   Widget build(BuildContext context) {
// //     return Material(
// //       color: Colors.transparent,
// //       child: InkWell(
// //         onTap: onPressed,
// //         borderRadius: BorderRadius.circular(16),
// //         child: Container(
// //           padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
// //           decoration: BoxDecoration(
// //             color: const Color(0xFF1E1E1E).withOpacity(0.95),
// //             borderRadius: BorderRadius.circular(16),
// //             border: Border.all(color: color.withOpacity(0.5), width: 1.5),
// //             boxShadow: [
// //               BoxShadow(
// //                 color: color.withOpacity(0.2),
// //                 blurRadius: 8,
// //                 offset: const Offset(0, 2),
// //               ),
// //             ],
// //           ),
// //           child: Column(
// //             mainAxisSize: MainAxisSize.min,
// //             children: [
// //               Icon(icon, color: color, size: 28),
// //               const SizedBox(height: 4),
// //               Text(
// //                 label,
// //                 style: TextStyle(
// //                   color: color,
// //                   fontSize: 12,
// //                   fontWeight: FontWeight.w600,
// //                   fontFamily: 'Inter',
// //                 ),
// //               ),
// //             ],
// //           ),
// //         ),
// //       ),
// //     );
// //   }
// // }

// // // Depth View Overlay
// // class DepthViewOverlay extends StatelessWidget {
// //   final List<DetectedItem> detectedItems;

// //   const DepthViewOverlay({Key? key, required this.detectedItems})
// //       : super(key: key);

// //   @override
// //   Widget build(BuildContext context) {
// //     return CustomPaint(
// //       painter: DepthPainter(detectedItems: detectedItems),
// //     );
// //   }
// // }

// // // Depth Painter
// // class DepthPainter extends CustomPainter {
// //   final List<DetectedItem> detectedItems;

// //   DepthPainter({required this.detectedItems});

// //   @override
// //   void paint(Canvas canvas, Size size) {
// //     final random = math.Random(42);

// //     for (var item in detectedItems) {
// //       final rect = item.boundingBox;
// //       final depth = random.nextDouble();

// //       // Color gradient from blue (close) to red (far)
// //       final color = Color.lerp(
// //         const Color(0xFF2196F3),
// //         const Color(0xFFF44336),
// //         depth,
// //       )!;

// //       final paint = Paint()
// //         ..color = color.withOpacity(0.4)
// //         ..style = PaintingStyle.fill;

// //       canvas.drawRect(rect, paint);
// //     }
// //   }

// //   @override
// //   bool shouldRepaint(DepthPainter oldDelegate) => false;
// // }


// import 'package:flutter/material.dart';
// import 'package:camera/camera.dart';
// import 'dart:async';
// import 'dart:math' as math;

// // Main Screen
// class InventoryScanScreen extends StatefulWidget {
//   const InventoryScanScreen({Key? key}) : super(key: key);

//   @override
//   State<InventoryScanScreen> createState() => _InventoryScanScreenState();
// }

// class _InventoryScanScreenState extends State<InventoryScanScreen>
//     with TickerProviderStateMixin {
//   CameraController? _cameraController;
//   bool _isCameraInitialized = false;
//   bool _isScanning = true;
//   bool _showDepthView = false;
//   List<DetectedItem> _detectedItems = [];
//   late AnimationController _scanAnimationController;
//   late AnimationController _itemAnimationController;

//   // Object Detection Service (inject via dependency injection)
//   late ObjectDetectionService _detectionService;
//   StreamSubscription<List<Detection>>? _detectionSubscription;

//   @override
//   void initState() {
//     super.initState();
//     _detectionService = ObjectDetectionService();
//     _initializeCamera();
//     _scanAnimationController = AnimationController(
//       vsync: this,
//       duration: const Duration(seconds: 2),
//     )..repeat();
//     _itemAnimationController = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 500),
//     );
//     _startRealTimeDetection();
//   }

//   Future<void> _initializeCamera() async {
//     try {
//       final cameras = await availableCameras();
//       if (cameras.isEmpty) return;

//       _cameraController = CameraController(
//         cameras.first,
//         ResolutionPreset.high,
//         enableAudio: false,
//       );

//       await _cameraController!.initialize();
      
//       // Start image stream for real-time detection
//       _cameraController!.startImageStream((CameraImage image) {
//         if (_isScanning) {
//           _detectionService.processFrame(image);
//         }
//       });

//       if (mounted) {
//         setState(() {
//           _isCameraInitialized = true;
//         });
//       }
//     } catch (e) {
//       debugPrint('Camera initialization error: $e');
//     }
//   }

//   void _startRealTimeDetection() {
//     _detectionSubscription = _detectionService.detectionStream.listen((detections) {
//       if (mounted && _isScanning) {
//         setState(() {
//           _detectedItems = detections.map((d) => DetectedItem(
//             name: d.label,
//             count: d.count,
//             confidence: d.confidence,
//             boundingBox: d.boundingBox,
//           )).toList();
//         });
//         _itemAnimationController.forward(from: 0);
//       }
//     });
//   }

//   void _rescan() {
//     setState(() {
//       _detectedItems.clear();
//       _isScanning = true;
//     });
//     _detectionService.reset();
//   }

//   void _confirmCount() {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         backgroundColor: const Color(0xFF1E1E1E),
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//         title: const Text(
//           'Confirm Count',
//           style: TextStyle(color: Colors.white, fontFamily: 'Inter'),
//         ),
//         content: Text(
//           'Total items detected: ${_detectedItems.fold<int>(0, (sum, item) => sum + item.count)}',
//           style: const TextStyle(color: Colors.white70, fontFamily: 'Inter'),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
//           ),
//           ElevatedButton(
//             onPressed: () {
//               Navigator.pop(context);
//               // Proceed to verification
//             },
//             style: ElevatedButton.styleFrom(
//               backgroundColor: const Color(0xFF00C853),
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(8),
//               ),
//             ),
//             child: const Text('Confirm',
//                 style: TextStyle(fontFamily: 'Inter', color: Colors.white)),
//           ),
//         ],
//       ),
//     );
//   }

//   void _toggleDepthView() {
//     setState(() {
//       _showDepthView = !_showDepthView;
//     });
//   }

//   @override
//   void dispose() {
//     _detectionSubscription?.cancel();
//     _cameraController?.dispose();
//     _scanAnimationController.dispose();
//     _itemAnimationController.dispose();
//     _detectionService.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFF121212),
//       body: Stack(
//         children: [
//           // Camera Preview
//           if (_isCameraInitialized && _cameraController != null)
//             SizedBox.expand(
//               child: CameraPreview(_cameraController!),
//             )
//           else
//             Container(
//               color: const Color(0xFF121212),
//               child: const Center(
//                 child: CircularProgressIndicator(color: Color(0xFF00C853)),
//               ),
//             ),

//           // Semi-transparent overlay
//           Container(
//             color: Colors.black.withOpacity(0.3),
//           ),

//           // Detection Overlay
//           if (_detectedItems.isNotEmpty)
//             DetectionOverlay(
//               detectedItems: _detectedItems,
//               animation: _itemAnimationController,
//             ),

//           // Depth View Overlay
//           if (_showDepthView)
//             DepthViewOverlay(
//               detectedItems: _detectedItems,
//             ),

//           // Scanning Indicator
//           if (_isScanning && _detectedItems.isEmpty)
//             Center(
//               child: AnimatedBuilder(
//                 animation: _scanAnimationController,
//                 builder: (context, child) {
//                   return Column(
//                     mainAxisSize: MainAxisSize.min,
//                     children: [
//                       SizedBox(
//                         width: 60,
//                         height: 60,
//                         child: CircularProgressIndicator(
//                           value: _scanAnimationController.value,
//                           strokeWidth: 3,
//                           valueColor: const AlwaysStoppedAnimation<Color>(
//                             Color(0xFF00C853),
//                           ),
//                         ),
//                       ),
//                       const SizedBox(height: 16),
//                       const Text(
//                         'Scanning inventory...',
//                         style: TextStyle(
//                           color: Colors.white,
//                           fontSize: 16,
//                           fontFamily: 'Inter',
//                           fontWeight: FontWeight.w500,
//                         ),
//                       ),
//                     ],
//                   );
//                 },
//               ),
//             ),

//           // Top Counter
//           Positioned(
//             top: 50,
//             right: 20,
//             child: TotalItemsCounter(
//               totalItems: _detectedItems.fold<int>(
//                 0,
//                 (sum, item) => sum + item.count,
//               ),
//             ),
//           ),

//           // Bottom Controls
//           Positioned(
//             bottom: 40,
//             left: 0,
//             right: 0,
//             child: BottomControls(
//               onRescan: _rescan,
//               onConfirm: _confirmCount,
//               onToggleDepth: _toggleDepthView,
//               depthViewActive: _showDepthView,
//             ),
//           ),

//           // Safe Area for status bar
//           Positioned(
//             top: 0,
//             left: 0,
//             right: 0,
//             child: Container(
//               height: MediaQuery.of(context).padding.top,
//               color: Colors.black.withOpacity(0.5),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// // Detected Item Model
// class DetectedItem {
//   final String name;
//   final int count;
//   final double confidence;
//   final Rect boundingBox;

//   DetectedItem({
//     required this.name,
//     required this.count,
//     required this.confidence,
//     required this.boundingBox,
//   });
// }

// // Detection Overlay Widget
// class DetectionOverlay extends StatelessWidget {
//   final List<DetectedItem> detectedItems;
//   final Animation<double> animation;

//   const DetectionOverlay({
//     Key? key,
//     required this.detectedItems,
//     required this.animation,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return CustomPaint(
//       painter: DetectionPainter(
//         detectedItems: detectedItems,
//         animation: animation,
//       ),
//       child: Stack(
//         children: detectedItems.map((item) {
//           return AnimatedBuilder(
//             animation: animation,
//             builder: (context, child) {
//               return Positioned(
//                 left: item.boundingBox.left,
//                 top: item.boundingBox.top - 30,
//                 child: FadeTransition(
//                   opacity: animation,
//                   child: ScaleTransition(
//                     scale: Tween<double>(begin: 0.8, end: 1.0).animate(
//                       CurvedAnimation(
//                         parent: animation,
//                         curve: Curves.easeOutBack,
//                       ),
//                     ),
//                     child: ItemLabel(item: item),
//                   ),
//                 ),
//               );
//             },
//           );
//         }).toList(),
//       ),
//     );
//   }
// }

// // Detection Painter
// class DetectionPainter extends CustomPainter {
//   final List<DetectedItem> detectedItems;
//   final Animation<double> animation;

//   DetectionPainter({
//     required this.detectedItems,
//     required this.animation,
//   }) : super(repaint: animation);

//   @override
//   void paint(Canvas canvas, Size size) {
//     final paint = Paint()
//       ..color = const Color(0xFF00C853).withOpacity(0.8 * animation.value)
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 3;

//     final cornerPaint = Paint()
//       ..color = const Color(0xFF00C853)
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 4
//       ..strokeCap = StrokeCap.round;

//     for (var item in detectedItems) {
//       final rect = item.boundingBox;

//       // Draw corner brackets
//       const cornerLength = 20.0;

//       // Top-left corner
//       canvas.drawLine(
//         rect.topLeft,
//         rect.topLeft + const Offset(cornerLength, 0),
//         cornerPaint,
//       );
//       canvas.drawLine(
//         rect.topLeft,
//         rect.topLeft + const Offset(0, cornerLength),
//         cornerPaint,
//       );

//       // Top-right corner
//       canvas.drawLine(
//         rect.topRight,
//         rect.topRight + const Offset(-cornerLength, 0),
//         cornerPaint,
//       );
//       canvas.drawLine(
//         rect.topRight,
//         rect.topRight + const Offset(0, cornerLength),
//         cornerPaint,
//       );

//       // Bottom-left corner
//       canvas.drawLine(
//         rect.bottomLeft,
//         rect.bottomLeft + const Offset(cornerLength, 0),
//         cornerPaint,
//       );
//       canvas.drawLine(
//         rect.bottomLeft,
//         rect.bottomLeft + const Offset(0, -cornerLength),
//         cornerPaint,
//       );

//       // Bottom-right corner
//       canvas.drawLine(
//         rect.bottomRight,
//         rect.bottomRight + const Offset(-cornerLength, 0),
//         cornerPaint,
//       );
//       canvas.drawLine(
//         rect.bottomRight,
//         rect.bottomRight + const Offset(0, -cornerLength),
//         cornerPaint,
//       );
//     }
//   }

//   @override
//   bool shouldRepaint(DetectionPainter oldDelegate) => true;
// }

// // Item Label Widget
// class ItemLabel extends StatelessWidget {
//   final DetectedItem item;

//   const ItemLabel({Key? key, required this.item}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//       decoration: BoxDecoration(
//         color: const Color(0xFF00C853),
//         borderRadius: BorderRadius.circular(8),
//         boxShadow: [
//           BoxShadow(
//             color: const Color(0xFF00C853).withOpacity(0.3),
//             blurRadius: 8,
//             offset: const Offset(0, 2),
//           ),
//         ],
//       ),
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Text(
//             item.name,
//             style: const TextStyle(
//               color: Colors.white,
//               fontSize: 14,
//               fontWeight: FontWeight.w600,
//               fontFamily: 'Inter',
//             ),
//           ),
//           const SizedBox(width: 8),
//           Container(
//             padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
//             decoration: BoxDecoration(
//               color: Colors.white.withOpacity(0.2),
//               borderRadius: BorderRadius.circular(4),
//             ),
//             child: Text(
//               '×${item.count}',
//               style: const TextStyle(
//                 color: Colors.white,
//                 fontSize: 12,
//                 fontWeight: FontWeight.bold,
//                 fontFamily: 'Inter',
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// // Total Items Counter
// class TotalItemsCounter extends StatelessWidget {
//   final int totalItems;

//   const TotalItemsCounter({Key? key, required this.totalItems})
//       : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
//       decoration: BoxDecoration(
//         color: const Color(0xFF1E1E1E).withOpacity(0.9),
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(color: const Color(0xFF00C853), width: 2),
//         boxShadow: [
//           BoxShadow(
//             color: const Color(0xFF00C853).withOpacity(0.2),
//             blurRadius: 12,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           const Icon(
//             Icons.inventory_2_rounded,
//             color: Color(0xFF00C853),
//             size: 20,
//           ),
//           const SizedBox(width: 8),
//           Text(
//             'Total: $totalItems',
//             style: const TextStyle(
//               color: Colors.white,
//               fontSize: 16,
//               fontWeight: FontWeight.bold,
//               fontFamily: 'Inter',
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// // Bottom Controls
// class BottomControls extends StatelessWidget {
//   final VoidCallback onRescan;
//   final VoidCallback onConfirm;
//   final VoidCallback onToggleDepth;
//   final bool depthViewActive;

//   const BottomControls({
//     Key? key,
//     required this.onRescan,
//     required this.onConfirm,
//     required this.onToggleDepth,
//     required this.depthViewActive,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 20),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//         children: [
//           _ControlButton(
//             icon: Icons.refresh_rounded,
//             label: 'Rescan',
//             onPressed: onRescan,
//             color: const Color(0xFF2196F3),
//           ),
//           _ControlButton(
//             icon: Icons.check_circle_rounded,
//             label: 'Confirm',
//             onPressed: onConfirm,
//             color: const Color(0xFF00C853),
//           ),
//           _ControlButton(
//             icon: depthViewActive
//                 ? Icons.layers_rounded
//                 : Icons.layers_outlined,
//             label: 'Depth',
//             onPressed: onToggleDepth,
//             color: depthViewActive
//                 ? const Color(0xFFFF9800)
//                 : const Color(0xFF757575),
//           ),
//         ],
//       ),
//     );
//   }
// }

// // Control Button
// class _ControlButton extends StatelessWidget {
//   final IconData icon;
//   final String label;
//   final VoidCallback onPressed;
//   final Color color;

//   const _ControlButton({
//     Key? key,
//     required this.icon,
//     required this.label,
//     required this.onPressed,
//     required this.color,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return Material(
//       color: Colors.transparent,
//       child: InkWell(
//         onTap: onPressed,
//         borderRadius: BorderRadius.circular(16),
//         child: Container(
//           padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
//           decoration: BoxDecoration(
//             color: const Color(0xFF1E1E1E).withOpacity(0.95),
//             borderRadius: BorderRadius.circular(16),
//             border: Border.all(color: color.withOpacity(0.5), width: 1.5),
//             boxShadow: [
//               BoxShadow(
//                 color: color.withOpacity(0.2),
//                 blurRadius: 8,
//                 offset: const Offset(0, 2),
//               ),
//             ],
//           ),
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               Icon(icon, color: color, size: 28),
//               const SizedBox(height: 4),
//               Text(
//                 label,
//                 style: TextStyle(
//                   color: color,
//                   fontSize: 12,
//                   fontWeight: FontWeight.w600,
//                   fontFamily: 'Inter',
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// // Depth View Overlay
// class DepthViewOverlay extends StatelessWidget {
//   final List<DetectedItem> detectedItems;

//   const DepthViewOverlay({Key? key, required this.detectedItems})
//       : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return CustomPaint(
//       painter: DepthPainter(detectedItems: detectedItems),
//     );
//   }
// }

// // Depth Painter
// class DepthPainter extends CustomPainter {
//   final List<DetectedItem> detectedItems;

//   DepthPainter({required this.detectedItems});

//   @override
//   void paint(Canvas canvas, Size size) {
//     final random = math.Random(42);

//     for (var item in detectedItems) {
//       final rect = item.boundingBox;
//       final depth = random.nextDouble();

//       // Color gradient from blue (close) to red (far)
//       final color = Color.lerp(
//         const Color(0xFF2196F3),
//         const Color(0xFFF44336),
//         depth,
//       )!;

//       final paint = Paint()
//         ..color = color.withOpacity(0.4)
//         ..style = PaintingStyle.fill;

//       canvas.drawRect(rect, paint);
//     }
//   }

//   @override
//   bool shouldRepaint(DepthPainter oldDelegate) => false;
// }

// // ============================================================================
// // OBJECT DETECTION SERVICE - Connect your AI model here
// // ============================================================================

// class Detection {
//   final String label;
//   final int count;
//   final double confidence;
//   final Rect boundingBox;

//   Detection({
//     required this.label,
//     required this.count,
//     required this.confidence,
//     required this.boundingBox,
//   });
// }

// class ObjectDetectionService {
//   final _detectionController = StreamController<List<Detection>>.broadcast();
//   Stream<List<Detection>> get detectionStream => _detectionController.stream;

//   // TODO: Initialize your TFLite model here
//   // Interpreter? _interpreter;
//   // IsolateInterpreter? _isolateInterpreter;

//   ObjectDetectionService() {
//     _initializeModel();
//   }

//   Future<void> _initializeModel() async {
//     // TODO: Load your TFLite model
//     // Example with tflite_flutter:
//     // _interpreter = await Interpreter.fromAsset('models/ssd_mobilenet.tflite');
    
//     // OR use Google ML Kit for simpler integration:
//     // _objectDetector = ObjectDetector(options: ObjectDetectorOptions(...));
    
//     debugPrint('Object Detection Model Ready');
//   }

//   void processFrame(CameraImage image) {
//     // TODO: Process camera frame with your model
//     // This is where you'll run inference on each frame
    
//     // Example flow:
//     // 1. Convert CameraImage to format your model expects (e.g., Float32List)
//     // 2. Run inference: _interpreter.run(inputTensor, outputTensor);
//     // 3. Parse output tensor to get bounding boxes, labels, scores
//     // 4. Group detections by label and count them
//     // 5. Emit results via stream
    
//     // For now, emit mock data (remove this when you connect real model)
//     _emitMockDetections();
//   }

//   // REMOVE THIS METHOD when you connect real detection
//   void _emitMockDetections() {
//     final mockResults = [
//       Detection(
//         label: 'Coca-Cola Can',
//         count: 12,
//         confidence: 0.95,
//         boundingBox: const Rect.fromLTWH(50, 100, 200, 80),
//       ),
//       Detection(
//         label: 'Pepsi Can',
//         count: 8,
//         confidence: 0.92,
//         boundingBox: const Rect.fromLTWH(80, 220, 180, 75),
//       ),
//       Detection(
//         label: 'Sprite Bottle',
//         count: 15,
//         confidence: 0.89,
//         boundingBox: const Rect.fromLTWH(70, 340, 220, 85),
//       ),
//       Detection(
//         label: 'Water Bottle',
//         count: 20,
//         confidence: 0.93,
//         boundingBox: const Rect.fromLTWH(90, 460, 200, 80),
//       ),
//     ];
    
//     _detectionController.add(mockResults);
//   }

//   void reset() {
//     _detectionController.add([]);
//   }

//   void dispose() {
//     _detectionController.close();
//     // TODO: Close interpreter
//     // _interpreter?.close();
//   }
// }

// // ============================================================================
// // INTEGRATION OPTIONS - Choose one based on your needs
// // ============================================================================

// /*
// OPTION 1: TensorFlow Lite (Recommended for custom models)
// ==========================================
// Dependencies:
//   tflite_flutter: ^0.10.4

// Steps:
// 1. Train/download an object detection model (SSD MobileNet, YOLO, etc.)
// 2. Place .tflite file in assets/models/
// 3. Load model: Interpreter.fromAsset('models/your_model.tflite')
// 4. Convert CameraImage → Input Tensor
// 5. Run inference and parse outputs

// Example:
//   final input = _preprocessImage(image);
//   final output = List.filled(1 * 10 * 4, 0).reshape([1, 10, 4]);
//   _interpreter.run(input, output);
//   final detections = _parseOutput(output);

// OPTION 2: Google ML Kit (Easiest, but limited customization)
// ==========================================
// Dependencies:
//   google_ml_kit: ^0.16.3

// Steps:
// 1. Use ObjectDetector with pre-trained models
// 2. Process InputImage from CameraImage
// 3. Get detections directly

// Example:
//   final inputImage = InputImage.fromBytes(...);
//   final objects = await _objectDetector.processImage(inputImage);

// OPTION 3: Edge Impulse (For IoT/Edge devices)
// ==========================================
// - Train model on Edge Impulse platform
// - Export as TFLite
// - Integrate similar to Option 1

// OPTION 4: Custom Backend API
// ==========================================
// - Send frames to your backend
// - Run detection on server (Python + YOLO/Detectron2)
// - Return results via WebSocket/REST

// For inventory counting specifically:
// - Use instance segmentation models (Mask R-CNN)
// - Apply shelf detection + object detection
// - Use depth estimation for behind-stock counting
// */