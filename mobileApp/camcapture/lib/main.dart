import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

final localRenderer = RTCVideoRenderer();
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
  late IO.Socket socket;
  late RTCPeerConnection pc;

  Future<void> createOffer() async {
    pc = await createPeerConnection({});

    var offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    // Send the SDP offer to the signaling server
    socket.emit('offer', {
      'sdp': offer.sdp,
      'type': offer.type,
    });
  }

  void handleOffer(dynamic data) async {
    var remoteDesc = RTCSessionDescription(data['sdp'], data['type']);
    await pc.setRemoteDescription(remoteDesc);

    var answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    socket.emit('answer', {
      'sdp': answer.sdp,
      'type': answer.type,
    });
  }

  void handleAnswer(dynamic data) async {
    var remoteDesc = RTCSessionDescription(data['sdp'], data['type']);
    await pc.setRemoteDescription(remoteDesc);
  }

  @override
  void initState() {
    super.initState();
    _cameraInitialization = startCameraStream();

    String serverIp = dotenv.env['SERVER_IP'] ?? '127.0.0.1';
    socket = IO.io('http://$serverIp:8000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket.connect();

    socket.on('connect', (_) {
      print('Connected to signaling server');
      createOffer(); 
    });

    socket.on('offer', (data) {
      handleOffer(data);
    });

    socket.on('answer', (data) {
      handleAnswer(data);
    });
  }

  @override
  void dispose() {
    localRenderer.dispose();
    socket.dispose();
    pc.close();
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
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
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
