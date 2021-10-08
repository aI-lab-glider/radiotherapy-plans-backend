"""The main application logic"""

from flask import Flask
from flask_restful import Api
import api

app = Flask(__name__)

rest_api = Api(app)
HOSTED_API_ROOT = "/api/"

rest_api.add_resource(api.rest.FileUploads, HOSTED_API_ROOT + 'Upload')
rest_api.add_resource(api.rest.CalculateMesh, HOSTED_API_ROOT + 'MakeMesh')

if __name__ == '__main__':
    app.run(debug=True)
