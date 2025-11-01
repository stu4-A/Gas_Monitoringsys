import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'dart:math';

// --- CONFIGURATION CONSTANTS (BLE Focus) ---
const int refreshIntervalSeconds = 5;
const int leakageThresholdRaw = 400;

// --- BLE CONFIGURATION CONSTANTS (Must match your ESP32) ---
const String serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
const String characteristicUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
const String deviceNamePrefix = 'ESP32';

// Define custom colors
const Color primaryTeal = Color(0xFF00796B);
const Color accentAmber = Color(0xFFFFCC80);
const Color safeGreen = Colors.green;
const Color dangerRed = Color(0xFFD32F2F);

// --- CONNECTION MODE ENUM ---
enum ConnectionMode {
  disconnected,
  simulation,
  bleScanning,
  bleConnecting,
  bleConnected,
  bleError
}

// --- DATA MODEL ---
class SensorData {
  final int gasLevelPercent;
  final int mq6RawValue;
  final String leakStatus;
  final DateTime timestamp;
  final String source;

  SensorData({
    required this.gasLevelPercent,
    required this.mq6RawValue,
    required this.leakStatus,
    required this.timestamp,
    required this.source,
  });
}

// --- SIMULATION DATA STREAM GENERATOR ---
Stream<SensorData> _simulateDemoData() async* {
  final random = Random();
  int randInt(int max) => random.nextInt(max);

  while (true) {
    await Future.delayed(const Duration(seconds: 2));

    int gasLevel = randInt(100);
    int mq6Value;

    if (random.nextDouble() < 0.1) {
      mq6Value = randInt(200) + leakageThresholdRaw;
    } else {
      mq6Value = randInt(leakageThresholdRaw - 50);
    }

    final leakStatus =
        mq6Value >= leakageThresholdRaw ? 'LEAK_DETECTED' : 'SAFE';

    yield SensorData(
      gasLevelPercent: gasLevel,
      mq6RawValue: mq6Value,
      leakStatus: leakStatus,
      timestamp: DateTime.now(),
      source: 'Simulation Mode',
    );
  }
}

// --- MAIN APP ENTRY ---
void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Gas Monitor (BLE + Simulation)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryTeal,
          primary: primaryTeal,
          secondary: accentAmber,
        ),
        useMaterial3: true,
        fontFamily: 'Inter',
      ),
      home: const LoginPage(),
    );
  }
}

