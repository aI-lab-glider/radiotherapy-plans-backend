
from dataclasses import dataclass
from enum import Enum
from typing import Any, List

import requests
from flask_restful import Resource, reqparse
from api.config import GENIE_API
from api.helpers import get_ct_payload, get_roi_payload
from dataclasses import dataclass, asdict

@dataclass
class CalculateCtMeshParams: 
    ct_fname: str
    dose_fname: str
    rs_fname: str
    save_to: str

@dataclass
class CalculateRoiMeshParams(CalculateCtMeshParams):
    roi_name: str
    save_hot: str
    save_cold: str

class CalculateMeshLogic:

    @classmethod
    def _calculate_roi(cls, mesh_params: CalculateRoiMeshParams):
        payload = get_roi_payload(mesh_params)
        return requests.post(f'{GENIE_API}/MakeRoiMesh', json=asdict(payload))

    @classmethod
    def _calculate_ct(cls, mesh_params: CalculateCtMeshParams):
        payload = get_ct_payload(mesh_params)
        return requests.post(f'{GENIE_API}/MakeCtMesh', json=asdict(payload))




