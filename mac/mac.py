#venv\Scripts\Activate.ps1    
from flask import Flask
from flask_socketio import SocketIO, emit
from aiortc import RTCPeerConnection, RTCSessionDescription
import cv2
import asyncio
import eventlet

app = Flask(__name__)
socketio = SocketIO(app, async_mode="eventlet", cors_allowed_origins="*")

pc = RTCPeerConnection()

def display_video(frame):
    cv2.imshow('Video', frame)
    if cv2.waitKey(1) & 0xFF == ord('q'):
        cv2.destroyAllWindows()
        
async def handle_offer(offer):
    await pc.setRemoteDescription(offer)
    
    @pc.on('track')
    async def on_track(track):
        if track.kind == 'video':
            print("Receiving video track")
            while True:
                frame = await track.recv()
                display_video(frame.to_ndarray(format='bgr24'))



@socketio.on('offer')
def on_offer(data):
    print("Received offer:", data)

    offer = RTCSessionDescription(data['sdp'], data['type'])
    asyncio.run(handle_offer(offer))


if __name__ == '__main__':
    socketio.run(app, host='0.0.0.0', port=5000, debug=True)
