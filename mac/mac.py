from aiortc import RTCPeerConnection, RTCSessionDescription, VideoStreamTrack
from flask_socketio import SocketIO, emit
import cv2
import asyncio

socketio = SocketIO()

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

if __name__ == '__main__':
    socketio.run(app, host='0.0.0.0', port=8000)
