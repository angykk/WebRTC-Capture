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
