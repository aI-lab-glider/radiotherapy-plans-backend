"""The main application logic"""

from flask import Flask
from flask_restful import Api
from api import UploadFile, CalculateMesh
from flask_cors import CORS


app = Flask(__name__)
CORS(app)
rest_api = Api(app)
HOSTED_API_ROOT = "/api/"

rest_api.add_resource(UploadFile, HOSTED_API_ROOT + 'Upload')
rest_api.add_resource(CalculateMesh, HOSTED_API_ROOT + 'MakeMesh')

if __name__ == '__main__':
    app.run(debug=True)
