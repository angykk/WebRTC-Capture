from flask import Flask
from flask_socketio import SocketIO, emit
from aiortc import RTCPeerConnection, RTCSessionDescription, VideoStreamTrack
import cv2
import asyncio

# Flask and SocketIO setup
app = Flask(__name__)
socketio = SocketIO(app)

# WebSocket event handlers
@socketio.on('offer')
def handle_offer(data):
    emit('offer', data, broadcast=True)

@socketio.on('answer')
def handle_answer(data):
    emit('answer', data, broadcast=True)

# Start the Flask-SocketIO server
if __name__ == '__main__':
    socketio.run(app, host='0.0.0.0', port=8000)

pc = RTCPeerConnection()

# Track for displaying video
class VideoDisplayTrack(VideoStreamTrack):
    def __init__(self, frame):
        super().__init__()
        self.frame = frame

    async def recv(self):
        return self.frame

@socketio.on('offer')
async def on_offer(data):
    offer = RTCSessionDescription(data['sdp'], data['type'])
    await pc.setRemoteDescription(offer)

    # Create and send an answer
    answer = await pc.createAnswer()
    await pc.setLocalDescription(answer)
    emit('answer', {'sdp': pc.localDescription.sdp, 'type': pc.localDescription.type})


# Display the video frame
def display_video(frame):
    cv2.imshow('Video', frame.to_ndarray(format='bgr24'))
    if cv2.waitKey(1) & 0xFF == ord('q'):
        cv2.destroyAllWindows()


