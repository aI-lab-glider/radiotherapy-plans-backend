"""API for the backend"""

import os
from pathlib import Path
from typing import Literal, Optional
import zipfile
from api.config import DICOMS_DIR, UPLOAD_DIR
from api.calculate_mesh import CalculateMeshLogic, CalculateCtMeshParams
from flask_restful import Resource, reqparse
from dataclasses import dataclass
from flask import send_file
from api.calculate_mesh import CalculateRoiMeshParams
from api.config import ROI_DIR


@dataclass
class CalculateROIPostRequestParams:
    roi_name: str


    @classmethod
    def from_request(cls):
        parser = reqparse.RequestParser()
        parser.add_argument('roi_name', required=True, type=str)
        args = parser.parse_args()
        return cls(
            roi_name=args['roi_name'],
        )

@dataclass
class CalculateROIGetRequestParams:
    roi_name: str
    type: Literal["hot"] or Literal["cold"] or None


    @classmethod
    def from_request(cls):
        parser = reqparse.RequestParser()
        parser.add_argument('roi_name', required=True, type=str)
        parser.add_argument('type', required=False, type=str)
        args = parser.parse_args()
        return cls(
            roi_name=args['roi_name'],
            type=args.get('type')
        )


class CalculateROI(Resource):

    def __init__(self):
        self._mesh_logic = CalculateMeshLogic()
        self._last_mesh_params: Optional[CalculateCtMeshParams] = None
        if not UPLOAD_DIR.exists():
            UPLOAD_DIR.mkdir(parents=True)

    def get(self, mesh_name: str):
        params = CalculateROIGetRequestParams.from_request()
        suffix = f'_{params.type}' if params.type else ''
        return send_file(str(ROI_DIR.absolute()/mesh_name/f'{params.roi_name}{suffix}.obj'))

    def post(self, mesh_name: str):
        body = CalculateROIPostRequestParams.from_request()
        # TODO refactor path creation
        unpacked_dicoms_path = UPLOAD_DIR/DICOMS_DIR/mesh_name
        
        print('Upload dir', ROI_DIR.absolute()/mesh_name/f'{body.roi_name}.obj')
        last_mesh_params = CalculateRoiMeshParams(
            ct_fname=str(unpacked_dicoms_path.absolute()/'ctFiles'),
            dose_fname=str(unpacked_dicoms_path.absolute() /
                           'rtDoseFile'/'0.dcm'),
            rs_fname=str(unpacked_dicoms_path.absolute() /
                         'rtStructFile'/'0.dcm'),
            save_to=str(ROI_DIR.absolute()/mesh_name/f'{body.roi_name}.obj'),
            roi_name=body.roi_name,
            save_cold=str(ROI_DIR.absolute()/mesh_name/f'{body.roi_name}_cold.obj'),
            save_hot=str(ROI_DIR.absolute()/mesh_name/f'{body.roi_name}_hot.obj')
        )
        print(last_mesh_params)

        response = self._mesh_logic._calculate_roi(last_mesh_params)
        return response.status_code

