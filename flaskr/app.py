from flask import Flask
from flask_restful import Api

from api import HelloWorld, FileUploads

# Flask application initialization
app = Flask(__name__)

# REST API initialization
api = Api(app)
hosted_api_root = "/api/" 

api.add_resource(HelloWorld, hosted_api_root + 'hello')
api.add_resource(FileUploads, hosted_api_root + 'upload')

computation_api_url_base = "http://127.0.0.1:8001"

@app.route("/")
def hello_world():
   return "<p>Hello World!</p>"

if __name__ == '__main__':
    app.run(debug=True)

