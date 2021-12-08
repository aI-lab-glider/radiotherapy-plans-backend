FROM python:3.8

WORKDIR /flaskr

COPY requirements.txt .

RUN python3 -m pip install -r requirements.txt

COPY . .

EXPOSE 5000

CMD ["python3", "app.py"]
