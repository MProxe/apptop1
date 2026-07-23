import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const StaticRigApp());
}

class StaticRigApp extends StatelessWidget {
  const StaticRigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          background: Colors.black,
          surface: Color(0xFF0A0A0A),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? txChar;
  BluetoothCharacteristic? rxChar;
  
  bool isConnected = false;
  double currentForce = 0.0;
  double peakForce = 0.0;
  
  List<FlSpot> forcePoints = [];
  double timeCounter = 0;

  final String serviceUuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  final String rxUuid = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";
  final String txUuid = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";

  void startScanAndConnect() async {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        if (r.device.platformName == "STATIC_FORCE_RIG") {
          FlutterBluePlus.stopScan();
          await connectToDevice(r.device);
          break;
        }
      }
    });
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    await device.connect();
    setState(() {
      targetDevice = device;
      isConnected = true;
    });

    List<BluetoothService> services = await device.discoverServices();
    for (var service in services) {
      if (service.uuid.toString().toUpperCase() == serviceUuid) {
        for (var char in service.characteristics) {
          if (char.uuid.toString().toUpperCase() == txUuid) {
            txChar = char;
            await txChar!.setNotifyValue(true);
            txChar!.lastValueStream.listen(handleData);
          }
          if (char.uuid.toString().toUpperCase() == rxUuid) {
            rxChar = char;
          }
        }
      }
    }
  }

  void handleData(List<int> value) {
    String dataStr = utf8.decode(value).trim();
    // Bóc tách dữ liệu từ ESP32 (Eforce:XX.X,peak:YY.Y)
    if (dataStr.startsWith("Eforce:")) {
      try {
        var parts = dataStr.replaceAll("Eforce:", "").split(",peak:");
        double force = double.parse(parts[0]);
        double peak = double.parse(parts[1]);

        setState(() {
          currentForce = force;
          peakForce = peak;
          timeCounter += 0.1;
          
          forcePoints.add(FlSpot(timeCounter, force));
          if (forcePoints.length > 50) { // Giữ lại 50 điểm gần nhất trên đồ thị
            forcePoints.removeAt(0);
          }
        });
      } catch (e) {
        // Bỏ qua nếu gói tin bị lỗi nhiễu
      }
    }
  }

  void resetPeak() {
    if (rxChar != null) {
      rxChar!.write(utf8.encode("r"));
      setState(() {
        peakForce = 0.0;
        forcePoints.clear();
        timeCounter = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Nút trạng thái kết nối
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isConnected ? Colors.grey[900] : Colors.cyanAccent,
                    foregroundColor: isConnected ? Colors.greenAccent : Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: isConnected ? null : startScanAndConnect,
                  child: Text(
                    isConnected ? "ĐÃ KẾT NỐI (BLE ACTIVE)" : "KẾT NỐI STATIC RIG",
                    style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 15),

              // Bảng Lực Tức Thời
              Expanded(
                flex: 2,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A0A),
                    border: Border.all(color: const Color(0xFF262626)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("LỰC TỨC THỜI", style: TextStyle(color: Color(0xFF737373), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
                      Text(currentForce.toStringAsFixed(2), style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900, fontFamily: 'monospace', color: Colors.white)),
                      const Text("KG", style: TextStyle(color: Color(0xFF525252), fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 15),

              // Bảng Lực Đỉnh (PEAK)
              Expanded(
                flex: 2,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF121212),
                    border: Border.all(color: const Color(0xFF404040)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("LỰC ĐỈNH (PEAK)", style: TextStyle(color: Color(0xFF737373), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
                      Text(peakForce.toStringAsFixed(2), style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900, fontFamily: 'monospace', color: Colors.white)),
                      const Text("KG", style: TextStyle(color: Color(0xFF525252), fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 15),

              // Khung Đồ Thị Sóng Lực Real-time
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.only(right: 15, top: 15, bottom: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A0A),
                    border: Border.all(color: const Color(0xFF262626)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: forcePoints,
                          isCurved: true,
                          color: Colors.white,
                          barWidth: 3,
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15),

              // Nút RESET PEAK
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: resetPeak,
                  child: const Text("RESET PEAK", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
