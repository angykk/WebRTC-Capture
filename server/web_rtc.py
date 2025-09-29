# venv\Scripts\Activate.ps1    
import asyncio
from flask import Flask
from flask_socketio import SocketIO
from aiortc import RTCPeerConnection, RTCSessionDescription, RTCIceCandidate
import cv2
import threading 

app = Flask(__name__)
socketio = SocketIO(app, async_mode="threading", cors_allowed_origins="*")
pc = None
ice_candidates = []
loop = None

def parse_ice_candidate(candidate_string):
    """Parse ICE candidate string to extract components"""
    parts = {}
    tokens = candidate_string.split()
    
    for i, token in enumerate(tokens):
        if token == 'typ' and i + 1 < len(tokens):
            parts['type'] = tokens[i + 1]
        elif i > 0:
            if tokens[i - 1] == 'candidate':
                parts['foundation'] = token
            elif i >= 2 and tokens[i - 2] == 'candidate':
                parts['component'] = int(token)
            elif i >= 3 and tokens[i - 3] == 'candidate':
                parts['protocol'] = token.lower()
            elif i >= 4 and tokens[i - 4] == 'candidate':
                parts['priority'] = int(token)
            elif i >= 5 and tokens[i - 5] == 'candidate':
                parts['ip'] = token
            elif i >= 6 and tokens[i - 6] == 'candidate':
                parts['port'] = int(token)
    
    return parts

@socketio.on('connect')
def on_connect():
    global pc, ice_candidates
    print("Client connected")
    pc = RTCPeerConnection()
    ice_candidates = []
    
    @pc.on('signalingstatechange')
    async def on_signaling_state_change():
        print(f"Signaling state changed to: {pc.signalingState}")
        if pc.signalingState == 'stable' and ice_candidates:
            print(f"Processing {len(ice_candidates)} queued ICE candidates")
            for ice_candidate in ice_candidates:
                try:
                    parsed = parse_ice_candidate(ice_candidate['candidate'])
                    candidate = RTCIceCandidate(
                        component=parsed.get('component', 1),
                        foundation=parsed.get('foundation', '1'),
                        ip=parsed.get('ip', '0.0.0.0'),
                        port=parsed.get('port', 0),
                        priority=parsed.get('priority', 0),
                        protocol=parsed.get('protocol', 'udp'),
                        type=parsed.get('type', 'host'),
                        sdpMid=ice_candidate['sdpMid'],
                        sdpMLineIndex=ice_candidate['sdpMLineIndex']
                    )
                    await pc.addIceCandidate(candidate)
                except Exception as e:
                    print(f"Error adding queued ICE candidate: {e}")
                    import traceback
                    traceback.print_exc()
            ice_candidates.clear()
    
    @pc.on('iceconnectionstatechange')
    async def on_ice_connection_state_change():
        print(f"ICE connection state: {pc.iceConnectionState}")
    
    @pc.on('connectionstatechange')
    async def on_connection_state_change():
        print(f"Connection state: {pc.connectionState}")
    
    @pc.on('track')
    def on_track(track):        
        if track.kind == 'video':
            async def process_track():
                frame_count = 0
                try:
                    while True:
                        try:
                            # print(f"Waiting for video frame... (attempt {frame_count + 1})")
                            frame = await track.recv()
                            # frame_count += 1                            
                            img = frame.to_ndarray(format='bgr24')                            
                            cv2.imshow('WebRTC Video Stream', img)
                            if cv2.waitKey(1) & 0xFF == ord('q'):
                                print("User pressed 'q', stopping...")
                                break
                            
                        except Exception as e:
                            print(f"Error receiving video frame: {e}")
                            import traceback
                            traceback.print_exc()
                            break
                finally:
                    print("Closing video window...")
                    cv2.destroyAllWindows()
            
            future = asyncio.run_coroutine_threadsafe(process_track(), loop)
            print(f"process_track scheduled: {future}")

@socketio.on('icecandidate')
def on_icecandidate_from_client(data):
    print(f"Received ICE candidate from client: {data.get('candidate', 'N/A')[:50]}...")
    if pc is None:
        print("null pc")
        return
    
    async def add_ice_candidate():
        try:
            parsed = parse_ice_candidate(data['candidate'])
            print(f"Parsed ICE: type={parsed.get('type')}, ip={parsed.get('ip')}, port={parsed.get('port')}")
            
            candidate = RTCIceCandidate(
                component=parsed.get('component', 1),
                foundation=parsed.get('foundation', '1'),
                ip=parsed.get('ip', '0.0.0.0'),
                port=parsed.get('port', 0),
                priority=parsed.get('priority', 0),
                protocol=parsed.get('protocol', 'udp'),
                type=parsed.get('type', 'host'),
                sdpMid=data['sdpMid'],
                sdpMLineIndex=data['sdpMLineIndex']
            )
            
            await pc.addIceCandidate(candidate)
            print("Added ICE candidate")
        except Exception as e:
            print(f"Error adding ICE candidate: {e}")
            import traceback
            traceback.print_exc()
    
    if pc.remoteDescription is not None:
        asyncio.run_coroutine_threadsafe(add_ice_candidate(), loop)
    else:
        ice_candidates.append(data)
        print("Queued ICE candidate")

async def handle_offer(offer):
    if pc is None:
        print("null pc")
        return
    
    print(f"\nReceived offer")
    print(offer.sdp[:200] + "..." if len(offer.sdp) > 200 else offer.sdp)
    
    await pc.setRemoteDescription(offer)
    print(f"Remote description set. Signaling state: {pc.signalingState}")
    
    transceivers = pc.getTransceivers()
    print(f"Transceivers count: {len(transceivers)}")
    for i, t in enumerate(transceivers):
        print(f"  Transceiver {i}: {t.kind}, direction={t.direction}")
        
    answer = await pc.createAnswer()
    await pc.setLocalDescription(answer)
    
    print(f"\nGenerated Answer")
    print(answer.sdp[:200] + "..." if len(answer.sdp) > 200 else answer.sdp)
    
    socketio.emit('answer', {
        'sdp': pc.localDescription.sdp,
        'type': pc.localDescription.type
    })
    print("Sent answer to client")

@socketio.on('offer')
def on_offer(data):
    if pc is None:
        print("null pc")
        return
        
    offer = RTCSessionDescription(data['sdp'], data['type'])
    asyncio.run_coroutine_threadsafe(handle_offer(offer), loop)

@socketio.on('disconnect')
def on_disconnect():
    global pc
    print("Client disconnected")
    if pc:
        asyncio.run_coroutine_threadsafe(pc.close(), loop)
        pc = None
        cv2.destroyAllWindows()

def run_async_loop():
    global loop
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    print("asyncio event loop started")
    loop.run_forever()

if __name__ == '__main__':
    asyncio_thread = threading.Thread(target=run_async_loop, daemon=True)
    asyncio_thread.start()
    
    import time
    time.sleep(0.5)
    
    socketio.run(app, host='0.0.0.0', port=5000, debug=True, use_reloader=False)