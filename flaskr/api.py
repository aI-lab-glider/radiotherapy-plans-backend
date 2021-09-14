from flask_restful import Resource, reqparse
import os
import werkzeug
import requests
import zipfile

UPLOAD_DIR = '../static/uploads'
DICOM_PATH_RELATIVE = UPLOAD_DIR + '/dicoms'
DICOM_PATH_ABSOLUTE = '~/ProjectSummer/radiotherapy-plans-backend/static/uploads/dicoms'
GENIE_API = 'http://127.0.0.1:8001/'

class HelloWorld(Resource):
    def get(self):
        return {'hello': 'world'}

class FileUploads(Resource):
    def __init__(self):
        self.parser = reqparse.RequestParser()

    def get(self):
        # get all files in the ./static/uploads directory
        files = [f for f in os.listdir(UPLOAD_DIR + '/dicoms')]
        return {
                'pathRelative': DICOM_PATH_RELATIVE,
                'pathAbsolute': DICOM_PATH_ABSOLUTE,
                'count' : len(files),
                'files' : files,
                }

    def post(self):
        self.parser.add_argument('dicomArchive', required=True, \
                type=werkzeug.datastructures.FileStorage, location='files')

        args = self.parser.parse_args()

        # save the .zip archive
        archive = args.get('dicomArchive')
        archive.save(os.path.join(UPLOAD_DIR, archive.filename))

        # unzip the archive
        with zipfile.ZipFile(os.path.join(UPLOAD_DIR, archive.filename), 'r') as zip_ref:
            zip_ref.extractall(os.path.join(UPLOAD_DIR, 'dicoms'))
        
        return { 
                'message': 'files saved to path',
                'pathRelative': DICOM_PATH_RELATIVE,
                'pathAbsolute': DICOM_PATH_ABSOLUTE,
            }

