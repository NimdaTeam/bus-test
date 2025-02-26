import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_compass/flutter_map_compass.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:nbt_app/baseConfigs/global_variables.dart';
import 'package:nbt_app/data/busLine.dart' as busLineData;
import 'package:nbt_app/gen/assets.gen.dart';
import 'package:nbt_app/gen/fonts.gen.dart';
import 'package:nbt_app/main.dart';
import 'package:nbt_app/utilities/connectivity_provider/connectivity_provider.dart';
import 'package:nbt_app/utilities/location_utilities/location_provider.dart';
import 'package:provider/provider.dart';
import 'package:signalr_netcore/signalr_client.dart';
// Import your parser code, where we have busLines, stationMarkers, etc.
import 'package:nbt_app/utilities/Parsers/geoJsonParser.dart'
    show
        stationMarkerNames,
        stationMarkers,
        loadMapStaticData,
        globalBusLineModels; // we need the model list

bool isActive = false;

class MainMapPage extends StatefulWidget {
  final int userId;
  final String userType; // 'bus' or 'person'

  const MainMapPage({
    super.key,
    required this.userId,
    required this.userType,
  });

  @override
  State<MainMapPage> createState() => MainMapPageState();
}

class MainMapPageState extends State<MainMapPage> {
  final MapController mapController = MapController();

  var currentZoom = 12;

  late HubConnection _hubConnection;
  Timer? _heartbeatTimer;

  // ------------------------------------------------------------------------
  // 1) Markers for OTHER buses (only shown if userType == 'person')
  // ------------------------------------------------------------------------
  final Map<int, Marker> _busMarkers = {};

  // 2) Markers for persons (shown to both bus & person)
  final Map<int, Marker> _personMarkers = {};

  // If a person clicks on a bus, highlight that bus line
  Polyline? _clickedBusLine;
  Color? _clickedBusLineColor;
  String? _clickedBusLineName;
  bool _showClickedBusLine = false;

// If a bus driver select a busline and start driving
  Polyline? _selectedBusLine;

  // If user is bus, store the chosen line ID here
  int? _selectedBusLineId;

  // Subscription for location
  StreamSubscription<LocationData>? _locationStreamSub;

  List<int> _onlineBusLines = [];

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  // ------------------------------------------------------------------------
  // Initialize App
  // ------------------------------------------------------------------------
  Future<void> _initializeApp() async {
    await loadMapStaticData(); // load stations + lines from your API
    await _initSignalR(); // set up real-time connection
    /*await _fetchOnlinePersons();
    await _fetchOnlineBusDrivers();*/
  }

  // ------------------------------------------------------------------------
  // Initialize SignalR
  // ------------------------------------------------------------------------
  Future<void> _initSignalR() async {
    _hubConnection = HubConnectionBuilder()
        .withUrl("http://10.0.2.2:5000/locationHub")
        .build();

    _hubConnection.on('close', (e) {
      debugPrint('SignalR closed: $e');
    });

    // Real-time location updates
    _hubConnection.on("ReceiveBusLocation", _onReceiveBusLocation);
    _hubConnection.on("ReceivePersonLocation", _onReceivePersonLocation);

    // Online/offline status changes
    _hubConnection.on("BusDriverStatusChanged", _onBusDriverStatusChanged);
    _hubConnection.on("PersonStatusChanged", _onPersonStatusChanged);

    try {
      await _hubConnection.start();
      debugPrint("SignalR connected.");

      // After connecting, fetch existing online users
      // If I'm a bus, I DO NOT fetch other bus drivers
      // If I'm a person, I fetch bus drivers
      /*if (widget.userType == 'person') {*/
      await _fetchOnlineBusDrivers();
      /*}*/
      // Always fetch persons (both bus & person see persons)
      await _fetchOnlinePersons();
    } catch (e) {
      debugPrint("Error connecting to SignalR: $e");
    }
  }

