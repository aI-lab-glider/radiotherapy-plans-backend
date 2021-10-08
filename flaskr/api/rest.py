"""API for the backend"""

import os
import zipfile
from flask_restful import Resource, reqparse
import werkzeug
import requests

from utils import dicomutils

UPLOAD_DIR = '/home/trebor/ProjectSummer/radiotherapy-plans-backend/static/uploads'
DICOM_PATH_ABSOLUTE = '/home/trebor/ProjectSummer/radiotherapy-plans-backend/static/uploads/dicoms'
GENIE_API = 'http://127.0.0.1:8001/' # temporary

class FileUploads(Resource):

    def __init__(self):
        self.parser = reqparse.RequestParser()
        self.files = []
        if not os.path.isdir(DICOM_PATH_ABSOLUTE):
            os.makedirs(DICOM_PATH_ABSOLUTE) 

    def get(self):
        # get all files in the ../static/uploads directory
        if not self.files:
            self.files = list(os.listdir(DICOM_PATH_ABSOLUTE))
        return {
                'pathAbsolute': DICOM_PATH_ABSOLUTE,
                'count' : len(self.files),
                'files' : self.files,
                }

    def post(self):
        self.parser.add_argument('dicomArchive', required=True, \
                type=werkzeug.datastructures.FileStorage, location='files')

        args = self.parser.parse_args()

        # save the .zip archive
        archive = args.get('dicomArchive')
        path_to_archive = os.path.join(UPLOAD_DIR, archive.filename)
        archive.save(path_to_archive)

        # unzip the archive
        # TODO: implement try catch version & catch zipfile errors
        with zipfile.ZipFile(path_to_archive, 'r') as zip_ref:
            zip_ref.extractall(os.path.join(UPLOAD_DIR, 'dicoms'))

        # verify that the archive contains dicom files
        try:
            check_archive_contents(path_to_archive)
        except dicomutils.InvalidDicomName as err:
            print(err)
#            handle_invalid_contents(err)

        return {
                'status': 'success',
                'message': 'files saved to path',
                'pathAbsolute': DICOM_PATH_ABSOLUTE,
                }


class CalculateMesh(Resource):

    def __init__(self):
        self.parser = reqparse.RequestParser()

    def post(self):
        self.parser.add_argument('type', required=True, \
                type=str, location='json')
        self.parser.add_argument('args', required=False, \
                type=list, location='json')

        args = self.parser.parse_args()
        
        response = None
        
        if args['type'] == "ROI":
            payload = get_roi_payload(args['args'])
            try:
                response = requests.post(GENIE_API + 'MakeRoiMesh', data=payload)
            except Exception:
                print('Endpoint error')
        elif args['type'] == "CT":
            payload = get_ct_payload(args['args'])
            try:
                response = requests.post(GENIE_API + 'MakeCtMesh', data=payload)
            except Exception:
                print('Endpoint error')

        print(response) # debug

def check_archive_contents(path):
    # TODO: implement recursively going into all directories on $path
    # and checking all files in them for regex: ^[[:alnum:]\/\- \.\\]*\.dcm$
    print(path)

def get_roi_payload(args):
    print('get_roi_payload:\ntype of args {}\n{}'.format(type(args),args))
    return args

def get_ct_payload(args):
    print('get_ct_payload:\ntype of args {}\n{}'.format(type(args),args))
    return args
