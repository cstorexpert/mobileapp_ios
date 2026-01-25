import 'dart:convert';
import 'package:countx/screens/barcode.dart';
import 'package:countx/screens/company.dart';
import 'package:countx/screens/inventory.dart';
// import 'package:countx/screens/streams/aggregate-stock-report.dart';
// import 'package:countx/screens/streams/customer-node-status.dart';
// import 'package:countx/screens/streams/dashboard.dart';
// import 'package:countx/screens/streams/trend_report.dart';
import 'package:flutter/material.dart';
import 'package:countx/drawer.dart';
import 'package:countx/screens/transactions.dart';
import 'package:countx/screens/users.dart';
import 'package:countx/screens/shortcode.dart';
// import 'package:countx/screens/streams/notification_screen.dart';
// import 'package:countx/screens/streams/profile_screen.dart';

class StreamsPage extends StatefulWidget {
  const StreamsPage({super.key});

  @override
  State<StreamsPage> createState() => _StreamsPageState();
}

class _StreamsPageState extends State<StreamsPage> {
  String selectedPage = 'company';
  void setPage(String page) {
    setState(() {
      selectedPage = page;
    });
    Navigator.pop(context); // Close drawer
  }

  Widget getPageContent() {
    print('$selectedPage');
    switch (selectedPage) {
      case 'users':
        return UserManagementScreen();
      case 'company':
        return CompanyScreen();
      case 'shortcode':
        return ShortCodeManagementScreen();
      // case 'barcode':
      //   return const StockManagementScreen(allocatedSection: 'E-CIGARETTE',);
      case 'barcode':
        return TransactionScreen();
      // case 'inventory':
      //   return InventoryScanScreen();
      
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            SizedBox(width: 60),
            Text('CountX', style: TextStyle(color: Color.fromARGB(255, 2, 18, 31), fontSize: 25, fontWeight: FontWeight.bold)),
            // SizedBox(width: 5),
            // Text('|', style: TextStyle(color: Colors.black, fontSize: 20)),
            // SizedBox(width: 5),
            // Text('Streams', style: TextStyle(color: Colors.orange, fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          // IconButton(
          //   icon: const Icon(Icons.person_outline),
          //   onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen())),
          // ),
          // Stack(
          //   children: [
          //     IconButton(
          //       icon: const Icon(Icons.notifications_outlined),
          //       onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen())),
          //     ),
          //     const Positioned(
          //       right: 10,
          //       top: 10,
          //       child: CircleAvatar(radius: 5, backgroundColor: Colors.red),
          //     ),
          //   ],
          // ),
        ],
      ),
      drawer: AppDrawer(onItemTap: setPage),
      body: getPageContent(),
    );
  }
}