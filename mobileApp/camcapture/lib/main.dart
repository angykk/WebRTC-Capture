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
      pc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ]
      }, {});

      // Add the local stream to the peer connection
      localRenderer.srcObject?.getVideoTracks().forEach((track) {
        pc.addTrack(track, localRenderer.srcObject!).catchError((error) {
          print('Error adding track: $error');
        });
      });
      // Handle ICE candidates
      pc.onIceCandidate = (candidate) {
        print('Sending ice candidate');
        if (candidate != null) {
          socket.emit('icecandidate', {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          });
        }
      };

      var offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      socket.emit('offer', {
        'sdp': offer.sdp,
        'type': offer.type,
      });
      print('Offer sent');

      socket.on('answer', (data) async {
        print('Received answer:');
        if (pc.signalingState ==
            RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
          await pc.setRemoteDescription(
              RTCSessionDescription(data['sdp'], data['type']));
          print('Answer received and set');
        } else {
          print('Cannot set remote description in state: ${pc.signalingState}');
        }
      });

      socket.on('icecandidate', (data) async {
        var candidate = RTCIceCandidate(
          data['candidate'],
          data['sdpMid'],
          data['sdpMLineIndex'],
        );
        await pc.addCandidate(candidate);
        print('ICE candidate added');
      });
    } catch (e) {
      print('Error creating offer: $e');
    }
  }

  Future<void> connect() async {
    ipAddress = dotenv.env['SERVER_IP'];
  }

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    await connect();
    localRenderer = RTCVideoRenderer();
    _cameraInitialization = startCameraStream();

    socket = IO.io(ipAddress, <String, dynamic>{
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
