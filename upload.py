#!/usr/bin/env python3

import boto3
import sys

KEY, SECRET, ENDPOINT, BUCKET, FILEPATH, FILENAME = [sys.argv[i+1] for i in range(6)]

session = boto3.session.Session()
client = session.client('s3',
                        region_name='nyc3',
                        endpoint_url='https://' + ENDPOINT,
                        aws_access_key_id = KEY,
                        aws_secret_access_key = SECRET)

client.upload_file(FILEPATH, # Path to local file
                   BUCKET,   # Name of Space
                   FILENAME, # Name for remote file
                   ExtraArgs={'ACL':'private'})