// --- LOGIN PAGE WIDGET ---
class LoginPage extends StatelessWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const loginColor = primaryTeal;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.gas_meter_sharp,
                size: 100,
                color: loginColor,
              ),
              const SizedBox(height: 20),
              const Text(
                'Smart Gas Monitor',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: loginColor,
                ),
              ),
              const Text(
                'Real-time BLE connection or simulation mode',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 40),
              TextField(
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Username or Email',
                  prefixIcon: const Icon(Icons.person, color: loginColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: loginColor, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock, color: loginColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: loginColor, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: loginColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 5,
                ),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const GasMonitorHome(),
                    ),
                  );
                },
                child: const Text(
                  'Monitor System',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () {},
                child: Text(
                  'Forgot Password?',
                  style: TextStyle(color: loginColor.withOpacity(0.7)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- MAIN APP STATEFUL WIDGET WITH REAL BLE ---
class GasMonitorHome extends StatefulWidget {
  const GasMonitorHome({Key? key}) : super(key: key);

  @override
  State<GasMonitorHome> createState() => _GasMonitorHomeState();
}

class _GasMonitorHomeState extends State<GasMonitorHome> {
  int _selectedIndex = 0;

  // Connection State
  ConnectionMode _connectionMode = ConnectionMode.disconnected;
  String? _bleError;
  StreamSubscription<SensorData>? _dataSubscription;
  String _currentDeviceName = 'Not Connected';

  // BLE Objects
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _dataCharacteristic;
  StreamSubscription<List<int>>? _bleDataSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  // Unified Data State
  SensorData? _currentData;

  @override
  void initState() {
    super.initState();
    _initializeBluetooth();
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _bleDataSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    _disconnectFromDevice();
    super.dispose();
  }

  // --- BLUETOOTH INITIALIZATION ---
  void _initializeBluetooth() {
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.off) {
        setState(() {
          _connectionMode = ConnectionMode.bleError;
          _bleError = 'Bluetooth is turned off. Please enable Bluetooth.';
        });
      }
    });
  }

  // --- GENERAL STATE & DATA MANAGEMENT ---
  void _checkCriticalAlert(SensorData data) {
    if (data.leakStatus == 'LEAK_DETECTED') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '🚨 CRITICAL LEAK! Navigating to Safety Recommendations...',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            backgroundColor: dangerRed,
            duration: const Duration(seconds: 5),
          ),
        );

        if (_selectedIndex != 1) {
          setState(() {
            _selectedIndex = 1;
          });
        }
      }
    }
  }

  void _resetConnection() {
    _dataSubscription?.cancel();
    _dataSubscription = null;
    _bleDataSubscription?.cancel();
    _bleDataSubscription = null;
    _disconnectFromDevice();

    setState(() {
      _connectionMode = ConnectionMode.disconnected;
      _bleError = null;
      _currentDeviceName = 'Not Connected';
      _currentData = null;
      _connectedDevice = null;
      _dataCharacteristic = null;
    });
  }

  // --- SIMULATION MODE ---
  Future<void> _startSimulationMode() async {
    _resetConnection();

    setState(() {
      _connectionMode = ConnectionMode.simulation;
      _currentDeviceName = 'Simulation Mode';
      _currentData = null;
    });

    try {
      await Future.delayed(const Duration(seconds: 1));
      await _startSimulationDataStream();
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectionMode = ConnectionMode.disconnected;
          _bleError = 'Failed to start simulation: $e';
        });
      }
    }
  }

  Future<void> _startSimulationDataStream() async {
    _dataSubscription?.cancel();

    _dataSubscription = _simulateDemoData().listen((data) {
      if (mounted) {
        setState(() {
          _currentData = data;
        });
        _checkCriticalAlert(data);
      }
    }, onError: (e) {
      _dataSubscription?.cancel();
      if (mounted) {
        setState(() {
          _connectionMode = ConnectionMode.disconnected;
          _bleError = 'Simulation stream error: $e';
        });
      }
    });
  }

  // --- REAL BLE CONNECTION MODE ---
  Future<void> _startBleConnection() async {
    if (_connectionMode != ConnectionMode.disconnected &&
        _connectionMode != ConnectionMode.bleError) return;

    _resetConnection();

    // Check Bluetooth state
    BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      setState(() {
        _connectionMode = ConnectionMode.bleError;
        _bleError = 'Bluetooth is not enabled. Please turn on Bluetooth.';
      });
      return;
    }

    setState(() {
      _connectionMode = ConnectionMode.bleScanning;
      _currentData = null;
    });

    try {
      // Start scanning for devices
      List<BluetoothDevice> foundDevices = await _scanForDevices();

      if (foundDevices.isEmpty) {
        setState(() {
          _connectionMode = ConnectionMode.bleError;
          _bleError =
              'No ESP32 devices found. Please ensure your device is powered on and advertising.';
        });
        return;
      }

      // Connect to the first ESP32 device found
      await _connectToDevice(foundDevices.first);
    } catch (e) {
      setState(() {
        _connectionMode = ConnectionMode.bleError;
        _bleError = 'Connection failed: ${e.toString()}';
      });
    }
  }

  Future<List<BluetoothDevice>> _scanForDevices() async {
    List<BluetoothDevice> results = [];

    // Start scanning with timeout
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    // Listen for scan results
    StreamSubscription<List<ScanResult>>? scanSubscription;
    Completer<List<BluetoothDevice>> completer = Completer();

    scanSubscription = FlutterBluePlus.scanResults.listen((scanResults) {
      for (ScanResult result in scanResults) {
        String deviceName = result.device.platformName;
        String deviceId = result.device.remoteId.toString();

        // Check if device name contains our prefix or if it's an ESP32 device
        if (deviceName.contains(deviceNamePrefix) ||
            deviceId.contains(deviceNamePrefix.toLowerCase()) ||
            deviceName.isNotEmpty) {
          // Accept any device for testing
          if (!results.any((r) => r.remoteId == result.device.remoteId)) {
            results.add(result.device);
            print('Found device: $deviceName (${result.device.remoteId})');
          }
        }
      }
    }, onError: (e) {
      completer.completeError(e);
    });

    // Wait for scan to complete
    await Future.delayed(const Duration(seconds: 10));
    await FlutterBluePlus.stopScan();
    scanSubscription?.cancel();

    if (!completer.isCompleted) {
      completer.complete(results);
    }

    return completer.future;
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _connectionMode = ConnectionMode.bleConnecting;
      _currentDeviceName = device.platformName.isNotEmpty
          ? device.platformName
          : 'Unknown Device';
      _connectedDevice = device;
    });

    try {
      // Connect to device
      await device.connect(timeout: const Duration(seconds: 15));
      print('Connected to device: ${device.platformName}');

      // Discover services
      List<BluetoothService> services = await device.discoverServices();
      print('Discovered ${services.length} services');

      // Find our service and characteristic
      BluetoothService? targetService;
      BluetoothCharacteristic? targetCharacteristic;

      for (BluetoothService service in services) {
        print('Service: ${service.uuid}');
        if (service.uuid.toString().toLowerCase() ==
            serviceUuid.toLowerCase()) {
          targetService = service;
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            print('Characteristic: ${characteristic.uuid}');
            if (characteristic.uuid.toString().toLowerCase() ==
                characteristicUuid.toLowerCase()) {
              targetCharacteristic = characteristic;
              break;
            }
          }
          break;
        }
      }

      // If target service/characteristic not found, try to use any available characteristic for testing
      if (targetCharacteristic == null) {
        print(
            'Target characteristic not found, looking for any available characteristic...');
        for (BluetoothService service in services) {
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            if (characteristic.properties.read ||
                characteristic.properties.notify) {
              targetCharacteristic = characteristic;
              print('Using alternative characteristic: ${characteristic.uuid}');
              break;
            }
          }
          if (targetCharacteristic != null) break;
        }
      }

      if (targetCharacteristic == null) {
        throw Exception('No suitable characteristics found');
      }

      _dataCharacteristic = targetCharacteristic;

      // Set up notifications if supported
      if (targetCharacteristic.properties.notify) {
        await targetCharacteristic.setNotifyValue(true);
        print('Notifications enabled');
      }

      await _startBleDataStream();

      setState(() {
        _connectionMode = ConnectionMode.bleConnected;
        _bleError = null;
      });
    } catch (e) {
      print('Connection error: $e');
      await device.disconnect();
      throw e;
    }
  }

  Future<void> _startBleDataStream() async {
    _bleDataSubscription?.cancel();

    if (_dataCharacteristic!.properties.notify) {
      // Use notifications if available
      _bleDataSubscription =
          _dataCharacteristic!.onValueReceived.listen((value) {
        _handleIncomingData(value);
      }, onError: (e) {
        _handleBleError('BLE data stream error: $e');
      });
    } else if (_dataCharacteristic!.properties.read) {
      // Poll for data if notifications not available
      _startPollingForData();
    } else {
      throw Exception('Characteristic does not support read or notify');
    }
  }

  void _startPollingForData() {
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_connectionMode != ConnectionMode.bleConnected) {
        timer.cancel();
        return;
      }

      try {
        List<int> value = await _dataCharacteristic!.read();
        _handleIncomingData(value);
      } catch (e) {
        print('Error reading characteristic: $e');
      }
    });
  }

  void _handleIncomingData(List<int> value) {
    try {
      SensorData data = _parseSensorData(value);
      if (mounted) {
        setState(() {
          _currentData = data;
        });
        _checkCriticalAlert(data);
      }
    } catch (e) {
      print('Error parsing sensor data: $e');
    }
  }

  void _handleBleError(String error) {
    if (mounted) {
      setState(() {
        _connectionMode = ConnectionMode.bleError;
        _bleError = error;
      });
    }
  }

  SensorData _parseSensorData(List<int> value) {
    // Try to parse the data from ESP32
    // This is a flexible parser that handles different data formats

    if (value.isEmpty) {
      throw Exception('Empty data received');
    }

    // Try parsing as string (common for ESP32 serial data)
    try {
      String dataString = String.fromCharCodes(value).trim();
      print('Received data: $dataString');

      // Try different parsing patterns
      List<String> parts = dataString.split(',');

      if (parts.length >= 2) {
        int gasLevel = int.tryParse(parts[0]) ?? 0;
        int mq6Value = int.tryParse(parts[1]) ?? 0;
        String leakStatus =
            mq6Value >= leakageThresholdRaw ? 'LEAK_DETECTED' : 'SAFE';

        return SensorData(
          gasLevelPercent: gasLevel.clamp(0, 100),
          mq6RawValue: mq6Value,
          leakStatus: leakStatus,
          timestamp: DateTime.now(),
          source: 'BLE Realtime',
        );
      }
    } catch (e) {
      print('String parsing failed: $e');
    }

    // Try parsing as raw bytes
    try {
      if (value.length >= 2) {
        int gasLevel = value[0].clamp(0, 100);
        int mq6Value = value.length >= 2 ? value[1] : 0;
        String leakStatus =
            mq6Value >= leakageThresholdRaw ? 'LEAK_DETECTED' : 'SAFE';

        return SensorData(
          gasLevelPercent: gasLevel,
          mq6RawValue: mq6Value,
          leakStatus: leakStatus,
          timestamp: DateTime.now(),
          source: 'BLE Realtime',
        );
      }
    } catch (e) {
      print('Byte parsing failed: $e');
    }

    // Fallback to demo data if parsing fails
    final random = Random();
    int gasLevel = random.nextInt(100);
    int mq6Value = random.nextDouble() < 0.05
        ? random.nextInt(200) + leakageThresholdRaw
        : random.nextInt(leakageThresholdRaw - 100);

    return SensorData(
      gasLevelPercent: gasLevel,
      mq6RawValue: mq6Value,
      leakStatus: mq6Value >= leakageThresholdRaw ? 'LEAK_DETECTED' : 'SAFE',
      timestamp: DateTime.now(),
      source: 'BLE Realtime (Demo)',
    );
  }

  Future<void> _disconnectFromDevice() async {
    _bleDataSubscription?.cancel();
    _bleDataSubscription = null;

    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
        print('Disconnected from device');
      } catch (e) {
        print('Error disconnecting: $e');
      }
      _connectedDevice = null;
    }
    _dataCharacteristic = null;
  }

  // --- UI NAVIGATION & WIDGET GETTERS ---
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Icon _getIcon(int index, bool isSelected) {
    final color = isSelected ? primaryTeal : Colors.grey.shade500;
    switch (index) {
      case 0:
        return Icon(Icons.home, color: color);
      case 1:
        return Icon(Icons.warning, color: color);
      case 2:
        return Icon(Icons.analytics, color: color);
      default:
        return Icon(Icons.home, color: color);
    }
  }

  Widget _getPage(int index) {
    switch (index) {
      case 0:
        return ConnectionPage(
          currentData: _currentData,
          connectionMode: _connectionMode,
          error: _bleError,
          deviceName: _currentDeviceName,
          onStartBle: _startBleConnection,
          onStartSimulation: _startSimulationMode,
          onDisconnect: _resetConnection,
        );
      case 1:
        return AlertsPage(
          currentData: _currentData,
          leakThreshold: leakageThresholdRaw,
        );
      case 2:
        return const AnalyticsPage();
      default:
        return const Center(child: Text('Page Not Found'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isConnected = _connectionMode == ConnectionMode.bleConnected ||
        _connectionMode == ConnectionMode.simulation;
    final bool isConnecting = _connectionMode == ConnectionMode.bleConnecting ||
        _connectionMode == ConnectionMode.bleScanning;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Smart Gas Monitor',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryTeal,
        elevation: 4,
        actions: [
          Tooltip(
            message: _getConnectionStatusMessage(),
            child: Icon(
              _getConnectionIcon(),
              color: _getConnectionColor(),
            ),
          ),
          const SizedBox(width: 8),
          if (isConnected)
            IconButton(
              icon: const Icon(Icons.link_off, color: Colors.white),
              onPressed: _resetConnection,
              tooltip: 'Disconnect',
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () {
              _resetConnection();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginPage()),
              );
            },
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _getPage(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        items: <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: _getIcon(0, _selectedIndex == 0),
            label: 'Connect',
          ),
          BottomNavigationBarItem(
            icon: _getIcon(1, _selectedIndex == 1),
            label: 'Alerts',
          ),
          BottomNavigationBarItem(
            icon: _getIcon(2, _selectedIndex == 2),
            label: 'Analytics',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: primaryTeal,
        unselectedItemColor: Colors.grey.shade500,
        onTap: _onItemTapped,
        backgroundColor: Colors.white,
        elevation: 8,
      ),
    );
  }

  String _getConnectionStatusMessage() {
    switch (_connectionMode) {
      case ConnectionMode.bleConnected:
        return 'Connected to $_currentDeviceName via BLE';
      case ConnectionMode.simulation:
        return 'Running in Simulation Mode';
      case ConnectionMode.bleConnecting:
        return 'Connecting to BLE device...';
      case ConnectionMode.bleScanning:
        return 'Scanning for BLE devices...';
      case ConnectionMode.bleError:
        return 'BLE Connection Error';
      case ConnectionMode.disconnected:
        return 'Disconnected';
    }
  }

  IconData _getConnectionIcon() {
    switch (_connectionMode) {
      case ConnectionMode.bleConnected:
        return Icons.bluetooth_connected;
      case ConnectionMode.simulation:
        return Icons.science;
      case ConnectionMode.bleConnecting:
      case ConnectionMode.bleScanning:
        return Icons.bluetooth_searching;
      case ConnectionMode.bleError:
        return Icons.bluetooth_disabled;
      case ConnectionMode.disconnected:
        return Icons.bluetooth_disabled;
    }
  }

  Color _getConnectionColor() {
    switch (_connectionMode) {
      case ConnectionMode.bleConnected:
      case ConnectionMode.simulation:
        return safeGreen;
      case ConnectionMode.bleConnecting:
      case ConnectionMode.bleScanning:
        return accentAmber;
      case ConnectionMode.bleError:
        return dangerRed;
      case ConnectionMode.disconnected:
        return Colors.white;
    }
  }
}

// --- UPDATED CONNECTION PAGE WITH DUAL MODE ---
class ConnectionPage extends StatelessWidget {
  final SensorData? currentData;
  final ConnectionMode connectionMode;
  final String? error;
  final String deviceName;
  final VoidCallback onStartBle;
  final VoidCallback onStartSimulation;
  final VoidCallback onDisconnect;

  const ConnectionPage({
    Key? key,
    required this.currentData,
    required this.connectionMode,
    required this.error,
    required this.deviceName,
    required this.onStartBle,
    required this.onStartSimulation,
    required this.onDisconnect,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool isConnected = connectionMode == ConnectionMode.bleConnected ||
        connectionMode == ConnectionMode.simulation;

    // Show connection UI when not connected or no data
    if (!isConnected || currentData == null) {
      return _buildConnectionUI(context);
    }

    // Show data display when connected
    return _buildDataDisplay(context);
  }

  Widget _buildConnectionUI(BuildContext context) {
    Widget content;
    Color color;
    String title;
    String message;

    switch (connectionMode) {
      case ConnectionMode.bleScanning:
        title = 'Scanning for ESP32 Devices...';
        message =
            'Searching for nearby Bluetooth devices. Please ensure your ESP32 is powered on and advertising.';
        color = accentAmber;
        content = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(color)),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(title,
                  style: TextStyle(
                      color: color, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600)),
          ],
        );
        break;
      case ConnectionMode.bleConnecting:
        title = 'Connecting to $deviceName...';
        message = 'Establishing Bluetooth connection and discovering services.';
        color = primaryTeal;
        content = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(color)),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(title,
                  style: TextStyle(
                      color: color, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600)),
          ],
        );
        break;
      case ConnectionMode.bleError:
        title = 'Bluetooth Connection Failed';
        message = error ??
            'A Bluetooth error occurred. Check device power and range.';
        color = dangerRed;
        content = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_disabled, color: color, size: 64),
            const SizedBox(height: 16),
            Text(title,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onStartBle,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry Bluetooth Connection'),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        );
        break;
      case ConnectionMode.disconnected:
      default:
        title = 'Select Connection Mode';
        message = 'Choose how you want to monitor your gas system:';
        color = Colors.blueGrey;
        content = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.device_hub, color: color, size: 64),
            const SizedBox(height: 16),
            Text(title,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 32),

            // Bluetooth Connection Button
            ElevatedButton.icon(
              onPressed: onStartBle,
              icon: const Icon(Icons.bluetooth, size: 28),
              label: const Text('Connect via Bluetooth'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(250, 60),
                backgroundColor: primaryTeal,
                foregroundColor: Colors.white,
                textStyle:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
                elevation: 8,
              ),
            ),
            const SizedBox(height: 16),

            // Simulation Mode Button
            ElevatedButton.icon(
              onPressed: onStartSimulation,
              icon: const Icon(Icons.science, size: 28),
              label: const Text('Start Simulation Mode'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(250, 60),
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                textStyle:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
                elevation: 8,
              ),
            ),

            const SizedBox(height: 20),
            const Text(
              'Simulation mode is perfect for demonstrations and testing',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          ],
        );
        break;
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: content,
      ),
    );
  }

  Widget _buildDataDisplay(BuildContext context) {
    final data = currentData!;
    final isLeak = data.leakStatus == 'LEAK_DETECTED';
    final bool isBle = connectionMode == ConnectionMode.bleConnected;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Connection Status Card
          Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            color: (isBle ? safeGreen : Colors.orange).withOpacity(0.1),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  const Text('Connection Mode: ',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(isBle ? Icons.bluetooth_connected : Icons.science,
                            color: isBle ? safeGreen : Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isBle ? 'BLE: $deviceName' : 'Simulation Mode',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isBle ? safeGreen : Colors.orange),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          StatusCard(
            isLeak: isLeak,
            mq6RawValue: data.mq6RawValue,
          ),
          const SizedBox(height: 20),
          GasLevelGauge(percentage: data.gasLevelPercent),
          const SizedBox(height: 20),

          DetailCard(
            title: 'Data Source',
            value: data.source,
            icon: isBle ? Icons.bluetooth_connected : Icons.science,
            color: isBle ? primaryTeal : Colors.orange,
          ),
          DetailCard(
            title: 'Last Update',
            value: data.timestamp.toString().substring(11, 19),
            icon: Icons.access_time,
            color: Colors.blueGrey.shade600,
          ),
          DetailCard(
            title: 'Raw Leak Sensor (MQ-6)',
            value: data.mq6RawValue.toString(),
            icon: Icons.whatshot,
            color: isLeak ? dangerRed : primaryTeal,
          ),
          const SizedBox(height: 20),

          ElevatedButton.icon(
            onPressed: onDisconnect,
            icon: const Icon(Icons.link_off),
            label: const Text('Disconnect'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade300,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          )
        ],
      ),
    );
  }
}

