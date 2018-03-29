# ================================================================================
#     ObjectStorageUploader.py
#     © Copyright IBM Corporation 2014.
#     LICENSE: MIT (http://opensource.org/licenses/MIT)    
# ================================================================================

import argparse
import os
import math
import http.client
from urllib.parse import urlparse
from urllib.parse import quote


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-f", "--file", help="file to upload to SWIFT")
    parser.add_argument("-u", "--username", help="SWIFT username")
    parser.add_argument("-p", "--password", help="SWIFT password (SoftLayer API key)")
    parser.add_argument("-c", "--cluster", help="SWIFT cluster to use (default: dal05.objectstorage.softlayer.net)")
    parser.add_argument("-t", "--target", help="location on SWIFT cluster to store file (container/filename.vhd)")
    args = parser.parse_args()

    if not args.file:
        filename = select_file()
    else:
        filename = args.file

    if not args.username:
        swift_user_name, swift_password = get_swift_credentials()
    else:
        swift_user_name = args.username
        swift_password = args.password

    if not args.cluster:
        storage_url, auth_token = authenticate_swift(
            swift_user_name,
            swift_password,
            "dal05.objectstorage.softlayer.net"
        )
    else:
        storage_url, auth_token = authenticate_swift(
            swift_user_name,
            swift_password,
            args.cluster
        )

    if not args.target:
        container = select_container(storage_url, auth_token)
        swift_target_path = "{}/{}".format(container, quote(filename))
    else:
        swift_target_path = args.target

    upload_file(filename, swift_target_path, storage_url, auth_token)


def select_file():
    current_path = (os.path.dirname(os.path.realpath(__file__)))
    print("Files in {}".format(current_path))
    files = get_file_list(current_path)
    return prompt_for_choice(files, "Select file for upload:")


def get_file_list(path):
    files = []
    for file in os.listdir(path):
        if os.path.isfile(file):
            files.append(file)
    return files


def prompt_for_choice(list, prompt_label):
    for i, item in enumerate(list):
        if len(item):
            print("{}) {}".format(i, item))
    selected_index = input(prompt_label)
    if selected_index.isdigit():
        if 0 <= int(selected_index) < len(list):
            print()
            return list[int(selected_index)]

    print("Invalid Input: {}".format(selected_index))
    return prompt_for_choice(list, prompt_label)


def get_swift_credentials():
    swift_user_name = input("Swift Username:")
    swift_password = input("Swift Password:")
    return swift_user_name, swift_password


def authenticate_swift(swift_user_name, swift_password, selected_endpoint=""):
    if selected_endpoint == "":
        swift_endpoints = [
            "dal05.objectstorage.softlayer.net",
            "sng01.objectstorage.softlayer.net",
            "ams01.objectstorage.softlayer.net",
        ]
        selected_endpoint = prompt_for_choice(
            swift_endpoints,
            "Select Object Storage Endpoint:"
        )

    print("Authenticating...")
    headers = {
        "X-Storage-User": swift_user_name,
        "X-Storage-Pass": swift_password
    }
    try:
        response = object_storage_request(
            selected_endpoint,
            "/auth/v1.0/",
            headers
        )
    except Exception:
        swift_user_name, swift_password = get_swift_credentials()
        return authenticate_swift(swift_user_name, swift_password)
    print("Success!")

    storage_url = response.getheader("X-Storage-Url")
    auth_token = response.getheader("X-Auth-Token")

    return storage_url, auth_token


def select_container(storage_url, auth_token):
    url_tuple = urlparse(storage_url)

    headers = {"X-Auth-Token": auth_token}
    try:
        response = object_storage_request(
            url_tuple.netloc,
            url_tuple.path,
            headers
        )
    except Exception:
        swift_user_name, swift_password = get_swift_credentials()
        storage_url, auth_token = authenticate_swift(swift_user_name, swift_password)
        return select_container(storage_url, auth_token)

    containers = response.read().decode("utf-8").split("\n")
    return prompt_for_choice(containers, "Select Container:")


def object_storage_request(server, path, headers, method="GET", data=""):
    connection = http.client.HTTPConnection(server)
    connection.request(method, path, data, headers)
    response = connection.getresponse()

    if 200 <= response.getcode() < 300:
        return response

    print("Error {}: {}".format(response.status, response.reason))
    raise Exception(response.status, response.reason)


def upload_file(filename, swift_target_path, storage_url, auth_token):
    url_tuple = urlparse(storage_url)
    headers = {"X-Auth-Token": auth_token}

    file_size = os.path.getsize(filename)
    block_size = 1048576
    chunk_size = 5 * block_size
    chunks = math.ceil(file_size / chunk_size)

    print("Reading in file")
    file = open(filename, 'rb')
    print("Uploading {} to \"{}\"".format(filename, swift_target_path))
    for i in range(0, chunks):
        data = file.read(chunk_size)
        print("Uploading part {} of {}".format(i + 1, chunks))
        chunk_name = "chunk-{0:0>5}".format(i)
        object_storage_request(
            url_tuple.netloc,
            "{}/{}/{}".format(url_tuple.path, swift_target_path, chunk_name),
            headers,
            "PUT",
            data
        )

    try:
        print("Writing manifest file")
        headers = {
            "X-Auth-Token": auth_token,
            "X-Object-Manifest": swift_target_path,
            "Content-Length": 0,
        }
        object_storage_request(
            url_tuple.netloc,
            "{}/{}".format(url_tuple.path, swift_target_path),
            headers,
            "PUT"
        )
    except Exception:
        return

    print("File Uploaded!")

if __name__ == "__main__":
    main()


