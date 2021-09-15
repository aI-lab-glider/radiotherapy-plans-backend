"""Backend main module"""

from flask import Flask
from flask_restful import Api

from api import FileUploads

# Flask application initialization
app = Flask(__name__)

# REST API initialization
api = Api(app)
HOSTED_API_ROOT = "/api/"

api.add_resource(FileUploads, HOSTED_API_ROOT + 'upload')

@app.route("/")
def hello_world():
    return "<p>Hello World!</p>"

if __name__ == '__main__':
    app.run(debug=True)
