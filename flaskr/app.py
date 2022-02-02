"""The main application logic"""

from flask import Flask
from flask_restful import Api, Resource
from api import UploadFile, CalculateMeshLogic, UploadedDicoms
from flask_cors import CORS
from api.calculate_roi import CalculateROI
from api.regions_api import RegionsApi
from api.config import PORT


app = Flask(__name__)
CORS(app)
rest_api = Api(app)
HOSTED_API_ROOT = "/api/"

rest_api.add_resource(UploadFile, HOSTED_API_ROOT + 'Upload')
rest_api.add_resource(CalculateROI, HOSTED_API_ROOT + 'CalculateRoi/<string:mesh_name>')
rest_api.add_resource(UploadedDicoms, HOSTED_API_ROOT + 'UploadedDicoms')
rest_api.add_resource(RegionsApi, f'{HOSTED_API_ROOT}UploadedDicoms/<string:dicom_name>/regions')


if __name__ == '__main__':
    app.run(debug=True, port=PORT)