  // ------------------------------------------------------------------------
  // Fetch existing online bus drivers (only if userType == 'person')
  // ------------------------------------------------------------------------
  Future<void> _fetchOnlineBusDrivers() async {
    try {
      debugPrint('fetchingOnlineBusDrivers ${DateTime.now()}');
      // 'GetOnlineBusDrivers' should return a list of e.g.:
      // [ { "busId":1,"busLineId":101,"latitude":36.21,"longitude":57.64 }, ... ]
      final result =
          await _hubConnection.invoke("GetOnlineBusDrivers") as List<dynamic>?;
      if (result == null) return;

      setState(() {
        for (final item in result) {
          final mapItem = item as Map<String, dynamic>;
          final busId = mapItem["busId"] as int;
          final busLineId = mapItem["busLineId"] as int?;
          final lat = mapItem["latitude"] as double?;
          final lng = mapItem["longitude"] as double?;

          if (busLineId != null) {
            _onlineBusLines.add(busLineId);
          }

          final index =
              globalBusLineModels.indexWhere((m) => m.id == busLineId);
          if (index != -1) {
            final lineModel = globalBusLineModels[index];
            _clickedBusLineColor = lineModel.color;
            _clickedBusLineName = lineModel.name;

            if (lat != null && lng != null && widget.userType != 'person') {
              _busMarkers[busId] = Marker(
                width: 40,
                height: 40,
                point: LatLng(lat, lng),
                child: GestureDetector(
                  onTap: () {
                    if (busLineId != null) {
                      _showBusLineOnClick(busLineId);
                    }
                  },
                  child: Icon(
                    Icons.directions_bus,
                    color: _clickedBusLineColor,
                    size: 40,
                  ),
                ),
              );
            }
          }
        }
      });
    } catch (e) {
      debugPrint("Error fetching bus drivers: $e");
    }
  }

  // ------------------------------------------------------------------------
  // Fetch existing online persons (shown to both bus & person)
  // ------------------------------------------------------------------------
  Future<void> _fetchOnlinePersons() async {
    try {
      debugPrint('fetchingOnlinepersons ${DateTime.now()}');
      // 'GetOnlinePersons' returns e.g.:
      // [ { "personId":10, "latitude":36.22, "longitude":57.64 }, ... ]
      final result =
          await _hubConnection.invoke("GetOnlinePersons") as List<dynamic>?;
      if (result == null) return;

      setState(() {
        for (final item in result) {
          final mapItem = item as Map<String, dynamic>;
          final personId = mapItem["personId"] as int;
          final lat = mapItem["latitude"] as double?;
          final lng = mapItem["longitude"] as double?;

          if (lat != null && lng != null && personId.toString() != userId) {
            _personMarkers[personId] = Marker(
              width: 40,
              height: 40,
              point: LatLng(lat, lng),
              child: Assets.img.icons.streetViewIcon.svg(width: 30, height: 30),
            );
          }
        }
      });
    } catch (e) {
      debugPrint("Error fetching persons: $e");
    }
  }

  // ------------------------------------------------------------------------
  // SignalR Handlers
  // ------------------------------------------------------------------------
  // Only show other buses if I'm a person
  void _onReceiveBusLocation(List<dynamic>? parameters) {
    if (parameters == null || parameters.length < 4) return;
    final busId = parameters[0] as int;
    final busLineId = parameters[1] as int;
    final lat = parameters[2] as double;
    final lng = parameters[3] as double;

    // If it's OUR bus location, ignore
    if (busId == widget.userId) return;

    // If I'm a bus, skip other bus drivers
    if (widget.userType == 'bus') return;

    final index = globalBusLineModels.indexWhere((m) => m.id == busLineId);

    // I'm a person => show this bus
    setState(() {
      if (index != -1) {
        final lineModel = globalBusLineModels[index];
        _clickedBusLineColor = lineModel.color;
        _clickedBusLineName = lineModel.name;

        _busMarkers[busId] = Marker(
          width: 40,
          height: 40,
          point: LatLng(lat, lng),
          child: GestureDetector(
            onTap: () {
              _showBusLineOnClick(busLineId);
            },
            child: Icon(
              Icons.directions_bus,
              color: _clickedBusLineColor,
              size: 40,
            ),
          ),
        );
      }
    });
  }

