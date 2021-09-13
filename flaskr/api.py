from flask_restful import Resource, reqparse
import os
import werkzeug
import requests

UPLOAD_DIR = '../static/uploads'
GENIE_API = 'http://127.0.0.1:8001/'

class HelloWorld(Resource):
    def get(self):
        return {'hello': 'world'}

class FileUploads(Resource):
    def __init__(self):
        self.parser = reqparse.RequestParser()

    def get(self):
        # get all files in the ./static/uploads directory
        files = [f for f in os.listdir(UPLOAD_DIR)]
        return {
                'dir' : UPLOAD_DIR, 
                'count' : len(files),
                'files' : files,
                }

    def post(self):
        self.parser.add_argument('startComputation', required=True, type=str)
        self.parser.add_argument('CTFile', required=False, \
                type=werkzeug.datastructures.FileStorage, location='files')
        self.parser.add_arguemnt('DoseDataFile', required=False, \
                type=werkzeug.datastructures.FileStorage, location='files')
        self.parser.add_argument('RSFile', required=False, \
                type=werkzeug.datastructures.FileStorage, location='files')

        args = self.parser.parse_args()

        if 'CTFile' in args:
            save_file(args.get('CTFile'), 'CT.zip')
        if 'DoseSumFile' in args:
            save_file(args.get('DoseSumFile'), 'DoseSum.zip')
        if 'RSFile' in args:
            save_file(args.get('RSFile'), 'RS.zip')
        
        if args['startComputation']:
            payload = {
                    'CT_fname': 'CT.zip',
                    'DoseSum_fname': 'DoseSum.zip',
                    'RS_fname': 'RS.zip'
                    }
            response = requests.request('GET', GENIE_API+'load', headers={}, data=payload, files=[])
            return {
                    'successful': True,
                    'computationStarted': True,
                }

        return {
                'successful': True,
                'computationStarted': False,
            }

def save_file(file, filename):
    file.save(os.path.join(UPLOAD_DIR, filename))

