"""Backend main module"""

from flask import Flask
from flask_restful import Api
import api

print(api)

# Flask application initialization
app = Flask(__name__)

# REST API initialization
rest_api = Api(app)
HOSTED_API_ROOT = "/api/"

rest_api.add_resource(api.rest.FileUploads, HOSTED_API_ROOT + 'upload')

@app.route("/")
def hello_world():
    return "<p>Hello World!</p>"

if __name__ == '__main__':
    app.run(debug=True)
