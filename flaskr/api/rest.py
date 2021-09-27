"""API for the backend"""

import os
import zipfile
from flask_restful import Resource, reqparse
import werkzeug
from utils import dicomutils

UPLOAD_DIR = '../static/uploads'
DICOM_PATH_RELATIVE = UPLOAD_DIR + '/dicoms'
DICOM_PATH_ABSOLUTE = '~/ProjectSummer/radiotherapy-plans-backend/static/uploads/dicoms'
GENIE_API = 'http://127.0.0.1:8001/'

class FileUploads(Resource):

    def __init__(self):
        self.parser = reqparse.RequestParser()
        self.files = []

    def get(self):
        # get all files in the ./static/uploads directory
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
            handle_invalid_contents(err)

        return {
                'status': 'success',
                'message': 'files saved to path',
                'pathRelative': DICOM_PATH_RELATIVE,
                'pathAbsolute': DICOM_PATH_ABSOLUTE,
                }


def check_archive_contents(path):
    # TODO: implement recursively going into all directories on $path
    # and checking all files in them for regex: ^[[:alnum:]\/\- \.\\]*\.dcm$
    raise NotImplementedError('check_archive_contents()')


def handle_bad_zip_file(ex: zipfile.BadZipFile):
    return {
            'status': 'exception',
            'message': 'bad zip file provided',
            'exceptionMessage': str(ex),
            }


def handle_large_zip_file(ex: zipfile.LargeZipFile):
    return {
            'status': 'exception',
            'message': 'excedingly large zip file provided',
            'exceptionMessage': str(ex),
            }


def handle_invalid_contents(ex: dicomutils.InvalidDicomName):
    return {
            'status': 'exception',
            'message': 'invalid name found inside the archive: {}'.format(ex.filename),
            'exceptionMessage': ex.message,
            }
