from flask import Flask
from flask_socketio import SocketIO, emit
from flask_cors import CORS


app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})
socketio = SocketIO(app)

@socketio.on('offer')
def handle_offer(data):
    emit('offer', data, broadcast=True)

@socketio.on('answer')
def handle_answer(data):
    emit('answer', data, broadcast=True)

if __name__ == '__main__':
    socketio.run(app, host='0.0.0.0', port=8000)