from dotenv import load_dotenv
import os
load_dotenv()

UPLOAD_DIR = os.environ['UPLOAD_DIR']
DICOMS_DIR = os.environ['DICOMS_DIR']
GENIE_API = f"http://127.0.0.1:{os.environ['GENIE_PORT']}"
