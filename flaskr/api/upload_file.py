"""API for the backend"""

import os
from pathlib import Path
from typing import Optional
import zipfile
from flask_restful import Resource, reqparse
import werkzeug
from api.config import DICOMS_DIR, UPLOAD_DIR
from api.calculate_mesh import CalculateMeshLogic, CalculateCtMeshParams
from dataclasses import dataclass
from flask import send_file


@dataclass
class UploadFilesPostParams:
    dicom_archive: werkzeug.datastructures.FileStorage

    @classmethod
    def from_request(cls):
        parser = reqparse.RequestParser()
        parser.add_argument('file', required=True,
                            type=werkzeug.datastructures.FileStorage, location='files')
        args = parser.parse_args()
        return cls(
            dicom_archive=args['file']
        )

@dataclass
class UploadFilesGetParams:
    meshName: str

    @classmethod
    def from_request(cls):
        parser = reqparse.RequestParser()
        parser.add_argument('meshName', required=True, type=str)
        args = parser.parse_args()
        return cls(
            meshName=args['meshName']
        )


class UploadFile(Resource):

    def __init__(self):
        self._mesh_logic = CalculateMeshLogic()
        self._last_mesh_params: Optional[CalculateCtMeshParams] = None
        if not UPLOAD_DIR.exists():
            UPLOAD_DIR.mkdir(parents=True)

    def get(self):
        params = UploadFilesGetParams.from_request()
        return send_file(str(UPLOAD_DIR.absolute()/'dicoms'/params.meshName/'result.obj'))

    def post(self):
        body = UploadFilesPostParams.from_request()
        unpacked_dicoms_path = self._save_zip(body.dicom_archive)
        self._last_mesh_params = CalculateCtMeshParams(
            ct_fname=str(unpacked_dicoms_path.absolute()/'ctFiles'),
            dose_fname=str(unpacked_dicoms_path.absolute() /
                           'rtDoseFile'/'0.dcm'),
            rs_fname=str(unpacked_dicoms_path.absolute() /
                         'rtStructFile'/'0.dcm'),
            save_to=str(unpacked_dicoms_path.absolute()/'result.obj')
        )

        response = self._mesh_logic._calculate_ct(self._last_mesh_params)
        return response.status_code

    def _save_zip(self, zip_achive: werkzeug.datastructures.FileStorage) -> Path:
        archive_fname = Path(zip_achive.filename).stem
        path_to_archive = UPLOAD_DIR/DICOMS_DIR/archive_fname
        with zipfile.ZipFile(zip_achive, 'r') as zip_ref:
            zip_ref.extractall(path_to_archive)
        return path_to_archive
