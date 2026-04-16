import 'dart:async';
import 'package:flutter/material.dart';
import '../services/offline_routing_service.dart';

class TestRoutingButton extends StatefulWidget {
  final bool iconOnly;
  const TestRoutingButton({super.key, this.iconOnly = false});

  @override
  State<TestRoutingButton> createState() => _TestRoutingButtonState();
}

class _TestRoutingButtonState extends State<TestRoutingButton> {
  bool _isLoading = false;
  bool _isReady = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    // Poll for status until it's ready
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkStatus());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    final ready = await OfflineRoutingService().isReady();
    if (mounted && ready != _isReady) {
      setState(() => _isReady = ready);
      if (ready) _pollTimer?.cancel();
    }
  }

  Future<void> _testRoute() async {
    if (!_isReady) return;
    setState(() => _isLoading = true);

    // Coordinates provided for the test (Ahmedabad)
    const startLat = 23.0225;
    const startLng = 72.5714;
    const endLat = 23.0300;
    const endLng = 72.5800;

    final service = OfflineRoutingService();
    
    // Call the method channel through our service
    final result = await service.getRoute(
      startLat: startLat,
      startLng: startLng,
      endLat: endLat,
      endLng: endLng,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result != null) {
      final distInKm = (result['distance'] as double) / 1000.0;
      final timeInMins = (result['time'] as int) / 60000.0;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Success! 🚗 \nDistance: ${distInKm.toStringAsFixed(2)} km\nTime: ${timeInMins.toStringAsFixed(1)} mins'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to get route! Either not ready or points invalid.'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.iconOnly) {
      return Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: IconButton(
          onPressed: (_isLoading || !_isReady) ? null : _testRoute,
          icon: _isLoading 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.blueAccent, strokeWidth: 2))
              : Icon(
                  Icons.directions_car, 
                  color: _isReady ? Colors.blueAccent : Colors.white24
                ),
          tooltip: _isReady ? 'Test Offline Route' : 'Engine Loading...',
        ),
      );
    }

    return FloatingActionButton.extended(
      onPressed: (_isLoading || !_isReady) ? null : _testRoute,
      icon: _isLoading 
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : Icon(Icons.directions_car, color: _isReady ? Colors.white : Colors.white38),
      label: Text(_isLoading 
          ? 'Calculating...' 
          : (_isReady ? 'Test Offline Route' : 'Engine Loading...')),
      backgroundColor: _isReady ? Colors.blueAccent : Colors.grey.shade800,
    );
  }
}
