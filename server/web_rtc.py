#venv\Scripts\Activate.ps1    
import eventlet
eventlet.monkey_patch()
from flask import Flask
from flask_socketio import SocketIO, emit
from aiortc import RTCPeerConnection, RTCSessionDescription, RTCIceCandidate
import cv2
import asyncio
import threading 

app = Flask(__name__)
socketio = SocketIO(app, async_mode="eventlet", cors_allowed_origins="*")
pc = RTCPeerConnection()
ice_candidates = []
        
@pc.on('signalingstatechange')
async def on_signaling_state_change():
    print(f"Signaling state changed to: {pc.signalingState}")
    if pc.signalingState == 'have-remote-offer':
        print("Processing queued ICE candidates")
        for ice_candidate in ice_candidates:
            try:
                candidate = RTCIceCandidate(
                    sdpMid=ice_candidate['sdpMid'],
                    sdpMLineIndex=ice_candidate['sdpMLineIndex'],
                    candidate=ice_candidate['candidate']
                )
                add_candidate(candidate)
                print(f"Added queued ICE candidate: {candidate}")
            except Exception as e:
                print(f"Error adding queued ICE candidate: {e}")
        
@socketio.on('icecandidate')
def on_icecandidate_from_client(data):
        print("Received ICE candidate from client append ")
        ice_candidates.append(data)

        
async def add_candidate(data):
    await pc.addIceCandidate(data)

@pc.on('icecandidate')
async def on_icecandidate(event):
    if event.candidate:
        print("Sending ICE candidate to Flutter client")
        socketio.emit('icecandidate', {
            'sdpMid': event.candidate.sdpMid,
            'sdpMLineIndex': event.candidate.sdpMLineIndex,
            'sdp': event.candidate.candidate,
        })
        
@pc.on('track')
async def on_track(track):
    if track.kind == 'video':
        while True:
            try:
                print("trying to receive video frame")
                frame = await asyncio.wait_for(track.recv(), timeout=5.0)
                print("receive video frame")
                display_video(frame.to_ndarray(format='bgr24'))
            except Exception as e:
                print(f"Error receiving video frame: {e}")
                break

def display_video(frame):
    def show_frame():
        cv2.imshow('Video', frame)
        if cv2.waitKey(1) & 0xFF == ord('q'):
            cv2.destroyAllWindows()
    threading.Thread(target=show_frame, daemon=True).start()

async def handle_offer(offer):
    await pc.setRemoteDescription(offer)
    answer = await pc.createAnswer()
    await pc.setLocalDescription(answer)
    socketio.emit('answer', {
        'sdp': pc.localDescription.sdp,
        'type': pc.localDescription.type
    })
    print("Sent answer to client")

        
@socketio.on('offer')
def on_offer(data):
    print("Received offer")
    offer = RTCSessionDescription(data['sdp'], data['type'])
    eventlet.spawn(lambda: asyncio.run(handle_offer(offer)))

if __name__ == '__main__':
    socketio.run(app, host='0.0.0.0', port=5000, debug=True)