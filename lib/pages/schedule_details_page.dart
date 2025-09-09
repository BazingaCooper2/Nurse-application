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

  Future<void> _getNurseLocation() async {
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    setState(() {
      _nurseLocation = LatLng(pos.latitude, pos.longitude);
    });
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
