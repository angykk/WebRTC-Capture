import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

void main() async {
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
  late RTCPeerConnection pc;

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
      pc = await createPeerConnection({});

      // Add the local stream to the peer connection
      localRenderer.srcObject?.getVideoTracks().forEach((track) {
        pc.addTrack(track, localRenderer.srcObject!).catchError((error) {
          print('Error adding track: $error');
        });
      });

      var offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      socket.emit('offer', {
        'sdp': offer.sdp,
        'type': offer.type,
      });
      print('Offer sent');
    } catch (e) {
      print('Error creating offer: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    localRenderer = RTCVideoRenderer();
    _cameraInitialization = startCameraStream();

    socket = IO.io('http://192.168.2.44:5000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket.connect();

    socket.onConnect((_) {
      print('Connected to signaling server');
      createOffer();
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
