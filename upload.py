#!/usr/bin/env python3

import boto3
import sys

KEY = sys.argv[1]
SECRET = sys.argv[2]
ENDPOINT = sys.argv[3]
BUCKET = sys.argv[4]
FILEPATH = sys.argv[5]
FILENAME = sys.argv[6]


session = boto3.session.Session()
client = session.client('s3',
                        region_name='nyc3',
                        endpoint_url='https://' + ENDPOINT,
                        aws_access_key_id = KEY,
                        aws_secret_access_key = SECRET)

client.upload_file(FILEPATH, # Path to local file
                   BUCKET,   # Name of Space
                   FILENAME, # Name for remote file
                   ExtraArgs={'ACL':'public-read'})

