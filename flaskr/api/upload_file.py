"""API for the backend"""

import os
from pathlib import Path
import zipfile
from flask_restful import Resource, reqparse
import werkzeug
from api.config import DICOMS_DIR, UPLOAD_DIR
from api.calculate_mesh import CalculateMesh, MeshParams
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
        self._mesh_logic = CalculateMesh()
        if not UPLOAD_DIR.exists():
            UPLOAD_DIR.mkdir(parents=True)


    def get(self):
        files = list(DICOMS_DIR.iterdir())
        return {
                'pathAbsolute': str(DICOMS_DIR),
                'count' : len(files),
                'files' : files,
                }

    def post(self):
        body = UploadFilesPostParams.from_request()        
        unpacked_dicoms_path = self._save_zip(body.dicom_archive)
        mesh_params = MeshParams(
                ct_fname=str(unpacked_dicoms_path/'ctFiles'),
                dose_fname=str(unpacked_dicoms_path/'rtDoseFile'/'0.dcm'),
                rs_fname=str(unpacked_dicoms_path/'rtStructFile'/'0.dcm'),
                save_to=str(unpacked_dicoms_path/'result.obj')
            )
        
        response = self._mesh_logic._calculate_ct(mesh_params)
        if response.status_code != 200:
            return 422
        computations_result = self._read_mesh(mesh_params.save_to)
        return {
            'mesh': computations_result
        }

    def _save_zip(self, zip_achive: werkzeug.datastructures.FileStorage) -> Path:
        archive_fname = Path(zip_achive.filename).stem
        path_to_archive = DICOMS_DIR/archive_fname
        with zipfile.ZipFile(zip_achive, 'r') as zip_ref:
            zip_ref.extractall(UPLOAD_DIR/path_to_archive)
        return path_to_archive
    
    def _read_mesh(self, mesh_file):
        with open(mesh_file, 'r') as f:
            return "".join(f.readlines())