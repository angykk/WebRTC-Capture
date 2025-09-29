import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late RTCVideoRenderer localRenderer;
  late Future<void> _cameraInitialization;
  late IO.Socket socket;
  late String? ipAddress;
  RTCPeerConnection? pc; // Changed to nullable
  List<Map<String, dynamic>> pendingIceCandidates =
      []; // Queue for ICE candidates

  var frontFacing = false;

  Future<void> startCameraStream() async {
    await localRenderer.initialize();
    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'video': true,
        'audio': false,
      });
      localRenderer.srcObject = stream;
    } catch (e) {
      print("Error starting camera: $e");
    }
  }

  void switchCamera() {
    Helper.switchCamera(
      localRenderer.srcObject!.getVideoTracks()[0],
    );
    frontFacing = !frontFacing;
  }

  Future<void> createOffer() async {
    try {
      await _cameraInitialization;

      pc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ]
      }, {});

      // Set up ICE candidate handler BEFORE creating offer
      pc!.onIceCandidate = (RTCIceCandidate candidate) {
        print("Sending ICE candidate");
        socket.emit('icecandidate', {
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'candidate': candidate.candidate,
        });
      };

      // Monitor ICE connection state
      pc!.onIceConnectionState = (RTCIceConnectionState state) {
        print("ICE Connection State: $state");
      };

      // Add the local stream to the peer connection
      pc!.addStream(localRenderer.srcObject!);

      print("Creating offer...");

      var offer = await pc!.createOffer();
      await pc!.setLocalDescription(offer);

      socket.emit('offer', {
        'sdp': offer.sdp,
        'type': offer.type,
      });
      print('Offer sent');
    } catch (e) {
      print('Error creating offer: $e');
    }
  }

  void connect() async {
    ipAddress = dotenv.env['SERVER_IP'];
  }

  @override
  void initState() {
    super.initState();
    connect();
    localRenderer = RTCVideoRenderer();
    _cameraInitialization = startCameraStream();

    socket = IO.io(ipAddress, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    socket.connect();

    socket.onConnect((_) {
      print('Connected to signaling server');
      createOffer();
    });

    socket.on('answer', (data) async {
      print('Received answer');

      if (pc == null) {
        print('PC not initialized yet');
        return;
      }

      if (pc!.signalingState ==
          RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        await pc!.setRemoteDescription(
            RTCSessionDescription(data['sdp'], data['type']));
        print('Answer received and set');

        // Process any pending ICE candidates
        for (var candidateData in pendingIceCandidates) {
          try {
            var candidate = RTCIceCandidate(
              candidateData['candidate'],
              candidateData['sdpMid'],
              candidateData['sdpMLineIndex'],
            );
            await pc!.addCandidate(candidate);
            print('Added pending ICE candidate');
          } catch (e) {
            print('Error adding pending candidate: $e');
          }
        }
        pendingIceCandidates.clear();
      } else {
        print('Cannot set remote description in state: ${pc!.signalingState}');
      }
    });

    socket.on('icecandidate', (data) async {
      print("Receiving ICE candidate");

      if (pc == null) {
        print('PC not initialized, queuing ICE candidate');
        return;
      }

      var remoteDesc = await pc!.getRemoteDescription();
      if (remoteDesc == null) {
        print('Remote description not set, queuing ICE candidate');
        pendingIceCandidates.add(data);
        return;
      }

      try {
        var candidate = RTCIceCandidate(
          data['candidate'],
          data['sdpMid'],
          data['sdpMLineIndex'],
        );
        await pc!.addCandidate(candidate);
        print('ICE candidate added');
      } catch (e) {
        print('Error adding ICE candidate: $e');
      }
    });
  }

  @override
  void dispose() {
    localRenderer.dispose();
    socket.dispose();
    pc?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: const Color(0x00000000)),
      home: Scaffold(
        floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            setState(() {
              switchCamera();
            });
          },
          child: const Icon(Icons.loop),
        ),
        body: Center(
          child: FutureBuilder(
            future: _cameraInitialization,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              } else if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              }
              return Stack(
                children: [
                  SizedBox.expand(
                    child: RTCVideoView(
                      localRenderer,
                      mirror: frontFacing,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
