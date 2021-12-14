
from dataclasses import dataclass
from enum import Enum
from typing import Any, List

import requests
from flask_restful import Resource, reqparse
from api.config import GENIE_API
from api.helpers import get_ct_payload, get_roi_payload
from dataclasses import dataclass, asdict

@dataclass
class MeshParams: 
    ct_fname: str
    dose_fname: str
    rs_fname: str
    save_to: str

class MeshType(Enum):
    ROI = 'ROI'
    CT = 'CT'

@dataclass
class CalculateMeshPostParams:
    mesh_type: MeshType
    mesh_params: List[Any]

    @classmethod
    def from_request(cls) -> 'CalculateMeshPostParams':
        parser = reqparse.RequestParser()
        parser.add_argument('mesh_type', required=True, \
                type=str, location='json')
        parser.add_argument('mesh_params', required=False, \
                type=list, location='json')
        args = parser.parse_args()
        return cls(
            mesh_type=MeshType(args['mesh_type']),
            mesh_params=args['mesh_params'],
        )

class CalculateMesh(Resource):

    def post(self):
        body = CalculateMeshPostParams.from_request()
        parser = self._get_args_parser(body.mesh_type)     
        endpoint = self._get_calculation_endpoint_url(body.mesh_type)
        payload = parser(body.mesh_params)
        return requests.post(f'{GENIE_API}/{endpoint}', data=payload)

    def _get_args_parser(self, mesh_type: MeshType):
        return {
            MeshType.CT: get_ct_payload,
            MeshType.ROI: get_roi_payload
        }[mesh_type]

    def _get_calculation_endpoint_url(self, mesh_type: MeshType):
        return {
            MeshType.ROI: 'MakeRoiMesh', 
            MeshType.CT: 'MakeCtMesh'
        }[mesh_type]

    def _calculate_roi(self, mesh_params: MeshParams):
        payload = get_roi_payload(mesh_params)
        return requests.post(f'{GENIE_API}/MakeRoiMesh', json=asdict(payload))

    def _calculate_ct(self, mesh_params: MeshParams):
        payload = get_ct_payload(mesh_params)
        return requests.post(f'{GENIE_API}/MakeCtMesh', json=asdict(payload))




