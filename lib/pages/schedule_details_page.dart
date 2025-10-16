import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../models/schedule.dart';

class ScheduleDetailsPage extends StatefulWidget {
  final Schedule schedule;

  const ScheduleDetailsPage({super.key, required this.schedule});

  @override
  State<ScheduleDetailsPage> createState() => _ScheduleDetailsPageState();
}

class _ScheduleDetailsPageState extends State<ScheduleDetailsPage> {
  LatLng? _nurseLocation;
  StreamSubscription<Position>? _positionStream;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _getNurseLocation();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _getNurseLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Location services are disabled. Please enable them to show your location on the map.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Location permission denied. Please grant permission to show your location.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Location permission permanently denied. Please enable it in app settings.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Current position
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _nurseLocation = LatLng(pos.latitude, pos.longitude);
      });

      // Live updates
      _positionStream?.cancel();
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position position) {
        if (mounted) {
          setState(() {
            _nurseLocation = LatLng(position.latitude, position.longitude);
          });
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final patient = widget.schedule.patient;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule Details'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (patient?.latitude != null && patient?.longitude != null)
              SizedBox(
                height: 250,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter:
                        LatLng(patient!.latitude!, patient.longitude!),
                    initialZoom: 14,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                      subdomains: const ['a', 'b', 'c'],
                    ),
                    MarkerLayer(
                      markers: [
                        // Patient marker
                        Marker(
                          point: LatLng(patient.latitude!, patient.longitude!),
                          child: const Icon(Icons.location_pin,
                              color: Colors.red, size: 40),
                        ),
                        // Nurse marker
                        if (_nurseLocation != null)
                          Marker(
                            point: _nurseLocation!,
                            child: const Icon(Icons.person_pin_circle,
                                color: Colors.blue, size: 40),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("📋 Appointment Details",
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 8),
                            Text("Service: ${widget.schedule.serviceType}"),
                            Text("Status: ${widget.schedule.status}"),
                            Text(
                              "Date: ${DateFormat('MMM dd, yyyy').format(widget.schedule.scheduledDate)}",
                            ),
                            Text(
                              "Time: ${widget.schedule.scheduledStartTime} - ${widget.schedule.scheduledEndTime}",
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("👤 Patient Information",
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 8),
                            Text("Name: ${patient?.fullName ?? 'Unknown'}"),
                            Text(
                                "Address: ${patient?.address ?? 'Not available'}"),
                            Text("Phone: ${patient?.phone ?? 'Not provided'}"),
                            if (patient?.medicalNotes != null &&
                                patient!.medicalNotes!.isNotEmpty)
                              Text("Notes: ${patient.medicalNotes}"),
                          ],
                        ),
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
