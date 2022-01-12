from flask_restful import Resource
from api.config import UPLOAD_DIR
import json

class UploadedDicoms(Resource):
    
    def get(self):
        directories = map(lambda path: path.stem, (UPLOAD_DIR.absolute()/'dicoms').iterdir())
        return json.dumps({'meshesNames': list(directories)})
