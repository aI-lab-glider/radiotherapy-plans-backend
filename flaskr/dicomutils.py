#!/usr/bin/env python

class InvalidDicomName(Exception):
    """Exception raised when a file name doesn't indicate 
    that it's a dicom file.

    Arttibutes:
        filename - the full name of the file (with extension)
        message - additional info
    """

    def __init__(self, filename: str, message: str):
        self.filename = filename
        self.message = message

