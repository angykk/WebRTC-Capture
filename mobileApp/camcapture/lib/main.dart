import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

void main() {
  runApp(const MyApp());
}

final localRenderer = RTCVideoRenderer();
var frontFacing = false;

class WebRTCSignaling {
  late IO.Socket socket;
  late RTCPeerConnection pc;

  WebRTCSignaling() {
    // Connect to the signaling server
    socket = IO.io('http://your-signaling-server:8000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket.connect();

    // Listen for incoming events
    socket.on('connect', (_) {
      print('Connected to signaling server');
    });

    socket.on('offer', (data) {
      handleOffer(data);
    });

    socket.on('answer', (data) {
      handleAnswer(data);
    });
  }

  Future<void> createOffer() async {
    pc = await createPeerConnection({
      'iceServers': [
        {'url': 'stun:stun.l.google.com:19302'}, // STUN server example
      ]
    });

    var offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    // Send the SDP offer to the signaling server
    socket.emit('offer', {
      'sdp': offer.sdp,
      'type': offer.type,
    });
  }

  void handleOffer(dynamic data) async {
    // Parse the offer and set it as the remote description
    var remoteDesc = RTCSessionDescription(data['sdp'], data['type']);
    await pc.setRemoteDescription(remoteDesc);

    // Create an answer
    var answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    // Send the answer back to the signaling server
    socket.emit('answer', {
      'sdp': answer.sdp,
      'type': answer.type,
    });
  }

  void handleAnswer(dynamic data) async {
    // Parse and set the remote description
    var remoteDesc = RTCSessionDescription(data['sdp'], data['type']);
    await pc.setRemoteDescription(remoteDesc);
  }

  void handleIceCandidate(dynamic data) async {
    // Add ICE candidate received from the other peer
    var candidate = RTCIceCandidate(
      data['candidate'],
      data['sdpMid'],
      data['sdpMLineIndex'],
    );
    await pc.addCandidate(candidate);
  }

  void dispose() {
    socket.dispose();
    pc.close();
  }
}

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
  final camera = Helper.switchCamera(
    localRenderer.srcObject!.getVideoTracks()[0],
  );
  frontFacing = !frontFacing;
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<void> _cameraInitialization;
  late WebRTCSignaling signaling;

  @override
  void initState() {
    _cameraInitialization = startCameraStream();
    signaling = WebRTCSignaling();
    super.initState();
  }

  @override
  void dispose() {
    localRenderer.dispose();
    signaling.socket.dispose();
    signaling.pc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: const Color(0x00000000)),
      home: Scaffold(
        body: Center(
          child: FutureBuilder(
            future: _cameraInitialization,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              } else if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              }
              signaling.createOffer();
              return Scaffold(
                floatingActionButtonLocation:
                    FloatingActionButtonLocation.endDocked,
                floatingActionButton: FloatingActionButton(
                  onPressed: () {
                    setState(() {
                      switchCamera();
                    });
                  },
                  child: const Icon(Icons.loop),
                ),
                body: Stack(
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
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