  // Persons are shown to both bus & person
  void _onReceivePersonLocation(List<dynamic>? parameters) {
    if (parameters == null || parameters.length < 3) return;
    final personId = parameters[0] as int;
    final lat = parameters[1] as double;
    final lng = parameters[2] as double;

    // If it's our own person ID, ignore
    if (widget.userType == 'person' && personId == widget.userId) return;

    // Show person for everyone
    setState(() {
      _personMarkers[personId] = Marker(
        width: 40,
        height: 40,
        point: LatLng(lat, lng),
        child: Assets.img.icons.streetViewIcon.svg(width: 30, height: 30),
      );
    });
  }

  // If I'm a person => remove or add bus. If I'm a bus => skip
  void _onBusDriverStatusChanged(List<dynamic>? parameters) {
    if (parameters == null || parameters.length < 3) return;
    final busId = parameters[0] as int;
    final busLineId = parameters[1] as int;
    final isOnline = parameters[2] as bool;

    if (busId == widget.userId) {
      // Our own status => ignore
      return;
    }
    debugPrint("Bus $busId is now online? $isOnline (line $busLineId)");

    // If I'm a bus, do nothing about other bus drivers
    /*if (widget.userType == 'bus') return;*/

    // If I'm a person, remove or keep the bus
    if (!isOnline) {
      setState(() {
        _busMarkers.remove(busId);
        _clickedBusLine = null;
        _clickedBusLineColor = null;
        _clickedBusLineName = null;
        _showClickedBusLine = false;

        _onlineBusLines.remove(busLineId);
      });
    }
    // else we rely on _onReceiveBusLocation to place it
  }

  // Persons are shown to both bus & person
  void _onPersonStatusChanged(List<dynamic>? parameters) {
    if (parameters == null || parameters.length < 2) return;
    final personId = parameters[0] as int;
    final isOnline = parameters[1] as bool;

    // If it's our own person ID, ignore
    if (widget.userType == 'person' && personId == widget.userId) return;

    debugPrint("Person $personId is now online? $isOnline");

    if (!isOnline) {
      setState(() {
        _personMarkers.remove(personId);
      });
    }
  }

  // ------------------------------------------------------------------------
  // Person clicks on bus => highlight bus line
  // ------------------------------------------------------------------------
  void _showBusLineOnClick(int busLineId) {
    if (widget.userType != 'person') return; // only persons can do this
    setState(() {
      _clickedBusLine = null;
      final index = globalBusLineModels.indexWhere((m) => m.id == busLineId);
      if (index != -1) {
        final lineModel = globalBusLineModels[index];
        _clickedBusLineColor = lineModel.color;
        _clickedBusLineName = lineModel.name;
        _showClickedBusLine = true;
        _clickedBusLine = Polyline(
          points: lineModel.points,
          color: lineModel.color,
          strokeWidth: 5.0,
        );
      }
    });
  }

