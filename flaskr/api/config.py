from dotenv import load_dotenv
from pathlib import Path
import os
load_dotenv()

UPLOAD_DIR = Path(os.environ['UPLOAD_DIR'])
DICOMS_DIR = Path(os.environ['DICOMS_DIR'])
GENIE_API = f"http://127.0.0.1:{os.environ['GENIE_PORT']}"
