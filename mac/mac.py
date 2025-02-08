#venv\Scripts\Activate.ps1    
from flask import Flask
from flask_socketio import SocketIO, emit
from aiortc import RTCPeerConnection, RTCSessionDescription, RTCIceCandidate
import cv2
import asyncio
import eventlet

app = Flask(__name__)
socketio = SocketIO(app, async_mode="eventlet")

pc = RTCPeerConnection()

def display_video(frame):
    cv2.imshow('Video', frame)
    if cv2.waitKey(1) & 0xFF == ord('q'):
        cv2.destroyAllWindows()


async def handle_offer(offer):
    @pc.on('track')
    async def on_track(track):
        if track.kind == 'video':
            print("Receiving video track")
            while True:
                try:
                    if pc.connectionState != "connected":
                        print(f"Peer connection state: {pc.connectionState}")
                        await asyncio.sleep(1)
                        continue
                    frame = await track.recv()
                    print("Receiving video track 2")
                    display_video(frame.to_ndarray(format='bgr24'))
                except Exception as e:
                    print(f"Error receiving video frame: {e}")
                break
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
    print("Received offer:")
    offer = RTCSessionDescription(data['sdp'], data['type'])
    eventlet.spawn(asyncio.run, handle_offer(offer))


if __name__ == '__main__':
    socketio.run(app, host='0.0.0.0', port=5000, debug=True)
