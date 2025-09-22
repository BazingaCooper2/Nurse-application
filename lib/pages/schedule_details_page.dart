import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  GoogleMapController? _mapController;
  LatLng? _nurseLocation;

  @override
  void initState() {
    super.initState();
    _getNurseLocation();
  }

  StreamSubscription<Position>? _positionStream;

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _getNurseLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Location services are not enabled, show a message or prompt
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location services are disabled. Please enable them to show your location on the map.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Check and request permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission denied. Please grant permission to show your location.'),
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
              content: Text('Location permission permanently denied. Please enable it in app settings.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Get current position initially
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _nurseLocation = LatLng(pos.latitude, pos.longitude);
      });

      // Set up live location stream
      _positionStream?.cancel();
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Update every 10 meters
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
                // Google Map
                if (patient?.latitude != null && patient?.longitude != null)
                  SizedBox(
                    height: 250,
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(
                          patient!.latitude!,
                          patient.longitude!,
                        ),
                        zoom: 14,
                      ),
                      markers: {
                        Marker(
                          markerId: const MarkerId("patient"),
                          position: LatLng(patient.latitude!, patient.longitude!),
                          infoWindow: InfoWindow(title: patient.fullName),
                        ),
                        if (_nurseLocation != null)
                          Marker(
                            markerId: const MarkerId("nurse"),
                            position: _nurseLocation!,
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                                BitmapDescriptor.hueBlue),
                            infoWindow: const InfoWindow(title: "You (Nurse)"),
                          ),
                      },
                      onMapCreated: (controller) => _mapController = controller,
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
                                Text("Address: ${patient?.address ?? 'Not available'}"),
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
