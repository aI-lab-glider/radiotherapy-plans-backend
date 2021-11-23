"""API for the backend"""

import os
import zipfile
from flask_restful import Resource, reqparse
import werkzeug
import requests
from api.config import DICOMS_DIR, UPLOAD_DIR
from api.helpers import check_archive_contents
from utils import dicomutils
from dataclasses import dataclass



@dataclass
class UploadFilesPostParams:
    dicom_archive: werkzeug.datastructures.FileStorage

    @classmethod
    def from_request(cls):
        parser = reqparse.RequestParser()
        parser.add_argument('file', required=True, \
                type=werkzeug.datastructures.FileStorage, location='files')
        args = parser.parse_args()
        return cls(
            dicom_archive=args['file']
        )


class UploadFile(Resource):

    def __init__(self):
        if not os.path.isdir(DICOMS_DIR):
            os.makedirs(DICOMS_DIR) 

    def get(self):
        files = list(os.listdir(DICOMS_DIR))
        return {
                'pathAbsolute': DICOMS_DIR,
                'count' : len(files),
                'files' : files,
                }

    def post(self):
        body = UploadFilesPostParams.from_request()        

        # save the .zip archive
        path = self._save_zip(body.dicom_archive)
        is_valid = self._validate_archive(path)
        
        return {
                'status': 'success' if is_valid else 'failure',
                'message': 'files saved to path',
                'pathAbsolute': DICOMS_DIR,
            }

    def _save_zip(self, zip_achive: werkzeug.datastructures.FileStorage) -> str:
        path_to_archive = os.path.join(UPLOAD_DIR, zip_achive.filename)
        if not os.path.isdir(UPLOAD_DIR):
            os.mkdir(UPLOAD_DIR)
        zip_achive.save(path_to_archive)
        return path_to_archive

    def _validate_archive(self, path):
        tmp_unzip_location = 'dicoms'
        with zipfile.ZipFile(path, 'r') as zip_ref:
            zip_ref.extractall(os.path.join(UPLOAD_DIR, tmp_unzip_location))
        try:
            check_archive_contents(path)
        except dicomutils.InvalidDicomName:
            return False
        return True