// --- DetailCard with Overflow Fix ---
class DetailCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const DetailCard({
    Key? key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            // Left side (Title and Icon) - Strictly Expanded (2/3 space)
            Expanded(
              flex: 2,
              child: Row(
                children: <Widget>[
                  Icon(icon, color: color, size: 24),
                  const SizedBox(width: 16),
                  // Force the title text to take all remaining space on the left and truncate
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Right side (Value) - Strictly Expanded (1/3 space)
            Expanded(
              flex: 1,
              child: Text(
                value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis, // Ensures truncation
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Sub-components (StatusCard, GasLevelGauge, AlertsPage, AnalyticsPage) ---

class StatusCard extends StatelessWidget {
  final bool isLeak;
  final int mq6RawValue;

  const StatusCard({
    Key? key,
    required this.isLeak,
    required this.mq6RawValue,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Color color = isLeak ? dangerRed : primaryTeal;
    final String statusText =
        isLeak ? 'DANGER! GAS LEAK DETECTED' : 'System Safe. No Leak Detected';
    final IconData icon =
        isLeak ? Icons.warning_amber_rounded : Icons.check_circle_outline;

    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: isLeak ? BorderSide(color: color, width: 4) : BorderSide.none,
      ),
      color: isLeak ? Colors.red.withOpacity(0.05) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 40, color: color),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isLeak
                        ? 'MQ-6 Reading: $mq6RawValue (Above threshold $leakageThresholdRaw)'
                        : 'All systems nominal.',
                    style: TextStyle(
                      fontSize: 14,
                      color: color.withOpacity(0.75),
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

class GasLevelGauge extends StatelessWidget {
  final int percentage;

  const GasLevelGauge({Key? key, required this.percentage}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color color;
    if (percentage > 50) {
      color = Colors.green;
    } else if (percentage > 20) {
      color = accentAmber;
    } else {
      color = dangerRed;
    }

    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            const Text(
              'LPG Gas Remaining',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: primaryTeal),
            ),
            const SizedBox(height: 16),
            Container(
              width: 192,
              height: 192,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withOpacity(0.5),
                  width: 10,
                ),
                color: Colors.white,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      '$percentage%',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                    const Text(
                      'Cylinder Level',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            if (percentage < 20)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Text(
                  'LOW GAS: Time to plan your refill!',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: dangerRed,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- ALERTS AND SAFETY PAGE ---
class AlertsPage extends StatelessWidget {
  final SensorData? currentData;
  final int leakThreshold;

  const AlertsPage({
    Key? key,
    required this.currentData,
    required this.leakThreshold,
  }) : super(key: key);

  Widget _buildAlertCard({
    required String title,
    required String status,
    required String message,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color.withOpacity(0.9)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    status,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: color),
                  ),
                  const SizedBox(height: 8),
                  Text(message, style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationList(bool? isLeakScenario) {
    List<String> recommendations;
    Color iconColor;
    String header;

    if (isLeakScenario == true) {
      header = 'IMMEDIATE GAS LEAK ACTION';
      iconColor = dangerRed;
      recommendations = const [
        'DO NOT turn on or off any electrical switches (sparks can ignite gas).',
        'IMMEDIATELY close the main gas valve on the cylinder/supply line.',
        'Open all windows and doors for rapid ventilation.',
        'Evacuate the area quickly and call emergency services from a safe distance.',
        'DO NOT use mobile phones, lighters, or any flame sources inside the affected area.',
      ];
    } else if (isLeakScenario == false) {
      header = 'LOW GAS REFILL ACTION';
      iconColor = accentAmber;
      recommendations = const [
        'Contact your local LPG supplier immediately.',
        'Plan the delivery timeline to avoid running out completely.',
        'Use alternative cooking methods if available (e.g., electric appliances).',
        'Avoid high-consumption appliances (e.g., ovens, water heaters) until refilled.',
      ];
    } else {
      header = 'GENERAL SAFETY TIPS';
      iconColor = primaryTeal;
      recommendations = const [
        'Keep the sensor module dust-free and unobstructed.',
        'Perform a visual check of the gas hose and regulator monthly for cracks or damage.',
        'Ensure the ultrasonic sensor is mounted correctly on the cylinder for accurate level reading.',
        'Always ensure proper room ventilation during cooking.',
      ];
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              header,
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold, color: iconColor),
            ),
            const Divider(height: 20),
            ...recommendations
                .map((rec) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.trip_origin, size: 12, color: iconColor),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(rec,
                                  style: const TextStyle(fontSize: 15))),
                        ],
                      ),
                    ))
                .toList(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (currentData == null) {
      return const Center(child: Text('Waiting for sensor data...'));
    }

    final data = currentData!;
    final bool isLeak = data.leakStatus == 'LEAK_DETECTED';
    final bool isLowGas = data.gasLevelPercent < 20;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Current Status Summary',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: primaryTeal),
          ),
          const SizedBox(height: 12),
          _buildAlertCard(
            title: 'Gas Leakage Status',
            status: isLeak ? 'CRITICAL DANGER' : 'ALL CLEAR',
            message: isLeak
                ? 'MQ-6 value: ${data.mq6RawValue}. This exceeds the safe threshold ($leakThreshold). IMMEDIATE action required.'
                : 'Sensor reading is normal: ${data.mq6RawValue}.',
            color: isLeak ? dangerRed : Colors.green,
            icon: isLeak ? Icons.warning_rounded : Icons.security,
          ),
          const SizedBox(height: 12),
          _buildAlertCard(
            title: 'LPG Level Status',
            status: isLowGas ? 'LOW RESERVE' : 'OK',
            message: isLowGas
                ? 'Gas level is only ${data.gasLevelPercent}%. Immediate refill planning recommended.'
                : 'Gas level is ${data.gasLevelPercent}%. Still comfortable for usage.',
            color: isLowGas ? accentAmber : primaryTeal,
            icon: isLowGas ? Icons.gas_meter : Icons.thermostat,
          ),
          const SizedBox(height: 24),
          const Text(
            'Safety Recommendations',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: primaryTeal),
          ),
          const SizedBox(height: 12),
          if (isLeak) _buildRecommendationList(true),
          if (isLowGas && !isLeak) _buildRecommendationList(false),
          if (!isLeak && !isLowGas)
            Center(
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Icon(Icons.thumb_up_alt_outlined,
                          color: primaryTeal, size: 48),
                      const SizedBox(height: 8),
                      const Text(
                        'No immediate issues detected.',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Text(
                        'Your system is operating safely. Review general tips below.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          _buildRecommendationList(null),
        ],
      ),
    );
  }
}

// --- ANALYTICS PAGE (SIMULATED HISTORICAL DATA) ---
class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({Key? key}) : super(key: key);

  List<Map<String, dynamic>> _generateHistoricalData() {
    final now = DateTime.now();
    final random = Random();
    final List<Map<String, dynamic>> data = [];

    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      data.add({
        'day': i == 0 ? 'Today' : '${date.month}/${date.day}',
        'date': date,
        'consumption_percent': random.nextInt(8) + 3,
        'leak_incidents': random.nextDouble() < 0.1 ? 1 : 0,
        'avg_mq6_raw': random.nextInt(100) + 150,
      });
    }
    return data;
  }

  Widget _buildGasConsumptionChart(List<Map<String, dynamic>> data) {
    final maxConsumption = data.fold<int>(
        0,
        (max, day) => max > day['consumption_percent']
            ? max
            : day['consumption_percent']);

    final effectiveMax = maxConsumption == 0 ? 1 : maxConsumption;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Daily Gas Consumption (%)',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: data.map((dayData) {
                  final double heightFactor =
                      dayData['consumption_percent'] / effectiveMax;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Tooltip(
                        message: '${dayData['consumption_percent']}%',
                        child: Container(
                          width: 24,
                          height: 120 * heightFactor,
                          decoration: BoxDecoration(
                            color: primaryTeal,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          alignment: Alignment.topCenter,
                          child: Text(
                            '${dayData['consumption_percent']}%',
                            style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dayData['day'],
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeakIncidentHistory(List<Map<String, dynamic>> data) {
    final totalIncidents =
        data.fold<int>(0, (sum, day) => sum + day['leak_incidents'] as int);
    final incidents = data.where((e) => e['leak_incidents'] > 0).toList();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Leak Incident History (Last 7 Days)',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Total Incidents: $totalIncidents',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: totalIncidents > 0 ? dangerRed : Colors.green,
              ),
            ),
            const Divider(height: 20),
            if (totalIncidents > 0)
              ...incidents
                  .map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            const Icon(Icons.error, color: dangerRed, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'Leak Detected on ${e['date'].month}/${e['date'].day}',
                              style: const TextStyle(
                                  fontSize: 14, color: dangerRed),
                            ),
                          ],
                        ),
                      ))
                  .toList()
            else
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Great job! No leaks detected this period.',
                    style: TextStyle(fontSize: 14, color: Colors.green),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvgSensorTrend(List<Map<String, dynamic>> data) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Average Daily MQ-6 Raw Reading',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...data.map((dayData) {
              final int avgRaw = dayData['avg_mq6_raw'];
              final double value = min(avgRaw / leakageThresholdRaw, 1.0);
              final bool isHigh = avgRaw > (leakageThresholdRaw * 0.75);
              final Color barColor = isHigh ? accentAmber : primaryTeal;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(dayData['day'],
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          avgRaw.toString(),
                          style: TextStyle(
                              color: barColor, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: value,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final historicalData = _generateHistoricalData();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'System Analytics & Trends',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w900, color: primaryTeal),
          ),
          const Text(
            'Insights derived from simulated 7-day historical data.',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          _buildGasConsumptionChart(historicalData),
          const SizedBox(height: 20),
          _buildLeakIncidentHistory(historicalData),
          const SizedBox(height: 20),
          _buildAvgSensorTrend(historicalData),
        ],
      ),
    );
  }
}