  // ------------------------------------------------------------------------
  // Heartbeat
  // ------------------------------------------------------------------------
  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (_hubConnection.state == HubConnectionState.Connected && isActive) {
        _hubConnection
            .invoke("SendHeartbeat", args: [widget.userType, widget.userId]);
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // ------------------------------------------------------------------------
  // Toggle Online Status
  // ------------------------------------------------------------------------
  Future<void> toggleOnlineStatus() async {
    try {
      if (!isActive) {
        // Going online
        if (widget.userType == 'bus') {
          // Show a line selection
          await _showBusLineSelectionDialog();
          if (_selectedBusLineId == null) {
            setState(() {
              isActive = false;
            });
            return;
          } else {
            // Notify server
            await _hubConnection.invoke(
              "NotifyBusDriverStatus",
              args: [widget.userId, _selectedBusLineId!, true],
            );
            setState(() {
              _onlineBusLines.add(_selectedBusLineId!);
              final index = globalBusLineModels
                  .indexWhere((m) => m.id == _selectedBusLineId!);
              if (index != -1) {
                final lineModel = globalBusLineModels[index];
                _selectedBusLine = Polyline(
                  points: lineModel.points,
                  color: lineModel.color,
                  strokeWidth: 5.0,
                );
              }
            });
          }
        } else {
          // Person
          await _hubConnection.invoke(
            "NotifyPersonStatus",
            args: [widget.userId, true],
          );
        }
        // Start location
        _startLocationTracking();
        _startHeartbeat();
      } else {
        // Going offline
        _stopLocationTracking();
        _stopHeartbeat();

        if (widget.userType == 'bus') {
          if (_selectedBusLineId != null) {
            await _hubConnection.invoke(
              "NotifyBusDriverStatus",
              args: [widget.userId, _selectedBusLineId!, false],
            );
            setState(() {
              _onlineBusLines.remove(_selectedBusLineId);
              _selectedBusLineId = null;
              _selectedBusLine = null;
            });
          }
        } else {
          await _hubConnection.invoke(
            "NotifyPersonStatus",
            args: [widget.userId, false],
          );
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("تغییر وضعیت با موفقیت انجام شد"),backgroundColor: Colors.green,),
          snackBarAnimationStyle: AnimationStyle(curve: const Split(3)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("خطا در تغییر وضعیت : ${e.toString()}") ,backgroundColor: Colors.red, ),
          snackBarAnimationStyle: AnimationStyle(curve: const Split(3)));
    }
    setState(() {
      isActive = !isActive;
    });
  }

  Future<List<busLineData.BusLineModel>> _getAvailableBusLines() async {
    try {
      debugPrint('fetchingOnlineBusDrivers ${DateTime.now()}');
      // 'GetOnlineBusDrivers' should return a list of e.g.:
      // [ { "busId":1,"busLineId":101,"latitude":36.21,"longitude":57.64 }, ... ]
      final result =
          await _hubConnection.invoke("GetOnlineBusDrivers") as List<dynamic>?;
      if (result == null) return[];

      var allBusLines = globalBusLineModels;
      List<busLineData.BusLineModel> list = [];

      for (final item in result) {
        final mapItem = item as Map<String, dynamic>;
        final busId = mapItem["busId"] as int;
        final busLineId = mapItem["busLineId"] as int?;
        final lat = mapItem["latitude"] as double?;
        final lng = mapItem["longitude"] as double?;

        final index = globalBusLineModels.indexWhere((m) => m.id == busLineId);
        if (index != -1) {
          final lineModel = globalBusLineModels[index];
          _clickedBusLineColor = lineModel.color;
          _clickedBusLineName = lineModel.name;

          list.add(busLineData.BusLineModel(
              id: lineModel.id,
              name: lineModel.name,
              points: lineModel.points,
              color: lineModel.color));
        }
      }

      for(final line in allBusLines){
        if(list.any((l) => l.id == line.id)){
          allBusLines.remove(line);
        }
      }

      return allBusLines;

    } catch (e) {
      debugPrint("Error fetching bus drivers: $e");
    }
    return [];
  }

  // ------------------------------------------------------------------------
  // Show a dialog for bus driver to pick line
  // ------------------------------------------------------------------------
  Future<void> _showBusLineSelectionDialog() async {
    // Filter out the bus lines that are already occupied
    var _availableList = await _getAvailableBusLines();

    return showDialog<void>(
      context: context,
      builder: (BuildContext context2) {
        int? tempSelectedLineId;
        return AlertDialog(
          title: Row(
            children: [
              const Expanded(
                child: Text(
                  'انتخاب خط',
                  style:
                      TextStyle(fontFamily: FontFamily.iranSans, fontSize: 20),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context2).pop(),
                child: const Icon(
                  Icons.cancel_rounded,
                  size: 24,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          content: StatefulBuilder(
            builder: (context3, setStateDialog) {
              return DropdownButton<int>(
                hint: const Text(
                  'لطفا یک خط را برای شروع انتخاب کنید',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: FontFamily.iranSans),
                ),
                value: tempSelectedLineId,
                items: _availableList.map((line) {
                  return DropdownMenuItem<int>(
                    value: line.id,
                    child: Text(
                      line.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: FontFamily.iranSans),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  setStateDialog(() {
                    tempSelectedLineId = val;
                  });
                },
              );
            },
          ),
          actions: [
            Center(
              child: ElevatedButton(
                onPressed: () {
                  _selectedBusLineId = tempSelectedLineId;
                  Navigator.of(context2).pop();
                },
                style: ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(Colors.grey.shade600),
                ),
                child: const Text(
                  'تایید',
                  style: TextStyle(
                      fontFamily: FontFamily.iranSans, color: Colors.white),
                ),
              ),
            )
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------------------
  // Location Tracking
  // ------------------------------------------------------------------------
  void _startLocationTracking() {
    final location = Location();
    _locationStreamSub = location.onLocationChanged.listen((locData) {
      if (locData.latitude == null || locData.longitude == null) return;

      if (_hubConnection.state == HubConnectionState.Connected && isActive) {
        if (widget.userType == 'bus') {
          _hubConnection.invoke("SendBusLocation", args: [
            widget.userId,
            locData.latitude!,
            locData.longitude!,
          ]);
        } else {
          _hubConnection.invoke("SendPersonLocation", args: [
            widget.userId,
            locData.latitude!,
            locData.longitude!,
          ]);
        }
      }
    });
  }

  void _stopLocationTracking() {
    _locationStreamSub?.cancel();
    _locationStreamSub = null;
  }

  // ------------------------------------------------------------------------
  // Build UI
  // ------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Consumer<LocationProvider>(
        builder: (context, locationProvider, child) {
      final userLocation = locationProvider.userLocation;

      return Scaffold(
        body: Stack(
          children: [
            // MAP
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
              ),
              child: FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  initialCenter: userLocation != null
                      ? LatLng(userLocation.latitude!, userLocation.longitude!)
                      : const LatLng(36.212588, 57.681844),
                  initialZoom: 12,
                  onTap: (TapPosition tp, LatLng position) {
                    setState(() {
                      _clickedBusLine = null;
                      _clickedBusLineColor = null;
                      _clickedBusLineName = null;
                      _showClickedBusLine = false;
                    });
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  ),

                  // 3) Station markers
                  MarkerLayer(
                    markers: stationMarkers.map((originalMarker) {
                      return Marker(
                        width: originalMarker.width,
                        height: originalMarker.height,
                        point: originalMarker.point,
                        child: GestureDetector(
                          onTap: () {
                            final stationName =
                                stationMarkerNames[originalMarker] ??
                                    'ایستگاه ناشناس';
                            showDialog(
                              context: context,
                              builder: (BuildContext context2) {
                                return AlertDialog(
                                  title: Text(
                                    stationName,
                                    style: const TextStyle(
                                      fontFamily: FontFamily.iranSans,
                                      fontSize: 20,
                                    ),
                                  ),
                                  content: const Text(''),
                                  actions: [
                                    FloatingActionButton(
                                      tooltip: 'بستن این پنجره',
                                      onPressed: () {
                                        Navigator.of(context2).pop();
                                      },
                                      child: const Icon(CupertinoIcons.clear),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                          child: originalMarker.child,
                        ),
                      );
                    }).toList(),
                  ),

                  // 4) Static polylines (all bus lines)
                  if (_selectedBusLineId != null &&
                      widget.userType == 'bus' &&
                      isActive)
                    PolylineLayer(
                      polylines: [_selectedBusLine!],
                    ),
                  if (_selectedBusLineId != null &&
                      widget.userType == 'bus' &&
                      isActive)
                    MarkerLayer(
                      markers: [
                        Marker(
                          width: 60,
                          height: 60,
                          point: _selectedBusLine!.points.first,
                          child: Assets.img.icons.originIconPng
                              .image(width: 100, height: 60),
                        ),
                        Marker(
                          width: 60,
                          height: 60,
                          point: _selectedBusLine!.points.last,
                          child: Assets.img.icons.destinationIconPng
                              .image(width: 100, height: 60),
                        ),
                      ],
                    ),

                  // 5) If person clicked a bus, highlight that bus line
                  if (_clickedBusLine != null &&
                      widget.userType == 'person' &&
                      _showClickedBusLine)
                    PolylineLayer(
                      polylines: [_clickedBusLine!],
                    ),

                  if (_clickedBusLine != null &&
                      widget.userType == 'person' &&
                      _showClickedBusLine)
                    MarkerLayer(
                      markers: [
                        Marker(
                          width: 60,
                          height: 60,
                          point: _clickedBusLine!.points.first,
                          child: Assets.img.icons.originIconPng
                              .image(width: 100, height: 60),
                        ),
                        Marker(
                            width: 75,
                            point: _clickedBusLine!
                                .points[_clickedBusLine!.points.length ~/ 2],
                            child: Container(
                              decoration: BoxDecoration(
                                  color: context.themeData.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(16)),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(CupertinoIcons.bus),
                                  Text(_clickedBusLineName!),
                                ],
                              ),
                            )),
                        Marker(
                          width: 60,
                          height: 60,
                          point: _clickedBusLine!.points.last,
                          child: Assets.img.icons.destinationIconPng
                              .image(width: 100, height: 60),
                        ),
                      ],
                    ),

                  // 6) Real-time bus markers (only if user is person)
                  if (widget.userType == 'person')
                    MarkerLayer(
                      markers: _busMarkers.values.toList(),
                    ),

                  // 7) Real-time person markers (shown to both bus & person)
                  MarkerLayer(
                    markers: _personMarkers.values.toList(),
                  ),

                  // 8) Compass
                  const MapCompass.cupertino(
                    hideIfRotatedNorth: true,
                    rotationDuration: Duration(seconds: 1),
                  ),

                  // 9) Current location layer
                  if (userLocation != null)
                    CurrentLocationLayer(
                      alignPositionOnUpdate: AlignOnUpdate.never,
                      style: LocationMarkerStyle(
                        marker: DefaultLocationMarker(
                          color: Colors.green,
                          child: Icon(
                            widget.userType == 'person'
                                ? Icons.person
                                : CupertinoIcons.bus,
                            color: Colors.white,
                          ),
                        ),
                        markerSize: const Size.square(40),
                        accuracyCircleColor:
                            Colors.greenAccent.withOpacity(0.3),
                        headingSectorColor: Colors.green,
                        headingSectorRadius: 100,
                      ),
                      moveAnimationDuration: const Duration(seconds: 2),
                    ),
                ],
              ),
            ),

            // FABs
            Positioned(
              bottom: 105,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton(
                    onPressed: () {
                      setState(() {
                        final center = mapController.camera.center;
                        double newZoom = currentZoom + 1;
                        if (newZoom <= 18) {
                          mapController.move(center, newZoom);
                          currentZoom = currentZoom + 1;
                        }
                      });
                    },
                    backgroundColor: context.themeData.colorScheme.surface,
                    foregroundColor: context.themeData.colorScheme.secondary,
                    child: currentZoom != 18
                        ? const Icon(CupertinoIcons.zoom_in, size: 28)
                        : const Icon(CupertinoIcons.nosign, size: 28),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton(
                    onPressed: () {
                      setState(() {
                        final center = mapController.camera.center;
                        double newZoom = currentZoom - 1;
                        if (newZoom >= 1) {
                          mapController.move(center, newZoom);
                          currentZoom = currentZoom - 1;
                        }
                      });
                    },
                    backgroundColor: context.themeData.colorScheme.surface,
                    foregroundColor: context.themeData.colorScheme.secondary,
                    child: currentZoom != 1
                        ? const Icon(CupertinoIcons.zoom_out, size: 28)
                        : const Icon(CupertinoIcons.nosign, size: 28),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton(
                    onPressed: () async {
                      bool locationFetched =
                          await locationProvider.getUserLocation();
                      if (locationFetched && userLocation != null) {
                        mapController.move(
                          LatLng(
                              userLocation.latitude!, userLocation.longitude!),
                          18,
                        );
                      }
                    },
                    backgroundColor: context.themeData.colorScheme.surface,
                    foregroundColor: context.themeData.colorScheme.secondary,
                    child: userLocation != null
                        ? const Icon(Icons.my_location_rounded, size: 28)
                        : const Icon(Icons.location_disabled, size: 28),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 103,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 63,
                  height: 63,
                  alignment: Alignment.topCenter,
                  child: InkWell(
                    onTap: () {
                      toggleOnlineStatus();
                    },
                    child: Container(
                      height: 63,
                      width: 63,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: isActive
                            ? Colors.green.shade600
                            : const Color(0xff376AED),
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: const Icon(
                        CupertinoIcons.power,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  @override
  void dispose() {
    _stopLocationTracking();
    _stopHeartbeat();
    _hubConnection.stop();
    super.dispose();
  }
}
