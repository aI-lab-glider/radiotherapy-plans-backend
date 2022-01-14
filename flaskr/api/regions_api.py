from flask_restful import Resource, reqparse
from dicom_parser import Image
from api.config import UPLOAD_DIR
import json

class RegionsApi(Resource):
    
    def get(self, dicom_name: str):
        """
        Dicom for which regions should be parsed.
        """
        # according to the convention
        rtStructFile = UPLOAD_DIR.absolute()/'dicoms'/dicom_name/'rtStructFile'/'0.dcm'
        rtStructImage = Image(rtStructFile)
        roiDataset = rtStructImage.header.raw['StructureSetROISequence']
        names = [el['ROIName'].value for el in roiDataset]
        return json.dumps({ 'roiNames': names })